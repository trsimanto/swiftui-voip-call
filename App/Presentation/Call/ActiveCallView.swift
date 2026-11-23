import CallCore
import SwiftUI

@MainActor
struct ActiveCallView: View {
    let call: Call

    @Environment(CallSession.self) private var session
    @State private var showsKeypad = false

    var body: some View {
        VStack(spacing: 12) {
            header
                .padding(.top, 48)

            Spacer()

            if showsKeypad {
                keypad
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                controls
                    .transition(.opacity)
            }

            Spacer()

            endButton
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
        .animation(.spring(duration: 0.3), value: showsKeypad)
        .onChange(of: call.state) { _, newState in
            if newState != .active { showsKeypad = false }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(name: call.displayName, size: 96)

            Text(call.displayName)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            statusLine

            if let quality = call.quality, call.state.isLive {
                CallQualityIndicator(quality: quality)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if CallStatusPresenter.needsLiveTimer(call) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                statusText(at: context.date)
            }
        } else {
            statusText(at: .now)
        }
    }

    private func statusText(at date: Date) -> some View {
        Text(CallStatusPresenter.statusText(for: call, now: date))
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            .contentTransition(.numericText())
            .accessibilityIdentifier("call.status")
    }

    private var controls: some View {
        let enabled = CallStatusPresenter.controlsEnabled(for: call)
        return Grid(horizontalSpacing: 28, verticalSpacing: 24) {
            GridRow {
                CallControlButton(
                    title: call.isMuted ? "Unmute" : "Mute",
                    systemImage: call.isMuted ? "mic.slash.fill" : "mic.fill",
                    isOn: call.isMuted,
                    isEnabled: enabled.mute
                ) { session.toggleMute() }

                CallControlButton(
                    title: "Keypad",
                    systemImage: "circle.grid.3x3.fill",
                    isEnabled: enabled.keypad
                ) { showsKeypad = true }

                CallControlButton(
                    title: "Speaker",
                    systemImage: call.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                    isOn: call.isSpeakerOn,
                    isEnabled: enabled.speaker
                ) { session.toggleSpeaker() }
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)

                CallControlButton(
                    title: call.isOnHold ? "Resume" : "Hold",
                    systemImage: call.isOnHold ? "play.fill" : "pause.fill",
                    isOn: call.isOnHold,
                    isEnabled: enabled.hold
                ) { session.toggleHold() }

                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: 16) {
            Text(call.dtmfDigits.isEmpty ? " " : call.dtmfDigits)
                .font(.title2.monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.head)

            KeypadView(style: .dark) { digit in
                session.sendDigit(digit)
            }

            Button("Hide Keypad") { showsKeypad = false }
                .foregroundStyle(.white)
        }
    }

    private var endButton: some View {
        Button {
            session.endCall()
        } label: {
            Image(systemName: "phone.down.fill")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Circle().fill(Color.red))
        }
        .buttonStyle(.plain)
        .disabled(call.state.isTerminal)
        .opacity(call.state.isTerminal ? 0.4 : 1)
        .accessibilityLabel("End call")
    }
}
