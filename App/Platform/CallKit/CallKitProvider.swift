import AVFoundation
import CallKit
import CallCore
import os

/// `CallProvider` backed by CallKit.
///
/// Outgoing requests become `CXTransaction`s on a `CXCallController`; the
/// system then calls back into `CXProviderDelegate`, which we forward as
/// `CallProviderEvent`s. This indirection is what gives us lock-screen,
/// Bluetooth headset and CarPlay control for free: those buttons produce the
/// same delegate callbacks as our own UI does.
@MainActor
final class CallKitProvider: CallProvider {
    let events: AsyncStream<CallProviderEvent>

    private let provider: CXProvider
    private let controller = CXCallController()
    private let delegateProxy: ProviderDelegateProxy
    private let logger = Logger(subsystem: "dev.towhid.voipcall", category: "CallKit")

    init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber, .generic]
        configuration.includesCallsInRecents = true

        provider = CXProvider(configuration: configuration)

        let (stream, continuation) = AsyncStream.makeStream(of: CallProviderEvent.self)
        events = stream
        delegateProxy = ProviderDelegateProxy(continuation: continuation)
        // nil queue = main queue, which matches CallManager's isolation.
        provider.setDelegate(delegateProxy, queue: nil)
    }

    // MARK: - Reporting

    func reportIncomingCall(id: UUID, handle: String, displayName: String?) async throws {
        let update = makeUpdate(handle: handle, displayName: displayName)
        try await provider.reportNewIncomingCall(with: id, update: update)
        logger.info("Reported incoming call \(id, privacy: .public)")
    }

    func reportOutgoingCallStartedConnecting(id: UUID) {
        provider.reportOutgoingCall(with: id, startedConnectingAt: nil)
    }

    func reportOutgoingCallConnected(id: UUID) {
        provider.reportOutgoingCall(with: id, connectedAt: nil)
    }

    func reportCallEnded(id: UUID, reason: CallEndReason) {
        provider.reportCall(with: id, endedAt: nil, reason: Self.cxReason(for: reason))
    }

    // MARK: - Requests

    func requestStartCall(id: UUID, handle: String, displayName: String?) async throws {
        let action = CXStartCallAction(call: id, handle: CXHandle(type: .phoneNumber, value: handle))
        try await request(action)
        // Without this the system UI would only ever show the raw number.
        provider.reportCall(with: id, updated: makeUpdate(handle: handle, displayName: displayName))
    }

    func requestAnswer(id: UUID) async throws {
        try await request(CXAnswerCallAction(call: id))
    }

    func requestEnd(id: UUID) async throws {
        try await request(CXEndCallAction(call: id))
    }

    func requestSetHeld(_ onHold: Bool, id: UUID) async throws {
        try await request(CXSetHeldCallAction(call: id, onHold: onHold))
    }

    func requestSetMuted(_ muted: Bool, id: UUID) async throws {
        try await request(CXSetMutedCallAction(call: id, muted: muted))
    }

    func requestPlayDTMF(_ digits: String, id: UUID) async throws {
        try await request(CXPlayDTMFCallAction(call: id, digits: digits, type: .singleTone))
    }

    // MARK: - Private

    private func request(_ action: CXCallAction) async throws {
        do {
            try await controller.request(CXTransaction(action: action))
        } catch {
            logger.error("CallKit rejected \(String(describing: type(of: action)), privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func makeUpdate(handle: String, displayName: String?) -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: handle)
        update.localizedCallerName = displayName
        update.hasVideo = false
        update.supportsHolding = true
        update.supportsDTMF = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        return update
    }

    private static func cxReason(for reason: CallEndReason) -> CXCallEndedReason {
        switch reason {
        case .completed, .cancelled, .busy, .declined:
            return .remoteEnded
        case .missed, .unanswered:
            return .unanswered
        case .failed:
            return .failed
        }
    }
}

/// Receives `CXProviderDelegate` callbacks and turns them into events.
///
/// Kept separate from `CallKitProvider` so the delegate methods don't need to
/// be main-actor isolated: they only touch the continuation, which is Sendable.
private final class ProviderDelegateProxy: NSObject, CXProviderDelegate {
    private let continuation: AsyncStream<CallProviderEvent>.Continuation

    init(continuation: AsyncStream<CallProviderEvent>.Continuation) {
        self.continuation = continuation
    }

    func providerDidReset(_ provider: CXProvider) {
        continuation.yield(.reset)
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        forward(action, as: .start(handle: action.handle.value))
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        forward(action, as: .answer)
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        forward(action, as: .end)
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        forward(action, as: .setHeld(action.isOnHold))
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        forward(action, as: .setMuted(action.isMuted))
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        forward(action, as: .playDTMF(action.digits))
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        action.fail()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        continuation.yield(.audioSessionActivated)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        continuation.yield(.audioSessionDeactivated)
    }

    private func forward(_ action: CXCallAction, as kind: ProviderAction.Kind) {
        let providerAction = ProviderAction(callID: action.callUUID, kind: kind) { success in
            if success {
                action.fulfill()
            } else {
                action.fail()
            }
        }
        continuation.yield(.perform(providerAction))
    }
}
