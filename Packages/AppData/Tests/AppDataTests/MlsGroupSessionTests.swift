// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
@testable import AppData

/// A scriptable repository. `joinResults` are consumed one per call; a gated call waits until `open()`.
private final class FakeMls: MlsGroupRepository, @unchecked Sendable {
    struct State {
        var calls: [String: Int] = [:]
        var joinResults: [Result<MlsJoinResult, MlsGroupError>] = []
        var gates: [CheckedContinuation<Void, Never>] = []
        var gateJoin = false
        var gateSend = false
        var sendGates: [CheckedContinuation<Void, Never>] = []
        var history: [(after: Int64?, before: Int64?)] = []
        var historyPages: [MlsHistoryPage] = []
        var sendResults: [Result<MlsSendReceipt, MlsGroupError>] = []
    }
    let state = Mutex(State())
    func count(_ name: String) -> Int { state.withLock { $0.calls[name] ?? 0 } }
    private func note(_ name: String) { state.withLock { $0.calls[name, default: 0] += 1 } }
    func openSend() { let waiting = state.withLock { s -> [CheckedContinuation<Void, Never>] in s.gateSend = false; defer { s.sendGates = [] }; return s.sendGates }; waiting.forEach { $0.resume() } }
    func open() { let waiting = state.withLock { s -> [CheckedContinuation<Void, Never>] in s.gateJoin = false; defer { s.gates = [] }; return s.gates }; waiting.forEach { $0.resume() } }
    func list(account: String, cursor: String?, limit: Int) async -> Result<MlsGroupPage, MlsGroupError> { note("list"); return .success(MlsGroupPage(groups: [], cursor: nil)) }
    func info(account: String, groupID: String) async -> Result<MlsGroupInfo, MlsGroupError> { note("info"); return .success(MlsGroupInfo(groupID: groupID, name: "G")) }
    func create(account: String, name: String, approval: Bool) async -> Result<MlsCreated, MlsGroupError> { note("create"); return .failure(.unavailable) }
    func inviteCreate(account: String, groupID: String, maxUses: Int, ttlSeconds: Int) async -> Result<MlsInvite, MlsGroupError> { note("inviteCreate"); return .failure(.unavailable) }
    func inviteList(account: String, groupID: String) async -> Result<[MlsInvite], MlsGroupError> { note("inviteList"); return .success([]) }
    func inviteRevoke(account: String, groupID: String, inviteID: String) async -> Result<Void, MlsGroupError> { note("inviteRevoke"); return .success(()) }
    func join(account: String, link: String) async -> Result<MlsJoinResult, MlsGroupError> {
        note("join")
        if state.withLock({ $0.gateJoin }) { await withCheckedContinuation { c in state.withLock { $0.gates.append(c) } } }
        return state.withLock { $0.joinResults.isEmpty ? .failure(.generic(nil)) : $0.joinResults.removeFirst() }
    }
    func joinPending(account: String) async -> Result<[MlsPendingJoin], MlsGroupError> { note("joinPending"); return .success([]) }
    func members(account: String, groupID: String, cursor: String?, limit: Int) async -> Result<MlsMemberPage, MlsGroupError> { note("members"); return .success(MlsMemberPage(rows: [], cursor: nil)) }
    func send(account: String, groupID: String, text: String, replyTo: String?, mentions: [String]) async -> Result<MlsSendReceipt, MlsGroupError> {
        note("send")
        if state.withLock({ $0.gateSend }) { await withCheckedContinuation { c in state.withLock { $0.sendGates.append(c) } } }
        return state.withLock { $0.sendResults.isEmpty ? .failure(.generic(nil)) : $0.sendResults.removeFirst() }
    }
    func history(account: String, groupID: String, afterLogSeq: Int64?, beforeLogSeq: Int64?, limit: Int) async -> Result<MlsHistoryPage, MlsGroupError> {
        note("history")
        state.withLock { $0.history.append((afterLogSeq, beforeLogSeq)) }
        // A gap fill is slow enough for a second one to be asked for while it runs.
        if afterLogSeq != nil { try? await Task.sleep(for: .milliseconds(50)) }
        return state.withLock { $0.historyPages.isEmpty ? .success(MlsHistoryPage(posts: [], floorLogSeq: 1, lastLogSeq: 0, more: false)) : .success($0.historyPages.removeFirst()) }
    }
    func refresh(account: String, groupID: String?) async -> Result<[MlsRefreshRow], MlsGroupError> { note("refresh"); return .success([]) }
    func markRead(account: String, groupID: String, logSeq: Int64) async -> Result<MlsReadState, MlsGroupError> { note("markRead"); return .success(MlsReadState(readLogSeq: logSeq, unread: 0, unreadMentions: 0)) }
    func deleteMessage(account: String, groupID: String, postID: String) async -> Result<MlsDeleteOutcome, MlsGroupError> { note("delete"); return .success(.deleted(logSeq: 99)) }
    func leave(account: String, groupID: String) async -> Result<MlsCommit, MlsGroupError> { note("leave"); return .success(MlsCommit(logSeq: 1)) }
    func events(account: String) -> AsyncStream<MlsGroupEvent> { AsyncStream { $0.finish() } }
    // M3 methods: scripted by MlsGroupAdminTests through `FakeMls`.
    public func requests(account: String, groupID: String, cursor: String?, limit: Int) async -> Result<MlsRequestsPage, MlsGroupError> { .failure(.unavailable) }
    public func approve(account: String, groupID: String, requestID: String) async -> Result<MlsAdminOutcome, MlsGroupError> { .failure(.unavailable) }
    public func decline(account: String, groupID: String, requestID: String) async -> Result<MlsAdminOutcome, MlsGroupError> { .failure(.unavailable) }
    public func setRole(account: String, groupID: String, anchor: String, role: MlsRole) async -> Result<MlsAdminOutcome, MlsGroupError> { .failure(.unavailable) }
    public func removeMember(account: String, groupID: String, anchor: String) async -> Result<MlsAdminOutcome, MlsGroupError> { .failure(.unavailable) }
    public func banMember(account: String, groupID: String, anchor: String) async -> Result<MlsAdminOutcome, MlsGroupError> { .failure(.unavailable) }
    public func setSettings(account: String, groupID: String, name: String?, approval: Bool?) async -> Result<MlsAdminOutcome, MlsGroupError> { .failure(.unavailable) }
    public func setPush(account: String, groupID: String, push: MlsPush) async -> Result<MlsPush, MlsGroupError> { .failure(.unavailable) }
    public func skipCatchUp(account: String, groupID: String) async -> Result<MlsCatchUpResult, MlsGroupError> { .failure(.unavailable) }
    public func void(account: String, groupID: String, logSeq: Int64) async -> Result<MlsAdminOutcome, MlsGroupError> { .failure(.unavailable) }

}

private func author(_ anchor: String, ai: Bool = false, me: Bool = false) -> MlsAuthor { MlsAuthor(anchor: anchor, display: anchor.uppercased(), aiFlag: ai, isMe: me) }
private func text(_ seq: Int64, id: String? = nil, by: MlsAuthor? = nil, state: MlsPostState = .sent) -> MlsPost {
    MlsPost(logSeq: seq, postID: id ?? "p\(seq)", author: by ?? author("a1"), appendedAt: seq, kind: .text, body: .text("m\(seq)"), state: state)
}
private func page(_ posts: [MlsPost], more: Bool = false) -> MlsHistoryPage { MlsHistoryPage(posts: posts, floorLogSeq: 1, lastLogSeq: posts.compactMap(\.logSeq).max() ?? 0, more: more) }
private func session(_ fake: FakeMls) -> MlsGroupSession { MlsGroupSession(account: "acct", repository: fake, makeID: { UUID().uuidString }) }
private func postRows(_ snapshot: MlsTimelineSnapshot) -> [MlsPostRow] { snapshot.entries.compactMap { if case .post(let row) = $0 { row } else { nil } } }
private func pendings(_ snapshot: MlsTimelineSnapshot) -> [MlsPendingPost] { snapshot.entries.compactMap { if case .pending(let row) = $0 { row } else { nil } } }

struct MlsGroupSessionTests {
    @Test func aSecondJoinIsRefusedWhileAnyJoinOfTheAccountIsInFlightEvenAfterTheSheetClosed() async {
        let fake = FakeMls()
        fake.state.withLock { $0.gateJoin = true; $0.joinResults = [.success(.joined(groupID: "g-old"))] }
        let s = session(fake)
        let first = Task { await s.join(link: "rfinv-slow") }
        while fake.count("join") < 1 { await Task.yield() }
        // The sheet closes and opens again: it shows the call in flight, and a tap with any link makes no call.
        await s.dismissJoin()
        let reopened = await s.joinSnapshot()
        #expect(reopened.joining && reopened.outcome == nil)
        #expect(await s.join(link: "rfinv-slow") == nil)
        #expect(await s.join(link: "rfinv-other") == nil)
        #expect(await s.join(link: "bad link") == nil)
        #expect(fake.count("join") == 1)
        fake.open(); _ = await first.value
        // The older Joined is not the outcome of the newer attempt, but the group was recorded (an info read follows).
        let done = await s.joinSnapshot()
        #expect(!done.joining && done.outcome == nil)
        for _ in 0..<50 where fake.count("info") == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(fake.count("info") >= 1)
        // Once it returned, the next tap is accepted.
        #expect(await s.join(link: "rfinv-next") != nil)
        #expect(fake.count("join") == 2)
    }
    @Test func aSecondTapDuringACallIsIgnored() async {
        let fake = FakeMls()
        fake.state.withLock { $0.gateJoin = true; $0.joinResults = [.success(.joined(groupID: "g"))] }
        let s = session(fake)
        let first = Task { await s.join(link: "rfinv-slow") }
        while fake.count("join") < 1 { await Task.yield() }
        #expect(await s.join(link: "rfinv-slow") == nil)
        fake.open(); _ = await first.value
        #expect(fake.count("join") == 1)
    }
    @Test func theLocalLinkChecksMakeNoCall() async {
        let fake = FakeMls(); let s = session(fake)
        await s.join(link: String(repeating: "a", count: 513)); await s.join(link: "has space")
        #expect(fake.count("join") == 0)
        #expect(await s.joinSnapshot().outcome == .refused(.linkInvalid, local: true))
    }
    @Test func noCallFollowsAnyOutcome() async {
        let fake = FakeMls()
        fake.state.withLock { $0.joinResults = [.success(.refused(.rateLimited(retryAfterSeconds: 10))), .failure(.hostUnreachable), .failure(.unavailable), .success(.pending(requestID: "r", reason: .awaitingAdmin, expiresAt: 0))] }
        let s = session(fake)
        for _ in 0..<4 { await s.join(link: "rfinv-a") }
        try? await Task.sleep(for: .milliseconds(100))
        // Exactly one call per tap: nothing retried, nothing scheduled.
        #expect(fake.count("join") == 4)
        #expect(fake.count("joinPending") == 0 && fake.count("list") == 0)
    }
    @Test func aJoinResultMatchesByRequestIdOnlyAndAnUnknownIdRefreshesTheList() async {
        let fake = FakeMls()
        fake.state.withLock { $0.joinResults = [.success(.pending(requestID: "r1", reason: .awaitingMemberOnline, expiresAt: Int64.max))] }
        let s = session(fake)
        await s.join(link: "rfinv-a")
        #expect(await s.listSnapshot().pendingJoins.count == 1)
        await s.handle(.joinResult(MlsJoinEvent(requestID: "other", groupID: "g", outcome: .joined)))
        #expect(await s.listSnapshot().pendingJoins.count == 1)
        for _ in 0..<50 where fake.count("list") == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(fake.count("list") >= 1)
        await s.handle(.joinResult(MlsJoinEvent(requestID: "r1", groupID: "g", outcome: .joined)))
        #expect(await s.listSnapshot().pendingJoins.isEmpty)
    }
    @Test func anEventAndAHistoryRowWithOneLogSeqGiveOneItem() async {
        let fake = FakeMls()
        fake.state.withLock { $0.historyPages = [page([text(1), text(2)])] }
        let s = session(fake)
        await s.open("g")
        await s.handle(.post(groupID: "g", seq: 1, at: 5, post: text(2)))
        await s.handle(.post(groupID: "g", seq: 2, at: 5, post: text(3)))
        await s.handle(.post(groupID: "g", seq: 2, at: 5, post: text(3)))
        #expect(postRows(await s.timelineSnapshot("g")).map(\.post.postID) == ["p1", "p2", "p3"])
    }
    @Test func sentAfterAnEventMovesTheItemWithoutDuplicatingIt() async {
        let fake = FakeMls()
        fake.state.withLock { $0.historyPages = [page([text(1)])]; $0.sendResults = [.success(MlsSendReceipt(postID: "mine", state: .queued(.catchingUp)))] }
        let s = session(fake)
        await s.open("g")
        await s.send("g", text: "hello")
        var snapshot = await s.timelineSnapshot("g")
        #expect(pendings(snapshot).count == 1 && pendings(snapshot)[0].state == .queued(.catchingUp))
        await s.handle(.postState(groupID: "g", postID: "mine", state: .sent, logSeq: 2))
        snapshot = await s.timelineSnapshot("g")
        #expect(pendings(snapshot).isEmpty)
        #expect(postRows(snapshot).map(\.post.postID) == ["p1", "mine"])
        // The `post` event for the same slot, and a second `post_state`, add nothing.
        await s.handle(.post(groupID: "g", seq: 5, at: 5, post: text(2, id: "mine", by: author("me", me: true))))
        await s.handle(.postState(groupID: "g", postID: "mine", state: .sent, logSeq: 2))
        #expect(postRows(await s.timelineSnapshot("g")).count == 2)
    }
    @Test func aPostThatArrivesBeforeTheReplyIsMergedByPostId() async {
        let fake = FakeMls()
        fake.state.withLock { $0.historyPages = [page([text(1)])]; $0.sendResults = [.success(MlsSendReceipt(postID: "mine", state: .sent(logSeq: 2)))] }
        let s = session(fake)
        await s.open("g")
        await s.handle(.post(groupID: "g", seq: 5, at: 5, post: text(2, id: "mine", by: author("me", me: true))))
        await s.send("g", text: "hello")
        let snapshot = await s.timelineSnapshot("g")
        #expect(postRows(snapshot).filter { $0.post.postID == "mine" }.count == 1 && pendings(snapshot).isEmpty)
    }
    @Test func aFailedSendIsKeptAndNeverResentWithoutAnExplicitRetry() async {
        let fake = FakeMls()
        fake.state.withLock { $0.historyPages = [page([text(1)])]; $0.sendResults = [.failure(.tooLarge(maxBytes: 10)), .success(MlsSendReceipt(postID: "n", state: .sent(logSeq: 2)))] }
        let s = session(fake)
        await s.open("g")
        await s.send("g", text: "big")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(fake.count("send") == 1)
        let failed = pendings(await s.timelineSnapshot("g"))
        #expect(failed.count == 1 && failed[0].state == .notSent(.error(.tooLarge(maxBytes: 10))))
        let retried = await s.retry("g", localID: failed[0].localID)
        #expect(fake.count("send") == 2 && retried != nil && retried != failed[0].localID)
        #expect(pendings(await s.timelineSnapshot("g")).isEmpty)
    }
    @Test func aReadOnlyGroupNeverSends() async {
        let fake = FakeMls()
        fake.state.withLock { $0.historyPages = [page([text(1)])] }
        let s = session(fake)
        await s.open("g")
        let refreshesBefore = fake.count("refresh")
        await s.handle(.membership(groupID: "g", seq: 1, at: 1, post: MlsPost(logSeq: 2, postID: "m", author: nil, kind: .membership, body: .membership(changes: [MlsMembershipChange(change: .removed, actor: author("me"), isMe: true)], by: author("a1")))))
        #expect(await s.timelineSnapshot("g").readOnly == .removed)
        #expect(await s.send("g", text: "x") == nil)
        #expect(fake.count("send") == 0)
        await s.refresh("g")
        #expect(fake.count("refresh") == refreshesBefore)
    }
    @Test func oneGapFillRunsAtATime() async {
        let fake = FakeMls()
        fake.state.withLock { $0.historyPages = [page([text(1), text(2)])] }
        let s = session(fake)
        await s.open("g")
        fake.state.withLock { $0.history = []; $0.historyPages = [page([text(3), text(4)], more: true), page([text(5)])] }
        async let a: Void = s.fillGap("g")
        async let b: Void = s.fillGap("g")
        _ = await (a, b)
        let calls = fake.state.withLock { $0.history }.filter { $0.after != nil }
        // Two pages for the fill, then one queued round (empty): never two calls at once, and the rounds follow `last`.
        #expect(calls.map { $0.after } == [2, 4, 5])
        #expect(postRows(await s.timelineSnapshot("g")).count == 5)
    }
    @Test func theAIFlagStaysTrueAfterAFalseRow() async {
        let fake = FakeMls()
        fake.state.withLock { $0.historyPages = [page([text(1, by: author("bot", ai: true))])] }
        let s = session(fake)
        await s.open("g")
        await s.handle(.post(groupID: "g", seq: 1, at: 1, post: text(2, by: author("bot", ai: false))))
        let rows = postRows(await s.timelineSnapshot("g"))
        #expect(rows.count == 2 && rows.allSatisfy(\.authorIsAgent))
    }
    @Test func aClearRefusesLaterWritesUntilAdmitted() async {
        let fake = FakeMls()
        fake.state.withLock { $0.historyPages = [page([text(1)])]; $0.joinResults = [.success(.joined(groupID: "g"))] }
        let s = session(fake)
        await s.open("g")
        await s.clear()
        #expect(await s.send("g", text: "x") == nil)
        #expect(await s.join(link: "rfinv-a") == nil)
        await s.handle(.post(groupID: "g", seq: 1, at: 1, post: text(9)))
        #expect(await s.timelineSnapshot("g").entries.isEmpty)
        #expect(fake.count("send") == 0 && fake.count("join") == 0)
        await s.admit()
        #expect(await s.join(link: "rfinv-a") != nil)
    }
    @Test func aCallThatReturnsAfterAClearIsDropped() async {
        let fake = FakeMls()
        fake.state.withLock { $0.gateJoin = true; $0.joinResults = [.success(.pending(requestID: "r", reason: .awaitingAdmin, expiresAt: Int64.max))] }
        let s = session(fake)
        let call = Task { await s.join(link: "rfinv-a") }
        while fake.count("join") < 1 { await Task.yield() }
        await s.clear(); await s.admit()
        fake.open(); _ = await call.value
        #expect(await s.listSnapshot().pendingJoins.isEmpty)
        #expect(await s.joinSnapshot().outcome == nil)
    }
    @Test func membershipLinesCollapseAndDeviceChangesAreNeverShown() async {
        let fake = FakeMls()
        func join(_ seq: Int64, _ names: [String]) -> MlsPost { MlsPost(logSeq: seq, postID: "m\(seq)", author: nil, kind: .membership, body: .membership(changes: names.map { MlsMembershipChange(change: .joined, actor: author($0)) }, by: nil)) }
        let devices = MlsPost(logSeq: 4, postID: "m4", author: nil, kind: .membership, body: .membership(changes: [MlsMembershipChange(change: .deviceAdded, actor: author("a1"))], by: nil))
        fake.state.withLock { $0.historyPages = [page([join(1, ["a", "b"]), join(2, ["c"]), devices, text(5)])] }
        let s = session(fake)
        await s.open("g")
        let lines = await s.timelineSnapshot("g").entries.compactMap { entry -> MlsServiceLine? in if case .service(let line) = entry { line } else { nil } }
        #expect(lines.count == 1)
        if case .joined(let names)? = lines.first?.kind { #expect(names.count == 3) } else { Issue.record("joined") }
    }
}

private func ownPending(_ seq: Int64?, id: String) -> MlsPost {
    MlsPost(logSeq: seq, postID: id, author: author("me", me: true), appendedAt: 1, kind: .text, body: .text("hello"), state: .pending(.queued(.catchingUp)))
}

struct MlsGroupSessionAuditTests {
    @Test func notSentBubblesSurviveTheEvictionOfTheirTimeline() async {
        let fake = FakeMls()
        fake.state.withLock { $0.sendResults = [.failure(.tooLarge(maxBytes: 10))] }
        let s = session(fake)
        await s.open("g1")
        await s.send("g1", text: "big")
        for group in ["g2", "g3", "g4"] { await s.open(group) }
        await s.open("g1")
        let kept = pendings(await s.timelineSnapshot("g1"))
        #expect(kept.count == 1 && kept[0].text == "big" && kept[0].state == .notSent(.error(.tooLarge(maxBytes: 10))))
    }
    @Test func aSubmitInFlightWhenItsTimelineIsEvictedStillRecordsItsOutcome() async {
        let fake = FakeMls()
        fake.state.withLock { $0.gateSend = true; $0.sendResults = [.failure(.offline)] }
        let s = session(fake)
        await s.open("g1")
        let call = Task { await s.send("g1", text: "slow") }
        while fake.count("send") < 1 { await Task.yield() }
        for group in ["g2", "g3", "g4"] { await s.open(group) }
        fake.openSend(); _ = await call.value
        await s.open("g1")
        let kept = pendings(await s.timelineSnapshot("g1"))
        #expect(kept.count == 1 && kept[0].state == .notSent(.error(.offline)))
    }
    @Test func aClearForgetsTheEvictedSendRecords() async {
        let fake = FakeMls()
        fake.state.withLock { $0.sendResults = [.failure(.offline)] }
        let s = session(fake)
        await s.open("g1"); await s.send("g1", text: "x")
        for group in ["g2", "g3", "g4"] { await s.open(group) }
        await s.clear(); await s.admit()
        await s.open("g1")
        #expect(pendings(await s.timelineSnapshot("g1")).isEmpty)
    }
    @Test func theSdkRowOfAnOwnPostArrivingDuringTheSubmitIsOneBubbleWithTheLatestState() async {
        let fake = FakeMls()
        fake.state.withLock { $0.gateSend = true; $0.sendResults = [.success(MlsSendReceipt(postID: "P1", state: .queued(.catchingUp)))] }
        let s = session(fake)
        await s.open("g")
        let call = Task { await s.send("g", text: "hello") }
        while fake.count("send") < 1 { await Task.yield() }
        await s.handle(.post(groupID: "g", seq: 7, at: 1, post: ownPending(nil, id: "P1")))
        #expect(pendings(await s.timelineSnapshot("g")).count == 2)
        fake.openSend(); _ = await call.value
        let one = pendings(await s.timelineSnapshot("g"))
        #expect(one.count == 1 && one[0].postID == "P1")
        await s.handle(.postState(groupID: "g", postID: "P1", state: .sent, logSeq: 3))
        let after = await s.timelineSnapshot("g")
        #expect(pendings(after).isEmpty && postRows(after).filter { $0.post.postID == "P1" }.count == 1)
    }
    @Test func aRateLimitLiftsAtItsResetTimeWithoutSendingAnything() async {
        let fake = FakeMls()
        let reset = Int64(Date().timeIntervalSince1970 * 1000) + 200
        fake.state.withLock { $0.sendResults = [.success(MlsSendReceipt(postID: "P1", state: .rateLimited(MlsQuota(limit: 5, remaining: 0, firstDay: false, resetsAt: reset))))] }
        let s = session(fake)
        await s.open("g")
        let changes = await s.changes()
        await s.send("g", text: "hello")
        #expect(await s.timelineSnapshot("g").composerOffUntil == reset)
        // While locked neither a new send nor a Retry reaches the SDK.
        #expect(await s.send("g", text: "again") == nil)
        let notSent = pendings(await s.timelineSnapshot("g"))
        #expect(await s.retry("g", localID: notSent[0].localID) == nil)
        // The timer publishes a change at the reset time; the snapshot then shows the composer on.
        var lifted = false
        let deadline = Date().addingTimeInterval(5)
        for await _ in changes {
            if await s.timelineSnapshot("g").composerOffUntil == nil { lifted = true; break }
            if Date() > deadline { break }
        }
        #expect(lifted)
        #expect(fake.count("send") == 1)
    }
    @Test func aClearCancelsTheResetTimer() async {
        let fake = FakeMls()
        let reset = Int64(Date().timeIntervalSince1970 * 1000) + 100
        fake.state.withLock { $0.sendResults = [.success(MlsSendReceipt(postID: "P1", state: .rateLimited(MlsQuota(limit: 5, remaining: 0, firstDay: false, resetsAt: reset))))] }
        let s = session(fake)
        await s.open("g"); await s.send("g", text: "x")
        await s.clear()
        let changes = await s.changes()
        let fired = Mutex(false)
        let watcher = Task { for await _ in changes { fired.withLock { $0 = true } } }
        try? await Task.sleep(for: .milliseconds(300))
        watcher.cancel()
        #expect(!fired.withLock { $0 })
    }
    @Test func theInviteLinkIsNotRevealedByDump() {
        let invite = MlsInvite(inviteID: "i1", link: "rfinv-SECRETLINK", maxUses: 1, expiresAt: 5)
        var out = ""
        dump(invite, to: &out); dump(MlsCreated(groupID: "g", invite: invite), to: &out); var snapshot = MlsInviteSnapshot(); snapshot.invites = [invite]; dump(snapshot, to: &out)
        print(String(describing: Mirror(reflecting: invite).children.map { "\($0.value)" }), to: &out)
        #expect(!out.contains("SECRETLINK") && out.contains("<redacted>"))
    }
}
