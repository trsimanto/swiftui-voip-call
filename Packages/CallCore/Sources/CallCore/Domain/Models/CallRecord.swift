import Foundation

/// A finished call as it appears in Recents.
public struct CallRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let handle: String
    public let displayName: String
    public let direction: CallDirection
    public let endReason: CallEndReason
    public let startedAt: Date
    public let duration: TimeInterval

    public init(
        id: UUID,
        handle: String,
        displayName: String,
        direction: CallDirection,
        endReason: CallEndReason,
        startedAt: Date,
        duration: TimeInterval
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.direction = direction
        self.endReason = endReason
        self.startedAt = startedAt
        self.duration = duration
    }

    public init(call: Call, endReason: CallEndReason, endedAt: Date) {
        self.init(
            id: call.id,
            handle: call.handle,
            displayName: call.displayName,
            direction: call.direction,
            endReason: endReason,
            startedAt: call.createdAt,
            duration: call.duration(at: endedAt)
        )
    }

    public var isMissed: Bool {
        direction == .incoming && endReason == .missed
    }

    /// Whether the two parties actually talked.
    public var wasConnected: Bool {
        duration > 0
    }
}
