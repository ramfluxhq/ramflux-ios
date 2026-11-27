// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// Native session and its projection mapper. Never passes SDK frames into feature modules.
public actor NativeSessionRepository: SessionRepository {
    private let client: RamfluxClient
    private let lifecycle: PhoneLifecycle
    private let proxy: SDKProxy
    private var observer: AsyncStream<SessionSnapshot>.Continuation?
    private var current = SessionSnapshot(phase: .stopped)
    private var revision: UInt64 = 0
    private let updates: NativeUpdateSource?
    /// Card sessions are suspended with the SDK at background and app lock, and resumed at foreground.
    private let cards: CardSessionRegistry?
    /// The queued card suspends, newest last. Each is chained behind the previous one, and a foreground resume waits for
    /// the chain, so no suspend can land after the resume that brings the cards back.
    private var cardSuspend: Task<Void, Never>?
    private let appLock: AppLockService
    public init(client: RamfluxClient, dataRoot: URL, updates: NativeUpdateSource? = nil, cards: CardSessionRegistry? = nil) {
        self.client = client; self.updates = updates; self.cards = cards; proxy = SDKProxy(client: client); lifecycle = PhoneLifecycle(client: client, dataRoot: dataRoot)
        appLock = AppLockService(gateway: ProxyGateway(proxy: proxy))
    }
    /// Queues the suspend of every card session without waiting for it: the card operations in flight finish first, and
    /// the caller (background, lock) is not held up by them.
    private func suspendCards() {
        guard let registry = cards else { return }
        let previous = cardSuspend
        cardSuspend = Task { await previous?.value; await registry.suspendAll() }
    }
    /// The app lock engaged for `account`: the SDK dropped its card sessions, so their handles are forgotten here with no bus
    /// call (the cards keep their last tree and the next tap opens them again). Queued behind earlier suspends.
    private func forgetCards(account: String?) {
        guard let registry = cards else { return }
        guard let account else { suspendCards(); return }
        let previous = cardSuspend
        cardSuspend = Task { await previous?.value; await registry.forgetAccount(account) }
    }
    /// Waits for the queued card suspends, at most `bound`: they must reach the SDK before the client suspends,
    /// which refuses card calls afterwards, but a slow card call never holds up the background for long. When the
    /// bound passes first, the suspends still queued reach the SDK after the client suspend and are refused there;
    /// the core drops the sessions of a suspended client's locked account itself.
    private func awaitCardSuspend(bound: Duration) async {
        guard let task = cardSuspend else { return }
        // Neither waiter is joined: a task group would wait for the card suspend even after the bound passed.
        let once = ResumeOnce()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task { await task.value; once.resume(continuation) }
            Task { try? await Task.sleep(for: bound); once.resume(continuation) }
        }
    }
    /// Brings the card sessions back once the queued suspends have run.
    private func resumeCards() async {
        await cardSuspend?.value
        cardSuspend = nil
        await cards?.resumeAll()
    }
    public func snapshots() -> AsyncStream<SessionSnapshot> {
        observer?.finish()
        let pair = AsyncStream<SessionSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observer = pair.continuation; observer?.yield(current)
        return pair.stream
    }
    /// The last account that was open in this process: an engaged app lock closes the account in the SDK, so
    /// `account.list` then names no active account and this is the first one to ask about.
    private var lastActiveAccount: String?
    private func publish(_ value: SessionSnapshot) {
        current = value
        if let id = value.activeAccountID { lastActiveAccount = id }
        observer?.yield(value)
    }
    /// Opens the SDK on the first foreground and resumes it after the background; neither asks for
    /// the account code. A return from the background keeps the published snapshot, so the screens stay
    /// as they were. On a cold start the SDK reopens accounts that were not explicitly locked through
    /// their device-bound key (`account.list` reports them `restore_pending` until that finishes).
    public func activate() async -> RepositoryResult<SessionSnapshot> {
        revision &+= 1; let epoch = revision
        if current.phase != .ready { publish(SessionSnapshot(phase: .opening, appLockEnabled: current.appLockEnabled)) }
        do {
            try await lifecycle.foreground()
            await updates?.resumeAfterBackground()
            var snapshot = try await accounts()
            // The silent reopen runs inside the SDK after open; wait for it boundedly before showing a
            // locked account that is about to open by itself.
            for _ in 0..<50 where snapshot.restorePending {
                try await Task.sleep(for: .milliseconds(200))
                snapshot = try await accounts()
            }
            guard epoch == revision, !Task.isCancelled else { return .failure(.busy) }
            let value = try await withAppLock(snapshot.value)
            guard epoch == revision, !Task.isCancelled else { return .failure(.busy) }
            // Card sessions come back only once the app-lock decision is known: an engaged lock keeps them suspended.
            if value.appLocked { forgetCards(account: value.activeAccountID) } else { await resumeCards() }
            publish(value); return .success(value)
        } catch where AppFailure.isAppLocked(error) {
            // The SDK refused a call because the app lock is engaged: the records stay covered and the code is asked.
            return await raiseAppLock(account: current.activeAccountID, epoch: epoch)
        } catch {
            EventDiagnostics.failed("session activate", error)
            let failure = AppFailure.map(error)
            if epoch == revision { publish(SessionSnapshot(phase: .failed(failure), appLockEnabled: current.appLockEnabled)) }
            return .failure(failure)
        }
    }
    /// The one handler of an `app_locked` refusal, wherever it comes from (activation, selection, background): the
    /// lock screen is raised and `account.app_lock.state` is read again for the enabled flag; a failed read keeps
    /// the flag on (fail closed). With no account there is nothing to unlock, so the failure is kept covered with a
    /// retry. Nothing is published once a newer operation has started.
    private func raiseAppLock(account: String?, epoch: UInt64) async -> RepositoryResult<SessionSnapshot> {
        // The lock closes the SDK's unlocked state for the card sessions too: none stays resident behind the lock. The
        // suspend is queued, not awaited, so the lock snapshot below is published without waiting for card operations.
        forgetCards(account: account)
        guard let account else {
            guard epoch == revision else { return .failure(.busy) }
            publish(SessionSnapshot(phase: .failed(.locked), appLockEnabled: true))
            return .failure(.locked)
        }
        let enabled = (try? await appLock.state(account: account))?.enabled ?? true
        guard epoch == revision else { return .failure(.busy) }
        let value = SessionSnapshot(phase: .ready, accounts: current.accounts, activeAccountID: account, appLocked: true, appLockEnabled: enabled)
        publish(value); return .success(value)
    }
    /// Reads the active account's app lock after the SDK resumed. An engaged lock is reported in the snapshot and
    /// nothing is told to the SDK (the shell covers the records until the code is entered). Otherwise the SDK gets
    /// the foreground lifecycle, which cancels the deadline armed when the app went away. Its reply is the lock as
    /// the core holds it now, so a lock that expired at that call is reported as engaged.
    private func withAppLock(_ value: SessionSnapshot) async throws -> SessionSnapshot {
        guard let account = value.activeAccountID else { return await engagedAppLock(in: value) }
        var record = try await appLock.state(account: account)
        if record.state != .locked { record = try await appLock.lifecycle(account: account, .foreground) }
        return SessionSnapshot(phase: value.phase, accounts: value.accounts, activeAccountID: value.activeAccountID, appLocked: record.state == .locked, appLockEnabled: record.enabled)
    }
    /// An engaged app lock closes the account inside the SDK: `account.list` then lists it as locked (name redacted)
    /// and names no active account. Such an account whose app lock is on and engaged is the one the code is asked
    /// for, so the shell shows the app-lock form instead of the locked-accounts screen. Any other locked account
    /// (an explicit lock with the app lock off) keeps the ordinary account-unlock path.
    private func engagedAppLock(in value: SessionSnapshot) async -> SessionSnapshot {
        var candidates = value.accounts.filter(\.isLocked)
        if let last = lastActiveAccount, let index = candidates.firstIndex(where: { $0.id == last }) { candidates.insert(candidates.remove(at: index), at: 0) }
        for candidate in candidates.prefix(8) {
            let record: AppLockRecord?
            do { record = try await appLock.state(account: candidate.id) }
            catch where AppFailure.isAppLocked(error) { record = nil }
            catch { continue }
            guard record == nil || (record?.enabled == true && record?.state == .locked) else { continue }
            let rows = value.accounts.map { $0.id == candidate.id ? AccountRecord(id: $0.id, displayName: $0.displayName, isLocked: false) : $0 }
            return SessionSnapshot(phase: value.phase, accounts: rows, activeAccountID: candidate.id, appLocked: true, appLockEnabled: true)
        }
        return value
    }
    private func accounts() async throws -> (value: SessionSnapshot, restorePending: Bool) {
        try Self.decodeAccountList(try await proxy.accountList(context: context()))
    }
    /// The app went to the background: live updates pause (observers stay registered) and the SDK
    /// suspends. The session snapshot is kept, so nothing is torn down or asked for on return.
    public func suspend() async -> RepositoryResult<Void> {
        revision &+= 1; let epoch = revision
        // Best effort while the SDK is still running: the lifecycle arms the deadline of an enabled app lock, and the
        // enabled flag is published so the shell covers the next return until the lock is read. The SDK arms the
        // deadline on suspend as well, so a refusal here (for instance an already suspended core) is not fatal.
        if let account = current.activeAccountID {
            // A failed read leaves the flag unknown, so the next return keeps the records covered (fail closed).
            // A refused read means the lock is already engaged: it is raised, and the suspend below still runs.
            var lockRefused = false
            let enabled: Bool?
            do { enabled = try await appLock.state(account: account).enabled }
            catch where AppFailure.isAppLocked(error) { lockRefused = true; enabled = nil }
            catch { EventDiagnostics.failed("app lock state at background", error); enabled = nil }
            // A newer activation or selection owns the session now: nothing of this background is applied.
            guard epoch == revision else { return .failure(.busy) }
            if lockRefused {
                _ = await raiseAppLock(account: account, epoch: epoch)
            } else {
                publish(SessionSnapshot(phase: current.phase, accounts: current.accounts, activeAccountID: current.activeAccountID, appLocked: current.appLocked, appLockEnabled: enabled))
                do { _ = try await appLock.lifecycle(account: account, .background) }
                catch where AppFailure.isAppLocked(error) { _ = await raiseAppLock(account: account, epoch: epoch) }
                catch { EventDiagnostics.failed("app lock lifecycle at background", error) }
            }
        }
        guard epoch == revision else { return .failure(.busy) }
        // Card sessions are suspended while the SDK still runs; the client suspend below refuses card calls.
        suspendCards()
        await awaitCardSuspend(bound: .milliseconds(1500))
        // A newer activation or selection may have started during the wait: it owns the session now.
        guard epoch == revision else { return .failure(.busy) }
        await updates?.suspendForBackground()
        let outcome: RepositoryResult<Void>
        do { try await lifecycle.background(); outcome = .success(()) }
        catch { let failure = AppFailure.map(error); if epoch == revision { publish(SessionSnapshot(phase: .failed(failure))) }; outcome = .failure(failure) }
        return outcome
    }
    /// The app lock of the active account was configured in Settings: the flag the shell reads follows at once.
    public func appLockConfigured(enabled: Bool) async {
        publish(SessionSnapshot(phase: current.phase, accounts: current.accounts, activeAccountID: current.activeAccountID, appLocked: current.appLocked, appLockEnabled: enabled))
    }
    public func selectAccount(_ id: String) async -> RepositoryResult<SessionSnapshot> {
        guard current.phase == .ready, current.accounts.contains(where: { $0.id == id && !$0.isLocked }) else { return .failure(.locked) }
        let epoch = revision
        do {
            let result = try await proxy.accountSwitch(context: context(account: id, operation: .fresh()))
            do { try Self.validateMutation(result) } catch { return .failure(.outcomeUnknown) }
            guard epoch == revision, !Task.isCancelled else { return .failure(.outcomeUnknown) }
            let snapshot = try await withAppLock(SessionSnapshot(phase: .ready, accounts: current.accounts, activeAccountID: id))
            publish(snapshot); return .success(snapshot)
        } catch where AppFailure.isAppLocked(error) {
            return await raiseAppLock(account: id, epoch: epoch)
        } catch { return .failure(AppFailure.map(error)) }
    }
    private func context(account: String? = nil, operation: OperationID? = nil) -> RequestContext {
        RequestContext(accountID: account, operationID: operation, deadlineUnixMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 10_000)
    }
    static func decodeAccounts(_ sealed: SecretBytes) throws -> SessionSnapshot { try decodeAccountList(sealed).value }
    static func decodeAccountList(_ sealed: SecretBytes) throws -> (value: SessionSnapshot, restorePending: Bool) {
        try sealed.consume { bytes in
            let completion = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
            guard completion["code"] == .number(0), completion["response"]?["ok"] == .bool(true),
                  let body = completion["response"]?["body"], case .array(let values) = body["accounts"], values.count <= 4096 else { throw AppFailure.invalidData }
            // Every account held on this phone, open or locked, with its display name (`account.list` rows
            // `{id, display_name, locked}`); the active account is always an open one.
            // `active_account_id` names an open account. Right after a cold start the SDK's silent reopen can
            // finish between the two halves of one `account.list` answer, so the picker row may still say
            // locked; the active account is open either way.
            let active = body["active_account_id"]?.string
            let accounts = try values.map { value in
                guard let id = value["id"]?.string, !id.isEmpty, id.utf8.count <= 256, let locked = value["locked"]?.bool else { throw AppFailure.invalidData }
                let name = value["display_name"]?.string.flatMap { $0.isEmpty || $0.utf8.count > 1024 ? nil : $0 } ?? id
                return AccountRecord(id: id, displayName: name, isLocked: locked && id != active)
            }
            guard Set(accounts.map(\.id)).count == accounts.count else { throw AppFailure.invalidData }
            guard active == nil || accounts.contains(where: { $0.id == active && !$0.isLocked }) else { throw AppFailure.invalidData }
            var pending = false
            if case .array(let details) = body["account_details"] { pending = details.contains { $0["state"]?.string == "restore_pending" } }
            return (SessionSnapshot(phase: .ready, accounts: accounts, activeAccountID: active), pending)
        }
    }
    private static func validateMutation(_ sealed: SecretBytes) throws {
        try sealed.consume { bytes in
            let completion = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
            guard completion["code"] == .number(0), completion["response"]?["ok"] == .bool(true) else { throw AppFailure.outcomeUnknown }
        }
    }
    deinit { observer?.finish() }
}

/// Resumes a continuation exactly once, whichever caller comes first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { continuation.resume() }
    }
}
