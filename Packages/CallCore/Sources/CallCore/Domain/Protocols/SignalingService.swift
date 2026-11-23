import Foundation

/// Messages coming *from* the signaling server.
public enum SignalingEvent: Equatable, Sendable {
    case registered
    case incomingCall(id: UUID, handle: String, displayName: String?)
    case remoteRinging(id: UUID)
    case remoteAnswered(id: UUID)
    case mediaConnected(id: UUID)
    case remoteEnded(id: UUID, reason: CallEndReason)
    case qualityChanged(id: UUID, metrics: CallMetrics)
}

public enum SignalingError: Error, Equatable, Sendable {
    case notRegistered
    case unknownCall
    case networkUnavailable
    case timeout
}

/// Abstraction over the SIP / WebRTC signaling channel.
///
/// The real implementation would sit on a WebSocket (or a SIP stack) and
/// translate wire messages into `SignalingEvent`s. The app only ever talks to
/// this protocol, so swapping the mock for a production client is a DI change.
public protocol SignalingService: AnyObject, Sendable {
    /// Single-consumer stream; `CallManager` is the only subscriber.
    var events: AsyncStream<SignalingEvent> { get }

    func register() async throws
    func placeCall(id: UUID, to handle: String) async throws
    func answer(id: UUID) async throws
    func reject(id: UUID, reason: CallEndReason) async
    func hangUp(id: UUID) async
    func setHold(_ onHold: Bool, id: UUID) async throws
    func sendDTMF(_ digits: String, id: UUID) async
}

/// Lets the demo UI trigger an inbound call without a server.
public protocol IncomingCallSimulating: AnyObject, Sendable {
    func simulateIncomingCall(from handle: String, displayName: String?, after delay: Duration) async
}
