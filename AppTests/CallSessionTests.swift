import CallCore
import XCTest
@testable import VoIPCall

/// End-to-end through the real CallManager, loopback provider and mock
/// signaling with zero delays: the same wiring the simulator build uses.
@MainActor
final class CallSessionTests: XCTestCase {

    private func makeSession() async -> (CallSession, CallManager, MockSignalingService) {
        let signaling = MockSignalingService(configuration: .immediate)
        let manager = CallManager(
            provider: LoopbackCallProvider(),
            signaling: signaling,
            history: InMemoryCallHistoryStore(),
            audio: NoopAudioRouting(),
            endedCallLinger: .seconds(30)
        )
        let session = CallSession(manager: manager, simulator: signaling)
        session.start()
        await manager.start()
        return (session, manager, signaling)
    }

    private func waitFor(_ description: String, timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(description)")
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testOutgoingCallReachesActiveAndEnds() async {
        let (session, manager, _) = await makeSession()
        defer { manager.stop() }

        session.startCall(handle: "+1 (555) 010-0101", name: "Ayesha Rahman")
        await waitFor("active call") { session.call?.state == .active }
        XCTAssertTrue(session.isPresentingCall)
        XCTAssertEqual(session.call?.displayName, "Ayesha Rahman")

        session.toggleMute()
        await waitFor("muted") { session.call?.isMuted == true }

        session.endCall()
        await waitFor("ended") { session.call?.state == .ended(.completed) }
        await waitFor("history bump") { session.historyVersion == 1 }

        session.dismissEndedCall()
        await waitFor("dismissed") { session.call == nil }
    }

    func testBlankNumberIsIgnored() async {
        let (session, manager, _) = await makeSession()
        defer { manager.stop() }

        session.startCall(handle: "   ", name: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(session.call)
    }

    func testSimulatedIncomingCallCanBeAccepted() async {
        let (session, manager, _) = await makeSession()
        defer { manager.stop() }

        session.simulateIncomingCall(delay: .zero)
        await waitFor("ringing") { session.call?.state == .ringing }
        XCTAssertEqual(session.call?.direction, .incoming)

        session.accept()
        await waitFor("active") { session.call?.state == .active }
    }

    func testUnreachableServerSurfacesFriendlyError() async {
        let signaling = MockSignalingService(
            configuration: {
                var config = MockSignalingService.Configuration.immediate
                config.behaviors = [SampleContacts.unreachableHandle: .networkFailure]
                return config
            }()
        )
        let manager = CallManager(
            provider: LoopbackCallProvider(),
            signaling: signaling,
            history: InMemoryCallHistoryStore(),
            audio: NoopAudioRouting()
        )
        let session = CallSession(manager: manager, simulator: nil)
        session.start()
        await manager.start()
        defer { manager.stop() }

        session.startCall(handle: SampleContacts.unreachableHandle, name: "Offline Server")
        await waitFor("failure") { session.call?.state == .ended(.failed) }
        XCTAssertEqual(session.errorMessage, "Couldn't reach the calling server. Check your connection and try again.")
    }

    func testUserMessages() {
        XCTAssertNil(CallSession.userMessage(for: CallManagerError.invalidTransition(InvalidCallTransition(from: .idle, event: .hold))))
        XCTAssertNil(CallSession.userMessage(for: CallManagerError.noActiveCall))
        XCTAssertNotNil(CallSession.userMessage(for: CallManagerError.callAlreadyInProgress))
        XCTAssertNotNil(CallSession.userMessage(for: CallManagerError.providerRequestFailed("x")))
    }

    func testIsolatedCompositionResolvesEverything() async {
        let environment = AppEnvironment.preview()
        XCTAssertNil(environment.callSession.call)
        XCTAssertTrue(environment.callSession.canSimulateIncomingCall)

        let contacts = environment.makeContactsViewModel()
        await contacts.load()
        XCTAssertEqual(contacts.contacts.count, SampleContacts.all.count)
        XCTAssertFalse(contacts.favorites.isEmpty)

        contacts.searchText = "mei"
        XCTAssertEqual(contacts.filteredContacts.map(\.name), ["Mei Tanaka"])
        XCTAssertTrue(contacts.favorites.isEmpty)
    }
}
