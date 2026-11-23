import XCTest
@testable import CallCore

final class CallManagerTests: XCTestCase {

    // MARK: - Setup

    @MainActor
    func testStartRegistersOnce() async {
        let h = await CallManagerHarness.make()
        await h.manager.start()

        let count = await h.signaling.registerCount
        XCTAssertEqual(count, 1)
        h.manager.stop()
    }

    // MARK: - Outgoing

    @MainActor
    func testOutgoingCallHappyPath() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }

        let id = try await h.manager.startOutgoingCall(to: "+1 (555) 010-0101", displayName: "Ayesha Rahman")
        XCTAssertEqual(h.state, .dialing)
        XCTAssertEqual(h.manager.currentCall?.direction, .outgoing)
        XCTAssertEqual(h.manager.currentCall?.displayName, "Ayesha Rahman")
        XCTAssertEqual(h.audio.configureCount, 1)

        await waitUntil("INVITE sent") { await h.signaling.placedCalls.map { $0.id } == [id] }
        await waitUntil("audio session activated") { h.audio.activations == 1 }

        h.signaling.emit(.remoteRinging(id: id))
        await waitUntil("ringing") { h.state == .ringing }

        h.signaling.emit(.remoteAnswered(id: id))
        await waitUntil("connecting") { h.state == .connecting }
        XCTAssertEqual(h.provider.reportedConnecting, [id])

        h.signaling.emit(.mediaConnected(id: id))
        await waitUntil("active") { h.state == .active }
        XCTAssertEqual(h.provider.reportedConnected, [id])
        XCTAssertEqual(h.manager.currentCall?.connectedAt, h.clock.now)

        h.clock.advance(by: 95)
        try await h.manager.end()
        await waitUntil("ended") { h.state == .ended(.completed) }

        let hungUp = await h.signaling.hungUpCalls
        XCTAssertEqual(hungUp, [id])
        XCTAssertTrue(h.provider.reportedEnded.isEmpty, "a provider-initiated end must not be reported back to it")

        await waitUntil("history saved") { await h.historyRecords().count == 1 }
        let record = await h.historyRecords().first
        XCTAssertEqual(record?.id, id)
        XCTAssertEqual(record?.direction, .outgoing)
        XCTAssertEqual(record?.endReason, .completed)
        XCTAssertEqual(record?.duration, 95)
    }

    @MainActor
    func testSecondOutgoingCallIsRejectedWhileOneIsInProgress() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }

        try await h.manager.startOutgoingCall(to: "100")
        do {
            try await h.manager.startOutgoingCall(to: "200")
            XCTFail("expected callAlreadyInProgress")
        } catch {
            XCTAssertEqual(error as? CallManagerError, .callAlreadyInProgress)
        }
    }

    @MainActor
    func testCancellingBeforeAnswerIsRecordedAsCancelled() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }

        let id = try await h.manager.startOutgoingCall(to: "100")
        await waitUntil("INVITE sent") { !(await h.signaling.placedCalls.isEmpty) }
        h.signaling.emit(.remoteRinging(id: id))
        await waitUntil("ringing") { h.state == .ringing }

        try await h.manager.end()
        await waitUntil("cancelled") { h.state == .ended(.cancelled) }
        await waitUntil("history saved") { await h.historyRecords().first?.endReason == .cancelled }
        let duration = await h.historyRecords().first?.duration
        XCTAssertEqual(duration, 0)
    }

    @MainActor
    func testSignalingFailureEndsCallAsFailed() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        await h.signaling.failPlaceCall(with: .networkUnavailable)
        let recorder = EventRecorder(manager: h.manager)

        let id = try await h.manager.startOutgoingCall(to: "100")
        await waitUntil("failed") { h.state == .ended(.failed) }

        XCTAssertEqual(h.provider.reportedEnded.map { $0.id }, [id])
        XCTAssertEqual(h.provider.reportedEnded.first?.reason, .failed)
        await waitUntil("error published") {
            recorder.errors.contains { if case .signalingFailed = $0 { return true } else { return false } }
        }
        recorder.stop()
    }

    @MainActor
    func testProviderRefusingStartThrowsAndEndsCall() async {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        h.provider.failStartCall = true

        do {
            try await h.manager.startOutgoingCall(to: "100")
            XCTFail("expected providerRequestFailed")
        } catch let error as CallManagerError {
            guard case .providerRequestFailed = error else {
                return XCTFail("unexpected error \(error)")
            }
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(h.state, .ended(.failed))
    }

    @MainActor
    func testRemoteBusyEndsOutgoingCall() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }

        let id = try await h.manager.startOutgoingCall(to: "100")
        h.signaling.emit(.remoteEnded(id: id, reason: .busy))
        await waitUntil("busy") { h.state == .ended(.busy) }
        XCTAssertEqual(h.provider.reportedEnded.first?.reason, .busy)
    }

    @MainActor
    func testRemoteHangUpDuringActiveCall() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }

        let id = try await h.establishOutgoingCall()
        h.clock.advance(by: 12)
        h.signaling.emit(.remoteEnded(id: id, reason: .completed))

        await waitUntil("ended") { h.state == .ended(.completed) }
        XCTAssertEqual(h.provider.reportedEnded.first?.reason, .completed)
        await waitUntil("history saved") { await h.historyRecords().first?.duration == 12 }
    }

    // MARK: - Incoming

    @MainActor
    func testIncomingCallAccepted() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let id = UUID()

        h.signaling.emit(.incomingCall(id: id, handle: "+1 (555) 010-0142", displayName: "Daniel Okafor"))
        await waitUntil("ringing") { h.state == .ringing }
        XCTAssertEqual(h.manager.currentCall?.id, id)
        XCTAssertEqual(h.manager.currentCall?.direction, .incoming)
        XCTAssertEqual(h.provider.reportedIncomingCalls, [id])

        try await h.manager.answer()
        await waitUntil("answered on signaling") { await h.signaling.answeredCalls == [id] }
        XCTAssertEqual(h.state, .connecting)

        h.signaling.emit(.mediaConnected(id: id))
        await waitUntil("active") { h.state == .active }
        XCTAssertTrue(h.provider.reportedConnected.isEmpty, "only outgoing calls report connection to the provider")
    }

    @MainActor
    func testAnswerIsRejectedForOutgoingCall() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }

        try await h.manager.startOutgoingCall(to: "100")
        do {
            try await h.manager.answer()
            XCTFail("expected operationNotAllowed")
        } catch {
            XCTAssertEqual(error as? CallManagerError, .operationNotAllowed(state: .dialing))
        }
    }

    @MainActor
    func testIncomingCallDeclined() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let id = UUID()

        h.signaling.emit(.incomingCall(id: id, handle: "300", displayName: nil))
        await waitUntil("ringing") { h.state == .ringing }
        XCTAssertEqual(h.manager.currentCall?.displayName, "300", "falls back to the handle")

        try await h.manager.end()
        await waitUntil("declined") { h.state == .ended(.declined) }

        let rejected = await h.signaling.rejectedCalls
        XCTAssertEqual(rejected.map { $0.id }, [id])
        XCTAssertEqual(rejected.first?.reason, .declined)
        let hungUp = await h.signaling.hungUpCalls
        XCTAssertTrue(hungUp.isEmpty)
        await waitUntil("history saved") { await h.historyRecords().first?.endReason == .declined }
    }

    @MainActor
    func testIncomingCallBecomesMissedWhenCallerGivesUp() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let id = UUID()

        h.signaling.emit(.incomingCall(id: id, handle: "300", displayName: "Mei"))
        await waitUntil("ringing") { h.state == .ringing }
        h.signaling.emit(.remoteEnded(id: id, reason: .cancelled))

        await waitUntil("missed") { h.state == .ended(.missed) }
        XCTAssertEqual(h.provider.reportedEnded.first?.reason, .missed)
        await waitUntil("history saved") { await h.historyRecords().first?.isMissed == true }
    }

    @MainActor
    func testIncomingCallDuringActiveCallIsRejectedAsBusy() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let activeID = try await h.establishOutgoingCall()
        let secondID = UUID()

        h.signaling.emit(.incomingCall(id: secondID, handle: "999", displayName: "Lars"))
        await waitUntil("busy reject") {
            await h.signaling.rejectedCalls.contains { $0.id == secondID && $0.reason == .busy }
        }

        XCTAssertEqual(h.manager.currentCall?.id, activeID)
        XCTAssertEqual(h.state, .active)
        XCTAssertTrue(h.provider.reportedIncomingCalls.isEmpty)
        await waitUntil("missed call logged") {
            await h.historyRecords().contains { $0.id == secondID && $0.isMissed }
        }
    }

    @MainActor
    func testIncomingCallBlockedByProviderIsDeclined() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        h.provider.failIncomingReport = true
        let id = UUID()

        h.signaling.emit(.incomingCall(id: id, handle: "300", displayName: nil))
        await waitUntil("declined") { h.state == .ended(.declined) }
        let rejected = await h.signaling.rejectedCalls.map { $0.id }
        XCTAssertEqual(rejected, [id])
    }

    @MainActor
    func testVoIPPushReportsIncomingCallAndDeduplicatesInvite() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let id = UUID()

        await h.manager.reportIncomingPush(callID: id, handle: "300", displayName: "Push Caller")
        XCTAssertEqual(h.state, .ringing)
        XCTAssertEqual(h.provider.reportedIncomingCalls, [id])

        // The INVITE for the same call usually lands right after the push.
        h.signaling.emit(.incomingCall(id: id, handle: "300", displayName: "Push Caller"))
        try await Task.sleep(nanoseconds: 50_000_000)
        let rejected = await h.signaling.rejectedCalls
        XCTAssertTrue(rejected.isEmpty)
        XCTAssertEqual(h.state, .ringing)
    }

    // MARK: - In-call controls

    @MainActor
    func testHoldAndResume() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let id = try await h.establishOutgoingCall()

        try await h.manager.setHeld(true)
        await waitUntil("held") { h.state == .held }
        XCTAssertTrue(h.manager.currentCall?.isOnHold ?? false)

        try await h.manager.setHeld(false)
        await waitUntil("resumed") { h.state == .active }

        let requests = await h.signaling.holdRequests
        XCTAssertEqual(requests.map { $0.onHold }, [true, false])
        XCTAssertEqual(Set(requests.map { $0.id }), [id])
    }

    @MainActor
    func testHoldIsNotAllowedBeforeCallIsActive() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }

        try await h.manager.startOutgoingCall(to: "100")
        do {
            try await h.manager.setHeld(true)
            XCTFail("expected operationNotAllowed")
        } catch {
            XCTAssertEqual(error as? CallManagerError, .operationNotAllowed(state: .dialing))
        }
    }

    @MainActor
    func testHoldFailureLeavesCallActive() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        try await h.establishOutgoingCall()
        await h.signaling.failHold(with: .timeout)
        let recorder = EventRecorder(manager: h.manager)

        try await h.manager.setHeld(true)
        await waitUntil("error published") { !recorder.errors.isEmpty }
        XCTAssertEqual(h.state, .active)
        recorder.stop()
    }

    @MainActor
    func testMuteToggle() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        try await h.establishOutgoingCall()

        try await h.manager.setMuted(true)
        await waitUntil("muted") { h.manager.currentCall?.isMuted == true }

        try await h.manager.setMuted(false)
        await waitUntil("unmuted") { h.manager.currentCall?.isMuted == false }
    }

    @MainActor
    func testSpeakerRouting() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        try await h.establishOutgoingCall()

        try h.manager.setSpeakerEnabled(true)
        XCTAssertTrue(h.audio.speakerEnabled)
        XCTAssertEqual(h.manager.currentCall?.isSpeakerOn, true)

        h.audio.failSpeaker = true
        XCTAssertThrowsError(try h.manager.setSpeakerEnabled(false)) { error in
            guard case .audioRouteFailed = error as? CallManagerError else {
                return XCTFail("unexpected error \(error)")
            }
        }
        XCTAssertEqual(h.manager.currentCall?.isSpeakerOn, true, "UI state must follow the real route")
    }

    @MainActor
    func testSpeakerWithoutCallThrows() async {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }

        XCTAssertThrowsError(try h.manager.setSpeakerEnabled(true)) { error in
            XCTAssertEqual(error as? CallManagerError, .noActiveCall)
        }
    }

    @MainActor
    func testDTMFDigitsAreSentInOrder() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        try await h.establishOutgoingCall()

        try await h.manager.sendDTMF("1")
        try await h.manager.sendDTMF("#")
        await waitUntil("digits sent") { h.manager.currentCall?.dtmfDigits == "1#" }

        let sent = await h.signaling.dtmf
        XCTAssertEqual(sent, ["1", "#"])
    }

    @MainActor
    func testDTMFRequiresActiveCall() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }

        try await h.manager.startOutgoingCall(to: "100")
        do {
            try await h.manager.sendDTMF("5")
            XCTFail("expected operationNotAllowed")
        } catch {
            XCTAssertEqual(error as? CallManagerError, .operationNotAllowed(state: .dialing))
        }
    }

    @MainActor
    func testQualityReportsUpdateCall() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let id = try await h.establishOutgoingCall()

        h.signaling.emit(.qualityChanged(id: id, metrics: CallMetrics(roundTripTimeMs: 40, jitterMs: 4, packetLossPercent: 0)))
        await waitUntil("excellent") { h.manager.currentCall?.quality == .excellent }

        h.signaling.emit(.qualityChanged(id: id, metrics: CallMetrics(roundTripTimeMs: 600, jitterMs: 80, packetLossPercent: 15)))
        await waitUntil("poor") { h.manager.currentCall?.quality == .poor }
    }

    // MARK: - Robustness

    @MainActor
    func testEventsForUnknownCallsAreIgnored() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        try await h.establishOutgoingCall()

        h.signaling.emit(.remoteEnded(id: UUID(), reason: .completed))
        h.signaling.emit(.qualityChanged(id: UUID(), metrics: CallMetrics(roundTripTimeMs: 900, jitterMs: 90, packetLossPercent: 30)))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(h.state, .active)
        XCTAssertNil(h.manager.currentCall?.quality)
    }

    @MainActor
    func testDuplicateSignalingIsReportedAsInvalidTransition() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let id = try await h.establishOutgoingCall()
        let recorder = EventRecorder(manager: h.manager)

        h.signaling.emit(.remoteRinging(id: id))
        await waitUntil("invalid transition reported") {
            recorder.errors.contains(.invalidTransition(InvalidCallTransition(from: .active, event: .remoteRinging)))
        }
        XCTAssertEqual(h.state, .active)
        recorder.stop()
    }

    // MARK: - Ended call lifecycle

    @MainActor
    func testEndedCallClearsAfterLinger() async throws {
        let h = await CallManagerHarness.make(linger: .milliseconds(20))
        defer { h.manager.stop() }
        try await h.establishOutgoingCall()

        try await h.manager.end()
        await waitUntil("cleared") { h.manager.currentCall == nil }
    }

    @MainActor
    func testDismissEndedCallClearsImmediately() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        try await h.establishOutgoingCall()

        h.manager.dismissEndedCall()
        XCTAssertNotNil(h.manager.currentCall, "live calls can't be dismissed")

        try await h.manager.end()
        await waitUntil("ended") { h.state?.isTerminal == true }
        h.manager.dismissEndedCall()
        XCTAssertNil(h.manager.currentCall)
    }

    @MainActor
    func testNewCallCanStartWhileEndedCallIsLingering() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let first = try await h.establishOutgoingCall()
        try await h.manager.end()
        await waitUntil("ended") { h.state?.isTerminal == true }

        let second = try await h.manager.startOutgoingCall(to: "200")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(h.state, .dialing)
    }

    @MainActor
    func testUpdatesReplayCurrentCallAndPublishHistoryChanges() async throws {
        let h = await CallManagerHarness.make()
        defer { h.manager.stop() }
        let id = try await h.manager.startOutgoingCall(to: "100")

        let recorder = EventRecorder(manager: h.manager)
        await waitUntil("replayed") { !recorder.calls.isEmpty }
        XCTAssertEqual(recorder.calls.first??.id, id)

        try await h.manager.end()
        await waitUntil("history change published") { recorder.historyChanges == 1 }
        recorder.stop()
    }

    func testLocalEndReasonMapping() {
        let now = Date()
        func call(_ direction: CallDirection, _ state: CallState) -> Call {
            Call(handle: "1", direction: direction, state: state, createdAt: now)
        }

        XCTAssertEqual(CallManager.localEndReason(for: call(.incoming, .ringing)), .declined)
        XCTAssertEqual(CallManager.localEndReason(for: call(.outgoing, .dialing)), .cancelled)
        XCTAssertEqual(CallManager.localEndReason(for: call(.outgoing, .ringing)), .cancelled)
        XCTAssertEqual(CallManager.localEndReason(for: call(.incoming, .connecting)), .completed)
        XCTAssertEqual(CallManager.localEndReason(for: call(.outgoing, .active)), .completed)
        XCTAssertEqual(CallManager.localEndReason(for: call(.incoming, .held)), .completed)
    }
}
