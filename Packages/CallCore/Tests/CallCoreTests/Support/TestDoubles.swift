import Foundation
import XCTest
@testable import CallCore

/// Signaling double that records outbound calls and lets the test play the
/// server side by emitting events by hand.
actor StubSignalingService: SignalingService {
    nonisolated let events: AsyncStream<SignalingEvent>
    private nonisolated let continuation: AsyncStream<SignalingEvent>.Continuation

    private(set) var registerCount = 0
    private(set) var placedCalls: [(id: UUID, handle: String)] = []
    private(set) var answeredCalls: [UUID] = []
    private(set) var rejectedCalls: [(id: UUID, reason: CallEndReason)] = []
    private(set) var hungUpCalls: [UUID] = []
    private(set) var holdRequests: [(id: UUID, onHold: Bool)] = []
    private(set) var dtmf: [String] = []

    private var placeCallError: SignalingError?
    private var holdError: SignalingError?

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: SignalingEvent.self)
        events = stream
        self.continuation = continuation
    }

    nonisolated func emit(_ event: SignalingEvent) {
        continuation.yield(event)
    }

    func failPlaceCall(with error: SignalingError) { placeCallError = error }
    func failHold(with error: SignalingError) { holdError = error }

    func register() async throws { registerCount += 1 }

    func placeCall(id: UUID, to handle: String) async throws {
        if let placeCallError { throw placeCallError }
        placedCalls.append((id, handle))
    }

    func answer(id: UUID) async throws { answeredCalls.append(id) }
    func reject(id: UUID, reason: CallEndReason) async { rejectedCalls.append((id, reason)) }
    func hangUp(id: UUID) async { hungUpCalls.append(id) }

    func setHold(_ onHold: Bool, id: UUID) async throws {
        if let holdError { throw holdError }
        holdRequests.append((id, onHold))
    }

    func sendDTMF(_ digits: String, id: UUID) async { dtmf.append(digits) }
}

/// Provider that fails requests on demand; otherwise behaves like the loopback.
@MainActor
final class ControllableCallProvider: CallProvider {
    struct RequestFailed: Error {}

    private let loopback = LoopbackCallProvider()
    var events: AsyncStream<CallProviderEvent> { loopback.events }

    var failStartCall = false
    var failIncomingReport = false

    var reportedIncomingCalls: [UUID] { loopback.reportedIncomingCalls }
    var reportedConnecting: [UUID] { loopback.reportedConnecting }
    var reportedConnected: [UUID] { loopback.reportedConnected }
    var reportedEnded: [(id: UUID, reason: CallEndReason)] { loopback.reportedEnded }

    func reportIncomingCall(id: UUID, handle: String, displayName: String?) async throws {
        if failIncomingReport { throw RequestFailed() }
        try await loopback.reportIncomingCall(id: id, handle: handle, displayName: displayName)
    }

    func requestStartCall(id: UUID, handle: String, displayName: String?) async throws {
        if failStartCall { throw RequestFailed() }
        try await loopback.requestStartCall(id: id, handle: handle, displayName: displayName)
    }

    func requestAnswer(id: UUID) async throws { try await loopback.requestAnswer(id: id) }
    func requestEnd(id: UUID) async throws { try await loopback.requestEnd(id: id) }
    func requestSetHeld(_ onHold: Bool, id: UUID) async throws { try await loopback.requestSetHeld(onHold, id: id) }
    func requestSetMuted(_ muted: Bool, id: UUID) async throws { try await loopback.requestSetMuted(muted, id: id) }
    func requestPlayDTMF(_ digits: String, id: UUID) async throws { try await loopback.requestPlayDTMF(digits, id: id) }

    func reportOutgoingCallStartedConnecting(id: UUID) { loopback.reportOutgoingCallStartedConnecting(id: id) }
    func reportOutgoingCallConnected(id: UUID) { loopback.reportOutgoingCallConnected(id: id) }
    func reportCallEnded(id: UUID, reason: CallEndReason) { loopback.reportCallEnded(id: id, reason: reason) }
}

@MainActor
final class SpyAudioRouting: AudioRouting {
    struct RouteError: Error {}

    private(set) var configureCount = 0
    private(set) var speakerEnabled = false
    private(set) var activations = 0
    private(set) var deactivations = 0
    var failSpeaker = false

    func configureForVoiceCall() throws { configureCount += 1 }

    func setSpeakerEnabled(_ enabled: Bool) throws {
        if failSpeaker { throw RouteError() }
        speakerEnabled = enabled
    }

    func audioSessionDidActivate() { activations += 1 }
    func audioSessionDidDeactivate() { deactivations += 1 }
}

/// Polls until `condition` holds. Call flows hop across several tasks, so
/// waiting on an observable outcome is more robust than counting yields.
@MainActor
func waitUntil(
    _ description: String,
    timeout: TimeInterval = 2,
    file: StaticString = #filePath,
    line: UInt = #line,
    condition: () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !(await condition()) {
        if Date() > deadline {
            XCTFail("Timed out waiting for: \(description)", file: file, line: line)
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

/// Collects up to `count` events, giving up after `timeout`.
func collect(
    _ count: Int,
    from stream: AsyncStream<SignalingEvent>,
    timeout: Duration = .seconds(2)
) async -> [SignalingEvent] {
    await withTaskGroup(of: [SignalingEvent]?.self) { group in
        group.addTask {
            var received: [SignalingEvent] = []
            for await event in stream {
                received.append(event)
                if received.count == count { break }
            }
            return received
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first ?? []
    }
}
