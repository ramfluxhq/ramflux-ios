// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public enum ContactsPreviews {
    public static var states: [ContactsState] {
        var empty = ContactsState(), loading = ContactsState(), offline = ContactsState(), populated = ContactsState()
        loading.loading = true; offline.failure = .offline
        populated.contacts = [ContactRecord(id: "alex@example.org", displayName: "Alex", subtitle: "alex@example.org")]
        var strangers = ContactsState(mode: .strangers)
        strangers.requests = [ContactRequestRecord(id: "request", principal: "alex@example.org", name: "Alex", direction: "inbound", state: "pending", preview: "Hello")]
        var detail = strangers; detail.mode = .request("request"); detail.selectedRequest = strangers.requests.first
        var sent = ContactsState(mode: .sent); sent.requests = [ContactRequestRecord(id: "outgoing", principal: "alex@example.org", name: "Alex", direction: "outbound", state: "pending")]
        var profile = ContactsState(mode: .profile("alex"))
        empty.loading = false
        profile.selected = ContactRecord(id: "alex", displayName: "Alex", subtitle: "alex", rootCommitment: "preview-root", linkID: "preview-link")
        return [empty, loading, offline, populated, strangers, detail, sent, profile, ContactsState(mode: .add)]
    }
}
#Preview("Contacts") { ContactsScreen(state: ContactsPreviews.states[3], onAction: { _ in }) }

#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(ContactsPreviews.states.indices, id: \.self) { index in ContactsScreen(state: ContactsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }

#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(ContactsPreviews.states.indices, id: \.self) { index in ContactsScreen(state: ContactsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
