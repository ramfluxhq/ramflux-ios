// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData

/// A centred line of the timeline made on this device from the identity change stream and the security read.
/// It is never a message row.
public struct ServiceLine: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case identityChanged, identityAccepted, forkRecovered
        /// An MLS group timeline line (M2).
        case mls(MlsServiceLine)
        /// "Earlier messages are not available on this device".
        case mlsFloor }
    public let id: String
    public let kind: Kind
    public let name: String
    public init(id: String, kind: Kind, name: String) { self.id = id; self.kind = kind; self.name = name }
}

/// What a screen shows about one direct contact's identity: the banner, the review sheet, the encryption section
/// and the service lines.
public struct IdentityPanel: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle, accepting
        /// `no_pending_change`: the sheet shows that the change was handled and closes by itself.
        case alreadyHandled
        /// `anchor_mismatch`: the sheet shows the latest change and waits for a new tap.
        case changedAgain
        case failed
    }
    /// The contact's name as the screen knows it; the sheet isolates it from the surrounding text.
    public var name = ""
    /// Nil until the SDK answered (or when it cannot answer): nothing is claimed then.
    public var state: IdentityState?
    /// The change the sheet displays; `Accept` names exactly its `newAnchor`.
    public var change: IdentityChange?
    public var phase: Phase = .idle
    public var sheetOpen = false
    public var security: ConversationSecurity?
    public var serviceLines: [ServiceLine] = []
    public init() {}
    public var isChanged: Bool { state == .changed }
    /// `changed` while the new anchor is not known: Review is disabled and the sheet waits.
    public var isWaiting: Bool { isChanged && change == nil }
    public var presentedName: String { name.isEmpty ? (change?.username.map { "@" + $0 } ?? "") : name }
    /// The review sheet is on screen only while the identity is still changed or the "already handled" line shows.
    public var showsSheet: Bool { sheetOpen && (isChanged || phase == .alreadyHandled) }
}

/// Reads one contact's identity and runs the review of a changed one. The only place that calls
/// `ContactIdentityRepository.accept`: the Accept tap of the review sheet. There is no timer, no accept on open, no
/// accept together with a send, no batch accept, and no retry; a send blocked by a pending change is never repeated.
@MainActor public final class IdentityReview {
    public private(set) var panel: IdentityPanel { didSet { if panel != oldValue { publish(panel) } } }
    private let repository: any ContactIdentityRepository
    private let account: String
    private let contact: String
    private let conversation: String?
    private let publish: (IdentityPanel) -> Void
    private var epoch: UInt64 = 0
    private var started = false
    private var reading = false
    private var rereadPending = false
    private var watch: Task<Void, Never>?
    private var changes: Task<Void, Never>?
    private var read: Task<Void, Never>?
    private var acceptance: Task<Void, Never>?
    private var closing: Task<Void, Never>?
    /// How long "already handled" stays before the sheet closes.
    private static let closeDelay: Duration = .milliseconds(1500)
    public init(repository: any ContactIdentityRepository, account: String, contact: String, name: String, conversation: String? = nil, publish: @escaping (IdentityPanel) -> Void) {
        self.repository = repository; self.account = account; self.contact = contact; self.conversation = conversation; self.publish = publish
        var initial = IdentityPanel(); initial.name = name; panel = initial
    }
    public func start() {
        guard !started else { return }
        started = true; epoch &+= 1; let current = epoch
        watch = Task { [weak self, repository, account] in
            let observation = await repository.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self, self.epoch == current else { break }
                if case .invalidated = update { self.reread() }
            }
            await observation.stop()
        }
        changes = Task { [weak self, repository, account] in
            for await change in repository.changes(account: account) {
                guard !Task.isCancelled, let self, self.epoch == current else { break }
                self.received(change)
            }
        }
        reread()
    }
    public func stop() {
        epoch &+= 1; started = false; reading = false; rereadPending = false
        for task in [watch, changes, read, acceptance, closing] { task?.cancel() }
        watch = nil; changes = nil; read = nil; acceptance = nil; closing = nil
    }
    /// Opens the sheet for the change the SDK named. Disabled while the new anchor is unknown.
    public func review() {
        guard panel.isChanged, panel.change != nil, panel.phase != .accepting else { return }
        closing?.cancel(); panel.phase = .idle; panel.sheetOpen = true
    }
    /// "Not now": the sheet closes and the identity stays changed.
    public func later() {
        guard panel.phase != .accepting else { return }
        closing?.cancel(); panel.phase = .idle; panel.sheetOpen = false
    }
    /// The explicit "Accept new identity" tap. It names the anchor of the change the sheet displays now.
    /// `anchor` is the new anchor the sheet rendered when it was tapped; when the panel holds a different change by now,
    /// nothing is sent and the sheet shows "changed again" and waits for a new tap.
    public func accept(anchor: String) {
        guard panel.sheetOpen, panel.phase != .accepting, panel.phase != .alreadyHandled, let displayed = panel.change else { return }
        guard displayed.newAnchor == anchor else { panel.phase = .changedAgain; return }
        panel.phase = .accepting
        let current = epoch
        acceptance = Task { [weak self, repository, account] in
            let outcome = await repository.accept(account: account, contact: displayed.contact, newAnchor: displayed.newAnchor)
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.finish(outcome, displayed: displayed)
        }
    }
    public func settle() async {
        await acceptance?.value
        while true { let current = epoch; await read?.value; if current == epoch, !reading { return } }
    }
    private func finish(_ outcome: AcceptOutcome, displayed: IdentityChange) {
        switch outcome {
        case .accepted:
            // The status is read again for the real state; until then nothing is claimed.
            // A newer change that arrived while the request ran stays visible, with the sheet showing "changed again".
            if panel.change?.newAnchor == displayed.newAnchor {
                panel.change = nil; panel.state = nil; panel.phase = .idle; panel.sheetOpen = false
            } else if panel.change != nil {
                panel.phase = .changedAgain
            } else {
                panel.state = nil; panel.phase = .idle; panel.sheetOpen = false
            }
            append(ServiceLine(id: "accepted:" + displayed.newAnchor, kind: .identityAccepted, name: panel.presentedName))
            reread()
        case .alreadyHandled:
            // A newer change that arrived while the request ran must be reviewed, not reported as handled.
            if let change = panel.change, change.newAnchor != displayed.newAnchor {
                panel.phase = .changedAgain
                reread()
                return
            }
            panel.phase = .alreadyHandled
            reread()
            let current = epoch
            closing = Task { [weak self] in
                try? await Task.sleep(for: Self.closeDelay)
                guard !Task.isCancelled, let self, self.epoch == current, self.panel.phase == .alreadyHandled else { return }
                self.panel.sheetOpen = false; self.panel.phase = .idle
            }
        case .changedAgain:
            panel.phase = .changedAgain
            reread()
        case .failed:
            // A newer change that arrived while the request ran is shown as "changed again", so a retry tap is a new decision.
            if let change = panel.change, change.newAnchor != displayed.newAnchor { panel.phase = .changedAgain } else { panel.phase = .failed }
        }
    }
    private func received(_ change: IdentityChange) {
        guard change.contact == contact else { return }
        if panel.change?.newAnchor != change.newAnchor {
            var next = panel
            next.state = .changed; next.change = change
            if panel.sheetOpen, panel.phase != .accepting { next.phase = .changedAgain }
            else if panel.phase == .alreadyHandled { next.phase = .idle }
            panel = next
            append(ServiceLine(id: "changed:" + change.newAnchor, kind: .identityChanged, name: panel.presentedName))
        }
    }
    private func reread() {
        guard started else { return }
        guard !reading else { rereadPending = true; return }
        reading = true; let current = epoch
        read = Task { [weak self, repository, account, contact, conversation] in
            let identity = await repository.identity(account: account, contact: contact)
            var security: RepositoryResult<ConversationSecurity>?
            if let conversation { security = await repository.security(account: account, conversation: conversation) }
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.reading = false
            self.apply(identity: identity, security: security)
            if self.rereadPending { self.rereadPending = false; self.reread() }
        }
    }
    private func apply(identity: RepositoryResult<IdentityRead>, security: RepositoryResult<ConversationSecurity>?) {
        var next = panel
        if case .success(let value) = identity {
            next.state = value.state
            if value.state == .changed {
                // A status read that names no anchor keeps the one the event gave.
                if let change = value.change {
                    // The sheet shows another change than the one on screen: the user must tap again.
                    if next.sheetOpen, next.phase != .accepting, let shown = next.change, shown.newAnchor != change.newAnchor { next.phase = .changedAgain }
                    next.change = change
                }
            } else {
                next.change = nil
                if next.phase != .alreadyHandled { next.phase = .idle; next.sheetOpen = false }
            }
        }
        if case .success(let value)? = security {
            next.security = value
            if value.warning == .forkRecovered, !next.serviceLines.contains(where: { $0.id == "fork:\(value.epoch)" }) {
                next.serviceLines.append(ServiceLine(id: "fork:\(value.epoch)", kind: .forkRecovered, name: next.presentedName))
            }
        }
        panel = next
    }
    private func append(_ line: ServiceLine) {
        guard !panel.serviceLines.contains(where: { $0.id == line.id }) else { return }
        panel.serviceLines.append(line)
    }
    deinit { for task in [watch, changes, read, acceptance, closing] { task?.cancel() } }
}
