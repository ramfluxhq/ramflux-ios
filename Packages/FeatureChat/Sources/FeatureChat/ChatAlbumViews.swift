// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// The visual attachments of one message as an album (MOB-B23 is not designed yet). The box size
/// depends only on the item count, so the row never changes height when items download:
/// two items side by side (2:1), three as one tall leading item and two stacked (1:1), four or
/// more as a 2x2 grid (1:1) whose last cell shows "+n" and opens the whole album (up to 16).
/// Stacks follow the reading direction, so the first item sits at the leading edge.
struct MediaAlbumGrid: View {
    let messageID: String
    let items: [AttachmentRecord]
    let states: [String: MediaTransferState]
    let revealed: Set<String>
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        Group {
            switch items.count {
            case 2: HStack(spacing: spacing) { tile(0); tile(1) }.aspectRatio(2, contentMode: .fit)
            case 3: HStack(spacing: spacing) { tile(0); VStack(spacing: spacing) { tile(1); tile(2) } }.aspectRatio(1, contentMode: .fit)
            default:
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) { tile(0); tile(1) }
                    HStack(spacing: spacing) { tile(2); if items.count > 4 { more } else { tile(3) } }
                }.aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: ChatMediaText.boxWidth)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius_bubble))
    }
    static func layout(_ count: Int) -> (aspect: CGFloat, cells: Int) {
        switch count {
        case ...1: (4.0 / 3.0, 1)
        case 2: (2, 2)
        case 3: (1, 3)
        default: (1, 4)
        }
    }
    private var spacing: CGFloat { KitMetrics.stroke * 2 }
    private func tile(_ index: Int) -> some View {
        MediaTile(attachment: items[index], state: states[items[index].id] ?? .idle, revealed: revealed.contains(items[index].id), compact: true, onAction: onAction)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var more: some View {
        ZStack {
            tile(3).allowsHitTesting(false)
            theme.scrim
            Text(verbatim: "+" + (items.count - 3).formatted(.number.locale(locale))).rfFont(.page, weight: .semibold).foregroundStyle(theme.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onAction(.openAlbum(messageID)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(FeatureChatStrings.format("chat.album.more", items.count - 3, locale: locale)))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAction(.openAlbum(messageID)) }
    }
}

/// Every attachment of an album message in a lazy grid; each cell keeps its own state.
struct MediaAlbumSheet: View {
    let items: [AttachmentRecord]
    let states: [String: MediaTransferState]
    let revealed: Set<String>
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            HStack {
                Text(FeatureChatStrings.format("chat.album.title", items.count, locale: locale)).rfFont(.page)
                Spacer()
                Button(FeatureChatStrings.text("chat.details.close", locale: locale)) { onAction(.closeAlbum) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: ChatMediaText.albumCell), spacing: theme.gap / 2)], spacing: theme.gap / 2) {
                ForEach(items) { item in
                    MediaTile(attachment: item, state: states[item.id] ?? .idle, revealed: revealed.contains(item.id), compact: true, onAction: onAction)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius_md))
                }
            }
        }.padding(theme.gap) } }
    }
}

/// The send preview for picked media (MOB-B18/B28 are not designed yet): every staged item with
/// a remove button, one caption for the message, Send and Cancel.
struct MediaDraftSheet: View {
    let draft: MediaDraft
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureChatStrings.format("chat.draft.title", draft.items.count, locale: locale)).rfFont(.page)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: ChatMediaText.albumCell), spacing: theme.gap / 2)], spacing: theme.gap / 2) {
                ForEach(Array(draft.items.enumerated()), id: \.element.file) { index, item in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if item.mime.hasPrefix("image/") { PipelineImage(source: .file(item.file), maxPixel: ChatMediaText.tilePixels * 2) } else {
                                VStack(spacing: theme.gap / 2) {
                                    KitIcon(name: item.mime.hasPrefix("video/") ? "video" : "file-text", size: KitMetrics.iconAction, tint: theme.secondary)
                                    KitFileName(item.fileName, size: theme.size_secondary).lineLimit(2)
                                }.padding(theme.gap / 2)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.surface)
                        Button { onAction(.removeDraftItem(index)) } label: {
                            KitIcon(name: "x", size: KitMetrics.iconInfo, tint: theme.text).padding(theme.gap / 2).background(theme.overlay, in: Circle())
                        }
                        .buttonStyle(.plain).padding(theme.gap / 2)
                        .accessibilityLabel(Text(FeatureChatStrings.text("chat.draft.remove", locale: locale)))
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius_md))
                }
            }
            TextField(FeatureChatStrings.text("chat.draft.caption", locale: locale), text: Binding(get: { draft.caption }, set: { onAction(.draftCaptionChanged($0)) }), axis: .vertical)
                .lineLimit(1...5).rfFont(.body).padding(theme.gap).background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
            HStack(spacing: theme.gap) {
                KitButton(FeatureChatStrings.text("chat.composer.cancel", locale: locale), action: { onAction(.cancelMediaDraft) }, kind: .secondary, tag: "media-draft-cancel")
                KitButton(FeatureChatStrings.text("chat.draft.send", locale: locale), action: { onAction(.sendMediaDraft) }, enabled: !draft.items.isEmpty, tag: "media-draft-send")
            }
        }.padding(theme.gap) } }
    }
}
