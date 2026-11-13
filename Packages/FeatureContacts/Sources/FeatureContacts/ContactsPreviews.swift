// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum ContactsPreviews {
    public static var states: [ContactsState] {
        var empty = ContactsState(), loading = ContactsState(), offline = ContactsState(), populated = ContactsState()
        loading.loading = true; offline.failure = .offline
        populated.contacts = [ContactRecord(id: "alex@example.org", displayName: "Alex", subtitle: "alex@example.org", verified: false)]
        var strangers = ContactsState(mode: .strangers)
        strangers.requests = [ContactRequestRecord(id: "request", principal: "alex@example.org", name: "Alex", direction: "inbound", state: "pending", preview: "Hello")]
        var detail = strangers; detail.mode = .request("request")
        var sent = ContactsState(mode: .sent); sent.requests = [ContactRequestRecord(id: "outgoing", principal: "alex@example.org", name: "Alex", direction: "outbound", state: "pending")]
        var safety = ContactsState(mode: .safety("alex")); safety.safety = ContactSafety(root: "preview-root", number: "12345 67890 12345", fingerprint: "preview-fingerprint", verified: false, requiresReview: true)
        empty.loading = false
        populated.visibleContacts = populated.contacts; strangers.visibleRequests = strangers.requests; sent.visibleRequests = sent.requests; safety.safetyPrincipal = "alex"
        return [empty, loading, offline, populated, strangers, detail, sent, safety, ContactsState(mode: .add)]
    }
}
#Preview("Contacts") { ContactsScreen(state: ContactsPreviews.states[3], onAction: { _ in }) }

#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(ContactsPreviews.states.indices, id: \.self) { index in ContactsScreen(state: ContactsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }

#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(ContactsPreviews.states.indices, id: \.self) { index in ContactsScreen(state: ContactsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
