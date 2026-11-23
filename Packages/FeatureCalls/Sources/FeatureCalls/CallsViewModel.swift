// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Observation
import AppData
@Observable @MainActor public final class CallsViewModel {
    public private(set) var state: CallsState
    private let repository: any CallsRepository
    private let microphone: any MicrophoneRepository
    private let account: String
    private let permissions: (any CallPermissionRequesting)?
    private let peerNames: (any CallPeerNames)?
    private let emit: (CallsEvent) -> Void
    @ObservationIgnored private var read: Task<Void, Never>?
    @ObservationIgnored private var more: Task<Void, Never>?
    @ObservationIgnored private var mutation: Task<Void, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var mediaWatch: Task<Void, Never>?
    @ObservationIgnored private var connecting: Task<Void, Never>?
    @ObservationIgnored private var epoch: UInt64 = 0
    @ObservationIgnored private var readID: UInt64 = 0
    @ObservationIgnored private var watchID: UInt64 = 0
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var connectedCalls: Set<String> = []
    public init(repository: any CallsRepository, microphone: any MicrophoneRepository, account: String, state: CallsState = CallsState(),
                permissions: (any CallPermissionRequesting)? = nil, peerNames: (any CallPeerNames)? = nil, emit: @escaping (CallsEvent) -> Void) {
        self.repository = repository; self.microphone = microphone; self.account = account; self.permissions = permissions; self.peerNames = peerNames
        var initial = state; initial.accountID = account; initial.media = repository.mediaAvailability(); self.state = initial; self.emit = emit
    }
    public func send(_ action: CallsAction) {
        switch action {
        case .appeared, .refresh: refresh(); observe()
        case .loadMore: loadMore()
        case .filter(let value): state.query = String(value.prefix(256)); project()
        case .mode(let mode):
            guard !state.busy else { return }
            if case .detail(let id) = mode, !state.calls.contains(where: { $0.id == id }) { return }
            state.mode = mode; state.failure = nil; state.permissionNeeded = nil; project(); refresh()
        case .start:
            guard !state.busy, state.pending == nil, case .dial(let conversation) = state.mode else { return }
            // While the engine refuses, a real invite would ring a peer this phone cannot hear.
            guard state.canCall else { state.failure = repository.audioUnavailable(); return }
            withMicrophone { [weak self, repository, account] in self?.perform { await repository.start(account: account, conversation: conversation) } }
        case .answer:
            guard state.canAnswer, let selected = state.selected else {
                if !state.canCall { state.failure = repository.audioUnavailable() }; return
            }
            let attempt = CallSignalAttempt(expected: selected, signal: .answer, operationID: UUID().uuidString)
            withMicrophone { [weak self, repository, account] in self?.perform { await repository.signal(account: account, attempt: attempt) } }
        case .control(let control):
            guard let capabilities = state.media.capabilities, let selected = state.selected, selected.phase == .active, Self.allowed(control, capabilities) else { return }
            if case .camera(true) = control, permissions != nil {
                permissions?.requestPermission(.camera) { [weak self] granted in
                    if granted { self?.apply(control, callID: selected.id) } else { self?.state.permissionNeeded = .camera }
                }
            } else { apply(control, callID: selected.id) }
        case .signal(let signal, let callID, let sequence):
            guard signal != .answer, state.pending == nil, !state.busy, let selected = state.selected, state.fresh, selected.id == callID, selected.sequence == sequence,
                  (signal == .decline ? selected.canDecline : selected.canHangup) else { return }
            let attempt = CallSignalAttempt(expected: selected, signal: signal, operationID: UUID().uuidString)
            perform { [repository, account] in await repository.signal(account: account, attempt: attempt) }
        case .reconcile(let operationID):
            guard !state.busy, let pending = state.pending, pending.operationID == operationID else { return }
            perform { [repository, account] in await repository.signal(account: account, attempt: pending) }
        case .openSettings: emit(.openSystemSettings)
        case .settingsResult(let opened): if !opened { state.failure = .localFailure }
        case .permissionResolved(let permission, let granted): if !granted { state.permissionNeeded = permission } else if state.permissionNeeded == permission { state.permissionNeeded = nil }
        case .dismissPermission: state.permissionNeeded = nil
        case .disappeared:
            epoch &+= 1; readID &+= 1; watchID &+= 1
            [read, more, mutation, observer, mediaWatch, connecting].forEach { $0?.cancel() }; observer = nil; mediaWatch = nil; pendingRefresh = false
            let mode = state.mode; state = CallsState(mode: mode); state.accountID = account; state.media = repository.mediaAvailability()
        }
    }
    static func allowed(_ control: CallMediaControl, _ capabilities: CallMediaCapabilities) -> Bool {
        switch control {
        case .mute: capabilities.audio
        case .route: capabilities.speakerRoute
        case .camera: capabilities.video
        case .switchCamera: capabilities.video && capabilities.cameraSwitch
        }
    }
    /// Runs `next` once the microphone is usable. Without the app hook the system status is
    /// read and a missing grant becomes the permission-needed state.
    private func withMicrophone(_ next: @escaping @MainActor () -> Void) {
        state.permissionNeeded = nil
        if let permissions {
            permissions.requestPermission(.microphone) { [weak self] granted in
                guard let self else { return }
                if granted { next() } else { self.state.permissionNeeded = .microphone }
            }
            return
        }
        Task { [weak self, microphone] in
            let status = await microphone.status()
            guard let self else { return }
            self.state.microphone = status
            if status == .granted { next() } else { self.state.permissionNeeded = .microphone }
        }
    }
    private func apply(_ control: CallMediaControl, callID: String) {
        Task { [weak self, repository] in
            let result = await repository.control(control, callID: callID)
            guard let self, self.state.selected?.id == callID else { return }
            switch result {
            case .success:
                switch control {
                case .mute(let value): self.state.muted = value
                case .route(let value): self.state.route = value
                case .camera(let value): self.state.camera = value
                case .switchCamera: break
                }
            case .failure(let failure): self.state.failure = failure
            }
        }
    }
    private func perform(_ operation: @escaping @Sendable () async -> RepositoryResult<CallRecord>) {
        guard !state.busy else { return }
        readID &+= 1; read?.cancel(); state.loading = false; state.busy = true; let current = epoch
        mutation = Task { [weak self, repository, account] in
            let result = await operation(); let pending = await repository.pending(account: account)
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.state.busy = false; self.state.pending = pending
            switch result { case .success(let row):
                self.state.failure = nil; self.state.mode = .detail(row.id); self.refresh()
            case .failure(let failure): self.state.failure = failure; self.state.fresh = false; if failure == .locked { self.state.calls = []; self.state.selected = nil }; if self.pendingRefresh { self.pendingRefresh = false; self.refresh() } }
        }
    }
    private func refresh() {
        guard !state.busy else { pendingRefresh = true; return }
        readID &+= 1; let id = readID; read?.cancel(); more?.cancel(); state.loading = true; state.fresh = false; state.accountID = account; state.media = repository.mediaAvailability()
        read = Task { [weak self, repository, microphone, account, peerNames] in
            let pending = await repository.pending(account: account)
            let result = await repository.history(account: account, cursor: nil), permission = await microphone.status()
            var names: [String: String] = [:]
            if case .success(let page) = result, let peerNames { names = await peerNames.names(account: account, peers: Array(Set(page.rows.map(\.peerID)))) }
            guard !Task.isCancelled, let self, self.readID == id else { return }
            self.state.pending = pending; self.state.microphone = permission; self.state.loading = false
            switch result { case .success(let page): self.state.calls = Array(page.rows.prefix(CallsState.window)); self.state.nextCursor = page.nextCursor; self.state.names = names; self.state.fresh = true; self.state.failure = nil
            case .failure(let failure): self.state.failure = failure; if failure == .locked { self.state.calls = [] } }
            self.project(); self.followMedia()
            if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
        }
    }
    private func loadMore() {
        guard let cursor = state.nextCursor, more == nil || more?.isCancelled == true, !state.loading else { return }
        let id = readID
        more = Task { [weak self, repository, account] in
            let result = await repository.history(account: account, cursor: cursor)
            guard !Task.isCancelled, let self, self.readID == id else { return }
            self.more = nil
            switch result {
            case .success(let page):
                let known = Set(self.state.calls.map(\.id))
                self.state.calls.append(contentsOf: page.rows.filter { !known.contains($0.id) })
                // A bounded window: the oldest rows leave memory first.
                if self.state.calls.count > CallsState.window { self.state.calls.removeLast(self.state.calls.count - CallsState.window) }
                self.state.nextCursor = self.state.calls.count >= CallsState.window ? nil : page.nextCursor
                self.project()
            case .failure(let failure): self.state.failure = failure
            }
        }
    }
    private func project() {
        state.visibleCalls = state.query.isEmpty ? state.calls : state.calls.filter { row in
            row.peerID.localizedCaseInsensitiveContains(state.query) || state.names[row.peerID]?.localizedCaseInsensitiveContains(state.query) == true
        }
        if case .detail(let id) = state.mode { state.selected = state.calls.first { $0.id == id } } else { state.selected = nil }
    }
    /// Hands an active call's media to the engine once, and stops it when the call ends.
    private func followMedia() {
        guard let row = state.selected, state.canCall else { return }
        if row.phase == .ended, connectedCalls.remove(row.id) != nil {
            let id = row.id; Task { [repository] in await repository.stopMedia(callID: id) }; state.mediaState = .stopped; return
        }
        guard row.phase == .active, !connectedCalls.contains(row.id) else { return }
        connectedCalls.insert(row.id); watchMedia(); let current = epoch
        connecting = Task { [weak self, repository, account] in
            let result = await repository.connectMedia(account: account, call: row)
            guard !Task.isCancelled, let self, self.epoch == current, case .failure(let failure) = result else { return }
            self.state.mediaState = .failed(.invalidMaterial); self.state.failure = failure
        }
    }
    private func watchMedia() {
        guard mediaWatch == nil else { return }
        mediaWatch = Task { [weak self, repository] in
            for await event in repository.mediaEvents() {
                guard !Task.isCancelled, let self else { break }
                guard let id = self.state.selected?.id else { continue }
                switch event {
                case .state(let call, let value) where call == id: self.state.mediaState = value
                case .remoteVideo(let call, let active) where call == id: self.state.remoteVideo = active
                default: break
                }
            }
        }
    }
    private func observe() {
        guard observer == nil else { return }; watchID &+= 1; let id = watchID
        observer = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self else { break }
                self.state.fresh = false
                switch update { case .invalidated: if self.state.loading || self.state.busy { self.pendingRefresh = true } else { self.refresh() }; case .failed(let failure): self.state.failure = failure }
            }
            await observation.stop(); if let self, self.watchID == id { self.observer = nil; self.state.fresh = false }
        }
    }
    /// Attaches a video view for the engine (not an action: views are not values).
    public func attachVideo(_ surface: (any CallVideoSurface)?, slot: CallVideoSlot, callID: String) { repository.attachVideo(surface, slot: slot, callID: callID) }
    public func settle() async { await mutation?.value; while true { let id = readID; await read?.value; await more?.value; await connecting?.value; if id == readID { return } } }
    deinit { [read, more, mutation, observer, mediaWatch, connecting].forEach { $0?.cancel() } }
}
