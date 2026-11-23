import CallCore
import XCTest
@testable import VoIPCall

final class CallStatusPresenterTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func call(_ state: CallState, direction: CallDirection = .outgoing, connectedAfter: TimeInterval? = nil) -> Call {
        Call(
            handle: "+1 555",
            displayName: "Ayesha",
            direction: direction,
            state: state,
            createdAt: start,
            connectedAt: connectedAfter.map { start.addingTimeInterval($0) }
        )
    }

    func testPreConnectStates() {
        XCTAssertEqual(CallStatusPresenter.statusText(for: call(.dialing), now: start), "Calling…")
        XCTAssertEqual(CallStatusPresenter.statusText(for: call(.ringing), now: start), "Ringing…")
        XCTAssertEqual(CallStatusPresenter.statusText(for: call(.ringing, direction: .incoming), now: start), "Incoming VoIP call")
        XCTAssertEqual(CallStatusPresenter.statusText(for: call(.connecting), now: start), "Connecting…")
    }

    func testActiveCallShowsTimer() {
        let active = call(.active, connectedAfter: 5)
        XCTAssertEqual(CallStatusPresenter.statusText(for: active, now: start.addingTimeInterval(70)), "1:05")
    }

    func testHeldCallKeepsTimer() {
        let held = call(.held, connectedAfter: 0)
        XCTAssertEqual(CallStatusPresenter.statusText(for: held, now: start.addingTimeInterval(9)), "On hold · 0:09")
    }

    func testEndedStates() {
        var ended = call(.ended(.completed), connectedAfter: 0)
        ended.endedAt = start.addingTimeInterval(42)
        XCTAssertEqual(CallStatusPresenter.statusText(for: ended, now: start.addingTimeInterval(500)), "Call ended · 0:42")

        XCTAssertEqual(CallStatusPresenter.statusText(for: call(.ended(.busy)), now: start), "Busy")
        XCTAssertEqual(CallStatusPresenter.statusText(for: call(.ended(.unanswered)), now: start), "No answer")
    }

    func testTimerOnlyRunsWhileConnected() {
        XCTAssertFalse(CallStatusPresenter.needsLiveTimer(call(.ringing)))
        XCTAssertTrue(CallStatusPresenter.needsLiveTimer(call(.active)))
        XCTAssertTrue(CallStatusPresenter.needsLiveTimer(call(.held)))
        XCTAssertFalse(CallStatusPresenter.needsLiveTimer(call(.ended(.completed))))
    }

    func testControlAvailability() {
        let dialing = CallStatusPresenter.controlsEnabled(for: call(.dialing))
        XCTAssertTrue(dialing.mute)
        XCTAssertFalse(dialing.keypad)
        XCTAssertFalse(dialing.hold)

        let active = CallStatusPresenter.controlsEnabled(for: call(.active))
        XCTAssertTrue(active.keypad)
        XCTAssertTrue(active.hold)

        let held = CallStatusPresenter.controlsEnabled(for: call(.held))
        XCTAssertFalse(held.keypad, "DTMF makes no sense while on hold")
        XCTAssertTrue(held.hold)

        let ended = CallStatusPresenter.controlsEnabled(for: call(.ended(.completed)))
        XCTAssertFalse(ended.mute)
        XCTAssertFalse(ended.speaker)
    }
}
