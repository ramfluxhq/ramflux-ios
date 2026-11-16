// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public enum KitRowTrailing { case chevron, check, none }

public struct KitIconTile: View {
    var icon: String
    var tag: String?
    @Environment(\.rfTheme) private var theme
    public init(icon: String, tag: String? = nil) { self.icon = icon; self.tag = tag }
    public var body: some View {
        KitIcon(name: icon, size: KitMetrics.tileGlyph, tint: theme.text)
            .frame(width: KitMetrics.tile, height: KitMetrics.tile)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_sm))
            .kitTag(tag)
    }
}

public struct KitInfoButton: View {
    var label: String
    var tag: String?
    var action: () -> Void
    @Environment(\.rfTheme) private var theme
    public init(label: String = "", tag: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.tag = tag
        self.action = action
    }
    public var body: some View {
        KitHit(enabled: true, label: label.isEmpty ? RFDesignStrings.text("kit.info") : label, hitTag: tag.map { $0 + "-hit" }, action: action) {
            KitIcon(name: "info", size: KitMetrics.iconInfo, tint: theme.secondary)
                .frame(width: KitMetrics.iconButton, height: KitMetrics.iconButton)
                .kitTag(tag)
        }
    }
}

public struct KitRow: View {
    var label: String
    var action: () -> Void
    var icon: String?
    var value: String?
    var tagLabel: String?
    var trailing: KitRowTrailing
    var enabled: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme
    @Environment(\.kitPreviewPressed) private var previewPressed
    @State private var holding = false

    public init(
        _ label: String,
        action: @escaping () -> Void = {},
        icon: String? = nil,
        value: String? = nil,
        tagLabel: String? = nil,
        trailing: KitRowTrailing = .chevron,
        enabled: Bool = true,
        tag: String? = nil
    ) {
        self.label = label
        self.action = action
        self.icon = icon
        self.value = value
        self.tagLabel = tagLabel
        self.trailing = trailing
        self.enabled = enabled
        self.tag = tag
    }

    public var body: some View {
        let pressed = enabled && (holding || previewPressed)
        HStack(spacing: KitMetrics.rowGap) {
            if let icon { KitIconTile(icon: icon) }
            VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                KitLabel(label, size: theme.size_mobile_body, weight: .regular, color: theme.text, line: KitMetrics.lineTitle)
                if let value, !value.isEmpty {
                    KitLabel(value, size: theme.size_secondary, weight: .regular, color: theme.secondary, line: KitMetrics.lineSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tagLabel, !tagLabel.isEmpty {
                KitLabel(tagLabel, size: theme.size_meta, weight: .semibold, color: theme.warning, line: KitMetrics.lineTitle)
                    .padding(.horizontal, KitMetrics.tagPadH)
                    .padding(.vertical, KitMetrics.tagPadV)
                    .background(theme.warning_bg, in: RoundedRectangle(cornerRadius: theme.radius_chip))
            }
            switch trailing {
            case .chevron: KitIcon(name: "chevron-right", size: KitMetrics.chevron, tint: theme.control)
            case .check: KitIcon(name: "circle-check", size: KitMetrics.chevron, tint: theme.text)
            case .none: EmptyView()
            }
        }
        .padding(.horizontal, KitMetrics.gutter)
        .padding(.vertical, KitMetrics.rowPadV)
        .frame(maxWidth: .infinity)
        .frame(height: KitMetrics.row)
        .background(pressed ? theme.selected : .clear)
        .kitHairline(theme.line)
        .opacity(enabled ? 1 : KitMetrics.disabledAlpha)
        .contentShape(Rectangle())
        .gesture(rowPress)
        .allowsHitTesting(enabled)
        .kitTag(tag)
        .preference(key: KitHits.self, value: tag.map { [$0: enabled] } ?? [:])
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
    }

    private var rowPress: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in if enabled { holding = true } }
            .onEnded { _ in
                holding = false
                if enabled { action() }
            }
    }
}

public struct KitConversationRow<Avatar: View>: View {
    var title: String
    var preview: String
    var time: String
    var action: () -> Void
    var sender: String?
    var muted: Bool
    var pinned: Bool
    var read: Bool
    var badge: String?
    var enabled: Bool
    var tag: String?
    var avatar: Avatar
    @Environment(\.rfTheme) private var theme
    @Environment(\.kitPreviewPressed) private var previewPressed
    @State private var holding = false

    public init(
        _ title: String,
        preview: String,
        time: String,
        sender: String? = nil,
        muted: Bool = false,
        pinned: Bool = false,
        read: Bool = false,
        badge: String? = nil,
        enabled: Bool = true,
        tag: String? = nil,
        action: @escaping () -> Void = {},
        @ViewBuilder avatar: () -> Avatar
    ) {
        self.title = title
        self.preview = preview
        self.time = time
        self.sender = sender
        self.muted = muted
        self.pinned = pinned
        self.read = read
        self.badge = badge
        self.enabled = enabled
        self.tag = tag
        self.action = action
        self.avatar = avatar()
    }

    public var body: some View {
        let pressed = enabled && (holding || previewPressed)
        HStack(spacing: KitMetrics.avatarGap) {
            avatar
            VStack(alignment: .leading, spacing: KitMetrics.summaryGap) {
                HStack(spacing: KitMetrics.bubbleGap) {
                    KitLabel(title, size: theme.size_mobile_body, weight: .semibold, color: theme.text, line: KitMetrics.lineTitle)
                    if muted { KitIcon(name: "bell-off", size: KitMetrics.metaIcon, tint: theme.secondary) }
                    Spacer(minLength: KitMetrics.bubbleGap)
                    if !time.isEmpty {
                        KitLabel(time, size: theme.size_mobile_caption, weight: .regular, color: theme.secondary, line: KitMetrics.lineTitle)
                    }
                }
                HStack(spacing: KitMetrics.bubbleGap) {
                    if read { KitIcon(name: "check-check", size: KitMetrics.metaIcon, tint: theme.secondary) }
                    if let sender, !sender.isEmpty {
                        KitLabel(sender, size: theme.size_body, weight: .regular, color: theme.text, line: KitMetrics.lineBody)
                    }
                    KitLabel(preview, size: theme.size_body, weight: .regular, color: theme.secondary, line: KitMetrics.lineBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let badge, !badge.isEmpty {
                        KitLabel(badge, size: theme.size_meta, weight: .semibold, color: theme.on_badge, line: KitMetrics.lineTitle)
                            .padding(.horizontal, KitMetrics.listBadgePad)
                            .frame(height: KitMetrics.listBadge)
                            .background(theme.badge, in: RoundedRectangle(cornerRadius: KitMetrics.listBadgeRadius))
                    }
                    if pinned { KitIcon(name: "pin", size: KitMetrics.metaIcon, tint: theme.secondary) }
                }
            }
            .padding(.trailing, KitMetrics.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .kitHairline(theme.line)
        }
        .padding(.leading, KitMetrics.gutter)
        .frame(maxWidth: .infinity)
        .frame(height: KitMetrics.conversation)
        .background(pressed ? theme.selected : .clear)
        .opacity(enabled ? 1 : KitMetrics.disabledAlpha)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if enabled { holding = true } }.onEnded { _ in holding = false; if enabled { action() } })
        .allowsHitTesting(enabled)
        .kitTag(tag)
    }
}
