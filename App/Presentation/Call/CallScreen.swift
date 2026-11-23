import CallCore
import SwiftUI

/// Full-screen container that switches between the incoming and in-call UIs.
@MainActor
struct CallScreen: View {
    @Environment(CallSession.self) private var session

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.10, blue: 0.18), Color(red: 0.02, green: 0.03, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let call = session.call {
                if call.direction == .incoming && call.state == .ringing {
                    IncomingCallView(
                        call: call,
                        onAccept: { session.accept() },
                        onDecline: { session.endCall() }
                    )
                    .transition(.opacity)
                } else {
                    ActiveCallView(call: call)
                        .transition(.opacity)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.25), value: session.call?.state)
    }
}
