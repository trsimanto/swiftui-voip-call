import Foundation

/// Inputs that drive `CallStateMachine`. Events are deliberately transport
/// agnostic: both SIP and WebRTC-style signaling map onto the same set.
public enum CallEvent: Equatable, Hashable, Sendable {
    /// Local user starts an outgoing call.
    case dial
    /// Signaling delivered an incoming INVITE / offer.
    case incoming
    /// Remote side is alerting (SIP 180 Ringing).
    case remoteRinging
    /// Call was accepted, locally for incoming or remotely for outgoing (200 OK).
    case answer
    /// ICE / RTP is up and audio is flowing.
    case mediaConnected
    case hold
    case resume
    case end(CallEndReason)
}

extension CallEvent: CustomStringConvertible {
    public var description: String {
        switch self {
        case .dial: return "dial"
        case .incoming: return "incoming"
        case .remoteRinging: return "remoteRinging"
        case .answer: return "answer"
        case .mediaConnected: return "mediaConnected"
        case .hold: return "hold"
        case .resume: return "resume"
        case let .end(reason): return "end(\(reason.rawValue))"
        }
    }
}
