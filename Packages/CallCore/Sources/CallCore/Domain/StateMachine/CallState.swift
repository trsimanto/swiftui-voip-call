import Foundation

/// Lifecycle of a single call.
///
/// Outgoing: idle -> dialing -> ringing -> connecting -> active <-> held -> ended
/// Incoming: idle -> ringing -> connecting -> active <-> held -> ended
public enum CallState: Equatable, Hashable, Sendable {
    case idle
    case dialing
    case ringing
    case connecting
    case active
    case held
    case ended(CallEndReason)

    /// True once media is (or is about to be) flowing.
    public var isLive: Bool {
        switch self {
        case .connecting, .active, .held: return true
        default: return false
        }
    }

    public var isTerminal: Bool {
        if case .ended = self { return true }
        return false
    }

    /// A call that exists and hasn't finished yet.
    public var isInProgress: Bool {
        self != .idle && !isTerminal
    }

    public var endReason: CallEndReason? {
        if case let .ended(reason) = self { return reason }
        return nil
    }
}

extension CallState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .dialing: return "dialing"
        case .ringing: return "ringing"
        case .connecting: return "connecting"
        case .active: return "active"
        case .held: return "held"
        case let .ended(reason): return "ended(\(reason.rawValue))"
        }
    }
}
