// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// Conversation details (members, mute, safety). Built from the Kit and the nearest boards; no
/// mobile board exists for it yet. Facts the SDK does not return are shown as unavailable.
struct ChatDetailsSheet: View {
    let state: ChatDetailsState
    let title: String
    let conversationID: String
    let isGroup: Bool
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureChatStrings.text("chat.details.title", locale: locale)).rfFont(.page)
            Text(untrusted: title).rfFont(.body)
            Text(FeatureChatStrings.text("chat.details.conversationID", locale: locale)).rfFont(.caption)
            KitIdentifierText(conversationID)
            if state.loading { ProgressView(FeatureChatStrings.text("chat.loading", locale: locale)) }
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            if let details = state.details {
                Text(FeatureChatStrings.text("chat.details.members", locale: locale)).rfFont(.caption)
                if isGroup {
                    Text(FeatureChatStrings.text("chat.details.groupMembers", locale: locale)).rfFont(.body)
                } else {
                    KitRow(FeatureChatStrings.text("chat.details.you", locale: locale), icon: "user-round", trailing: .none)
                    KitRow(RFUntrustedText.clean(details.peerName ?? title), icon: "user-round", value: details.peerPrincipal.map(RFIdentifier.display), trailing: .none)
                }
                if let muted = details.muted {
                    HStack(spacing: theme.gap) {
                        Text(FeatureChatStrings.text("chat.details.mute", locale: locale)).rfFont(.body).frame(maxWidth: .infinity, alignment: .leading)
                        KitSwitch(checked: muted, onChecked: { onAction(.setMuted($0)) }, enabled: !state.muting, label: FeatureChatStrings.text("chat.details.mute", locale: locale), tag: "chat-details-mute")
                    }
                } else {
                    Text(FeatureChatStrings.text("chat.details.muteUnknown", locale: locale)).rfFont(.caption)
                }
                if !isGroup {
                    if details.peerPrincipal != nil {
                        KitRow(FeatureChatStrings.text("chat.details.safety", locale: locale), action: { onAction(.openSafetyNumber) }, icon: "shield-check", tag: "chat-details-safety")
                    } else {
                        Text(FeatureChatStrings.text("chat.details.safetyUnavailable", locale: locale)).rfFont(.caption)
                    }
                }
            }
            Button(FeatureChatStrings.text("chat.details.close", locale: locale)) { onAction(.closeDetails) }
        }.padding(theme.gap) } }
    }
}
