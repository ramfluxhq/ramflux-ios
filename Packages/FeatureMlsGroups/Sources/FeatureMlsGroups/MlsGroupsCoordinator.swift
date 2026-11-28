// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
import FeatureChat

/// What the groups module presents over its list.
public enum MlsSheet: Identifiable, Equatable, Sendable {
    case create, join
    /// `fromCreate`: the panel opened right after a create; closing it shows the one-time host notice.
    case invite(group: String, fromCreate: Bool)
    case hostNotice(host: String)
    public var id: String {
        switch self {
        case .create: "create"
        case .join: "join"
        case .invite(let group, _): "invite:" + group
        case .hostNotice: "notice"
        }
    }
}
public enum MlsRoute: Hashable, Sendable { case chat(String), info(String), members(String) }

/// The MLS groups module for one account: the list, the join sheet and the navigation. All state of a call lives in the
/// `MlsGroupSession`; this reads its snapshots and sends intents (S4).
@Observable @MainActor public final class MlsGroupsCoordinator {
    public let session: MlsGroupSession
    public let account: String
    public private(set) var list = MlsListSnapshot()
    public private(set) var join = MlsJoinSnapshot()
    public var path: [MlsRoute] = []
    public var sheet: MlsSheet?
    /// The create sheet's own state: creating, and the typed error of the last attempt.
    public private(set) var creating = false
    public private(set) var createError: MlsGroupError?
    /// The group a joined outcome names, once `group.info` knows it.
    public private(set) var joinedName: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var chats: [String: MlsGroupChatModel] = [:]
    @ObservationIgnored private var details: [String: MlsGroupModel] = [:]

    public init(session: MlsGroupSession, account: String, defaults: UserDefaults = .standard) {
        self.session = session; self.account = account; self.defaults = defaults
    }

    public func start() {
        guard observer == nil else { return }
        observer = Task { [weak self] in
            guard let session = self?.session else { return }
            let changes = await session.changes()
            await session.start()
            await self?.reload()
            await session.loadList()
            for await _ in changes { await self?.reload() }
        }
    }
    public func stop() { observer?.cancel(); observer = nil }
    private func reload() async {
        list = await session.listSnapshot()
        join = await session.joinSnapshot()
        if case .joined(let id)? = join.outcome { joinedName = await session.group(id)?.name }
    }

    // MARK: List
    public func refresh() { Task { await session.loadList() } }
    public func loadMore() { Task { await session.loadMoreList() } }
    /// Pages in when the row is within 10 rows of the end.
    public func rowAppeared(_ id: String) {
        guard let index = list.rows.firstIndex(where: { $0.groupID == id }), index >= list.rows.count - 10, list.moreAvailable, !list.loadingMore else { return }
        loadMore()
    }

    // MARK: Join (one call per explicit tap)
    public func joinTapped(link: String) { Task { await session.join(link: link) } }
    public func closeJoin() { Task { await session.dismissJoin() }; sheet = nil }
    public func openJoined(_ group: String) { closeJoin(); open(group) }
    public func openJoinSheet() { sheet = .join }

    // MARK: Create
    public func create(name: String, approval: Bool) {
        guard !creating, case .ok(let clean) = MlsGroupsText.checkName(name) else { return }
        creating = true; createError = nil
        Task { [weak self] in
            guard let self else { return }
            let result = await session.create(name: clean, approval: approval)
            creating = false
            switch result {
            case .success(let created)?:
                sheet = nil
                open(created.groupID)
                // The invite panel opens over the new group; the host notice follows once, when it closes.
                try? await Task.sleep(for: .milliseconds(400))
                sheet = .invite(group: created.groupID, fromCreate: true)
            case .failure(let error)?: createError = error
            case nil: break
            }
        }
    }
    public func clearCreateError() { createError = nil }
    public func openCreateSheet() { createError = nil; sheet = .create }

    // MARK: Navigation and the one-time host notice
    public func open(_ group: String) { path.append(.chat(group)) }
    public func inviteClosed(group: String, fromCreate: Bool) {
        sheet = nil
        guard fromCreate else { return }
        Task { [weak self] in
            guard let self, let host = await session.group(group)?.visibleHost else { return }
            let key = Self.noticeKey(account: account, group: group)
            guard !defaults.bool(forKey: key) else { return }
            defaults.set(true, forKey: key)
            sheet = .hostNotice(host: host)
        }
    }
    /// The notice is remembered per account and group; the key holds neither the link nor any name.
    static func noticeKey(account: String, group: String) -> String { "mls.hostNotice." + account + "." + group }

    // MARK: Per-group models (kept while the module lives)
    public func chat(_ group: String) -> MlsGroupChatModel {
        if let model = chats[group] { return model }
        let model = MlsGroupChatModel(session: session, groupID: group, title: list.rows.first { $0.groupID == group }?.name ?? "") { [weak self] in self?.path.append(.info(group)) }
        chats[group] = model; return model
    }
    public func detail(_ group: String) -> MlsGroupModel {
        if let model = details[group] { return model }
        let model = MlsGroupModel(session: session, groupID: group)
        details[group] = model; return model
    }
    /// Lock or removal: the session is cleared by the owner; the models drop their snapshots too.
    public func reset() { chats = [:]; details = [:]; path = []; sheet = nil }
}
