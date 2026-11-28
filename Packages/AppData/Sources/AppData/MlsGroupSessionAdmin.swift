// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

// The admin owner of the MLS group session (MLS-GUI M3, common 3.1 to 3.7). It lives inside the account-scoped
// `MlsGroupSession`, so no view owns an outcome and `clear()` empties it with the rest (A9). Every admin write is one
// call per explicit, confirmed tap of a screen; no event, timer, unlock or outcome starts one (A2). The native repository
// answers every method with the typed unavailable outcome until the pin batch.

// MARK: Snapshot types

public enum MlsRequestsPhase: Equatable, Sendable { case idle, loading, loadError(MlsGroupError), loaded, loadingMore, pageError(MlsGroupError) }
public enum MlsRequestRowState: Equatable, Sendable { case idle, approving, adding, declining }

public struct MlsRequestRow: Equatable, Sendable, Identifiable {
    public var id: String { request.requestID }
    /// `aiFlag` is the OR of every row of the group that named this anchor (S8, A12).
    public let request: MlsJoinRequest
    public let state: MlsRequestRowState
    public let expired: Bool
}

public struct MlsRequestsSnapshot: Equatable, Sendable {
    public var rows: [MlsRequestRow] = []
    public var phase: MlsRequestsPhase = .idle
    /// More pages exist: the count is "more than" the loaded rows.
    public var more = false
    /// Approval is off: the entry is closed and an open screen shows the notice.
    public var approvalOff = false
    public init() {}
    public var count: Int { rows.count }
}

/// The one admin commit in flight for a group: running its call, or waiting for the matching event ("Updating…").
public struct MlsAdminBusy: Equatable, Sendable {
    public let kind: MlsAdminKind
    public let target: MlsAdminTarget
    public let waiting: Bool
}

public struct MlsAdminSnapshot: Equatable, Sendable {
    public var busy: MlsAdminBusy?
    /// Unix milliseconds until which every commit entry of the group is off (`paced{retry_at}`); the screen re-reads at that time.
    public var pacedUntil: Int64?
    public var notice: MlsAdminNotice?
    public var requests = MlsRequestsSnapshot()
    /// The push choice being saved, and a failed last choice.
    public var pushSaving: MlsPush?
    public var pushFailed = false
    public var catchUp: MlsCatchUpView?
    /// Every banner in order, hidden ones left out; the chat shows two and "+N".
    public var banners: [MlsBanner] = []
    /// The rows of group info: every warning but `host_ip_visible`.
    public var warningRows: [MlsWarningCode] = []
    /// The commit row the viewer may undo, and the head commit a `head_commit_rejected` names (admins only).
    public var voidableLogSeq: Int64?
    public var rejectedLogSeq: Int64?
    public var undecryptable: (count: Int, fromLogSeq: Int64?)?
    public var readOnly = false
    public init() {}
    public static func == (lhs: MlsAdminSnapshot, rhs: MlsAdminSnapshot) -> Bool {
        lhs.busy == rhs.busy && lhs.pacedUntil == rhs.pacedUntil && lhs.notice == rhs.notice && lhs.requests == rhs.requests && lhs.pushSaving == rhs.pushSaving && lhs.pushFailed == rhs.pushFailed
            && lhs.catchUp == rhs.catchUp && lhs.banners == rhs.banners && lhs.warningRows == rhs.warningRows && lhs.voidableLogSeq == rhs.voidableLogSeq && lhs.rejectedLogSeq == rhs.rejectedLogSeq
            && lhs.undecryptable?.count == rhs.undecryptable?.count && lhs.undecryptable?.fromLogSeq == rhs.undecryptable?.fromLogSeq && lhs.readOnly == rhs.readOnly
    }
}

// MARK: State

struct MlsAdminSlot {
    enum Phase: Equatable { case running, pending(Int64?) }
    var actionID: String
    var kind: MlsAdminKind
    var target: MlsAdminTarget
    var phase: Phase
}
struct MlsRequestsState {
    var rows: [MlsJoinRequest] = []
    var cursor: String?
    var phase: MlsRequestsPhase = .idle
    /// A page requested before the list was reset carries an older generation and is dropped (A10).
    var generation = 0
}
struct MlsCatchRecord {
    var state: MlsCatchUp.State = .idle
    var done = 0
    var total = 0
    /// The envelope `seq` of the newest applied event.
    var seq: Int64?
    /// Counts the events applied, so an info read issued before one does not apply its state.
    var events = 0
    /// Counts the changes of the state itself (a skip result applies only when this did not move).
    var stateGeneration = 0
    var skipError: MlsGroupError?
}
struct MlsSkipMark { var actionID: String; var fromGeneration: Int }
struct MlsPushMark { var actionID: String; var choice: MlsPush }
struct MlsInfoMark { var warnings: Int; var catchEvents: Int; var settingsEvents: Int }

/// Everything the admin owner holds for one account. Memory only: nothing here is persisted (no `UserDefaults`).
struct MlsAdminState {
    var slots: [String: MlsAdminSlot] = [:]
    /// The last 64 commit `log_seq`s applied per group, so an event that arrived before its reply resolves it at once.
    var applied: [String: [Int64]] = [:]
    var pacedUntil: [String: Int64] = [:]
    var requests: [String: MlsRequestsState] = [:]
    /// Decline in flight: group, request id to action id.
    var declining: [String: [String: String]] = [:]
    var push: [String: MlsPushMark] = [:]
    var pushFailed: Set<String> = []
    var catchUp: [String: MlsCatchRecord] = [:]
    var skip: [String: MlsSkipMark] = [:]
    var warnings: [String: MlsWarningSet] = [:]
    var hidden: [String: Set<String>] = [:]
    var notices: [String: MlsAdminNotice] = [:]
    /// Counts the settings events applied per group: a read issued before one keeps the event's name and switch.
    var settingsEvents: [String: Int] = [:]
    static let appliedLimit = 64
    static let requestLimit = 1000

    mutating func noteApplied(_ seq: Int64, group: String) {
        var list = applied[group] ?? []
        guard !list.contains(seq) else { return }
        list.append(seq)
        if list.count > Self.appliedLimit { list.removeFirst(list.count - Self.appliedLimit) }
        applied[group] = list
    }
    func isApplied(_ seq: Int64, group: String) -> Bool { applied[group]?.contains(seq) ?? false }
    /// Times at which a snapshot changes by the clock alone: a pace that ends, a request that expires.
    func wakeTimes() -> [Int64] {
        var times = Array(pacedUntil.values)
        for state in requests.values { times += state.rows.map(\.expiresAt).filter { $0 > 0 } }
        return times
    }
    /// Drops what a group that became read-only or unknown held.
    mutating func dropGroup(_ group: String) {
        slots[group] = nil; requests[group] = nil; declining[group] = nil; push[group] = nil; pushFailed.remove(group)
        skip[group] = nil; pacedUntil[group] = nil; notices[group] = nil
    }
}

// MARK: Reads and guards

extension MlsGroupSession {
    /// The group, when it is known, not read-only, and the viewer is its owner or an admin (`ownerOnly` narrows it to the owner).
    func canAdmin(_ group: String, ownerOnly: Bool = false) -> MlsGroupInfo? {
        guard admitted, let info = groups[group], timelines[group]?.readOnly == nil else { return nil }
        switch info.myRole {
        case .owner: return info
        case .admin: return ownerOnly ? nil : info
        default: return nil
        }
    }
    func adminMark(_ group: String) -> MlsInfoMark {
        MlsInfoMark(warnings: admin.warnings[group]?.generation ?? 0, catchEvents: admin.catchUp[group]?.events ?? 0, settingsEvents: admin.settingsEvents[group] ?? 0)
    }

    /// The head commit row the viewer may undo (common 2.6).
    func headCommit(_ group: String) -> Int64? {
        guard let store = timelines[group], store.loaded, let info = groups[group] else { return nil }
        var commits: [(seq: Int64, kind: MlsPostKind)] = []
        var voided: Set<Int64> = []
        for (seq, post) in store.posts {
            switch post.kind {
            case .membership, .settings: commits.append((seq, post.kind))
            case .void:
                commits.append((seq, .void))
                if case .void(let target?, _) = post.body { voided.insert(target) }
            default: break
            }
        }
        return MlsHeadCommit.voidable(commits: commits, voided: voided, detached: store.detached, role: info.myRole, readOnly: store.readOnly != nil)
    }
    func adminTimelineContext(_ group: String, isMe: @escaping (MlsAuthor) -> Bool, isAI: @escaping (MlsAuthor) -> Bool) -> MlsTimelineProjection.Context {
        var undecryptable: (count: Int, from: Int64?)?
        if case .undecryptable(let count, let from)? = admin.warnings[group]?.codes["undecryptable"] { undecryptable = (count, from) }
        var undoing: Int64?
        if let slot = admin.slots[group], slot.kind == .void, case .logSeq(let seq) = slot.target { undoing = seq }
        return MlsTimelineProjection.Context(isMe: isMe, isAI: isAI, voidable: headCommit(group), undoing: undoing, undecryptable: undecryptable)
    }

    public func adminSnapshot(_ group: String) -> MlsAdminSnapshot {
        var snapshot = MlsAdminSnapshot()
        let info = groups[group]
        let role = info?.myRole ?? .member
        snapshot.readOnly = timelines[group]?.readOnly != nil
        if let slot = admin.slots[group] {
            if case .pending = slot.phase { snapshot.busy = MlsAdminBusy(kind: slot.kind, target: slot.target, waiting: true) }
            else { snapshot.busy = MlsAdminBusy(kind: slot.kind, target: slot.target, waiting: false) }
        }
        snapshot.pacedUntil = admin.pacedUntil[group].flatMap { $0 > nowMillis ? $0 : nil }
        snapshot.notice = admin.notices[group]
        snapshot.requests = requestsSnapshot(group, info: info)
        snapshot.pushSaving = admin.push[group]?.choice
        snapshot.pushFailed = admin.pushFailed.contains(group)
        guard !snapshot.readOnly else { return snapshot }
        let codes = admin.warnings[group]?.codes ?? [:]
        var view: MlsCatchUpView?
        let record = admin.catchUp[group] ?? MlsCatchRecord()
        if case .rejoinNeeded(let reason)? = codes["rejoin_needed"] { view = .rejoining(reason: reason) }
        else if record.state == .rejoining { view = .rejoining(reason: nil) }
        else if record.state == .running { view = .running(done: record.done, total: record.total, skipping: admin.skip[group] != nil, error: record.skipError) }
        snapshot.catchUp = view
        snapshot.banners = MlsBannerPlan.banners(codes: codes, catchUp: view, role: role, hidden: admin.hidden[group] ?? [])
        snapshot.warningRows = MlsBannerPlan.rows(codes: codes, role: role)
        snapshot.voidableLogSeq = headCommit(group)
        if role == .owner || role == .admin, case .headCommitRejected(let seq)? = codes["head_commit_rejected"] { snapshot.rejectedLogSeq = seq }
        if case .undecryptable(let count, let from)? = codes["undecryptable"] { snapshot.undecryptable = (count, from) }
        return snapshot
    }

    private func requestsSnapshot(_ group: String, info: MlsGroupInfo?) -> MlsRequestsSnapshot {
        var snapshot = MlsRequestsSnapshot()
        snapshot.approvalOff = info?.approval == false
        guard let state = admin.requests[group] else { return snapshot }
        let ai = aiAnchors[group] ?? []
        let now = nowMillis
        let slot = admin.slots[group]
        let declining = admin.declining[group] ?? [:]
        snapshot.rows = state.rows.map { request in
            var rowState = MlsRequestRowState.idle
            if declining[request.requestID] != nil { rowState = .declining }
            if let slot, slot.kind == .approve, slot.target == .request(request.requestID) {
                if case .pending = slot.phase { rowState = .adding } else { rowState = .approving }
            }
            let merged = MlsJoinRequest(requestID: request.requestID, anchor: request.anchor, display: request.display, aiFlag: request.aiFlag || ai.contains(request.anchor), requestedAt: request.requestedAt, expiresAt: request.expiresAt)
            return MlsRequestRow(request: merged, state: rowState, expired: request.isExpired(now: now))
        }
        snapshot.phase = state.phase; snapshot.more = state.cursor != nil
        return snapshot
    }
    public func clearAdminNotice(_ group: String) { if admin.notices[group] != nil { admin.notices[group] = nil; changed() } }

    // MARK: Info and events feed the owner

    /// A `group.info` result issued at `mark`: warnings merge by the 2.7 rule, the catch-up state applies only when no
    /// catch-up event came since, and a commit the info already shows resolves the waiting action.
    func adminApplyInfo(_ info: MlsGroupInfo, group: String, mark: MlsInfoMark) {
        var set = admin.warnings[group] ?? MlsWarningSet()
        set.applyInfo(info.warnings, issued: mark.warnings)
        admin.warnings[group] = set
        var record = admin.catchUp[group] ?? MlsCatchRecord()
        if record.events == mark.catchEvents {
            if record.state != info.catchUp.state { record.stateGeneration += 1 }
            record.state = info.catchUp.state; record.done = info.catchUp.done; record.total = info.catchUp.total
            if info.catchUp.state != .running { record.skipError = nil }
            admin.catchUp[group] = record
        }
        // The info shows the commit (its `log_seq` is reached), or the reply had no `log_seq` and a read that followed it saw the group.
        if let slot = admin.slots[group], case .pending(let seq) = slot.phase, seq.map({ info.lastLogSeq >= $0 }) ?? true { resolveSlot(group, byEvent: false) }
    }
    func adminDropGroup(_ group: String) { admin.dropGroup(group) }

    /// A commit event of a group (membership, settings or void row) at `logSeq`: it resolves the action waiting for it.
    private func adminCommitApplied(_ logSeq: Int64?, group: String) -> Bool {
        guard let logSeq else { return false }
        let fresh = !admin.isApplied(logSeq, group: group)
        admin.noteApplied(logSeq, group: group)
        if let slot = admin.slots[group], case .pending(let seq?) = slot.phase, seq == logSeq { resolveSlot(group, byEvent: true) }
        return fresh
    }
    /// Frees the slot; an approved request leaves the list, and a member action reads the members again when no event showed it.
    private func resolveSlot(_ group: String, byEvent: Bool) {
        guard let slot = admin.slots.removeValue(forKey: group) else { return }
        if slot.kind == .approve, case .request(let id) = slot.target { admin.requests[group]?.rows.removeAll { $0.requestID == id } }
        if !byEvent, [.role, .remove, .ban].contains(slot.kind) { Task { [weak self] in await self?.reloadMembers(group) } }
        changed()
    }
    func reloadMembers(_ group: String) async {
        guard admitted, let snapshot = members[group], snapshot.phase == .done || snapshot.phase == .idle else { return }
        memberCursor[group] = nil
        await loadMemberPage(group, first: true)
    }

    /// A member page that no longer lists the removed or banned member shows the result (only once every page is loaded).
    func adminMembersLoaded(_ group: String) {
        guard let slot = admin.slots[group], case .pending = slot.phase, slot.kind == .remove || slot.kind == .ban, case .member(let anchor) = slot.target, let snapshot = members[group], !snapshot.hasMore, snapshot.phase == .done, !snapshot.rows.contains(where: { $0.anchor == anchor }) else { return }
        resolveSlot(group, byEvent: true)
    }

    func adminMembershipApplied(_ post: MlsPost, group: String) {
        guard case .membership(let changes, _) = post.body else { return }
        _ = adminCommitApplied(post.logSeq, group: group)
        for change in changes {
            let anchor = change.actor.anchor
            switch change.change {
            case .joined: admin.requests[group]?.rows.removeAll { $0.anchor == anchor }
            case .removed, .banned: members[group]?.rows.removeAll { $0.anchor == anchor }
            case .roleChanged:
                if let role = change.role, let at = members[group]?.rows.firstIndex(where: { $0.anchor == anchor }), let row = members[group]?.rows[at] {
                    members[group]?.rows[at] = MlsMemberRow(anchor: row.anchor, display: row.display, role: role, aiFlag: row.aiFlag, devices: row.devices, isMe: row.isMe)
                }
            default: break
            }
        }
    }
    func adminSettingsApplied(_ post: MlsPost, group: String) {
        guard case .settings(let name, let approval, _) = post.body else { return }
        _ = adminCommitApplied(post.logSeq, group: group)
        // The confirmed value shows from the event: name and switch follow it, never the requested value.
        if let info = groups[group], name != nil || approval != nil { groups[group] = info.with(name: name, approval: approval) }
        admin.settingsEvents[group, default: 0] += 1
        if approval == true { admin.warnings[group, default: MlsWarningSet()].drop(key: "admission_needs_online"); admin.hidden[group]?.remove("admission_needs_online") }
    }
    /// A void row (arrived as `post{kind: void}` or `kind: void`): the voided row gets its mark from the row itself; the
    /// roster may revert, so info and the loaded member pages are read again (once per `log_seq`).
    func adminVoidApplied(_ post: MlsPost, group: String) {
        guard adminCommitApplied(post.logSeq, group: group) else { return }
        scheduleInfo(group)
        if members[group] != nil { Task { [weak self] in await self?.reloadMembers(group) } }
    }

    func adminPendingJoin(group: String, request: MlsJoinRequest) {
        guard let info = groups[group], info.approval, info.myRole == .owner || info.myRole == .admin, timelines[group]?.readOnly == nil else { return }
        if request.aiFlag { aiAnchors[group, default: []].insert(request.anchor) }
        var state = admin.requests[group] ?? MlsRequestsState()
        guard !state.rows.contains(where: { $0.requestID == request.requestID }), state.rows.count < MlsAdminState.requestLimit else { return }
        state.rows.append(request)
        state.rows.sort { ($0.requestedAt, $0.requestID) < ($1.requestedAt, $1.requestID) }
        admin.requests[group] = state
    }

    func adminCatchUp(group: String, seq: Int64?, state: MlsCatchUp) {
        var record = admin.catchUp[group] ?? MlsCatchRecord()
        if let seq, let last = record.seq, seq <= last { return }
        if let seq { record.seq = seq }
        record.events += 1
        let wasRejoining = record.state == .rejoining
        if record.state != state.state { record.stateGeneration += 1 }
        record.state = state.state; record.done = state.done; record.total = state.total
        if state.state != .running { record.skipError = nil }
        admin.catchUp[group] = record
        // The floor moved: read the newest page and the info again (no other call).
        if wasRejoining, state.state == .idle { Task { [weak self] in await self?.loadNewest(group); _ = await self?.refreshInfo(group) } }
    }
    func adminWarning(group: String, warning: MlsWarning) {
        admin.warnings[group, default: MlsWarningSet()].apply(warning)
        if warning.cleared { admin.hidden[group]?.remove(warning.code.key) }
    }

    // MARK: Requests (common 3.2)

    /// Group info opens for an admin of an approval group: the first page loads once.
    public func prepareRequests(_ group: String) async {
        guard let info = canAdmin(group), info.approval, (admin.requests[group]?.phase ?? .idle) == .idle else { return }
        await loadRequestsPage(group, first: true)
    }
    /// The requests screen opens: the list is read again.
    public func openRequests(_ group: String) async {
        guard let info = canAdmin(group), info.approval else { return }
        if admin.requests[group]?.phase == .loading { return }
        await loadRequestsPage(group, first: true)
    }
    /// Within 20 rows of the end. After a failed page nothing loads until `retryRequests`.
    public func loadMoreRequests(_ group: String) async {
        guard canAdmin(group)?.approval == true, let state = admin.requests[group], state.cursor != nil, state.phase == .loaded else { return }
        await loadRequestsPage(group, first: false)
    }
    /// The user's "Try again": the only way a failed read is requested again.
    public func retryRequests(_ group: String) async {
        guard canAdmin(group)?.approval == true, let phase = admin.requests[group]?.phase else { return }
        switch phase {
        case .loadError: await loadRequestsPage(group, first: true)
        case .pageError: await loadRequestsPage(group, first: false)
        default: break
        }
    }
    private func loadRequestsPage(_ group: String, first: Bool) async {
        guard canAdmin(group)?.approval == true else { return }
        let token = epoch
        var state = admin.requests[group] ?? MlsRequestsState()
        if first { state.generation += 1; state.cursor = nil } else if state.phase == .loadingMore { return }
        let generation = state.generation, cursor = first ? nil : state.cursor
        state.phase = first ? .loading : .loadingMore
        admin.requests[group] = state; changed()
        let result = await repository.requests(account: account, groupID: group, cursor: cursor, limit: 200)
        guard live(token), canAdmin(group)?.approval == true, var next = admin.requests[group], next.generation == generation else { return }
        switch result {
        case .success(let page):
            if first { next.rows = [] }
            var seen = Set(next.rows.map(\.requestID))
            for row in page.rows where seen.insert(row.requestID).inserted && next.rows.count < MlsAdminState.requestLimit {
                if row.aiFlag { aiAnchors[group, default: []].insert(row.anchor) }
                next.rows.append(row)
            }
            next.rows.sort { ($0.requestedAt, $0.requestID) < ($1.requestedAt, $1.requestID) }
            next.cursor = page.cursor; next.phase = .loaded
            admin.requests[group] = next
            // A re-read that no longer lists the approved request shows the result (3.1 rule 3).
            if page.cursor == nil, let slot = admin.slots[group], slot.kind == .approve, case .pending = slot.phase, case .request(let id) = slot.target, !next.rows.contains(where: { $0.requestID == id }) { resolveSlot(group, byEvent: true) }
        case .failure(let error):
            next.phase = first ? .loadError(error) : .pageError(error)
            admin.requests[group] = next
        }
        changed()
    }

    /// Approve: one admin commit, after its confirmation.
    @discardableResult public func approve(_ group: String, requestID: String) async -> Bool {
        guard let info = canAdmin(group), info.approval, let row = admin.requests[group]?.rows.first(where: { $0.requestID == requestID }), !row.isExpired(now: nowMillis), admin.declining[group]?[requestID] == nil else { return false }
        return await runCommit(group, kind: .approve, target: .request(requestID)) { [repository, account] in await repository.approve(account: account, groupID: group, requestID: requestID) }
    }
    /// Decline commits nothing: the row leaves on the reply. It has its own in-flight mark per request.
    public func decline(_ group: String, requestID: String) async {
        guard let info = canAdmin(group), info.approval, let row = admin.requests[group]?.rows.first(where: { $0.requestID == requestID }), !row.isExpired(now: nowMillis), admin.declining[group]?[requestID] == nil else { return }
        if let slot = admin.slots[group], slot.kind == .approve, slot.target == .request(requestID) { return }
        let token = epoch, id = makeID()
        admin.declining[group, default: [:]][requestID] = id; admin.notices[group] = nil; changed()
        let result = await repository.decline(account: account, groupID: group, requestID: requestID)
        guard live(token), admin.declining[group]?[requestID] == id else { return }
        admin.declining[group]?[requestID] = nil
        guard groups[group] != nil, timelines[group]?.readOnly == nil else { changed(); return }
        switch result {
        case .success(.declined), .success(.committed): admin.requests[group]?.rows.removeAll { $0.requestID == requestID }
        case .failure(.requestNotFound):
            admin.requests[group]?.rows.removeAll { $0.requestID == requestID }
            admin.notices[group] = MlsAdminNotice(error: .requestNotFound, isToast: true)
        case .failure(let error): admin.notices[group] = MlsAdminNotice(error: error)
        }
        changed()
    }

    // MARK: Member actions (common 3.3)

    private func memberRow(_ group: String, anchor: String) -> MlsMemberRow? {
        members[group]?.rows.first { $0.anchor == anchor && !$0.isMe && $0.anchor != myAnchor }
    }
    /// Make admin or make member: the owner only.
    @discardableResult public func setRole(_ group: String, anchor: String, role: MlsRole) async -> Bool {
        guard canAdmin(group, ownerOnly: true) != nil, let row = memberRow(group, anchor: anchor) else { return false }
        switch role {
        case .admin: guard row.role == .member else { return false }
        case .member: guard row.role == .admin else { return false }
        default: return false
        }
        return await runCommit(group, kind: .role, target: .member(anchor)) { [repository, account] in await repository.setRole(account: account, groupID: group, anchor: anchor, role: role) }
    }
    /// The owner removes any member but the owner; an admin removes plain members only.
    private func canActOnMember(_ group: String, anchor: String) -> Bool {
        guard let info = canAdmin(group), let row = memberRow(group, anchor: anchor) else { return false }
        return info.myRole == .owner ? row.role != .owner : row.role == .member
    }
    @discardableResult public func removeMember(_ group: String, anchor: String) async -> Bool {
        guard canActOnMember(group, anchor: anchor) else { return false }
        return await runCommit(group, kind: .remove, target: .member(anchor)) { [repository, account] in await repository.removeMember(account: account, groupID: group, anchor: anchor) }
    }
    @discardableResult public func banMember(_ group: String, anchor: String) async -> Bool {
        guard canActOnMember(group, anchor: anchor) else { return false }
        return await runCommit(group, kind: .ban, target: .member(anchor)) { [repository, account] in await repository.banMember(account: account, groupID: group, anchor: anchor) }
    }

    // MARK: Settings and push (common 3.4)

    /// The name form: one call with `{name}` only; an invalid or unchanged name makes no call.
    @discardableResult public func setName(_ group: String, name raw: String) async -> Bool {
        guard let info = canAdmin(group), case .ok(let name) = MlsAdminRules.checkName(raw), name != info.name else { return false }
        return await runCommit(group, kind: .settings, target: .setting(.name)) { [repository, account] in await repository.setSettings(account: account, groupID: group, name: name, approval: nil) }
    }
    /// The approval switch: one call with `{approval}` only.
    @discardableResult public func setApproval(_ group: String, on: Bool) async -> Bool {
        guard let info = canAdmin(group), info.approval != on else { return false }
        return await runCommit(group, kind: .settings, target: .setting(.approval)) { [repository, account] in await repository.setSettings(account: account, groupID: group, name: nil, approval: on) }
    }
    /// The per-device push picker: every member of a group that is not read-only. The value changes on the reply only.
    public func setPush(_ group: String, _ push: MlsPush) async {
        guard admitted, groups[group] != nil, timelines[group]?.readOnly == nil, admin.push[group] == nil else { return }
        if case .unknown = push { return }
        let token = epoch, id = makeID()
        admin.push[group] = MlsPushMark(actionID: id, choice: push); admin.pushFailed.remove(group); changed()
        let result = await repository.setPush(account: account, groupID: group, push: push)
        guard live(token), admin.push[group]?.actionID == id else { return }
        admin.push[group] = nil
        guard let info = groups[group], timelines[group]?.readOnly == nil else { changed(); return }
        switch result {
        case .success(let value): groups[group] = info.with(push: value)
        case .failure: admin.pushFailed.insert(group)
        }
        changed()
    }

    // MARK: Catch-up skip (common 3.5)

    /// "Skip" in the dialog: the only path to `skip: true`. Only while the catch-up runs, one call at a time.
    public func skipCatchUp(_ group: String) async {
        guard admitted, groups[group] != nil, timelines[group]?.readOnly == nil, admin.skip[group] == nil, let record = admin.catchUp[group], record.state == .running, admin.warnings[group]?.codes["rejoin_needed"] == nil else { return }
        let token = epoch, id = makeID()
        admin.skip[group] = MlsSkipMark(actionID: id, fromGeneration: record.stateGeneration)
        admin.catchUp[group]?.skipError = nil; changed()
        let result = await repository.skipCatchUp(account: account, groupID: group)
        guard live(token), let mark = admin.skip[group], mark.actionID == id else { return }
        admin.skip[group] = nil
        guard groups[group] != nil, timelines[group]?.readOnly == nil else { changed(); return }
        switch result {
        case .success(let value):
            // A newer catch-up state (an idle event, say) wins: the late result changes nothing.
            guard var record = admin.catchUp[group], record.stateGeneration == mark.fromGeneration else { break }
            switch value {
            case .rejoining: record.state = .rejoining
            case .running(let done, let total): record.state = .running; record.done = done; record.total = total
            case .idle: record.state = .idle
            }
            record.stateGeneration += 1
            admin.catchUp[group] = record
        case .failure(let error): admin.catchUp[group]?.skipError = error
        }
        changed()
    }

    // MARK: Void (common 3.6)

    /// "Undo this change" for the commit the confirmation named (the head commit row, or the one a `head_commit_rejected`
    /// names). After its confirmation. The SDK is the authority on which commit is the head: when a newer commit arrived
    /// while the dialog was open it refuses with `void_not_head` (common 2.6 rule 4), and nothing is retried.
    @discardableResult public func void(_ group: String, logSeq: Int64) async -> Bool {
        guard canAdmin(group) != nil else { return false }
        return await runCommit(group, kind: .void, target: .logSeq(logSeq)) { [repository, account] in await repository.void(account: account, groupID: group, logSeq: logSeq) }
    }

    /// `undecryptable`, `host_unusual` and `admission_needs_online` can be hidden for the session.
    public func hideWarning(_ group: String, code: String) {
        guard ["undecryptable", "host_unusual", "admission_needs_online"].contains(code) else { return }
        admin.hidden[group, default: []].insert(code); changed()
    }

    // MARK: The one commit runner

    /// One admin commit at a time per group (3.1 rule 1). The result applies only when the epoch is unchanged, the group
    /// is still known and not read-only, and the slot still holds this action (rule 2).
    private func runCommit(_ group: String, kind: MlsAdminKind, target: MlsAdminTarget, call: @escaping @Sendable () async -> Result<MlsAdminOutcome, MlsGroupError>) async -> Bool {
        guard admin.slots[group] == nil, (admin.pacedUntil[group] ?? 0) <= nowMillis else { return false }
        let token = epoch, id = makeID()
        admin.slots[group] = MlsAdminSlot(actionID: id, kind: kind, target: target, phase: .running)
        admin.notices[group] = nil
        changed()
        let result = await call()
        guard live(token), admin.slots[group]?.actionID == id else { return false }
        guard groups[group] != nil, timelines[group]?.readOnly == nil else { admin.slots[group] = nil; changed(); return false }
        switch result {
        case .success(.committed(let seq)):
            if let seq, admin.isApplied(seq, group: group) { resolveSlot(group, byEvent: true) }
            else { admin.slots[group]?.phase = .pending(seq) }
            scheduleInfo(group)
        case .success(.declined):
            admin.slots[group] = nil
            admin.notices[group] = MlsAdminNotice(error: .generic(nil), kind: kind)
        case .failure(let error):
            admin.slots[group] = nil
            admin.notices[group] = MlsAdminNotice(error: error, isToast: error == .requestNotFound, kind: kind)
            switch error {
            case .paced(let at): admin.pacedUntil[group] = at
            case .requestNotFound: if kind == .approve, case .request(let request) = target { admin.requests[group]?.rows.removeAll { $0.requestID == request } }
            case .notAdmin, .notOwner: scheduleInfo(group)
            case .voidNotHead: Task { [weak self] in await self?.fillGap(group) }
            default: break
            }
        }
        changed()
        return true
    }
}
