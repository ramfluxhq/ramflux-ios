// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
@testable import RFDesign

struct KitBoard {
    var name: String
    var width: CGFloat?
    var dark = false
    var pressed = false
    var body: AnyView
}

@MainActor
enum KitCatalog {
    static func boards() -> [KitBoard] {
        var items = light()
        let darkNames: Set<String> = [
            "avatar--person", "avatar--agent", "bubble--own", "bubble--incoming", "bubble--file",
            "button--primary", "button--secondary", "button--text",
            "chat-header--default", "composer--default", "context-menu--default", "date-chip--default",
            "home-indicator--default", "list-row-conversation--default", "mono-block--default",
            "page-header--default", "page-header--large-title", "reaction-bar--default", "row--default",
            "search-field--default", "segmented--default", "sheet--default", "status-bar--default",
            "status-hero--default", "tab-bar--default", "text-field--default", "tip-bar--default",
            "unread-divider--default", "qr-placeholder--default",
        ]
        items += items.compactMap { item in
            guard darkNames.contains(item.name) else { return nil }
            var copy = item
            copy.name += "--dark"
            copy.dark = true
            return copy
        }
        items += states()
        return items
    }

    private static func light() -> [KitBoard] {
        let tabs = messageTabs(badge: "1")
        return [
            item("button--primary", 361) { KitButton("按钮", action: {}) },
            item("button--secondary", 361) { KitButton("按钮", action: {}, kind: .secondary) },
            item("button--destructive", 361) { KitButton("按钮", action: {}, kind: .destructive) },
            item("button--disabled", 361) { KitButton("按钮", action: {}, kind: .disabled) },
            item("button--text", 361) { KitButton("文字按钮", action: {}, kind: .text) },
            item("avatar--person") { KitAvatar("林", size: 28, kind: .person) },
            item("avatar--person-small-18") { KitAvatar("林", size: 18, kind: .person) },
            item("avatar--agent") { KitAvatar("", size: 28, kind: .agent) },
            item("avatar--agent-gem") { KitAvatar("", size: 18, kind: .agent, icon: "gem") },
            item("avatar--agent-orbit-small") { KitAvatar("", size: 44, kind: .agent) },
            item("switch--on") { KitSwitch(checked: true) },
            item("switch--off") { KitSwitch(checked: false) },
            item("checkbox--on") { KitCheckbox(checked: true) },
            item("checkbox--off") { KitCheckbox(checked: false) },
            item("segmented--default", 361) { KitSegmented(labels: ["扫描二维码", "对比号码"], selected: 0) },
            item("status-bar--default", 393) { KitStatusBar(time: "9:41") },
            item("home-indicator--default") { KitHomeIndicator() },
            item("page-header--default", 393) { KitPageHeader("页面标题", onBack: {}) },
            item("page-header--info-action", 393) { KitPageHeader("自定义节点", onBack: {}, onInfo: {}) },
            item("page-header--no-back", 393) { KitPageHeader("来电") },
            item("page-header--no-back-no-title", 393) { KitPageHeader("") },
            item("page-header--large-title", 393) {
                KitPageHeader("消息", large: true, subtitle: "林澈 · 当前账号", actions: [
                    KitHeaderAction(icon: "square-pen", action: {}),
                    KitHeaderAction(icon: "ellipsis", action: {}),
                ])
            },
            item("page-header--large-title-plus-ellipsis", 393) {
                KitPageHeader("Agents", large: true, actions: [
                    KitHeaderAction(icon: "ellipsis", action: {}),
                    KitHeaderAction(icon: "plus", action: {}),
                ], latin: true)
            },
            item("page-header--large-title-single-action", 393) {
                KitPageHeader("更多", large: true, actions: [KitHeaderAction(icon: "ellipsis", action: {})])
            },
            item("chat-header--default", 393) {
                KitChatHeader("周宁", subtitle: "私人会话", onBack: {}, onMore: {}) { KitAvatar("周", size: 36, kind: .person) }
            },
            item("chat-header--agent", 393) {
                KitChatHeader("Nova", subtitle: nil, onBack: {}, onMore: {}) { KitAvatar("", size: 36, kind: .agent) }
            },
            item("chat-header--channel", 393) {
                KitChatHeader("#general", subtitle: "产品探索 · 3 位成员", onBack: {}, onMore: {}) { KitAvatar("", size: 36, kind: .channel) }
            },
            item("chat-header--no-more", 393) {
                KitChatHeader("陆尧", subtitle: "私人会话", onBack: {}) { KitAvatar("陆", size: 36, kind: .person) }
            },
            item("tab-bar--default", 393) { KitTabBar(tabs: tabs, selected: 0, onSelect: { _ in }) },
            item("tab-bar--messages-selected-badge", 393) { KitTabBar(tabs: tabs, selected: 0, onSelect: { _ in }) },
            item("tab-bar--messages-selected-no-badge", 393) { KitTabBar(tabs: messageTabs(badge: nil), selected: 0, onSelect: { _ in }) },
            item("tab-bar--groups-selected", 393) { KitTabBar(tabs: tabs, selected: 1, onSelect: { _ in }) },
            item("tab-bar--agents-selected", 393) { KitTabBar(tabs: tabs, selected: 2, onSelect: { _ in }) },
            item("tab-bar--more-selected", 393) { KitTabBar(tabs: tabs, selected: 3, onSelect: { _ in }) },
            item("search-field--default", 361) { KitSearchField(value: .constant(""), placeholder: "搜索") },
            item("search-field--query", 361) { KitSearchField(value: .constant("@zhouning@node.example.org"), placeholder: "搜索", showsClear: false) },
            item("search-field--query-with-clear", 309) { KitSearchField(value: .constant("@zhouning@node.example.org"), placeholder: "搜索") },
            item("text-field--default", 361) { KitTextField(value: .constant("输入内容"), label: "标签") },
            item("text-field--placeholder", 361) { KitTextField(value: .constant(""), label: "第 11 个词", placeholder: "输入单词") },
            item("text-field--focused", 361) { KitTextField(value: .constant(String(repeating: "•", count: 14)), label: "再次输入数据口令", focused: true) },
            item("text-field--disabled", 361) { KitTextField(value: .constant("maple"), label: "第 7 个词", enabled: false) },
            item("text-field--error", 361) { KitTextField(value: .constant("garlic"), label: "第 14 个词", error: "这个词与你的恢复短语不一致。") },
            item("text-field--error-message", 361) { KitTextField(value: .constant("林澈"), label: "显示名称", note: "此名称用于新账号，之后可以修改。") },
            item("row--default", 361) { KitRow("标题", icon: "user-round", value: "说明", tagLabel: "网页") },
            item("row--tag", 361) {
                KitRow("Chrome · macOS", icon: "globe", value: "chat.example.org · 此节点的运营方可以读取这台设备上的消息。", tagLabel: "网页")
            },
            item("row--selected-check", 361) { KitRow("Ramflux 官方节点", icon: "server", value: "默认节点 · 已选择", trailing: .check) },
            item("icon-tile--default") { KitIconTile(icon: "user-round") },
            item("info-button--default") { KitInfoButton(action: {}) },
            item("list-row-conversation--default", 393) { conversation("林", "林悦", "好的，附件里的版本说明也请一起看。", "10:24") },
            item("list-row-conversation--unread-badge", 393) { conversation("林", "林悦", "好的，附件里的版本说明也请一起看。", "10:24", badge: "1") },
            item("list-row-conversation--agent", 393) {
                KitConversationRow("Nova", preview: "协作设置已确认", time: "09:42") { KitAvatar("", size: 52, kind: .agent) }
            },
            item("list-row-conversation--channel-pinned", 393) {
                KitConversationRow("产品探索", preview: "你：收到，稍后一起看。", time: "10:23", pinned: true) { KitAvatar("", size: 52, kind: .channel) }
            },
            item("list-row-conversation--muted-group-badge", 393) {
                KitConversationRow("团队公告", preview: "本周安排与文档", time: "周二", muted: true, badge: "5") {
                    KitAvatar("", size: 52, kind: .person, icon: "users-round")
                }
            },
            item("list-row-conversation--read-tick", 393) {
                KitConversationRow("周宁", preview: "好的，明天继续。", time: "昨天", read: true) { KitAvatar("周", size: 52, kind: .person) }
            },
            item("list-row-conversation--search-result", 393) {
                KitConversationRow("陌生人", preview: "3 位非联系人的消息", time: "", badge: "3") {
                    KitAvatar("", size: 52, kind: .person, icon: "user-round-search")
                }
            },
            item("bubble--own", 260) { KitBubble("收到，我会把问题逐项回复。", time: "10:23", maxWidth: 260) },
            item("bubble--incoming", 260) { KitBubble("新版资料我整理好了，你有空时看一下。", kind: .incoming, time: "10:21", maxWidth: 260) },
            item("bubble--file") { KitBubble("", kind: .file, time: "10:24", fileName: "版本说明.pdf", fileMeta: "PDF") },
            item("bubble--own-meta-time-ticks", 300) { KitBubble("帮我整理研究资料，归纳重点并标出需要我确认的事项。", time: "10:24", read: true, maxWidth: 300) },
            item("bubble--own-no-meta", 276) { KitBubble("我已查看，稍后补充修改意见。", failed: true, maxWidth: 276) },
            item("bubble--own-pending-clock", 260) { KitBubble("好的，我下午把修改意见发你。", time: "待发送", pending: true, maxWidth: 260) },
            item("bubble--own-transient-opacity0", 316) { KitBubble("收到，我会把问题逐项回复。", transient: true, maxWidth: 316) },
            item("bubble--incoming-group-sender-agent-tag", 290) {
                KitBubble("这里先归纳资料，再把需要确认的内容放进线程。", kind: .incoming, time: "10:21", sender: "Nova", agentTag: "Agent", maxWidth: 290)
            },
            item("composer--default", 393) { KitComposer(value: .constant(""), placeholder: "发消息…") },
            item("composer--attach-disabled", 393) { KitComposer(value: .constant(""), placeholder: "发消息…", attachEnabled: false) },
            item("composer--mode-chip", 393) { KitComposer(value: .constant(""), placeholder: "向 Nova 提出请求…", mode: "请求 Nova") },
            item("composer--mode-chip-send-active", 393) { KitComposer(value: .constant(""), placeholder: "向 Nova 提出请求…", sendActive: true, mode: "请求 Nova") },
            item("composer--option-row-send-active", 393) { KitComposer(value: .constant(""), placeholder: "发消息…", sendActive: true, option: "同时发送到 #general") },
            item("composer--reply-attachment-send-active", 393) {
                KitComposer(
                    value: .constant(""),
                    placeholder: "发消息…",
                    sendActive: true,
                    replyAuthor: "回复 林悦",
                    replyExcerpt: "附件里的版本说明也请一起看。",
                    onCloseReply: {},
                    attachmentName: "版本说明.pdf",
                    attachmentState: "待发送",
                    onRemoveAttachment: {}
                )
            },
            item("date-chip--default", 361) { KitDateChip("今天") },
            item("unread-divider--default", 361) { KitUnreadDivider("以下为未读消息") },
            item("reaction-bar--default", 320) { KitReactionBar(reactions: ["👍", "❤️", "😂", "😮", "😢", "🙏"]) },
            item("context-menu--default") { KitContextMenu(entries: menu(restricted: false)) },
            item("context-menu--restricted") { KitContextMenu(entries: menu(restricted: true)) },
            item("sheet--default", 393) { KitSheet("标题", body: "说明", closeLabel: "知道了") },
            item("sheet--no-close", 393) { linkSheet },
            item("tip-bar--default", 361) { KitTipBar("当前离线 · 消息将在恢复连接后发送", icon: "wifi-off") },
            item("tip-bar--loading", 361) { KitTipBar("等待在已有设备上批准…", icon: "loader-circle", loading: true) },
            item("tip-bar--offline-retry", 361) { KitTipBar("当前离线 · 显示上次同步的内容", icon: "wifi-off", action: "重试", onAction: {}) },
            item("tip-bar--shield-action", 369) { KitTipBar("安全号码尚未核对", icon: "shield", action: "核对", onAction: {}) },
            item("tip-bar--timer", 361) { KitTipBar("剩余 4:36 · 时间到后需要重新开始", icon: "timer") },
            item("security-warning--warning", 361) { KitSecurityWarning(warnTitle, body: warnBody, tone: .warning) },
            item("security-warning--danger", 361) { KitSecurityWarning(warnTitle, body: warnBody, tone: .danger) },
            item("security-warning--danger-alert", 361) {
                KitSecurityWarning("第 14 个词不匹配", body: "不会显示正确的词。请对照你抄写的短语，重新输入第 14 个词。", tone: .danger, icon: "circle-alert")
            },
            item("status-hero--default") { KitStatusHero(icon: "loader-circle") },
            item("status-hero--success") { KitStatusHero(icon: "check", tint: RFDesign.light.success, fill: RFDesign.light.success_bg) },
            item("status-hero--success-shield") { KitStatusHero(icon: "shield-check", tint: RFDesign.light.success, fill: RFDesign.light.success_bg) },
            item("status-hero--neutral-user-search") { KitStatusHero(icon: "user-round-search") },
            item("status-hero--danger") { KitStatusHero(icon: "circle-alert", tint: RFDesign.light.danger, fill: RFDesign.light.danger_bg) },
            item("status-hero--warning-timeout") { KitStatusHero(icon: "timer-off", tint: RFDesign.light.warning, fill: RFDesign.light.warning_bg) },
            item("status-hero--warning-offline") { KitStatusHero(icon: "wifi-off", tint: RFDesign.light.warning, fill: RFDesign.light.warning_bg) },
            item("approval-card--default") { approval },
            item("mono-block--default", 361) { KitMonoBlock("A1B2 C3D4 E5F6 0718 293A\nB4C5 D6E7 F809 1A2B 3C4D") },
            item("pairing-code--default", 361) { KitPairingCode("4821 7730") },
            item("qr-placeholder--default") { KitQrPlaceholder() },
        ]
    }

    private static func states() -> [KitBoard] {
        [
            item("button--primary--pressed", 361, pressed: true) { KitButton("按钮", action: {}) },
            item("button--primary--focused", 361) { KitButton("按钮", action: {}, focused: true) },
            item("button--primary--loading", 361) { KitButton("按钮", action: {}, loading: true) },
            item("button--primary--en", 361) { KitButton("Continue", action: {}) },
            item("button--primary--zh", 361) { KitButton("按钮", action: {}) },
            item("page-header--default--en", 393) { KitPageHeader("Title", onBack: {}) },
            item("page-header--default--zh", 393) { KitPageHeader("页面标题", onBack: {}) },
            item("row--default--en", 361) { KitRow("Title", icon: "user-round", value: "Detail", tagLabel: "Web") },
            item("row--default--zh", 361) { KitRow("标题", icon: "user-round", value: "说明", tagLabel: "网页") },
            item("row--default--pressed", 361, pressed: true) { KitRow("标题", icon: "user-round", value: "说明", tagLabel: "网页") },
            item("bubble--own--en", 260) { KitBubble("Received. I will answer each point.", time: "10:23", maxWidth: 260) },
            item("tab-bar--messages-selected-badge--en", 393) { KitTabBar(tabs: messageTabs(badge: "1"), selected: 0, onSelect: { _ in }) },
            item("search-field--focused", 361) { KitSearchField(value: .constant(""), placeholder: "搜索", focused: true) },
        ]
    }

    private static func item(_ name: String, _ width: CGFloat? = nil, pressed: Bool = false, @ViewBuilder body: () -> some View) -> KitBoard {
        KitBoard(name: name, width: width, pressed: pressed, body: AnyView(body()))
    }

    private static func messageTabs(badge: String?) -> [KitTab] {
        [
            KitTab(icon: "messages-square", label: "消息", badge: badge),
            KitTab(icon: "users-round", label: "群组"),
            KitTab(icon: "bot", label: "Agents", latin: true),
            KitTab(icon: "ellipsis", label: "更多"),
        ]
    }

    private static func conversation(_ initial: String, _ title: String, _ preview: String, _ time: String, badge: String? = nil) -> some View {
        KitConversationRow(title, preview: preview, time: time, badge: badge) { KitAvatar(initial, size: 52, kind: .person) }
    }

    private static func menu(restricted: Bool) -> [KitMenuEntry] {
        var entries = [
            KitMenuEntry(label: "回复", icon: "reply"),
            KitMenuEntry(label: "复制", icon: "copy"),
            KitMenuEntry(label: "编辑", icon: "pencil"),
        ]
        if !restricted {
            entries += [
                KitMenuEntry(label: "转发", icon: "forward"),
                KitMenuEntry(label: "置顶", icon: "pin"),
                KitMenuEntry(label: "选择", icon: "list-checks"),
            ]
        }
        entries.append(KitMenuEntry(label: "删除", icon: "trash-2", danger: true, groupBefore: true))
        return entries
    }

    private static var warnTitle: String { "网页会话不受节点运营方的防护" }
    private static var warnBody: String { "该节点的运营方可以读取这台网页设备上的密钥和消息明文。" }

    private static var approval: some View {
        KitApprovalCard(
            requester: "Luma · Agent",
            status: "等待你的决定",
            title: "读取「研究资料」文件夹",
            scopeLabel: "本次请求的范围",
            scopeDetail: "工具：文件读取 · 只读 · 仅作用于这一次请求。",
            decline: "拒绝",
            approve: "允许"
        )
    }

    private static var linkSheet: some View {
        KitSheet("批准关联网页设备？", body: "Chrome · macOS · 网页设备，不保存主密钥和恢复密钥。", closeLabel: "", showClose: false) {
            VStack(alignment: .leading, spacing: KitMetrics.sheetGap) {
                VStack(alignment: .leading, spacing: KitMetrics.summaryGap) {
                    HStack(spacing: KitMetrics.headerGap) {
                        KitIcon(name: "globe", size: KitMetrics.securityIcon, tint: RFDesign.light.secondary)
                        KitLabel("正在关联的来源", size: 13, weight: .regular, color: RFDesign.light.secondary, line: KitMetrics.lineSecondary)
                    }
                    KitLabel("https://chat.example.org", size: 17, weight: .semibold, color: RFDesign.light.text, line: KitMetrics.lineTitle)
                    KitLabel("确认它与那个浏览器地址栏显示的地址完全一致，否则请拒绝。", size: 13, weight: .regular, color: RFDesign.light.secondary, line: KitMetrics.lineSecondary, lines: nil)
                }
                .padding(KitMetrics.securityPad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RFDesign.light.surface, in: RoundedRectangle(cornerRadius: RFDesign.light.radius_md))
                .overlay { RoundedRectangle(cornerRadius: RFDesign.light.radius_md).strokeBorder(RFDesign.light.line, lineWidth: KitMetrics.stroke) }
                KitSecurityWarning(warnTitle, body: "该节点的运营方可以读取这台网页设备上的密钥和消息明文。网页设备可随时在「设置 › 设备」中撤销。", tone: .warning)
                KitButton("批准关联", action: {})
                KitButton("拒绝", action: {}, kind: .secondary)
            }
        }
    }
}
