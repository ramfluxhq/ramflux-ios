// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData
public enum OnboardingStage: String, CaseIterable, Identifiable, Sendable {
    case launch, start, connection, address, checkingAddress, verifying, connectionFailed, restoring, offline
    case defaultNode, identity, verificationFailed, saveFailed, configuration, normalizedAddress, saving, saved
    case welcome, create, savePhrase, confirmPhrase, localUnlock, complete, link, recover
    public var id: Self { self }
    public var board: String { "MOB-S" + String(format: "%02d", (Self.allCases.firstIndex(of: self) ?? 0) + 1) }
    public var title: String { title(locale: .current) }
    public func title(locale: Locale) -> String {
        switch self {
        case .launch: FeatureOnboardingStrings.text("common.appName", locale: locale); case .start, .welcome: FeatureOnboardingStrings.text("onboarding.welcome.title", locale: locale)
        case .connection, .defaultNode: FeatureOnboardingStrings.text("onboarding.node.choose", locale: locale); case .address: FeatureOnboardingStrings.text("onboarding.stage.customNode", locale: locale)
        case .checkingAddress, .normalizedAddress: FeatureOnboardingStrings.text("onboarding.stage.checkingAddress", locale: locale); case .verifying: FeatureOnboardingStrings.text("onboarding.stage.verifying", locale: locale)
        case .connectionFailed: FeatureOnboardingStrings.text("common.connection.failed", locale: locale); case .restoring: FeatureOnboardingStrings.text("onboarding.stage.restoring", locale: locale); case .offline: FeatureOnboardingStrings.text("onboarding.stage.offline", locale: locale)
        case .identity: FeatureOnboardingStrings.text("onboarding.stage.identity", locale: locale); case .verificationFailed: FeatureOnboardingStrings.text("onboarding.stage.verificationFailed", locale: locale); case .saveFailed: FeatureOnboardingStrings.text("onboarding.stage.saveFailed", locale: locale)
        case .configuration: FeatureOnboardingStrings.text("onboarding.stage.configuration", locale: locale); case .saving: FeatureOnboardingStrings.text("onboarding.stage.saving", locale: locale); case .saved: FeatureOnboardingStrings.text("onboarding.stage.saved", locale: locale)
        case .create: FeatureOnboardingStrings.text("onboarding.create.title", locale: locale); case .savePhrase: FeatureOnboardingStrings.text("onboarding.stage.savePhrase", locale: locale); case .confirmPhrase: FeatureOnboardingStrings.text("onboarding.stage.confirmPhrase", locale: locale)
        case .localUnlock: FeatureOnboardingStrings.text("onboarding.stage.localUnlock", locale: locale); case .complete: FeatureOnboardingStrings.text("onboarding.stage.complete", locale: locale); case .link: FeatureOnboardingStrings.text("onboarding.link.title", locale: locale); case .recover: FeatureOnboardingStrings.text("onboarding.stage.recover", locale: locale)
        }
    }
}
