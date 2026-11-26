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
    private let repository: any OnboardingRepository
    private let account: String
    private let onUnlocked: @MainActor () -> Void
    public init(repository: any OnboardingRepository, account: String, onUnlocked: @escaping @MainActor () -> Void) {
        self.repository = repository; self.account = account; self.onUnlocked = onUnlocked
    }
    public func submit(_ input: SensitiveSubmission) {
        guard !busy else { input.erase(); return }
        if let issue = input.accountCodeIssue { input.erase(); failure = .accountCode(issue); return }
        busy = true; failure = nil
        Task { [repository, account] in
            let result = await repository.unlock(accountID: account, submission: input)
            self.busy = false
            switch result {
            case .success: self.onUnlocked()
            case .failure(let error): self.failure = error
            }
        }
    }
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
                #if os(iOS)
                RFSecureEntryForm(fields: [RFSecureEntryField(id: "passphrase", label: FeatureAppShellStrings.text("shell.appLock.code", locale: locale), kind: .accountCode)],
                                  enabled: !model.busy) { model.submit(SensitiveSubmission(values: $0, accountCode: .existing)) }
                    .frame(minHeight: theme.composer_min * 4)
                #endif
                if model.busy { ProgressView() }
                if let failure = model.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            }
            .padding(KitMetrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("app-lock-screen")
    }
}
