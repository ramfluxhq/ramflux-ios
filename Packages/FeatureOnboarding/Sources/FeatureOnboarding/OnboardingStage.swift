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
        case .launch: FeatureOnboardingStrings.text("copy.28f2d4300544", locale: locale); case .start, .welcome: FeatureOnboardingStrings.text("copy.b9d9bb247022", locale: locale)
        case .connection, .defaultNode: FeatureOnboardingStrings.text("copy.8e9aff1d599c", locale: locale); case .address: FeatureOnboardingStrings.text("copy.dac665b06b4d", locale: locale)
        case .checkingAddress, .normalizedAddress: FeatureOnboardingStrings.text("copy.985b82be2098", locale: locale); case .verifying: FeatureOnboardingStrings.text("copy.7cee9719c6e5", locale: locale)
        case .connectionFailed: FeatureOnboardingStrings.text("copy.e40966162b11", locale: locale); case .restoring: FeatureOnboardingStrings.text("copy.e1b57debc57c", locale: locale); case .offline: FeatureOnboardingStrings.text("copy.4d5c943931a4", locale: locale)
        case .identity: FeatureOnboardingStrings.text("copy.5f13d96a0063", locale: locale); case .verificationFailed: FeatureOnboardingStrings.text("copy.b47895eadb24", locale: locale); case .saveFailed: FeatureOnboardingStrings.text("copy.0234cae2e221", locale: locale)
        case .configuration: FeatureOnboardingStrings.text("copy.83c95649b037", locale: locale); case .saving: FeatureOnboardingStrings.text("copy.59d9af4c5214", locale: locale); case .saved: FeatureOnboardingStrings.text("copy.e77b763e169d", locale: locale)
        case .create: FeatureOnboardingStrings.text("copy.86033f75a4c0", locale: locale); case .savePhrase: FeatureOnboardingStrings.text("copy.e0d94a676bb9", locale: locale); case .confirmPhrase: FeatureOnboardingStrings.text("copy.a954d93bce56", locale: locale)
        case .localUnlock: FeatureOnboardingStrings.text("copy.2fcb31c28a31", locale: locale); case .complete: FeatureOnboardingStrings.text("copy.04d3e7f2e48b", locale: locale); case .link: FeatureOnboardingStrings.text("copy.5dfe7b2bb38d", locale: locale); case .recover: FeatureOnboardingStrings.text("copy.51ac0753998e", locale: locale)
        }
    }
}
