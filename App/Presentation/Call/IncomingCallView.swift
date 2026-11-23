import CallCore
import SwiftUI

struct IncomingCallView: View {
    let call: Call
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)

            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.35), lineWidth: 2)
                    .frame(width: 140, height: 140)
                    .scaleEffect(pulse ? 1.25 : 1)
                    .opacity(pulse ? 0 : 1)
                AvatarView(name: call.displayName, size: 112)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }

            Text(call.displayName)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            if call.displayName != call.handle {
                Text(call.handle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Label("Incoming VoIP call", systemImage: "waveform")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            HStack {
                RoundCallButton(title: "Decline", systemImage: "phone.down.fill", color: .red, action: onDecline)
                Spacer()
                RoundCallButton(title: "Accept", systemImage: "phone.fill", color: .green, action: onAccept)
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 48)
        }
        .padding()
    }
}

struct RoundCallButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(color))
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#Preview {
    IncomingCallView(
        call: Call(handle: "+1 (555) 010-0142", displayName: "Daniel Okafor", direction: .incoming, state: .ringing, createdAt: .now),
        onAccept: {},
        onDecline: {}
    )
    .background(Color.black)
}
