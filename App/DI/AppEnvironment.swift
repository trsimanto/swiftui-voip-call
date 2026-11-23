import CallCore
import Foundation

/// App-wide object graph, built once from the container.
@MainActor
final class AppEnvironment {
    let callSession: CallSession

    private let container: DependencyContainer
    private var hasStarted = false

    init(container: DependencyContainer) {
        self.container = container
        self.callSession = CallSession(
            manager: container.resolve(CallManager.self),
            simulator: container.resolveIfRegistered((any IncomingCallSimulating).self)
        )
    }

    static func live() -> AppEnvironment {
        // Under XCTest the host app shouldn't touch CallKit or the user's history file.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return AppEnvironment(container: CompositionRoot.makeContainer(mode: isRunningTests ? .isolated : .live))
    }

    static func preview() -> AppEnvironment {
        AppEnvironment(container: CompositionRoot.makeContainer(mode: .isolated))
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        callSession.start()
        container.resolve(VoIPPushRegistry.self).register()
        await container.resolve(CallManager.self).start()
    }

    // MARK: - Screen factories

    func makeContactsViewModel() -> ContactsViewModel {
        ContactsViewModel(repository: container.resolve((any ContactRepository).self))
    }

    func makeRecentsViewModel() -> RecentsViewModel {
        RecentsViewModel(repository: container.resolve((any CallHistoryRepository).self))
    }

    func makeDialerViewModel() -> DialerViewModel {
        DialerViewModel()
    }
}
