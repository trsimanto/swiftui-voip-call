import XCTest
@testable import CallCore

final class CallDurationFormatterTests: XCTestCase {

    func testClockString() {
        XCTAssertEqual(CallDurationFormatter.clockString(from: 0), "0:00")
        XCTAssertEqual(CallDurationFormatter.clockString(from: 7), "0:07")
        XCTAssertEqual(CallDurationFormatter.clockString(from: 59.9), "0:59")
        XCTAssertEqual(CallDurationFormatter.clockString(from: 60), "1:00")
        XCTAssertEqual(CallDurationFormatter.clockString(from: 765), "12:45")
        XCTAssertEqual(CallDurationFormatter.clockString(from: 3_600), "1:00:00")
        XCTAssertEqual(CallDurationFormatter.clockString(from: 3_723), "1:02:03")
    }

    func testClockStringHandlesBadInput() {
        XCTAssertEqual(CallDurationFormatter.clockString(from: -5), "0:00")
        XCTAssertEqual(CallDurationFormatter.clockString(from: .nan), "0:00")
        XCTAssertEqual(CallDurationFormatter.clockString(from: .infinity), "0:00")
        XCTAssertEqual(CallDurationFormatter.clockString(from: 10_000_000), "99:59:59")
    }

    func testCompactString() {
        XCTAssertEqual(CallDurationFormatter.compactString(from: 0), "0s")
        XCTAssertEqual(CallDurationFormatter.compactString(from: 45), "45s")
        XCTAssertEqual(CallDurationFormatter.compactString(from: 125), "2m 05s")
        XCTAssertEqual(CallDurationFormatter.compactString(from: 3_720), "1h 02m")
    }

    func testCallDurationIsZeroUntilConnected() {
        let start = Date(timeIntervalSince1970: 1_000)
        var call = Call(handle: "100", direction: .outgoing, state: .ringing, createdAt: start)
        XCTAssertEqual(call.duration(at: start.addingTimeInterval(30)), 0)

        call.connectedAt = start.addingTimeInterval(10)
        XCTAssertEqual(call.duration(at: start.addingTimeInterval(25)), 15)

        call.endedAt = start.addingTimeInterval(40)
        XCTAssertEqual(call.duration(at: start.addingTimeInterval(500)), 30, "duration freezes once the call ends")
    }
}
