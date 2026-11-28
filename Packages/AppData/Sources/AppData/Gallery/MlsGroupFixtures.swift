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

    /// The admin and edge states of MLS-GUI M3 (common section 6: F3-1 to F3-14). Groups: Design (owner), Neighbours (member),
    /// Book club (admin), Scale (member), Queue (owner, approval on), Open house (admin, approval off), Late catch and Zero
    /// total (admin, catch-up), Stale (owner). Request ids are `rq-*`; member anchors are `fx-*`.
    public static let admin: [MlsGroupFixture] = [
        MlsGroupFixture(id: "F3-1", heading: "Join requests (Design, owner)", expected: "Confirmations name each person (Scout with the AI marker and note, the unnamed one as this member). Ana: Approving, Adding, row gone; Ben: row gone and a toast; Chen: gone; Dana: paced text, Approve off until the time; Eve: reopen shows the result; Fay once; Dana Expired after 30 s. Counters approve 4, decline 1", hint: "Design > info > Join requests: Approve Ana, Ben, Dana (twice) and Eve (close the screen at once); Decline Chen; wait 4 s for Fay"),
        MlsGroupFixture(id: "F3-2", heading: "Requests paging (Queue)", expected: "Count More than 200 then 230; a page error row; Try again loads page 2", hint: "Queue > info > Join requests; scroll to the end"),
        MlsGroupFixture(id: "F3-3", heading: "Owner member actions (Design)", expected: "One call per action; Updating until the event; the event-first role change resolves on the reply; Gus (a stale owner row) gives the owner text; no menu on the owner or own row", hint: "Design > info > Members: menus of Ben (event first), Chen, Dana (tap Remove twice), Eve, Gus"),
        MlsGroupFixture(id: "F3-4", heading: "Admin member actions and a stale role (Book club)", expected: "Members offer Remove and Ban only; admin and owner rows nothing; Remove Ana returns only an admin can do this, then the menus disappear", hint: "Book club > info > Members; Remove Ana"),
        MlsGroupFixture(id: "F3-5", heading: "One admin commit at a time (Design)", expected: "While Remove Dana runs (3 s), Ban Eve and Approve Fay are off with the busy text; one remove call", hint: "Design > Members: Remove Dana; at once open Eve's menu; open Join requests and look at Fay"),
        MlsGroupFixture(id: "F3-6", heading: "Settings and push (Design, Neighbours)", expected: "The old name stays until the event; 65 characters and the unchanged name make no call; approval off asks first, then the admission banner; approval on needs no confirmation; push shows Saving then the value, None fails", hint: "Design > info > Group settings; Neighbours > info > the push picker"),
        MlsGroupFixture(id: "F3-7", heading: "Catch-up and skip (Book club, Late catch, Zero total)", expected: "Progress 0 to 120; Keep catching up calls nothing; Skip then Rejoining; Late catch stays idle; Zero total shows the indeterminate text. The catch-up in Book club only ends by a skip", hint: "Open Book club; tap Skip in the banner; Keep catching up, then Skip again and confirm. Late catch: Skip, confirm. Zero total: read the banner"),
        MlsGroupFixture(id: "F3-8", heading: "Warnings (Design, Neighbours)", expected: "Four banners at once (two and +2), then every code in turn with its text, the critical ones without Hide; the placeholder row at message 140 and Show; the stale info read does not bring the fork alarm back; Neighbours shows no rejected-commit banner; the unknown code only in group info", hint: "Open Design and watch for about 90 s; open Neighbours; use Show and Hide; Design > info lists the rows"),
        MlsGroupFixture(id: "F3-9", heading: "Quota and privacy delay (Design, Neighbours, Scale)", expected: "Design: 60 of 500 line and the commit line; Neighbours: first-day line and the privacy row; Scale: the ETA hint and no quota line; values change only after the re-read", hint: "Send one message in each group; Design > info shows the commit line"),
        MlsGroupFixture(id: "F3-10", heading: "Void (Design, Stale)", expected: "Undo only on the newest change (message 250), not on the older one; Undone and the void line after the event; Stale shows the typed text and the gap fills; the rejected-commit banner opens the same confirmation", hint: "Design: long-press the newest change line > Undo this change; wait 3 s for the banner action. Stale: the same on its newest change"),
        MlsGroupFixture(id: "F3-11", heading: "Removed during an action (Book club)", expected: "The group turns read-only at 1 s; the late reply changes nothing; no further call", hint: "Book club > Members: Remove Ana, confirm, wait"),
        MlsGroupFixture(id: "F3-12", heading: "Lock during actions (Design, Book club)", expected: "After Unlock no request list, slot, pending action, warning or skip result survives; nothing was applied after the lock", hint: "Approve Ana in Design (reply after 3 s) and Skip in Book club; tap Lock now at 1 s and Unlock at 5 s (buttons at the top)"),
        MlsGroupFixture(id: "F3-13", heading: "Admission hint (Open house)", expected: "A banner and an info row with Get invite link (opens the invite panel, creates nothing) and the mobile hint; the join sheet's pending text shows the online note", hint: "Open house; then Join with a link: rfinv-online"),
        MlsGroupFixture(id: "F3-14", heading: "Unavailable (native repository for every M3 method)", expected: "Each M3 screen and action shows the unavailable text; nothing retries or crashes; the M3 counters stay at 0", hint: "Design: Join requests, Members > Remove, Settings > Save, undo the newest change; Book club: Skip"),
    ]
}

/// The counters of the fake, per method, for the gallery's Calls view.
public struct MlsCallCounts: Sendable {
    public static let methods = ["group.list", "group.info", "group.create", "group.invite.create", "group.invite.list", "group.invite.revoke", "group.join", "group.join.pending", "group.members", "group.send", "group.history", "group.refresh", "group.mark_read", "group.message.delete", "group.leave",
                                  "group.requests.list", "group.requests.approve", "group.requests.decline", "group.role.set", "group.member.remove", "group.member.ban", "group.settings.set", "group.push.set", "group.catch_up", "group.void"]
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
        // M3 (F3-*)
        var admin: [String: MlsGroupInfo] = [:]
        var appended: [String: [MlsPost]] = [:]
        var approved: Set<String> = []
        var declined: Set<String> = []
        var gone: Set<String> = []
        var roles: [String: MlsRole] = [:]
        var pageFailed = false
        var danaPaced = false
        var danaExpiresAt: Int64?
        var fayArrived = false
        var staleFork = false
        var skipped: Set<String> = []
        var envelope: Int64 = 9000
        var nextCommit: Int64 = 400
    }
    public let fixtureID: String
    private let state = Mutex(State())
    /// F3-14: the M3 methods are the native repository's, which answers with the typed unavailable outcome and calls nothing.
    private let native = NativeMlsGroupRepository()
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
        if isAdminFixture { return adminGroups() }
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
        if isAdminFixture, let stale = await staleInfo(groupID) { return .success(stale) }
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
        if isAdminFixture, let roster = roster(groupID) { return .success(MlsMemberPage(rows: roster, cursor: nil)) }
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
        if isAdminFixture { return max(adminTotal(groupID), state.withLock { $0.appended[groupID]?.compactMap(\.logSeq).max() ?? 0 }) }
        return switch groupID { case "g-scale": 20_000; case "g-design": fixtureID == "F2-3" ? 260 : 12; default: 12 }
    }
    private func post(_ seq: Int64, _ groupID: String) -> MlsPost {
        if isAdminFixture, let special = state.withLock({ $0.appended[groupID]?.first { $0.logSeq == seq } }) ?? adminPost(seq, groupID) { return special }
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
        if isAdminFixture { quotaDown(groupID) }
        guard fixtureID == "F2-4" else { return .success(MlsSendReceipt(postID: id, state: .sent(logSeq: (isAdminFixture ? total(groupID) : 12) + Int64(index)))) }
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

    // MARK: M3 methods (F3-*)
    public func requests(account: String, groupID: String, cursor: String?, limit: Int) async -> Result<MlsRequestsPage, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.requests(account: account, groupID: groupID, cursor: cursor, limit: limit) }
        note("group.requests.list"); await pause(200)
        return requestsPage(groupID, cursor: cursor)
    }
    public func approve(account: String, groupID: String, requestID: String) async -> Result<MlsAdminOutcome, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.approve(account: account, groupID: groupID, requestID: requestID) }
        note("group.requests.approve")
        return await approveScript(groupID, requestID)
    }
    public func decline(account: String, groupID: String, requestID: String) async -> Result<MlsAdminOutcome, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.decline(account: account, groupID: groupID, requestID: requestID) }
        note("group.requests.decline"); await pause(1_000)
        guard requestRow(requestID) != nil else { return .failure(.requestNotFound) }
        state.withLock { $0.declined.insert(requestID) }
        return .success(.declined)
    }
    public func setRole(account: String, groupID: String, anchor: String, role: MlsRole) async -> Result<MlsAdminOutcome, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.setRole(account: account, groupID: groupID, anchor: anchor, role: role) }
        note("group.role.set")
        let change = MlsMembershipChange(change: .roleChanged, actor: person(anchor), role: role)
        if fixtureID == "F3-3", anchor == "fx-ben" {
            // Event first: the membership row arrives half a second before the reply.
            after(500) { [self] in emit(membershipEvent(groupID, seq: 310, [change], by: Self.me)) }
            await pause(1_000); return .success(.committed(logSeq: 310))
        }
        await pause(400)
        let seq: Int64 = anchor == "fx-chen" ? 311 : nextCommitSeq()
        after(1_000) { [self] in emit(membershipEvent(groupID, seq: seq, [change], by: Self.me)) }
        return .success(.committed(logSeq: seq))
    }
    public func removeMember(account: String, groupID: String, anchor: String) async -> Result<MlsAdminOutcome, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.removeMember(account: account, groupID: groupID, anchor: anchor) }
        note("group.member.remove")
        return await removeOrBan(groupID, anchor: anchor, ban: false)
    }
    public func banMember(account: String, groupID: String, anchor: String) async -> Result<MlsAdminOutcome, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.banMember(account: account, groupID: groupID, anchor: anchor) }
        note("group.member.ban")
        return await removeOrBan(groupID, anchor: anchor, ban: true)
    }
    public func setSettings(account: String, groupID: String, name: String?, approval: Bool?) async -> Result<MlsAdminOutcome, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.setSettings(account: account, groupID: groupID, name: name, approval: approval) }
        note("group.settings.set"); await pause(300)
        let seq: Int64 = name != nil ? 330 : (approval == false ? 331 : 332)
        after(1_000) { [self] in
            let post = MlsPost(logSeq: seq, postID: "log:\(seq)", author: nil, appendedAt: nowMillis(), kind: .settings, body: .settings(name: name, approval: approval, by: Self.me))
            emit(.settings(groupID: groupID, seq: envelopeSeq(), at: nil, post: post))
            // Turning approval off: the SDK reports that a join now needs an online member or agent.
            if approval == false { after(300) { [self] in emit(.warning(groupID: groupID, seq: envelopeSeq(), warning: MlsWarning(code: .admissionNeedsOnline))) } }
        }
        return .success(.committed(logSeq: seq))
    }
    public func setPush(account: String, groupID: String, push: MlsPush) async -> Result<MlsPush, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.setPush(account: account, groupID: groupID, push: push) }
        note("group.push.set"); await pause(1_000)
        if push == .none { return .failure(.generic(nil)) }
        mutate(groupID) { $0.with(push: push) }
        return .success(push)
    }
    public func skipCatchUp(account: String, groupID: String) async -> Result<MlsCatchUpResult, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.skipCatchUp(account: account, groupID: groupID) }
        note("group.catch_up")
        state.withLock { _ = $0.skipped.insert(groupID) }
        if groupID == "g-latecatch" {
            // Late variant: an idle event arrives while the reply is still on its way.
            after(1_000) { [self] in emit(.catchUp(groupID: groupID, seq: envelopeSeq(), state: MlsCatchUp(state: .idle))) }
            await pause(3_000); return .success(.rejoining)
        }
        await pause(fixtureID == "F3-12" ? 3_000 : 300)
        after(5_000) { [self] in emit(.catchUp(groupID: groupID, seq: envelopeSeq(), state: MlsCatchUp(state: .idle))) }
        return .success(.rejoining)
    }
    public func void(account: String, groupID: String, logSeq: Int64) async -> Result<MlsAdminOutcome, MlsGroupError> {
        if fixtureID == "F3-14" { return await native.void(account: account, groupID: groupID, logSeq: logSeq) }
        note("group.void"); await pause(400)
        if groupID == "g-stale" {
            // Variant: a newer commit (252) landed while the dialog was open; the SDK refuses.
            emit(membershipEvent(groupID, seq: 252, [MlsMembershipChange(change: .joined, actor: MlsAuthor(anchor: "fx-zed", display: "Zed"))], by: Self.ana))
            return .failure(.voidNotHead(headLogSeq: 252))
        }
        after(1_000) { [self] in
            let post = MlsPost(logSeq: 251, postID: "log:251", author: nil, appendedAt: nowMillis(), kind: .void, body: .void(voidedLogSeq: logSeq, by: Self.me))
            emit(.post(groupID: groupID, seq: envelopeSeq(), at: nil, post: post))
            after(500) { [self] in emit(.warning(groupID: groupID, seq: envelopeSeq(), warning: MlsWarning(code: .headCommitRejected(logSeq: nil), cleared: true))) }
        }
        return .success(.committed(logSeq: 251))
    }

    // MARK: Events
    public func events(account: String) -> AsyncStream<MlsGroupEvent> {
        let (stream, continuation) = AsyncStream<MlsGroupEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let id = UUID()
        state.withLock { $0.sinks[id] = continuation }
        continuation.onTermination = { [weak self] _ in self?.state.withLock { $0.sinks[id] = nil } }
        return stream
    }
    private func emit(_ event: MlsGroupEvent) {
        if isAdminFixture { applyToFixture(event) }
        let sinks = state.withLock { Array($0.sinks.values) }
        for sink in sinks { sink.yield(event) }
    }
    /// F2-7: the membership and settings events start 2 s after the group's history is first read (the chat is open then).
    private func scriptOnOpen(_ groupID: String) {
        if isAdminFixture { scriptAdminOnOpen(groupID); return }
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
// MARK: F3-* (MLS-GUI M3): admin and edge states
extension FixtureMlsGroupRepository {
    fileprivate var isAdminFixture: Bool { fixtureID.hasPrefix("F3-") }
    fileprivate func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    fileprivate func envelopeSeq() -> Int64 { state.withLock { $0.envelope += 1; return $0.envelope } }
    fileprivate func nextCommitSeq() -> Int64 { state.withLock { $0.nextCommit += 1; return $0.nextCommit } }
    fileprivate func after(_ milliseconds: Int, _ body: @escaping @Sendable () -> Void) {
        Task { try? await Task.sleep(for: .milliseconds(milliseconds)); body() }
    }
    fileprivate func mutate(_ groupID: String, _ change: (MlsGroupInfo) -> MlsGroupInfo) {
        state.withLock { s in if let info = s.admin[groupID] { s.admin[groupID] = change(info) } }
    }

    // Groups and their infos
    fileprivate func adminGroups() -> [MlsGroupInfo] {
        state.withLock { s in
            if s.admin.isEmpty { s.admin = seedAdmin() }
            return ["g-scale", "g-design", "g-neighbours", "g-bookclub", "g-queue", "g-open", "g-latecatch", "g-catch0", "g-stale"].compactMap { s.admin[$0] }
        }
    }
    fileprivate func adminInfo(_ id: String) -> MlsGroupInfo? { adminGroups().first { $0.groupID == id } }
    private func seedAdmin() -> [String: MlsGroupInfo] {
        let real = nowMillis()
        let hostIP = MlsWarning(code: "host_ip_visible", hostNode: "node.example")
        func group(_ id: String, _ name: String, _ role: MlsRole, members: Int, agents: Int = 0, approval: Bool = true, rank: Int64, warnings: [MlsWarning]? = nil, catchUp: MlsCatchUp = MlsCatchUp(), post: MlsQuota? = nil, commit: MlsQuota? = nil, privacy: MlsPrivacyDelay = .none) -> MlsGroupInfo {
            MlsGroupInfo(groupID: id, name: name, members: members, leaves: members, agents: agents, approval: approval, myRole: role, hostNode: "node.example", catchUp: catchUp, privacyDelay: privacy, postQuota: post, commitQuota: commit, lastLogSeq: adminTotal(id), warnings: warnings ?? [hostIP], lastActivityAt: 1_767_258_000_000 + rank * 1_000)
        }
        let quotas = fixtureID == "F3-9"
        let catching = ["F3-7", "F3-12", "F3-14"].contains(fixtureID)
        let rows = [
            group("g-scale", "Scale", .member, members: 1000, rank: 10, post: quotas ? MlsQuota(limit: 500, remaining: 400, firstDay: false) : nil, privacy: quotas ? .waiting(sendAfter: real + 120_000) : .none),
            group("g-design", "Design", .owner, members: 8, agents: 1, rank: 9, post: quotas ? MlsQuota(limit: 500, remaining: 60, firstDay: false) : nil, commit: quotas ? MlsQuota(limit: 20, remaining: 2, firstDay: false) : nil),
            group("g-neighbours", "Neighbours", .member, members: 987, rank: 8, post: quotas ? MlsQuota(limit: 20, remaining: 3, firstDay: true) : nil, privacy: quotas ? .armed : .none),
            group("g-bookclub", "Book club", .admin, members: 5, rank: 7, catchUp: catching ? MlsCatchUp(state: .running, done: 40, total: 120) : MlsCatchUp()),
            group("g-queue", "Queue", .owner, members: 40, rank: 6),
            group("g-open", "Open house", .admin, members: 12, approval: false, rank: 5, warnings: [hostIP, MlsWarning(code: .admissionNeedsOnline)]),
            group("g-latecatch", "Late catch", .admin, members: 6, rank: 4, catchUp: fixtureID == "F3-7" ? MlsCatchUp(state: .running, done: 10, total: 120) : MlsCatchUp()),
            group("g-catch0", "Zero total", .admin, members: 6, rank: 3, catchUp: fixtureID == "F3-7" ? MlsCatchUp(state: .running, done: 0, total: 0) : MlsCatchUp()),
            group("g-stale", "Stale", .owner, members: 4, rank: 2),
        ]
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.groupID, $0) })
    }
    fileprivate func adminTotal(_ groupID: String) -> Int64 {
        switch (fixtureID, groupID) {
        case ("F3-8", "g-design"): 260
        case ("F3-10", "g-design"), ("F3-10", "g-stale"), ("F3-14", "g-design"): 250
        case (_, "g-scale"): 20_000
        default: 12
        }
    }
    /// The newest commit rows of the 250-post histories: an older membership row at 240 and a name change at 250.
    fileprivate func adminPost(_ seq: Int64, _ groupID: String) -> MlsPost? {
        guard adminTotal(groupID) == 250 else { return nil }
        let at = 1_767_258_000_000 + seq * 1_000
        switch seq {
        case 240: return MlsPost(logSeq: 240, postID: "log:240", author: nil, appendedAt: at, kind: .membership, body: .membership(changes: [MlsMembershipChange(change: .joined, actor: MlsAuthor(anchor: "fx-joiner", display: "Joiner"))], by: Self.ana))
        case 250: return MlsPost(logSeq: 250, postID: "log:250", author: nil, appendedAt: at, kind: .settings, body: .settings(name: "Design team", approval: nil, by: Self.ana))
        default: return nil
        }
    }
    fileprivate func staleInfo(_ id: String) async -> MlsGroupInfo? {
        guard fixtureID == "F3-8", id == "g-design", state.withLock({ s -> Bool in let armed = s.staleFork; s.staleFork = false; return armed }), let current = adminInfo(id) else { return nil }
        // Issued now, answered 3 s later, and still listing the fork alarm that was cleared in between.
        let snapshot = current.with(warnings: current.warnings + [MlsWarning(code: .forkAlarm(headN: 2))])
        try? await Task.sleep(for: .seconds(3))
        return snapshot
    }
    fileprivate func quotaDown(_ groupID: String) {
        mutate(groupID) { info in
            guard let quota = info.postQuota else { return info }
            return info.with(postQuota: MlsQuota(limit: quota.limit, remaining: max(0, quota.remaining - 1), firstDay: quota.firstDay, resetsAt: quota.resetsAt))
        }
    }

    // People
    fileprivate func person(_ anchor: String) -> MlsAuthor {
        let names = ["fx-ana": "Ana", "fx-ben": "Ben", "fx-chen": "Chen", "fx-dana": "Dana", "fx-eve": "Eve", "fx-gus": "Gus", "fx-olga": "Olga", "fx-scout": "Scout"]
        return MlsAuthor(anchor: anchor, display: names[anchor], aiFlag: anchor == "fx-scout", isMe: anchor == "fx-me")
    }
    fileprivate func roster(_ groupID: String) -> [MlsMemberRow]? {
        let base: [(String, MlsRole)]
        switch groupID {
        case "g-design": base = [("fx-me", .owner), ("fx-chen", .admin), ("fx-ana", .member), ("fx-ben", .member), ("fx-dana", .member), ("fx-eve", .member), ("fx-gus", .member), ("fx-scout", .member)]
        case "g-bookclub": base = [("fx-olga", .owner), ("fx-me", .admin), ("fx-chen", .admin), ("fx-ana", .member), ("fx-ben", .member)]
        default: return nil
        }
        let (roles, gone) = state.withLock { ($0.roles, $0.gone) }
        return base.filter { !gone.contains($0.0) }.map { anchor, role in
            let who = person(anchor)
            let shown: MlsRole = anchor == "fx-me" ? role : (roles[anchor] ?? role)
            return MlsMemberRow(anchor: anchor, display: anchor == "fx-me" ? "Me" : who.display, role: shown, aiFlag: who.aiFlag, devices: 1, isMe: anchor == "fx-me")
        }
    }

    // Requests
    fileprivate func requestRow(_ id: String) -> MlsJoinRequest? {
        let table: [(String, String?, Bool)] = [("rq-ana", "Ana", false), ("rq-ben", "Ben", false), ("rq-chen", "Chen", false), ("rq-dana", "Dana", false), ("rq-eve", "Eve", false), ("rq-scout", "Scout", true), ("rq-anon", nil, false), ("rq-fay", "Fay", false), ("rq-hana", "Hana", false)]
        guard let at = table.firstIndex(where: { $0.0 == id }) else { return nil }
        let real = nowMillis()
        let dana = id == "rq-dana" ? state.withLock { s -> Int64 in if let value = s.danaExpiresAt { return value }; s.danaExpiresAt = real + 30_000; return real + 30_000 } : nil
        return MlsJoinRequest(requestID: id, anchor: "fx-" + id, display: table[at].1, aiFlag: table[at].2, requestedAt: 1_767_254_000_000 + Int64(at) * 1_000, expiresAt: dana ?? real + 86_400_000)
    }
    fileprivate func requestsPage(_ groupID: String, cursor: String?) -> Result<MlsRequestsPage, MlsGroupError> {
        func generated(_ range: ClosedRange<Int>) -> [MlsJoinRequest] {
            range.map { MlsJoinRequest(requestID: String(format: "rq-q-%03d", $0), anchor: "fx-q-\($0)", display: String(format: "Applicant %03d", $0), requestedAt: 1_767_254_000_000 + Int64($0) * 1_000, expiresAt: nowMillis() + 86_400_000) }
        }
        let (approved, declined, fay) = state.withLock { ($0.approved, $0.declined, $0.fayArrived) }
        switch (fixtureID, groupID) {
        case ("F3-2", "g-queue"):
            if cursor == nil { return .success(MlsRequestsPage(rows: generated(1...200), cursor: "r2")) }
            if state.withLock({ s -> Bool in let failed = s.pageFailed; s.pageFailed = true; return !failed }) { return .failure(.hostUnreachable) }
            return .success(MlsRequestsPage(rows: generated(201...230), cursor: nil))
        case ("F3-1", "g-design"):
            startRequestScript()
            let ids = ["rq-ana", "rq-ben", "rq-chen", "rq-dana", "rq-eve", "rq-scout", "rq-anon"] + (fay ? ["rq-fay"] : [])
            return .success(MlsRequestsPage(rows: ids.filter { !approved.contains($0) && !declined.contains($0) }.compactMap(requestRow), cursor: nil))
        case ("F3-5", "g-design"): return .success(MlsRequestsPage(rows: ["rq-fay", "rq-hana"].filter { !approved.contains($0) }.compactMap(requestRow), cursor: nil))
        case ("F3-12", "g-design"): return .success(MlsRequestsPage(rows: ["rq-ana", "rq-ben"].filter { !approved.contains($0) }.compactMap(requestRow), cursor: nil))
        default: return .success(MlsRequestsPage(rows: [], cursor: nil))
        }
    }
    /// F3-1: 4 s after the first list read a request from Fay arrives as an event, and the same event again 1 s later.
    private func startRequestScript() {
        guard state.withLock({ $0.scripted.insert("requests").inserted }) else { return }
        after(4_000) { [self] in
            state.withLock { $0.fayArrived = true }
            if let fay = requestRow("rq-fay") { emit(.pendingJoin(groupID: "g-design", seq: envelopeSeq(), request: fay)) }
            after(1_000) { [self] in if let fay = requestRow("rq-fay") { emit(.pendingJoin(groupID: "g-design", seq: envelopeSeq(), request: fay)) } }
        }
    }
    fileprivate func approveScript(_ group: String, _ id: String) async -> Result<MlsAdminOutcome, MlsGroupError> {
        guard let row = requestRow(id) else { await pause(300); return .failure(.requestNotFound) }
        if id == "rq-ben" { await pause(300); state.withLock { _ = $0.declined.insert(id) }; return .failure(.requestNotFound) }
        if id == "rq-dana", fixtureID == "F3-1", state.withLock({ s -> Bool in let paced = s.danaPaced; s.danaPaced = true; return !paced }) {
            await pause(300); return .failure(.paced(retryAt: nowMillis() + 5_000))
        }
        await pause(id == "rq-eve" || (id == "rq-ana" && fixtureID == "F3-12") ? 3_000 : 300)
        let seq: Int64 = ["rq-ana": 301, "rq-eve": 302, "rq-dana": 303, "rq-fay": 304][id] ?? nextCommitSeq()
        after(1_000) { [self] in
            state.withLock { _ = $0.approved.insert(id) }
            emit(membershipEvent(group, seq: seq, [MlsMembershipChange(change: .joined, actor: MlsAuthor(anchor: row.anchor, display: row.display, aiFlag: row.aiFlag))], by: Self.me))
        }
        return .success(.committed(logSeq: seq))
    }

    // Member actions
    fileprivate func membershipEvent(_ group: String, seq: Int64, _ changes: [MlsMembershipChange], by: MlsAuthor?) -> MlsGroupEvent {
        .membership(groupID: group, seq: envelopeSeq(), at: nil, post: MlsPost(logSeq: seq, postID: "log:\(seq)", author: nil, appendedAt: nowMillis(), kind: .membership, body: .membership(changes: changes, by: by)))
    }
    fileprivate func removeOrBan(_ group: String, anchor: String, ban: Bool) async -> Result<MlsAdminOutcome, MlsGroupError> {
        switch (fixtureID, anchor) {
        case ("F3-3", "fx-gus"): await pause(300); return .failure(.ownerProtected)
        case ("F3-4", "fx-ana"):
            // The role changed elsewhere: the SDK refuses and the info read that follows says member.
            await pause(300); mutate(group) { $0.with(myRole: .member) }; return .failure(.notAdmin)
        case ("F3-11", _):
            after(1_000) { [self] in emit(membershipEvent(group, seq: 40, [MlsMembershipChange(change: .removed, actor: MlsAuthor(anchor: "fx-me", display: "Me", isMe: true), isMe: true)], by: Self.ana)) }
            await pause(3_000); return .success(.committed(logSeq: 41))
        case ("F3-5", _): await pause(3_000)
        default: await pause(400)
        }
        let seq: Int64 = fixtureID == "F3-5" ? 320 : (fixtureID == "F3-3" ? (anchor == "fx-dana" ? 312 : 313) : nextCommitSeq())
        let change = MlsMembershipChange(change: ban ? .banned : .removed, actor: person(anchor))
        after(1_000) { [self] in emit(membershipEvent(group, seq: seq, [change], by: Self.me)) }
        return .success(.committed(logSeq: seq))
    }

    // Events change the fixture the way the host would: infos, rosters and history follow them.
    fileprivate func applyToFixture(_ event: MlsGroupEvent) {
        func record(_ group: String, _ post: MlsPost) {
            state.withLock { s in
                guard let seq = post.logSeq, !(s.appended[group]?.contains { $0.logSeq == seq } ?? false) else { return }
                s.appended[group, default: []].append(post)
                if let info = s.admin[group], seq > info.lastLogSeq { s.admin[group] = info.with(lastLogSeq: seq) }
            }
        }
        switch event {
        case .membership(let group, _, _, let post):
            record(group, post)
            if case .membership(let changes, _) = post.body {
                state.withLock { s in
                    for change in changes {
                        switch change.change {
                        case .roleChanged: if let role = change.role { s.roles[change.actor.anchor] = role }
                        case .removed, .banned: s.gone.insert(change.actor.anchor)
                        default: break
                        }
                    }
                }
            }
        case .settings(let group, _, _, let post):
            record(group, post)
            if case .settings(let name, let approval, _) = post.body { mutate(group) { $0.with(name: name, approval: approval) } }
        case .post(let group, _, _, let post) where post.kind == .void: record(group, post)
        case .catchUp(let group, _, let catchUp): mutate(group) { $0.with(catchUp: catchUp) }
        case .warning(let group, _, let warning):
            mutate(group) { info in
                var rows = info.warnings.filter { $0.code.key != warning.code.key }
                if !warning.cleared { rows.append(MlsWarning(code: warning.code)) }
                return info.with(warnings: rows)
            }
        default: break
        }
    }

    // Scripts that start when a group's history is first read (the chat is open then).
    fileprivate func scriptAdminOnOpen(_ groupID: String) {
        guard state.withLock({ $0.scripted.insert(groupID).inserted }) else { return }
        switch (fixtureID, groupID) {
        case ("F3-7", "g-bookclub"), ("F3-7", "g-latecatch"):
            // Progress every 100 ms (Late catch: every 250 ms); only a skip ends it.
            Task { [self] in
                let top = groupID == "g-bookclub" ? 120 : 60, step = groupID == "g-bookclub" ? 100 : 250
                for done in 0...top {
                    if state.withLock({ $0.skipped.contains(groupID) }) { return }
                    emit(.catchUp(groupID: groupID, seq: envelopeSeq(), state: MlsCatchUp(state: .running, done: done, total: 120)))
                    await pause(step)
                }
            }
        case ("F3-8", "g-design"): Task { [self] in await warningScript(groupID) }
        case ("F3-8", "g-neighbours"):
            Task { [self] in
                await pause(2_000)
                emit(.warning(groupID: groupID, seq: envelopeSeq(), warning: MlsWarning(code: .headCommitRejected(logSeq: 250))))
                emit(.warning(groupID: groupID, seq: envelopeSeq(), warning: MlsWarning(code: .forkAlarm(headN: 2))))
            }
        case ("F3-10", "g-design"): after(3_000) { [self] in emit(.warning(groupID: groupID, seq: envelopeSeq(), warning: MlsWarning(code: .headCommitRejected(logSeq: 250)))) }
        default: break
        }
    }
    /// F3-8: four warnings at once (two banners and "+2"), then every code in turn, each cleared after 4 s, then the stale info read.
    private func warningScript(_ group: String) async {
        func set(_ code: MlsWarningCode) { emit(.warning(groupID: group, seq: envelopeSeq(), warning: MlsWarning(code: code))) }
        func clear(_ code: MlsWarningCode) { emit(.warning(groupID: group, seq: envelopeSeq(), warning: MlsWarning(code: code, cleared: true))) }
        await pause(2_000)
        let pile: [MlsWarningCode] = [.forkAlarm(headN: 2), .undecryptable(count: 12, fromLogSeq: 140), .hostUnusual(.lateRoll), .admissionNeedsOnline]
        for code in pile { set(code) }
        await pause(9_000)
        for code in pile { clear(code) }
        await pause(1_000)
        let single: [MlsWarningCode] = [.forkAlarm(headN: 2), .rejoinNeeded(.pruned), .rejoinNeeded(.gateRejected), .rejoinNeeded(.applyFailed), .rejoinNeeded(.welcomeExpired), .rejoinNeeded(.stateLost), .rejoinNeeded(.unknown("banana")), .undecryptable(count: 12, fromLogSeq: 140), .admissionNeedsOnline, .hostUnusual(.lateRoll), .headCommitRejected(logSeq: 250), .unknown("weird")]
        for code in single { set(code); await pause(4_000); clear(code); await pause(500) }
        // The stale read: a settings event starts an info read that is answered 3 s later and still lists the fork alarm.
        set(.forkAlarm(headN: 2))
        state.withLock { $0.staleFork = true }
        emit(.settings(groupID: group, seq: envelopeSeq(), at: nil, post: MlsPost(logSeq: 360, postID: "log:360", author: nil, appendedAt: nowMillis(), kind: .settings, body: .settings(name: nil, approval: nil, by: Self.ana))))
        await pause(1_500)
        clear(.forkAlarm(headN: nil))
    }
}
#endif
