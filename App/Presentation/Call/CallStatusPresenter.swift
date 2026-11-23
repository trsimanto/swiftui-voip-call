import CallCore
import Foundation

/// Pure formatting for the call screen, kept out of the views so it can be
/// unit tested.
enum CallStatusPresenter {
    static func statusText(for call: Call, now: Date) -> String {
        let clock = CallDurationFormatter.clockString(from: call.duration(at: now))

        switch call.state {
        case .idle, .dialing:
            return "Calling…"
        case .ringing:
            return call.direction == .incoming ? "Incoming VoIP call" : "Ringing…"
        case .connecting:
            return "Connecting…"
        case .active:
            return clock
        case .held:
            return "On hold · \(clock)"
        case let .ended(reason):
            if reason == .completed, call.connectedAt != nil {
                return "Call ended · \(clock)"
            }
            return reason.localizedDescription
        }
    }

    /// The timer only needs to tick while there is talk time to show.
    static func needsLiveTimer(_ call: Call) -> Bool {
        call.state == .active || call.state == .held
    }

    static func controlsEnabled(for call: Call) -> (mute: Bool, keypad: Bool, speaker: Bool, hold: Bool) {
        let inProgress = call.state.isInProgress
        return (
            mute: inProgress,
            keypad: call.state == .active,
            speaker: inProgress,
            hold: call.state == .active || call.state == .held
        )
    }
}
