import Foundation

/// In-process stand-in for a SIP / WebRTC signaling server.
///
/// It plays the remote side of every call with configurable delays, so the
/// whole call flow (ringing, answer, media up, quality reports, remote hang-up)
/// can be exercised in the simulator or in tests with no backend.
public actor MockSignalingService: SignalingService, IncomingCallSimulating {

    /// How the simulated far end responds to an outgoing call.
    public enum RemoteBehavior: Sendable, Equatable {
        case answer
        case decline
        case busy
        case noAnswer
        /// INVITE never makes it out (DNS failure, offline, 503...).
        case networkFailure
    }

    public struct Configuration: Sendable {
        public var registrationDelay: Duration
        public var ringDelay: Duration
        public var answerDelay: Duration
        public var mediaSetupDelay: Duration
        public var noAnswerTimeout: Duration
        /// How long a simulated caller waits before giving up on us.
        public var incomingRingTimeout: Duration
        /// Interval between quality reports; nil disables them.
        public var qualityReportInterval: Duration?
        /// Chance (0...1) that an otherwise answering call fails to connect.
        public var randomFailureRate: Double
        /// Per-handle overrides; anything not listed answers.
        public var behaviors: [String: RemoteBehavior]

        public init(
            registrationDelay: Duration = .milliseconds(300),
            ringDelay: Duration = .milliseconds(800),
            answerDelay: Duration = .seconds(2),
            mediaSetupDelay: Duration = .milliseconds(600),
            noAnswerTimeout: Duration = .seconds(8),
            incomingRingTimeout: Duration = .seconds(30),
            qualityReportInterval: Duration? = .seconds(2),
            randomFailureRate: Double = 0,
            behaviors: [String: RemoteBehavior] = [:]
        ) {
            self.registrationDelay = registrationDelay
            self.ringDelay = ringDelay
            self.answerDelay = answerDelay
            self.mediaSetupDelay = mediaSetupDelay
            self.noAnswerTimeout = noAnswerTimeout
            self.incomingRingTimeout = incomingRingTimeout
            self.qualityReportInterval = qualityReportInterval
            self.randomFailureRate = randomFailureRate
            self.behaviors = behaviors
        }

        /// No delays and no background quality reports. Used by tests.
        public static let immediate = Configuration(
            registrationDelay: .zero,
            ringDelay: .zero,
            answerDelay: .zero,
            mediaSetupDelay: .zero,
            noAnswerTimeout: .zero,
            incomingRingTimeout: .seconds(60),
            qualityReportInterval: nil
        )

        /// Wires the sample contacts to interesting outcomes for the demo.
        public static let demo = Configuration(behaviors: SampleContacts.demoBehaviors)
    }

    public nonisolated let events: AsyncStream<SignalingEvent>
    private nonisolated let continuation: AsyncStream<SignalingEvent>.Continuation

    private let configuration: Configuration
    private let randomUnit: @Sendable () -> Double
    private var isRegistered = false
    private var sessions: [UUID: Task<Void, Never>] = [:]
    private var heldCalls: Set<UUID> = []
    private(set) var sentDTMF: [UUID: String] = [:]

    public init(
        configuration: Configuration = Configuration(),
        randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.configuration = configuration
        self.randomUnit = randomUnit
        let (stream, continuation) = AsyncStream.makeStream(of: SignalingEvent.self)
        self.events = stream
        self.continuation = continuation
    }

    deinit {
        sessions.values.forEach { $0.cancel() }
        continuation.finish()
    }

    // MARK: - SignalingService

    public func register() async throws {
        try await Task.sleep(for: configuration.registrationDelay)
        isRegistered = true
        continuation.yield(.registered)
    }

    public func placeCall(id: UUID, to handle: String) async throws {
        guard isRegistered else { throw SignalingError.notRegistered }

        var behavior = configuration.behaviors[handle] ?? .answer
        if behavior == .answer, configuration.randomFailureRate > 0, randomUnit() < configuration.randomFailureRate {
            behavior = .networkFailure
        }
        if behavior == .networkFailure {
            throw SignalingError.networkUnavailable
        }

        let config = configuration
        let outcome = behavior
        sessions[id] = Task { [weak self] in
            do {
                if outcome == .busy {
                    try await Task.sleep(for: config.ringDelay)
                    await self?.emit(.remoteEnded(id: id, reason: .busy))
                    return
                }

                try await Task.sleep(for: config.ringDelay)
                await self?.emit(.remoteRinging(id: id))

                switch outcome {
                case .decline:
                    try await Task.sleep(for: config.answerDelay)
                    await self?.emit(.remoteEnded(id: id, reason: .declined))
                case .noAnswer:
                    try await Task.sleep(for: config.noAnswerTimeout)
                    await self?.emit(.remoteEnded(id: id, reason: .unanswered))
                default:
                    try await Task.sleep(for: config.answerDelay)
                    await self?.emit(.remoteAnswered(id: id))
                    try await Task.sleep(for: config.mediaSetupDelay)
                    await self?.emit(.mediaConnected(id: id))
                    await self?.runQualityReports(for: id)
                }
            } catch {
                // Cancelled by hang-up; nothing left to report.
            }
        }
    }

    public func answer(id: UUID) async throws {
        guard isRegistered else { throw SignalingError.notRegistered }
        guard sessions[id] != nil else { throw SignalingError.unknownCall }

        sessions[id]?.cancel()
        let config = configuration
        sessions[id] = Task { [weak self] in
            do {
                try await Task.sleep(for: config.mediaSetupDelay)
                await self?.emit(.mediaConnected(id: id))
                await self?.runQualityReports(for: id)
            } catch {}
        }
    }

    public func reject(id: UUID, reason: CallEndReason) async {
        endSession(id)
    }

    public func hangUp(id: UUID) async {
        endSession(id)
    }

    public func setHold(_ onHold: Bool, id: UUID) async throws {
        guard sessions[id] != nil else { throw SignalingError.unknownCall }
        // A re-INVITE with a=sendonly / a=sendrecv would go out here.
        if onHold {
            heldCalls.insert(id)
        } else {
            heldCalls.remove(id)
        }
    }

    public func sendDTMF(_ digits: String, id: UUID) async {
        guard sessions[id] != nil else { return }
        // RFC 4733 telephone-event packets in a real media stack.
        sentDTMF[id, default: ""] += digits
    }

    // MARK: - Demo hooks

    public func simulateIncomingCall(from handle: String, displayName: String?, after delay: Duration) async {
        let id = UUID()
        let config = configuration
        // Placeholder session so answer/reject can find the call. If nobody
        // answers in time, the caller gives up and the call becomes missed.
        sessions[id] = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                await self?.emit(.incomingCall(id: id, handle: handle, displayName: displayName))
                try await Task.sleep(for: config.incomingRingTimeout)
                await self?.emit(.remoteEnded(id: id, reason: .missed))
            } catch {}
        }
    }

    /// Remote party hangs up an established call.
    public func simulateRemoteHangUp(id: UUID) {
        guard sessions[id] != nil else { return }
        endSession(id)
        continuation.yield(.remoteEnded(id: id, reason: .completed))
    }

    func isOnHold(_ id: UUID) -> Bool {
        heldCalls.contains(id)
    }

    // MARK: - Private

    private func emit(_ event: SignalingEvent) {
        continuation.yield(event)
    }

    private func endSession(_ id: UUID) {
        sessions.removeValue(forKey: id)?.cancel()
        heldCalls.remove(id)
    }

    /// Random walk around healthy values with the occasional bad patch, so the
    /// quality indicator visibly moves during a demo call.
    private func runQualityReports(for id: UUID) async {
        guard let interval = configuration.qualityReportInterval else { return }
        var metrics = CallMetrics(roundTripTimeMs: 60, jitterMs: 6, packetLossPercent: 0.2)
        while !Task.isCancelled {
            emit(.qualityChanged(id: id, metrics: metrics))
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            let degrade = randomUnit() < 0.15
            metrics.roundTripTimeMs = degrade ? 280 + randomUnit() * 200 : 40 + randomUnit() * 80
            metrics.jitterMs = degrade ? 30 + randomUnit() * 40 : 2 + randomUnit() * 12
            metrics.packetLossPercent = degrade ? 3 + randomUnit() * 6 : randomUnit() * 1.2
        }
    }
}
