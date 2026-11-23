import Foundation

public struct InvalidCallTransition: Error, Equatable, Sendable, CustomStringConvertible {
    public let from: CallState
    public let event: CallEvent

    public init(from: CallState, event: CallEvent) {
        self.from = from
        self.event = event
    }

    public var description: String {
        "Invalid call transition: \(event) is not allowed while \(from)"
    }
}

/// Pure, value-type state machine for one call.
///
/// All transition rules live in `nextState(from:on:)` so they can be reasoned
/// about (and tested) in one place. Anything not listed there is rejected,
/// which is what keeps late or duplicated signaling messages from corrupting
/// the UI state.
public struct CallStateMachine: Sendable {
    public private(set) var state: CallState
    /// Every state the call has been in, oldest first. Handy for diagnostics.
    public private(set) var history: [CallState]

    public init(initialState: CallState = .idle) {
        self.state = initialState
        self.history = [initialState]
    }

    public static func nextState(from state: CallState, on event: CallEvent) -> CallState? {
        switch (state, event) {
        case (.idle, .dial):
            return .dialing
        case (.idle, .incoming):
            return .ringing
        case (.dialing, .remoteRinging):
            return .ringing
        case (.ringing, .answer):
            return .connecting
        case (.connecting, .mediaConnected):
            return .active
        case (.active, .hold):
            return .held
        case (.held, .resume):
            return .active
        case let (current, .end(reason)) where current.isInProgress:
            return .ended(reason)
        default:
            return nil
        }
    }

    public func canHandle(_ event: CallEvent) -> Bool {
        Self.nextState(from: state, on: event) != nil
    }

    @discardableResult
    public mutating func handle(_ event: CallEvent) throws -> CallState {
        guard let next = Self.nextState(from: state, on: event) else {
            throw InvalidCallTransition(from: state, event: event)
        }
        state = next
        history.append(next)
        return next
    }
}
