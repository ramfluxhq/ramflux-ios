// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_MLS_GALLERY
import Foundation
import Synchronization

/// Debug-only fixtures of the MLS groups (MLS-GUI M2, common section 6: F2-1 to F2-11). A scoped exception to
/// docs/bridge.md like the card gallery: the pinned SDK has no M2 method, so the screens run on `FixtureMlsGroupRepository`
/// in the gallery. Compiled only with `RAMFLUX_MLS_GALLERY` (Debug) and deleted when the pin batch is verified. The data is
/// neutral (Ana, Ben, Chen, Dana, Scout the agent, `node.example`) and every link is a fake ASCII string. Deterministic.
public struct MlsGroupFixture: Identifiable, Sendable {
    public let id: String
    public let heading: String
    public let expected: String
    /// Links and notes the runner needs, shown under the heading.
    public let hint: String
}

public enum MlsGroupFixtures {
    public static let all: [MlsGroupFixture] = [
        MlsGroupFixture(id: "F2-1", heading: "Groups list, 120 groups in 3 pages", expected: "No duplicate row; the repeated group sits at its newer position; the footer stops after page 3", hint: "Scroll the list to the end (mls-group-list)"),
        MlsGroupFixture(id: "F2-2", heading: "Members of Neighbours (987)", expected: "Role headers, AI markers, You, Member for null names; page 3 fails once, Retry loads it; search loads all pages", hint: "Neighbours > info > Members; search Ana"),
        MlsGroupFixture(id: "F2-3", heading: "History of Design (260 posts)", expected: "Tombstone, one collapsed join line, name change, Change undone, Group updated, floor line at the top", hint: "Open Design and scroll to the top"),
        MlsGroupFixture(id: "F2-4", heading: "Send states", expected: "One bubble per send in its state; the repeated post adds no row; nothing is sent without a Retry tap", hint: "Open Design and send 6 messages; then wait 10 s"),
        MlsGroupFixture(id: "F2-5", heading: "Join by link", expected: "The typed text for each link; no call for the two local cases", hint: "rfinv-joined, rfinv-admin, rfinv-online (joins after 5 s), rfinv-slow (joins after 4 s), rfinv-refused-link_invalid, -invite_expired, -invite_invalid, -group_full, -queue_full, -request_expired, -already_member, -rate_limited, rfinv-unknownreason, rfinv-down; 513 characters; a link with a space"),
        MlsGroupFixture(id: "F2-6", heading: "Create and invite", expected: "Panel, copy, list badges; Revoked only after the 2 s reply", hint: "New group, then Invite links from the group info"),
        MlsGroupFixture(id: "F2-7", heading: "Membership and settings events", expected: "The lines; Book club becomes read-only and send is not called", hint: "Open Design (events 2 s after it opens); open Book club (removed 2 s after it opens)"),
        MlsGroupFixture(id: "F2-8", heading: "Leave", expected: "Owner: typed refusal; member: read-only, then the group drops off the list", hint: "Design (owner) info > Leave; Neighbours (member) info > Leave"),
        MlsGroupFixture(id: "F2-9", heading: "Scale: 1000 members, 20,000 posts", expected: "Smooth scrolling; memory after the scroll is at most 1.5 times before", hint: "Open Scale and scroll up; open its members"),
        MlsGroupFixture(id: "F2-10", heading: "Delete own post", expected: "Deleting... then one tombstone; not_author on the forced post", hint: "Design: long-press your own last post > Delete for everyone; the second-last post is refused with not_author"),
        MlsGroupFixture(id: "F2-11", heading: "Unavailable (native repository)", expected: "Every screen shows the unavailable text; nothing crashes and nothing is retried", hint: "Open the list, New group, Join with a link"),
    ]
}

/// The counters of the fake, per method, for the gallery's Calls view.
public struct MlsCallCounts: Sendable {
    public static let methods = ["group.list", "group.info", "group.create", "group.invite.create", "group.invite.list", "group.invite.revoke", "group.join", "group.join.pending", "group.members", "group.send", "group.history", "group.refresh", "group.mark_read", "group.message.delete", "group.leave"]
}

/// The fake of the M2 group methods for one gallery fixture. It implements the same protocol as the native repository, so
/// the real session, view models and screens run on it. Time-dependent scripts use real delays.
public final class FixtureMlsGroupRepository: MlsGroupRepository {
    public static let account = "gallery"
    private struct State {
        var calls: [String: Int] = [:]
        var sinks: [UUID: AsyncStream<MlsGroupEvent>.Continuation] = [:]
        var sendIndex = 0
        var membersFailed = false
        var joined: [MlsGroupInfo] = []
        var left: Set<String> = []
        var created: [String: [MlsInvite]] = [:]
        var scripted: Set<String> = []
        var nextSeq: Int64 = 1000
        var deleted: Set<String> = []
    }
    public let fixtureID: String
    private let state = Mutex(State())
    private let t0: Int64 = 1_767_258_000_000
    public init(_ fixture: MlsGroupFixture) { fixtureID = fixture.id }

    public func count(_ method: String) -> Int { state.withLock { $0.calls[method] ?? 0 } }
    private func note(_ method: String) { state.withLock { $0.calls[method, default: 0] += 1 } }
    private func pause(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

    // MARK: Data
    private static let ana = MlsAuthor(anchor: "fx-ana", display: "Ana"), ben = MlsAuthor(anchor: "fx-ben", display: "Ben"), chen = MlsAuthor(anchor: "fx-chen", display: "Chen"), dana = MlsAuthor(anchor: "fx-dana", display: "Dana")
    private static let scout = MlsAuthor(anchor: "fx-scout", display: "Scout", aiFlag: true)
    private static let me = MlsAuthor(anchor: "fx-me", display: "Me", isMe: true)
    private static func anon(_ n: Int) -> MlsAuthor { MlsAuthor(anchor: "fx-anon-\(n)", display: nil) }
    private func author(_ seq: Int64) -> MlsAuthor {
        let cycle = [Self.ana, Self.ben, Self.scout, Self.me, Self.chen, Self.anon(1), Self.dana, Self.anon(2), Self.ana, Self.anon(3), Self.ben, Self.anon(4), Self.anon(5)]
        return cycle[Int(seq) % cycle.count]
    }
    private func group(_ id: String, _ name: String, role: MlsRole, members: Int, agents: Int = 0, activity: Int64, catchUp: MlsCatchUp = MlsCatchUp(), unread: Int = 0, last: Int64 = 0) -> MlsGroupInfo {
        MlsGroupInfo(groupID: id, name: name, members: members, leaves: members, agents: agents, approval: true, myRole: role, hostNode: "node.example", catchUp: catchUp, lastLogSeq: last, warnings: [MlsWarning(code: "host_ip_visible", hostNode: "node.example")], lastActivityAt: activity, unread: unread)
    }
    private var named: [MlsGroupInfo] {
        let historyLast: Int64 = fixtureID == "F2-3" ? 260 : (fixtureID == "F2-9" ? 20_000 : 12)
        var rows = [
            group("g-design", "Design", role: .owner, members: 12, agents: 1, activity: t0 + 9_000, unread: 2, last: historyLast),
            group("g-neighbours", "Neighbours", role: .member, members: 987, activity: t0 + 8_000),
            group("g-bookclub", "Book club", role: .admin, members: 3, activity: t0 + 7_000, catchUp: MlsCatchUp(state: .running, done: 40, total: 120)),
        ]
        if fixtureID == "F2-9" { rows.insert(group("g-scale", "Scale", role: .member, members: 1000, activity: t0 + 10_000, last: 20_000), at: 0) }
        return rows
    }
    private func generated(_ n: Int) -> MlsGroupInfo { group(String(format: "g-%03d", n), String(format: "Group %03d", n), role: .member, members: 5 + n % 40, activity: t0 - Int64(n) * 1_000) }
    private func allGroups() -> [MlsGroupInfo] {
        let gone = state.withLock { $0.left }
        return (named + state.withLock { $0.joined }).filter { !gone.contains($0.groupID) }
    }

    // MARK: list / info
    public func list(account: String, cursor: String?, limit: Int) async -> Result<MlsGroupPage, MlsGroupError> {
        note("group.list"); await pause(150)
        guard fixtureID == "F2-1" else { return .success(MlsGroupPage(groups: allGroups(), cursor: nil)) }
        // 120 groups: page 1 has the 3 named groups and 47 generated; page 2 repeats one of page 1 with a newer time; page 3 has the rest.
        let gen = (1...117).map(generated)
        switch cursor {
        case nil: return .success(MlsGroupPage(groups: named + Array(gen[0..<47]), cursor: "l2"))
        case "l2":
            let repeated = gen[10]
            let newer = MlsGroupInfo(groupID: repeated.groupID, name: repeated.name, members: repeated.members, myRole: repeated.myRole, hostNode: repeated.hostNode, lastActivityAt: t0 + 20_000)
            return .success(MlsGroupPage(groups: Array(gen[47..<96]) + [newer], cursor: "l3"))
        default: return .success(MlsGroupPage(groups: Array(gen[96..<117]), cursor: nil))
        }
    }
    public func info(account: String, groupID: String) async -> Result<MlsGroupInfo, MlsGroupError> {
        note("group.info"); await pause(80)
        if let row = allGroups().first(where: { $0.groupID == groupID }) { return .success(row) }
        if let row = generatedByID(groupID) { return .success(row) }
        return .failure(state.withLock { $0.left.contains(groupID) } ? .notMember : .notMember)
    }
    private func generatedByID(_ id: String) -> MlsGroupInfo? {
        guard id.hasPrefix("g-"), let n = Int(id.dropFirst(2)), (1...117).contains(n) else { return nil }
        return generated(n)
    }

    // MARK: create / invites
    public func create(account: String, name: String, approval: Bool) async -> Result<MlsCreated, MlsGroupError> {
        note("group.create"); await pause(400)
        let invite = MlsInvite(inviteID: "inv-new-1", link: "rfinv-created-0001", maxUses: 100, usesLeft: 100, expiresAt: t0 + 7 * 86_400_000)
        let info = group("g-new", String(name.prefix(64)), role: .owner, members: 1, activity: t0 + 30_000)
        state.withLock { $0.joined.append(info); $0.created["g-new"] = [invite] }
        return .success(MlsCreated(groupID: "g-new", invite: invite))
    }
    public func inviteCreate(account: String, groupID: String, maxUses: Int, ttlSeconds: Int) async -> Result<MlsInvite, MlsGroupError> {
        note("group.invite.create"); await pause(300)
        let n = state.withLock { s -> Int in let n = (s.created[groupID]?.count ?? 0) + 2; return n }
        let invite = MlsInvite(inviteID: "inv-\(n)", link: "rfinv-created-\(String(format: "%04d", n))", maxUses: maxUses, usesLeft: maxUses, expiresAt: t0 + Int64(ttlSeconds) * 1000)
        state.withLock { $0.created[groupID, default: []].insert(invite, at: 0) }
        return .success(invite)
    }
    public func inviteList(account: String, groupID: String) async -> Result<[MlsInvite], MlsGroupError> {
        note("group.invite.list"); await pause(150)
        let mine = state.withLock { $0.created[groupID] ?? [] }.map { MlsInvite(inviteID: $0.inviteID, link: $0.link, maxUses: $0.maxUses, usesLeft: nil, expiresAt: $0.expiresAt, revoked: $0.revoked) }
        let fixed = [MlsInvite(inviteID: "inv-live", link: "rfinv-live-0001", maxUses: 10, expiresAt: t0 + 6 * 86_400_000), MlsInvite(inviteID: "inv-revoked", link: "rfinv-revoked-0001", maxUses: 10, expiresAt: t0 + 6 * 86_400_000, revoked: true), MlsInvite(inviteID: "inv-expired", link: "rfinv-expired-0001", maxUses: 1, expiresAt: t0 - 86_400_000)]
        return .success(mine + fixed.filter { f in !mine.contains { $0.inviteID == f.inviteID } })
    }
    public func inviteRevoke(account: String, groupID: String, inviteID: String) async -> Result<Void, MlsGroupError> {
        note("group.invite.revoke"); await pause(2_000)
        state.withLock { s in
            if let at = s.created[groupID]?.firstIndex(where: { $0.inviteID == inviteID }), let row = s.created[groupID]?[at] { s.created[groupID]?[at] = MlsInvite(inviteID: row.inviteID, link: row.link, maxUses: row.maxUses, usesLeft: row.usesLeft, expiresAt: row.expiresAt, revoked: true) }
        }
        return .success(())
    }

    // MARK: join
    public func join(account: String, link: String) async -> Result<MlsJoinResult, MlsGroupError> {
        note("group.join")
        let joinedInfo = group("g-joined", "Joined Club", role: .member, members: 8, activity: t0 + 25_000)
        switch link {
        case "rfinv-joined":
            await pause(300); state.withLock { s in if !s.joined.contains(where: { $0.groupID == "g-joined" }) { s.joined.append(joinedInfo) } }
            return .success(.joined(groupID: "g-joined"))
        case "rfinv-admin": await pause(300); return .success(.pending(requestID: "req-admin", reason: .awaitingAdmin, expiresAt: t0 + 86_400_000))
        case "rfinv-online":
            await pause(300)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let online = self.group("g-online", "Online Club", role: .member, members: 21, activity: self.t0 + 26_000)
                self.state.withLock { $0.joined.append(online) }
                self.emit(.joinResult(MlsJoinEvent(requestID: "req-online", groupID: "g-online", outcome: .joined)))
            }
            return .success(.pending(requestID: "req-online", reason: .awaitingMemberOnline, expiresAt: t0 + 86_400_000))
        case "rfinv-slow":
            await pause(4_000); state.withLock { s in if !s.joined.contains(where: { $0.groupID == "g-joined" }) { s.joined.append(joinedInfo) } }
            return .success(.joined(groupID: "g-joined"))
        case "rfinv-down": await pause(300); return .failure(.hostUnreachable)
        case "rfinv-unknownreason": await pause(300); return .success(.refused(.unknown("banana")))
        case "rfinv-refused-link_invalid": return .success(.refused(.linkInvalid))
        case "rfinv-refused-invite_expired": return .success(.refused(.inviteExpired(expiredAt: t0 - 3_600_000)))
        case "rfinv-refused-invite_invalid": return .success(.refused(.inviteInvalid))
        case "rfinv-refused-group_full": return .success(.refused(.groupFull))
        case "rfinv-refused-queue_full": return .success(.refused(.queueFull))
        case "rfinv-refused-request_expired": return .success(.refused(.requestExpired(expiredAt: t0 - 3_600_000)))
        case "rfinv-refused-already_member": return .success(.refused(.alreadyMember(groupID: "g-design")))
        case "rfinv-refused-rate_limited": return .success(.refused(.rateLimited(retryAfterSeconds: 10)))
        default: await pause(300); return .success(.refused(.inviteInvalid))
        }
    }
    public func joinPending(account: String) async -> Result<[MlsPendingJoin], MlsGroupError> { note("group.join.pending"); return .success([]) }

    // MARK: members
    public func members(account: String, groupID: String, cursor: String?, limit: Int) async -> Result<MlsMemberPage, MlsGroupError> {
        note("group.members"); await pause(250)
        let total = groupID == "g-scale" ? 1000 : (groupID == "g-neighbours" ? 987 : 12)
        let page = cursor.flatMap { Int($0.dropFirst()) } ?? 1   // "p2" ... "p5"
        if groupID == "g-neighbours", fixtureID == "F2-2", page == 3, state.withLock({ s in let failed = s.membersFailed; s.membersFailed = true; return !failed }) { return .failure(.hostUnreachable) }
        let start = (page - 1) * 200, end = min(total, start + 200)
        guard start < total else { return .success(MlsMemberPage(rows: [], cursor: nil)) }
        let rows = (start..<end).map(member)
        return .success(MlsMemberPage(rows: rows, cursor: end < total ? "p\(page + 1)" : nil))
    }
    private func member(_ index: Int) -> MlsMemberRow {
        // Index 0 is the owner, 1...6 admins; agents, null names and the own row are spread deterministically.
        let role: MlsRole = index == 0 ? .owner : (index <= 6 ? .admin : .member)
        if index == 3 { return MlsMemberRow(anchor: "fx-me", display: "Me", role: role, devices: 2, isMe: true) }
        let agents: Set<Int> = [11, 250, 480, 700]
        let nameless = index % 33 == 5
        let names = ["Ana", "Ben", "Chen", "Dana", "Eli", "Fay", "Gus", "Hana"]
        let display: String? = agents.contains(index) ? "Scout \(index)" : (nameless ? nil : names[index % names.count] + (index >= 8 ? " \(index)" : ""))
        return MlsMemberRow(anchor: "fx-member-\(index)", display: display, role: role, aiFlag: agents.contains(index), devices: 1 + index % 3)
    }

    // MARK: history
    private func total(_ groupID: String) -> Int64 {
        switch groupID { case "g-scale": 20_000; case "g-design": fixtureID == "F2-3" ? 260 : 12; default: 12 }
    }
    private func post(_ seq: Int64, _ groupID: String) -> MlsPost {
        let n = total(groupID)
        let by = author(seq)
        func service(_ kind: MlsPostKind, _ body: MlsPostBody) -> MlsPost { MlsPost(logSeq: seq, postID: "fx-p\(seq)", author: nil, appendedAt: t0 + seq * 1_000, kind: kind, body: body) }
        if groupID == "g-design", fixtureID == "F2-3" {
            switch seq {
            case 80: return MlsPost(logSeq: seq, postID: "fx-p\(seq)", author: Self.ana, appendedAt: t0 + seq * 1_000, kind: .unknown("poll"), body: .none)
            case 100: return service(.void, .void(voidedLogSeq: 99, by: Self.ana))
            case 120: return service(.settings, .settings(name: "Design team", approval: nil, by: Self.ana))
            case 150: return service(.membership, .membership(changes: (1...15).map { MlsMembershipChange(change: .joined, actor: MlsAuthor(anchor: "fx-new-\($0)", display: $0 % 4 == 0 ? nil : "Joiner \($0)")) }, by: Self.ana))
            case 200: return MlsPost(logSeq: seq, postID: "fx-p\(seq)", author: Self.ben, appendedAt: t0 + seq * 1_000, kind: .text, body: .text("removed"), state: .deleted)
            default: break
            }
        }
        if groupID == "g-design", fixtureID == "F2-10", seq == n - 1 { return MlsPost(logSeq: seq, postID: "fx-forced-not-author", author: Self.me, appendedAt: t0 + seq * 1_000, kind: .text, body: .text("Delete me (refused)")) }
        if groupID == "g-design", fixtureID == "F2-10", seq == n { return MlsPost(logSeq: seq, postID: "fx-own-1", author: Self.me, appendedAt: t0 + seq * 1_000, kind: .text, body: .text("Delete me"), state: state.withLock { $0.deleted.contains("fx-own-1") } ? .deleted : .sent) }
        return MlsPost(logSeq: seq, postID: "fx-p\(seq)", author: by, appendedAt: t0 + seq * 1_000, kind: .text, body: .text("Message \(seq)"))
    }
    public func history(account: String, groupID: String, afterLogSeq: Int64?, beforeLogSeq: Int64?, limit: Int) async -> Result<MlsHistoryPage, MlsGroupError> {
        note("group.history"); await pause(120)
        scriptOnOpen(groupID)
        let n = total(groupID)
        let range: ClosedRange<Int64>, more: Bool
        if let after = afterLogSeq {
            let end = min(n, after + Int64(limit)); range = (after + 1)...max(after + 1, end); more = end < n
            if after >= n { return .success(MlsHistoryPage(posts: [], floorLogSeq: 1, lastLogSeq: n, more: false)) }
        } else if let before = beforeLogSeq {
            let start = max(1, before - Int64(limit)); range = start...max(start, before - 1); more = start > 1
            if before <= 1 { return .success(MlsHistoryPage(posts: [], floorLogSeq: 1, lastLogSeq: n, more: false)) }
        } else {
            let start = max(1, n - Int64(limit) + 1); range = start...n; more = start > 1
        }
        return .success(MlsHistoryPage(posts: range.map { post($0, groupID) }, floorLogSeq: 1, lastLogSeq: n, more: more))
    }

    // MARK: send, read, delete, leave
    public func send(account: String, groupID: String, text: String, replyTo: String?, mentions: [String]) async -> Result<MlsSendReceipt, MlsGroupError> {
        note("group.send"); await pause(250)
        let index = state.withLock { s -> Int in s.sendIndex += 1; return s.sendIndex }
        let id = "fx-send-\(index)"
        guard fixtureID == "F2-4" else { return .success(MlsSendReceipt(postID: id, state: .sent(logSeq: 12 + Int64(index)))) }
        switch index {
        case 1: return .success(MlsSendReceipt(postID: id, state: .sent(logSeq: 13)))
        case 2: return .success(MlsSendReceipt(postID: id, state: .queued(.catchingUp)))
        case 3: return .success(MlsSendReceipt(postID: id, state: .delayed(sendAfter: Int64(Date().timeIntervalSince1970 * 1000) + 90_000, delaySeconds: 90)))
        case 4: return .success(MlsSendReceipt(postID: id, state: .rateLimited(MlsQuota(limit: 20, remaining: 0, firstDay: true, resetsAt: Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000))))
        case 5: return .failure(.tooLarge(maxBytes: 65_536))
        case 6:
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(2)); self.emit(.postState(groupID: groupID, postID: "fx-send-2", state: .sent, logSeq: 14))
                try? await Task.sleep(for: .seconds(2)); self.emit(.postState(groupID: groupID, postID: "fx-send-3", state: .failed("expired"), logSeq: nil))
                try? await Task.sleep(for: .seconds(2)); self.emit(.post(groupID: groupID, seq: 2000, at: nil, post: self.post(10, groupID)))
            }
            return .success(MlsSendReceipt(postID: id, state: .unknown("parked")))
        default: return .success(MlsSendReceipt(postID: id, state: .sent(logSeq: 12 + Int64(index))))
        }
    }
    public func refresh(account: String, groupID: String?) async -> Result<[MlsRefreshRow], MlsGroupError> { note("group.refresh"); return .success([]) }
    public func markRead(account: String, groupID: String, logSeq: Int64) async -> Result<MlsReadState, MlsGroupError> { note("group.mark_read"); return .success(MlsReadState(readLogSeq: logSeq, unread: 0, unreadMentions: 0)) }
    public func deleteMessage(account: String, groupID: String, postID: String) async -> Result<MlsDeleteOutcome, MlsGroupError> {
        note("group.message.delete")
        if postID == "fx-forced-not-author" { await pause(300); return .failure(.notAuthor) }
        await pause(2_000)
        state.withLock { $0.deleted.insert(postID) }
        Task { [weak self] in try? await Task.sleep(for: .seconds(1)); self?.emit(.postDeleted(groupID: groupID, postID: postID, postLogSeq: nil, logSeq: nil)) }
        return .success(.deleted(logSeq: 99))
    }
    public func leave(account: String, groupID: String) async -> Result<MlsCommit, MlsGroupError> {
        note("group.leave"); await pause(400)
        let role = allGroups().first { $0.groupID == groupID }?.myRole
        if role == .owner { return .failure(.ownerProtected) }
        state.withLock { $0.left.insert(groupID) }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            let change = MlsMembershipChange(change: .left, actor: Self.me, isMe: true)
            self?.emit(.membership(groupID: groupID, seq: 3000, at: nil, post: MlsPost(logSeq: 500, postID: "fx-left", author: nil, kind: .membership, body: .membership(changes: [change], by: nil))))
        }
        return .success(MlsCommit(logSeq: 500))
    }

    // MARK: Events
    public func events(account: String) -> AsyncStream<MlsGroupEvent> {
        let (stream, continuation) = AsyncStream<MlsGroupEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let id = UUID()
        state.withLock { $0.sinks[id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.state.withLock { $0.sinks[id] = nil } }
        return stream
    }
    private func emit(_ event: MlsGroupEvent) { let sinks = state.withLock { Array($0.sinks.values) }; for sink in sinks { sink.yield(event) } }
    /// F2-7: the membership and settings events start 2 s after the group's history is first read (the chat is open then).
    private func scriptOnOpen(_ groupID: String) {
        guard fixtureID == "F2-7", state.withLock({ $0.scripted.insert(groupID).inserted }) else { return }
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(2))
            func row(_ seq: Int64, _ changes: [MlsMembershipChange], by: MlsAuthor?) -> MlsGroupEvent { .membership(groupID: groupID, seq: 4000 + seq, at: nil, post: MlsPost(logSeq: 12 + seq, postID: "fx-m\(seq)", author: nil, appendedAt: nil, kind: .membership, body: .membership(changes: changes, by: by))) }
            if groupID == "g-design" {
                self.emit(row(1, [MlsMembershipChange(change: .removed, actor: Self.chen)], by: Self.ana)); try? await Task.sleep(for: .seconds(1))
                self.emit(row(2, [MlsMembershipChange(change: .banned, actor: Self.dana)], by: Self.ana)); try? await Task.sleep(for: .seconds(1))
                self.emit(row(3, [MlsMembershipChange(change: .roleChanged, actor: Self.ben, role: .admin)], by: Self.ana)); try? await Task.sleep(for: .seconds(1))
                self.emit(row(4, [MlsMembershipChange(change: .deviceAdded, actor: Self.ben)], by: nil)); try? await Task.sleep(for: .seconds(1))
                self.emit(.settings(groupID: groupID, seq: 4005, at: nil, post: MlsPost(logSeq: 17, postID: "fx-s5", author: nil, kind: .settings, body: .settings(name: nil, approval: false, by: Self.ana))))
            } else if groupID == "g-bookclub" {
                self.emit(row(1, [MlsMembershipChange(change: .removed, actor: Self.me, isMe: true)], by: Self.ana))
            }
        }
    }
}
#endif
