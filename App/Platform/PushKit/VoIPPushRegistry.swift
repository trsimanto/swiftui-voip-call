import Foundation
import PushKit
import os

struct IncomingCallPush: Equatable {
    let callID: UUID
    let handle: String
    let callerName: String?

    /// Expected payload shape:
    /// `{ "call_id": "<uuid>", "handle": "+15550100", "caller_name": "Ayesha" }`
    init?(payload: [AnyHashable: Any]) {
        guard
            let rawID = payload["call_id"] as? String,
            let callID = UUID(uuidString: rawID),
            let handle = payload["handle"] as? String,
            !handle.isEmpty
        else { return nil }

        self.callID = callID
        self.handle = handle
        self.callerName = payload["caller_name"] as? String
    }
}

/// PushKit VoIP registration.
///
/// The server side isn't part of this demo, so the token is only logged; in
/// production it would be uploaded alongside the SIP registration. The
/// important bit is the incoming-push contract: since iOS 13 every VoIP push
/// *must* result in a CallKit report before the completion handler runs, or
/// the system terminates the app and eventually stops delivering pushes.
final class VoIPPushRegistry: NSObject, PKPushRegistryDelegate {
    typealias IncomingCallHandler = @MainActor (IncomingCallPush) async -> Void

    private(set) var tokenHex: String?
    private let registry: PKPushRegistry
    private let onIncomingCall: IncomingCallHandler
    private let logger = Logger(subsystem: "dev.towhid.voipcall", category: "PushKit")

    init(onIncomingCall: @escaping IncomingCallHandler) {
        self.registry = PKPushRegistry(queue: .main)
        self.onIncomingCall = onIncomingCall
        super.init()
    }

    func register() {
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
    }

    // MARK: - PKPushRegistryDelegate

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        tokenHex = token
        // TODO: send to the signaling backend together with the SIP registration.
        logger.info("VoIP push token updated (\(token.count / 2) bytes)")
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        tokenHex = nil
        logger.info("VoIP push token invalidated")
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }

        // A malformed push still has to be reported to CallKit, so fall back to
        // an unknown caller rather than dropping it.
        let push = IncomingCallPush(payload: payload.dictionaryPayload)
            ?? IncomingCallPush(payload: ["call_id": UUID().uuidString, "handle": "Unknown"])!

        let handler = onIncomingCall
        Task { @MainActor in
            await handler(push)
            completion()
        }
    }
}
