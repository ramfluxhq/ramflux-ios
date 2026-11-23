// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class AgentsViewModel {
    public private(set) var state: AgentsState
    private let repository: any AgentsRepository
    private let account: String
    private let emit: (AgentsEvent) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var window = RowWindow<AgentRecord>()
    @ObservationIgnored private var journal = ""
    public init(repository: any AgentsRepository, account: String, state: AgentsState = AgentsState(), emit: @escaping (AgentsEvent) -> Void) { self.repository = repository; self.account = account; self.state = state; self.emit = emit }
    public func send(_ action: AgentsAction) {
        switch action {
        case .appeared: load(); observe()
        case .retry: load()
        case .loadMore: loadMore()
        case .query(let value): state.query = String(value.prefix(256)); project()
        case .mode(let mode):
            guard !state.busy else { return }
            state.mode = mode; state.failure = nil; state.confirmingDelete = false; state.confirmingEdit = false
            switch mode {
            case .directory: project()
            case .profile(let id), .edit(let id):
                state.selected = window.rows.first { $0.id == id } ?? (state.selected?.id == id ? state.selected : nil)
                if case .edit = mode, let selected = state.selected { state.draft = selected.persona }
                loadRecord(id)
            }
        case .chat(let id):
            guard !state.busy else { return }
            generation &+= 1; let current = generation; task?.cancel(); state.loading = true; state.failure = nil
            task = Task { [weak self, repository, account] in
                let result = await repository.chatConversation(account: account, agent: id)
                guard !Task.isCancelled, let self, self.generation == current else { return }
                self.state.loading = false
                switch result { case .success(let conversation): self.emit(.navigate(.conversation(conversation))); case .failure(let failure): self.state.failure = failure }
            }
        case .draftName(let value): state.draft.name = String(value.unicodeScalars.prefix(256))
        case .draftResponsibility(let value): state.draft.responsibility = String(value.unicodeScalars.prefix(1024))
        case .save:
            guard case .edit = state.mode, state.selected != nil, !state.busy else { return }
            guard !state.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { state.failure = .invalidInput; return }
            state.confirmingEdit = true
        case .delete: guard case .profile = state.mode, state.selected != nil, !state.busy else { return }; state.confirmingDelete = true
        case .cancelConfirmation: if !state.busy { state.confirmingDelete = false; state.confirmingEdit = false }
        case .confirmSave:
            guard state.confirmingEdit, let agent = state.selected else { return }
            let persona = state.draft
            mutate { [repository, account] in await repository.editPersona(account: account, agent: agent.id, persona: persona) } done: { [weak self] record in
                self?.window = self?.window.patching(record) ?? RowWindow(); self?.state.selected = record; self?.state.mode = .profile(record.id); self?.project()
            }
        case .confirmDelete:
            guard state.confirmingDelete, let agent = state.selected else { return }
            mutate { [repository, account] in await repository.delete(account: account, agent: agent.id) } done: { [weak self] record in
                guard let self else { return }
                self.window = self.window.removing(record.id); self.state.selected = nil; self.state.mode = .directory; self.project()
            }
        case .unavailable(let capability): state.failure = repository.unavailable(capability)
        case .disappeared:
            generation &+= 1; task?.cancel(); observer?.cancel(); observer = nil
            window = RowWindow(); journal = ""; state = AgentsState(mode: state.mode)
        }
    }
    private func mutate(_ operation: @escaping @Sendable () async -> RepositoryResult<AgentRecord>, done: @escaping @MainActor (AgentRecord) -> Void) {
        generation &+= 1; let id = generation; state.busy = true; state.failure = nil; task?.cancel()
        task = Task { [weak self] in
            let result = await operation()
            guard !Task.isCancelled, let self, self.generation == id else { return }
            self.state.busy = false; self.state.confirmingDelete = false; self.state.confirmingEdit = false
            switch result { case .success(let record): done(record); case .failure(let failure): self.state.failure = failure }
        }
    }
    private func load() {
        generation &+= 1; let id = generation; task?.cancel(); state.loading = true
        task = Task { [weak self, repository, account] in
            let journal = JournalBox("")
            let first = await RowWindow.first({ cursor, limit in
                let result = await repository.page(account: account, cursor: cursor, limit: limit)
                return result.map { page in journal.set(page.journalCursor); return page.page }
            })
            let creation = await repository.pendingCreation(account: account)
            guard !Task.isCancelled, let self, self.generation == id else { return }
            self.state.loading = false
            switch first {
            case .success(let window): self.window = window; self.journal = journal.value; self.state.failure = nil
            case .failure(let failure): self.state.failure = failure; if failure == .locked { self.window = RowWindow() }
            }
            // No pending creation, or none readable: the section stays hidden rather than guessing.
            if case .success(let request) = creation { self.state.creation = request } else { self.state.creation = nil }
            self.project()
        }
    }
    private func loadMore() {
        guard window.canLoadAfter, !state.loading, !state.loadingMore, !state.busy else { return }
        generation &+= 1; let id = generation; state.loadingMore = true; let current = window
        task = Task { [weak self, repository, account] in
            let next = await current.after { cursor, limit in await repository.page(account: account, cursor: cursor, limit: limit).map(\.page) }
            guard !Task.isCancelled, let self, self.generation == id else { return }
            self.state.loadingMore = false
            switch next { case .success(let window): self.window = window; case .failure(let failure): self.state.failure = failure }
            self.project()
        }
    }
    private func loadRecord(_ agent: String) {
        generation &+= 1; let id = generation; task?.cancel(); state.loading = true
        task = Task { [weak self, repository, account] in
            let result = await repository.record(account: account, agent: agent)
            guard !Task.isCancelled, let self, self.generation == id else { return }
            self.state.loading = false
            switch result {
            case .success(let record):
                self.state.selected = record; self.window = self.window.patching(record)
                if case .edit = self.state.mode, self.state.draft.name.isEmpty { self.state.draft = record.persona }
            case .failure(let failure): self.state.failure = failure; self.state.selected = nil
            }
        }
    }
    /// Account invalidations carry no agent topic; `agent.watch` returns what changed since the journal
    /// cursor and only those rows are patched.
    private func observe() {
        guard observer == nil else { return }
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }
                guard case .invalidated = update, !self.journal.isEmpty, !self.state.loading, !self.state.busy else { continue }
                if case .success(let changes) = await repository.changes(account: account, since: self.journal) {
                    for record in changes.page.rows { self.window = record.lifecycle == "retired" ? self.window.removing(record.id) : self.window.patching(record) }
                    if !changes.journalCursor.isEmpty { self.journal = changes.journalCursor }
                    self.project()
                }
            }
            await observation.stop()
        }
    }
    /// Projects the held window (at most a few hundred rows) into directory rows. `agent.list` has no
    /// query parameter, so the search filters the held window only.
    private func project() {
        let needle = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.entries = window.rows.filter { needle.isEmpty || $0.persona.name.localizedStandardContains(needle) }.map { record in
            AgentEntry(id: record.id, name: record.persona.name.isEmpty ? record.id : record.persona.name, detail: record.persona.responsibility, icon: KitAgentIcon.name(record.persona.avatar))
        }
        state.canLoadMore = window.canLoadAfter
    }
    public func settle() async { while true { let current = generation; await task?.value; if current == generation { return } } }
    deinit { task?.cancel(); observer?.cancel() }
}

/// A locked box for the journal cursor written inside a page reader.
private final class JournalBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String
    init(_ value: String) { stored = value }
    func set(_ value: String) { lock.lock(); stored = value; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return stored }
}

/// The persona avatar is an icon name when it names a Kit icon; anything else (a URL, an emoji) shows the default glyph.
enum KitAgentIcon {
    static func name(_ avatar: String) -> String { ["orbit", "gem", "user-round", "bot", "sparkles"].contains(avatar) ? avatar : "orbit" }
}
