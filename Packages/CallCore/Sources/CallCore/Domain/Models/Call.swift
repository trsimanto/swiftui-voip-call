import Foundation

public enum CallDirection: String, Codable, Hashable, Sendable {
    case incoming
    case outgoing
}

/// Snapshot of the call currently owned by `CallManager`.
public struct Call: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let handle: String
    public var displayName: String
    public let direction: CallDirection
    public var state: CallState
    public let createdAt: Date
    public var connectedAt: Date?
    public var endedAt: Date?
    public var isMuted: Bool
    public var isSpeakerOn: Bool
    public var quality: CallQuality?
    /// Digits sent over DTMF during this call, in order.
    public var dtmfDigits: String

    public init(
        id: UUID = UUID(),
        handle: String,
        displayName: String? = nil,
        direction: CallDirection,
        state: CallState,
        createdAt: Date,
        connectedAt: Date? = nil,
        endedAt: Date? = nil,
        isMuted: Bool = false,
        isSpeakerOn: Bool = false,
        quality: CallQuality? = nil,
        dtmfDigits: String = ""
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName ?? handle
        self.direction = direction
        self.state = state
        self.createdAt = createdAt
        self.connectedAt = connectedAt
        self.endedAt = endedAt
        self.isMuted = isMuted
        self.isSpeakerOn = isSpeakerOn
        self.quality = quality
        self.dtmfDigits = dtmfDigits
    }

    public var isOnHold: Bool { state == .held }

    /// Talk time. Zero until media connects; frozen once the call ends.
    public func duration(at now: Date) -> TimeInterval {
        guard let connectedAt else { return 0 }
        let end = endedAt ?? now
        return max(0, end.timeIntervalSince(connectedAt))
    }
}
