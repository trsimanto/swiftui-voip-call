import Foundation

/// Audio session control, kept behind a protocol so CallCore stays free of
/// AVFoundation. The app provides an `AVAudioSession` backed implementation.
@MainActor
public protocol AudioRouting: AnyObject {
    /// Called before a call is reported to the system, as CallKit expects the
    /// category to be set up front and will activate the session itself.
    func configureForVoiceCall() throws
    func setSpeakerEnabled(_ enabled: Bool) throws
    /// The system activated the session; safe to start the media engine.
    func audioSessionDidActivate()
    func audioSessionDidDeactivate()
}

@MainActor
public final class NoopAudioRouting: AudioRouting {
    public init() {}
    public func configureForVoiceCall() throws {}
    public func setSpeakerEnabled(_ enabled: Bool) throws {}
    public func audioSessionDidActivate() {}
    public func audioSessionDidDeactivate() {}
}
