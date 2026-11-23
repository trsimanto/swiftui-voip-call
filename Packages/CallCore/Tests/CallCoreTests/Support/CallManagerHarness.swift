import Foundation
@testable import CallCore

/// Manually advanced clock so durations in assertions are exact.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

@MainActor
struct CallManagerHarness {
    let manager: CallManager
    let provider: ControllableCallProvider
    let signaling: StubSignalingService
    let history: InMemoryCallHistoryStore
    let audio: SpyAudioRouting
    let clock: TestClock

    static func make(linger: Duration = .seconds(60)) async -> CallManagerHarness {
        let provider = ControllableCallProvider()
        let signaling = StubSignalingService()
        let history = InMemoryCallHistoryStore()
        let audio = SpyAudioRouting()
        let clock = TestClock()
        let manager = CallManager(
            provider: provider,
            signaling: signaling,
            history: history,
            audio: audio,
            endedCallLinger: linger,
            now: { clock.now }
        )
        await manager.start()
        return CallManagerHarness(
            manager: manager,
            provider: provider,
            signaling: signaling,
            history: history,
            audio: audio,
            clock: clock
        )
    }

    var state: CallState? { manager.currentCall?.state }

    /// Drives an outgoing call all the way to `.active`.
    @discardableResult
    func establishOutgoingCall(to handle: String = "+1 (555) 010-0101", name: String = "Ayesha Rahman") async throws -> UUID {
        let id = try await manager.startOutgoingCall(to: handle, displayName: name)
        await waitUntil("INVITE sent") {
            await signaling.placedCalls.contains { $0.id == id }
        }
        signaling.emit(.remoteRinging(id: id))
        signaling.emit(.remoteAnswered(id: id))
        signaling.emit(.mediaConnected(id: id))
        await waitUntil("call active") { state == .active }
        return id
    }

    func historyRecords() async -> [CallRecord] {
        (try? await history.fetchAll()) ?? []
    }
}

/// Records everything `CallManager.updates()` publishes.
@MainActor
final class EventRecorder {
    private(set) var calls: [Call?] = []
    private(set) var errors: [CallManagerError] = []
    private(set) var historyChanges = 0
    private var task: Task<Void, Never>?

    init(manager: CallManager) {
        let stream = manager.updates()
        task = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case let .callChanged(call): self.calls.append(call)
                case .historyChanged: self.historyChanges += 1
                case let .error(error): self.errors.append(error)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
    }
}
