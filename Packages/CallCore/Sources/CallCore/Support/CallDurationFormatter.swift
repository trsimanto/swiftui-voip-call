import Foundation

public enum CallDurationFormatter {
    /// In-call timer style: "0:07", "12:45", "1:02:03".
    public static func clockString(from interval: TimeInterval) -> String {
        let total = wholeSeconds(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }
        return "\(minutes):\(twoDigits(seconds))"
    }

    /// Compact style for Recents: "45s", "2m 05s", "1h 02m".
    public static func compactString(from interval: TimeInterval) -> String {
        let total = wholeSeconds(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return "\(hours)h \(twoDigits(minutes))m"
        }
        if minutes > 0 {
            return "\(minutes)m \(twoDigits(seconds))s"
        }
        return "\(seconds)s"
    }

    private static func wholeSeconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite, interval > 0 else { return 0 }
        // Cap absurd values instead of trapping on Int conversion.
        return Int(min(interval, 359_999).rounded(.down))
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
