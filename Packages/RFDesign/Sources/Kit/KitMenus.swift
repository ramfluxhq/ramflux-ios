// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public struct KitMenuEntry {
    public var label: String
    public var icon: String
    public var danger: Bool
    public var groupBefore: Bool
    public init(label: String, icon: String, danger: Bool = false, groupBefore: Bool = false) {
        self.label = label
        self.icon = icon
        self.danger = danger
        self.groupBefore = groupBefore
    }
}

public struct KitContextMenu: View {
    var entries: [KitMenuEntry]
    var onSelect: (Int) -> Void
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(entries: [KitMenuEntry], onSelect: @escaping (Int) -> Void = { _ in }, tag: String? = nil) {
        self.entries = entries
        self.onSelect = onSelect
        self.tag = tag
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius_menu)
        VStack(spacing: 0) {
            let groups = menuGroups
            ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                if groupIndex > 0 { Rectangle().fill(theme.line).frame(height: KitMetrics.stroke) }
                let start = group.first?.offset ?? 0
                VStack(spacing: 0) {
                    ForEach(Array(group.enumerated()), id: \.offset) { index, item in
                        MenuRow(entry: item.entry, hairline: index < group.count - 1, hitTag: "menu-hit-\(start)-\(index)", action: { onSelect(item.offset) })
                    }
                }
            }
        }
        .frame(minWidth: KitMetrics.menu, idealWidth: KitMetrics.menu, maxWidth: KitMetrics.menu)
        .background(theme.overlay, in: shape)
        .overlay { shape.strokeBorder(theme.overlay_border, lineWidth: KitMetrics.stroke) }
        .kitTag(tag)
    }

    private var menuGroups: [[(offset: Int, entry: KitMenuEntry)]] {
        var groups: [[(offset: Int, entry: KitMenuEntry)]] = []
        var current: [(offset: Int, entry: KitMenuEntry)] = []
        for (offset, entry) in entries.enumerated() {
            if entry.groupBefore && !current.isEmpty {
                groups.append(current)
                current = []
            }
            current.append((offset, entry))
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}

private struct MenuRow: View {
    var entry: KitMenuEntry
    var hairline: Bool
    var hitTag: String
    var action: () -> Void
    @Environment(\.rfTheme) private var theme
    @Environment(\.kitPreviewPressed) private var previewPressed
    @State private var holding = false
    var body: some View {
        let tint = entry.danger ? theme.danger : theme.text
        KitHit(enabled: true, label: entry.label, hitTag: hitTag, onPress: { holding = $0 }, action: action) {
            HStack(spacing: KitMetrics.headerGap) {
                KitLabel(entry.label, size: theme.size_mobile_body, weight: .regular, color: tint, line: KitMetrics.lineTitle, lines: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                KitIcon(name: entry.icon, size: KitMetrics.menuIcon, tint: tint)
            }
            .padding(.horizontal, KitMetrics.menuPad)
            .padding(.vertical, KitMetrics.tagPadV)
            .frame(maxWidth: .infinity, minHeight: KitMetrics.menuItem)
            .background((holding || previewPressed) ? theme.selected : .clear)
            .kitHairline(hairline ? theme.line : .clear)
        }
    }
}

public struct KitReactionBar: View {
    var reactions: [String]
    var onReaction: (Int) -> Void
    var onMore: () -> Void
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(reactions: [String], onReaction: @escaping (Int) -> Void = { _ in }, onMore: @escaping () -> Void = {}, tag: String? = nil) {
        self.reactions = reactions
        self.onReaction = onReaction
        self.onMore = onMore
        self.tag = tag
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius_menu)
        HStack(spacing: KitMetrics.reactionGap) {
            ForEach(Array(reactions.enumerated()), id: \.offset) { index, reaction in
                KitHit(enabled: true, label: reaction, hitTag: tag.map { "\($0)-\(index)" }, action: { onReaction(index) }) {
                    KitLabel(reaction, size: theme.size_page, weight: .regular, color: theme.text, line: KitMetrics.lineTitle, scales: false)
                        .frame(width: KitMetrics.reactionCell, height: KitMetrics.reaction)
                        .kitTag(tag.map { "\($0)-cell-\(index)" })
                }
            }
            KitHit(enabled: true, label: RFDesignStrings.text("kit.more"), hitTag: tag.map { $0 + "-more" }, action: onMore) {
                KitIcon(name: "plus", size: KitMetrics.moreIcon, tint: theme.text)
                    .frame(width: KitMetrics.reactionCell, height: KitMetrics.reaction)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_xs))
                    .kitTag(tag.map { $0 + "-more-cell" })
            }
        }
        .padding(.horizontal, KitMetrics.reactionPad)
        .frame(minHeight: KitMetrics.reaction)
        .background(theme.overlay, in: shape)
        .overlay { shape.strokeBorder(theme.overlay_border, lineWidth: KitMetrics.stroke) }
        .kitTag(tag)
    }
}

public struct KitDateChip: View {
    var label: String
    var tag: String?
    @Environment(\.rfTheme) private var theme
    public init(_ label: String, tag: String? = nil) { self.label = label; self.tag = tag }
    public var body: some View {
        KitLabel(label, size: theme.size_meta, weight: .medium, color: theme.secondary, line: KitMetrics.lineTitle, lines: nil)
            .multilineTextAlignment(.center)
            .padding(.horizontal, KitMetrics.chipPadH)
            .padding(.vertical, KitMetrics.chipPadV)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_chip))
            .frame(maxWidth: .infinity)
            .padding(.vertical, KitMetrics.datePadV)
            .kitTag(tag)
    }
}

public struct KitUnreadDivider: View {
    var label: String
    var tag: String?
    @Environment(\.rfTheme) private var theme
    public init(_ label: String, tag: String? = nil) { self.label = label; self.tag = tag }
    public var body: some View {
        HStack(spacing: KitMetrics.unreadGap) {
            Rectangle().fill(theme.line_strong).frame(height: KitMetrics.unreadLine)
            KitLabel(label, size: theme.size_meta, weight: .semibold, color: theme.text, line: KitMetrics.lineTitle, lines: nil)
                .multilineTextAlignment(.center)
                .layoutPriority(1)
            Rectangle().fill(theme.line_strong).frame(height: KitMetrics.unreadLine)
        }
        .frame(maxWidth: .infinity, minHeight: KitMetrics.unread)
        .kitTag(tag)
    }
}
