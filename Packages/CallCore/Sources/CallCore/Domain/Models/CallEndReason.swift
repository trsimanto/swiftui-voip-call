import Foundation

public enum CallEndReason: String, Codable, CaseIterable, Hashable, Sendable {
    /// Connected call that one side hung up normally.
    case completed
    /// Caller hung up before the callee answered.
    case cancelled
    /// Callee rejected the call.
    case declined
    /// Incoming call that rang out or was withdrawn before we answered.
    case missed
    /// Callee was already on another call.
    case busy
    /// Nobody picked up before the ring timeout.
    case unanswered
    /// Network, signaling or media failure.
    case failed

    public var localizedDescription: String {
        switch self {
        case .completed: return "Call ended"
        case .cancelled: return "Cancelled"
        case .declined: return "Declined"
        case .missed: return "Missed"
        case .busy: return "Busy"
        case .unanswered: return "No answer"
        case .failed: return "Call failed"
        }
    }
}
