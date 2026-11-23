import CallCore
import SwiftUI

@MainActor
struct RootView: View {
    private let environment: AppEnvironment

    @State private var contacts: ContactsViewModel
    @State private var recents: RecentsViewModel
    @State private var dialer: DialerViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _contacts = State(initialValue: environment.makeContactsViewModel())
        _recents = State(initialValue: environment.makeRecentsViewModel())
        _dialer = State(initialValue: environment.makeDialerViewModel())
    }

    var body: some View {
        let session = environment.callSession
        let isPresentingCall = session.isPresentingCall
        let errorMessage = session.errorMessage

        TabView {
            ContactsView(viewModel: contacts)
                .tabItem { Label("Contacts", systemImage: "person.crop.circle") }

            RecentsView(viewModel: recents)
                .tabItem { Label("Recents", systemImage: "clock") }
                .badge(recents.missedCount)

            DialerView(viewModel: dialer)
                .tabItem { Label("Keypad", systemImage: "circle.grid.3x3.fill") }
        }
        .environment(session)
        .fullScreenCover(isPresented: Binding(
            get: { isPresentingCall },
            set: { presented in
                if !presented { session.dismissEndedCall() }
            }
        )) {
            CallScreen()
                .environment(session)
        }
        .alert(
            "Call Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { presented in
                    if !presented { session.errorMessage = nil }
                }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
        .task { await environment.start() }
    }
}

#Preview {
    RootView(environment: .preview())
}
