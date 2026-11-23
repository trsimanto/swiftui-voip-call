import Foundation

public enum CallManagerError: Error, Equatable, Sendable {
    case callAlreadyInProgress
    case noActiveCall
    case operationNotAllowed(state: CallState)
    case invalidTransition(InvalidCallTransition)
    case providerRequestFailed(String)
    case signalingFailed(String)
    case audioRouteFailed(String)
}

public enum CallManagerEvent: Sendable {
    case callChanged(Call?)
    case historyChanged
    case error(CallManagerError)
}

/// Owns the one active call and coordinates the three parties involved in it:
/// the OS (`CallProvider`), the network (`SignalingService`) and audio
/// (`AudioRouting`).
///
/// Everything runs on the main actor. Call state is tiny and UI-bound, and a
/// single serial executor removes a whole class of races between CallKit
/// callbacks and signaling events. The slow work (network, disk) happens in
/// the actors behind the protocols.
@MainActor
public final class CallManager {
    public private(set) var currentCall: Call? {
        didSet { broadcast(.callChanged(currentCall)) }
    }

    private var machine = CallStateMachine()

    private let provider: CallProvider
    private let signaling: SignalingService
    private let history: CallHistoryRepository
    private let audio: AudioRouting
    private let now: @Sendable () -> Date
    private let endedCallLinger: Duration

    private var subscribers: [UUID: AsyncStream<CallManagerEvent>.Continuation] = [:]
    private var listenerTasks: [Task<Void, Never>] = []
    private var lingerTask: Task<Void, Never>?

    /// - Parameter endedCallLinger: How long an ended call stays visible
    ///   (showing "Call ended") before `currentCall` resets to nil.
    public init(
        provider: CallProvider,
        signaling: SignalingService,
        history: CallHistoryRepository,
        audio: AudioRouting,
        endedCallLinger: Duration = .milliseconds(1_200),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.signaling = signaling
        self.history = history
        self.audio = audio
        self.endedCallLinger = endedCallLinger
        self.now = now
    }

    // MARK: - Lifecycle

    /// Starts listening to the provider and signaling streams and registers
    /// with the signaling server. Safe to call more than once.
    public func start() async {
        guard listenerTasks.isEmpty else { return }

        let providerEvents = provider.events
        listenerTasks.append(Task { [weak self] in
            for await event in providerEvents {
                guard let self else { return }
                await self.handleProviderEvent(event)
            }
        })

        let signalingEvents = signaling.events
        listenerTasks.append(Task { [weak self] in
            for await event in signalingEvents {
                guard let self else { return }
                await self.handleSignalingEvent(event)
            }
        })

        do {
            try await signaling.register()
        } catch {
            broadcast(.error(.signalingFailed(String(describing: error))))
        }
    }

    public func stop() {
        listenerTasks.forEach { $0.cancel() }
        listenerTasks.removeAll()
        lingerTask?.cancel()
        lingerTask = nil
    }

    /// Multicast stream of state changes. The current call is replayed on
    /// subscription so late subscribers don't render a stale screen.
    public func updates() -> AsyncStream<CallManagerEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: CallManagerEvent.self)
        subscribers[UUID()] = continuation
        continuation.yield(.callChanged(currentCall))
        return stream
    }

    // MARK: - User intents

    @discardableResult
    public func startOutgoingCall(to handle: String, displayName: String? = nil) async throws -> UUID {
        if let currentCall, currentCall.state.isInProgress {
            throw CallManagerError.callAlreadyInProgress
        }
        resetForNewCall()

        let call = Call(handle: handle, displayName: displayName, direction: .outgoing, state: .idle, createdAt: now())
        currentCall = call
        apply(.dial)
        prepareAudio()

        do {
            try await provider.requestStartCall(id: call.id, handle: handle, displayName: displayName)
        } catch {
            await finishCall(id: call.id, reason: .failed, notifyProvider: false)
            throw CallManagerError.providerRequestFailed(String(describing: error))
        }
        return call.id
    }

    public func answer() async throws {
        let call = try requireCall()
        guard call.direction == .incoming, machine.canHandle(.answer) else {
            throw CallManagerError.operationNotAllowed(state: call.state)
        }
        try await performProviderRequest { try await $0.requestAnswer(id: call.id) }
    }

    /// Hang up, decline or cancel, depending on where the call is.
    public func end() async throws {
        let call = try requireCall()
        guard call.state.isInProgress else {
            throw CallManagerError.operationNotAllowed(state: call.state)
        }
        try await performProviderRequest { try await $0.requestEnd(id: call.id) }
    }

    public func setHeld(_ onHold: Bool) async throws {
        let call = try requireCall()
        guard machine.canHandle(onHold ? .hold : .resume) else {
            throw CallManagerError.operationNotAllowed(state: call.state)
        }
        try await performProviderRequest { try await $0.requestSetHeld(onHold, id: call.id) }
    }

    public func setMuted(_ muted: Bool) async throws {
        let call = try requireCall()
        guard call.state.isInProgress else {
            throw CallManagerError.operationNotAllowed(state: call.state)
        }
        try await performProviderRequest { try await $0.requestSetMuted(muted, id: call.id) }
    }

    public func sendDTMF(_ digits: String) async throws {
        let call = try requireCall()
        guard call.state == .active else {
            throw CallManagerError.operationNotAllowed(state: call.state)
        }
        try await performProviderRequest { try await $0.requestPlayDTMF(digits, id: call.id) }
    }

    /// Speaker routing isn't a CallKit action; it goes straight to the audio session.
    public func setSpeakerEnabled(_ enabled: Bool) throws {
        guard var call = currentCall, call.state.isInProgress else {
            throw CallManagerError.noActiveCall
        }
        do {
            try audio.setSpeakerEnabled(enabled)
        } catch {
            let failure = CallManagerError.audioRouteFailed(String(describing: error))
            broadcast(.error(failure))
            throw failure
        }
        call.isSpeakerOn = enabled
        currentCall = call
    }

    /// Clears an ended call immediately instead of waiting for the linger delay.
    public func dismissEndedCall() {
        guard let call = currentCall, call.state.isTerminal else { return }
        lingerTask?.cancel()
        lingerTask = nil
        currentCall = nil
        machine = CallStateMachine()
    }

    /// Entry point for VoIP pushes. iOS requires the call to be reported to
    /// CallKit before the push handler returns, so this goes through the same
    /// path as a signaling INVITE.
    public func reportIncomingPush(callID: UUID, handle: String, displayName: String?) async {
        await handleIncomingCall(id: callID, handle: handle, displayName: displayName)
    }

    // MARK: - Provider events

    private func handleProviderEvent(_ event: CallProviderEvent) async {
        switch event {
        case let .perform(action):
            await handleProviderAction(action)
        case .audioSessionActivated:
            audio.audioSessionDidActivate()
        case .audioSessionDeactivated:
            audio.audioSessionDidDeactivate()
        case .reset:
            if let call = currentCall, call.state.isInProgress {
                await signaling.hangUp(id: call.id)
                await finishCall(id: call.id, reason: .failed, notifyProvider: false)
            }
        }
    }

    private func handleProviderAction(_ action: ProviderAction) async {
        guard let call = currentCall, call.id == action.callID, call.state.isInProgress else {
            action.fail()
            return
        }

        switch action.kind {
        case .start:
            action.fulfill()
            // Don't hold up the provider event loop on the network round trip;
            // the user must still be able to cancel while the INVITE is in flight.
            Task { await self.placeCall(call) }

        case .answer:
            guard apply(.answer) else {
                action.fail()
                return
            }
            action.fulfill()
            Task { await self.acceptOnSignaling(call) }

        case .end:
            let reason = Self.localEndReason(for: call)
            if reason == .declined {
                await signaling.reject(id: call.id, reason: .declined)
            } else {
                await signaling.hangUp(id: call.id)
            }
            action.fulfill()
            // The provider initiated this end, so it already knows.
            await finishCall(id: call.id, reason: reason, notifyProvider: false)

        case let .setHeld(onHold):
            let event: CallEvent = onHold ? .hold : .resume
            guard machine.canHandle(event) else {
                action.fail()
                return
            }
            do {
                try await signaling.setHold(onHold, id: call.id)
                // Re-check: the call may have ended while we were waiting.
                guard currentCall?.id == call.id, apply(event) else {
                    action.fail()
                    return
                }
                action.fulfill()
            } catch {
                broadcast(.error(.signalingFailed(String(describing: error))))
                action.fail()
            }

        case let .setMuted(muted):
            // Muting is local: stop feeding the mic into the audio track.
            currentCall?.isMuted = muted
            action.fulfill()

        case let .playDTMF(digits):
            await signaling.sendDTMF(digits, id: call.id)
            if currentCall?.id == call.id {
                currentCall?.dtmfDigits.append(digits)
            }
            action.fulfill()
        }
    }

    // MARK: - Signaling events

    private func handleSignalingEvent(_ event: SignalingEvent) async {
        switch event {
        case .registered:
            break

        case let .incomingCall(id, handle, displayName):
            await handleIncomingCall(id: id, handle: handle, displayName: displayName)

        case let .remoteRinging(id):
            guard isCurrent(id) else { return }
            apply(.remoteRinging)

        case let .remoteAnswered(id):
            guard isCurrent(id), apply(.answer) else { return }
            provider.reportOutgoingCallStartedConnecting(id: id)

        case let .mediaConnected(id):
            guard isCurrent(id), apply(.mediaConnected) else { return }
            currentCall?.connectedAt = now()
            if currentCall?.direction == .outgoing {
                provider.reportOutgoingCallConnected(id: id)
            }

        case let .remoteEnded(id, reason):
            guard let call = currentCall, call.id == id else { return }
            // An incoming call that stops ringing before we pick up is "missed",
            // whatever the remote side calls it.
            let effectiveReason: CallEndReason =
                (call.direction == .incoming && call.state == .ringing) ? .missed : reason
            await finishCall(id: id, reason: effectiveReason, notifyProvider: true)

        case let .qualityChanged(id, metrics):
            guard isCurrent(id) else { return }
            currentCall?.quality = CallQuality(metrics: metrics)
        }
    }

    private func handleIncomingCall(id: UUID, handle: String, displayName: String?) async {
        // Single-line phone: anything arriving during a live call is busy.
        if let currentCall, currentCall.state.isInProgress {
            guard currentCall.id != id else { return } // push and INVITE for the same call
            await signaling.reject(id: id, reason: .busy)
            let missed = CallRecord(
                id: id,
                handle: handle,
                displayName: displayName ?? handle,
                direction: .incoming,
                endReason: .missed,
                startedAt: now(),
                duration: 0
            )
            await persist(missed)
            return
        }

        resetForNewCall()
        currentCall = Call(id: id, handle: handle, displayName: displayName, direction: .incoming, state: .idle, createdAt: now())
        apply(.incoming)
        prepareAudio()

        do {
            try await provider.reportIncomingCall(id: id, handle: handle, displayName: displayName)
        } catch {
            // Typically Do Not Disturb or a blocked number.
            await signaling.reject(id: id, reason: .declined)
            await finishCall(id: id, reason: .declined, notifyProvider: false)
        }
    }

    // MARK: - Helpers

    private func placeCall(_ call: Call) async {
        do {
            try await signaling.placeCall(id: call.id, to: call.handle)
        } catch {
            broadcast(.error(.signalingFailed(String(describing: error))))
            await finishCall(id: call.id, reason: .failed, notifyProvider: true)
        }
    }

    private func acceptOnSignaling(_ call: Call) async {
        do {
            try await signaling.answer(id: call.id)
        } catch {
            broadcast(.error(.signalingFailed(String(describing: error))))
            await finishCall(id: call.id, reason: .failed, notifyProvider: true)
        }
    }

    private func finishCall(id: UUID, reason: CallEndReason, notifyProvider: Bool) async {
        guard var call = currentCall, call.id == id, call.state.isInProgress else { return }

        _ = apply(.end(reason))
        let endedAt = now()
        call = currentCall ?? call
        call.endedAt = endedAt
        currentCall = call

        if notifyProvider {
            provider.reportCallEnded(id: id, reason: reason)
        }

        await persist(CallRecord(call: call, endReason: reason, endedAt: endedAt))
        scheduleClear(of: id)
    }

    private func persist(_ record: CallRecord) async {
        do {
            try await history.add(record)
            broadcast(.historyChanged)
        } catch {
            broadcast(.error(.signalingFailed("Could not save call history: \(error)")))
        }
    }

    private func scheduleClear(of id: UUID) {
        lingerTask?.cancel()
        let linger = endedCallLinger
        lingerTask = Task { [weak self] in
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled, let self, self.currentCall?.id == id else { return }
            self.currentCall = nil
            self.machine = CallStateMachine()
        }
    }

    /// Runs `event` through the state machine and mirrors the result onto
    /// `currentCall`. Invalid transitions are reported, not thrown, because
    /// they usually come from late network messages we can safely ignore.
    @discardableResult
    private func apply(_ event: CallEvent) -> Bool {
        do {
            let state = try machine.handle(event)
            currentCall?.state = state
            return true
        } catch let error as InvalidCallTransition {
            broadcast(.error(.invalidTransition(error)))
            return false
        } catch {
            return false
        }
    }

    private func resetForNewCall() {
        lingerTask?.cancel()
        lingerTask = nil
        machine = CallStateMachine()
    }

    private func prepareAudio() {
        do {
            try audio.configureForVoiceCall()
        } catch {
            broadcast(.error(.audioRouteFailed(String(describing: error))))
        }
    }

    private func isCurrent(_ id: UUID) -> Bool {
        currentCall?.id == id
    }

    private func requireCall() throws -> Call {
        guard let currentCall else { throw CallManagerError.noActiveCall }
        return currentCall
    }

    private func performProviderRequest(_ request: (CallProvider) async throws -> Void) async throws {
        do {
            try await request(provider)
        } catch let error as CallManagerError {
            throw error
        } catch {
            let failure = CallManagerError.providerRequestFailed(String(describing: error))
            broadcast(.error(failure))
            throw failure
        }
    }

    private func broadcast(_ event: CallManagerEvent) {
        for (token, continuation) in subscribers {
            // Subscribers that stopped listening are pruned lazily here.
            if case .terminated = continuation.yield(event) {
                subscribers[token] = nil
            }
        }
    }

    nonisolated static func localEndReason(for call: Call) -> CallEndReason {
        switch (call.direction, call.state) {
        case (.incoming, .ringing):
            return .declined
        case (.outgoing, .dialing), (.outgoing, .ringing):
            return .cancelled
        default:
            return .completed
        }
    }
}
