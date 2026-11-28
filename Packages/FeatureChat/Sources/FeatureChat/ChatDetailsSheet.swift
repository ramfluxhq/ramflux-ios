// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// Conversation details (members, mute, encryption). Built from the Kit and the nearest boards; no
/// mobile board exists for it yet. Facts the SDK does not return are shown as unavailable.
struct ChatDetailsSheet: View {
    let state: ChatDetailsState
    let title: String
    let conversationID: String
    let isGroup: Bool
    let identity: IdentityPanel
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
            }
            if !isGroup {
                IdentityEncryptionSection(panel: identity, showsSecurity: true, onReview: { onAction(.identityReview) })
            }
            KitRow(FeatureChatStrings.text("chat.gallery.title", locale: locale), action: { onAction(.openGallery) }, icon: "images", tag: "chat-details-gallery")
            if let storage = state.storage {
                KitRow(FeatureChatStrings.text("chat.storage.conversation", locale: locale), icon: "database", value: storage.formatted(.byteCount(style: .file).locale(locale)), trailing: .none)
                if storage > 0 {
                    if state.confirmClear {
                        Text(FeatureChatStrings.text("chat.storage.clearFact", locale: locale)).rfFont(.caption)
                        HStack(spacing: theme.gap) {
                            KitButton(FeatureChatStrings.text("chat.composer.cancel", locale: locale), action: { onAction(.clearMediaCancelled) }, kind: .secondary, size: .compact, tag: "chat-storage-cancel")
                            KitButton(FeatureChatStrings.text("chat.storage.clear", locale: locale), action: { onAction(.clearMediaConfirmed) }, kind: .destructive, size: .compact, tag: "chat-storage-confirm")
                        }
                    } else {
                        KitRow(FeatureChatStrings.text("chat.storage.clear", locale: locale), action: { onAction(.clearMediaRequested) }, icon: "trash-2", tag: "chat-storage-clear")
                    }
                }
            }
            Button(FeatureChatStrings.text("chat.details.close", locale: locale)) { onAction(.closeDetails) }
        }.padding(theme.gap) } }
        .sheet(isPresented: Binding(get: { identity.showsSheet }, set: { if !$0 { onAction(.identityLater) } })) {
            IdentityChangeSheet(panel: identity, onAccept: { onAction(.identityAccept(anchor: $0)) }, onLater: { onAction(.identityLater) })
        }
    }
}
