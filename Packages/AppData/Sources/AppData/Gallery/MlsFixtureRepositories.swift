// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_MLS_GALLERY
import Foundation
import Synchronization

/// The fake of the identity methods for one gallery fixture. It implements the same protocol as the native repository,
/// so the real view models and screens run on it. See `MlsFixture` for why it exists and when it goes.
public final class FixtureContactIdentityRepository: ContactIdentityRepository {
    private struct State {
        var identity: IdentityState
        var change: IdentityChange?
        var security: ConversationSecurity?
        var securityReads = 0
        var acceptCalls = 0
        var started = false
        var sinks: [UUID: AsyncStream<IdentityChange>.Continuation] = [:]
        var watchers: [UUID: AsyncStream<RepositoryUpdate>.Continuation] = [:]
        var tasks: [Task<Void, Never>] = []
    }
    public let fixture: MlsFixture
    private let state: Mutex<State>
    public init(_ fixture: MlsFixture) {
        self.fixture = fixture
        state = Mutex(State(identity: fixture.state, change: fixture.known, security: fixture.security))
    }
    /// Reads of `conversation.security` so far (the F1-9 silent re-read check).
    public var securityReads: Int { state.withLock { $0.securityReads } }
    public var isChanged: Bool { state.withLock { $0.identity == .changed } }
    public func identity(account: String, contact: String) async -> RepositoryResult<IdentityRead> {
        .success(state.withLock { IdentityRead(state: $0.identity, change: $0.change) })
    }
    public func security(account: String, conversation: String) async -> RepositoryResult<ConversationSecurity> {
        state.withLock { $0.securityReads += 1; return $0.security.map { .success($0) } ?? .failure(.unsupported) }
    }
    public func pendingChanges(account: String) async -> [IdentityChange] {
        state.withLock { $0.identity == .changed ? ($0.change.map { [$0] } ?? []) : [] }
    }
    public func accept(account: String, contact: String, newAnchor: String) async -> AcceptOutcome {
        var newer: IdentityChange?
        let outcome: AcceptOutcome = state.withLock { s in
            s.acceptCalls += 1
            switch fixture.accept {
            case .alreadyHandled:
                s.identity = .tofu; s.change = nil
                return .alreadyHandled
            case .mismatchThenAgain where s.acceptCalls == 1:
                // A newer identity arrives while the sheet shows the old one.
                let next = IdentityChange(contact: fixture.contact, username: fixture.contact, previousAnchor: s.change?.newAnchor, newAnchor: "A3", aiFlag: fixture.aiFlag, seenAt: 1_767_258_100)
                newer = next
                return .changedAgain
            case .accept, .mismatchThenAgain:
                guard let change = s.change else { return .alreadyHandled }
                guard change.newAnchor == newAnchor else { return .changedAgain }
                s.identity = .tofu; s.change = nil
                return .accepted
            }
        }
        if let newer { deliver(newer) } else { broadcast() }
        return outcome
    }
    public func changes(account: String) -> AsyncStream<IdentityChange> {
        let (stream, continuation) = AsyncStream<IdentityChange>.makeStream(bufferingPolicy: .bufferingNewest(8))
        let id = UUID()
        state.withLock { $0.sinks[id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.state.withLock { $0.sinks[id] = nil } }
        startScript()
        return stream
    }
    public func observe(account: String) async -> RepositoryObservation {
        let (stream, continuation) = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        state.withLock { $0.watchers[id] = continuation }
        continuation.yield(.invalidated)
        startScript()
        return RepositoryObservation(stream: stream, onStop: { [weak self] in self?.state.withLock { $0.watchers[id] = nil }; continuation.finish() })
    }
    /// Starts the scripted events once, on the first consumer: the identity event, the later security answer and the
    /// devices-changed event.
    private func startScript() {
        guard state.withLock({ s in let first = !s.started; s.started = true; return first }) else { return }
        var tasks: [Task<Void, Never>] = []
        if let event = fixture.event {
            tasks.append(Task { [weak self] in try? await Task.sleep(for: event.after); if !Task.isCancelled { self?.deliver(event.change) } })
        }
        if let later = fixture.laterSecurity {
            tasks.append(Task { [weak self] in try? await Task.sleep(for: later.after); if !Task.isCancelled { self?.state.withLock { $0.security = later.value }; self?.broadcast() } })
        }
        if let after = fixture.devicesChangedAfter, fixture.laterSecurity == nil {
            tasks.append(Task { [weak self] in try? await Task.sleep(for: after); if !Task.isCancelled { self?.broadcast() } })
        }
        state.withLock { $0.tasks = tasks }
    }
    private func deliver(_ change: IdentityChange) {
        let sinks = state.withLock { s -> [AsyncStream<IdentityChange>.Continuation] in s.identity = .changed; s.change = change; return Array(s.sinks.values) }
        for sink in sinks { sink.yield(change) }
        broadcast()
    }
    private func broadcast() {
        let watchers = state.withLock { Array($0.watchers.values) }
        for watcher in watchers { watcher.yield(.invalidated) }
    }
    deinit { state.withLock { $0.tasks }.forEach { $0.cancel() } }
}

/// A direct chat with two messages. A send while the peer's identity is changed is refused as the SDK refuses it
/// (`identity_change_pending`) and stays as a failed outbox row; a manual retry after the acceptance is admitted.
public final class FixtureChatRepository: ChatRepository {
    private struct State { var sent: [MessageRecord] = []; var outbox: [OutboxEntry] = [] }
    private let fixture: MlsFixture
    private let identity: FixtureContactIdentityRepository
    private let state = Mutex(State())
    public init(_ fixture: MlsFixture, identity: FixtureContactIdentityRepository) { self.fixture = fixture; self.identity = identity }
    public func unavailable(_ capability: ChatCapability) -> AppFailure { ChatUnavailable.failure(capability) }
    public func messages(account: String, conversation: String, before: MessageCursor?) async -> RepositoryResult<MessageWindowPage> {
        let base = [
            MessageRecord(id: "m2", sender: "", kind: .text("Hi, are you there?"), isOwn: true, timestamp: 1_767_258_000, delivery: .delivered),
            MessageRecord(id: "m1", sender: fixture.name, kind: .text("Hello."), isOwn: false, timestamp: 1_767_257_000),
        ]
        return .success(MessageWindowPage(records: state.withLock { $0.sent.reversed() } + base))
    }
    public func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> {
        await enqueue(account: account, conversation: conversation, text: text, operationID: operationID).map { $0.first ?? SendOutcome(messageID: operationID, state: .failed) }
    }
    public func enqueue(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<[SendOutcome]> {
        let entry = OutboxEntry(operationID: operationID, text: text, created: Int64(Date().timeIntervalSince1970), state: .queued)
        return .success(attempt(entry))
    }
    public func outbox(account: String, conversation: String) async -> [OutboxEntry] { state.withLock { $0.outbox } }
    public func retryOutbox(account: String, conversation: String, operationID: String) async -> [SendOutcome] {
        guard let entry = state.withLock({ s in s.outbox.first { $0.operationID == operationID } }) else { return [] }
        state.withLock { s in s.outbox.removeAll { $0.operationID == operationID } }
        return attempt(entry)
    }
    public func discardOutbox(account: String, conversation: String, operationID: String) async -> Bool {
        state.withLock { s in let before = s.outbox.count; s.outbox.removeAll { $0.operationID == operationID }; return s.outbox.count < before }
    }
    private func attempt(_ entry: OutboxEntry) -> [SendOutcome] {
        var failed = entry
        if identity.isChanged {
            failed.state = .failed(.identityChangePending(fixture.contact))
            state.withLock { $0.outbox.append(failed) }
            return []
        }
        state.withLock { s in
            s.sent.append(MessageRecord(id: "sent-" + entry.operationID, sender: "", kind: .text(entry.text), isOwn: true, timestamp: entry.created, delivery: .sent))
        }
        return [SendOutcome(messageID: "sent-" + entry.operationID, state: .submitted)]
    }
    public func edit(account: String, conversation: String, message: String, text: String, expectedRevision: Int64, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    public func reply(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    public func react(account: String, conversation: String, message: String, token: String, remove: Bool, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    public func delete(account: String, conversation: String, message: String, scope: MessageDeleteScope, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    public func details(account: String, conversation: String, peerAnchor: String?) async -> RepositoryResult<ChatDetails> {
        .success(ChatDetails(muted: false, peerPrincipal: fixture.contact, peerName: fixture.name))
    }
    public func observe(account: String) async -> RepositoryObservation { openObservation() }
}

/// The contact list of one fixture (one contact), for the profile screen.
public struct FixtureContactsRepository: ContactsRepository {
    private let fixture: MlsFixture
    public init(_ fixture: MlsFixture) { self.fixture = fixture }
    public func contacts(account: String) async -> RepositoryResult<[ContactRecord]> {
        .success([ContactRecord(id: fixture.contact, displayName: fixture.name, subtitle: fixture.contact, rootCommitment: "root-" + fixture.contact, linkID: "link-" + fixture.contact, classification: fixture.aiFlag ? .aiAgent : .person)])
    }
    public func requests(account: String) async -> RepositoryResult<[ContactRequestRecord]> { .success([]) }
    public func add(account: String, principal: String, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    public func decide(account: String, request: String, decision: ContactDecision, operationID: String) async -> RepositoryResult<Void> { .failure(.unsupported) }
    public func observe(account: String) async -> RepositoryObservation { openObservation() }
    public func unavailable(_ capability: ContactUnavailable) -> AppFailure { .unsupported }
}

/// The conversation list of one fixture (one direct row), for the list badge.
public struct FixtureConversationsRepository: ConversationsRepository {
    private let fixture: MlsFixture
    private let identity: FixtureContactIdentityRepository
    public init(_ fixture: MlsFixture, identity: FixtureContactIdentityRepository) { self.fixture = fixture; self.identity = identity }
    public func page(account: String, cursor: String?, limit: Int) async -> RepositoryResult<ConversationPage> {
        .success(ConversationPage(rows: [ConversationRecord(id: MlsFixtureRepositories.conversationID(fixture), title: fixture.name, preview: "Hello.", timeLabel: "10:24", classification: fixture.aiFlag ? .aiAgent : .person, peer: fixture.contact)], nextCursor: nil))
    }
    public func pendingRequests(account: String) async -> RepositoryResult<UInt> { .success(0) }
    public func search(account: String, query: String) async -> RepositoryResult<[ConversationRecord]> { .failure(.unsupported) }
    /// An identity event reloads the list, as the hub reloads it for the topic at the SDK.
    public func observe(account: String) async -> RepositoryObservation { await identity.observe(account: account) }
}

/// An observation that stays open and never reports anything.
private func openObservation() -> RepositoryObservation {
    let (stream, continuation) = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
    return RepositoryObservation(stream: stream, onStop: { continuation.finish() })
}

/// The repositories of one opened fixture. Each screen builds its own, so a script starts again on every open.
public struct MlsFixtureRepositories: Sendable {
    public static let account = "gallery"
    public static func conversationID(_ fixture: MlsFixture) -> String { "mls-" + fixture.id }
    public let fixture: MlsFixture
    public let identity: FixtureContactIdentityRepository
    public let chat: FixtureChatRepository
    public let contacts: FixtureContactsRepository
    public let conversations: FixtureConversationsRepository
    public var conversationID: String { Self.conversationID(fixture) }
    public init(_ fixture: MlsFixture) {
        self.fixture = fixture
        let identity = FixtureContactIdentityRepository(fixture)
        self.identity = identity; chat = FixtureChatRepository(fixture, identity: identity); contacts = FixtureContactsRepository(fixture); conversations = FixtureConversationsRepository(fixture, identity: identity)
    }
}
#endif
