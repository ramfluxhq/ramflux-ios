// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// A host event the renderer sends to a mounted node (`card.session.event`, `event` field of the body).
public enum CardHostEvent: Equatable, Sendable {
    case input(JSONValue)
    case activate
    case selectTab(index: Int)
    case modalOpen
    case modalClose

    var json: JSONValue {
        switch self {
        case .input(let value): .object(["kind": .string("input"), "value": value])
        case .activate: .object(["kind": .string("activate")])
        case .selectTab(let index): .object(["kind": .string("select_tab"), "index": .unsigned(UInt64(max(0, index)))])
        case .modalOpen: .object(["kind": .string("modal_open")])
        case .modalClose: .object(["kind": .string("modal_close")])
        }
    }
}

/// The outcome the host answers a host slot with (`card.session.slot`).
public enum CardSlotOutcome: String, Equatable, Sendable {
    case confirm, deny, cancel, unavailable
}

/// A host request the SDK raised for the host to show. The host answers it with `card.session.slot`.
public enum CardHostRequest: Equatable, Sendable {
    /// A link the author asked to open. Open the system browser only after the slot answers `opened`.
    case openURL(url: String, requestID: String, slotID: String, token: CardEventToken)
    /// A verified intent of an approval. Only "Waiting for confirmation" until the signed update.
    case approvalDecision(outcome: String, requestRef: String, taskBinding: JSONValue?)
    case other(kind: String)
}

/// The submit handle of a `pending_submit` result: the message id is reused for no other submit.
public struct CardSubmitHandle: Equatable, Sendable {
    public let messageID: String
    public let surfaceVersion: UInt64
    public let surfaceHash: String
}

/// One `card.session.*` result, decoded. Every result carries `render_allowed` and `fallback_text`; when
/// `renderAllowed` is false only the fallback text may be drawn.
public struct CardResponse: Equatable, Sendable {
    public let result: String
    public let session: UInt64?
    public let renderAllowed: Bool
    public let fallbackText: String
    public let reason: String?
    public let batch: CardMutationBatch?
    public let hostRequest: CardHostRequest?
    public let submit: CardSubmitHandle?
    public let draftConflict: Bool
    public let actionStatus: String?
    /// The card that replaced this one, when the runtime verified it (`superseded`).
    public let replacementRef: String?

    static func decode(_ json: JSONValue) throws -> CardResponse {
        guard let result = json["result"]?.string, !result.isEmpty else { throw AppFailure.invalidData }
        let batch: CardMutationBatch?
        if case .object? = json["batch"] { batch = try CardMutationBatch.decode(json["batch"] ?? .null) } else { batch = nil }
        return CardResponse(result: result, session: CardJSON.uint(json["session"]), renderAllowed: json["render_allowed"] == .bool(true),
                            fallbackText: json["fallback_text"]?.string ?? "", reason: json["reason"]?.string, batch: batch,
                            hostRequest: try hostRequest(json["host_request"]), submit: submit(json["submit"]),
                            draftConflict: json["draft_conflict"] == .bool(true), actionStatus: json["action_outcome"]?["status"]?.string,
                            replacementRef: json["action_outcome"]?["replacement_ref"]?.string)
    }

    private static func hostRequest(_ json: JSONValue?) throws -> CardHostRequest? {
        guard let json, case .object = json, let kind = json["kind"]?.string else { return nil }
        switch kind {
        case "open_url":
            guard let url = json["url"]?.string, let requestID = json["request_id"]?.string, let slotID = json["slot_id"]?.string,
                  let token = CardJSON.token(json["token"]) else { throw AppFailure.invalidData }
            return .openURL(url: url, requestID: requestID, slotID: slotID, token: token)
        case "approval_decision":
            guard let outcome = json["outcome"]?.string, let requestRef = json["request_ref"]?.string else { throw AppFailure.invalidData }
            return .approvalDecision(outcome: outcome, requestRef: requestRef, taskBinding: json["task_binding"])
        default: return .other(kind: kind)
        }
    }

    private static func submit(_ json: JSONValue?) -> CardSubmitHandle? {
        guard let json, let messageID = json["message_id"]?.string, let version = CardJSON.uint(json["surface_version"]),
              let hash = json["surface_hash"]?.string else { return nil }
        return CardSubmitHandle(messageID: messageID, surfaceVersion: version, surfaceHash: hash)
    }
}

/// Refusals the runtime names through the bus error (`card_session_*`). Anything else is an ordinary failure.
enum CardSessionRefusal: String, Sendable {
    case limit = "card_session_limit"
    case refused = "card_session_refused"
    case inactive = "card_session_inactive"
    case stale = "card_session_stale"
    case imageNative = "card_session_image_native"

    static func of(_ error: any Error) -> CardSessionRefusal? {
        guard let failure = error as? CoreFailure else { return nil }
        let names = [failure.reasonCode, failure.typedName, failure.response?["error"]?["message"]?.string].compactMap { $0 }
        for name in names { if let refusal = CardSessionRefusal(rawValue: name) { return refusal } }
        for name in names { for refusal in [limit, refused, inactive, stale, imageNative] where name.contains(refusal.rawValue) { return refusal } }
        return nil
    }
}

/// Typed `card.session.*` calls. Event, slot and submit are secret-input operations: the proxy sends them through the
/// secret transport, and no body value is logged. Only the submit call touches the network, inside the SDK.
struct CardSessionClient: Sendable {
    let gateway: ProxyGateway

    func open(account: String, surfaceRef: String, locale: String, dark: Bool) async throws -> CardResponse {
        try await view(.cardSessionOpen, account: account, body: ["surface_ref": .string(surfaceRef), "locale": .string(locale), "dark": .bool(dark)])
    }
    func update(account: String, session: UInt64) async throws -> CardResponse {
        try await view(.cardSessionUpdate, account: account, body: ["session": .unsigned(session)])
    }
    func present(account: String, session: UInt64, locale: String, dark: Bool) async throws -> CardResponse {
        try await view(.cardSessionPresent, account: account, body: ["session": .unsigned(session), "locale": .string(locale), "dark": .bool(dark)])
    }
    func event(account: String, session: UInt64, token: CardEventToken, event: CardHostEvent) async throws -> CardResponse {
        try await view(.cardSessionEvent, account: account, body: ["session": .unsigned(session), "token": token.json, "event": event.json])
    }
    func slot(account: String, session: UInt64, token: CardEventToken, slotID: String, requestID: String, outcome: CardSlotOutcome) async throws -> CardResponse {
        try await view(.cardSessionSlot, account: account, body: ["session": .unsigned(session), "token": token.json, "slot_id": .string(slotID),
                                                                       "request_id": .string(requestID), "outcome": .string(outcome.rawValue)])
    }
    func submit(account: String, session: UInt64) async throws -> CardResponse {
        try await view(.cardSessionSubmit, account: account, body: ["session": .unsigned(session)])
    }
    func suspend(account: String, session: UInt64) async throws -> CardResponse {
        try await view(.cardSessionSuspend, account: account, body: ["session": .unsigned(session)])
    }
    func resume(account: String, session: UInt64) async throws -> CardResponse {
        try await view(.cardSessionResume, account: account, body: ["session": .unsigned(session)])
    }
    func dispose(account: String, session: UInt64) async throws -> CardResponse {
        try await view(.cardSessionDispose, account: account, body: ["session": .unsigned(session)])
    }

    private func view(_ operation: SDKOperation, account: String, body: [String: JSONValue]) async throws -> CardResponse {
        // `call` routes secret-input and secret-output operations through the secret transport itself.
        try CardResponse.decode(try await gateway.call(operation, account: account, body: .object(body)))
    }
}
