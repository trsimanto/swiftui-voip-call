import CallCore
import Foundation
import Observation

/// Observable bridge between `CallManager` and SwiftUI.
///
/// Views read `call` and send intents through the methods below; they never
/// talk to the manager directly. Errors are flattened into a single
/// user-facing message.
@MainActor
@Observable
final class CallSession {
    private(set) var call: Call?
    /// Bumped whenever call history changes so Recents can reload.
    private(set) var historyVersion = 0
    var errorMessage: String?

    private let manager: CallManager
    private let simulator: (any IncomingCallSimulating)?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(manager: CallManager, simulator: (any IncomingCallSimulating)?) {
        self.manager = manager
        self.simulator = simulator
    }

    var isPresentingCall: Bool { call != nil }
    var canSimulateIncomingCall: Bool { simulator != nil }

    func start() {
        guard updatesTask == nil else { return }
        let stream = manager.updates()
        updatesTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    // MARK: - Intents

    func startCall(to contact: Contact) {
        startCall(handle: contact.handle, name: contact.name)
    }

    func startCall(handle: String, name: String?) {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        run { try await $0.startOutgoingCall(to: trimmed, displayName: name) }
    }

    func accept() {
        run { try await $0.answer() }
    }

    func endCall() {
        run { try await $0.end() }
    }

    func toggleMute() {
        guard let call else { return }
        run { try await $0.setMuted(!call.isMuted) }
    }

    func toggleHold() {
        guard let call else { return }
        run { try await $0.setHeld(call.state != .held) }
    }

    func toggleSpeaker() {
        guard let call else { return }
        do {
            try manager.setSpeakerEnabled(!call.isSpeakerOn)
        } catch {
            present(error)
        }
    }

    func sendDigit(_ digit: String) {
        run { try await $0.sendDTMF(digit) }
    }

    func dismissEndedCall() {
        manager.dismissEndedCall()
    }

    /// Rings in a few seconds, long enough to lock the phone and see the
    /// CallKit lock-screen UI on a device.
    func simulateIncomingCall(delay: Duration = .seconds(3)) {
        guard let simulator else { return }
        let caller = SampleContacts.all.filter { SampleContacts.demoBehaviors[$0.handle] == nil }.randomElement()
            ?? SampleContacts.all[0]
        Task {
            await simulator.simulateIncomingCall(from: caller.handle, displayName: caller.name, after: delay)
        }
    }

    // MARK: - Private

    private func handle(_ event: CallManagerEvent) {
        switch event {
        case let .callChanged(call):
            self.call = call
        case .historyChanged:
            historyVersion += 1
        case let .error(error):
            present(error)
        }
    }

    private func run(_ operation: @escaping @MainActor (CallManager) async throws -> Void) {
        let manager = manager
        Task {
            do {
                try await operation(manager)
            } catch {
                present(error)
            }
        }
    }

    private func present(_ error: Error) {
        guard let message = Self.userMessage(for: error) else { return }
        errorMessage = message
    }

    /// nil means "don't bother the user with this".
    static func userMessage(for error: Error) -> String? {
        guard let error = error as? CallManagerError else {
            return error.localizedDescription
        }
        switch error {
        case .invalidTransition:
            // Late or duplicate network messages; logged, not shown.
            return nil
        case .callAlreadyInProgress:
            return "Finish your current call before starting another."
        case .noActiveCall, .operationNotAllowed:
            return nil
        case .providerRequestFailed:
            return "The system couldn't start the call. Check that calling isn't restricted on this device."
        case .signalingFailed:
            return "Couldn't reach the calling server. Check your connection and try again."
        case .audioRouteFailed:
            return "Couldn't switch the audio route."
        }
    }
}
