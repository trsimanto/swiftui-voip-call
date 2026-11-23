import Foundation

/// A user or system intent the provider asks us to carry out.
///
/// Mirrors `CXCallAction`: whoever handles it must call `fulfill()` or `fail()`
/// exactly once, otherwise CallKit will time the action out.
public struct ProviderAction: Sendable {
    public enum Kind: Equatable, Sendable {
        case start(handle: String)
        case answer
        case end
        case setHeld(Bool)
        case setMuted(Bool)
        case playDTMF(String)
    }

    public let callID: UUID
    public let kind: Kind
    private let completion: @Sendable (Bool) -> Void

    public init(callID: UUID, kind: Kind, completion: @escaping @Sendable (Bool) -> Void = { _ in }) {
        self.callID = callID
        self.kind = kind
        self.completion = completion
    }

    public func fulfill() { completion(true) }
    public func fail() { completion(false) }
}

public enum CallProviderEvent: Sendable {
    case perform(ProviderAction)
    case audioSessionActivated
    case audioSessionDeactivated
    /// The provider dropped all calls (e.g. the CallKit daemon restarted).
    case reset
}

/// The OS-facing side of a call: system call UI, lock screen, Bluetooth
/// buttons, CarPlay. On device this is CallKit; in tests and in the simulator
/// it is a loopback that immediately echoes requests back as actions.
///
/// Requests flow *out* through the `request*` methods, and the provider calls
/// back through `events`. `CallManager` only mutates call state in response to
/// those events, so a hang-up from the lock screen and one from our own UI take
/// exactly the same path.
@MainActor
public protocol CallProvider: AnyObject {
    var events: AsyncStream<CallProviderEvent> { get }

    func reportIncomingCall(id: UUID, handle: String, displayName: String?) async throws
    func requestStartCall(id: UUID, handle: String, displayName: String?) async throws
    func requestAnswer(id: UUID) async throws
    func requestEnd(id: UUID) async throws
    func requestSetHeld(_ onHold: Bool, id: UUID) async throws
    func requestSetMuted(_ muted: Bool, id: UUID) async throws
    func requestPlayDTMF(_ digits: String, id: UUID) async throws

    func reportOutgoingCallStartedConnecting(id: UUID)
    func reportOutgoingCallConnected(id: UUID)
    func reportCallEnded(id: UUID, reason: CallEndReason)
}
