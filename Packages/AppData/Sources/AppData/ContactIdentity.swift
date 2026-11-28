// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// What the SDK says about a direct contact's identity (`contact.verification.status` → `identity_state`).
/// There is no "mark verified" action: `verified` is reported by the SDK, never set from the UI.
public enum IdentityState: Equatable, Sendable {
    case verified, tofu, changed
    /// A value this client does not know (or no value at all). Shown like `tofu`, with no badge.
    case unknown(String)
    public init(raw: String?) {
        switch raw {
        case "verified": self = .verified
        case "tofu": self = .tofu
        case "changed": self = .changed
        default: self = .unknown(String((raw ?? "").prefix(64)))
        }
    }
    public var isChanged: Bool { self == .changed }
}

/// A contact's identity that changed and has not been accepted. `newAnchor` is what an accept must name.
public struct IdentityChange: Equatable, Sendable {
    public let contact: String
    public let username: String?
    public let previousAnchor: String?
    public let newAnchor: String
    /// From the SDK `ai_flag` only, never guessed from a name.
    public let aiFlag: Bool
    /// Unix seconds when this client learned of the change.
    public let seenAt: Int64
    public init(contact: String, username: String? = nil, previousAnchor: String? = nil, newAnchor: String, aiFlag: Bool = false, seenAt: Int64 = 0) {
        self.contact = contact; self.username = username; self.previousAnchor = previousAnchor; self.newAnchor = newAnchor; self.aiFlag = aiFlag; self.seenAt = seenAt
    }
}

/// One status read: the state, and the pending change when its new anchor is known. `changed` with no
/// `change` is the "waiting for the new identity" case.
public struct IdentityRead: Equatable, Sendable {
    public let state: IdentityState
    public let change: IdentityChange?
    public init(state: IdentityState, change: IdentityChange? = nil) { self.state = state; self.change = change }
}

/// `conversation.security`: what the encryption section of a conversation shows.
public struct ConversationSecurity: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case ok, pending, reEstablished
        case unknown(String)
    }
    public enum Warning: Equatable, Sendable {
        case forkRecovered
        case unknown(String)
    }
    public let state: State
    public let epoch: UInt64
    /// Devices listed in `members`. For a direct chat the list is taken to be the peer's devices (checked at the pin).
    public let peerDevices: Int
    /// Any listed member carries the SDK `ai_flag`.
    public let anyAI: Bool
    public let warning: Warning?
    public init(state: State, epoch: UInt64, peerDevices: Int, anyAI: Bool = false, warning: Warning? = nil) {
        self.state = state; self.epoch = epoch; self.peerDevices = peerDevices; self.anyAI = anyAI; self.warning = warning
    }
}

/// The result of `contact.trust.accept_change`.
public enum AcceptOutcome: Equatable, Sendable {
    case accepted
    /// `no_pending_change`: someone or something handled it already.
    case alreadyHandled
    /// `anchor_mismatch`: a newer change exists; the user must review it again.
    case changedAgain
    case failed(AppFailure)
}

/// A send the SDK refused before the contact's changed identity is accepted (`identity_change_pending`).
public enum SendBlock: Equatable, Sendable {
    case identityChangePending(contact: String)
    public init?(failure: AppFailure) {
        guard case .identityChangePending(let contact) = failure else { return nil }
        self = .identityChangePending(contact: contact)
    }
    public var contact: String { switch self { case .identityChangePending(let contact): contact } }
}

public protocol ContactIdentityRepository: Sendable {
    /// The contact's identity state, and the pending change when its new anchor is known.
    func identity(account: String, contact: String) async -> RepositoryResult<IdentityRead>
    func security(account: String, conversation: String) async -> RepositoryResult<ConversationSecurity>
    /// Accepts the changed identity whose new anchor the user saw. Called from one place only: the Accept action of the
    /// identity change sheet. Never retried and never called without a tap.
    func accept(account: String, contact: String, newAnchor: String) async -> AcceptOutcome
    /// Identity changes as they arrive (`contact.identity_changed`).
    func changes(account: String) -> AsyncStream<IdentityChange>
    /// Invalidations for identity changes and `conversation.devices_changed`; screens re-read silently.
    func observe(account: String) async -> RepositoryObservation
}

/// Pure parsers over the response objects and event payloads of the identity methods. Nothing here logs a payload.
public enum ContactIdentityParsing {
    static let maxText = 4096
    private static func text(_ value: JSONValue?, limit: Int = maxText) -> String? {
        guard let value = value?.string, !value.isEmpty, value.utf8.count <= limit else { return nil }
        return value
    }
    private static func unsigned(_ value: JSONValue?) -> UInt64? {
        switch value {
        case .unsigned(let number): number
        case .number(let number): UInt64(exactly: number)
        case .string(let text): UInt64(text)
        default: nil
        }
    }
    /// `contact.verification.status`: `identity_state`, and the pending change when the SDK names `pending_anchor`.
    public static func status(_ body: JSONValue, contact: String, now: Int64) -> IdentityRead {
        let state = IdentityState(raw: body["identity_state"]?.string)
        guard state == .changed, let anchor = text(body["pending_anchor"]) ?? text(body["new_anchor"]) else { return IdentityRead(state: state) }
        return IdentityRead(state: state, change: IdentityChange(contact: contact, username: text(body["username"], limit: 256), previousAnchor: text(body["previous_anchor"]), newAnchor: anchor, aiFlag: body["ai_flag"] == .bool(true), seenAt: now))
    }
    /// The body of `contact.identity_changed`; nil when it lacks the contact or the new anchor.
    public static func change(_ body: JSONValue, now: Int64) -> IdentityChange? {
        guard let contact = text(body["contact"], limit: 2048), let anchor = text(body["new_anchor"]) else { return nil }
        return IdentityChange(contact: contact, username: text(body["username"], limit: 256), previousAnchor: text(body["previous_anchor"]), newAnchor: anchor, aiFlag: body["ai_flag"] == .bool(true), seenAt: now)
    }
    /// `conversation.security`.
    public static func security(_ body: JSONValue) throws -> ConversationSecurity {
        guard let raw = body["state"]?.string else { throw AppFailure.invalidData }
        let state: ConversationSecurity.State = switch raw {
        case "ok": .ok
        case "pending": .pending
        case "re_established": .reEstablished
        default: .unknown(String(raw.prefix(64)))
        }
        var devices = 0, anyAI = false
        if case .array(let members)? = body["members"] {
            devices = min(members.count, 4096)
            anyAI = members.prefix(4096).contains { $0["ai_flag"] == .bool(true) }
        }
        var warning: ConversationSecurity.Warning?
        if let code = body["warning"]?["code"]?.string { warning = code == "fork_recovered" ? .forkRecovered : .unknown(String(code.prefix(64))) }
        return ConversationSecurity(state: state, epoch: unsigned(body["epoch"]) ?? 0, peerDevices: devices, anyAI: anyAI, warning: warning)
    }
    /// The reply of `contact.trust.accept_change`.
    public static func accepted(_ body: JSONValue) -> AcceptOutcome {
        body["state"] == .string("accepted") ? .accepted : .failed(.invalidData)
    }
    /// A refusal of `contact.trust.accept_change`: the two typed codes, anything else a plain failure.
    public static func acceptRefusal(_ error: any Error) -> AcceptOutcome {
        if let failure = error as? CoreFailure {
            if codes(failure).contains("no_pending_change") { return .alreadyHandled }
            if codes(failure).contains("anchor_mismatch") { return .changedAgain }
        }
        return .failed(AppFailure.map(error))
    }
    /// `identity_change_pending{contact}` on a send; nil for every other failure.
    public static func sendBlock(_ failure: CoreFailure) -> SendBlock? {
        guard codes(failure).contains("identity_change_pending") else { return nil }
        let error = failure.response?["error"]
        guard let contact = text(error?["details"]?["contact"], limit: 2048) ?? text(error?["contact"], limit: 2048) ?? text(failure.response?["details"]?["contact"], limit: 2048) else { return nil }
        return .identityChangePending(contact: contact)
    }
    private static func codes(_ failure: CoreFailure) -> [String] {
        let error = failure.response?["error"]
        return [failure.typedName, failure.reasonCode, failure.reason, error?["code"]?.string, error?["reason_code"]?.string].compactMap { $0 }
    }
}

/// The latest unaccepted change per contact, kept in memory from `contact.identity_changed` events. Core does not yet
/// return the pending anchor on a status read, so a screen that opens after the event still needs it from here.
actor IdentityMemory {
    private var changes: [String: [String: IdentityChange]] = [:]
    private static let limit = 256
    func store(_ change: IdentityChange, account: String) {
        var rows = changes[account] ?? [:]
        if rows[change.contact] == nil, rows.count >= Self.limit, let oldest = rows.min(by: { $0.value.seenAt < $1.value.seenAt })?.key { rows[oldest] = nil }
        rows[change.contact] = change; changes[account] = rows
    }
    func latest(account: String, keys: [String]) -> IdentityChange? { keys.lazy.compactMap { self.changes[account]?[$0] }.first }
    func clear(account: String, keys: [String]) { for key in keys { changes[account]?[key] = nil } }
}

public struct NativeContactIdentityRepository: ContactIdentityRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    private let contacts: any ContactsRepository
    private let memory = IdentityMemory()
    public init(client: RamfluxClient, updates: NativeUpdateSource, contacts: any ContactsRepository) {
        gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates; self.contacts = contacts
    }
    public func identity(account: String, contact: String) async -> RepositoryResult<IdentityRead> {
        // `contact.verification.status` takes the contact's identity commitment.
        guard case .success(let row) = await contacts.contact(account: account, id: contact), let root = row?.rootCommitment else { return .failure(.unavailableResource("contacts.unavailable.identityCommitment")) }
        do {
            let body = try await gateway.call(.contactVerificationStatus, account: account, body: .object(["contact_identity_commitment": .string(root)]))
            var read = ContactIdentityParsing.status(body, contact: contact, now: Int64(Date().timeIntervalSince1970))
            if read.state != .changed { await memory.clear(account: account, keys: [contact, root]); return .success(read) }
            if read.change == nil, let known = await memory.latest(account: account, keys: [contact, root]) { read = IdentityRead(state: .changed, change: known) }
            return .success(read)
        } catch { EventDiagnostics.failed("contact.verification.status", error); return .failure(AppFailure.map(error)) }
    }
    public func security(account: String, conversation: String) async -> RepositoryResult<ConversationSecurity> {
        // W: SDKOperation.conversationSecurity after the pin; parse the reply with ContactIdentityParsing.security.
        .failure(.unsupported)
    }
    public func accept(account: String, contact: String, newAnchor: String) async -> AcceptOutcome {
        // W: SDKOperation.contactTrustAcceptChange after the pin, body {contact, new_anchor}; parse with
        // ContactIdentityParsing.accepted and ContactIdentityParsing.acceptRefusal.
        .failed(.unsupported)
    }
    public func changes(account: String) -> AsyncStream<IdentityChange> {
        let (stream, continuation) = AsyncStream<IdentityChange>.makeStream(bufferingPolicy: .bufferingNewest(16))
        let updates = updates, memory = memory
        let pump = Task {
            let hub = await updates.observe(account: account, eventFrames: true)
            if let events = hub.events {
                for await frame in events where frame.topic == NativeUpdateSource.identityChangedTopic {
                    guard let body = try? JSONDecoder().decode(JSONValue.self, from: frame.body), let change = ContactIdentityParsing.change(body, now: Int64(Date().timeIntervalSince1970)) else { continue }
                    await memory.store(change, account: account)
                    continuation.yield(change)
                }
            }
            await hub.stop(); continuation.finish()
        }
        continuation.onTermination = { _ in pump.cancel() }
        return stream
    }
    public func observe(account: String) async -> RepositoryObservation {
        let hub = await updates.observe(account: account, eventFrames: true)
        let (stream, continuation) = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let memory = memory
        let pump = Task {
            continuation.yield(.invalidated)
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await update in hub.stream { if case .failed = update { continuation.yield(update) } } }
                group.addTask {
                    guard let events = hub.events else { return }
                    for await frame in events {
                        if frame.topic == NativeUpdateSource.identityChangedTopic,
                           let body = try? JSONDecoder().decode(JSONValue.self, from: frame.body), let change = ContactIdentityParsing.change(body, now: Int64(Date().timeIntervalSince1970)) { await memory.store(change, account: account) }
                        continuation.yield(.invalidated)
                    }
                }
            }
            continuation.finish()
        }
        return RepositoryObservation(stream: stream, onStop: { pump.cancel(); await hub.stop(); continuation.finish() })
    }
}

public struct UnavailableContactIdentityRepository: ContactIdentityRepository {
    public init() {}
    public func identity(account: String, contact: String) async -> RepositoryResult<IdentityRead> { .failure(.sdkUnavailable) }
    public func security(account: String, conversation: String) async -> RepositoryResult<ConversationSecurity> { .failure(.sdkUnavailable) }
    public func accept(account: String, contact: String, newAnchor: String) async -> AcceptOutcome { .failed(.sdkUnavailable) }
    public func changes(account: String) -> AsyncStream<IdentityChange> { AsyncStream { $0.finish() } }
    public func observe(account: String) async -> RepositoryObservation { RepositoryObservation(failure: .sdkUnavailable) }
}
