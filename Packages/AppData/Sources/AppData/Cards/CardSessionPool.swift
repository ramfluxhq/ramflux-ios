// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

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

/// Card sessions of one account. The runtime keeps at most two resident VMs per process and 32 sessions per account;
/// this pool keeps at most two resumed sessions (the most recently touched), at most 24 open, suspends the rest and
/// disposes the sessions whose cards left the loaded window. A `card_session_limit` refusal suspends the least
/// recently used session and retries once.
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
    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
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

    init(client: CardSessionClient, account: String, suspended: Bool = false) {
        self.client = client; self.account = account; self.suspended = suspended
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

    /// Sign-out or removal of the account: no further operation is accepted and every session of the account is disposed
    /// behind the operations already queued on it.
    public func disposeAll() async {
        closed = true
        for ref in knownRefs() { await serialized(ref, .dispose) }
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

    private func run(_ ref: String, _ operation: Operation) async throws -> CardStep {
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
        if entries[ref] == nil, entries.count >= Self.maximumOpen { try await disposeLeastRecent(except: nil) }
        let response = try await perform(keeping: ref) {
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
            try await enforceResidency(keeping: ref)
        }
        return display(ref, entries[ref] ?? entry)
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
            try await enforceResidency(keeping: ref)
            let response = try await perform(keeping: ref) { try await self.client.resume(account: self.account, session: session) }
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
        guard let entry = entries[ref], let session = entry.session, let tree = entry.tree else { throw AppFailure.invalidInput }
        guard entry.resident else { return plain(try await resumeNow(ref)) }
        guard let token = tree.token(for: key) else { throw AppFailure.invalidInput }
        touch(ref)
        let response = try await perform(keeping: ref) {
            try await self.client.event(account: self.account, session: session, token: token, event: event)
        }
        let step = try await applyOrReload(response, to: ref)
        if response.result == "pending_submit" {
            // The runtime holds a resolved action: the host now asks the SDK to sign and submit it.
            return try await submitNow(ref)
        }
        return step
    }

    private func answerNow(_ ref: String, token: CardEventToken, slotID: String, requestID: String, outcome: CardSlotOutcome) async throws -> CardStep {
        guard let entry = entries[ref], let session = entry.session, entry.resident else { throw AppFailure.invalidInput }
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
        return CardStep(display: display(ref, current), hostRequest: nil, draftConflict: false, submit: response.submit)
    }

    private func refreshNow(_ ref: String, version: UInt64, locale: String, dark: Bool) async throws -> CardStep {
        guard let entry = entries[ref] else { return plain(try await openNow(ref, locale: locale, dark: dark)) }
        guard let session = entry.session else {
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

    /// Runs one bus call; a `card_session_limit` refusal suspends the least recently used resident session and retries once.
    private func perform(keeping ref: String, _ call: () async throws -> CardResponse) async throws -> CardResponse {
        do { return try await call() } catch where CardSessionRefusal.of(error) == .limit {
            guard try await suspendLeastRecent(except: ref) else { throw error }
            return try await call()
        }
    }

    private func enforceResidency(keeping ref: String) async throws {
        while residentCount(excluding: ref) >= Self.maximumResident {
            guard try await suspendLeastRecent(except: ref) else { return }
        }
    }

    private func residentCount(excluding ref: String) -> Int { entries.filter { $0.key != ref && $0.value.resident }.count }

    @discardableResult
    private func suspendLeastRecent(except ref: String) async throws -> Bool {
        guard let victim = entries.filter({ $0.key != ref && $0.value.resident }).min(by: { $0.value.touched < $1.value.touched }) else { return false }
        await suspend(victim.key)
        return true
    }

    private func suspend(_ ref: String) async {
        guard let session = entries[ref]?.session else { return }
        // A suspend that fails leaves the runtime without a resident VM in any case; the card is read-only either way.
        _ = try? await client.suspend(account: account, session: session)
        entries[ref]?.resident = false
        if entries[ref]?.phase == .live { entries[ref]?.phase = .suspended }
    }

    /// Evicts the least recently used card to make room for an open. Only the open of another card calls this, so the
    /// eviction is direct rather than queued (two opens waiting on each other's queues would deadlock). A card with an
    /// operation in flight is never evicted: when every candidate is draining, nothing is evicted and the pool overshoots
    /// the open limit until `retain` trims it.
    private func disposeLeastRecent(except ref: String?) async throws {
        guard let victim = entries.filter({ $0.key != ref && !draining.contains($0.key) }).min(by: { $0.value.touched < $1.value.touched })?.key else { return }
        await disposeNow(victim)
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
        clock &+= 1
        entries[ref]?.touched = clock
    }

    private func touch(_ ref: String, into entry: inout Entry) {
        clock &+= 1
        entry.touched = clock
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
        switch response.result {
        case "pending_submit": entry.phase = .submitting
        case "submitted": entry.phase = .consumed
        case "superseded": entry.phase = .superseded(replacement: response.replacementRef)
        case "refused", "stale_dropped": entry.phase = .refused(response.reason ?? response.result)
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
                    resident: entry.resident, phase: entry.phase)
    }

    /// The display of a card now, or an unavailable display when it has no session.
    private func snapshot(_ ref: String) -> CardDisplay {
        guard let entry = entries[ref] else {
            return CardDisplay(surfaceRef: ref, tree: nil, renderAllowed: false, fallbackText: "", resident: false, phase: .unavailable)
        }
        return display(ref, entry)
    }
}

/// One pool per account, shared by the repositories and the lifecycle hooks of the process.
public actor CardSessionRegistry {
    private let client: CardSessionClient
    private var pools: [String: CardSessionPool] = [:]
    /// Set by `suspendAll` and cleared by `resumeAll`: a pool created in between starts suspended.
    private var suspended = false

    public init(client: RamfluxClient) {
        self.client = CardSessionClient(gateway: ProxyGateway(proxy: SDKProxy(client: client)))
    }

    public func pool(account: String) -> CardSessionPool {
        if let pool = pools[account] { return pool }
        let pool = CardSessionPool(client: client, account: account, suspended: suspended)
        pools[account] = pool
        return pool
    }

    /// Sign-out or removal: the account's sessions are disposed and its pool is forgotten.
    public func disposeAccount(_ account: String) async {
        guard let pool = pools.removeValue(forKey: account) else { return }
        await pool.disposeAll()
    }

    /// The account's app lock is about to engage: its resident sessions are suspended; the sessions stay open.
    public func suspendAccount(_ account: String) async {
        await pools[account]?.suspendAll()
    }

    /// Background, or the app lock engaged: every account's resident sessions are suspended.
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
