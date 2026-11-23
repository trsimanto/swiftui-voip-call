import AVFoundation
import CallCore
import os

/// `AVAudioSession` setup for two-way voice.
///
/// With CallKit the system owns activation: we set the category up front and
/// wait for `provider(_:didActivate:)` before starting audio I/O. Activating
/// the session ourselves would race CallKit and can leave the call silent.
@MainActor
final class AudioSessionController: AudioRouting {
    private let session: AVAudioSession
    private let logger = Logger(subsystem: "dev.towhid.voipcall", category: "Audio")

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func configureForVoiceCall() throws {
        // .voiceChat enables the built-in echo cancellation and AGC.
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .duckOthers])
        try session.setPreferredSampleRate(48_000)
        // 10 ms buffers: a good trade-off between latency and CPU wakeups.
        try session.setPreferredIOBufferDuration(0.01)
    }

    func setSpeakerEnabled(_ enabled: Bool) throws {
        try session.overrideOutputAudioPort(enabled ? .speaker : .none)
        let state = enabled ? "on" : "off"
        logger.debug("Speaker \(state, privacy: .public)")
    }

    func audioSessionDidActivate() {
        // This is where the WebRTC / RTP audio unit would be started.
        logger.info("Audio session activated, route: \(self.currentRouteDescription, privacy: .public)")
    }

    func audioSessionDidDeactivate() {
        logger.info("Audio session deactivated")
    }

    private var currentRouteDescription: String {
        session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
    }
}
