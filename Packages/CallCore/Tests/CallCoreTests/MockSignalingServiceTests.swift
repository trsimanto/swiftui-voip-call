import XCTest
@testable import CallCore

final class MockSignalingServiceTests: XCTestCase {

    func testPlaceCallRequiresRegistration() async {
        let service = MockSignalingService(configuration: .immediate)
        do {
            try await service.placeCall(id: UUID(), to: "100")
            XCTFail("expected notRegistered")
        } catch {
            XCTAssertEqual(error as? SignalingError, .notRegistered)
        }
    }

    func testAnsweringRemoteGoesThroughFullSignalingSequence() async throws {
        let service = MockSignalingService(configuration: .immediate)
        let id = UUID()

        try await service.register()
        try await service.placeCall(id: id, to: "100")

        let events = await collect(4, from: service.events)
        XCTAssertEqual(events, [
            .registered,
            .remoteRinging(id: id),
            .remoteAnswered(id: id),
            .mediaConnected(id: id)
        ])
    }

    func testBusyRemote() async throws {
        let service = MockSignalingService(configuration: makeConfig(behaviors: ["busy": .busy]))
        let id = UUID()

        try await service.register()
        try await service.placeCall(id: id, to: "busy")

        let events = await collect(2, from: service.events)
        XCTAssertEqual(events, [.registered, .remoteEnded(id: id, reason: .busy)])
    }

    func testDecliningRemote() async throws {
        let service = MockSignalingService(configuration: makeConfig(behaviors: ["nope": .decline]))
        let id = UUID()

        try await service.register()
        try await service.placeCall(id: id, to: "nope")

        let events = await collect(3, from: service.events)
        XCTAssertEqual(events, [.registered, .remoteRinging(id: id), .remoteEnded(id: id, reason: .declined)])
    }

    func testUnansweredRemote() async throws {
        let service = MockSignalingService(configuration: makeConfig(behaviors: ["vm": .noAnswer]))
        let id = UUID()

        try await service.register()
        try await service.placeCall(id: id, to: "vm")

        let events = await collect(3, from: service.events)
        XCTAssertEqual(events.last, .remoteEnded(id: id, reason: .unanswered))
    }

    func testNetworkFailureThrows() async throws {
        let service = MockSignalingService(configuration: makeConfig(behaviors: ["down": .networkFailure]))
        try await service.register()

        do {
            try await service.placeCall(id: UUID(), to: "down")
            XCTFail("expected networkUnavailable")
        } catch {
            XCTAssertEqual(error as? SignalingError, .networkUnavailable)
        }
    }

    func testRandomFailureRateUsesInjectedRandomness() async throws {
        var config = MockSignalingService.Configuration.immediate
        config.randomFailureRate = 0.5

        let unlucky = MockSignalingService(configuration: config, randomUnit: { 0.1 })
        try await unlucky.register()
        do {
            try await unlucky.placeCall(id: UUID(), to: "100")
            XCTFail("expected a simulated failure")
        } catch {
            XCTAssertEqual(error as? SignalingError, .networkUnavailable)
        }

        let lucky = MockSignalingService(configuration: config, randomUnit: { 0.9 })
        try await lucky.register()
        try await lucky.placeCall(id: UUID(), to: "100")
    }

    func testIncomingCallCanBeAnswered() async throws {
        let service = MockSignalingService(configuration: .immediate)
        try await service.register()
        await service.simulateIncomingCall(from: "+1 555", displayName: "Caller", after: .zero)

        var iterator = service.events.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, .registered)

        guard case let .incomingCall(id, handle, name) = await iterator.next() else {
            return XCTFail("expected an incoming call")
        }
        XCTAssertEqual(handle, "+1 555")
        XCTAssertEqual(name, "Caller")

        try await service.answer(id: id)
        let connected = await iterator.next()
        XCTAssertEqual(connected, .mediaConnected(id: id))
    }

    func testAnsweringUnknownCallThrows() async throws {
        let service = MockSignalingService(configuration: .immediate)
        try await service.register()

        do {
            try await service.answer(id: UUID())
            XCTFail("expected unknownCall")
        } catch {
            XCTAssertEqual(error as? SignalingError, .unknownCall)
        }
    }

    func testHoldAndDTMFAreTrackedPerSession() async throws {
        var config = MockSignalingService.Configuration.immediate
        // Keep the session parked before answer so it stays alive.
        config.answerDelay = .seconds(30)
        let service = MockSignalingService(configuration: config)
        let id = UUID()
        try await service.register()
        try await service.placeCall(id: id, to: "100")

        try await service.setHold(true, id: id)
        var onHold = await service.isOnHold(id)
        XCTAssertTrue(onHold)

        try await service.setHold(false, id: id)
        onHold = await service.isOnHold(id)
        XCTAssertFalse(onHold)

        await service.sendDTMF("12", id: id)
        await service.sendDTMF("#", id: id)
        let digits = await service.sentDTMF[id]
        XCTAssertEqual(digits, "12#")

        await service.hangUp(id: id)
    }

    func testHangUpEndsSession() async throws {
        var config = MockSignalingService.Configuration.immediate
        config.answerDelay = .seconds(30)
        let service = MockSignalingService(configuration: config)
        let id = UUID()
        try await service.register()
        try await service.placeCall(id: id, to: "100")

        await service.hangUp(id: id)

        do {
            try await service.setHold(true, id: id)
            XCTFail("expected unknownCall after hang-up")
        } catch {
            XCTAssertEqual(error as? SignalingError, .unknownCall)
        }
    }

    func testRemoteHangUpEmitsCompleted() async throws {
        var config = MockSignalingService.Configuration.immediate
        config.answerDelay = .seconds(30)
        let service = MockSignalingService(configuration: config)
        let id = UUID()
        try await service.register()
        try await service.placeCall(id: id, to: "100")

        var iterator = service.events.makeAsyncIterator()
        let registered = await iterator.next()
        let ringing = await iterator.next()
        XCTAssertEqual(registered, .registered)
        XCTAssertEqual(ringing, .remoteRinging(id: id))

        await service.simulateRemoteHangUp(id: id)
        let ended = await iterator.next()
        XCTAssertEqual(ended, .remoteEnded(id: id, reason: .completed))
    }

    func testQualityReportsFollowMediaConnection() async throws {
        var config = MockSignalingService.Configuration.immediate
        config.qualityReportInterval = .milliseconds(10)
        let service = MockSignalingService(configuration: config, randomUnit: { 0.5 })
        let id = UUID()
        try await service.register()
        try await service.placeCall(id: id, to: "100")

        let events = await collect(6, from: service.events)
        let reports = events.filter {
            if case .qualityChanged = $0 { return true }
            return false
        }
        XCTAssertGreaterThanOrEqual(reports.count, 2)
        await service.hangUp(id: id)
    }

    func testDemoConfigurationMapsSampleContacts() {
        let behaviors = MockSignalingService.Configuration.demo.behaviors
        XCTAssertEqual(behaviors[SampleContacts.busyHandle], .busy)
        XCTAssertEqual(behaviors[SampleContacts.declineHandle], .decline)
        XCTAssertEqual(behaviors[SampleContacts.noAnswerHandle], .noAnswer)
        XCTAssertEqual(behaviors[SampleContacts.unreachableHandle], .networkFailure)
        XCTAssertNil(behaviors[SampleContacts.all[0].handle])
    }

    private func makeConfig(behaviors: [String: MockSignalingService.RemoteBehavior]) -> MockSignalingService.Configuration {
        var config = MockSignalingService.Configuration.immediate
        config.behaviors = behaviors
        return config
    }
}
