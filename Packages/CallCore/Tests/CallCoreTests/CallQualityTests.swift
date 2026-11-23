import XCTest
@testable import CallCore

final class CallQualityTests: XCTestCase {

    func testHealthyNetworkIsExcellent() {
        let metrics = CallMetrics(roundTripTimeMs: 40, jitterMs: 5, packetLossPercent: 0)
        XCTAssertEqual(CallQuality(metrics: metrics), .excellent)
    }

    func testHighLatencyWithSomeLossIsFair() {
        let metrics = CallMetrics(roundTripTimeMs: 300, jitterMs: 30, packetLossPercent: 5)
        XCTAssertEqual(CallQuality(metrics: metrics), .fair)
    }

    func testTerribleNetworkIsPoor() {
        let metrics = CallMetrics(roundTripTimeMs: 600, jitterMs: 80, packetLossPercent: 15)
        XCTAssertEqual(CallQuality(metrics: metrics), .poor)
        XCTAssertEqual(CallQuality.estimatedMOS(for: metrics), 1)
    }

    func testQualityDegradesMonotonicallyWithLoss() {
        var previous = CallQuality.excellent
        for loss in stride(from: 0.0, through: 20.0, by: 1.0) {
            let quality = CallQuality(metrics: CallMetrics(roundTripTimeMs: 60, jitterMs: 5, packetLossPercent: loss))
            XCTAssertLessThanOrEqual(quality, previous, "quality improved when loss rose to \(loss)%")
            previous = quality
        }
        XCTAssertEqual(previous, .poor)
    }

    func testBarsMatchLevels() {
        XCTAssertEqual(CallQuality.allCases.map(\.bars), [1, 2, 3, 4])
    }
}
