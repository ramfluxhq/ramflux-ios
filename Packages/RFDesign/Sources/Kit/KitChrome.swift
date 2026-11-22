// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public struct KitHeaderAction {
    public var icon: String
    public var label: String
    public var action: () -> Void
    public init(icon: String, label: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label ?? icon
        self.action = action
    }
}

public struct KitTab {
    public var icon: String
    public var label: String
    public var latin: Bool
    public var badge: String?
    public var hitTag: String?
    public init(icon: String, label: String, latin: Bool = false, badge: String? = nil, hitTag: String? = nil) {
        self.icon = icon
        self.label = label
        self.latin = latin
        self.badge = badge
        self.hitTag = hitTag
    }
}

public struct KitStatusBar: View {
    var time: String
    var tag: String?
    @Environment(\.rfTheme) private var theme
    public init(time: String, tag: String? = nil) { self.time = time; self.tag = tag }
    public var body: some View {
        HStack {
            KitLabel(time, size: theme.size_body, weight: .semibold, color: theme.text, line: KitMetrics.lineBody, role: .latin, scales: false)
            Spacer(minLength: KitMetrics.statusGap)
            HStack(spacing: KitMetrics.statusGap) {
                KitIcon(name: "signal", size: KitMetrics.statusIcon, tint: theme.text)
                KitIcon(name: "wifi", size: KitMetrics.statusIcon, tint: theme.text)
                KitIcon(name: "battery-full", size: KitMetrics.statusBattery, tint: theme.text)
            }
        }
        .padding(.horizontal, KitMetrics.statusPad)
        .frame(maxWidth: .infinity, minHeight: KitMetrics.statusBar)
        .background(theme.bg)
        .kitTag(tag)
    }
}

public struct KitHomeIndicator: View {
    var tag: String?
    @Environment(\.rfTheme) private var theme
    public init(tag: String? = nil) { self.tag = tag }
    public var body: some View {
        Capsule()
            .fill(theme.text)
            .frame(width: KitMetrics.homeWidth, height: KitMetrics.homeHeight)
            .kitTag(tag)
    }
}

public struct KitPageHeader: View {
    var title: String
    var large: Bool
    var subtitle: String?
    var onBack: (() -> Void)?
    var onInfo: (() -> Void)?
    var actionLabel: String?
    var onAction: (() -> Void)?
    var actions: [KitHeaderAction]
    var latin: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(
        _ title: String,
        large: Bool = false,
        subtitle: String? = nil,
        onBack: (() -> Void)? = nil,
        onInfo: (() -> Void)? = nil,
        actionLabel: String? = nil,
        onAction: (() -> Void)? = nil,
        actions: [KitHeaderAction] = [],
        latin: Bool = false,
        tag: String? = nil
    ) {
        self.title = title
        self.large = large
        self.subtitle = subtitle
        self.onBack = onBack
        self.onInfo = onInfo
        self.actionLabel = actionLabel
        self.onAction = onAction
        self.actions = actions
        self.latin = latin
        self.tag = tag
    }

    public var body: some View {
        HStack(spacing: KitMetrics.headerGap) {
            if !large, let onBack {
                KitIconHit(icon: "chevron-left", size: KitMetrics.iconBack, tint: theme.text, label: RFDesignStrings.text("kit.back"), tag: tag.map { $0 + "-back" }, action: onBack)
            }
            VStack(alignment: .leading, spacing: 0) {
                if !title.isEmpty {
                    KitLabel(
                        title,
                        size: large ? theme.size_mobile_large_title : theme.size_title,
                        weight: large ? .bold : .semibold,
                        color: theme.text,
                        line: large ? KitMetrics.lineTight : KitMetrics.lineTitle,
                        role: latin ? .latin : .ui
                    )
                }
                if large, let subtitle, !subtitle.isEmpty {
                    KitLabel(subtitle, size: theme.size_meta, weight: .regular, color: theme.secondary, line: KitMetrics.lineTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !large, let onInfo {
                KitIconHit(icon: "info", size: KitMetrics.iconInfo, tint: theme.secondary, label: RFDesignStrings.text("kit.info"), tag: tag.map { $0 + "-info" }, action: onInfo)
            }
            if !large, let actionLabel, let onAction {
                KitHit(enabled: true, label: actionLabel, hitTag: tag.map { $0 + "-action" }, action: onAction) {
                    KitLabel(actionLabel, size: theme.size_body, weight: .semibold, color: theme.text, line: KitMetrics.lineBody)
                        .padding(.horizontal, KitMetrics.headerGap)
                        .frame(minHeight: KitMetrics.hit)
                }
            }
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                KitIconHit(icon: action.icon, size: KitMetrics.iconAction, tint: theme.text, label: action.label, action: action.action)
            }
        }
        .padding(.leading, KitMetrics.gutter)
        .padding(.trailing, large ? KitMetrics.headerGap : KitMetrics.gutter)
        .padding(.vertical, KitMetrics.summaryGap)
        .frame(maxWidth: .infinity, minHeight: KitMetrics.header)
        .background(theme.bg)
        .kitHairline(theme.line)
        .kitTag(tag)
    }
}

public struct KitChatHeader<Avatar: View>: View {
    var title: String
    var subtitle: String?
    var onBack: () -> Void
    var onCall: (() -> Void)?
    var onMore: (() -> Void)?
    var tag: String?
    var avatar: Avatar
    @Environment(\.rfTheme) private var theme

    public init(
        _ title: String,
        subtitle: String?,
        onBack: @escaping () -> Void,
        onCall: (() -> Void)? = nil,
        onMore: (() -> Void)? = nil,
        tag: String? = nil,
        @ViewBuilder avatar: () -> Avatar
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.onCall = onCall
        self.onMore = onMore
        self.tag = tag
        self.avatar = avatar()
    }

    public var body: some View {
        HStack(spacing: KitMetrics.headerGap) {
            KitIconHit(icon: "chevron-left", size: KitMetrics.iconBack, tint: theme.text, label: RFDesignStrings.text("kit.back"), tag: tag.map { $0 + "-back" }, action: onBack)
            avatar
            VStack(alignment: .leading, spacing: 0) {
                KitLabel(RFUntrustedText(title, kind: .identity).text, size: theme.size_mobile_body, weight: .semibold, color: theme.text, line: KitMetrics.lineTitle)
                if let subtitle, !subtitle.isEmpty {
                    KitLabel(subtitle, size: theme.size_meta, weight: .regular, color: theme.secondary, line: KitMetrics.lineTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onCall { KitIconHit(icon: "phone", size: KitMetrics.iconBack, tint: theme.text, label: RFDesignStrings.text("kit.call"), action: onCall) }
            if let onMore { KitIconHit(icon: "ellipsis", size: KitMetrics.iconBack, tint: theme.text, label: RFDesignStrings.text("kit.more"), action: onMore) }
        }
        .padding(.horizontal, KitMetrics.gutter)
        .padding(.vertical, KitMetrics.headerPadV)
        .frame(maxWidth: .infinity, minHeight: KitMetrics.header)
        .background(theme.bg)
        .kitHairline(theme.line)
        .kitTag(tag)
    }
}

public struct KitTabBar: View {
    var tabs: [KitTab]
    var selected: Int
    var onSelect: (Int) -> Void
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(tabs: [KitTab], selected: Int, onSelect: @escaping (Int) -> Void, tag: String? = nil) {
        self.tabs = tabs
        self.selected = selected
        self.onSelect = onSelect
        self.tag = tag
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    let on = index == selected
                    let tint = on ? theme.text : theme.secondary
                    KitHit(enabled: true, label: tab.label, hitTag: tab.hitTag ?? tag.map { "\($0)-\(index)" }, selected: on, action: { onSelect(index) }) {
                        VStack(spacing: KitMetrics.tabGap) {
                            ZStack(alignment: .topTrailing) {
                                KitIcon(name: tab.icon, size: KitMetrics.tabIcon, tint: tint)
                                if let badge = tab.badge {
                                    KitLabel(badge, size: theme.size_mobile_caption, weight: .semibold, color: theme.on_badge, line: KitMetrics.lineTitle)
                                        .padding(.horizontal, KitMetrics.tabBadgePad)
                                        .frame(minWidth: KitMetrics.tabBadgeMin, minHeight: KitMetrics.tabBadge)
                                        .background(theme.badge, in: RoundedRectangle(cornerRadius: theme.radius_md))
                                        .alignmentGuide(.trailing) { $0[.trailing] - KitMetrics.badgeX }
                                        .alignmentGuide(.top) { $0[.top] - KitMetrics.badgeY }
                                }
                            }
                            .frame(width: KitMetrics.tabIcon, height: KitMetrics.tabIcon)
                            KitLabel(
                                tab.label,
                                size: theme.size_mobile_caption,
                                weight: on ? .semibold : .medium,
                                color: tint,
                                line: KitMetrics.lineTitle,
                                role: tab.latin ? .latin : .ui
                            )
                        }
                        .frame(maxWidth: .infinity, minHeight: KitMetrics.tab)
                    }
                    .frame(maxWidth: .infinity, minHeight: KitMetrics.hit)
                }
            }
            .padding(.top, KitMetrics.tabPadTop)
        }
        .frame(maxWidth: .infinity, minHeight: KitMetrics.tabBar, alignment: .top)
        .background(theme.bg)
        .kitHairline(theme.line, top: true)
        .kitTag(tag)
    }
}
