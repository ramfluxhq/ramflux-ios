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
    /// Only the contact list pulls to refresh; the event stream keeps every page current.
    @ViewBuilder private var page: some View {
        if state.mode == .contacts { scrolling.refreshable { onAction(.refresh) } } else { scrolling }
    }
    private var scrolling: some View {
        RFPage { ScrollView { LazyVStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(title, onBack: { dismiss() }, tag: "contacts-header")
            if state.pendingMutation != nil { Button(FeatureContactsStrings.text("contacts.reconcile", locale: locale)) { onAction(.retryPendingMutation) }.disabled(state.busy) }
            if state.loading { ProgressView(FeatureContactsStrings.text("contacts.loading", locale: locale)) }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
    }
    public var body: some View {
        page
            .privacySensitive().rfHidesNavigationBar()
            .sheet(item: Binding(get: { state.pending }, set: { if $0 == nil { onAction(.cancelDecision) } })) { pending in
                NavigationStack { RFPage { VStack(alignment: .leading, spacing: theme.gap) {
                    Text(untrusted: pending.request.name).rfFont(.body, weight: .semibold)
                    KitIdentifierText(pending.request.principal).textSelection(.enabled)
                    Text(pending.action == .accept ? FeatureContactsStrings.text("contacts.decision.confirmAccept", locale: locale) : FeatureContactsStrings.text("contacts.decision.confirmOther", locale: locale))
                    RFHostConfirmationActions(summary: FeatureContactsStrings.sentence("contacts.decision.summary", [.localized(AppDataStrings.status(pending.action.rawValue, locale: locale)), .untrusted(pending.request.name), .identifier(pending.request.principal)], locale: locale), enabled: !state.busy && !state.unknownMutation, cancelEnabled: !state.busy, destructive: pending.action != .accept, confirm: { onAction(.confirmDecision) }, cancel: { onAction(.cancelDecision) }).id(pending.id)
                    if state.busy { ProgressView(FeatureContactsStrings.text("contacts.decision.applying", locale: locale)) }
                    if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }.padding(theme.gap) } }.interactiveDismissDisabled(state.busy)
            }
            .sheet(item: Binding(get: { state.pendingChange }, set: { if $0 == nil { onAction(.cancelChange) } })) { pending in
                NavigationStack { RFPage { VStack(alignment: .leading, spacing: theme.gap) {
                    Text(untrusted: pending.contact.displayName).rfFont(.body, weight: .semibold)
                    KitIdentifierText(pending.contact.id).textSelection(.enabled)
                    Text(FeatureContactsStrings.text("contacts.change.confirm." + pending.change.rawValue, locale: locale))
                    RFHostConfirmationActions(summary: FeatureContactsStrings.sentence("contacts.decision.summary", [.localized(changeLabel(pending.change)), .untrusted(pending.contact.displayName), .identifier(pending.contact.id)], locale: locale), enabled: !state.busy && !state.unknownMutation, cancelEnabled: !state.busy, destructive: pending.change == .remove || pending.change == .block, confirm: { onAction(.confirmChange) }, cancel: { onAction(.cancelChange) }).id(pending.id)
                    if state.busy { ProgressView(FeatureContactsStrings.text("contacts.change.applying", locale: locale)) }
                    if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }.padding(theme.gap) } }.interactiveDismissDisabled(state.busy)
            }
    }
    private func changeLabel(_ change: ContactChange) -> String {
        switch change {
        case .remove: FeatureContactsStrings.text("contacts.profile.remove", locale: locale)
        case .block: FeatureContactsStrings.text("contacts.profile.block", locale: locale)
        case .unblock: FeatureContactsStrings.text("contacts.profile.unblock", locale: locale)
        case .verify: FeatureContactsStrings.text("contacts.safety.markCompared", locale: locale)
        }
    }
    @ViewBuilder private var pagingFooter: some View {
        if state.loadingMore { ProgressView(FeatureContactsStrings.text("contacts.loadingMore", locale: locale)) }
    }
    private func pageTriggers(id: String, first: String?, last: String?) -> some View {
        Color.clear.frame(height: 0).onAppear {
            if id == last && state.canLoadMore { onAction(.loadMore) }
            if id == first && state.canLoadBefore { onAction(.loadBefore) }
        }
    }
    private var title: String {
        switch state.mode { case .contacts: FeatureContactsStrings.text("common.tab.contacts", locale: locale); case .strangers: FeatureContactsStrings.text("contacts.strangers.title", locale: locale); case .sent: FeatureContactsStrings.text("contacts.sent.title", locale: locale); case .add: FeatureContactsStrings.text("contacts.add.title", locale: locale); case .profile: FeatureContactsStrings.text("contacts.profile.title", locale: locale); case .safety: FeatureContactsStrings.text("contacts.safety.title", locale: locale); case .request: FeatureContactsStrings.text("contacts.request.title", locale: locale); case .myCard: FeatureContactsStrings.text("contacts.myCard.title", locale: locale) }
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .contacts:
            HStack { Button(FeatureContactsStrings.text("contacts.strangers.title", locale: locale)) { onAction(.mode(.strangers)) }.accessibilityIdentifier("contacts-strangers"); Button(FeatureContactsStrings.text("contacts.sent.title", locale: locale)) { onAction(.mode(.sent)) }.accessibilityIdentifier("contacts-sent"); Spacer(); Button(FeatureContactsStrings.text("contacts.add.action", locale: locale), systemImage: "person.badge.plus") { onAction(.mode(.add)) }.accessibilityIdentifier("contacts-add") }
            Button(FeatureContactsStrings.text("contacts.myCard.title", locale: locale), systemImage: "qrcode") { onAction(.mode(.myCard)) }.accessibilityIdentifier("contacts-my-card")
            KitSearchField(value: Binding(get: { state.query }, set: { onAction(.filter($0)) }), placeholder: FeatureContactsStrings.text("contacts.filter.placeholder", locale: locale), tag: "contact-filter")
            let rows = state.contacts
            if rows.isEmpty && !state.loading { RFUnavailableView(title: FeatureContactsStrings.text("contacts.empty.title", locale: locale), message: FeatureContactsStrings.text("contacts.empty.message", locale: locale)) }
            ForEach(rows) { contact in
                KitConversationRow(contact.displayName, preview: contact.subtitle, time: "", aiMarker: contact.classification.isAIAgent, tag: contact.id, action: { onAction(.mode(.profile(contact.id))) }) {
                    KitAvatar(String(contact.displayName.prefix(1)), size: 44, kind: .person, tag: contact.id + "-avatar")
                }
                .background { pageTriggers(id: contact.id, first: rows.first?.id, last: rows.last?.id) }
            }
            pagingFooter
        case .myCard:
            if let card = state.ownCard { MyContactCardView(card: card) }
        case .add:
            TextField(FeatureContactsStrings.text("contacts.add.address", locale: locale), text: Binding(get: { state.principal }, set: { onAction(.principal($0)) })).textFieldStyle(.roundedBorder).rfAddressInput().disabled(state.busy).accessibilityIdentifier("contacts-add-address")
            Text(FeatureContactsStrings.text("contacts.add.notVerifiedNote", locale: locale))
            if state.lookingUp { ProgressView(FeatureContactsStrings.text("contacts.username.lookingUp", locale: locale)) }
            if let found = state.usernameLookup, found.text == state.principal {
                // The result card: what the directory holds for the name. Sending targets only this text.
                VStack(alignment: .leading, spacing: theme.gap / 2) {
                    Text(FeatureContactsStrings.format("contacts.username.found", found.text.hasPrefix("@") ? String(found.text.dropFirst()) : found.text, locale: locale)).rfFont(.body, weight: .semibold)
                    if let name = found.resolution.displayName { Text(untrusted: name) }
                    if let bio = found.resolution.bio { Text(untrusted: bio).rfFont(.caption) }
                    Button(FeatureContactsStrings.text("contacts.username.send", locale: locale)) { onAction(.sendUsername) }.disabled(state.busy || state.unknownMutation).accessibilityIdentifier("contacts-username-send")
                }
            }
            Button(FeatureContactsStrings.text(state.principal.hasPrefix("@") ? "contacts.username.lookup" : "contacts.add.send", locale: locale)) { onAction(.add) }.disabled(state.busy || state.unknownMutation || state.lookingUp || state.principal.isEmpty).accessibilityIdentifier("contacts-add-send")
        case .strangers, .sent:
            Text(FeatureContactsStrings.text("contacts.strangers.replyNote", locale: locale)).rfFont(.caption)
            if state.mode == .strangers { Button(FeatureContactsStrings.text("contacts.strangers.batch", locale: locale)) { onAction(.unavailable(.batch)) } }
            let requests = state.requests
            if requests.isEmpty && !state.loading { RFUnavailableView(title: FeatureContactsStrings.text("contacts.requests.empty.title", locale: locale), message: FeatureContactsStrings.text("contacts.requests.empty.message", locale: locale)) }
            ForEach(requests) { request in
                requestRow(request).background { pageTriggers(id: request.id, first: requests.first?.id, last: requests.last?.id) }
            }
            pagingFooter
        case .request(let id):
            if let request = state.selectedRequest, request.id == id { requestDetails(request) }
            else { Text(FeatureContactsStrings.text("contacts.request.missing", locale: locale)) }
        case .profile(let id):
            if let contact = state.selected, contact.id == id {
                HStack(spacing: theme.gap) { Text(untrusted: contact.displayName).rfFont(.page); if contact.classification.isAIAgent { KitAIMarker(tag: "contact-ai") } }
                KitIdentifierText(contact.id).textSelection(.enabled)
                Label(contact.verified == true ? FeatureContactsStrings.text("contacts.profile.verified", locale: locale) : FeatureContactsStrings.text("contacts.profile.notVerified", locale: locale), systemImage: contact.verified == true ? "checkmark.shield" : "shield")
                if contact.blocked { Label(FeatureContactsStrings.text("contacts.profile.blocked", locale: locale), systemImage: "hand.raised") }
                KitButton(FeatureContactsStrings.text("contacts.profile.viewSafety", locale: locale), action: { onAction(.mode(.safety(id))) }, kind: .secondary, tag: "contact-safety")
                changeButtons(contact)
            } else { Text(FeatureContactsStrings.text("contacts.profile.missing", locale: locale)) }
        case .safety:
            if let safety = state.safety, let contact = state.selected, state.safetyPrincipal == contact.id, !state.safetyStale {
                if safety.requiresReview { Label(FeatureContactsStrings.text("contacts.safety.identityChanged", locale: locale), systemImage: "exclamationmark.shield").foregroundStyle(theme.danger) }
                KitIdentifierText(safety.number, tag: "contacts-safety-number").textSelection(.enabled)
                KitIdentifierText(safety.fingerprint, color: theme.secondary, tag: "contacts-safety-fingerprint").textSelection(.enabled)
                Label(safety.verified ? FeatureContactsStrings.text("contacts.safety.verified", locale: locale) : FeatureContactsStrings.text("contacts.safety.notVerified", locale: locale), systemImage: safety.verified ? "checkmark.shield" : "shield")
                if safety.verified { Text(FeatureContactsStrings.text("contacts.safety.verifiedNote", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary) }
                else {
                    Text(FeatureContactsStrings.text("contacts.safety.compareInstructions", locale: locale))
                    KitButton(FeatureContactsStrings.text("contacts.safety.markCompared", locale: locale), action: { onAction(.requestChange(.verify)) },
                              enabled: ContactsViewModel.allows(.verify, contact: contact, safety: safety, stale: state.safetyStale) && !state.busy && !state.unknownMutation, tag: "contact-verify")
                }
            } else if !state.loading { Text(FeatureContactsStrings.text("contacts.safety.unavailable", locale: locale)) }
        }
    }
    @ViewBuilder private func changeButtons(_ contact: ContactRecord) -> some View {
        let enabled = !state.busy && !state.unknownMutation
        if ContactsViewModel.allows(.unblock, contact: contact, safety: nil, stale: false) {
            KitButton(FeatureContactsStrings.text("contacts.profile.unblock", locale: locale), action: { onAction(.requestChange(.unblock)) }, kind: .secondary, enabled: enabled, tag: "contact-unblock")
        }
        if ContactsViewModel.allows(.block, contact: contact, safety: nil, stale: false) {
            KitButton(FeatureContactsStrings.text("contacts.profile.block", locale: locale), action: { onAction(.requestChange(.block)) }, kind: .secondary, enabled: enabled, tag: "contact-block")
        }
        if ContactsViewModel.allows(.remove, contact: contact, safety: nil, stale: false) {
            KitButton(FeatureContactsStrings.text("contacts.profile.remove", locale: locale), action: { onAction(.requestChange(.remove)) }, kind: .destructive, enabled: enabled, tag: "contact-remove")
        }
    }
    private func requestRow(_ request: ContactRequestRecord) -> some View {
        KitRow(RFUntrustedText.clean(request.name), action: { onAction(.mode(.request(request.id))) }, value: request.direction == "outbound" ? FeatureContactsStrings.format("request.sentStatus", AppDataStrings.status(request.state, locale: locale), locale: locale) : RFIdentifier.display(request.principal), tagLabel: AppDataStrings.status(request.state, locale: locale), aiMarker: request.classification.isAIAgent, tag: request.id)
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
