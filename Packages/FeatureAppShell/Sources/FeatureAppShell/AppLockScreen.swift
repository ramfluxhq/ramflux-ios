// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import Observation
import AppData
import RFDesign

/// Unlocks an engaged app lock, or a locked account, with the account code (`account.unlock`, the code-only
/// path). The page names the one account it is bound to (its avatar initial and display name, read from `account.list`
/// for that account id and never logged), offers no forget or dismiss, and never moves the navigation: success only
/// asks the shell to re-activate, so the same screen is back underneath. Once the code checks are used up it offers
/// two exits for this account only: recovery with the recovery phrase and the account code, or removal from this device.
@Observable @MainActor public final class AppLockModel {
    public private(set) var busy = false
    public private(set) var failure: AppFailure?
    /// The account this page is bound to, as `account.list` names it. Only its own name and initial are drawn.
    public var account: AccountRecord?
    /// A recovery that ended with a wrong account code returns here: the exhausted page shows this notice above its title.
    public private(set) var codeNotice = false
    /// The account-code wait the SDK named, on a monotonic clock; nil when no wait applies. The field is off until it ends.
    public private(set) var waitUntil: ContinuousClock.Instant?
    /// The account-code checks are used up: no field, only the recovery phrase restores the account.
    public private(set) var exhausted = false
    /// The running wait follows an accepted recovery phrase: one code try is granted when it ends.
    public private(set) var phraseAccepted = false
    /// The removal confirmation is shown in place of the exhausted page.
    public private(set) var confirmingRemoval = false
    public private(set) var removalAcknowledged = false
    public private(set) var removing = false
    public private(set) var removalFailure: AppFailure?
    private var waitTimer: Task<Void, Never>?
    private let repository: any OnboardingRepository
    private let settings: any SettingsRepository
    let accountID: String
    private let onUnlocked: @MainActor () -> Void
    private let onRestore: @MainActor () -> Void
    private let onRemoved: @MainActor () -> Void
    public init(repository: any OnboardingRepository, settings: any SettingsRepository, account: String, record: AccountRecord? = nil,
                onUnlocked: @escaping @MainActor () -> Void, onRestore: @escaping @MainActor () -> Void, onRemoved: @escaping @MainActor () -> Void = {}) {
        self.repository = repository; self.settings = settings; self.accountID = account; self.account = record; self.onUnlocked = onUnlocked; self.onRestore = onRestore; self.onRemoved = onRemoved
    }
    public var waiting: Bool { waitUntil != nil }
    public func submit(_ input: SensitiveSubmission) {
        guard !busy, !waiting, !exhausted else { input.erase(); return }
        if let issue = input.accountCodeIssue { input.erase(); failure = .accountCode(issue); return }
        busy = true; failure = nil
        Task { [repository, accountID] in
            let result = await repository.unlock(accountID: accountID, submission: input)
            self.busy = false
            switch result {
            case .success: self.onUnlocked()
            case .failure(let error):
                self.failure = error
                self.apply(error)
                // A throttle that names no wait is read from the SDK's app-lock state, which carries it. A wrong code may be
                // the one that starts the wait (or uses the checks up): the state is read then too, so the countdown shows at once.
                if error == .accountCode(.retryLater) || error == .accountCode(.wrong) { await self.readState() }
            }
        }
    }
    public func restore() { guard exhausted, !busy, !removing else { return }; codeNotice = false; onRestore() }
    /// The user started typing: a status that described the last try goes; a running wait stays.
    public func fieldEdited() { if !waiting, failure != nil { failure = nil } }
    public func dismissNotice() { codeNotice = false }
    /// Reads the app-lock state again (every cover show): the exhausted page and the wait come from the SDK, never from
    /// anything this model remembers.
    public func refresh() async { await readState() }
    /// The recovery in the cover ended with a refusal that moves the lock screen. An accepted phrase leaves one code try
    /// under the wait that applies; a wrong code spends it. The state is read again either way.
    public func recoveryEnded(_ error: AppFailure) {
        switch error {
        case .accountCodeWait(_, let until): exhausted = false; phraseAccepted = true; failure = nil; startWait(until)
        case .accountCode(.retryLater): exhausted = false; phraseAccepted = true; failure = nil
        case .accountCode(.wrong): phraseAccepted = false; failure = nil; codeNotice = true
        default: phraseAccepted = false; failure = nil
        }
        Task { await readState() }
    }
    public func requestRemoval() {
        guard exhausted, !busy, !removing else { return }
        confirmingRemoval = true; removalAcknowledged = false; removalFailure = nil
    }
    public func acknowledgeRemoval(_ value: Bool) { if confirmingRemoval, !removing { removalAcknowledged = value } }
    public func cancelRemoval() { guard !removing else { return }; dismissRemoval() }
    /// The cover left the foreground: a removal that has not started is dismissed; nothing is kept.
    public func conceal() { guard !removing else { return }; dismissRemoval() }
    private func dismissRemoval() { confirmingRemoval = false; removalAcknowledged = false; removalFailure = nil }
    /// Removes this account from this device (`account.remove_local`, the account id in the envelope and as the
    /// confirmation). It needs the explicit acknowledgement; a failure leaves the account and the cover as they are.
    public func confirmRemoval() {
        guard confirmingRemoval, removalAcknowledged, !removing else { return }
        removing = true; removalFailure = nil
        Task { [settings, accountID] in
            let result = await settings.mutate(account: accountID, change: .removeLocal, operationID: UUID().uuidString)
            self.removing = false
            switch result {
            case .success: self.dismissRemoval(); self.onRemoved()
            case .failure(let error): self.removalFailure = error
            }
        }
    }
    private func apply(_ error: AppFailure) {
        switch error {
        case .accountCodeWait(_, let until): exhausted = false; phraseAccepted = false; startWait(until)
        case .accountCode(.attemptsExhausted): exhausted = true; phraseAccepted = false; failure = nil; clearWait()
        // A missing device unlock secret keeps the field and shows its own failure text; it is not the restore-only state.
        default: clearWait()
        }
    }
    private func readState() async {
        guard case .success(let record) = await settings.appLock(account: accountID) else { return }
        exhausted = record.codeAttemptsExhausted
        if exhausted { phraseAccepted = false; failure = nil; clearWait(); return }
        guard let seconds = record.codeRetryAfterSeconds, seconds > 0 else { if waitUntil == nil { phraseAccepted = false }; return }
        startWait(ContinuousClock.now.advanced(by: .seconds(Int(min(seconds, 86_400)))))
    }
    private func startWait(_ until: ContinuousClock.Instant) {
        waitUntil = until; waitTimer?.cancel()
        waitTimer = Task { [weak self] in
            try? await Task.sleep(until: until, clock: .continuous)
            guard !Task.isCancelled, let self else { return }
            self.waitUntil = nil; self.phraseAccepted = false
            // The "try again in" text describes the wait that has just ended; it goes with the countdown.
            if Self.isWaitFailure(self.failure) { self.failure = nil }
        }
    }
    private func clearWait() { waitTimer?.cancel(); waitTimer = nil; waitUntil = nil }
    private static func isWaitFailure(_ failure: AppFailure?) -> Bool {
        guard let failure else { return false }
        if case .accountCodeWait = failure { return true }
        return failure == .accountCode(.retryLater)
    }
}

/// The cover over the whole window while the privacy shield is up or the app lock is engaged: an opaque page with
/// the app name, the failure and a retry, or, when locked, the account-code field. Only the bound account's own display
/// name and initial are drawn (read from `account.list` for that account id, never logged); conversations, contacts,
/// previews, other people's avatars and unread counts stay hidden.
public struct AppShellCover: View {
    @Environment(\.locale) private var locale
    public let state: AppShellState
    public let onRetry: () -> Void
    public let lock: AppLockModel?
    public init(state: AppShellState, onRetry: @escaping () -> Void, lock: AppLockModel?) {
        self.state = state; self.onRetry = onRetry; self.lock = lock
    }
    public var body: some View {
        RFPage {
            if let lock, state.appLocked {
                AppLockForm(model: lock, accountID: lock.accountID)
            } else {
                VStack(alignment: .leading, spacing: KitMetrics.rowGap) {
                    Text(FeatureAppShellStrings.text("common.appName", locale: locale))
                        .rfFont(.page)
                        .accessibilityLabel(FeatureAppShellStrings.text("shell.locked.accessibility", locale: locale))
                    if let failure = state.failure {
                        RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale), retry: failure.canRetry ? onRetry : nil)
                    }
                }
                .padding(KitMetrics.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .privacySensitive()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-lock-cover")
    }
}

/// The lock page of a locked account (not the app lock): the same page as the app-lock cover, drawn in the shell. It has no
/// back control when it is the root of the shell; a page pushed from the account picker has one. With several accounts a
/// quiet action opens the picker.
public struct AccountLockPage: View {
    @Environment(\.locale) private var locale
    public let model: AppLockModel
    public let onBack: (() -> Void)?
    public let onSwitchAccount: (() -> Void)?
    public init(model: AppLockModel, onBack: (() -> Void)? = nil, onSwitchAccount: (() -> Void)? = nil) { self.model = model; self.onBack = onBack; self.onSwitchAccount = onSwitchAccount }
    public var body: some View {
        RFPage {
            VStack(spacing: 0) {
                if let onBack { KitPageHeader("", onBack: onBack, tag: "locked-page-header") }
                AppLockForm(model: model, accountID: model.accountID)
                if let onSwitchAccount, !model.confirmingRemoval, !model.exhausted {
                    KitButton(FeatureAppShellStrings.text("shell.accounts.switch", locale: locale), action: onSwitchAccount, kind: .text, tag: "shell-accounts")
                        .padding(.horizontal, KitMetrics.gutter).padding(.bottom, KitMetrics.gutter)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("locked-screen")
    }
}

/// The lock page of one account: its avatar initial and display name with "Locked" under it, the labelled account-code
/// field, one status line and the Unlock button. When the code checks are used up the field is gone and the page offers
/// recovery or removal of this account only. There is no skip.
struct AppLockForm: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: AppLockModel
    let accountID: String
    private var record: AccountRecord { model.account ?? AccountRecord(id: accountID, displayName: "", isLocked: true) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KitMetrics.rowGap) {
                if model.confirmingRemoval { removal } else if model.exhausted { exhausted } else { codeEntry }
            }
            .padding(KitMetrics.gutter)
            .frame(maxWidth: theme.column_max, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("app-lock-screen")
        // Every cover show reads the state again: the exhausted page and the wait come from the SDK.
        .task { await model.refresh() }
    }
    /// The account the page is about, before any field: initial, display name and "Locked".
    private var accountHeader: some View {
        KitAccountRow(name: record.title(locale: locale), initial: record.initial(locale: locale),
                      status: FeatureAppShellStrings.text("shell.appLock.locked", locale: locale), large: true, tag: "app-lock-account")
    }
    @ViewBuilder private var codeEntry: some View {
        accountHeader
        Text(FeatureAppShellStrings.text("shell.appLock.instructions", locale: locale)).foregroundStyle(theme.secondary)
        #if os(iOS)
        // Only the countdown ticks; the field is re-enabled by the model when the wait ends.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            RFSecureEntryForm(
                steps: [RFSecureEntryStep(fields: [RFSecureEntryField(id: "passphrase", label: FeatureAppShellStrings.text("shell.appLock.code", locale: locale), kind: .accountCode)],
                                          helper: FeatureAppShellStrings.text("shell.appLock.helper", locale: locale),
                                          actionLabel: FeatureAppShellStrings.text("shell.appLock.unlock", locale: locale))],
                enabled: !model.busy && !model.waiting, fieldsEnabled: !model.waiting, status: statusLine, onEdit: { model.fieldEdited() }
            ) { model.submit(SensitiveSubmission(values: $0, accountCode: .existing)) }
        }
        #endif
        if model.busy { ProgressView() }
    }
    /// The one status line under the field: the wait while one applies, otherwise the last refusal as a sentence.
    private var statusLine: String? {
        if let until = model.waitUntil {
            return FeatureAppShellStrings.format(model.phraseAccepted ? "shell.appLock.phraseAccepted" : "shell.appLock.wait", AppLockForm.countdown(until - ContinuousClock.now), locale: locale)
        }
        return model.failure?.message(locale: locale)
    }
    @ViewBuilder private var exhausted: some View {
        if model.codeNotice {
            HStack(alignment: .firstTextBaseline, spacing: KitMetrics.headerGap) {
                Text(FeatureAppShellStrings.text("shell.appLock.wrongCode", locale: locale)).foregroundStyle(theme.danger).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("app-lock-notice")
                KitButton(FeatureAppShellStrings.text("shell.appLock.dismiss", locale: locale), action: { model.dismissNotice() }, kind: .text, size: .compact, tag: "app-lock-notice-dismiss")
            }
            .padding(KitMetrics.headerGap)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_card))
        }
        accountHeader
        Text(FeatureAppShellStrings.text("shell.appLock.exhausted.title", locale: locale)).rfFont(.page, weight: .semibold).accessibilityAddTraits(.isHeader)
        Text(FeatureAppShellStrings.text("shell.appLock.exhausted.body", locale: locale)).foregroundStyle(theme.secondary)
        if model.busy { ProgressView() }
        KitButton(FeatureAppShellStrings.text("shell.appLock.restore", locale: locale), action: { model.restore() }, kind: .primary, enabled: !model.busy, tag: "app-lock-restore")
        KitButton(FeatureAppShellStrings.text("shell.appLock.remove", locale: locale), action: { model.requestRemoval() }, kind: .destructive, enabled: !model.busy, tag: "app-lock-remove")
    }
    /// The removal confirmation: names the account (display name and the short id line), states the consequence and needs the
    /// acknowledgement before the red Remove works.
    @ViewBuilder private var removal: some View {
        Text(FeatureAppShellStrings.text("shell.appLock.remove.title", locale: locale)).rfFont(.page, weight: .semibold).accessibilityAddTraits(.isHeader)
        KitAccountRow(name: record.title(locale: locale), initial: record.initial(locale: locale), shortID: record.shortID, tag: "app-lock-remove-account")
        Text(FeatureAppShellStrings.text("shell.appLock.remove.body", locale: locale)).foregroundStyle(theme.secondary)
        Toggle(FeatureAppShellStrings.text("shell.appLock.remove.ack", locale: locale), isOn: Binding(get: { model.removalAcknowledged }, set: { model.acknowledgeRemoval($0) }))
            .disabled(model.removing)
            .accessibilityIdentifier("app-lock-remove-ack")
        if model.removing { ProgressView() }
        if let failure = model.removalFailure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        RFHostConfirmationActions(summary: FeatureAppShellStrings.text("shell.appLock.remove.title", locale: locale), confirmLabel: FeatureAppShellStrings.text("shell.appLock.remove.confirm", locale: locale),
                                  enabled: model.removalAcknowledged && !model.removing, cancelEnabled: !model.removing, destructive: true, confirm: { model.confirmRemoval() }, cancel: { model.cancelRemoval() })
            .accessibilityIdentifier("app-lock-remove-actions")
    }
    /// The remaining wait as `m:ss`, rounded up so the last second still shows.
    static func countdown(_ remaining: Duration) -> String {
        let seconds = max(0, Int((remaining / .seconds(1)).rounded(.up)))
        return "\(seconds / 60):\(seconds % 60 < 10 ? "0" : "")\(seconds % 60)"
    }
}
