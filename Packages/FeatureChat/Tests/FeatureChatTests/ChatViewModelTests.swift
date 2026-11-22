// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import Foundation
@testable import AppData
@testable import FeatureChat

func record(_ id: String, own: Bool = false, text: String? = nil, ms: Int64, anchor: String? = nil) -> MessageRecord {
    MessageRecord(id: id, sender: own ? "" : "peer", kind: .text(text ?? id), isOwn: own, timestamp: ms / 1000, authorAnchor: anchor ?? (own ? nil : "peer-anchor"), order: MessageOrder(milliseconds: ms))
}

/// A history of `count` rows served newest first in pages, with the real outbox actor.
actor ChatFake: ChatRepository {
    private(set) var attempts: [(String, String)] = []
    private(set) var deletes: [(String, MessageDeleteScope)] = []
    private(set) var edits: [(String, String, String)] = []
    private(set) var replies: [(String, String, String)] = []
    private(set) var reactions: [(String, String, Bool, String)] = []
    private(set) var reads: [String] = []
    private(set) var typing: [Bool] = []
    private(set) var pageRequests: [Int?] = []
    private(set) var changeRequests: [UInt64] = []
    private(set) var muted: [Bool] = []
    let sends = RetainedMutation<String, SendOutcome>()
    let queue = ChatOutbox()
    let gate: MutationGate?
    var online = false
    var history: [MessageRecord]
    var pageSize = 50
    var journal: UInt64 = 7
    var pendingChanges: [MessageChangeBatch.Change] = []
    var editResult: RepositoryResult<Void> = .success(())
    var detailResult: RepositoryResult<ChatDetails> = .success(ChatDetails(muted: false, peerPrincipal: "lin", peerName: "Lin"))
    init(gate: MutationGate? = nil, history: [MessageRecord] = [record("m", ms: 1_000)]) { self.gate = gate; self.history = history }
    func setHistory(_ rows: [MessageRecord]) { history = rows }
    func setOnline(_ value: Bool) { online = value }
    func setEditResult(_ result: RepositoryResult<Void>) { editResult = result }
    func push(_ changes: [MessageChangeBatch.Change]) { pendingChanges += changes }
    nonisolated func unavailable(_ capability: ChatCapability) -> AppFailure { .unsupported }
    func messages(account: String, conversation: String, before: MessageCursor?) -> RepositoryResult<MessageWindowPage> {
        let start = before.map { cursorOffset($0) } ?? 0
        pageRequests.append(before == nil ? nil : start)
        let rows = Array(history.dropFirst(start).prefix(pageSize))
        let next = start + rows.count < history.count ? cursor(start + rows.count) : nil
        return .success(MessageWindowPage(records: rows, nextBefore: next, snapshotSequence: journal))
    }
    func changes(account: String, conversation: String, after: UInt64) -> RepositoryResult<MessageChangeBatch> {
        changeRequests.append(after)
        let batch = MessageChangeBatch(changes: pendingChanges, nextAfter: after + UInt64(pendingChanges.count), more: false)
        pendingChanges = []
        return .success(batch)
    }
    func sendState(account: String, conversation: String) async -> PendingChatSend? {
        guard let row = await sends.snapshot(scope: account + conversation) else { return nil }
        return PendingChatSend(operationID: row.operationID, text: row.arguments, unresolved: row.unresolved, result: row.result)
    }
    func send(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<SendOutcome> {
        await sends.run(scope: account + conversation, arguments: text, operationID: operationID) { await self.perform(text: text, operationID: operationID) }
    }
    private func perform(text: String, operationID: String) async -> RepositoryResult<SendOutcome> {
        attempts.append((operationID, text)); if attempts.count == 1, let gate { await gate.wait() }
        return online ? .success(SendOutcome(messageID: "event-" + operationID, state: .submitted)) : .failure(.offline)
    }
    func outbox(account: String, conversation: String) async -> [OutboxEntry] { await queue.entries(account, conversation) }
    func enqueue(account: String, conversation: String, text: String, operationID: String) async -> RepositoryResult<[SendOutcome]> {
        await queue.enqueue(account, conversation, entry: OutboxEntry(operationID: operationID, text: text, created: 0, state: .queued))
        return .success(await flushOutbox(account: account, conversation: conversation))
    }
    func enqueueMedia(account: String, conversation: String, groupID: String?, caption: String, items: [MediaUpload], operationID: String) async -> RepositoryResult<[SendOutcome]> {
        await queue.enqueue(account, conversation, entry: OutboxEntry(operationID: operationID, text: caption, created: 0, state: .queued, groupID: groupID, media: items))
        return .success(await flushOutbox(account: account, conversation: conversation))
    }
    func flushOutbox(account: String, conversation: String) async -> [SendOutcome] {
        await queue.flush(account, conversation) { entry in
            if entry.media.isEmpty { return await self.send(account: account, conversation: conversation, text: entry.text, operationID: entry.operationID) }
            return await self.recordMedia(entry)
        }
    }
    private func recordMedia(_ entry: OutboxEntry) -> RepositoryResult<SendOutcome> { mediaSends.append((entry.operationID, entry.media)); captions.append(entry.text); return mediaSendResult }
    func retryOutbox(account: String, conversation: String, operationID: String) async -> [SendOutcome] {
        await queue.requeue(account, conversation, operationID: operationID); return await flushOutbox(account: account, conversation: conversation)
    }
    func discardOutbox(account: String, conversation: String, operationID: String) async -> Bool {
        guard let entry = await queue.discard(account, conversation, operationID: operationID) else { return false }
        for item in entry.media { try? FileManager.default.removeItem(at: item.file) }
        return true
    }
    func edit(account: String, conversation: String, message: String, text: String, operationID: String) -> RepositoryResult<Void> { edits.append((message, text, operationID)); return editResult }
    private var retainedReply: PendingChatMutation?
    func reply(account: String, conversation: String, message: String, text: String, operationID: String) async -> RepositoryResult<Void> {
        replies.append((message, text, operationID))
        if gate != nil, replies.count == 1 {
            retainedReply = PendingChatMutation(operationID: operationID, key: ChatMutationKey(kind: .reply, message: message, text: text), unresolved: true)
            await gate?.wait()
            return .failure(.outcomeUnknown)
        }
        return .success(())
    }
    func mutationState(account: String, conversation: String) async -> PendingChatMutation? { retainedReply }
    func react(account: String, conversation: String, message: String, token: String, remove: Bool, operationID: String) -> RepositoryResult<Void> { reactions.append((message, token, remove, operationID)); return .success(()) }
    var deleteResult: RepositoryResult<Void> = .success(())
    func setDeleteResult(_ result: RepositoryResult<Void>) { deleteResult = result }
    func delete(account: String, conversation: String, message: String, scope: MessageDeleteScope, operationID: String) -> RepositoryResult<Void> { deletes.append((message, scope)); return deleteResult }
    func markRead(account: String, conversation: String, message: String) -> RepositoryResult<Void> { reads.append(message); return .success(()) }
    func setTyping(account: String, conversation: String, active: Bool) -> RepositoryResult<Void> { typing.append(active); return .success(()) }
    func details(account: String, conversation: String, peerAnchor: String?) -> RepositoryResult<ChatDetails> { detailResult }
    func setMuted(account: String, conversation: String, muted value: Bool, operationID: String) -> RepositoryResult<Bool> { muted.append(value); return .success(value) }
    private(set) var downloads: [String] = []
    private(set) var revokes: [String] = []
    private(set) var mediaSends: [(String, [MediaUpload])] = []
    private(set) var captions: [String] = []
    private(set) var forwards: [(String, [AttachmentRecord], String, String?)] = []
    private(set) var shared: [(URL, String)] = []
    private(set) var shareRemovals = 0
    var stored: [String: URL] = [:]
    var downloadResult: MediaTransferState?
    var mediaSendResult: RepositoryResult<SendOutcome> = .success(SendOutcome(messageID: "media-event", state: .submitted))
    let outboxDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("chat-outbox-\(UUID().uuidString)", isDirectory: true)
    func setDetails(_ result: RepositoryResult<ChatDetails>) { detailResult = result }
    func setStored(_ id: String, _ url: URL) { stored[id] = url }
    func setDownloadResult(_ state: MediaTransferState) { downloadResult = state }
    func setMediaSendResult(_ result: RepositoryResult<SendOutcome>) { mediaSendResult = result }
    func mediaState(account: String, attachment: AttachmentRecord) -> MediaTransferState? { stored[attachment.id].map { .ready($0) } }
    func download(account: String, attachment: AttachmentRecord) -> MediaTransferState {
        downloads.append(attachment.id)
        return downloadResult ?? .ready(FileManager.default.temporaryDirectory.appendingPathComponent(attachment.id))
    }
    func mediaOutbox(account: String) -> URL? { try? FileManager.default.createDirectory(at: outboxDirectory, withIntermediateDirectories: true); return outboxDirectory }
    private(set) var purgedConversations: [String] = []
    private(set) var accountPurges = 0
    var storedBytes: Int64 = 4_096
    func mediaUsage(account: String, conversation: String) -> Int64 { storedBytes }
    func mediaUsage(account: String) -> MediaUsage { MediaUsage(originals: storedBytes, outbox: 10) }
    func purgeConversationMedia(account: String, conversation: String) { purgedConversations.append(conversation); storedBytes = 0 }
    func purgeAccountMedia(account: String) { accountPurges += 1; storedBytes = 0 }
    func shareCopy(account: String, file: URL, name: String) -> URL? { shared.append((file, name)); return file.deletingLastPathComponent().appendingPathComponent(name) }
    func removeShareCopy(account: String) { shareRemovals += 1 }
    func forward(account: String, text: String, attachments: [AttachmentRecord], to conversation: String, groupID: String?, operationID: String) -> RepositoryResult<[SendOutcome]> {
        forwards.append((text, attachments, conversation, groupID)); return .success([SendOutcome(messageID: "forwarded", state: .submitted)])
    }
    func revokeMedia(account: String, message: String) -> RepositoryResult<Void> { revokes.append(message); return .success(()) }
    func draft(account: String, conversation: String) async -> String { await queue.draft(account, conversation) }
    func saveDraft(account: String, conversation: String, text: String) async { await queue.saveDraft(account, conversation, text: text) }
    private var listeners: [AsyncStream<RepositoryUpdate>.Continuation] = []
    func observe(account: String) -> RepositoryObservation {
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        listeners.append(pair.continuation)
        return RepositoryObservation(stream: pair.stream, onStop: { pair.continuation.finish() })
    }
    var observers: Int { listeners.count }
    func invalidate() { for listener in listeners { listener.yield(.invalidated) } }
    private func cursor(_ offset: Int) -> MessageCursor { MessageWindowPage.testCursor(offset) }
    private func cursorOffset(_ cursor: MessageCursor) -> Int { MessageWindowPage.testOffset(cursor) }
}
extension MessageWindowPage {
    static func testCursor(_ offset: Int) -> MessageCursor { MessageCursor(value: .number(Double(offset))) }
    static func testOffset(_ cursor: MessageCursor) -> Int { if case .number(let value) = cursor.value { Int(value) } else { 0 } }
}

@Suite(.timeLimit(.minutes(1))) @MainActor struct ChatViewModelTests {
    @Test func offlineSendsQueueInOrderSurviveTheScreenAndRetryWithTheirKeys() async {
        let fake = ChatFake()
        let a = ChatCoordinator(repository: fake, account: "a", conversation: "A")
        a.send(.appeared); await a.viewModel.settle()
        a.send(.draftChanged("first")); a.send(.send); await a.viewModel.settle()
        #expect(a.viewModel.state.draft.isEmpty)
        a.send(.draftChanged("second")); a.send(.send); await a.viewModel.settle()
        #expect(a.viewModel.state.outbox.map(\.text) == ["first", "second"])
        #expect(a.viewModel.state.outbox.allSatisfy { $0.state == .queued }); #expect(a.viewModel.state.offline)
        #expect(a.viewModel.state.messages.map(\.id) == ["m"])
        a.send(.conceal)
        let returned = ChatCoordinator(repository: fake, account: "a", conversation: "A")
        await fake.setOnline(true)
        returned.send(.appeared); await returned.viewModel.settle()
        #expect(returned.viewModel.state.outbox.isEmpty); #expect(!returned.viewModel.state.offline)
        let attempts = await fake.attempts
        let firstKey = attempts.first?.0
        #expect(attempts.filter { $0.1 == "first" }.allSatisfy { $0.0 == firstKey })
        #expect(attempts.map(\.1).last == "second")
        #expect(Set(attempts.filter { $0.1 == "second" }.map(\.0)).count == 1)
        returned.send(.conceal)
    }
    @Test func aSendThatCannotBeQueuedReturnsItsTextToTheComposer() async {
        let model = ChatViewModel(repository: UnavailableChatRepository(), account: "a", conversation: "c", emit: { _ in })
        model.send(.draftChanged("Keep")); model.send(.send); await model.settle()
        #expect(model.state.messages.isEmpty); #expect(model.state.outbox.isEmpty); #expect(model.state.draft == "Keep"); #expect(model.state.failure == .sdkUnavailable)
    }
    @Test func partialReplySurvivesNavigationAndRetriesTheSameKey() async {
        let gate = MutationGate(), fake = ChatFake(gate: gate)
        defer { gate.release() }
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.refresh); await model.settle()
        model.send(.beginReply("m")); model.send(.draftChanged("Reply text")); model.send(.send)
        var entered = gate.entered.stream.makeAsyncIterator(); _ = await entered.next()
        let operation = await fake.replies.first?.2
        model.send(.conceal)
        let returned = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        returned.send(.refresh); await returned.settle()
        #expect(returned.state.held == .revision(operationID: operation ?? "", messageID: "m", text: "Reply text", reply: true))
        gate.release(); await model.settle()
        returned.send(.retrySameSend); await returned.settle()
        let replies = await fake.replies
        #expect(replies.count == 2); #expect(replies.first?.2 == replies.last?.2); #expect(replies.last?.1 == "Reply text")
        returned.send(.conceal)
    }
    @Test func deletionRequiresKnownSelectionThenExplicitConfirmation() async {
        let fake = ChatFake(); let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.refresh); await model.settle()
        model.send(.requestDelete("unknown", .local)); model.send(.confirmDelete); await model.settle(); #expect(await fake.deletes.isEmpty)
        model.send(.requestDelete("m", .everyone)); model.send(.confirmDelete); await model.settle(); #expect(await fake.deletes.isEmpty)
        model.send(.requestDelete("m", .local)); #expect(await fake.deletes.isEmpty)
        model.send(.confirmDelete); await model.settle()
        let deletes = await fake.deletes
        #expect(deletes.count == 1); #expect(deletes.first?.0 == "m"); #expect(deletes.first?.1 == .local)
        model.send(.disappeared)
    }
    @Test func replyKeepsDraftAndEditRestoresItUnlessTheEditIsRefused() async {
        let fake = ChatFake(history: [record("m", ms: 2_000), record("mine", own: true, text: "Hello", ms: 1_000)])
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.refresh); await model.settle()
        model.send(.draftChanged("Draft")); model.send(.beginReply("m"))
        #expect(model.state.draft == "Draft")
        model.send(.send); await model.settle()
        let replies = await fake.replies
        #expect(replies.count == 1); #expect(replies.first?.0 == "m"); #expect(replies.first?.1 == "Draft")
        #expect(model.state.composer == nil); #expect(model.state.draft.isEmpty)
        model.send(.draftChanged("Draft")); model.send(.beginEdit("m")); #expect(model.state.draft == "Draft")
        model.send(.beginEdit("mine")); #expect(model.state.draft == "Hello")
        model.send(.draftChanged("Hello there")); await fake.setEditResult(.failure(.typedRefusal("edit_conflict")))
        model.send(.send); await model.settle()
        #expect(model.state.failure == .typedRefusal("edit_conflict"))
        #expect(model.state.composer == .edit(messageID: "mine", previousDraft: "Draft"))
        #expect(model.state.draft == "Hello there"); #expect(model.state.held == nil)
        await fake.setEditResult(.failure(.outcomeUnknown))
        model.send(.send); await model.settle()
        let first = await fake.edits.last?.2
        model.send(.retrySameSend); await model.settle()
        let second = await fake.edits.last?.2
        #expect(first == second); #expect(model.state.failure == .outcomeUnknown); #expect(model.state.composer != nil)
        await fake.setEditResult(.success(()))
        model.send(.retrySameSend); await model.settle()
        #expect(model.state.draft == "Draft"); #expect(model.state.composer == nil)
        model.send(.openActions("m")); #expect(model.state.actionTarget == "m")
        model.send(.chooseReaction("👍")); await model.settle(); #expect(model.state.actionTarget == nil)
        model.send(.beginReact("mine")); model.send(.reactionMode(true)); model.send(.removeReaction("🎉")); await model.settle()
        model.send(.beginReact("mine")); model.send(.chooseReaction("not offered")); await model.settle()
        let reactions = await fake.reactions
        #expect(reactions.count == 2)
        #expect(reactions.first?.0 == "m"); #expect(reactions.first?.1 == "👍"); #expect(reactions.first?.2 == false)
        #expect(reactions.last?.0 == "mine"); #expect(reactions.last?.1 == "🎉"); #expect(reactions.last?.2 == true)
        model.send(.cancelReaction)
        model.send(.requestDelete("mine", .everyone)); model.send(.confirmDelete); await model.settle()
        let removed = await fake.deletes
        #expect(removed.count == 1); #expect(removed.first?.0 == "mine"); #expect(removed.first?.1 == .everyone)
    }
    @Test func olderPagesPrependThroughTheCursorAndTheWindowStaysBounded() async {
        let rows = (0..<180).map { record("r\($0)", ms: Int64(200_000 - $0 * 1_000)) }
        let fake = ChatFake(history: rows)
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", windowCapacity: 120, emit: { _ in })
        model.send(.appeared); await model.settle()
        #expect(model.state.messages.count == 50); #expect(model.state.olderAvailable); #expect(model.state.messages.first?.id == "r0")
        model.send(.loadOlder); await model.settle()
        #expect(model.state.messages.count == 100); #expect(model.state.messages.last?.id == "r99"); #expect(!model.state.detached)
        model.send(.loadOlder); await model.settle()
        #expect(model.state.messages.count == 120); #expect(model.state.detached); #expect(model.state.messages.last?.id == "r149")
        #expect(model.state.messages.first?.id == "r30")
        model.send(.jumpToLatest); await model.settle()
        #expect(model.state.messages.first?.id == "r0"); #expect(!model.state.detached)
        #expect(await fake.pageRequests == [nil, 50, 100, nil])
        model.send(.disappeared)
    }
    @Test func invalidationsFollowChangesFromTheSnapshotInsteadOfReloading() async throws {
        let fake = ChatFake(history: [record("m2", ms: 2_000), record("m1", ms: 1_000)])
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        for _ in 0..<200 where await fake.observers == 0 { try await Task.sleep(for: .milliseconds(5)) }
        await fake.push([.row(record("m3", ms: 3_000)), .row(MessageRecord(id: "m1", sender: "", kind: .deleted, isOwn: false, order: MessageOrder(milliseconds: 1_000))), .hidden("m2")])
        await fake.invalidate()
        for _ in 0..<200 where await fake.changeRequests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await model.settle()
        #expect(await fake.changeRequests == [7])
        #expect(await fake.pageRequests == [nil])
        #expect(model.state.messages.map(\.id) == ["m3", "m1"]); #expect(model.state.messages.last?.kind == .deleted)
        model.send(.disappeared)
    }
    @Test func windowAppliesChangeBatchesByIdAndOrder() {
        var window = TimelineWindow(capacity: 10)
        window.reset(MessageWindowPage(records: [record("b", ms: 2_000), record("a", ms: 1_000)], nextBefore: nil, snapshotSequence: 5))
        window.apply(MessageChangeBatch(changes: [.row(record("c", ms: 3_000)), .row(record("a", text: "edited", ms: 1_000)), .hidden("b"), .row(record("mid", ms: 1_500))], nextAfter: 9, more: false))
        #expect(window.records.map(\.id) == ["c", "mid", "a"]); #expect(window.records.last?.kind == .text("edited")); #expect(window.journal == 9)
        var older = TimelineWindow(capacity: 10)
        older.reset(MessageWindowPage(records: [record("y", ms: 5_000)], nextBefore: MessageWindowPage.testCursor(1), snapshotSequence: 1))
        older.apply(MessageChangeBatch(changes: [.row(record("ancient", ms: 1))], nextAfter: 2, more: false))
        #expect(older.records.map(\.id) == ["y"])
        var full = TimelineWindow(capacity: 2)
        full.reset(MessageWindowPage(records: [record("b", ms: 2_000), record("a", ms: 1_000)], snapshotSequence: 1))
        full.apply(MessageChangeBatch(changes: [.row(record("c", ms: 3_000))], nextAfter: 2, more: false))
        #expect(full.records.map(\.id) == ["c", "b"]); #expect(full.needsReload)
    }
    @Test func displayedIncomingRowsMarkReadOnceInOrderAndOwnRowsNever() async {
        let fake = ChatFake(history: [record("new", ms: 3_000), record("mine", own: true, ms: 2_000), record("old", ms: 1_000)])
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        model.send(.displayed("old")); await model.settle()
        model.send(.displayed("mine")); model.send(.displayed("new")); await model.settle()
        model.send(.displayed("old")); model.send(.displayed("new")); await model.settle()
        #expect(await fake.reads == ["old", "new"])
        model.send(.disappeared)
    }
    @Test func typingIsThrottledAndStopsWhenTheDraftIsSentOrCleared() async {
        let clock = TestClock()
        let fake = ChatFake()
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", now: { clock.now }, emit: { _ in })
        model.send(.draftChanged("h")); model.send(.draftChanged("he")); await model.settle()
        clock.advance(5); model.send(.draftChanged("hel")); await model.settle()
        model.send(.draftChanged("")); await model.settle()
        model.send(.draftChanged("x")); model.send(.send); await model.settle()
        #expect(await fake.typing == [true, true, false, true, false])
        model.send(.disappeared); await model.settle()
        #expect(await fake.typing.count == 5)
    }
    @Test func draftsSurviveConcealmentInRepositoryMemoryOnly() async {
        let fake = ChatFake()
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { _ in })
        model.send(.appeared); await model.settle()
        model.send(.draftChanged("half written")); await model.settle()
        model.send(.conceal); await model.settle()
        #expect(model.state.draft.isEmpty)
        model.send(.appeared); await model.settle()
        #expect(model.state.draft == "half written")
        model.send(.disappeared)
    }
    @Test func detailsShowMuteAndRouteToTheMatchedContactsSafetyNumber() async {
        var routes: [AppRoute] = []
        let fake = ChatFake()
        let model = ChatViewModel(repository: fake, account: "a", conversation: "c", emit: { if case .navigate(let route) = $0 { routes.append(route) } })
        model.send(.appeared); await model.settle()
        model.send(.detailsRequested); await model.settle()
        #expect(model.state.details?.details == ChatDetails(muted: false, peerPrincipal: "lin", peerName: "Lin"))
        model.send(.setMuted(true)); await model.settle()
        #expect(model.state.details?.details?.muted == true); #expect(await fake.muted == [true])
        model.send(.openSafetyNumber)
        #expect(routes == [.safetyNumber("lin")]); #expect(model.state.details == nil)
        model.send(.disappeared)
    }
}

final class TestClock: @unchecked Sendable {
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { value }
    func advance(_ seconds: TimeInterval) { value += seconds }
}
