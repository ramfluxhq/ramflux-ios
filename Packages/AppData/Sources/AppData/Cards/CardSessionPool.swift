// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
import Synchronization

/// What the timeline draws for one card: the last known tree (read-only while the session is suspended), whether the
/// runtime allows content, the fallback text, and where the session stands.
public struct CardDisplay: Equatable, Sendable {
    public let surfaceRef: String
    public let tree: CardTree?
    public let renderAllowed: Bool
    public let fallbackText: String
    /// The session holds a resident VM and takes events. False: draw `tree` read-only; the first tap resumes it.
    public let resident: Bool
    public let phase: CardPhase
    /// A draft was visible when the session was dropped (lock, expiry): the host shows the spec 4.20 notice once.
    public let draftDiscarded: Bool
    /// The last event or answer came back `stale_dropped`: its batch reverted the field and the host shows the spec 5.3 line.
    public let contentChanged: Bool

    /// The runtime lifecycle of the held tree (spec 3.4); `open` when there is no tree.
    public var lifecycle: CardLifecycle { tree?.lifecycle ?? .open }
    /// The author still has an open text stream on the card: controls stay disabled and a progress chip shows.
    public var generating: Bool { tree?.generating ?? false }
    /// The card that replaced this one, when the runtime verified it.
    public var replacementRef: String? { tree?.replacementRef }
}

/// Lifecycle states of a card session (`docs/CARD-RENDER-SPEC-01.md` 3.4) as the runtime reports them.
public enum CardPhase: Equatable, Sendable {
    /// Interactive.
    case live
    /// Read-only last tree; the first tap resumes it.
    case suspended
    /// A submit is in flight.
    case submitting
    /// Submitted; controls stay consumed until the signed update.
    case consumed
    /// Replaced by a verified newer card.
    case superseded(replacement: String?)
    /// The runtime refused the last call with this name (`card_session_refused`, `card_session_stale`, ...).
    case refused(String)
    /// No session: the fallback text is all that can be drawn.
    case unavailable
}

/// The result of one host action: the display after it, the host request to answer, and the submit handle when the
/// action was a submit.
public struct CardStep: Equatable, Sendable {
    public let display: CardDisplay
    public let hostRequest: CardHostRequest?
    public let draftConflict: Bool
    public let submit: CardSubmitHandle?
    /// The runtime's result name for a host slot answer (`opened`, `cancelled`, `unavailable`, `approval_decision`).
    public var slotResult: String? = nil
}

/// Card sessions of one account. The runtime keeps at most two resident VMs per process and 32 sessions per account.
/// The resident budget is the process's, shared with the pools of the other accounts (`CardResidency`); this pool keeps
/// at most 24 sessions open, suspends the least recently used resumed card of any account to make room, and disposes the
/// sessions whose cards left the loaded window. `card_limit_exceeded` (open, resume) suspends the least recently used
/// resumed card and retries once; `card_session_limit` disposes this account's least recently used card and retries
/// once. A dropped session (`card_session_expired`, `card_session_inactive`, lock, sign-out) is forgotten and its last
/// tree stays drawn read-only; the next tap opens the card again.
///
/// The operations of one card run in the order they were made, one at a time (see `ordered`); a card never waits for
/// another card's operation. Every operation answers its caller, success or failure, so a card never stays busy.
public actor CardSessionPool {
    public static let maximumResident = 2
    public static let maximumOpen = 24

    private struct Entry {
        var session: UInt64?
        var tree: CardTree?
        var renderAllowed: Bool
        var fallbackText: String
        var resident: Bool
        var touched: UInt64
        var phase: CardPhase
        /// Resident before `suspendAll`, so `resumeAll` brings back exactly those sessions.
        var residentAtBackground: Bool
        /// An input was accepted and not yet submitted: a dropped session loses it.
        var hasDraft = false
        var draftDiscarded = false
        var contentChanged = false
    }

    /// One operation of a card's queue.
    private enum Operation: Sendable {
        case open(locale: String, dark: Bool)
        case resume
        case event(key: String, event: CardHostEvent)
        case answer(token: CardEventToken, slotID: String, requestID: String, outcome: CardSlotOutcome)
        case submit
        case refresh(version: UInt64, locale: String, dark: Bool)
        case present(locale: String, dark: Bool)
        /// Background or app lock: a resident session is suspended and remembered for `resumeAll`.
        case suspendForBackground
        case dispose

        var isDisposal: Bool { if case .dispose = self { true } else { false } }
    }

    /// A queued operation and every caller waiting for its answer. An `input` for the same control at the tail of the
    /// queue is merged into it: the newest value wins, and every merged caller receives the one answer.
    private struct Queued {
        var operation: Operation
        var waiters: [CheckedContinuation<CardStep, any Error>]
    }

    private let client: CardSessionClient
    private let account: String
    private let residency: CardResidency
    private var entries: [String: Entry] = [:]
    private var queues: [String: [Queued]] = [:]
    /// Cards with a consumer running (at most one per card).
    private var draining: Set<String> = []
    /// Set by `disposeAll`: no new operation is accepted, only the disposals already queued run.
    private var closed = false
    /// Set by `suspendAll` before its suspends are queued, cleared by `resumeAll`. While set, no session becomes resident:
    /// an open or a tap parks the card instead.
    private var suspended: Bool
    /// The host's colour scheme and locale as the pool last received them; a resumed session is presented in them.
    private var appearance: (locale: String, dark: Bool)?

    init(client: CardSessionClient, account: String, residency: CardResidency, suspended: Bool = false) {
        self.client = client; self.account = account; self.residency = residency; self.suspended = suspended
    }

    public func display(surfaceRef: String) -> CardDisplay? { entries[surfaceRef].map { display(surfaceRef, $0) } }

    /// Opens the card unless it is already open. Opening takes a resident slot; older cards are suspended to make room.
    public func open(surfaceRef: String, locale: String, dark: Bool) async throws -> CardDisplay {
        appearance = (locale, dark)
        return try await ordered(surfaceRef, .open(locale: locale, dark: dark)).display
    }

    /// The first tap on a suspended card: resumes it with a fresh token session and the full tree.
    public func resume(surfaceRef: String) async throws -> CardDisplay {
        try await ordered(surfaceRef, .resume).display
    }

    /// Sends one host event to a node of the held tree. A suspended card is resumed instead: the tap only resumes it.
    public func event(surfaceRef: String, key: String, event: CardHostEvent) async throws -> CardStep {
        try await ordered(surfaceRef, .event(key: key, event: event))
    }

    /// Answers a host slot (a confirmed link, a decision, a cancel) with the token and request id it was issued with.
    public func answer(surfaceRef: String, token: CardEventToken, slotID: String, requestID: String, outcome: CardSlotOutcome) async throws -> CardStep {
        try await ordered(surfaceRef, .answer(token: token, slotID: slotID, requestID: requestID, outcome: outcome))
    }

    /// Submits the pending action. Never retried automatically: a refusal is shown, not resent.
    public func submit(surfaceRef: String) async throws -> CardStep {
        try await ordered(surfaceRef, .submit)
    }

    /// Brings the session up to the surface version the list shows: an update when it moved, a fresh open when the card
    /// had no session before.
    public func refresh(surfaceRef: String, version: UInt64, locale: String, dark: Bool) async throws -> CardDisplay {
        appearance = (locale, dark)
        return try await ordered(surfaceRef, .refresh(version: version, locale: locale, dark: dark)).display
    }

    /// Re-presents the held session in a new locale or theme; no peer update.
    public func present(surfaceRef: String, locale: String, dark: Bool) async throws -> CardDisplay {
        appearance = (locale, dark)
        return try await ordered(surfaceRef, .present(locale: locale, dark: dark)).display
    }

    /// Keeps the sessions of the cards in the loaded window; disposes the others and any beyond the open limit. Each
    /// disposal runs in the card's queue, so an operation already in flight finishes first.
    public func retain(surfaceRefs: Set<String>) async {
        for ref in knownRefs() where !surfaceRefs.contains(ref) { await serialized(ref, .dispose) }
        let excess = entries.count - Self.maximumOpen
        guard excess > 0 else { return }
        let victims = entries.sorted { $0.value.touched < $1.value.touched }.prefix(excess).map(\.key)
        for ref in victims { await serialized(ref, .dispose) }
    }

    public func dispose(surfaceRef: String) async { await serialized(surfaceRef, .dispose) }

    /// The account locked, signed out or was removed: the SDK dropped every session itself and later calls would only fail.
    /// Every handle is forgotten here with no bus call; the trees stay for drawing. `close` accepts no further operation.
    public func forgetAll(close: Bool) {
        if close { closed = true }
        for ref in Array(entries.keys) { forget(ref) }
    }

    /// The resumed cards of this pool with their last touch, least recent first, for the process-wide budget.
    func residentTouches() -> [(ref: String, touched: UInt64)] {
        entries.filter { $0.value.resident }.map { ($0.key, $0.value.touched) }.sorted { $0.touched < $1.touched }
    }

    /// The least recently used resumed card that is not busy with an operation; `ref` is never offered.
    func leastRecentResident(excluding ref: String?) -> (ref: String, touched: UInt64)? {
        entries.filter { $0.key != ref && $0.value.resident && !draining.contains($0.key) }
            .min { $0.value.touched < $1.value.touched }.map { ($0.key, $0.value.touched) }
    }

    /// Suspends one resumed card to free a slot of the process budget. A card that began an operation meanwhile stays.
    func suspendResident(_ ref: String) async -> Bool {
        guard entries[ref]?.resident == true, !draining.contains(ref) else { return false }
        await suspend(ref)
        return true
    }

    /// The app goes to the background or the account is locked: the pool is marked suspended at once, then every resident
    /// session is suspended behind the card's queue, so an open in flight is suspended too; the trees stay.
    public func suspendAll() async {
        suspended = true
        for ref in knownRefs() { await serialized(ref, .suspendForBackground) }
    }

    /// The app returns to the foreground: the pool is no longer suspended and the sessions that were resident at the
    /// background come back, with fresh tokens.
    public func resumeAll() async {
        suspended = false
        for ref in entries.keys where entries[ref]?.residentAtBackground == true {
            entries[ref]?.residentAtBackground = false
            _ = try? await resume(surfaceRef: ref)
        }
    }

    // MARK: queue

    /// Queues `operation` behind what was already made on this card and waits for its answer. An `input` for the same
    /// control at the tail is merged instead of queued, so typing never fills the queue.
    private func ordered(_ ref: String, _ operation: Operation) async throws -> CardStep {
        guard !closed || operation.isDisposal else { throw AppFailure.busy }
        return try await withCheckedThrowingContinuation { continuation in
            var queue = queues[ref] ?? []
            if case .event(let key, .input(_)) = operation, let last = queue.indices.last,
               case .event(let tailKey, .input(_)) = queue[last].operation, tailKey == key {
                queue[last].operation = operation
                queue[last].waiters.append(continuation)
            } else {
                queue.append(Queued(operation: operation, waiters: [continuation]))
            }
            queues[ref] = queue
            if draining.insert(ref).inserted { Task { await self.drain(ref) } }
        }
    }

    /// Queues an operation whose answer is not needed (disposal, background suspend).
    private func serialized(_ ref: String, _ operation: Operation) async {
        _ = try? await ordered(ref, operation)
    }

    /// Every card with a session, or with an operation running: the cards an account-wide operation must reach.
    private func knownRefs() -> Set<String> { Set(entries.keys).union(draining) }

    /// The one consumer of a card's queue: applies the operations in order and answers every waiter, then stops.
    private func drain(_ ref: String) async {
        while let next = takeNext(ref) {
            let outcome: Result<CardStep, any Error>
            do { outcome = .success(try await run(ref, next.operation)) } catch { outcome = .failure(error) }
            for waiter in next.waiters { waiter.resume(with: outcome) }
        }
        draining.remove(ref)
    }

    private func takeNext(_ ref: String) -> Queued? {
        guard var queue = queues[ref], !queue.isEmpty else { queues[ref] = nil; return nil }
        let next = queue.removeFirst()
        queues[ref] = queue.isEmpty ? nil : queue
        return next
    }

    /// One operation. A dropped session (`card_session_expired` or `card_session_inactive`, as an error or as the refused
    /// result of a card with no tree) forgets the handle and answers with the card's last tree, read-only: the next tap
    /// opens the card again, never automatically.
    private func run(_ ref: String, _ operation: Operation) async throws -> CardStep {
        let step: CardStep
        do { step = try await runNow(ref, operation) } catch {
            guard !operation.isDisposal, let refusal = CardSessionRefusal.of(error), refusal == .expired || refusal == .inactive else { throw error }
            forget(ref)
            return plain(snapshot(ref))
        }
        if case .refused(let reason) = step.display.phase, reason == CardSessionRefusal.inactive.rawValue || reason == CardSessionRefusal.expired.rawValue {
            forget(ref)
            return plain(snapshot(ref))
        }
        return step
    }

    private func runNow(_ ref: String, _ operation: Operation) async throws -> CardStep {
        switch operation {
        case .open(let locale, let dark): return plain(try await openNow(ref, locale: locale, dark: dark))
        case .resume: return plain(try await resumeNow(ref))
        case .event(let key, let event): return try await eventNow(ref, key: key, event: event)
        case .answer(let token, let slotID, let requestID, let outcome):
            return try await answerNow(ref, token: token, slotID: slotID, requestID: requestID, outcome: outcome)
        case .submit: return try await submitNow(ref)
        case .refresh(let version, let locale, let dark): return try await refreshNow(ref, version: version, locale: locale, dark: dark)
        case .present(let locale, let dark): return try await presentNow(ref, locale: locale, dark: dark)
        case .suspendForBackground: await suspendForBackgroundNow(ref); return plain(snapshot(ref))
        case .dispose: await disposeNow(ref); return plain(snapshot(ref))
        }
    }

    // MARK: operations (run one at a time per card)

    private func openNow(_ ref: String, locale: String, dark: Bool) async throws -> CardDisplay {
        if let entry = entries[ref], entry.session != nil { touch(ref); return display(ref, entry) }
        if entries[ref] == nil, entries.count >= Self.maximumOpen { _ = await disposeLeastRecent(except: nil) }
        let response = try await perform(keeping: ref, kind: .open) {
            try await self.client.open(account: self.account, surfaceRef: ref, locale: locale, dark: dark)
        }
        var entry = Entry(session: response.session, tree: nil, renderAllowed: false, fallbackText: "", resident: false, touched: 0,
                          phase: .unavailable, residentAtBackground: false)
        touch(ref, into: &entry)
        entries[ref] = entry
        try applyWithoutStep(response, to: ref)
        if response.session != nil { entries[ref]?.resident = response.result == "opened" }
        if response.result == "refused" { entries[ref]?.phase = .refused(response.reason ?? "card_session_refused") }
        if suspended, entries[ref]?.resident == true {
            // Opened while the app is backgrounded or locked: the session is parked at once and comes back at the foreground.
            entries[ref]?.residentAtBackground = true
            await suspend(ref)
            entries[ref]?.phase = .suspended
        } else {
            await enforceResidency(keeping: ref)
        }
        return display(ref, entries[ref] ?? entry)
    }

    /// The tap on a card whose session was dropped (lock, sign-out, expiry): opens it again in the host's current
    /// presentation. The tap only reopens; the event it carried is not sent, because its token belongs to the dropped session.
    private func reopenNow(_ ref: String) async throws -> CardDisplay {
        let old = entries[ref]
        entries[ref] = nil
        let presentation = appearance ?? (locale: "en", dark: false)
        do { return try await openNow(ref, locale: presentation.locale, dark: presentation.dark) } catch {
            entries[ref] = old
            throw error
        }
    }

    private func resumeNow(_ ref: String) async throws -> CardDisplay {
        guard let entry = entries[ref], let session = entry.session else { throw AppFailure.invalidInput }
        if !entry.resident {
            // Backgrounded or locked: the tap only shows the card; it comes back with `resumeAll` at the foreground.
            guard !suspended else {
                entries[ref]?.residentAtBackground = true
                entries[ref]?.phase = .suspended
                return display(ref, entries[ref] ?? entry)
            }
            await enforceResidency(keeping: ref)
            let response: CardResponse
            do { response = try await perform(keeping: ref, kind: .resume) { try await self.client.resume(account: self.account, session: session) } }
            catch where Self.isOverLimit(error) {
                // No slot after one retry: the card stays read-only with the over-limit line and the next tap tries again.
                entries[ref]?.resident = false
                entries[ref]?.phase = .refused(CardSessionRefusal.limitExceeded.rawValue)
                return display(ref, entries[ref] ?? entry)
            }
            try applyWithoutStep(response, to: ref)
            entries[ref]?.resident = response.result == "resumed"
            entries[ref]?.phase = response.result == "resumed" ? .live : .refused(response.reason ?? "card_session_refused")
            if entries[ref]?.resident == true { await presentAppearance(ref, session: session) }
        }
        touch(ref)
        return display(ref, entries[ref] ?? entry)
    }

    /// A resumed session takes the host's current colour scheme and locale, which may have changed while it was suspended.
    /// A failed present keeps the resumed card as it is; the next present or open brings it up to date.
    private func presentAppearance(_ ref: String, session: UInt64) async {
        guard let appearance else { return }
        guard let response = try? await perform(keeping: ref, { try await self.client.present(account: self.account, session: session, locale: appearance.locale, dark: appearance.dark) }) else { return }
        try? applyWithoutStep(response, to: ref)
    }

    private func eventNow(_ ref: String, key: String, event: CardHostEvent) async throws -> CardStep {
        guard let entry = entries[ref], let tree = entry.tree else { throw AppFailure.invalidInput }
        guard let session = entry.session else { return plain(try await reopenNow(ref)) }
        guard entry.resident else { return plain(try await resumeNow(ref)) }
        guard let token = tree.token(for: key) else { throw AppFailure.invalidInput }
        touch(ref)
        let response = try await perform(keeping: ref) {
            try await self.client.event(account: self.account, session: session, token: token, event: event)
        }
        if case .input = event, response.result == "edited" || response.result == "validation" { entries[ref]?.hasDraft = true }
        let step = try await applyOrReload(response, to: ref)
        if response.result == "pending_submit" {
            // The runtime holds a resolved action: the host now asks the SDK to sign and submit it.
            return try await submitNow(ref)
        }
        return step
    }

    private func answerNow(_ ref: String, token: CardEventToken, slotID: String, requestID: String, outcome: CardSlotOutcome) async throws -> CardStep {
        guard let entry = entries[ref] else { throw AppFailure.invalidInput }
        guard let session = entry.session else { return plain(try await reopenNow(ref)) }
        guard entry.resident else { throw AppFailure.invalidInput }
        touch(ref)
        let response = try await perform(keeping: ref) {
            try await self.client.slot(account: self.account, session: session, token: token, slotID: slotID, requestID: requestID, outcome: outcome)
        }
        var step = try await applyOrReload(response, to: ref)
        step.slotResult = response.result
        return step
    }

    private func submitNow(_ ref: String) async throws -> CardStep {
        guard let entry = entries[ref], let session = entry.session else { throw AppFailure.invalidInput }
        entries[ref]?.phase = .submitting
        let response: CardResponse
        do {
            response = try await perform(keeping: ref) { try await self.client.submit(account: self.account, session: session) }
        } catch {
            // The call failed before the runtime answered: the card shows the refusal and the submit is not sent again.
            entries[ref]?.phase = .refused(CardSessionRefusal.of(error)?.rawValue ?? "card_submit_failed")
            throw error
        }
        let step = try await applyOrReload(response, to: ref)
        guard response.result == "submitted", let current = entries[ref] else { return step }
        entries[ref]?.phase = .consumed
        entries[ref]?.hasDraft = false
        return CardStep(display: display(ref, current), hostRequest: nil, draftConflict: false, submit: response.submit)
    }

    private func refreshNow(_ ref: String, version: UInt64, locale: String, dark: Bool) async throws -> CardStep {
        guard let entry = entries[ref] else { return plain(try await openNow(ref, locale: locale, dark: dark)) }
        guard let session = entry.session else {
            // A dropped session with a tree waits for the next tap; a card that never got a session is opened now.
            if entry.tree != nil { return plain(display(ref, entry)) }
            entries[ref] = nil
            return plain(try await openNow(ref, locale: locale, dark: dark))
        }
        guard entry.resident, entry.tree?.signedVersion != version else { return plain(display(ref, entry)) }
        let response = try await perform(keeping: ref) { try await self.client.update(account: self.account, session: session) }
        return try await applyOrReload(response, to: ref)
    }

    private func presentNow(_ ref: String, locale: String, dark: Bool) async throws -> CardStep {
        guard let entry = entries[ref], let session = entry.session, entry.resident else { throw AppFailure.invalidInput }
        let response = try await perform(keeping: ref) { try await self.client.present(account: self.account, session: session, locale: locale, dark: dark) }
        return try await applyOrReload(response, to: ref)
    }

    // MARK: residency

    private enum CallKind { case open, resume, other }
    private enum Recovery { case none, disposeOldest, suspendOldest }

    /// An open that the process budget refused, or a resume that failed as invalid (core leaves the resume cap untyped at
    /// this pin): both mean "no slot" and take the same one retry.
    private static func isOverLimit(_ error: any Error) -> Bool {
        let refusal = CardSessionRefusal.of(error)
        if refusal == .limitExceeded { return true }
        guard refusal == nil, let failure = error as? CoreFailure else { return false }
        return failure.code == .invalidArgument
    }

    private static func recovery(for error: any Error, kind: CallKind) -> Recovery {
        if CardSessionRefusal.of(error) == .limit { return .disposeOldest }
        switch kind {
        case .open: return CardSessionRefusal.of(error) == .limitExceeded ? .suspendOldest : .none
        case .resume: return isOverLimit(error) ? .suspendOldest : .none
        case .other: return .none
        }
    }

    /// Runs one bus call with one retry. `card_session_limit` (32 sessions of the account) disposes this account's least
    /// recently used card; `card_limit_exceeded` on open, or an invalid-argument failure on resume, suspends the least
    /// recently used resumed card of any account (the cap is the process's). A second failure is the caller's.
    private func perform(keeping ref: String, kind: CallKind = .other, _ call: () async throws -> CardResponse) async throws -> CardResponse {
        do { return try await call() } catch {
            switch Self.recovery(for: error, kind: kind) {
            case .none: throw error
            case .disposeOldest:
                guard await disposeLeastRecent(except: ref) else { throw error }
            case .suspendOldest:
                guard await residency.suspendLeastRecent(ResidentKey(account: account, ref: ref)) else { throw error }
            }
            return try await call()
        }
    }

    /// Makes room before a card takes a resident slot: while the process holds the maximum of resumed cards, the least
    /// recently used one (of any account) is suspended.
    private func enforceResidency(keeping ref: String) async {
        let key = ResidentKey(account: account, ref: ref)
        while await residency.residentCount(key) >= Self.maximumResident {
            guard await residency.suspendLeastRecent(key) else { return }
        }
    }

    private func suspend(_ ref: String) async {
        guard let session = entries[ref]?.session else { return }
        // A suspend that fails leaves the runtime without a resident VM in any case; the card is read-only either way.
        _ = try? await client.suspend(account: account, session: session)
        entries[ref]?.resident = false
        if entries[ref]?.phase == .live { entries[ref]?.phase = .suspended }
    }

    /// Evicts the least recently used card of this account to make room. Only the open of another card calls this, so the
    /// eviction is direct rather than queued (two opens waiting on each other's queues would deadlock). A card with an
    /// operation in flight is never evicted: when every candidate is draining, nothing is evicted and the pool overshoots
    /// the open limit until `retain` trims it.
    @discardableResult
    private func disposeLeastRecent(except ref: String?) async -> Bool {
        guard let victim = entries.filter({ $0.key != ref && !draining.contains($0.key) }).min(by: { $0.value.touched < $1.value.touched })?.key else { return false }
        await disposeNow(victim)
        return true
    }

    private func suspendForBackgroundNow(_ ref: String) async {
        guard entries[ref]?.resident == true else { return }
        entries[ref]?.residentAtBackground = true
        await suspend(ref)
    }

    private func disposeNow(_ ref: String) async {
        if let session = entries[ref]?.session { _ = try? await client.dispose(account: account, session: session) }
        entries[ref] = nil
    }

    // MARK: state

    private func touch(_ ref: String) {
        entries[ref]?.touched = residency.tick()
    }

    private func touch(_ ref: String, into entry: inout Entry) {
        entry.touched = residency.tick()
    }

    /// Drops the handle of a card whose session the SDK dropped. The last tree stays drawn read-only (a card that was
    /// never drawn is forgotten whole, so the next list refresh opens it); a draft that was visible is reported once.
    private func forget(_ ref: String) {
        guard var entry = entries[ref] else { return }
        guard entry.tree != nil else { entries[ref] = nil; return }
        entry.draftDiscarded = entry.hasDraft
        entry.hasDraft = false; entry.contentChanged = false
        entry.session = nil; entry.resident = false; entry.residentAtBackground = false
        switch entry.phase {
        case .consumed, .superseded: break
        default: entry.phase = .suspended
        }
        entries[ref] = entry
    }

    private func plain(_ display: CardDisplay) -> CardStep {
        CardStep(display: display, hostRequest: nil, draftConflict: false, submit: nil)
    }

    /// Applies a response to the entry it belongs to. A batch that does not match the held tree re-reads the full tree.
    private func apply(_ response: CardResponse, to ref: String) throws -> CardStep {
        try applyWithoutStep(response, to: ref)
        guard let entry = entries[ref] else { throw AppFailure.invalidData }
        return CardStep(display: display(ref, entry), hostRequest: response.hostRequest, draftConflict: response.draftConflict, submit: response.submit)
    }

    private func applyWithoutStep(_ response: CardResponse, to ref: String) throws {
        guard var entry = entries[ref] else { return }
        entry.renderAllowed = response.renderAllowed
        entry.fallbackText = response.fallbackText
        if let batch = response.batch {
            do { entry.tree = try (entry.tree ?? CardTree()).applying(batch) }
            catch {
                // The held tree and the runtime disagree: the card stays read-only until a full tree is read again.
                entry.resident = false
                entry.phase = .refused("card_tree_mismatch")
                entries[ref] = entry
                throw AppFailure.invalidData
            }
        }
        entry.contentChanged = response.result == "stale_dropped"
        switch response.result {
        case "pending_submit": entry.phase = .submitting
        case "submitted": entry.phase = .consumed
        case "superseded": entry.phase = .superseded(replacement: response.replacementRef)
        case "refused": entry.phase = .refused(response.reason ?? response.result)
        // A stale event or answer: its batch reverted the field; the card stays as it was.
        case "stale_dropped": if entry.resident, entry.phase != .consumed { entry.phase = .live }
        default: if entry.resident { entry.phase = .live }
        }
        entries[ref] = entry
    }

    /// A batch that did not match the held tree: the full tree is read again, so the card never draws a stale state.
    private func applyOrReload(_ response: CardResponse, to ref: String) async throws -> CardStep {
        do { return try apply(response, to: ref) } catch {
            guard entries[ref]?.phase == .refused("card_tree_mismatch") else { throw error }
            return plain(try await reload(ref))
        }
    }

    /// Suspend and resume take the full tree again (previous version 0) under a fresh token session.
    private func reload(_ ref: String) async throws -> CardDisplay {
        if let session = entries[ref]?.session { _ = try? await client.suspend(account: account, session: session) }
        entries[ref]?.resident = false
        entries[ref]?.tree = nil
        return try await resumeNow(ref)
    }

    private func display(_ ref: String, _ entry: Entry) -> CardDisplay {
        CardDisplay(surfaceRef: ref, tree: entry.tree, renderAllowed: entry.renderAllowed, fallbackText: entry.fallbackText,
                    resident: entry.resident, phase: entry.phase, draftDiscarded: entry.draftDiscarded, contentChanged: entry.contentChanged)
    }

    /// The display of a card now, or an unavailable display when it has no session.
    private func snapshot(_ ref: String) -> CardDisplay {
        guard let entry = entries[ref] else {
            return CardDisplay(surfaceRef: ref, tree: nil, renderAllowed: false, fallbackText: "", resident: false, phase: .unavailable, draftDiscarded: false, contentChanged: false)
        }
        return display(ref, entry)
    }
}

/// A card of an account, as the process-wide resident budget names it.
struct ResidentKey: Hashable, Sendable {
    let account: String
    let ref: String
}

/// The resident budget the pools of one process share (core allows two resident card VMs per process, whatever the
/// account). `tick` is one clock for every pool, so "least recently used" compares across accounts.
struct CardResidency: Sendable {
    let tick: @Sendable () -> UInt64
    /// How many cards of any account are resumed, not counting `key`.
    let residentCount: @Sendable (_ excluding: ResidentKey) async -> Int
    /// Suspends the least recently used resumed card of any account except `key`; false when there is none to suspend.
    let suspendLeastRecent: @Sendable (_ excluding: ResidentKey) async -> Bool
}

private final class CardTicker: Sendable {
    private let value = Mutex<UInt64>(0)
    func next() -> UInt64 { value.withLock { $0 &+= 1; return $0 } }
}

/// One pool per account, shared by the repositories and the lifecycle hooks of the process. The registry owns the
/// process's resident budget of two.
public actor CardSessionRegistry {
    private let client: CardSessionClient
    private var pools: [String: CardSessionPool] = [:]
    /// Set by `suspendAll` and cleared by `resumeAll`: a pool created in between starts suspended.
    private var suspended = false
    private let ticker = CardTicker()
    /// The images of the cards, released with their sessions and with the account's lock.
    public let images: CardImageLoader

    public init(client: RamfluxClient) {
        let gateway = ProxyGateway(proxy: SDKProxy(client: client))
        self.client = CardSessionClient(gateway: gateway)
        images = CardImageLoader(gateway: gateway)
    }

    public func pool(account: String) -> CardSessionPool {
        if let pool = pools[account] { return pool }
        let ticker = self.ticker
        let residency = CardResidency(tick: { ticker.next() },
                                      residentCount: { [weak self] key in await self?.residentCount(excluding: key) ?? 0 },
                                      suspendLeastRecent: { [weak self] key in await self?.suspendLeastRecent(excluding: key) ?? false })
        let pool = CardSessionPool(client: client, account: account, residency: residency, suspended: suspended)
        pools[account] = pool
        return pool
    }

    private func residentCount(excluding key: ResidentKey) async -> Int {
        var count = 0
        for (account, pool) in pools {
            count += await pool.residentTouches().filter { !(account == key.account && $0.ref == key.ref) }.count
        }
        return count
    }

    private func suspendLeastRecent(excluding key: ResidentKey) async -> Bool {
        var best: (pool: CardSessionPool, ref: String, touched: UInt64)?
        for (account, pool) in pools {
            guard let candidate = await pool.leastRecentResident(excluding: account == key.account ? key.ref : nil) else { continue }
            if best == nil || candidate.touched < (best?.touched ?? .max) { best = (pool, candidate.ref, candidate.touched) }
        }
        guard let best else { return false }
        return await best.pool.suspendResident(best.ref)
    }

    /// The account locked or is about to: the SDK dropped its sessions, so every handle is forgotten here with no bus call
    /// (a call on a locked account would only fail). The trees stay for drawing.
    public func forgetAccount(_ account: String) async {
        await pools[account]?.forgetAll(close: false)
        await images.releaseAccount(account)
    }

    /// Sign-out or removal: the handles are forgotten as for a lock and the pool is closed and released.
    public func closeAccount(_ account: String) async {
        await images.releaseAccount(account)
        guard let pool = pools.removeValue(forKey: account) else { return }
        await pool.forgetAll(close: true)
    }

    /// Background: every account's resident sessions are suspended.
    public func suspendAll() async {
        suspended = true
        for pool in pools.values { await pool.suspendAll() }
    }

    /// Foreground: the sessions that were resident at the background come back.
    public func resumeAll() async {
        suspended = false
        for pool in pools.values { await pool.resumeAll() }
    }
}
