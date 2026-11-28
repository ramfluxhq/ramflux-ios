// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
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
        profile.identity.state = .tofu
        var verified = profile; verified.identity.state = .verified
        var changed = profile; changed.identity.state = .changed
        changed.identity.change = IdentityChange(contact: "alex", username: "alex", previousAnchor: "preview-a1", newAnchor: "preview-a2")
        var review = changed; review.identity.sheetOpen = true
        var waiting = profile; waiting.identity.state = .changed
        return [empty, loading, offline, populated, strangers, detail, sent, profile, verified, changed, review, waiting, ContactsState(mode: .add)]
    }
}
#Preview("Contacts") { ContactsScreen(state: ContactsPreviews.states[3], onAction: { _ in }) }

#Preview("Chinese") { RFThemeScope { ScrollView { VStack { ForEach(ContactsPreviews.states.indices, id: \.self) { index in ContactsScreen(state: ContactsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "zh-CN")) }

#Preview("Expanded") { RFThemeScope { ScrollView { VStack { ForEach(ContactsPreviews.states.indices, id: \.self) { index in ContactsScreen(state: ContactsPreviews.states[index], onAction: { _ in }).frame(height: 844) } } } }.environment(\.locale, Locale(identifier: "en-XA")) }
