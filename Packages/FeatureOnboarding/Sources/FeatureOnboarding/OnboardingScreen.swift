// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct OnboardingScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let securePresentation: AnyView?
    public let state: OnboardingState
    public let onAction: (OnboardingAction) -> Void
    public init(state: OnboardingState, onAction: @escaping (OnboardingAction) -> Void, securePresentation: AnyView? = nil) { self.state = state; self.onAction = onAction; self.securePresentation = securePresentation }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureOnboardingStrings.text("copy.28f2d4300544", locale: locale)).font(theme.captionFont)
            Text(state.stage.title(locale: locale)).font(theme.pageFont).accessibilityAddTraits(.isHeader)
            content
            if state.busy { ProgressView(FeatureOnboardingStrings.text("copy.650cfe3a448f", locale: locale)) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            Button(FeatureOnboardingStrings.text("copy.c17bac18b5a6", locale: locale)) { onAction(.cancel) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
            .privacySensitive().accessibilityIdentifier(state.stage.board)
    }
    @ViewBuilder private var content: some View {
        switch state.stage {
        case .welcome, .launch, .start:
            Text(FeatureOnboardingStrings.text("copy.57fb564a5f32", locale: locale))
            action(FeatureOnboardingStrings.text("copy.8b8843897868", locale: locale), .unlockExisting); action(FeatureOnboardingStrings.text("copy.86033f75a4c0", locale: locale), .create); action(FeatureOnboardingStrings.text("copy.cb4bd1634dfb", locale: locale), .recover)
            action(FeatureOnboardingStrings.text("copy.5dfe7b2bb38d", locale: locale), .link); action(FeatureOnboardingStrings.text("copy.8e9aff1d599c", locale: locale), .customNode)
        case .create:
            TextField(FeatureOnboardingStrings.text("copy.2b7f6a84de91", locale: locale), text: Binding(get: { state.name }, set: { onAction(.nameChanged($0)) })).textFieldStyle(.roundedBorder)
            Text(FeatureOnboardingStrings.text("copy.aa242a674642", locale: locale))
            nodeChoices
            action(FeatureOnboardingStrings.text("copy.458db8c2c8c1", locale: locale), .beginCreation)
        case .address, .connection, .defaultNode:
            TextField(FeatureOnboardingStrings.text("copy.c9aadf9cd263", locale: locale), text: Binding(get: { state.address }, set: { onAction(.addressChanged($0)) }))
                .textFieldStyle(.roundedBorder).rfAddressInput()
            action(FeatureOnboardingStrings.text("copy.2b0ebbd9991d", locale: locale), .checkAddress)
        case .normalizedAddress, .checkingAddress:
            if let normalized = state.normalized {
                LabeledContent(FeatureOnboardingStrings.text("copy.db7dc45de14f", locale: locale), value: normalized.entered)
                LabeledContent(FeatureOnboardingStrings.text("copy.0caae4e9b4c4", locale: locale), value: normalized.origin).textSelection(.enabled)
                if normalized.changed { Text(FeatureOnboardingStrings.text("copy.e2d11145163b", locale: locale)) }
                action(FeatureOnboardingStrings.text("copy.1710d243883c", locale: locale), .inspectOrigin)
            }
        case .identity:
            if let candidate = state.candidate {
                Text(candidate.origin).textSelection(.enabled)
                if let fingerprint = state.visibleNodeFingerprint {
                    Text(FeatureOnboardingStrings.text("node.fingerprintInstructions", locale: locale))
                    Text(fingerprint).font(theme.captionFont).textSelection(.enabled)
                    action(FeatureOnboardingStrings.text("node.confirmFingerprint", locale: locale), .saveNode)
                    action(FeatureOnboardingStrings.text("node.editOperatorKey", locale: locale), .expectedNodeKeyChanged(""))
                } else {
                    Text(FeatureOnboardingStrings.text("node.operatorInstructions", locale: locale))
                    TextField(FeatureOnboardingStrings.text("node.operatorKey", locale: locale), text: Binding(get: { state.expectedNodeKey }, set: { onAction(.expectedNodeKeyChanged($0)) }))
                        .textFieldStyle(.roundedBorder).rfAddressInput()
                    action(FeatureOnboardingStrings.text("node.reviewFingerprint", locale: locale), .reviewNodeKey)
                }
            }
        case .saved:
            Text(FeatureOnboardingStrings.text("copy.2ba256d7a297", locale: locale))
            action(FeatureOnboardingStrings.text("copy.7ae2c8b71f1a", locale: locale), .setDefault); action(FeatureOnboardingStrings.text("copy.86033f75a4c0", locale: locale), .create)
        case .savePhrase:
            Text(FeatureOnboardingStrings.text("copy.1b01d88bd34d", locale: locale))
            if state.displayID != nil {
                #if os(iOS)
                securePresentation
                #else
                Text(FeatureOnboardingStrings.text("copy.deb375ac99ed", locale: locale))
                #endif
                action(FeatureOnboardingStrings.text("copy.5ccd5b11457e", locale: locale), .hidePhrase)
            } else { action(FeatureOnboardingStrings.text("copy.f23cb9253e3e", locale: locale), .showPhrase) }
        case .confirmPhrase:
            Text(FeatureOnboardingStrings.text("copy.985536fc1f55", locale: locale))
            ForEach(state.positions, id: \.self) { Text(FeatureOnboardingStrings.format("recovery.word.position", $0.formatted(.number.locale(locale)), locale: locale)) }
            Text(FeatureOnboardingStrings.text("copy.e0e8eed587f2", locale: locale))
            action(FeatureOnboardingStrings.text("copy.2fcb31c28a31", locale: locale), .continueUnlock)
        case .localUnlock:
            if state.unlockingSavedAccount {
                TextField(FeatureOnboardingStrings.text("copy.68295d2e45cf", locale: locale), text: Binding(get: { state.recoveryAccount }, set: { onAction(.recoveryAccountChanged($0)) })).textFieldStyle(.roundedBorder)
            } else { Text(FeatureOnboardingStrings.text("copy.0896fec51d88", locale: locale)) }
            #if os(iOS)
            SecureOnboardingForm(labels: (state.unlockingSavedAccount ? [] : state.positions.enumerated().map { ("word\($0.offset + 1)", FeatureOnboardingStrings.format("recovery.word.position", $0.element.formatted(.number.locale(locale)), locale: locale)) }) + [("passphrase", FeatureOnboardingStrings.text("copy.5cafb0b934b6", locale: locale))], enabled: !state.busy && !state.confirmationConsumed) { onAction(.submit($0)) }
                .frame(minHeight: theme.composer_min * (state.unlockingSavedAccount ? 3 : 6))
            #else
            Text(FeatureOnboardingStrings.text("copy.a1bcb108941e", locale: locale))
            #endif
        case .recover:
            if let metadata = state.metadata, let anchor = metadata.anchor {
                Text(anchor).textSelection(.enabled)
                Text(FeatureOnboardingStrings.text("copy.103d79748699", locale: locale))
                Toggle(FeatureOnboardingStrings.text("copy.cdfc37ac7863", locale: locale), isOn: Binding(get: { state.anchorChecked }, set: { onAction(.checkAnchor($0)) }))
                #if os(iOS)
                SecureOnboardingForm(labels: [("phrase", FeatureOnboardingStrings.text("copy.41edd3f47328", locale: locale)), ("passphrase", FeatureOnboardingStrings.text("copy.04eef37abc74", locale: locale))], enabled: state.anchorChecked && !state.busy && !state.confirmationConsumed) { onAction(.submit($0)) }.frame(minHeight: theme.composer_min * 4)
                #endif
            } else {
                TextField(FeatureOnboardingStrings.text("copy.4a248ed11c79", locale: locale), text: Binding(get: { state.recoveryAccount }, set: { onAction(.recoveryAccountChanged($0)) })).textFieldStyle(.roundedBorder)
                Text(FeatureOnboardingStrings.text("copy.10f868719bac", locale: locale))
                action(FeatureOnboardingStrings.text("copy.63466cf4d5b0", locale: locale), .beginRecovery)
            }
        case .complete:
            if let account = state.completedAccount { Text(account.displayName); Text(account.id).font(theme.captionFont); Text(account.networking == .live ? FeatureOnboardingStrings.text("copy.22965568d22a", locale: locale) : FeatureOnboardingStrings.text("copy.0b547581bb84", locale: locale)) }
            action(FeatureOnboardingStrings.text("copy.31fbef162594", locale: locale), .done)
        case .link:
            Text(FeatureOnboardingStrings.text("copy.a93020e0cfed", locale: locale))
        case .verifying, .restoring, .saving: ProgressView(state.stage.title(locale: locale))
        case .connectionFailed, .verificationFailed, .saveFailed, .configuration, .offline:
            Text(FeatureOnboardingStrings.text("copy.07af72e6141b", locale: locale))
            action(FeatureOnboardingStrings.text("copy.1b2db98c4d8d", locale: locale), .customNode)
        }
    }
    @ViewBuilder private var nodeChoices: some View {
        if state.nodes.isEmpty { Text(FeatureOnboardingStrings.text("copy.cf339d96c54f", locale: locale)) }
        ForEach(state.nodes) { node in
            Button { onAction(.nodeSelected(node.id)) } label: { Label(node.origin, systemImage: state.selectedNodeID == node.id ? "checkmark.circle.fill" : "circle") }
                .disabled(!node.canCreateAccount || state.busy)
        }
        action(FeatureOnboardingStrings.text("copy.2afe8ba12d97", locale: locale), .customNode)
    }
    private func action(_ title: String, _ action: OnboardingAction) -> some View {
        RFActionButton(id: title, label: title, kind: .primary, disabled: state.busy, theme: theme) { onAction(action) }
    }
}
