// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public enum KitWarningTone { case warning, danger }

public struct KitSheet<Extra: View>: View {
    var title: String
    var bodyText: String
    var closeLabel: String
    var onClose: () -> Void
    var showClose: Bool
    var extra: Extra
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(
        _ title: String,
        body: String,
        closeLabel: String,
        onClose: @escaping () -> Void = {},
        showClose: Bool = true,
        tag: String? = nil,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) {
        self.title = title
        self.bodyText = body
        self.closeLabel = closeLabel
        self.onClose = onClose
        self.showClose = showClose
        self.extra = extra()
        self.tag = tag
    }

    public var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: theme.radius_sheet, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: theme.radius_sheet)
        VStack(spacing: KitMetrics.sheetGap) {
            Capsule().fill(theme.line_strong).frame(width: KitMetrics.grabberWidth, height: KitMetrics.grabberHeight)
            KitLabel(title, size: theme.size_mobile_body, weight: .semibold, color: theme.text, line: KitMetrics.lineBody, lines: nil)
                .multilineTextAlignment(.center)
            KitLabel(bodyText, size: theme.size_body, weight: .regular, color: theme.text, line: KitMetrics.lineBody, lines: nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            extra
            if showClose { KitButton(closeLabel, action: onClose, kind: .secondary) }
        }
        .padding(.horizontal, KitMetrics.sheetPadH)
        .padding(.top, KitMetrics.sheetPadTop)
        .padding(.bottom, KitMetrics.sheetPadBottom)
        .frame(maxWidth: .infinity)
        .background(theme.overlay, in: shape)
        .overlay { shape.strokeBorder(theme.overlay_border, lineWidth: KitMetrics.stroke) }
        .shadow(color: theme.shadow, radius: KitMetrics.shadowBlur)
        .kitTag(tag)
    }
}

public struct KitTipBar: View {
    var text: String
    var icon: String
    var actionTitle: String?
    var onAction: (() -> Void)?
    var loading: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(_ text: String, icon: String, action: String? = nil, onAction: (() -> Void)? = nil, loading: Bool = false, tag: String? = nil) {
        self.text = text
        self.icon = icon
        self.actionTitle = action
        self.onAction = onAction
        self.loading = loading
        self.tag = tag
    }

    public var body: some View {
        HStack(spacing: KitMetrics.tipGap) {
            if loading { KitSpinner(size: KitMetrics.tipIcon, tint: theme.secondary) } else { KitIcon(name: icon, size: KitMetrics.tipIcon, tint: theme.secondary) }
            KitLabel(text, size: theme.size_secondary, weight: .regular, color: theme.text, line: KitMetrics.lineSecondary, lines: nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let onAction {
                KitLabel(actionTitle, size: theme.size_secondary, weight: .semibold, color: theme.text, line: KitMetrics.lineSecondary, lines: nil)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onAction)
            }
        }
        .padding(.horizontal, KitMetrics.tipPadH)
        .padding(.vertical, KitMetrics.tipPadV)
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_card))
        .kitTag(tag)
    }
}

public struct KitSecurityWarning: View {
    var title: String
    var bodyText: String
    var tone: KitWarningTone
    var icon: String?
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(_ title: String, body: String, tone: KitWarningTone, icon: String? = nil, tag: String? = nil) {
        self.title = title
        self.bodyText = body
        self.tone = tone
        self.icon = icon
        self.tag = tag
    }

    public var body: some View {
        let danger = tone == .danger
        HStack(alignment: .top, spacing: KitMetrics.securityGap) {
            KitIcon(name: icon ?? (danger ? "shield-alert" : "triangle-alert"), size: KitMetrics.securityIcon, tint: danger ? theme.danger : theme.warning)
            VStack(alignment: .leading, spacing: KitMetrics.bubbleGap) {
                KitLabel(title, size: theme.size_body, weight: .semibold, color: theme.text, line: KitMetrics.lineBubble, lines: nil)
                KitLabel(bodyText, size: theme.size_secondary, weight: .regular, color: theme.text, line: 1.5, lines: nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(KitMetrics.securityPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((danger ? theme.danger_bg : theme.warning_bg), in: RoundedRectangle(cornerRadius: theme.radius_card))
        .kitTag(tag)
    }
}

public struct KitStatusHero: View {
    var icon: String
    var tint: Color?
    var fill: Color?
    var tag: String?
    @Environment(\.rfTheme) private var theme
    public init(icon: String, tint: Color? = nil, fill: Color? = nil, tag: String? = nil) {
        self.icon = icon
        self.tint = tint
        self.fill = fill
        self.tag = tag
    }
    public var body: some View {
        KitIcon(name: icon, size: KitMetrics.heroGlyph, tint: tint ?? theme.secondary)
            .frame(width: KitMetrics.hero, height: KitMetrics.hero)
            .background(fill ?? theme.surface, in: RoundedRectangle(cornerRadius: KitMetrics.heroRadius))
            .kitTag(tag)
    }
}

public struct KitApprovalCard: View {
    var requester: String
    var status: String
    var title: String
    var scopeLabel: String
    var scopeDetail: String
    var decline: String
    var approve: String
    var onDecline: () -> Void
    var onApprove: () -> Void
    var result: String?
    var actions: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(
        requester: String,
        status: String,
        title: String,
        scopeLabel: String,
        scopeDetail: String,
        decline: String,
        approve: String,
        onDecline: @escaping () -> Void = {},
        onApprove: @escaping () -> Void = {},
        result: String? = nil,
        actions: Bool = true,
        tag: String? = nil
    ) {
        self.requester = requester
        self.status = status
        self.title = title
        self.scopeLabel = scopeLabel
        self.scopeDetail = scopeDetail
        self.decline = decline
        self.approve = approve
        self.onDecline = onDecline
        self.onApprove = onApprove
        self.result = result
        self.actions = actions
        self.tag = tag
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KitMetrics.approvalGap) {
            HStack(spacing: KitMetrics.headerGap) {
                KitAvatar("", size: KitMetrics.approvalAvatar, kind: .agent)
                KitLabel(requester, size: theme.size_secondary, weight: .regular, color: theme.secondary, line: KitMetrics.lineSecondary, lines: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                KitLabel(status, size: theme.size_meta, weight: .regular, color: theme.text, line: KitMetrics.lineTitle, lines: nil)
                    .padding(.horizontal, KitMetrics.tagPadH)
                    .padding(.vertical, KitMetrics.tagPadV)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_chip))
            }
            KitLabel(title, size: theme.size_mobile_body, weight: .semibold, color: theme.text, line: KitMetrics.lineBody, lines: nil)
            VStack(alignment: .leading, spacing: KitMetrics.summaryGap) {
                KitLabel(scopeLabel, size: theme.size_secondary, weight: .medium, color: theme.text, line: KitMetrics.lineSecondary, lines: nil)
                KitLabel(scopeDetail, size: theme.size_secondary, weight: .regular, color: theme.secondary, line: KitMetrics.lineSecondary, lines: nil)
            }
            .padding(KitMetrics.scopePad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
            if let result, !result.isEmpty {
                KitLabel(result, size: theme.size_secondary, weight: .regular, color: theme.secondary, line: KitMetrics.lineSecondary, lines: nil)
            }
            if actions {
                HStack(spacing: KitMetrics.headerGap) {
                    KitButton(decline, action: onDecline, kind: .secondary, size: .compact)
                    KitButton(approve, action: onApprove, size: .compact)
                }
            }
        }
        .padding(KitMetrics.approvalPad)
        .frame(idealWidth: KitMetrics.approvalMax, maxWidth: KitMetrics.approvalMax, alignment: .leading)
        .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_card))
        .overlay { RoundedRectangle(cornerRadius: theme.radius_card).strokeBorder(theme.line, lineWidth: KitMetrics.stroke) }
        .kitTag(tag)
    }
}

public struct KitMonoBlock: View {
    var value: String
    var onCopy: () -> Void
    var tag: String?
    @Environment(\.rfTheme) private var theme
    public init(_ value: String, onCopy: @escaping () -> Void = {}, tag: String? = nil) {
        self.value = value
        self.onCopy = onCopy
        self.tag = tag
    }
    public var body: some View {
        HStack(spacing: KitMetrics.bubbleGap) {
            KitLabel(value, size: theme.size_body, weight: .regular, color: theme.text, line: KitMetrics.lineBody, role: .mono, lines: nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            KitIconHit(icon: "copy", size: KitMetrics.iconInfo, tint: theme.secondary, label: RFDesignStrings.text("kit.copy"), action: onCopy)
        }
        .padding(.leading, KitMetrics.monoPadStart)
        .padding(.trailing, KitMetrics.monoPadEnd)
        .padding(.top, KitMetrics.monoPadTop)
        .padding(.bottom, KitMetrics.monoPadBottom)
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
        .kitTag(tag)
    }
}

public struct KitPairingCode: View {
    var code: String
    var tag: String?
    @Environment(\.rfTheme) private var theme
    public init(_ code: String, tag: String? = nil) { self.code = code; self.tag = tag }
    public var body: some View {
        KitLabel(code, size: KitMetrics.pairingSize, weight: .semibold, color: theme.text, line: KitMetrics.lineTitle, role: .mono, tracking: KitMetrics.pairingTrack)
            .frame(maxWidth: .infinity, minHeight: KitMetrics.pairing)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
            .kitTag(tag)
    }
}

public struct KitQrPlaceholder: View {
    var tag: String?
    public init(tag: String? = nil) { self.tag = tag }
    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: RFDesign.light.radius_md)
        KitIcon(name: "qr-code", size: KitMetrics.qrGlyph, tint: RFDesign.light.text)
            .frame(width: KitMetrics.qr, height: KitMetrics.qr)
            .background(RFDesign.light.surface_white, in: shape)
            .overlay { shape.strokeBorder(RFDesign.light.line_strong, lineWidth: KitMetrics.stroke) }
            .kitTag(tag)
    }
}
