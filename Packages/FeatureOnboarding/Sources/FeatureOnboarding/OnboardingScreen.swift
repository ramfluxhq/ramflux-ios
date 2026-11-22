// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization
public struct OnboardingScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let securePresentation: AnyView?
    public let state: OnboardingState
    public let onAction: (OnboardingAction) -> Void
    public init(state: OnboardingState, onAction: @escaping (OnboardingAction) -> Void, securePresentation: AnyView? = nil) { self.state = state; self.onAction = onAction; self.securePresentation = securePresentation }
    public var body: some View {
        Group {
            if state.stage == .create { createAccount } else { catalog }
        }
        .privacySensitive()
        .accessibilityIdentifier(state.stage.board)
    }
    private var catalog: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureOnboardingStrings.text("common.appName", locale: locale)).rfFont(.caption)
            Text(state.stage.title(locale: locale)).rfFont(.page).accessibilityAddTraits(.isHeader)
            content
            if state.busy { ProgressView(FeatureOnboardingStrings.text("onboarding.busy", locale: locale)) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            Button(FeatureOnboardingStrings.text("onboarding.cancel", locale: locale)) { onAction(.cancel) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
    }
    private var createAccount: some View {
        let ready = !state.busy && !state.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedNode?.canCreateAccount == true
        return VStack(spacing: 0) {
            KitPageHeader(copy("onboarding.n01.header"), onBack: { onAction(.cancel) }, tag: "n01-header")
            ScrollView {
                VStack(alignment: .leading, spacing: theme.gap) {
                    KitTextField(
                        value: Binding(get: { state.name }, set: { onAction(.nameChanged($0)) }),
                        label: copy("onboarding.n01.name"),
                        note: copy("onboarding.n01.name.note"),
                        enabled: !state.busy,
                        tag: "n01-name"
                    )
                    Text(copy("onboarding.n01.node"))
                        .rfFont(.size(theme.size_secondary), weight: .semibold)
                        .foregroundStyle(theme.secondary)
                    nodeCard
                    KitTipBar(copy("onboarding.n01.phrase"), icon: "pencil-line", tag: "n01-phrase")
                    if state.busy { ProgressView(FeatureOnboardingStrings.text("onboarding.busy", locale: locale)) }
                    if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }
                .padding(.horizontal, theme.gap)
                .padding(.top, 16)
                .padding(.bottom, theme.gap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            KitButton(copy("onboarding.n01.create"), action: { onAction(.beginCreation) }, enabled: ready, tag: "n01-create")
                .padding(.horizontal, theme.gap)
                .padding(.bottom, 8)
        }
        .rfFont(.body)
        .foregroundStyle(theme.text)
        .tint(theme.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.nav.ignoresSafeArea())
    }
    private var selectedNode: NodeRecord? { state.nodes.first { $0.id == state.selectedNodeID } }
    @ViewBuilder private var nodeCard: some View {
        if let node = selectedNode, node.canCreateAccount {
            HStack(spacing: KitMetrics.rowGap) {
                KitIconTile(icon: "server")
                VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                    Text(node.isDefault ? copy("onboarding.n01.node.official") : node.origin)
                        .rfFont(.size(theme.size_mobile_body))
                        .foregroundStyle(theme.text)
                    Text(copy("onboarding.n01.node.selected"))
                        .rfFont(.size(theme.size_secondary))
                        .foregroundStyle(theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KitIcon(name: "chevron-right", size: KitMetrics.chevron, tint: theme.control)
                    .opacity(KitMetrics.disabledAlpha)
            }
            .padding(.horizontal, KitMetrics.gutter)
            .frame(maxWidth: .infinity)
            .frame(height: KitMetrics.row)
            .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
            .accessibilityIdentifier("n01-node")
        } else {
            nodeChoices
        }
    }
    private func copy(_ key: String) -> String { FeatureOnboardingStrings.text(key, locale: locale) }
    @ViewBuilder private var content: some View {
        switch state.stage {
        case .welcome, .launch, .start:
            Text(FeatureOnboardingStrings.text("onboarding.welcome.primaryDevice", locale: locale))
            action(FeatureOnboardingStrings.text("onboarding.welcome.unlockSaved", locale: locale), .unlockExisting); action(FeatureOnboardingStrings.text("onboarding.create.title", locale: locale), .create); action(FeatureOnboardingStrings.text("onboarding.welcome.recover", locale: locale), .recover)
            action(FeatureOnboardingStrings.text("onboarding.link.title", locale: locale), .link); action(FeatureOnboardingStrings.text("onboarding.node.choose", locale: locale), .customNode)
        case .create:
            EmptyView()
        case .address, .connection, .defaultNode:
            TextField(FeatureOnboardingStrings.text("onboarding.address.field", locale: locale), text: Binding(get: { state.address }, set: { onAction(.addressChanged($0)) }))
                .textFieldStyle(.roundedBorder).rfAddressInput()
            action(FeatureOnboardingStrings.text("onboarding.address.check", locale: locale), .checkAddress)
        case .normalizedAddress, .checkingAddress:
            if let normalized = state.normalized {
                LabeledContent(FeatureOnboardingStrings.text("onboarding.address.entered", locale: locale), value: normalized.entered)
                LabeledContent(FeatureOnboardingStrings.text("onboarding.address.normalized", locale: locale), value: normalized.origin).textSelection(.enabled)
                if normalized.changed { Text(FeatureOnboardingStrings.text("onboarding.address.originOnly", locale: locale)) }
                action(FeatureOnboardingStrings.text("onboarding.address.connect", locale: locale), .inspectOrigin)
            }
        case .identity:
            if let candidate = state.candidate {
                Text(untrusted: candidate.origin).textSelection(.enabled)
                if let fingerprint = state.visibleNodeFingerprint {
                    Text(FeatureOnboardingStrings.text("node.fingerprintInstructions", locale: locale))
                    KitIdentifierText(fingerprint, tag: "onboarding-node-fingerprint").textSelection(.enabled)
                    RFHostConfirmationActions(summary: FeatureOnboardingStrings.sentence("node.confirmFingerprint.summary", [.untrusted(candidate.origin), .identifier(fingerprint)], locale: locale), enabled: !state.busy, cancelEnabled: !state.busy, confirm: { onAction(.saveNode) }, cancel: { onAction(.expectedNodeKeyChanged("")) }).id(fingerprint)
                    action(FeatureOnboardingStrings.text("node.editOperatorKey", locale: locale), .expectedNodeKeyChanged(""))
                } else {
                    Text(FeatureOnboardingStrings.text("node.operatorInstructions", locale: locale))
                    TextField(FeatureOnboardingStrings.text("node.operatorKey", locale: locale), text: Binding(get: { state.expectedNodeKey }, set: { onAction(.expectedNodeKeyChanged($0)) }))
                        .textFieldStyle(.roundedBorder).rfAddressInput()
                    action(FeatureOnboardingStrings.text("node.reviewFingerprint", locale: locale), .reviewNodeKey)
                }
            }
        case .saved:
            Text(FeatureOnboardingStrings.text("onboarding.node.saved.message", locale: locale))
            action(FeatureOnboardingStrings.text("onboarding.node.useAsDefault", locale: locale), .setDefault); action(FeatureOnboardingStrings.text("onboarding.create.title", locale: locale), .create)
        case .savePhrase:
            Text(FeatureOnboardingStrings.text("onboarding.phrase.keepPrivate", locale: locale))
            if state.displayID != nil {
                #if os(iOS)
                securePresentation
                #else
                Text(FeatureOnboardingStrings.text("onboarding.phrase.hostRequired", locale: locale))
                #endif
                action(FeatureOnboardingStrings.text("onboarding.phrase.hideAndContinue", locale: locale), .hidePhrase)
            } else { action(FeatureOnboardingStrings.text("onboarding.phrase.showOnce", locale: locale), .showPhrase) }
        case .confirmPhrase:
            Text(FeatureOnboardingStrings.text("onboarding.confirmPhrase.instructions", locale: locale))
            ForEach(state.positions, id: \.self) { Text(FeatureOnboardingStrings.format("recovery.word.position", $0.formatted(.number.locale(locale)), locale: locale)) }
            Text(FeatureOnboardingStrings.text("onboarding.phrase.erased", locale: locale))
            action(FeatureOnboardingStrings.text("onboarding.stage.localUnlock", locale: locale), .continueUnlock)
        case .localUnlock:
            if state.unlockingSavedAccount {
                TextField(FeatureOnboardingStrings.text("onboarding.localUnlock.accountID", locale: locale), text: Binding(get: { state.recoveryAccount }, set: { onAction(.recoveryAccountChanged($0)) })).textFieldStyle(.roundedBorder)
            } else { Text(FeatureOnboardingStrings.text("onboarding.localUnlock.instructions", locale: locale)) }
            #if os(iOS)
            SecureOnboardingForm(fields: unlockFields, accountCode: state.unlockingSavedAccount ? .existing : .new, enabled: !state.busy && !state.confirmationConsumed) { onAction(.submit($0)) }
                .frame(minHeight: theme.composer_min * (state.unlockingSavedAccount ? 3 : 7))
            Text(FeatureOnboardingStrings.text("onboarding.accountCode.local", locale: locale)).foregroundStyle(theme.secondary)
            if state.failure == .accountCode(.attemptsExhausted) || state.failure == .accountCode(.deviceUnlockUnavailable) {
                action(FeatureOnboardingStrings.text("onboarding.stage.recover", locale: locale), .recover)
            }
            #else
            Text(FeatureOnboardingStrings.text("common.secureInput.hostRequired", locale: locale))
            #endif
        case .recover:
            if let metadata = state.metadata, let anchor = metadata.anchor {
                KitIdentifierText(anchor, tag: "onboarding-recover-fingerprint").textSelection(.enabled)
                Text(FeatureOnboardingStrings.text("onboarding.recover.warning", locale: locale))
                Toggle(FeatureOnboardingStrings.text("onboarding.recover.fingerprintChecked", locale: locale), isOn: Binding(get: { state.anchorChecked }, set: { onAction(.checkAnchor($0)) }))
                #if os(iOS)
                SecureOnboardingForm(fields: [RFSecureEntryField(id: "phrase", label: FeatureOnboardingStrings.text("onboarding.recover.phrase", locale: locale)), RFSecureEntryField(id: "passphrase", label: FeatureOnboardingStrings.text("onboarding.accountCode.existing", locale: locale), kind: .accountCode)], accountCode: .existing, enabled: state.anchorChecked && !state.busy && !state.confirmationConsumed) { onAction(.submit($0)) }.frame(minHeight: theme.composer_min * 4)
                #endif
            } else {
                TextField(FeatureOnboardingStrings.text("onboarding.recover.accountID", locale: locale), text: Binding(get: { state.recoveryAccount }, set: { onAction(.recoveryAccountChanged($0)) })).textFieldStyle(.roundedBorder)
                Text(FeatureOnboardingStrings.text("onboarding.recover.scope", locale: locale))
                action(FeatureOnboardingStrings.text("onboarding.recover.readFingerprint", locale: locale), .beginRecovery)
            }
        case .complete:
            if let account = state.completedAccount { Text(untrusted: account.displayName); KitIdentifierText(account.id, color: theme.secondary); Text(account.networking == .live ? FeatureOnboardingStrings.text("onboarding.complete.connected", locale: locale) : FeatureOnboardingStrings.text("onboarding.complete.notConnected", locale: locale)) }
            action(FeatureOnboardingStrings.text("onboarding.complete.continue", locale: locale), .done)
        case .link:
            Text(FeatureOnboardingStrings.text("onboarding.link.unavailable", locale: locale))
        case .verifying, .restoring, .saving: ProgressView(state.stage.title(locale: locale))
        case .connectionFailed, .verificationFailed, .saveFailed, .configuration, .offline:
            Text(FeatureOnboardingStrings.text("onboarding.connection.preserved", locale: locale))
            action(FeatureOnboardingStrings.text("onboarding.connection.editAddress", locale: locale), .customNode)
        }
    }
    #if os(iOS)
    private var unlockFields: [RFSecureEntryField] {
        if state.unlockingSavedAccount { return [RFSecureEntryField(id: "passphrase", label: FeatureOnboardingStrings.text("onboarding.accountCode.existing", locale: locale), kind: .accountCode)] }
        let words = state.positions.enumerated().map { RFSecureEntryField(id: "word\($0.offset + 1)", label: FeatureOnboardingStrings.format("recovery.word.position", $0.element.formatted(.number.locale(locale)), locale: locale)) }
        return words + [RFSecureEntryField(id: "passphrase", label: FeatureOnboardingStrings.text("onboarding.accountCode.new", locale: locale), kind: .accountCode),
                        RFSecureEntryField(id: "passphraseRepeat", label: FeatureOnboardingStrings.text("onboarding.accountCode.repeat", locale: locale), kind: .accountCode)]
    }
    #endif
    @ViewBuilder private var nodeChoices: some View {
        if state.nodes.isEmpty { Text(FeatureOnboardingStrings.text("onboarding.node.noneConfirmed", locale: locale)) }
        ForEach(state.nodes) { node in
            Button { onAction(.nodeSelected(node.id)) } label: { Label(RFUntrustedText.clean(node.origin), systemImage: state.selectedNodeID == node.id ? "checkmark.circle.fill" : "circle") }
                .disabled(!node.canCreateAccount || state.busy)
        }
        action(FeatureOnboardingStrings.text("onboarding.node.other", locale: locale), .customNode)
    }
    private func action(_ title: String, _ action: OnboardingAction) -> some View {
        KitButton(title, action: { onAction(action) }, kind: .primary, enabled: !state.busy, tag: title)
    }
}
