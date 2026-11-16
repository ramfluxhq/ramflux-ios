// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

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
    var failed: Bool
    var transient: Bool
    var fileName: String?
    var fileMeta: String?
    var fileIcon: String
    var maxWidth: CGFloat?
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(
        _ bodyText: String,
        kind: KitBubbleKind = .own,
        time: String? = nil,
        edited: String? = nil,
        sender: String? = nil,
        agentTag: String? = nil,
        pending: Bool = false,
        read: Bool = false,
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
        let cap = maxWidth ?? theme.mobile_bubble_max
        let shape = bubbleShape
        VStack(alignment: .leading, spacing: KitMetrics.bubbleGap) {
            if kind == .incoming && (!(sender ?? "").isEmpty || !(agentTag ?? "").isEmpty) {
                HStack(spacing: KitMetrics.headerGap) {
                    if let sender, !sender.isEmpty {
                        KitLabel(sender, size: theme.size_secondary, weight: .semibold, color: theme.text, line: KitMetrics.lineSecondary)
                    }
                    if let agentTag, !agentTag.isEmpty {
                        KitLabel(agentTag, size: theme.size_mobile_caption, weight: .semibold, color: theme.secondary, line: KitMetrics.lineTitle, role: .latin)
                            .padding(.horizontal, KitMetrics.chipPadH)
                            .frame(height: KitMetrics.agentTag)
                            .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_chip))
                    }
                }
            }
            if kind == .file {
                fileRow(meta: meta)
            } else {
                HStack(alignment: .bottom, spacing: KitMetrics.headerGap) {
                    KitFlowText(text: bodyText, size: theme.size_mobile_body, weight: .regular, color: ink, line: KitMetrics.lineBubble, role: .ui)
                    HStack(spacing: KitMetrics.replyRadius) {
                        if let edited, !edited.isEmpty {
                            KitLabel(edited, size: theme.size_mobile_caption, weight: .regular, color: meta, line: KitMetrics.lineTitle, role: .latin)
                        }
                        if let time, !time.isEmpty {
                            KitLabel(time, size: theme.size_mobile_caption, weight: .regular, color: meta, line: KitMetrics.lineTitle, role: .latin)
                        }
                        if pending { KitIcon(name: "clock-3", size: KitMetrics.metaIcon, tint: meta) }
                        if own && !pending && (read || !(time ?? "").isEmpty) {
                            KitIcon(name: "check-check", size: KitMetrics.metaIcon, tint: read ? ink : meta)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, kind == .file ? KitMetrics.bubblePadV : KitMetrics.bubblePadH)
        .padding(.vertical, KitMetrics.bubblePadV)
        .frame(maxWidth: cap, alignment: .leading)
        .background(fill, in: shape)
        .overlay { if failed { shape.strokeBorder(theme.danger, lineWidth: KitMetrics.controlStroke) } }
        .opacity(transient ? 0 : 1)
        .kitTag(tag)
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
                KitLabel(fileName ?? "", size: theme.size_body, weight: .medium, color: theme.text, line: KitMetrics.lineBody)
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
