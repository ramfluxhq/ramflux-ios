// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFLocalization

public enum KitBubbleKind { case own, incoming, file }

public struct KitBubble: View {
    var bodyText: String
    var kind: KitBubbleKind
    var time: String?
    var edited: String?
    var sender: String?
    var agentTag: String?
    var pending: Bool
    var read: Bool
    var sentOnly: Bool
    var failed: Bool
    var transient: Bool
    var fileName: String?
    var fileMeta: String?
    var fileIcon: String
    var maxWidth: CGFloat?
    var tag: String?
    @Environment(\.rfTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        _ bodyText: String,
        kind: KitBubbleKind = .own,
        time: String? = nil,
        edited: String? = nil,
        sender: String? = nil,
        agentTag: String? = nil,
        pending: Bool = false,
        read: Bool = false,
        sentOnly: Bool = false,
        failed: Bool = false,
        transient: Bool = false,
        fileName: String? = nil,
        fileMeta: String? = nil,
        fileIcon: String = "file-text",
        maxWidth: CGFloat? = nil,
        tag: String? = nil
    ) {
        self.bodyText = bodyText
        self.kind = kind
        self.time = time
        self.edited = edited
        self.sender = sender
        self.agentTag = agentTag
        self.pending = pending
        self.read = read
        self.sentOnly = sentOnly
        self.failed = failed
        self.transient = transient
        self.fileName = fileName
        self.fileMeta = fileMeta
        self.fileIcon = fileIcon
        self.maxWidth = maxWidth
        self.tag = tag
    }

    public var body: some View {
        let own = kind == .own
        let fill = own ? theme.outgoing : theme.incoming
        let ink = own ? theme.outgoing_text : theme.text
        let meta = own ? theme.outgoing_meta : theme.incoming_meta
        let shape = bubbleShape
        KitBubbleWidth(fixed: maxWidth, token: theme.mobile_bubble_max, fraction: KitMetrics.bubbleWidthFraction) {
            content(own: own, ink: ink, meta: meta)
                .padding(.horizontal, kind == .file ? KitMetrics.bubblePadV : KitMetrics.bubblePadH)
                .padding(.vertical, KitMetrics.bubblePadV)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(fill, in: shape)
        .overlay { if failed { shape.strokeBorder(theme.danger, lineWidth: KitMetrics.controlStroke) } }
        .opacity(transient ? 0 : 1)
        .kitTag(tag)
    }

    private func content(own: Bool, ink: Color, meta: Color) -> some View {
        VStack(alignment: .leading, spacing: KitMetrics.bubbleGap) {
            if kind == .incoming && (!(sender ?? "").isEmpty || !(agentTag ?? "").isEmpty) {
                HStack(spacing: KitMetrics.headerGap) {
                    if let sender, !sender.isEmpty {
                        KitLabel(RFUntrustedText(sender, kind: .identity).text, size: theme.size_secondary, weight: .semibold, color: theme.text, line: KitMetrics.lineSecondary)
                    }
                    if let agentTag, !agentTag.isEmpty {
                        KitLabel(agentTag, size: theme.size_mobile_caption, weight: .semibold, color: theme.secondary, line: KitMetrics.lineTitle, role: .latin)
                            .padding(.horizontal, KitMetrics.chipPadH)
                            .frame(minHeight: KitMetrics.agentTag)
                            .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_chip))
                    }
                }
            }
            if kind == .file {
                fileRow(meta: meta)
            } else {
                // At accessibility text sizes the meta cluster moves under the text (trailing), so a
                // narrow bubble does not squeeze the message into a one-word column.
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .trailing, spacing: KitMetrics.bubbleGap))
                    : AnyLayout(HStackLayout(alignment: .bottom, spacing: KitMetrics.headerGap))
                layout {
                    KitMessageText(bodyText, color: ink)
                    metaCluster(own: own, ink: ink, meta: meta)
                }
            }
        }
    }

    private func metaCluster(own: Bool, ink: Color, meta: Color) -> some View {
        HStack(spacing: KitMetrics.replyRadius) {
            if let edited, !edited.isEmpty {
                KitLabel(edited, size: theme.size_mobile_caption, weight: .regular, color: meta, line: KitMetrics.lineTitle, role: .latin)
            }
            if let time, !time.isEmpty {
                KitLabel(time, size: theme.size_mobile_caption, weight: .regular, color: meta, line: KitMetrics.lineTitle, role: .latin)
            }
            if pending { KitIcon(name: "clock-3", size: KitMetrics.metaIcon, tint: meta) }
            // One check: sent, no device has confirmed delivery yet. Two checks: delivered; two
            // checks in the text colour: read on at least one device.
            if own && !pending && (read || !(time ?? "").isEmpty) {
                KitIcon(name: sentOnly && !read ? "check" : "check-check", size: KitMetrics.metaIcon, tint: read ? ink : meta)
            }
        }
        .fixedSize()
        // The ticks and the clock are drawn as hidden icons; their meaning is the cluster's value.
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(receiptStatus(own: own)))
    }

    /// What the ticks or the clock say, for assistive technology (empty when nothing is drawn).
    private func receiptStatus(own: Bool) -> String {
        if pending { return RFDesignStrings.text("kit.receipt.pending") }
        guard own, read || !(time ?? "").isEmpty else { return "" }
        if read { return RFDesignStrings.text("kit.receipt.read") }
        return RFDesignStrings.text(sentOnly ? "kit.receipt.sent" : "kit.receipt.delivered")
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if kind == .file {
            return UnevenRoundedRectangle(
                topLeadingRadius: theme.radius_bubble_joined,
                bottomLeadingRadius: theme.radius_bubble,
                bottomTrailingRadius: theme.radius_bubble,
                topTrailingRadius: theme.radius_bubble
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: theme.radius_bubble,
            bottomLeadingRadius: theme.radius_bubble,
            bottomTrailingRadius: theme.radius_bubble,
            topTrailingRadius: theme.radius_bubble
        )
    }

    private func fileRow(meta: Color) -> some View {
        HStack(spacing: KitMetrics.headerGap) {
            KitIcon(name: fileIcon, size: KitMetrics.fileGlyph, tint: theme.text)
                .frame(width: KitMetrics.fileTile, height: KitMetrics.fileTile)
                .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_md))
            VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                KitFileName(fileName ?? "")
                HStack(spacing: KitMetrics.headerGap) {
                    if let fileMeta, !fileMeta.isEmpty {
                        KitLabel(fileMeta, size: theme.size_mobile_caption, weight: .regular, color: meta, line: KitMetrics.lineTitle, role: .latin, tracking: 1)
                    }
                    if let time, !time.isEmpty {
                        KitLabel(time, size: theme.size_mobile_caption, weight: .regular, color: meta, line: KitMetrics.lineTitle, role: .latin)
                    }
                }
            }
        }
    }
}
