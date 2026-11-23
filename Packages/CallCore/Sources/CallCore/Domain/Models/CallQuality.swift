import Foundation

/// Raw network stats as reported by the media stack (RTCP / WebRTC getStats).
public struct CallMetrics: Equatable, Hashable, Sendable {
    public var roundTripTimeMs: Double
    public var jitterMs: Double
    public var packetLossPercent: Double

    public init(roundTripTimeMs: Double, jitterMs: Double, packetLossPercent: Double) {
        self.roundTripTimeMs = roundTripTimeMs
        self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent
    }
}

public enum CallQuality: Int, Comparable, CaseIterable, Sendable {
    case poor = 1
    case fair
    case good
    case excellent

    /// Buckets a simplified ITU-T G.107 E-model MOS estimate.
    /// Not a substitute for a real MOS calculation, but it tracks user
    /// perception well enough to drive a signal-bars indicator.
    public init(metrics: CallMetrics) {
        let mos = Self.estimatedMOS(for: metrics)
        switch mos {
        case 4.2...: self = .excellent
        case 3.6..<4.2: self = .good
        case 3.1..<3.6: self = .fair
        default: self = .poor
        }
    }

    public static func estimatedMOS(for metrics: CallMetrics) -> Double {
        // Jitter is weighted double because the jitter buffer turns it into delay.
        let effectiveLatency = metrics.roundTripTimeMs / 2 + metrics.jitterMs * 2 + 10
        var rFactor = 93.2
        if effectiveLatency < 160 {
            rFactor -= effectiveLatency / 40
        } else {
            rFactor -= (effectiveLatency - 120) / 10
        }
        rFactor -= metrics.packetLossPercent * 4

        if rFactor <= 0 { return 1 }
        if rFactor >= 100 { return 4.5 }
        return 1 + 0.035 * rFactor + 0.000007 * rFactor * (rFactor - 60) * (100 - rFactor)
    }

    /// Number of filled bars out of four.
    public var bars: Int { rawValue }

    public var label: String {
        switch self {
        case .poor: return "Poor connection"
        case .fair: return "Fair connection"
        case .good: return "Good connection"
        case .excellent: return "Excellent connection"
        }
    }

    public static func < (lhs: CallQuality, rhs: CallQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
