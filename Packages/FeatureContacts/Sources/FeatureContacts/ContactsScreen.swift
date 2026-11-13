// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct ContactsScreen: View {
    @Environment(\.colorScheme) private var scheme
    public let state: ContactsState
    public let onAction: (ContactsAction) -> Void
    public init(state: ContactsState, onAction: @escaping (ContactsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: RFTheme.adaptive(scheme).gap) {
            RFPageHeader(title: title, subtitle: "", theme: RFTheme.adaptive(scheme), leading: { EmptyView() }, trailing: { EmptyView() })
            if state.loading { ProgressView("Loading contacts") }
            content
            if let failure = state.failure { RFFailureView(title: failure.title, message: failure.message) }
        }.padding().frame(maxWidth: RFTheme.adaptive(scheme).column_max, alignment: .leading).frame(maxWidth: .infinity) } }
            .navigationTitle(title).privacySensitive()
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { onAction(.refresh) } }
            .sheet(item: Binding(get: { state.pending }, set: { if $0 == nil { onAction(.cancelDecision) } })) { pending in
                NavigationStack { RFPage { VStack(alignment: .leading, spacing: 16) {
                    Text(pending.request.name).font(.headline)
                    Text(pending.request.principal).textSelection(.enabled)
                    Text(pending.action == .accept ? "Accept this request and add this account to your contacts?" : "Apply this decision to this incoming request?")
                    Button(pending.action.rawValue.capitalized, role: pending.action == .accept ? nil : .destructive) { onAction(.confirmDecision) }.disabled(state.busy || state.unknownMutation)
                    if state.busy { ProgressView("Applying decision") }
                    if let failure = state.failure { RFFailureView(title: failure.title, message: failure.message) }
                }.padding() }.toolbar { Button("Cancel") { onAction(.cancelDecision) }.disabled(state.busy) } }.interactiveDismissDisabled(state.busy)
            }
    }
    private var title: String {
        switch state.mode { case .contacts: "Contacts"; case .strangers: "Strangers"; case .sent: "Sent requests"; case .add: "Add contact"; case .profile: "Contact"; case .safety: "Safety number"; case .request: "Stranger request" }
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .contacts:
            HStack { Button("Strangers") { onAction(.mode(.strangers)) }; Button("Sent requests") { onAction(.mode(.sent)) }; Spacer(); Button("Add", systemImage: "person.badge.plus") { onAction(.mode(.add)) } }
            RFSearchField(id: "contact-filter", label: "Filter contacts", value: Binding(get: { state.query }, set: { onAction(.filter($0)) }), theme: RFTheme.adaptive(scheme))
            let filtered = state.contacts.filter { state.query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(state.query) || $0.id.localizedCaseInsensitiveContains(state.query) }
            if filtered.isEmpty && !state.loading { RFUnavailableView(title: "No contacts found", message: "Add a contact using their account address.") }
            ForEach(filtered) { contact in
                RFListRow(id: contact.id, title: contact.displayName, subtitle: contact.subtitle, theme: RFTheme.adaptive(scheme),
                    leading: { RFAvatar(initial: String(contact.displayName.prefix(1)), kind: .person, theme: RFTheme.adaptive(scheme)) }, trailing: { Image(systemName: "chevron.right").accessibilityHidden(true) }) { onAction(.mode(.profile(contact.id))) }
            }
        case .add:
            TextField("Account address", text: Binding(get: { state.principal }, set: { onAction(.principal($0)) })).textFieldStyle(.roundedBorder).rfAddressInput()
            Text("A request does not make the other account verified.")
            Button("Send contact request") { onAction(.add) }.disabled(state.busy || state.unknownMutation || state.principal.isEmpty)
        case .strangers, .sent:
            Text("Replying does not accept a request or add a contact.").font(.caption)
            if state.mode == .strangers { Button("Batch actions") { onAction(.unavailable(.batch)) } }
            let requests = state.requests.filter { $0.direction == (state.mode == .sent ? "outbound" : "inbound") }
            if requests.isEmpty && !state.loading { RFUnavailableView(title: "No requests", message: "Requests for this account will appear here.") }
            ForEach(requests) { request in requestRow(request) }
        case .request(let id):
            if let request = state.requests.first(where: { $0.id == id }) { requestDetails(request) }
            else { Text("This request is no longer present. Refresh for its current status.") }
        case .profile(let id):
            if let contact = state.contacts.first(where: { $0.id == id }) {
                Text(contact.displayName).font(.title2); Text(contact.id).textSelection(.enabled)
                Label(contact.verified == true ? "Identity verified" : "Identity not verified", systemImage: contact.verified == true ? "checkmark.shield" : "shield")
                Button("View safety number") { onAction(.mode(.safety(id))) }
            } else { Text("This contact is unavailable. Refresh your contacts.") }
        case .safety:
            if let safety = state.safety {
                if safety.requiresReview { Label("Identity changed. Compare the complete number again.", systemImage: "exclamationmark.shield").foregroundStyle(RFTheme.adaptive(scheme).danger) }
                Text(safety.number).monospaced().textSelection(.enabled)
                Text(safety.fingerprint).font(.caption).textSelection(.enabled)
                Label(safety.verified ? "Verified" : "Not verified", systemImage: safety.verified ? "checkmark.shield" : "shield")
                Text("Compare this number through another trusted channel.")
                Button("I compared this number") { onAction(.unavailable(.atomicSafetyVerification)) }
            } else if !state.loading { Text("Safety details are unavailable for this contact.") }
        }
    }
    private func requestRow(_ request: ContactRequestRecord) -> some View {
        RFListRow(id: request.id, title: request.name, subtitle: request.direction == "outbound" ? "Sent request · \(request.state)" : request.principal,
                  theme: RFTheme.adaptive(scheme), leading: { EmptyView() }, trailing: { Text(request.state).font(.caption) }) { onAction(.mode(.request(request.id))) }
    }
    private func requestDetails(_ request: ContactRequestRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("First contact · identity not verified", systemImage: "exclamationmark.shield")
            Text(request.name).font(.headline); Text(request.principal).textSelection(.enabled)
            if let number = request.safetyNumber { LabeledContent("Safety number", value: number) }
            if let preview = request.preview { Text(preview) }
            Text(request.state)
            if request.direction == "inbound" && request.state == "pending" {
                HStack {
                    Button("Decline") { onAction(.requestDecision(request.id, .decline)) }
                    Button("Reply") { onAction(.unavailable(.replyWithoutAcceptance)) }
                    Button("Accept") { onAction(.requestDecision(request.id, .accept)) }
                }.disabled(state.busy || state.unknownMutation)
                Button("Block", role: .destructive) { onAction(.requestDecision(request.id, .block)) }.disabled(state.busy || state.unknownMutation)
                Button("Report") { onAction(.unavailable(.reporting)) }
            }
        }
    }
}
