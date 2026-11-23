import SwiftUI

@main
struct VoIPCallApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(environment: appDelegate.environment)
        }
    }
}
