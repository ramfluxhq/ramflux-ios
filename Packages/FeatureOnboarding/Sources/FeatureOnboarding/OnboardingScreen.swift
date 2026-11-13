// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct OnboardingScreen: View {
    @Environment(\.colorScheme) private var scheme
    public let state: OnboardingState
    public let onAction: (OnboardingAction) -> Void
    public init(state: OnboardingState, onAction: @escaping (OnboardingAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: RFTheme.adaptive(scheme).gap) {
            Text("Ramflux").font(.caption)
            Text(state.stage.title).font(RFTheme.adaptive(scheme).pageFont).accessibilityAddTraits(.isHeader)
            content
            if state.busy { ProgressView("Please wait") }
            if let failure = state.failure { RFFailureView(title: failure.title, message: failure.message) }
            Button("Cancel setup") { onAction(.cancel) }
        }.padding().frame(maxWidth: RFTheme.adaptive(scheme).column_max, alignment: .leading).frame(maxWidth: .infinity) } }
            .privacySensitive().accessibilityIdentifier(state.stage.board)
    }
    @ViewBuilder private var content: some View {
        switch state.stage {
        case .welcome, .launch, .start:
            Text("This phone can be your primary device.")
            action("Unlock saved account", .unlockExisting); action("Create an account", .create); action("Recover an account", .recover)
            action("Link an existing account", .link); action("Choose a node", .customNode)
        case .create:
            TextField("Display name", text: Binding(get: { state.name }, set: { onAction(.nameChanged($0)) })).textFieldStyle(.roundedBorder)
            Text("Account keys are generated on this phone.")
            nodeChoices
            action("Prepare recovery phrase", .beginCreation)
        case .address, .connection, .defaultNode:
            TextField("Node address", text: Binding(get: { state.address }, set: { onAction(.addressChanged($0)) }))
                .textFieldStyle(.roundedBorder).rfAddressInput()
            action("Check address", .checkAddress)
        case .normalizedAddress, .checkingAddress:
            if let normalized = state.normalized {
                LabeledContent("Entered", value: normalized.entered)
                LabeledContent("Connect to", value: normalized.origin).textSelection(.enabled)
                if normalized.changed { Text("Only the HTTPS origin will be used. Paths and invitations are not sent.") }
                action("Connect to this origin", .inspectOrigin)
            }
        case .identity:
            if let candidate = state.candidate {
                Text(candidate.origin).textSelection(.enabled)
                Text(candidate.fingerprint ?? "Fingerprint unavailable").font(.caption).textSelection(.enabled)
                Text("Compare the node fingerprint through another trusted channel before saving.")
                action("Trust and save this node", .saveNode)
            }
        case .saved:
            Text("The account service saved this node's identity.")
            action("Use as default node", .setDefault); action("Create an account", .create)
        case .savePhrase:
            Text("Keep these words private and save them offline. They cannot be shown again in this ceremony.")
            if let display = state.display {
                #if os(iOS)
                RecoveryPhraseView(display: display)
                #else
                Text("Open this secure phrase display in the iOS app.")
                #endif
                action("I saved it. Hide and continue", .hidePhrase)
            } else { action("Show recovery phrase once", .showPhrase) }
        case .confirmPhrase:
            Text("Next, enter the words at these positions in order:")
            ForEach(state.positions, id: \.self) { Text("Word \($0)") }
            Text("The full phrase has been hidden and its display storage erased.")
            action("Set up local unlock", .continueUnlock)
        case .localUnlock:
            if state.unlockingSavedAccount {
                TextField("Local account ID", text: Binding(get: { state.recoveryAccount }, set: { onAction(.recoveryAccountChanged($0)) })).textFieldStyle(.roundedBorder)
            } else { Text("Choose a local passphrase, then enter the three requested recovery words. Confirmation is a single attempt.") }
            #if os(iOS)
            SecureOnboardingForm(labels: (state.unlockingSavedAccount ? [] : state.positions.enumerated().map { ("word\($0.offset + 1)", "Word \($0.element)") }) + [("passphrase", "Local passphrase")], enabled: !state.busy && !state.confirmationConsumed) { onAction(.submit($0)) }
                .frame(minHeight: state.unlockingSavedAccount ? 120 : 260)
            #else
            Text("Complete secure input in the iOS app.")
            #endif
        case .recover:
            if let metadata = state.metadata, let anchor = metadata.anchor {
                Text(anchor).textSelection(.enabled)
                Text("Confirm this account fingerprint through a trusted channel. Recovery revokes all other devices. Enter your phrase only for recovery you started yourself.")
                Toggle("I checked this account fingerprint", isOn: Binding(get: { state.anchorChecked }, set: { onAction(.checkAnchor($0)) }))
                #if os(iOS)
                SecureOnboardingForm(labels: [("phrase", "Recovery phrase"), ("passphrase", "Existing local passphrase")], enabled: state.anchorChecked && !state.busy && !state.confirmationConsumed) { onAction(.submit($0)) }.frame(minHeight: 180)
                #endif
            } else {
                TextField("Existing local account ID", text: Binding(get: { state.recoveryAccount }, set: { onAction(.recoveryAccountChanged($0)) })).textFieldStyle(.roundedBorder)
                Text("Recovery resumes an account already stored on this phone.")
                action("Read account fingerprint", .beginRecovery)
            }
        case .complete:
            if let account = state.completedAccount { Text(account.displayName); Text(account.id).font(.caption); Text(account.networking == .live ? "Connected" : "Local account is ready. Network connection has not been confirmed.") }
            action("Continue", .done)
        case .link:
            Text("Linking needs a registered phone pairing coordinator. This build does not create a QR code or pairing code.")
        case .verifying, .restoring, .saving: ProgressView(state.stage.title)
        case .connectionFailed, .verificationFailed, .saveFailed, .configuration, .offline:
            Text("Your last confirmed connection is preserved.")
            action("Edit node address", .customNode)
        }
    }
    @ViewBuilder private var nodeChoices: some View {
        if state.nodes.isEmpty { Text("No saved node is available. You can prepare local keys and configure a node separately.") }
        ForEach(state.nodes) { node in
            Button { onAction(.nodeSelected(node.id)) } label: { Label(node.origin, systemImage: state.selectedNodeID == node.id ? "checkmark.circle.fill" : "circle") }
                .disabled(!node.enabled || state.busy)
        }
        action("Other node", .customNode)
    }
    private func action(_ title: String, _ action: OnboardingAction) -> some View {
        RFActionButton(id: title, label: title, kind: .primary, disabled: state.busy, theme: RFTheme.adaptive(scheme)) { onAction(action) }
    }
}
