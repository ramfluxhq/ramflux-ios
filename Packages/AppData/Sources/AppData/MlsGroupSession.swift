// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// The group list as the screen shows it.
public struct MlsListSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case loading, loaded, failed(MlsGroupError) }
    public var rows: [MlsGroupInfo] = []
    public var phase: Phase = .loading
    public var moreAvailable = false
    public var loadingMore = false
    /// Join requests that are still waiting, shown as one row at the top of the list.
    public var pendingJoins: [MlsPendingJoin] = []
    public init() {}
}

/// What the join sheet shows: only the outcome of its own attempt.
public enum MlsJoinOutcome: Equatable, Sendable {
    case joined(groupID: String)
    case pending(requestID: String, reason: MlsPendingReason, expiresAt: Int64)
    case refused(MlsJoinRefusal, local: Bool)
    case failed(MlsGroupError)
}
public struct MlsJoinSnapshot: Equatable, Sendable {
    public var attempt = 0
    public var joining = false
    public var outcome: MlsJoinOutcome?
    public init() {}
}

public struct MlsInviteSnapshot: Equatable, Sendable {
    public var invites: [MlsInvite] = []
    public var loading = false
    public var creating = false
    public var revoking: Set<String> = []
    public var error: MlsGroupError?
    public init() {}
}

public struct MlsMembersSnapshot: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, loading, pageError(MlsGroupError), done }
    public var rows: [MlsMemberRow] = []
    public var phase: Phase = .idle
    public var hasMore = false
    public var pagesLoaded = 0
    /// True while a search is loading the remaining pages.
    public var loadingAll = false
    public init() {}
}

public enum MlsLinkCheck {
    /// S2: the trimmed link is 1 to 512 printable ASCII characters (0x21 to 0x7E). The only change is trimming
    /// leading and trailing ASCII whitespace. Nothing parses the link.
    public static func trimmed(_ raw: String) -> String? {
        let scalars = Array(raw.unicodeScalars)
        var start = 0, end = scalars.count
        func space(_ scalar: Unicode.Scalar) -> Bool { scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{0B}" || scalar == "\u{0C}" }
        while start < end, space(scalars[start]) { start += 1 }
        while end > start, space(scalars[end - 1]) { end -= 1 }
        let body = scalars[start..<end]
        guard !body.isEmpty, body.count <= 512, body.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { return nil }
        var result = String.UnicodeScalarView(); result.append(contentsOf: body)
        return String(result)
    }
}

/// The account-scoped owner of everything M2 records outside a view (S4, S5): the join owner, the send owner, the
/// timeline stores, the member pages, the invites and the group list. Views read snapshots and send intents; they never
/// run a call, so closing a screen never loses an outcome. `clear()` empties it on lock and on removal, and it refuses
/// writes until `admit()`; a call that returns after a clear is dropped (lesson R4-F2). Nothing here retries a call by itself.
public actor MlsGroupSession {
    public let account: String
    let repository: any MlsGroupRepository
    let now: @Sendable () -> Date
    let makeID: @Sendable () -> String
    var admitted = true
    var epoch = 0
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var eventTask: Task<Void, Never>?

    // List
    var groups: [String: MlsGroupInfo] = [:]
    private var eventNewer: Set<String> = []
    private var listCursor: String?
    private var listPhase: MlsListSnapshot.Phase = .loading
    private var listLoading = false
    private var listLoadingMore = false
    private var pendingJoins: [String: MlsPendingJoin] = [:]
    private var openGroup: String?
    // Join owner
    private var joinAttempt = 0
    private var joinInFlight: Int?
    private var joinOutcome: MlsJoinOutcome?
    private var requestAttempts: [String: Int] = [:]
    // Create
    private var creating = false
    // Per group
    var timelines: [String: MlsTimelineStore] = [:]
    private var recent: [String] = []
    private var invites: [String: MlsInviteSnapshot] = [:]
    var members: [String: MlsMembersSnapshot] = [:]
    var memberCursor: [String: String] = [:]
    var aiAnchors: [String: Set<String>] = [:]
    var myAnchor: String?
    private var lastRefresh: [String: Date] = [:]
    var lastInfoRead: [String: Date] = [:]
    private var infoQueued: Set<String> = []
    private var markedRead: [String: Int64] = [:]
    /// Send records of a group whose timeline was evicted (S4): not-sent bubbles and sends still in flight survive until
    /// lock or removal, so a reopened group still shows them and a late reply still lands on its record.
    private struct EvictedSend { var pending: [MlsPendingPost]; var composerOffUntil: Int64? }
    private var evictedSend: [String: EvictedSend] = [:]
    private var wakeTask: Task<Void, Never>?
    private var wakeAt: Int64?
    /// The M3 admin owner state (common 3.1 to 3.7): the slot, requests, push, skip, catch-up and warning records of the account.
    var admin = MlsAdminState()
    static let recentGroups = 3
    static let refreshWindow: TimeInterval = 5

    public init(account: String, repository: any MlsGroupRepository, now: @escaping @Sendable () -> Date = { Date() }, makeID: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.account = account; self.repository = repository; self.now = now; self.makeID = makeID
    }

    // MARK: Lifecycle and observation
    /// Changes of any snapshot. The stream carries no data; the reader asks for the snapshot it shows.
    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    func changed() { for continuation in observers.values { continuation.yield(()) }; scheduleWake() }
    /// One timer at the earliest future time a snapshot changes by the clock alone (a rate-limit reset or a pending join
    /// that expires). It only publishes a change so the screen re-reads its snapshot; it never sends anything.
    private func scheduleWake() {
        guard admitted else { wakeTask?.cancel(); wakeTask = nil; wakeAt = nil; return }
        let current = nowMillis
        var times: [Int64] = timelines.values.compactMap(\.composerOffUntil) + evictedSend.values.compactMap(\.composerOffUntil)
        times += pendingJoins.values.map(\.expiresAt)
        times += admin.wakeTimes()
        times += groups.values.compactMap { if case .waiting(let after) = $0.privacyDelay { after } else { nil } }
        let next = times.filter { $0 > current }.min()
        guard next != wakeAt else { return }
        wakeTask?.cancel(); wakeTask = nil; wakeAt = next
        guard let next else { return }
        let token = epoch
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(next - current + 5))
            guard !Task.isCancelled else { return }
            await self?.wake(token)
        }
    }
    private func wake(_ token: Int) {
        guard live(token) else { return }
        wakeTask = nil; wakeAt = nil
        changed()
    }
    public var isAdmitted: Bool { admitted }

    /// Starts the `group.event` consumer once. The native repository feeds it from the hub.
    public func start() {
        guard admitted, eventTask == nil else { return }
        let stream = repository.events(account: account)
        eventTask = Task { [weak self] in
            for await event in stream { await self?.handle(event) }
        }
    }

    /// Lock and account removal: drops every record in memory and refuses writes until `admit()`.
    public func clear() {
        admitted = false; epoch &+= 1
        eventTask?.cancel(); eventTask = nil
        groups = [:]; eventNewer = []; listCursor = nil; listPhase = .loading; listLoading = false; listLoadingMore = false; pendingJoins = [:]; openGroup = nil
        joinAttempt = 0; joinInFlight = nil; joinOutcome = nil; requestAttempts = [:]; creating = false
        timelines = [:]; recent = []; invites = [:]; members = [:]; memberCursor = [:]; aiAnchors = [:]; myAnchor = nil
        lastRefresh = [:]; lastInfoRead = [:]; infoQueued = []; markedRead = [:]; evictedSend = [:]
        admin = MlsAdminState()
        wakeTask?.cancel(); wakeTask = nil; wakeAt = nil
        changed()
    }
    /// The account is unlocked again: writes are accepted and the event consumer restarts.
    public func admit() { guard !admitted else { return }; admitted = true; start(); changed() }

    func live(_ token: Int) -> Bool { admitted && token == epoch }
    var nowMillis: Int64 { Int64(now().timeIntervalSince1970 * 1000) }

    // MARK: Snapshots
    public func listSnapshot() -> MlsListSnapshot {
        var snapshot = MlsListSnapshot()
        snapshot.rows = groups.values.sorted { ($0.lastActivityAt, $1.groupID) > ($1.lastActivityAt, $0.groupID) }
        snapshot.phase = listPhase; snapshot.moreAvailable = listCursor != nil; snapshot.loadingMore = listLoadingMore
        snapshot.pendingJoins = pendingJoins.values.filter { $0.expiresAt == 0 || $0.expiresAt > nowMillis }.sorted { $0.requestedAt > $1.requestedAt }
        return snapshot
    }
    public func joinSnapshot() -> MlsJoinSnapshot {
        var snapshot = MlsJoinSnapshot()
        snapshot.attempt = joinAttempt; snapshot.joining = joinInFlight != nil; snapshot.outcome = joinOutcome
        return snapshot
    }
    public func group(_ id: String) -> MlsGroupInfo? { groups[id] }
    public func inviteSnapshot(_ group: String) -> MlsInviteSnapshot { invites[group] ?? MlsInviteSnapshot() }
    public func membersSnapshot(_ group: String) -> MlsMembersSnapshot {
        var snapshot = members[group] ?? MlsMembersSnapshot()
        let ai = aiAnchors[group] ?? [], me = myAnchor
        snapshot.rows = snapshot.rows.map { row in MlsMemberRow(anchor: row.anchor, display: row.display, role: row.role, aiFlag: row.aiFlag || ai.contains(row.anchor), devices: row.devices, isMe: row.isMe || row.anchor == me) }
        return snapshot
    }
    public func isReadOnly(_ group: String) -> MlsReadOnly? { timelines[group]?.readOnly }
    public func timelineSnapshot(_ group: String) -> MlsTimelineSnapshot {
        guard let store = timelines[group] else { return MlsTimelineSnapshot(groupID: group) }
        var snapshot = MlsTimelineSnapshot(groupID: group)
        let ai = aiAnchors[group] ?? [], me = myAnchor
        let context = adminTimelineContext(group, isMe: { $0.isMe || (me != nil && $0.anchor == me) }, isAI: { $0.aiFlag || ai.contains($0.anchor) })
        snapshot.entries = MlsTimelineProjection.entries(store, mine: { post in post.author.map { $0.isMe || (me != nil && $0.anchor == me) } ?? false }, context: context)
        snapshot.phase = store.phase; snapshot.olderAvailable = store.olderMore; snapshot.loadingOlder = store.loadingOlder; snapshot.detached = store.detached
        snapshot.readOnly = store.readOnly; snapshot.composerOffUntil = store.composerOffUntil.flatMap { $0 > nowMillis ? $0 : nil }
        snapshot.actionError = store.actionError; snapshot.newestLogSeq = store.last
        return snapshot
    }
    /// Members already loaded for the mention picker (the own account is left out).
    public func mentionCandidates(_ group: String) -> [MlsMemberRow] { membersSnapshot(group).rows.filter { !$0.isMe } }
    public func clearActionError(_ group: String) { timelines[group]?.actionError = nil; changed() }

    // MARK: Absorbing SDK rows (S8)
    func absorb(_ author: MlsAuthor?, group: String) {
        guard let author, !author.anchor.isEmpty else { return }
        if author.aiFlag { aiAnchors[group, default: []].insert(author.anchor) }
        if author.isMe { myAnchor = author.anchor }
    }
    func absorb(_ post: MlsPost, group: String) {
        absorb(post.author, group: group)
        switch post.body {
        case .membership(let changes, let by):
            absorb(by, group: group)
            for change in changes { absorb(change.actor, group: group); if change.isMe { myAnchor = change.actor.anchor } }
        case .settings(_, _, let by): absorb(by, group: group)
        case .void(_, let by): absorb(by, group: group)
        default: break
        }
    }

    // MARK: Group list
    /// Loads the first page. The rows already shown stay until the new page arrives.
    public func loadList() async {
        guard admitted, !listLoading else { return }
        let token = epoch
        listLoading = true
        if groups.isEmpty { listPhase = .loading }
        changed()
        let result = await repository.list(account: account, cursor: nil, limit: 50)
        let pendingResult = await repository.joinPending(account: account)
        guard live(token) else { return }
        listLoading = false
        switch result {
        case .success(let page):
            groups = [:]; eventNewer = []
            merge(page.groups); listCursor = page.cursor; listPhase = .loaded
        case .failure(let error): listPhase = .failed(error)
        }
        if case .success(let rows) = pendingResult { for row in rows { pendingJoins[row.requestID] = row } }
        changed()
    }
    public func loadMoreList() async {
        guard admitted, !listLoading, !listLoadingMore, let cursor = listCursor else { return }
        let token = epoch
        listLoadingMore = true; changed()
        let result = await repository.list(account: account, cursor: cursor, limit: 50)
        guard live(token) else { return }
        listLoadingMore = false
        switch result {
        case .success(let page): merge(page.groups); listCursor = page.cursor
        case .failure(let error): listPhase = .failed(error)
        }
        changed()
    }
    /// Common 2.2: deduplicated by `group_id`; a later row replaces the stored one only when its `last_activity_at` is
    /// greater or equal, and a row for a group an event already updated is ignored (events are newer).
    private func merge(_ rows: [MlsGroupInfo]) {
        for row in rows where !eventNewer.contains(row.groupID) {
            if let post = row.lastPost { absorb(post.author, group: row.groupID) }
            if let stored = groups[row.groupID], stored.lastActivityAt > row.lastActivityAt { continue }
            groups[row.groupID] = row
        }
    }

    /// Reads `group.info` (when a group opens, on a settings or membership event, after an own action).
    @discardableResult public func refreshInfo(_ group: String) async -> MlsGroupError? {
        guard admitted else { return .unavailable }
        let token = epoch
        let mark = adminMark(group)
        let result = await repository.info(account: account, groupID: group)
        guard live(token) else { return nil }
        lastInfoRead[group] = now()
        switch result {
        case .success(let info):
            // A name or switch an event confirmed after this read was issued is newer than the read: keep the event's value.
            let kept = mark.settingsEvents != (admin.settingsEvents[group] ?? 0) ? groups[group] : nil
            groups[group] = info.with(lastActivityAt: max(info.lastActivityAt, groups[group]?.lastActivityAt ?? 0), name: kept?.name, approval: kept?.approval)
            adminApplyInfo(info, group: group, mark: mark)
            changed(); return nil
        case .failure(let error):
            if error == .notMember, timelines[group] != nil, timelines[group]?.readOnly == nil { timelines[group]?.readOnly = .left; adminDropGroup(group); changed() }
            return error
        }
    }
    /// Info reads caused by events are coalesced to at most one per second per group.
    func scheduleInfo(_ group: String) {
        if let last = lastInfoRead[group], now().timeIntervalSince(last) < 1 {
            guard infoQueued.insert(group).inserted else { return }
            let token = epoch
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                await self?.runQueuedInfo(group, token: token)
            }
        } else {
            lastInfoRead[group] = now()
            Task { [weak self] in _ = await self?.refreshInfo(group) }
        }
    }
    private func runQueuedInfo(_ group: String, token: Int) async {
        infoQueued.remove(group)
        guard live(token) else { return }
        _ = await refreshInfo(group)
    }

    // MARK: Join owner (common 3.1)
    /// One call per explicit tap. Returns the attempt number, or nil when the tap was ignored (a call of the sheet's
    /// join of this account is in flight).
    @discardableResult public func join(link raw: String) async -> Int? {
        guard admitted else { return nil }
        if joinInFlight != nil { return nil }   // one join per account at a time, even after the sheet was closed
        joinAttempt += 1
        let attempt = joinAttempt
        guard let link = MlsLinkCheck.trimmed(raw) else {
            joinOutcome = .refused(.linkInvalid, local: true); changed(); return attempt
        }
        let token = epoch
        joinInFlight = attempt; joinOutcome = nil; changed()
        let result = await repository.join(account: account, link: link)
        guard live(token) else { return attempt }
        if joinInFlight == attempt { joinInFlight = nil }
        let current = attempt == joinAttempt
        switch result {
        case .success(.joined(let group)):
            // Recorded even for an older attempt, so a joined group is never lost.
            if current { joinOutcome = .joined(groupID: group) }
            Task { [weak self] in _ = await self?.refreshInfo(group); await self?.loadList() }
        case .success(.pending(let request, let reason, let expires)):
            pendingJoins[request] = MlsPendingJoin(requestID: request, groupID: "", hostNode: nil, reason: reason, requestedAt: nowMillis, expiresAt: expires)
            requestAttempts[request] = attempt
            if current { joinOutcome = .pending(requestID: request, reason: reason, expiresAt: expires) }
        case .success(.refused(let refusal)): if current { joinOutcome = .refused(refusal, local: false) }
        case .failure(let error): if current { joinOutcome = .failed(error) }
        }
        changed()
        return attempt
    }
    /// The sheet closed: the field is cleared by the view, the outcome of the closed attempt is not shown to the next
    /// one, and a call still in flight keeps running and is recorded when it returns.
    public func dismissJoin() { joinAttempt += 1; joinOutcome = nil; changed() }

    private func applyJoinEvent(_ event: MlsJoinEvent) {
        guard pendingJoins[event.requestID] != nil || requestAttempts[event.requestID] != nil else {
            // An unknown request id changes no record; a group joined from another session still appears.
            Task { [weak self] in await self?.loadList() }
            return
        }
        pendingJoins[event.requestID] = nil
        let attempt = requestAttempts.removeValue(forKey: event.requestID)
        let showing: Bool = { if attempt == joinAttempt, case .pending(let request, _, _)? = joinOutcome { return request == event.requestID } else { return false } }()
        switch event.outcome {
        case .joined:
            if let group = event.groupID { Task { [weak self] in _ = await self?.refreshInfo(group) } }
            Task { [weak self] in await self?.loadList() }
            if showing, let group = event.groupID { joinOutcome = .joined(groupID: group) }
        case .refused(let refusal): if showing { joinOutcome = .refused(refusal, local: false) }
        }
    }

    // MARK: Create and invites
    /// One call per tap; nil while another create is in flight.
    public func create(name: String, approval: Bool) async -> Result<MlsCreated, MlsGroupError>? {
        guard admitted else { return .failure(.unavailable) }
        guard !creating else { return nil }
        let token = epoch
        creating = true
        let result = await repository.create(account: account, name: name, approval: approval)
        guard live(token) else { return .failure(.unavailable) }
        creating = false
        if case .success(let created) = result {
            var snapshot = invites[created.groupID] ?? MlsInviteSnapshot()
            snapshot.invites = [created.invite]; invites[created.groupID] = snapshot
            _ = await refreshInfo(created.groupID)
        }
        changed()
        return result
    }
    public func loadInvites(_ group: String) async {
        guard admitted else { return }
        let token = epoch
        var snapshot = invites[group] ?? MlsInviteSnapshot()
        snapshot.loading = true; snapshot.error = nil; invites[group] = snapshot; changed()
        let result = await repository.inviteList(account: account, groupID: group)
        guard live(token) else { return }
        var next = invites[group] ?? MlsInviteSnapshot()
        next.loading = false
        switch result {
        case .success(let rows):
            // `uses_left` is known only right after a create: keep it for an invite this session created.
            var known: [String: Int] = [:]
            for invite in next.invites { if let left = invite.usesLeft { known[invite.inviteID] = left } }
            next.invites = rows.map { row in MlsInvite(inviteID: row.inviteID, link: row.link, maxUses: row.maxUses, usesLeft: row.usesLeft ?? known[row.inviteID], expiresAt: row.expiresAt, revoked: row.revoked) }
        case .failure(let error): next.error = error
        }
        invites[group] = next; changed()
    }
    public func createInvite(_ group: String, maxUses: Int, ttlSeconds: Int) async {
        guard admitted, invites[group]?.creating != true else { return }
        let token = epoch
        var snapshot = invites[group] ?? MlsInviteSnapshot()
        snapshot.creating = true; snapshot.error = nil; invites[group] = snapshot; changed()
        let result = await repository.inviteCreate(account: account, groupID: group, maxUses: maxUses, ttlSeconds: ttlSeconds)
        guard live(token) else { return }
        var next = invites[group] ?? MlsInviteSnapshot()
        next.creating = false
        switch result {
        case .success(let invite): next.invites.insert(invite, at: 0)
        case .failure(let error): next.error = error
        }
        invites[group] = next; changed()
    }
    /// "Revoked" shows only after the reply (S6).
    public func revokeInvite(_ group: String, inviteID: String) async {
        guard admitted, invites[group]?.revoking.contains(inviteID) != true else { return }
        let token = epoch
        var snapshot = invites[group] ?? MlsInviteSnapshot()
        snapshot.revoking.insert(inviteID); snapshot.error = nil; invites[group] = snapshot; changed()
        let result = await repository.inviteRevoke(account: account, groupID: group, inviteID: inviteID)
        guard live(token) else { return }
        var next = invites[group] ?? MlsInviteSnapshot()
        next.revoking.remove(inviteID)
        switch result {
        case .success:
            next.invites = next.invites.map { $0.inviteID == inviteID ? MlsInvite(inviteID: $0.inviteID, link: $0.link, maxUses: $0.maxUses, usesLeft: $0.usesLeft, expiresAt: $0.expiresAt, revoked: true) : $0 }
        case .failure(let error): next.error = error
        }
        invites[group] = next; changed()
    }

    // MARK: Members (common 3.4)
    public func openMembers(_ group: String) async {
        guard admitted else { return }
        if members[group] == nil || members[group]?.phase == .idle { members[group] = MlsMembersSnapshot(); memberCursor[group] = nil; await loadMemberPage(group, first: true) }
    }
    /// The next page when the list is within 20 rows of the end. After a failed page nothing loads until `retryMembers`.
    public func loadMoreMembers(_ group: String) async {
        guard admitted, let snapshot = members[group], snapshot.hasMore, snapshot.phase == .done else { return }
        await loadMemberPage(group, first: false)
    }
    /// The user's "Try again": the only way a failed page is requested again.
    public func retryMembers(_ group: String) async {
        guard admitted, case .pageError? = members[group]?.phase else { return }
        await loadMemberPage(group, first: members[group]?.pagesLoaded == 0)
    }
    /// A search needs every page (at most 5 for the 1000 tier).
    public func loadAllMembers(_ group: String) async {
        guard admitted, members[group]?.loadingAll != true else { return }
        members[group]?.loadingAll = true; changed()
        var pages = 0
        while pages < 5, admitted, let snapshot = members[group], snapshot.hasMore, snapshot.phase == .done {
            await loadMemberPage(group, first: false); pages += 1
        }
        members[group]?.loadingAll = false; changed()
    }
    func loadMemberPage(_ group: String, first: Bool) async {
        let token = epoch
        var snapshot = members[group] ?? MlsMembersSnapshot()
        guard snapshot.phase != .loading else { return }
        snapshot.phase = .loading; members[group] = snapshot; changed()
        let result = await repository.members(account: account, groupID: group, cursor: first ? nil : memberCursor[group], limit: 200)
        guard live(token) else { return }
        var next = members[group] ?? MlsMembersSnapshot()
        switch result {
        case .success(let page):
            var rows = first ? [] : next.rows
            var index: [String: Int] = [:]
            for (at, row) in rows.enumerated() { index[row.anchor] = at }
            for row in page.rows {
                if row.aiFlag { aiAnchors[group, default: []].insert(row.anchor) }
                if row.isMe { myAnchor = row.anchor }
                if let at = index[row.anchor] { rows[at] = row } else { index[row.anchor] = rows.count; rows.append(row) }
            }
            next.rows = rows; next.hasMore = page.cursor != nil; next.pagesLoaded = first ? 1 : next.pagesLoaded + 1; next.phase = .done
            memberCursor[group] = page.cursor
        case .failure(let error): next.phase = .pageError(error)
        }
        members[group] = next
        adminMembersLoaded(group)
        changed()
    }

    // MARK: Timeline (common 3.3)
    /// Opens a group: its timeline is kept for the 3 most recently opened groups. The newest page loads once.
    public func open(_ group: String) async {
        guard admitted else { return }
        openGroup = group
        recent.removeAll { $0 == group }; recent.insert(group, at: 0)
        while recent.count > Self.recentGroups { let dropped = recent.removeLast(); evict(dropped); invites[dropped] = nil; members[dropped] = nil; if openGroup == dropped { openGroup = nil } }
        if timelines[group] == nil {
            var store = MlsTimelineStore(); store.groupID = group
            if let kept = evictedSend.removeValue(forKey: group) { store.pending = kept.pending; store.composerOffUntil = kept.composerOffUntil }
            timelines[group] = store
        }
        if let info = groups[group], info.unread > 0 { groups[group] = info.with(unread: 0, unreadMentions: 0) }
        changed()
        guard timelines[group]?.loaded != true else { return }
        await loadNewest(group)
        _ = await refreshInfo(group)
        await refresh(group)
    }
    /// Drops the window of a group but keeps its send records (rows read from history come back with the next load).
    private func evict(_ group: String) {
        if let store = timelines[group] {
            let kept = store.pending.filter { !$0.localID.hasPrefix("post:") }
            if !kept.isEmpty || store.composerOffUntil != nil { evictedSend[group] = EvictedSend(pending: kept, composerOffUntil: store.composerOffUntil) }
        }
        timelines[group] = nil
    }
    /// Runs a change on the send records of a group, whether its timeline is held or was evicted.
    private func mutateSend(_ group: String, _ body: (inout MlsTimelineStore) -> Void) {
        if var store = timelines[group] { body(&store); timelines[group] = store; return }
        var store = MlsTimelineStore(); store.groupID = group
        store.pending = evictedSend[group]?.pending ?? []; store.composerOffUntil = evictedSend[group]?.composerOffUntil
        body(&store)
        evictedSend[group] = store.pending.isEmpty && store.composerOffUntil == nil ? nil : EvictedSend(pending: store.pending, composerOffUntil: store.composerOffUntil)
    }
    private func sendRecord(_ group: String, _ localID: String) -> MlsPendingPost? {
        (timelines[group]?.pending ?? evictedSend[group]?.pending ?? []).first { $0.localID == localID }
    }
    public func close(_ group: String) { if openGroup == group { openGroup = nil } }

    /// The newest page; also "Jump to latest" after the window detached.
    public func loadNewest(_ group: String) async {
        guard admitted, timelines[group] != nil else { return }
        let token = epoch
        let result = await repository.history(account: account, groupID: group, afterLogSeq: nil, beforeLogSeq: nil, limit: 50)
        guard live(token), var store = timelines[group] else { return }
        switch result {
        case .success(let page):
            var fresh = MlsTimelineStore(); fresh.groupID = group
            fresh.readOnly = store.readOnly; fresh.composerOffUntil = store.composerOffUntil; fresh.deleting = store.deleting; fresh.tombstoned = store.tombstoned
            fresh.pending = store.pending.filter { !$0.localID.hasPrefix("post:") }
            for post in page.posts { absorb(post, group: group); fresh.insert(post) }
            fresh.floor = page.floorLogSeq; fresh.last = max(fresh.last, page.lastLogSeq); fresh.olderMore = page.more
            fresh.loaded = true; fresh.phase = .ready
            store = fresh
        case .failure(let error): store.phase = .failed(error)
        }
        timelines[group] = store; changed()
    }
    public func loadOlder(_ group: String) async {
        guard admitted, var store = timelines[group], store.olderMore, !store.loadingOlder, let oldest = store.oldest else { return }
        let token = epoch
        store.loadingOlder = true; timelines[group] = store; changed()
        let result = await repository.history(account: account, groupID: group, afterLogSeq: nil, beforeLogSeq: oldest, limit: 50)
        guard live(token), var next = timelines[group] else { return }
        next.loadingOlder = false
        switch result {
        case .success(let page):
            for post in page.posts { absorb(post, group: group); next.insert(post) }
            next.floor = page.floorLogSeq; next.olderMore = page.more
            next.trim(dropping: .newest)
        case .failure(let error): next.actionError = error
        }
        timelines[group] = next; changed()
    }

    /// One gap fill per group at a time; a gap found during a fill queues one more round. No automatic retry on failure.
    public func fillGap(_ group: String) async {
        guard admitted, var store = timelines[group], store.loaded, !store.detached, store.readOnly == nil else { return }
        if store.filling { store.fillQueued = true; timelines[group] = store; return }
        store.filling = true; timelines[group] = store
        let token = epoch
        var rounds = 0
        repeat {
            timelines[group]?.fillQueued = false
            var more = true
            while more, rounds < 50 {
                rounds += 1
                guard let last = timelines[group]?.last else { break }
                let result = await repository.history(account: account, groupID: group, afterLogSeq: last, beforeLogSeq: nil, limit: 200)
                guard live(token), var next = timelines[group] else { return }
                switch result {
                case .success(let page):
                    for post in page.posts { absorb(post, group: group); next.insert(post) }
                    next.last = max(next.last, page.lastLogSeq); next.trim(dropping: .oldest)
                    more = page.more && !page.posts.isEmpty
                case .failure: more = false
                }
                timelines[group] = next; changed()
            }
        } while timelines[group]?.fillQueued == true && rounds < 50
        timelines[group]?.filling = false; changed()
    }

    /// `group.refresh`, at most once every 5 s per group (extra calls inside the window are dropped). Not called in a read-only group.
    public func refresh(_ group: String) async {
        guard admitted, timelines[group]?.readOnly == nil else { return }
        if let last = lastRefresh[group], now().timeIntervalSince(last) < Self.refreshWindow { return }
        lastRefresh[group] = now()
        let token = epoch
        let result = await repository.refresh(account: account, groupID: group)
        guard live(token) else { return }
        if case .success(let rows) = result, let row = rows.first(where: { $0.groupID == group }), row.newPosts > 0, let last = timelines[group]?.last, row.lastLogSeq > last { await fillGap(group) }
    }
    /// Moves the read position forward to what the screen has shown (never backwards, never in a read-only group).
    public func markRead(_ group: String) async {
        guard admitted, let store = timelines[group], store.readOnly == nil, store.last > (markedRead[group] ?? 0), store.last > (groups[group]?.readLogSeq ?? 0) else { return }
        markedRead[group] = store.last
        let token = epoch
        let result = await repository.markRead(account: account, groupID: group, logSeq: store.last)
        guard live(token) else { return }
        if case .success(let state) = result, let info = groups[group] {
            groups[group] = info.with(unread: state.unread, unreadMentions: state.unreadMentions, readLogSeq: state.readLogSeq)
            changed()
        }
    }

    // MARK: Send owner (common 3.2)
    /// Submits one text post. The call runs here, so the outcome is recorded even if the chat closed. Returns the
    /// `local_id`, or nil when the group is read-only, the text is empty, or the session is not admitted.
    @discardableResult public func send(_ group: String, text: String, replyTo: String? = nil, mentions: [String] = []) async -> String? {
        guard admitted, var store = timelines[group], store.readOnly == nil, !composerLocked(store) else { return nil }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let localID = makeID()
        store.pending.append(MlsPendingPost(localID: localID, groupID: group, text: body, replyTo: replyTo, mentions: Array(mentions.prefix(50)), state: .submitting))
        timelines[group] = store; changed()
        await submit(localID, group: group)
        return localID
    }
    /// The daily limit is used up and its reset time has not come (checked against the clock, not a stored flag).
    private func composerLocked(_ store: MlsTimelineStore) -> Bool { store.composerOffUntil.map { $0 > nowMillis } ?? false }
    private func submit(_ localID: String, group: String) async {
        guard let pending = sendRecord(group, localID) else { return }
        let token = epoch
        let result = await repository.send(account: account, groupID: group, text: pending.text, replyTo: pending.replyTo, mentions: pending.mentions)
        guard live(token) else { return }
        mutateSend(group) { store in
            guard var index = store.pending.firstIndex(where: { $0.localID == localID }) else { return }
            switch result {
            case .failure(let error): store.pending[index].state = .notSent(.error(error))
            case .success(let receipt):
                store.pending[index].postID = receipt.postID
                // The SDK row of this post may have arrived while the call ran (r4 item 8): one bubble per `post_id`.
                store.pending.removeAll { $0.localID != localID && $0.postID == receipt.postID }
                index = store.pending.firstIndex(where: { $0.localID == localID }) ?? index
                if store.byPostID[receipt.postID] != nil { store.pending.remove(at: index) }   // an event posted it first
                else { apply(receipt.state, to: &store, at: index) }
            }
        }
        // The quota is a local count: read it again after the own send reply (coalesced, common 2.8).
        scheduleInfo(group)
        changed()
    }
    /// Moves a pending post to the state of a reply or a `post_state` event.
    private func apply(_ state: MlsSendState, to store: inout MlsTimelineStore, at index: Int) {
        let pending = store.pending[index]
        switch state {
        case .sent(let seq):
            store.pending.remove(at: index)
            guard seq > 0, store.posts[seq] == nil, let id = pending.postID else { return }
            let me = MlsAuthor(anchor: myAnchor ?? "", display: nil, aiFlag: false, isMe: true)
            store.insert(MlsPost(logSeq: seq, postID: id, author: me, appendedAt: nowMillis, kind: .text, body: .text(pending.text), replyTo: pending.replyTo, mentions: pending.mentions, state: .sent))
        case .queued(let reason): store.pending[index].state = .queued(reason)
        case .delayed(let after, _): store.pending[index].state = .delayed(sendAfter: after)
        case .rateLimited(let quota):
            store.pending[index].state = .notSent(.rateLimited(quota))
            if quota.remaining <= 0 { store.composerOffUntil = quota.resetsAt }
        case .failed(let reason): store.pending[index].state = .notSent(.failed(reason))
        case .unknown: store.pending[index].state = .queued(.unknown(""))
        }
    }
    /// Retry is an explicit tap only: a new `group.send` with the same text, reply and mentions, and a new `local_id`.
    @discardableResult public func retry(_ group: String, localID: String) async -> String? {
        guard admitted, var store = timelines[group], store.readOnly == nil, !composerLocked(store), let index = store.pending.firstIndex(where: { $0.localID == localID }), store.pending[index].canRetry else { return nil }
        let old = store.pending.remove(at: index)
        timelines[group] = store
        return await send(group, text: old.text, replyTo: old.replyTo, mentions: old.mentions)
    }
    /// Removes a not-sent bubble the user chose to drop.
    public func discard(_ group: String, localID: String) { timelines[group]?.pending.removeAll { $0.localID == localID && $0.canRetry }; changed() }

    // MARK: Delete and leave
    public func deletePost(_ group: String, postID: String) async {
        guard admitted, var store = timelines[group], store.readOnly == nil, !store.deleting.contains(postID), let seq = store.byPostID[postID], let post = store.posts[seq], post.state != .deleted, !store.tombstoned.contains(postID) else { return }
        store.deleting.insert(postID); store.actionError = nil; timelines[group] = store; changed()
        let token = epoch
        let result = await repository.deleteMessage(account: account, groupID: group, postID: postID)
        guard live(token), var next = timelines[group] else { return }
        switch result {
        case .success(.deleted): next.deleting.remove(postID); next.tombstoned.insert(postID)
        case .success: break   // queued or delayed: the row shows "Deleting…" until `post_deleted`
        case .failure(let error): next.deleting.remove(postID); next.actionError = error
        }
        timelines[group] = next; changed()
    }
    /// "You left" only on `committed` (S6). The group then drops off the list on the membership event or the next refresh.
    public func leave(_ group: String) async -> Result<MlsCommit, MlsGroupError> {
        guard admitted else { return .failure(.unavailable) }
        let token = epoch
        let result = await repository.leave(account: account, groupID: group)
        guard live(token) else { return .failure(.unavailable) }
        if case .success = result {
            if timelines[group] == nil { var store = MlsTimelineStore(); store.groupID = group; timelines[group] = store }
            timelines[group]?.readOnly = .left
            adminDropGroup(group)
            _ = await refreshInfo(group)
        }
        changed()
        return result
    }

    // MARK: Events
    func handle(_ event: MlsGroupEvent) async {
        guard admitted else { return }
        switch event {
        case .post(let group, let seq, let at, let post):
            applyPost(post, group: group, seq: seq, at: at)
            if post.kind == .void { adminVoidApplied(post, group: group) }
        case .membership(let group, let seq, let at, let post):
            applyPost(post, group: group, seq: seq, at: at)
            adminMembershipApplied(post, group: group)
            applyOwnMembership(post, group: group)
            scheduleInfo(group)
        case .settings(let group, let seq, let at, let post): applyPost(post, group: group, seq: seq, at: at); adminSettingsApplied(post, group: group); scheduleInfo(group)
        case .postState(let group, let postID, let state, let logSeq): applyPostState(group: group, postID: postID, state: state, logSeq: logSeq)
        case .postDeleted(let group, let postID, let postLogSeq, _):
            guard var store = timelines[group] else { break }
            var id = postID
            if store.byPostID[id] == nil, let seq = postLogSeq, let post = store.posts[seq] { id = post.postID }
            store.deleting.remove(id); store.tombstoned.insert(id)
            timelines[group] = store
        case .joinResult(let join): applyJoinEvent(join)
        case .read(let group, let readSeq, let unread, let mentions):
            if let info = groups[group] { groups[group] = info.with(unread: unread, unreadMentions: mentions, readLogSeq: readSeq) }
        case .pendingJoin(let group, _, let request): adminPendingJoin(group: group, request: request)
        case .catchUp(let group, let seq, let state): adminCatchUp(group: group, seq: seq, state: state)
        case .warning(let group, _, let warning): adminWarning(group: group, warning: warning)
        case .ignored: break
        }
        changed()
    }
    private func applyPost(_ post: MlsPost, group: String, seq: Int64?, at: Int64?) {
        absorb(post, group: group)
        // Deduplicated by `(group_id, log_seq)`, else by `seq`.
        if let logSeq = post.logSeq {
            if let existing = timelines[group]?.posts[logSeq], post.state != .deleted || existing.state == .deleted { return }
        } else if let seq, timelines[group]?.noteSeq(seq) == false { return }
        bump(group, post: post, at: at)
        guard var store = timelines[group], store.loaded, !store.detached else { return }
        let gap = post.logSeq.map { $0 > store.last + 1 } ?? false
        store.insert(post); store.trim(dropping: .oldest)
        timelines[group] = store
        if gap { Task { [weak self] in await self?.fillGap(group) } }
    }
    /// The list row's activity time and unread count follow the event (events win over list rows).
    private func bump(_ group: String, post: MlsPost, at: Int64?) {
        eventNewer.insert(group)
        guard let info = groups[group] else { return }
        let time = post.appendedAt ?? at ?? nowMillis
        let isText = post.kind == .text || post.kind == .attachment || post.kind == .card
        let incoming = isText && (post.author.map { !($0.isMe || (myAnchor != nil && $0.anchor == myAnchor)) } ?? false)
        groups[group] = info.with(lastLogSeq: max(info.lastLogSeq, post.logSeq ?? 0), lastActivityAt: max(info.lastActivityAt, time), unread: incoming && openGroup != group ? info.unread + 1 : info.unread)
    }
    /// A membership change of the own account: removed and banned make the group read-only; left drops it from the list.
    private func applyOwnMembership(_ post: MlsPost, group: String) {
        guard case .membership(let changes, _) = post.body else { return }
        for change in changes where change.isMe {
            switch change.change {
            case .removed: setReadOnly(group, .removed)
            case .banned: setReadOnly(group, .banned)
            case .left: setReadOnly(group, .left); groups[group] = nil
            default: break
            }
        }
    }
    func setReadOnly(_ group: String, _ reason: MlsReadOnly) {
        if timelines[group] == nil { var store = MlsTimelineStore(); store.groupID = group; timelines[group] = store }
        timelines[group]?.readOnly = reason
        adminDropGroup(group)
    }
    private func applyPostState(group: String, postID: String, state: MlsPostState, logSeq: Int64?) {
        let mapped: MlsSendState = switch state {
        case .sent: .sent(logSeq: logSeq ?? 0)
        case .queued(let reason): .queued(reason)
        case .delayed(let after): .delayed(sendAfter: after, delaySeconds: 0)
        case .failed(let reason): .failed(reason)
        case .rateLimited(let quota): .rateLimited(quota ?? MlsQuota(limit: 0, remaining: 0, firstDay: false))
        default: .unknown("")
        }
        mutateSend(group) { store in
            guard let index = store.pending.firstIndex(where: { $0.postID == postID }) else { return }
            apply(mapped, to: &store, at: index)
        }
    }
}
