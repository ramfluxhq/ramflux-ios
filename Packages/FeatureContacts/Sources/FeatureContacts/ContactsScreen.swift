// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization
public struct ContactsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: ContactsState
    public let onAction: (ContactsAction) -> Void
    public init(state: ContactsState, onAction: @escaping (ContactsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(title, onBack: { dismiss() }, actions: [KitHeaderAction(icon: "refresh-cw", label: FeatureContactsStrings.text("common.action.refresh", locale: locale), action: { onAction(.refresh) })], tag: "contacts-header")
            if state.pendingMutation != nil { Button(FeatureContactsStrings.text("contacts.reconcile", locale: locale)) { onAction(.retryPendingMutation) }.disabled(state.busy) }
            if state.loading { ProgressView(FeatureContactsStrings.text("contacts.loading", locale: locale)) }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
            .privacySensitive().rfHidesNavigationBar()
            .sheet(item: Binding(get: { state.pending }, set: { if $0 == nil { onAction(.cancelDecision) } })) { pending in
                NavigationStack { RFPage { VStack(alignment: .leading, spacing: theme.gap) {
                    Text(untrusted: pending.request.name).rfFont(.body, weight: .semibold)
                    KitIdentifierText(pending.request.principal).textSelection(.enabled)
                    Text(pending.action == .accept ? FeatureContactsStrings.text("contacts.decision.confirmAccept", locale: locale) : FeatureContactsStrings.text("contacts.decision.confirmOther", locale: locale))
                    RFHostConfirmationActions(summary: FeatureContactsStrings.sentence("contacts.decision.summary", [.localized(AppDataStrings.status(pending.action.rawValue, locale: locale)), .untrusted(pending.request.name), .identifier(pending.request.principal)], locale: locale), enabled: !state.busy && !state.unknownMutation, cancelEnabled: !state.busy, confirm: { onAction(.confirmDecision) }, cancel: { onAction(.cancelDecision) }).id(pending.id)
                    if state.busy { ProgressView(FeatureContactsStrings.text("contacts.decision.applying", locale: locale)) }
                    if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }.padding(theme.gap) } }.interactiveDismissDisabled(state.busy)
            }
    }
    private var title: String {
        switch state.mode { case .contacts: FeatureContactsStrings.text("common.tab.contacts", locale: locale); case .strangers: FeatureContactsStrings.text("contacts.strangers.title", locale: locale); case .sent: FeatureContactsStrings.text("contacts.sent.title", locale: locale); case .add: FeatureContactsStrings.text("contacts.add.title", locale: locale); case .profile: FeatureContactsStrings.text("contacts.profile.title", locale: locale); case .safety: FeatureContactsStrings.text("contacts.safety.title", locale: locale); case .request: FeatureContactsStrings.text("contacts.request.title", locale: locale) }
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .contacts:
            HStack { Button(FeatureContactsStrings.text("contacts.strangers.title", locale: locale)) { onAction(.mode(.strangers)) }; Button(FeatureContactsStrings.text("contacts.sent.title", locale: locale)) { onAction(.mode(.sent)) }; Spacer(); Button(FeatureContactsStrings.text("contacts.add.action", locale: locale), systemImage: "person.badge.plus") { onAction(.mode(.add)) } }
            KitSearchField(value: Binding(get: { state.query }, set: { onAction(.filter($0)) }), placeholder: FeatureContactsStrings.text("contacts.filter.placeholder", locale: locale), tag: "contact-filter")
            let filtered = state.visibleContacts
            if filtered.isEmpty && !state.loading { RFUnavailableView(title: FeatureContactsStrings.text("contacts.empty.title", locale: locale), message: FeatureContactsStrings.text("contacts.empty.message", locale: locale)) }
            ForEach(filtered) { contact in
                KitConversationRow(contact.displayName, preview: contact.subtitle, time: "", tag: contact.id, action: { onAction(.mode(.profile(contact.id))) }) {
                    KitAvatar(String(contact.displayName.prefix(1)), size: 44, kind: .person, tag: contact.id + "-avatar")
                }
            }
        case .add:
            TextField(FeatureContactsStrings.text("contacts.add.address", locale: locale), text: Binding(get: { state.principal }, set: { onAction(.principal($0)) })).textFieldStyle(.roundedBorder).rfAddressInput()
            Text(FeatureContactsStrings.text("contacts.add.notVerifiedNote", locale: locale))
            Button(FeatureContactsStrings.text("contacts.add.send", locale: locale)) { onAction(.add) }.disabled(state.busy || state.unknownMutation || state.principal.isEmpty)
        case .strangers, .sent:
            Text(FeatureContactsStrings.text("contacts.strangers.replyNote", locale: locale)).rfFont(.caption)
            if state.mode == .strangers { Button(FeatureContactsStrings.text("contacts.strangers.batch", locale: locale)) { onAction(.unavailable(.batch)) } }
            let requests = state.visibleRequests
            if requests.isEmpty && !state.loading { RFUnavailableView(title: FeatureContactsStrings.text("contacts.requests.empty.title", locale: locale), message: FeatureContactsStrings.text("contacts.requests.empty.message", locale: locale)) }
            ForEach(requests) { request in requestRow(request) }
        case .request(let id):
            if let request = state.requests.first(where: { $0.id == id }) { requestDetails(request) }
            else { Text(FeatureContactsStrings.text("contacts.request.missing", locale: locale)) }
        case .profile(let id):
            if let contact = state.contacts.first(where: { $0.id == id }) {
                Text(untrusted: contact.displayName).rfFont(.page); KitIdentifierText(contact.id).textSelection(.enabled)
                Label(contact.verified == true ? FeatureContactsStrings.text("contacts.profile.verified", locale: locale) : FeatureContactsStrings.text("contacts.profile.notVerified", locale: locale), systemImage: contact.verified == true ? "checkmark.shield" : "shield")
                Button(FeatureContactsStrings.text("contacts.profile.viewSafety", locale: locale)) { onAction(.mode(.safety(id))) }
            } else { Text(FeatureContactsStrings.text("contacts.profile.missing", locale: locale)) }
        case .safety:
            if let safety = state.safety, state.safetyPrincipal != nil, !state.safetyStale {
                if safety.requiresReview { Label(FeatureContactsStrings.text("contacts.safety.identityChanged", locale: locale), systemImage: "exclamationmark.shield").foregroundStyle(theme.danger) }
                KitIdentifierText(safety.number, tag: "contacts-safety-number").textSelection(.enabled)
                KitIdentifierText(safety.fingerprint, color: theme.secondary, tag: "contacts-safety-fingerprint").textSelection(.enabled)
                Label(safety.verified ? FeatureContactsStrings.text("contacts.safety.verified", locale: locale) : FeatureContactsStrings.text("contacts.safety.notVerified", locale: locale), systemImage: safety.verified ? "checkmark.shield" : "shield")
                Text(FeatureContactsStrings.text("contacts.safety.compareInstructions", locale: locale))
                Button(FeatureContactsStrings.text("contacts.safety.markCompared", locale: locale)) { onAction(.unavailable(.atomicSafetyVerification)) }
            } else if !state.loading { Text(FeatureContactsStrings.text("contacts.safety.unavailable", locale: locale)) }
        }
    }
    private func requestRow(_ request: ContactRequestRecord) -> some View {
        KitRow(RFUntrustedText.clean(request.name), action: { onAction(.mode(.request(request.id))) }, value: request.direction == "outbound" ? FeatureContactsStrings.format("request.sentStatus", AppDataStrings.status(request.state, locale: locale), locale: locale) : RFIdentifier.display(request.principal), tagLabel: AppDataStrings.status(request.state, locale: locale), tag: request.id)
    }
    private func requestDetails(_ request: ContactRequestRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Label(FeatureContactsStrings.text("contacts.request.firstContact", locale: locale), systemImage: "exclamationmark.shield")
            Text(untrusted: request.name).rfFont(.body, weight: .semibold); KitIdentifierText(request.principal).textSelection(.enabled)
            if let number = request.safetyNumber { LabeledContent { KitIdentifierText(number) } label: { Text(FeatureContactsStrings.text("contacts.safety.title", locale: locale)) } }
            if let preview = request.preview { Text(untrusted: preview, kind: .messageBody) }
            Text(AppDataStrings.status(request.state, locale: locale))
            if request.direction == "inbound" && request.state == "pending" {
                HStack {
                    Button(FeatureContactsStrings.text("contacts.request.decline", locale: locale)) { onAction(.requestDecision(request.id, .decline)) }
                    Button(FeatureContactsStrings.text("common.action.reply", locale: locale)) { onAction(.unavailable(.replyWithoutAcceptance)) }
                    Button(FeatureContactsStrings.text("contacts.request.accept", locale: locale)) { onAction(.requestDecision(request.id, .accept)) }
                }.disabled(state.busy || state.unknownMutation)
                Button(FeatureContactsStrings.text("contacts.request.block", locale: locale), role: .destructive) { onAction(.requestDecision(request.id, .block)) }.disabled(state.busy || state.unknownMutation)
                Button(FeatureContactsStrings.text("contacts.request.report", locale: locale)) { onAction(.unavailable(.reporting)) }
            }
        }
    }
}
