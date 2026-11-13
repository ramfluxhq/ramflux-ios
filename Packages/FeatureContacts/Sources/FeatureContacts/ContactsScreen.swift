// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ContactsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: ContactsState
    public let onAction: (ContactsAction) -> Void
    public init(state: ContactsState, onAction: @escaping (ContactsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            RFPageHeader(title: title, subtitle: "", theme: theme, leading: { EmptyView() }, trailing: { EmptyView() })
            if state.pendingMutation != nil { Button(FeatureContactsStrings.text("copy.c3f72136e5bb", locale: locale)) { onAction(.retryPendingMutation) }.disabled(state.busy) }
            if state.loading { ProgressView(FeatureContactsStrings.text("copy.b25dcb116a99", locale: locale)) }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
            .navigationTitle(title).privacySensitive()
            .toolbar { Button(FeatureContactsStrings.text("copy.0e9161011702", locale: locale), systemImage: "arrow.clockwise") { onAction(.refresh) } }
            .sheet(item: Binding(get: { state.pending }, set: { if $0 == nil { onAction(.cancelDecision) } })) { pending in
                NavigationStack { RFPage { VStack(alignment: .leading, spacing: theme.gap) {
                    Text(pending.request.name).font(theme.bodyFont.weight(.semibold))
                    Text(pending.request.principal).textSelection(.enabled)
                    Text(pending.action == .accept ? FeatureContactsStrings.text("copy.e4876d53862c", locale: locale) : FeatureContactsStrings.text("copy.5adf603bb15f", locale: locale))
                    Button(AppDataStrings.status(pending.action.rawValue, locale: locale), role: pending.action == .accept ? nil : .destructive) { onAction(.confirmDecision) }.disabled(state.busy || state.unknownMutation)
                    if state.busy { ProgressView(FeatureContactsStrings.text("copy.a17f264ff140", locale: locale)) }
                    if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }.padding(theme.gap) }.toolbar { Button(FeatureContactsStrings.text("copy.19766ed6ccb2", locale: locale)) { onAction(.cancelDecision) }.disabled(state.busy) } }.interactiveDismissDisabled(state.busy)
            }
    }
    private var title: String {
        switch state.mode { case .contacts: FeatureContactsStrings.text("copy.b450645debe2", locale: locale); case .strangers: FeatureContactsStrings.text("copy.4ebdb8769377", locale: locale); case .sent: FeatureContactsStrings.text("copy.874d69d66eb2", locale: locale); case .add: FeatureContactsStrings.text("copy.a02ce0df219d", locale: locale); case .profile: FeatureContactsStrings.text("copy.2b5c3d26721a", locale: locale); case .safety: FeatureContactsStrings.text("copy.97a2aa71bc3b", locale: locale); case .request: FeatureContactsStrings.text("copy.115034107ae1", locale: locale) }
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .contacts:
            HStack { Button(FeatureContactsStrings.text("copy.4ebdb8769377", locale: locale)) { onAction(.mode(.strangers)) }; Button(FeatureContactsStrings.text("copy.874d69d66eb2", locale: locale)) { onAction(.mode(.sent)) }; Spacer(); Button(FeatureContactsStrings.text("copy.9fd728c66c9a", locale: locale), systemImage: "person.badge.plus") { onAction(.mode(.add)) } }
            RFSearchField(id: "contact-filter", label: FeatureContactsStrings.text("copy.604bf8eb82d8", locale: locale), value: Binding(get: { state.query }, set: { onAction(.filter($0)) }), theme: theme)
            let filtered = state.visibleContacts
            if filtered.isEmpty && !state.loading { RFUnavailableView(title: FeatureContactsStrings.text("copy.0013e6984bf6", locale: locale), message: FeatureContactsStrings.text("copy.d6aa21ab75ee", locale: locale)) }
            ForEach(filtered) { contact in
                RFListRow(id: contact.id, title: contact.displayName, subtitle: contact.subtitle, theme: theme,
                    leading: { RFAvatar(initial: String(contact.displayName.prefix(1)), kind: .person, theme: theme) }, trailing: { Image(systemName: "chevron.right").accessibilityHidden(true) }) { onAction(.mode(.profile(contact.id))) }
            }
        case .add:
            TextField(FeatureContactsStrings.text("copy.cc755b5f1b02", locale: locale), text: Binding(get: { state.principal }, set: { onAction(.principal($0)) })).textFieldStyle(.roundedBorder).rfAddressInput()
            Text(FeatureContactsStrings.text("copy.4d43cecc17d7", locale: locale))
            Button(FeatureContactsStrings.text("copy.a45f93ef3f36", locale: locale)) { onAction(.add) }.disabled(state.busy || state.unknownMutation || state.principal.isEmpty)
        case .strangers, .sent:
            Text(FeatureContactsStrings.text("copy.7ca1e1523ef9", locale: locale)).font(theme.captionFont)
            if state.mode == .strangers { Button(FeatureContactsStrings.text("copy.076c195e33c2", locale: locale)) { onAction(.unavailable(.batch)) } }
            let requests = state.visibleRequests
            if requests.isEmpty && !state.loading { RFUnavailableView(title: FeatureContactsStrings.text("copy.29f7a933bca1", locale: locale), message: FeatureContactsStrings.text("copy.eb4cab81786c", locale: locale)) }
            ForEach(requests) { request in requestRow(request) }
        case .request(let id):
            if let request = state.requests.first(where: { $0.id == id }) { requestDetails(request) }
            else { Text(FeatureContactsStrings.text("copy.b2e254c8cd4a", locale: locale)) }
        case .profile(let id):
            if let contact = state.contacts.first(where: { $0.id == id }) {
                Text(contact.displayName).font(theme.pageFont); Text(contact.id).textSelection(.enabled)
                Label(contact.verified == true ? FeatureContactsStrings.text("copy.99b52fb41be2", locale: locale) : FeatureContactsStrings.text("copy.13b58a61daec", locale: locale), systemImage: contact.verified == true ? "checkmark.shield" : "shield")
                Button(FeatureContactsStrings.text("copy.a131c2d2b123", locale: locale)) { onAction(.mode(.safety(id))) }
            } else { Text(FeatureContactsStrings.text("copy.d911b7040af8", locale: locale)) }
        case .safety:
            if let safety = state.safety, state.safetyPrincipal != nil, !state.safetyStale {
                if safety.requiresReview { Label(FeatureContactsStrings.text("copy.5dacc74e46f5", locale: locale), systemImage: "exclamationmark.shield").foregroundStyle(theme.danger) }
                Text(safety.number).monospaced().textSelection(.enabled)
                Text(safety.fingerprint).font(theme.captionFont).textSelection(.enabled)
                Label(safety.verified ? FeatureContactsStrings.text("copy.4f7838402f37", locale: locale) : FeatureContactsStrings.text("copy.151339072593", locale: locale), systemImage: safety.verified ? "checkmark.shield" : "shield")
                Text(FeatureContactsStrings.text("copy.9c240ce98597", locale: locale))
                Button(FeatureContactsStrings.text("copy.4b7574aab6d2", locale: locale)) { onAction(.unavailable(.atomicSafetyVerification)) }
            } else if !state.loading { Text(FeatureContactsStrings.text("copy.1390f67d32c2", locale: locale)) }
        }
    }
    private func requestRow(_ request: ContactRequestRecord) -> some View {
        RFListRow(id: request.id, title: request.name, subtitle: request.direction == "outbound" ? FeatureContactsStrings.format("request.sentStatus", AppDataStrings.status(request.state, locale: locale), locale: locale) : request.principal,
                  theme: theme, leading: { EmptyView() }, trailing: { Text(AppDataStrings.status(request.state, locale: locale)).font(theme.captionFont) }) { onAction(.mode(.request(request.id))) }
    }
    private func requestDetails(_ request: ContactRequestRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Label(FeatureContactsStrings.text("copy.65fd288cba62", locale: locale), systemImage: "exclamationmark.shield")
            Text(request.name).font(theme.bodyFont.weight(.semibold)); Text(request.principal).textSelection(.enabled)
            if let number = request.safetyNumber { LabeledContent(FeatureContactsStrings.text("copy.97a2aa71bc3b", locale: locale), value: number) }
            if let preview = request.preview { Text(preview) }
            Text(AppDataStrings.status(request.state, locale: locale))
            if request.direction == "inbound" && request.state == "pending" {
                HStack {
                    Button(FeatureContactsStrings.text("copy.a2d285b35287", locale: locale)) { onAction(.requestDecision(request.id, .decline)) }
                    Button(FeatureContactsStrings.text("copy.c253f451bdd5", locale: locale)) { onAction(.unavailable(.replyWithoutAcceptance)) }
                    Button(FeatureContactsStrings.text("copy.89713b9c9c1b", locale: locale)) { onAction(.requestDecision(request.id, .accept)) }
                }.disabled(state.busy || state.unknownMutation)
                Button(FeatureContactsStrings.text("copy.211d0bb8cf4f", locale: locale), role: .destructive) { onAction(.requestDecision(request.id, .block)) }.disabled(state.busy || state.unknownMutation)
                Button(FeatureContactsStrings.text("copy.b6ce788d9786", locale: locale)) { onAction(.unavailable(.reporting)) }
            }
        }
    }
}
