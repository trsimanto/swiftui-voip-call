import Foundation

/// `CallProvider` that behaves like CallKit with the system UI taken out:
/// every request is immediately handed back as an action.
///
/// Used in the simulator (where CallKit's outgoing call support is patchy) and
/// as the default provider in tests.
@MainActor
public final class LoopbackCallProvider: CallProvider {
    public let events: AsyncStream<CallProviderEvent>
    private let continuation: AsyncStream<CallProviderEvent>.Continuation

    public private(set) var reportedIncomingCalls: [UUID] = []
    public private(set) var reportedConnecting: [UUID] = []
    public private(set) var reportedConnected: [UUID] = []
    public private(set) var reportedEnded: [(id: UUID, reason: CallEndReason)] = []

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: CallProviderEvent.self)
        self.events = stream
        self.continuation = continuation
    }

    public func reportIncomingCall(id: UUID, handle: String, displayName: String?) async throws {
        reportedIncomingCalls.append(id)
    }

    public func requestStartCall(id: UUID, handle: String, displayName: String?) async throws {
        perform(.start(handle: handle), for: id)
        continuation.yield(.audioSessionActivated)
    }

    public func requestAnswer(id: UUID) async throws {
        perform(.answer, for: id)
        continuation.yield(.audioSessionActivated)
    }

    public func requestEnd(id: UUID) async throws {
        perform(.end, for: id)
        continuation.yield(.audioSessionDeactivated)
    }

    public func requestSetHeld(_ onHold: Bool, id: UUID) async throws {
        perform(.setHeld(onHold), for: id)
    }

    public func requestSetMuted(_ muted: Bool, id: UUID) async throws {
        perform(.setMuted(muted), for: id)
    }

    public func requestPlayDTMF(_ digits: String, id: UUID) async throws {
        perform(.playDTMF(digits), for: id)
    }

    public func reportOutgoingCallStartedConnecting(id: UUID) {
        reportedConnecting.append(id)
    }

    public func reportOutgoingCallConnected(id: UUID) {
        reportedConnected.append(id)
    }

    public func reportCallEnded(id: UUID, reason: CallEndReason) {
        reportedEnded.append((id, reason))
        continuation.yield(.audioSessionDeactivated)
    }

    private func perform(_ kind: ProviderAction.Kind, for id: UUID) {
        continuation.yield(.perform(ProviderAction(callID: id, kind: kind)))
    }
}
