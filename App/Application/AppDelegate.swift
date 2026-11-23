import UIKit

/// Owns the object graph so it exists before SwiftUI builds any views. VoIP
/// pushes can launch the app straight into the background, and PushKit must
/// be registered early in launch for those to be delivered.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private(set) lazy var environment = AppEnvironment.live()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let environment = environment
        Task { await environment.start() }
        return true
    }
}
