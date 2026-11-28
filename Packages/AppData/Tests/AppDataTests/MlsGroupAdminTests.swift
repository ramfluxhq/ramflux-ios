// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
@testable import AppData

/// A scriptable repository for the admin owner. A method named in `holds` waits until `release(_:)`; results are consumed per method.
private final class AdminFake: MlsGroupRepository, @unchecked Sendable {
    struct State {
        var calls: [String: Int] = [:]
        var holds: Set<String> = []
        var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
        var admin: [String: [Result<MlsAdminOutcome, MlsGroupError>]] = [:]
        var info = MlsGroupInfo(groupID: "g", name: "Design", approval: true, myRole: .owner)
        var infos: [MlsGroupInfo] = []
        var pages: [Result<MlsRequestsPage, MlsGroupError>] = []
        var members = MlsMemberPage(rows: [], cursor: nil)
        var push: Result<MlsPush, MlsGroupError> = .success(.all)
        var skip: Result<MlsCatchUpResult, MlsGroupError> = .success(.rejoining)
        var settings: [(String?, Bool?)] = []
    }
    let state = Mutex(State())
    func count(_ name: String) -> Int { state.withLock { $0.calls[name] ?? 0 } }
    func hold(_ names: String...) { state.withLock { $0.holds.formUnion(names) } }
    func release(_ name: String) {
        let waiting = state.withLock { s -> [CheckedContinuation<Void, Never>] in s.holds.remove(name); defer { s.waiting[name] = [] }; return s.waiting[name] ?? [] }
        waiting.forEach { $0.resume() }
    }
    private func enter(_ name: String) async {
        state.withLock { $0.calls[name, default: 0] += 1 }
        if state.withLock({ $0.holds.contains(name) }) { await withCheckedContinuation { c in state.withLock { $0.waiting[name, default: []].append(c) } } }
    }
    private func adminResult(_ name: String) -> Result<MlsAdminOutcome, MlsGroupError> {
        state.withLock { $0.admin[name]?.isEmpty == false ? $0.admin[name]!.removeFirst() : .success(.committed(logSeq: 100)) }
    }
    func list(account: String, cursor: String?, limit: Int) async -> Result<MlsGroupPage, MlsGroupError> { await enter("list"); return .success(MlsGroupPage(groups: [], cursor: nil)) }
    func info(account: String, groupID: String) async -> Result<MlsGroupInfo, MlsGroupError> {
        let mine = state.withLock { s -> MlsGroupInfo in s.infos.isEmpty ? s.info : s.infos.removeFirst() }
        await enter("info")
        return .success(mine)
    }
    func create(account: String, name: String, approval: Bool) async -> Result<MlsCreated, MlsGroupError> { .failure(.unavailable) }
    func inviteCreate(account: String, groupID: String, maxUses: Int, ttlSeconds: Int) async -> Result<MlsInvite, MlsGroupError> { .failure(.unavailable) }
    func inviteList(account: String, groupID: String) async -> Result<[MlsInvite], MlsGroupError> { .success([]) }
    func inviteRevoke(account: String, groupID: String, inviteID: String) async -> Result<Void, MlsGroupError> { .success(()) }
    func join(account: String, link: String) async -> Result<MlsJoinResult, MlsGroupError> { .failure(.unavailable) }
    func joinPending(account: String) async -> Result<[MlsPendingJoin], MlsGroupError> { .success([]) }
    func members(account: String, groupID: String, cursor: String?, limit: Int) async -> Result<MlsMemberPage, MlsGroupError> { await enter("members"); return .success(state.withLock { $0.members }) }
    func send(account: String, groupID: String, text: String, replyTo: String?, mentions: [String]) async -> Result<MlsSendReceipt, MlsGroupError> { .failure(.unavailable) }
    func history(account: String, groupID: String, afterLogSeq: Int64?, beforeLogSeq: Int64?, limit: Int) async -> Result<MlsHistoryPage, MlsGroupError> { await enter("history"); return .success(MlsHistoryPage(posts: [], floorLogSeq: 1, lastLogSeq: 0, more: false)) }
    func refresh(account: String, groupID: String?) async -> Result<[MlsRefreshRow], MlsGroupError> { .success([]) }
    func markRead(account: String, groupID: String, logSeq: Int64) async -> Result<MlsReadState, MlsGroupError> { .success(MlsReadState(readLogSeq: logSeq, unread: 0, unreadMentions: 0)) }
    func deleteMessage(account: String, groupID: String, postID: String) async -> Result<MlsDeleteOutcome, MlsGroupError> { .failure(.unavailable) }
    func leave(account: String, groupID: String) async -> Result<MlsCommit, MlsGroupError> { .failure(.unavailable) }
    func events(account: String) -> AsyncStream<MlsGroupEvent> { AsyncStream { $0.finish() } }
    func requests(account: String, groupID: String, cursor: String?, limit: Int) async -> Result<MlsRequestsPage, MlsGroupError> {
        let result = state.withLock { $0.pages.isEmpty ? Result<MlsRequestsPage, MlsGroupError>.success(MlsRequestsPage(rows: [], cursor: nil)) : $0.pages.removeFirst() }
        await enter("requests")
        return result
    }
    func approve(account: String, groupID: String, requestID: String) async -> Result<MlsAdminOutcome, MlsGroupError> { let r = adminResult("approve"); await enter("approve"); return r }
    func decline(account: String, groupID: String, requestID: String) async -> Result<MlsAdminOutcome, MlsGroupError> { await enter("decline"); return state.withLock { $0.admin["decline"]?.isEmpty == false ? $0.admin["decline"]!.removeFirst() : .success(.declined) } }
    func setRole(account: String, groupID: String, anchor: String, role: MlsRole) async -> Result<MlsAdminOutcome, MlsGroupError> { let r = adminResult("setRole"); await enter("setRole"); return r }
    func removeMember(account: String, groupID: String, anchor: String) async -> Result<MlsAdminOutcome, MlsGroupError> { let r = adminResult("remove"); await enter("remove"); return r }
    func banMember(account: String, groupID: String, anchor: String) async -> Result<MlsAdminOutcome, MlsGroupError> { let r = adminResult("ban"); await enter("ban"); return r }
    func setSettings(account: String, groupID: String, name: String?, approval: Bool?) async -> Result<MlsAdminOutcome, MlsGroupError> {
        state.withLock { $0.settings.append((name, approval)) }
        let r = adminResult("settings"); await enter("settings"); return r
    }
    func setPush(account: String, groupID: String, push: MlsPush) async -> Result<MlsPush, MlsGroupError> { let r = state.withLock { $0.push }; await enter("push"); return r }
    func skipCatchUp(account: String, groupID: String) async -> Result<MlsCatchUpResult, MlsGroupError> { let r = state.withLock { $0.skip }; await enter("skip"); return r }
    func void(account: String, groupID: String, logSeq: Int64) async -> Result<MlsAdminOutcome, MlsGroupError> { let r = adminResult("void"); await enter("void"); return r }
}

private func member(_ anchor: String, _ role: MlsRole = .member) -> MlsMemberRow { MlsMemberRow(anchor: anchor, display: anchor.uppercased(), role: role) }
private func request(_ id: String, anchor: String? = nil, at: Int64 = 1, expires: Int64 = 0) -> MlsJoinRequest { MlsJoinRequest(requestID: id, anchor: anchor ?? "a-" + id, display: id.uppercased(), requestedAt: at, expiresAt: expires) }
private func commit(_ seq: Int64, kind: MlsPostKind = .membership, body: MlsPostBody) -> MlsPost { MlsPost(logSeq: seq, postID: "log:\(seq)", author: nil, appendedAt: seq, kind: kind, body: body) }
private func joined(_ seq: Int64, _ anchor: String) -> MlsPost { commit(seq, body: .membership(changes: [MlsMembershipChange(change: .joined, actor: MlsAuthor(anchor: anchor, display: "X"))], by: nil)) }
private func removed(_ seq: Int64, _ anchor: String) -> MlsPost { commit(seq, body: .membership(changes: [MlsMembershipChange(change: .removed, actor: MlsAuthor(anchor: anchor, display: "X"))], by: nil)) }

/// A session on the fake with the group open and its info and members loaded, so the admin entries are live.
private func ready(_ fake: AdminFake, role: MlsRole = .owner, approval: Bool = true, rows: [MlsMemberRow] = [], requests: [MlsJoinRequest] = []) async -> MlsGroupSession {
    fake.state.withLock {
        $0.info = MlsGroupInfo(groupID: "g", name: "Design", approval: approval, myRole: role)
        $0.members = MlsMemberPage(rows: rows, cursor: nil)
        $0.pages = [.success(MlsRequestsPage(rows: requests, cursor: nil))]
    }
    let session = MlsGroupSession(account: "acct", repository: fake, makeID: { UUID().uuidString })
    await session.open("g")
    await session.openMembers("g")
    if approval, role != .member { await session.openRequests("g") }
    return session
}
private func settle(_ fake: AdminFake, _ name: String, calls: Int) async { while fake.count(name) < calls { await Task.yield() } }

struct MlsGroupAdminTests {
    @Test func aSecondAdminActionOnABusyGroupIsRefusedAndTheSlotFreesOnATypedRefusal() async {
        let fake = AdminFake()
        let s = await ready(fake, rows: [member("dana"), member("eve")], requests: [request("fay")])
        fake.state.withLock { $0.admin["remove"] = [.failure(.notAdmin)] }
        fake.hold("remove")
        let first = Task { await s.removeMember("g", anchor: "dana") }
        await settle(fake, "remove", calls: 1)
        #expect(await s.banMember("g", anchor: "eve") == false)
        #expect(await s.approve("g", requestID: "fay") == false)
        #expect(await s.setName("g", name: "Other") == false)
        #expect(await s.removeMember("g", anchor: "dana") == false)
        #expect(fake.count("ban") == 0 && fake.count("approve") == 0 && fake.count("remove") == 1)
        fake.release("remove")
        _ = await first.value
        #expect(await s.adminSnapshot("g").busy == nil)
        #expect(await s.adminSnapshot("g").notice?.error == .notAdmin)
        #expect(await s.banMember("g", anchor: "eve") == true)
    }
    @Test func anEventAtTheRepliesLogSeqThatArrivedFirstResolvesTheActionAtOnce() async {
        let fake = AdminFake()
        let s = await ready(fake, rows: [member("ben")])
        fake.state.withLock { $0.admin["setRole"] = [.success(.committed(logSeq: 310))] }
        // The event comes before the reply.
        await s.handle(.membership(groupID: "g", seq: 1, at: nil, post: commit(310, body: .membership(changes: [MlsMembershipChange(change: .roleChanged, actor: MlsAuthor(anchor: "ben"), role: .admin)], by: nil))))
        _ = await s.setRole("g", anchor: "ben", role: .admin)
        #expect(await s.adminSnapshot("g").busy == nil)
        #expect(await s.membersSnapshot("g").rows.first?.role == .admin)
    }
    @Test func theEventAfterTheReplyResolvesAndUntilThenTheRowShowsUpdating() async {
        let fake = AdminFake()
        let s = await ready(fake, rows: [member("dana")])
        fake.state.withLock { $0.admin["remove"] = [.success(.committed(logSeq: 320))] }
        _ = await s.removeMember("g", anchor: "dana")
        let waiting = await s.adminSnapshot("g")
        #expect(waiting.busy == MlsAdminBusy(kind: .remove, target: .member("dana"), waiting: true))
        #expect(await s.membersSnapshot("g").rows.contains { $0.anchor == "dana" })
        await s.handle(.membership(groupID: "g", seq: 2, at: nil, post: removed(320, "dana")))
        #expect(await s.adminSnapshot("g").busy == nil)
        #expect(await s.membersSnapshot("g").rows.isEmpty)
    }
    @Test func anAdminResultAfterAClearAndAdmitIsDroppedAndTheStateIsEmpty() async {
        let fake = AdminFake()
        let s = await ready(fake, rows: [member("dana")], requests: [request("fay")])
        fake.hold("approve")
        let call = Task { await s.approve("g", requestID: "fay") }
        await settle(fake, "approve", calls: 1)
        await s.clear(); await s.admit()
        fake.release("approve")
        #expect(await call.value == false)
        let snapshot = await s.adminSnapshot("g")
        #expect(snapshot.busy == nil && snapshot.requests.rows.isEmpty && snapshot.notice == nil)
        #expect(await s.group("g") == nil)
    }
    @Test func aStaleInfoReadDoesNotBringBackAClearedWarning() async {
        let fake = AdminFake()
        let s = await ready(fake)
        fake.state.withLock { $0.infos = [MlsGroupInfo(groupID: "g", name: "Design", myRole: .owner, warnings: [MlsWarning(code: .forkAlarm(headN: 2))])] }
        fake.hold("info")
        let read = Task { await s.refreshInfo("g") }
        await settle(fake, "info", calls: 2)
        await s.handle(.warning(groupID: "g", seq: 5, warning: MlsWarning(code: .forkAlarm(headN: 2))))
        await s.handle(.warning(groupID: "g", seq: 6, warning: MlsWarning(code: .forkAlarm(headN: nil), cleared: true)))
        fake.release("info")
        _ = await read.value
        #expect(await s.adminSnapshot("g").banners.isEmpty)
        // An event that arrives after a read is issued survives that read too.
        await s.handle(.warning(groupID: "g", seq: 7, warning: MlsWarning(code: .hostUnusual(.lateRoll))))
        _ = await s.refreshInfo("g")
        #expect(await s.adminSnapshot("g").banners.isEmpty)
    }
    @Test func aLateSkipResultAfterAnIdleEventChangesNothing() async {
        let fake = AdminFake()
        let s = await ready(fake, role: .admin)
        await s.handle(.catchUp(groupID: "g", seq: 1, state: MlsCatchUp(state: .running, done: 10, total: 120)))
        fake.hold("skip")
        let call = Task { await s.skipCatchUp("g") }
        await settle(fake, "skip", calls: 1)
        let during = await s.adminSnapshot("g")
        if case .running(_, _, let skipping, _)? = during.catchUp { #expect(skipping) } else { Issue.record("not running") }
        // Progress alone does not make the result stale; an idle event does.
        await s.handle(.catchUp(groupID: "g", seq: 2, state: MlsCatchUp(state: .running, done: 50, total: 120)))
        await s.handle(.catchUp(groupID: "g", seq: 3, state: MlsCatchUp(state: .idle)))
        fake.release("skip")
        await call.value
        #expect(await s.adminSnapshot("g").catchUp == nil)
    }
    @Test func aSkipResultAppliesWhenNothingNewerCameAndOnlyTheSkipPathSendsIt() async {
        let fake = AdminFake()
        let s = await ready(fake, role: .member)
        await s.handle(.catchUp(groupID: "g", seq: 1, state: MlsCatchUp(state: .running, done: 10, total: 120)))
        await s.handle(.catchUp(groupID: "g", seq: 2, state: MlsCatchUp(state: .running, done: 20, total: 120)))
        #expect(fake.count("skip") == 0)
        await s.skipCatchUp("g")
        #expect(fake.count("skip") == 1)
        #expect(await s.adminSnapshot("g").catchUp == .rejoining(reason: nil))
        // Rejoining shows no Skip: a second call is not made.
        await s.skipCatchUp("g")
        #expect(fake.count("skip") == 1)
        // A rejoin warning never calls skip either.
        await s.handle(.warning(groupID: "g", seq: 4, warning: MlsWarning(code: .rejoinNeeded(.stateLost))))
        #expect(fake.count("skip") == 1)
        #expect(await s.adminSnapshot("g").catchUp == .rejoining(reason: .stateLost))
    }
    @Test func aRequestsPageFromAnOlderGenerationIsDropped() async {
        let fake = AdminFake()
        let s = await ready(fake, requests: [request("a"), request("b")])
        fake.state.withLock { $0.pages = [.success(MlsRequestsPage(rows: [request("c", at: 3)], cursor: "r2"))] }
        await s.openRequests("g")
        #expect(await s.adminSnapshot("g").requests.rows.map(\.id) == ["c"])
        // A "load more" is issued, then the list is reset by a reopen; the older page must not land.
        fake.state.withLock { $0.pages = [.success(MlsRequestsPage(rows: [request("old", at: 9)], cursor: nil)), .success(MlsRequestsPage(rows: [request("fresh", at: 5)], cursor: nil))] }
        fake.hold("requests")
        let more = Task { await s.loadMoreRequests("g") }
        await settle(fake, "requests", calls: 3)
        let reopen = Task { await s.openRequests("g") }
        await settle(fake, "requests", calls: 4)
        fake.release("requests")
        await more.value; await reopen.value
        #expect(await s.adminSnapshot("g").requests.rows.map(\.id) == ["fresh"])
    }
    @Test func pendingJoinEventsDeduplicateAndOnlyAdminsOfAnApprovalGroupKeepThem() async {
        let fake = AdminFake()
        let s = await ready(fake, requests: [request("a")])
        let fay = request("fay", at: 9)
        await s.handle(.pendingJoin(groupID: "g", seq: 1, request: fay)); await s.handle(.pendingJoin(groupID: "g", seq: 2, request: fay))
        #expect(await s.adminSnapshot("g").requests.rows.map(\.id) == ["a", "fay"])
        let member = AdminFake()
        let m = await ready(member, role: .member)
        await m.handle(.pendingJoin(groupID: "g", seq: 1, request: fay))
        #expect(await m.adminSnapshot("g").requests.rows.isEmpty)
    }
    @Test func aRequestRowKeepsItsAIFlagAcrossRowsOfTheSameAnchor() async {
        let fake = AdminFake()
        let s = await ready(fake, requests: [request("a", anchor: "scout")])
        await s.handle(.pendingJoin(groupID: "g", seq: 1, request: MlsJoinRequest(requestID: "b", anchor: "scout", display: nil, aiFlag: true, requestedAt: 2)))
        let rows = await s.adminSnapshot("g").requests.rows
        #expect(rows.allSatisfy { $0.request.aiFlag })
    }
    @Test func approveCallsOnceAndTheRowLeavesOnlyOnTheJoinedEvent() async {
        let fake = AdminFake()
        let s = await ready(fake, requests: [request("ana", anchor: "a-ana")])
        fake.state.withLock { $0.admin["approve"] = [.success(.committed(logSeq: 301))] }
        _ = await s.approve("g", requestID: "ana")
        #expect(fake.count("approve") == 1)
        let adding = await s.adminSnapshot("g").requests.rows
        #expect(adding.first?.state == .adding)
        await s.handle(.membership(groupID: "g", seq: 1, at: nil, post: joined(301, "a-ana")))
        #expect(await s.adminSnapshot("g").requests.rows.isEmpty)
        #expect(await s.adminSnapshot("g").busy == nil)
    }
    @Test func requestNotFoundRemovesTheRowWithAToastAndDeclineCommitsNothing() async {
        let fake = AdminFake()
        let s = await ready(fake, requests: [request("ben"), request("chen")])
        fake.state.withLock { $0.admin["approve"] = [.failure(.requestNotFound)] }
        _ = await s.approve("g", requestID: "ben")
        #expect(await s.adminSnapshot("g").notice == MlsAdminNotice(error: .requestNotFound, isToast: true))
        #expect(await s.adminSnapshot("g").requests.rows.map(\.id) == ["chen"])
        await s.decline("g", requestID: "chen")
        let after = await s.adminSnapshot("g")
        #expect(fake.count("decline") == 1 && after.requests.rows.isEmpty && after.busy == nil)
    }
    @Test func pacedKeepsEntriesOffUntilTheTimeAndCallsNothingByItself() async {
        let fake = AdminFake()
        let clock = Mutex(Date(timeIntervalSince1970: 1000))
        fake.state.withLock { $0.info = MlsGroupInfo(groupID: "g", name: "Design", myRole: .owner); $0.members = MlsMemberPage(rows: [member("dana")], cursor: nil) }
        let s = MlsGroupSession(account: "acct", repository: fake, now: { clock.withLock { $0 } }, makeID: { UUID().uuidString })
        await s.open("g"); await s.openMembers("g")
        fake.state.withLock { $0.admin["remove"] = [.failure(.paced(retryAt: 1_005_000))] }
        _ = await s.removeMember("g", anchor: "dana")
        #expect(await s.adminSnapshot("g").pacedUntil == 1_005_000)
        #expect(await s.removeMember("g", anchor: "dana") == false)
        #expect(fake.count("remove") == 1)
        clock.withLock { $0 = Date(timeIntervalSince1970: 1006) }
        #expect(await s.adminSnapshot("g").pacedUntil == nil)
        let again = await s.removeMember("g", anchor: "dana")
        #expect(again && fake.count("remove") == 2)
    }
    @Test func rolesAndTargetsGateTheMemberActions() async {
        let fake = AdminFake()
        let owner = await ready(fake, rows: [member("o", .owner), member("adm", .admin), member("mem")])
        #expect(await owner.removeMember("g", anchor: "o") == false)
        #expect(await owner.setRole("g", anchor: "mem", role: .member) == false)
        #expect(await owner.setRole("g", anchor: "adm", role: .admin) == false)
        #expect(await owner.removeMember("g", anchor: "adm") == true)
        let adminFake = AdminFake()
        let admin = await ready(adminFake, role: .admin, rows: [member("adm", .admin), member("mem")])
        #expect(await admin.setRole("g", anchor: "mem", role: .admin) == false)
        #expect(await admin.removeMember("g", anchor: "adm") == false)
        #expect(await admin.banMember("g", anchor: "mem") == true)
        let plain = AdminFake()
        let regular = await ready(plain, role: .member, rows: [member("mem")])
        #expect(await regular.removeMember("g", anchor: "mem") == false)
        #expect(plain.count("remove") == 0)
    }
    @Test func aStaleRoleThatReachesARefusalReadsTheInfoAgain() async {
        let fake = AdminFake()
        let s = await ready(fake, role: .admin, rows: [member("mem")])
        let before = fake.count("info")
        fake.state.withLock { $0.admin["remove"] = [.failure(.notAdmin)]; $0.info = MlsGroupInfo(groupID: "g", name: "Design", myRole: .member) }
        _ = await s.removeMember("g", anchor: "mem")
        while fake.count("info") == before { await Task.yield() }
        while await s.group("g")?.myRole != .member { await Task.yield() }
        #expect(await s.removeMember("g", anchor: "mem") == false)
    }
    @Test func settingsSendOneFieldAtATimeAndTheValueFollowsTheEventNotTheReply() async {
        let fake = AdminFake()
        let s = await ready(fake)
        #expect(await s.setName("g", name: "Design") == false)     // unchanged
        #expect(await s.setName("g", name: "   ") == false)         // empty
        #expect(await s.setName("g", name: String(repeating: "x", count: 65)) == false)
        #expect(fake.count("settings") == 0)
        fake.state.withLock { $0.admin["settings"] = [.success(.committed(logSeq: 330))] }
        _ = await s.setName("g", name: "  Design team ")
        #expect(fake.state.withLock { $0.settings.map { "\($0.0 ?? "-")|\($0.1.map(String.init) ?? "-")" } } == ["Design team|-"])
        #expect(await s.group("g")?.name == "Design")
        await s.handle(.settings(groupID: "g", seq: 1, at: nil, post: commit(330, kind: .settings, body: .settings(name: "Design team", approval: nil, by: nil))))
        let renamed = await s.group("g")?.name
        let free = await s.adminSnapshot("g").busy == nil
        #expect(renamed == "Design team" && free)
        fake.state.withLock { $0.admin["settings"] = [.success(.committed(logSeq: 331))] }
        _ = await s.setApproval("g", on: false)
        #expect(fake.state.withLock { $0.settings.last?.1 } == false && fake.state.withLock { $0.settings.last?.0 } == nil)
    }
    @Test func approvalOnDropsTheAdmissionWarningAndOffClosesTheRequestsEntry() async {
        let fake = AdminFake()
        let s = await ready(fake, approval: false)
        await s.handle(.warning(groupID: "g", seq: 1, warning: MlsWarning(code: .admissionNeedsOnline)))
        #expect(await s.adminSnapshot("g").banners.count == 1)
        await s.handle(.settings(groupID: "g", seq: 2, at: nil, post: commit(9, kind: .settings, body: .settings(name: nil, approval: true, by: nil))))
        #expect(await s.adminSnapshot("g").banners.isEmpty)
        #expect(await s.adminSnapshot("g").requests.approvalOff == false)
        await s.handle(.settings(groupID: "g", seq: 3, at: nil, post: commit(10, kind: .settings, body: .settings(name: nil, approval: false, by: nil))))
        #expect(await s.adminSnapshot("g").requests.approvalOff)
    }
    @Test func pushChangesOnTheReplyOnlyAndAFailureKeepsTheOldValue() async {
        let fake = AdminFake()
        let s = await ready(fake, role: .member)
        fake.hold("push")
        let call = Task { await s.setPush("g", .all) }
        await settle(fake, "push", calls: 1)
        let during = await s.adminSnapshot("g").pushSaving
        #expect(await s.group("g")?.push == .mentionsReplies)
        #expect(during == .all)
        await s.setPush("g", .none)                                  // one call per group at a time
        #expect(fake.count("push") == 1)
        fake.release("push"); await call.value
        #expect(await s.group("g")?.push == .all)
        #expect(fake.count("settings") == 0)
        fake.state.withLock { $0.push = .failure(.generic(nil)) }
        await s.setPush("g", .none)
        let failed = await s.adminSnapshot("g").pushFailed
        #expect(await s.group("g")?.push == .all)
        #expect(failed)
    }
    @Test func voidIsOnlyOfferedOnTheHeadCommitAndAVoidRowMarksTheVoidedOne() async {
        let fake = AdminFake()
        let s = await ready(fake)
        let posts = [commit(240, body: .membership(changes: [], by: nil)), commit(250, kind: .settings, body: .settings(name: "N", approval: nil, by: nil))]
        for post in posts { await s.handle(.post(groupID: "g", seq: nil, at: nil, post: post)) }
        #expect(await s.adminSnapshot("g").voidableLogSeq == 250)
        #expect(await s.void("g", logSeq: 240) == false)
        #expect(fake.count("void") == 0)
        fake.state.withLock { $0.admin["void"] = [.success(.committed(logSeq: 251))] }
        #expect(await s.void("g", logSeq: 250) == true)
        await s.handle(.post(groupID: "g", seq: nil, at: nil, post: commit(251, kind: .void, body: .void(voidedLogSeq: 250, by: nil))))
        #expect(await s.adminSnapshot("g").busy == nil)
        #expect(await s.adminSnapshot("g").voidableLogSeq == nil)
        let lines = await s.timelineSnapshot("g").entries.compactMap { entry -> MlsServiceLine? in if case .service(let line) = entry { line } else { nil } }
        #expect(lines.first { $0.logSeq == 250 }?.voided == true)
        #expect(lines.contains { if case .void = $0.kind { true } else { false } })
    }
    @Test func aVoidNotHeadRefusalShowsTheTypedTextAndReadsTheGapWithoutRetrying() async {
        let fake = AdminFake()
        let s = await ready(fake)
        await s.handle(.post(groupID: "g", seq: nil, at: nil, post: commit(250, kind: .settings, body: .settings(name: "N", approval: nil, by: nil))))
        let history = fake.count("history")
        fake.state.withLock { $0.admin["void"] = [.failure(.voidNotHead(headLogSeq: 252))] }
        _ = await s.void("g", logSeq: 250)
        #expect(await s.adminSnapshot("g").notice?.error == .voidNotHead(headLogSeq: 252))
        while fake.count("history") == history { await Task.yield() }
        #expect(fake.count("void") == 1)
    }
    @Test func aRemovalDuringAnActionTurnsTheGroupReadOnlyAndTheLateReplyChangesNothing() async {
        let fake = AdminFake()
        let s = await ready(fake, rows: [member("ana")])
        fake.hold("remove")
        let call = Task { await s.removeMember("g", anchor: "ana") }
        await settle(fake, "remove", calls: 1)
        await s.handle(.membership(groupID: "g", seq: 1, at: nil, post: commit(40, body: .membership(changes: [MlsMembershipChange(change: .removed, actor: MlsAuthor(anchor: "me", isMe: true), isMe: true)], by: nil))))
        fake.release("remove")
        #expect(await call.value == false)
        let snapshot = await s.adminSnapshot("g")
        #expect(snapshot.readOnly && snapshot.busy == nil && snapshot.banners.isEmpty)
        #expect(await s.removeMember("g", anchor: "ana") == false)
        #expect(fake.count("remove") == 1)
    }

    @Test func theUndecryptablePlaceholderSitsBeforeTheFirstRowAtOrAfterItsLogSeqAndNeverMergesTheHeadCommit() async {
        let fake = AdminFake()
        let s = await ready(fake)
        let text: (Int64) -> MlsPost = { MlsPost(logSeq: $0, postID: "p\($0)", author: MlsAuthor(anchor: "a"), appendedAt: $0, kind: .text, body: .text("m")) }
        for post in [text(138), text(139), text(141), joined(150, "x"), joined(151, "y")] { await s.handle(.post(groupID: "g", seq: nil, at: nil, post: post)) }
        await s.handle(.warning(groupID: "g", seq: 1, warning: MlsWarning(code: .undecryptable(count: 12, fromLogSeq: 140))))
        let entries = await s.timelineSnapshot("g").entries
        let ids = entries.map(\.id)
        let placeholder = ids.firstIndex(of: "service:undecryptable")
        #expect(placeholder != nil && ids.firstIndex(of: "post:p141") == (placeholder ?? 0) + 1 && ids.firstIndex(of: "post:p139") == (placeholder ?? 0) - 1)
        // The two join rows stay two lines because the newest one is the head commit the viewer may undo.
        let joinedLines = entries.compactMap { entry -> MlsServiceLine? in if case .service(let line) = entry, case .joined = line.kind { line } else { nil } }
        #expect(joinedLines.count == 2 && joinedLines.last?.voidable == true && joinedLines.first?.voidable == false)
        await s.handle(.warning(groupID: "g", seq: 2, warning: MlsWarning(code: .undecryptable(count: 0, fromLogSeq: nil), cleared: true)))
        #expect(await s.timelineSnapshot("g").entries.contains { $0.id == "service:undecryptable" } == false)
    }
    @Test func hidingABannerIsPerGroupAndOnlyForTheHideableCodes() async {
        let fake = AdminFake()
        let s = await ready(fake)
        await s.handle(.warning(groupID: "g", seq: 1, warning: MlsWarning(code: .hostUnusual(.lateRoll))))
        await s.handle(.warning(groupID: "g", seq: 2, warning: MlsWarning(code: .forkAlarm(headN: 1))))
        await s.hideWarning("g", code: "fork_alarm")
        #expect(await s.adminSnapshot("g").banners.count == 2)
        await s.hideWarning("g", code: "host_unusual")
        let after = await s.adminSnapshot("g")
        #expect(after.banners.map(\.id) == ["fork_alarm"])
        #expect(after.warningRows.count == 2)   // the info rows keep the hidden one
        await s.clear(); await s.admit()
        #expect(await s.adminSnapshot("g").banners.isEmpty)
    }

    // MARK: Pure rules
    @Test func theHeadCommitRule() {
        let rows: [(seq: Int64, kind: MlsPostKind)] = [(240, .membership), (250, .settings)]
        #expect(MlsHeadCommit.voidable(commits: rows, voided: [], detached: false, role: .owner, readOnly: false) == 250)
        #expect(MlsHeadCommit.voidable(commits: rows, voided: [], detached: false, role: .admin, readOnly: false) == 250)
        #expect(MlsHeadCommit.voidable(commits: rows, voided: [], detached: false, role: .member, readOnly: false) == nil)
        #expect(MlsHeadCommit.voidable(commits: rows, voided: [], detached: true, role: .owner, readOnly: false) == nil)
        #expect(MlsHeadCommit.voidable(commits: rows, voided: [], detached: false, role: .owner, readOnly: true) == nil)
        #expect(MlsHeadCommit.voidable(commits: rows, voided: [250], detached: false, role: .owner, readOnly: false) == nil)
        #expect(MlsHeadCommit.voidable(commits: rows + [(251, .void)], voided: [250], detached: false, role: .owner, readOnly: false) == nil)
        #expect(MlsHeadCommit.voidable(commits: [], voided: [], detached: false, role: .owner, readOnly: false) == nil)
    }
    @Test func theWarningMergeRule() {
        var set = MlsWarningSet()
        set.apply(MlsWarning(code: .forkAlarm(headN: 2)))
        let issued = set.generation
        set.apply(MlsWarning(code: .forkAlarm(headN: nil), cleared: true))
        set.apply(MlsWarning(code: .hostUnusual(.lateRoll)))
        // A read issued before both events lists the cleared code and misses the new one.
        set.applyInfo([MlsWarning(code: .forkAlarm(headN: 2)), MlsWarning(code: .admissionNeedsOnline)], issued: issued)
        #expect(Set(set.codes.keys) == ["host_unusual", "admission_needs_online"])
        // A read issued after every event replaces the set.
        set.applyInfo([], issued: set.generation)
        #expect(set.codes.isEmpty)
    }
    @Test func theBannerOrderLimitAndHiding() {
        let codes: [String: MlsWarningCode] = ["admission_needs_online": .admissionNeedsOnline, "undecryptable": .undecryptable(count: 2, fromLogSeq: 5), "fork_alarm": .forkAlarm(headN: 1), "head_commit_rejected": .headCommitRejected(logSeq: 9), "host_unusual": .hostUnusual(.lateReply)]
        let owner = MlsBannerPlan.banners(codes: codes, catchUp: .running(done: 1, total: 2, skipping: false, error: nil), role: .owner, hidden: [])
        #expect(owner.map(\.id) == ["fork_alarm", "head_commit_rejected", "catchup", "undecryptable", "host_unusual", "admission_needs_online"])
        #expect(owner.prefix(2).allSatisfy { $0.severity == .critical && !$0.canHide })
        let member = MlsBannerPlan.banners(codes: codes, catchUp: .rejoining(reason: .pruned), role: .member, hidden: ["undecryptable"])
        #expect(member.map(\.id) == ["fork_alarm", "catchup", "host_unusual", "admission_needs_online"])
        #expect(MlsBannerPlan.rows(codes: codes.merging(["unknown:weird": .unknown("weird")]) { first, _ in first }, role: .member).last == .unknown("weird"))
        #expect(!MlsBannerPlan.rows(codes: codes, role: .member).contains(.headCommitRejected(logSeq: 9)))
    }
    @Test func theQuotaAndPrivacyRules() {
        #expect(MlsQuotaRule.shows(MlsQuota(limit: 500, remaining: 60, firstDay: false)))
        #expect(!MlsQuotaRule.shows(MlsQuota(limit: 500, remaining: 400, firstDay: false)))
        #expect(MlsQuotaRule.shows(MlsQuota(limit: 20, remaining: 3, firstDay: true)))
        #expect(MlsQuotaRule.shows(MlsQuota(limit: 2, remaining: 1, firstDay: false)))
        #expect(MlsPrivacyRule.eta(.waiting(sendAfter: 200), now: 100) == 200)
        #expect(MlsPrivacyRule.eta(.waiting(sendAfter: 50), now: 100) == nil && MlsPrivacyRule.eta(.armed, now: 100) == nil)
        #expect(MlsPrivacyRule.showsInfo(.armed) && !MlsPrivacyRule.showsInfo(.none))
    }
    @Test func theNameCheckCountsGraphemeClusters() {
        #expect(MlsAdminRules.checkName("  Design ") == .ok("Design"))
        #expect(MlsAdminRules.checkName("   ") == .empty)
        #expect(MlsAdminRules.checkName(String(repeating: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", count: 64)) == .ok(String(repeating: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", count: 64)))
        #expect(MlsAdminRules.checkName(String(repeating: "a", count: 65)) == .tooLong)
    }
    @Test func theUnavailableRepositoryAnswersEveryAdminMethodWithTheTypedOutcome() async {
        let repo = UnavailableMlsGroupRepository(), native = NativeMlsGroupRepository()
        for source in [repo as any MlsGroupRepository, native] {
            #expect(await source.requests(account: "a", groupID: "g", cursor: nil, limit: 200) == .failure(.unavailable))
            #expect(await source.approve(account: "a", groupID: "g", requestID: "r") == .failure(.unavailable))
            #expect(await source.decline(account: "a", groupID: "g", requestID: "r") == .failure(.unavailable))
            #expect(await source.setRole(account: "a", groupID: "g", anchor: "x", role: .admin) == .failure(.unavailable))
            #expect(await source.removeMember(account: "a", groupID: "g", anchor: "x") == .failure(.unavailable))
            #expect(await source.banMember(account: "a", groupID: "g", anchor: "x") == .failure(.unavailable))
            #expect(await source.setSettings(account: "a", groupID: "g", name: "n", approval: nil) == .failure(.unavailable))
            #expect(await source.setPush(account: "a", groupID: "g", push: .all) == .failure(.unavailable))
            #expect(await source.skipCatchUp(account: "a", groupID: "g") == .failure(.unavailable))
            #expect(await source.void(account: "a", groupID: "g", logSeq: 1) == .failure(.unavailable))
        }
    }
}

