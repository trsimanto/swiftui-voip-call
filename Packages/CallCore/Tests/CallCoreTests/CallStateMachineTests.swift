import XCTest
@testable import CallCore

final class CallStateMachineTests: XCTestCase {

    // MARK: - Happy paths

    func testOutgoingCallFullLifecycle() throws {
        var machine = CallStateMachine()

        XCTAssertEqual(try machine.handle(.dial), .dialing)
        XCTAssertEqual(try machine.handle(.remoteRinging), .ringing)
        XCTAssertEqual(try machine.handle(.answer), .connecting)
        XCTAssertEqual(try machine.handle(.mediaConnected), .active)
        XCTAssertEqual(try machine.handle(.end(.completed)), .ended(.completed))

        XCTAssertEqual(machine.history, [.idle, .dialing, .ringing, .connecting, .active, .ended(.completed)])
    }

    func testIncomingCallFullLifecycle() throws {
        var machine = CallStateMachine()

        try machine.handle(.incoming)
        XCTAssertEqual(machine.state, .ringing)
        try machine.handle(.answer)
        try machine.handle(.mediaConnected)
        XCTAssertEqual(machine.state, .active)
    }

    func testHoldAndResumeCanRepeat() throws {
        var machine = try activeMachine()

        for _ in 0..<3 {
            XCTAssertEqual(try machine.handle(.hold), .held)
            XCTAssertEqual(try machine.handle(.resume), .active)
        }
    }

    func testEndIsAllowedFromEveryInProgressState() throws {
        let inProgress: [CallState] = [.dialing, .ringing, .connecting, .active, .held]
        for state in inProgress {
            var machine = CallStateMachine(initialState: state)
            XCTAssertEqual(try machine.handle(.end(.failed)), .ended(.failed), "end should be valid from \(state)")
        }
    }

    func testEndPreservesReason() throws {
        for reason in CallEndReason.allCases {
            var machine = CallStateMachine(initialState: .ringing)
            try machine.handle(.end(reason))
            XCTAssertEqual(machine.state.endReason, reason)
        }
    }

    // MARK: - Invalid transitions

    func testInvalidTransitionsAreRejected() {
        let invalid: [(CallState, CallEvent)] = [
            (.idle, .answer),
            (.idle, .remoteRinging),
            (.idle, .mediaConnected),
            (.idle, .hold),
            (.idle, .end(.completed)),
            (.dialing, .dial),
            (.dialing, .answer),          // must ring first
            (.dialing, .mediaConnected),
            (.dialing, .hold),
            (.ringing, .remoteRinging),
            (.ringing, .mediaConnected),
            (.ringing, .hold),
            (.connecting, .hold),
            (.connecting, .answer),
            (.active, .dial),
            (.active, .incoming),
            (.active, .answer),
            (.active, .resume),
            (.held, .hold),
            (.held, .mediaConnected),
            (.ended(.completed), .dial),
            (.ended(.completed), .incoming),
            (.ended(.completed), .end(.failed)),
            (.ended(.missed), .answer)
        ]

        for (state, event) in invalid {
            var machine = CallStateMachine(initialState: state)
            XCTAssertThrowsError(try machine.handle(event), "\(event) from \(state) should be rejected") { error in
                XCTAssertEqual(error as? InvalidCallTransition, InvalidCallTransition(from: state, event: event))
            }
            XCTAssertEqual(machine.state, state, "state must not change after a rejected event")
            XCTAssertEqual(machine.history, [state])
        }
    }

    func testCanHandleMatchesTransitionTable() throws {
        let machine = try activeMachine()
        XCTAssertTrue(machine.canHandle(.hold))
        XCTAssertTrue(machine.canHandle(.end(.completed)))
        XCTAssertFalse(machine.canHandle(.resume))
        XCTAssertFalse(machine.canHandle(.dial))
    }

    func testInvalidTransitionDescriptionIsReadable() {
        let error = InvalidCallTransition(from: .ringing, event: .hold)
        XCTAssertEqual(error.description, "Invalid call transition: hold is not allowed while ringing")
    }

    // MARK: - State helpers

    func testStateFlags() {
        XCTAssertFalse(CallState.idle.isInProgress)
        XCTAssertTrue(CallState.dialing.isInProgress)
        XCTAssertFalse(CallState.dialing.isLive)
        XCTAssertTrue(CallState.connecting.isLive)
        XCTAssertTrue(CallState.held.isLive)
        XCTAssertTrue(CallState.ended(.busy).isTerminal)
        XCTAssertFalse(CallState.ended(.busy).isInProgress)
        XCTAssertNil(CallState.active.endReason)
    }

    private func activeMachine() throws -> CallStateMachine {
        var machine = CallStateMachine()
        try machine.handle(.dial)
        try machine.handle(.remoteRinging)
        try machine.handle(.answer)
        try machine.handle(.mediaConnected)
        return machine
    }
}
