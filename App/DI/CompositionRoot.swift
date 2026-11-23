import CallCore
import Foundation

/// The one place that knows about concrete types. Everything else depends on
/// protocols from CallCore.
@MainActor
enum CompositionRoot {
    enum Mode {
        /// CallKit on device, JSON history on disk.
        case live
        /// Loopback provider and in-memory history; used by unit tests and previews.
        case isolated
    }

    static func makeContainer(mode: Mode) -> DependencyContainer {
        let container = DependencyContainer()

        // One mock instance plays both roles: signaling and the demo's
        // "simulate incoming call" hook.
        let signaling = MockSignalingService(configuration: .demo)
        container.register((any SignalingService).self) { _ in signaling }
        container.register((any IncomingCallSimulating).self) { _ in signaling }

        container.register((any CallProvider).self) { _ in
            makeCallProvider(mode: mode)
        }

        container.register((any AudioRouting).self) { _ in
            makeAudioRouting(mode: mode)
        }

        container.register((any CallHistoryRepository).self) { _ in
            makeHistoryRepository(mode: mode)
        }

        container.register((any ContactRepository).self) { _ in
            SampleContactRepository()
        }

        container.register(CallManager.self) { c in
            CallManager(
                provider: c.resolve((any CallProvider).self),
                signaling: c.resolve((any SignalingService).self),
                history: c.resolve((any CallHistoryRepository).self),
                audio: c.resolve((any AudioRouting).self)
            )
        }

        container.register(VoIPPushRegistry.self) { c in
            let manager = c.resolve(CallManager.self)
            return VoIPPushRegistry { push in
                await manager.reportIncomingPush(
                    callID: push.callID,
                    handle: push.handle,
                    displayName: push.callerName
                )
            }
        }

        return container
    }

    private static func makeCallProvider(mode: Mode) -> any CallProvider {
        #if targetEnvironment(simulator)
        // CallKit can't place outgoing calls in the simulator.
        return LoopbackCallProvider()
        #else
        if mode == .isolated || ProcessInfo.processInfo.arguments.contains("-useLoopbackProvider") {
            return LoopbackCallProvider()
        }
        return CallKitProvider()
        #endif
    }

    private static func makeAudioRouting(mode: Mode) -> any AudioRouting {
        if mode == .live {
            return AudioSessionController()
        }
        return NoopAudioRouting()
    }

    private static func makeHistoryRepository(mode: Mode) -> any CallHistoryRepository {
        guard mode == .live, let url = try? JSONCallHistoryStore.defaultFileURL() else {
            return InMemoryCallHistoryStore()
        }
        return JSONCallHistoryStore(fileURL: url)
    }
}
