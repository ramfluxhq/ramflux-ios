// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import Observation
import AppData
import RFDesign

/// Unlocks an engaged app lock with the account code of the active account (`account.unlock`, the code-only
/// path). It shows no account name, offers no forget or dismiss, and never moves the navigation: success only
/// asks the shell to re-activate, so the same screen is back underneath.
@Observable @MainActor public final class AppLockModel {
    public private(set) var busy = false
    public private(set) var failure: AppFailure?
    /// The account-code wait the SDK named, on a monotonic clock; nil when no wait applies. The field is off until it ends.
    public private(set) var waitUntil: ContinuousClock.Instant?
    /// The account-code checks are used up: no field, only the recovery phrase restores the account.
    public private(set) var exhausted = false
    private var waitTimer: Task<Void, Never>?
    private let repository: any OnboardingRepository
    private let settings: any SettingsRepository
    private let account: String
    private let onUnlocked: @MainActor () -> Void
    private let onRestore: @MainActor () -> Void
    public init(repository: any OnboardingRepository, settings: any SettingsRepository, account: String,
                onUnlocked: @escaping @MainActor () -> Void, onRestore: @escaping @MainActor () -> Void) {
        self.repository = repository; self.settings = settings; self.account = account; self.onUnlocked = onUnlocked; self.onRestore = onRestore
    }
    public var waiting: Bool { waitUntil != nil }
    public func submit(_ input: SensitiveSubmission) {
        guard !busy, !waiting, !exhausted else { input.erase(); return }
        if let issue = input.accountCodeIssue { input.erase(); failure = .accountCode(issue); return }
        busy = true; failure = nil
        Task { [repository, settings, account] in
            let result = await repository.unlock(accountID: account, submission: input)
            self.busy = false
            switch result {
            case .success: self.onUnlocked()
            case .failure(let error):
                self.failure = error
                self.apply(error)
                // A throttle that names no wait is read from the SDK's app-lock state, which carries it.
                if error == .accountCode(.retryLater) { await self.readWait(settings) }
            }
        }
    }
    public func restore() { onRestore() }
    private func apply(_ error: AppFailure) {
        switch error {
        case .accountCodeWait(_, let until): exhausted = false; startWait(until)
        case .accountCode(.attemptsExhausted), .accountCode(.deviceUnlockUnavailable): exhausted = true; clearWait()
        default: clearWait()
        }
    }
    private func readWait(_ settings: any SettingsRepository) async {
        guard case .success(let record) = await settings.appLock(account: account) else { return }
        if record.codeAttemptsExhausted { exhausted = true; clearWait(); return }
        guard let milliseconds = record.codeRetryAfterMilliseconds else { return }
        startWait(ContinuousClock.now.advanced(by: .milliseconds(Int(min(milliseconds, 86_400_000)))))
    }
    private func startWait(_ until: ContinuousClock.Instant) {
        waitUntil = until; waitTimer?.cancel()
        waitTimer = Task { [weak self] in
            try? await Task.sleep(until: until, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.waitUntil = nil
        }
    }
    private func clearWait() { waitTimer?.cancel(); waitTimer = nil; waitUntil = nil }
}

/// The cover over the whole window while the privacy shield is up or the app lock is engaged: an opaque page with
/// the app name, the failure and a retry, or, when locked, the account-code field. Nothing of the account is drawn.
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
                AppLockForm(model: lock)
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

/// The account-code field of the app lock: the app name, the field and the failure text. No name, no skip.
struct AppLockForm: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: AppLockModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KitMetrics.rowGap) {
                Text(FeatureAppShellStrings.text("common.appName", locale: locale)).rfFont(.page)
                Text(FeatureAppShellStrings.text("shell.appLock.instructions", locale: locale)).foregroundStyle(theme.secondary)
                if !model.exhausted {
                    #if os(iOS)
                    RFSecureEntryForm(fields: [RFSecureEntryField(id: "passphrase", label: FeatureAppShellStrings.text("shell.appLock.code", locale: locale), kind: .accountCode)],
                                      enabled: !model.busy && !model.waiting) { model.submit(SensitiveSubmission(values: $0, accountCode: .existing)) }
                        .frame(minHeight: theme.composer_min * 4)
                    #endif
                    // Only the countdown ticks; the field above is re-enabled by the model when the wait ends.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let until = model.waitUntil {
                            Text(FeatureAppShellStrings.format("shell.appLock.wait", AppLockForm.countdown(until - ContinuousClock.now), locale: locale)).foregroundStyle(theme.secondary)
                        }
                    }
                }
                if model.busy { ProgressView() }
                if let failure = model.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                if model.exhausted {
                    KitButton(FeatureAppShellStrings.text("shell.appLock.restore", locale: locale), action: { model.restore() }, kind: .primary, enabled: !model.busy, tag: "app-lock-restore")
                }
            }
            .padding(KitMetrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("app-lock-screen")
    }
    /// The remaining wait as `m:ss`, rounded up so the last second still shows.
    static func countdown(_ remaining: Duration) -> String {
        let seconds = max(0, Int((remaining / .seconds(1)).rounded(.up)))
        return "\(seconds / 60):\(seconds % 60 < 10 ? "0" : "")\(seconds % 60)"
    }
}
