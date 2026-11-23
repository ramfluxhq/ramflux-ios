// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFLocalization

public struct KitComposer: View {
    @Binding var value: String
    var placeholder: String
    var onSend: () -> Void
    var onAttach: () -> Void
    var sendActive: Bool
    var attachEnabled: Bool
    var mode: String?
    var option: String?
    var optionChecked: Bool
    var onOption: (Bool) -> Void
    var replyAuthor: String?
    var replyExcerpt: String?
    var onCloseReply: (() -> Void)?
    var attachmentName: String?
    var attachmentState: String?
    var onRemoveAttachment: (() -> Void)?
    var tag: String?
    @Environment(\.rfTheme) private var theme
    @Environment(\.kitCapturing) private var capturing
    @Environment(\.layoutDirection) private var layoutDirection

    public init(
        value: Binding<String>,
        placeholder: String,
        onSend: @escaping () -> Void = {},
        onAttach: @escaping () -> Void = {},
        sendActive: Bool = false,
        attachEnabled: Bool = true,
        mode: String? = nil,
        option: String? = nil,
        optionChecked: Bool = false,
        onOption: @escaping (Bool) -> Void = { _ in },
        replyAuthor: String? = nil,
        replyExcerpt: String? = nil,
        onCloseReply: (() -> Void)? = nil,
        attachmentName: String? = nil,
        attachmentState: String? = nil,
        onRemoveAttachment: (() -> Void)? = nil,
        tag: String? = nil
    ) {
        self._value = value
        self.placeholder = placeholder
        self.onSend = onSend
        self.onAttach = onAttach
        self.sendActive = sendActive
        self.attachEnabled = attachEnabled
        self.mode = mode
        self.option = option
        self.optionChecked = optionChecked
        self.onOption = onOption
        self.replyAuthor = replyAuthor
        self.replyExcerpt = replyExcerpt
        self.onCloseReply = onCloseReply
        self.attachmentName = attachmentName
        self.attachmentState = attachmentState
        self.onRemoveAttachment = onRemoveAttachment
        self.tag = tag
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KitMetrics.headerGap) {
            if let mode, !mode.isEmpty {
                HStack(spacing: KitMetrics.bubbleGap) {
                    KitLabel(mode, size: theme.size_secondary, weight: .medium, color: theme.text, line: KitMetrics.lineSecondary)
                    KitIcon(name: "chevron-down", size: KitMetrics.chevron, tint: theme.secondary)
                }
                .padding(.horizontal, KitMetrics.modePad)
                .frame(minHeight: KitMetrics.modeChip)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_chip))
            }
            if let option, !option.isEmpty {
                HStack(spacing: KitMetrics.approvalGap) {
                    KitCheckbox(checked: optionChecked, onChecked: onOption, size: KitMetrics.optionBox, radius: theme.radius_xs, strokeColor: theme.line_strong)
                    KitLabel(option, size: theme.size_secondary, weight: .regular, color: theme.secondary, line: KitMetrics.lineSecondary, lines: nil)
                }
                .padding(.horizontal, KitMetrics.headerGap)
                .frame(maxWidth: .infinity, minHeight: KitMetrics.optionRow, alignment: .leading)
            }
            if let replyAuthor, !replyAuthor.isEmpty {
                HStack(spacing: KitMetrics.approvalGap) {
                    RoundedRectangle(cornerRadius: KitMetrics.replyRadius)
                        .fill(theme.accent)
                        .frame(width: KitMetrics.replyAccentWidth, height: KitMetrics.replyAccentHeight)
                    VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                        KitLabel(replyAuthor, size: theme.size_secondary, weight: .semibold, color: theme.text, line: KitMetrics.lineSecondary)
                        if let replyExcerpt, !replyExcerpt.isEmpty {
                            KitLabel(RFUntrustedText(replyExcerpt, kind: .messageBody).text, size: theme.size_button, weight: .regular, color: theme.secondary, line: KitMetrics.lineTitle)
                        }
                    }
                    .padding(.vertical, KitMetrics.capsulePad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let onCloseReply {
                        KitIconHit(icon: "x", size: KitMetrics.iconInfo, tint: theme.secondary, label: RFDesignStrings.text("kit.close"), action: onCloseReply)
                    }
                }
                .padding(.leading, KitMetrics.gutter)
                .frame(maxWidth: .infinity, minHeight: KitMetrics.replyBar)
            }
            if let attachmentName, !attachmentName.isEmpty {
                HStack(spacing: KitMetrics.headerGap) {
                    KitIcon(name: "file-text", size: KitMetrics.fileGlyph, tint: theme.text)
                        .frame(width: KitMetrics.fileTile, height: KitMetrics.fileTile)
                        .background(theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_md))
                    VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                        KitFileName(attachmentName)
                        if let attachmentState, !attachmentState.isEmpty {
                            KitLabel(attachmentState, size: theme.size_meta, weight: .regular, color: theme.secondary, line: KitMetrics.lineTitle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let onRemoveAttachment {
                        KitIconHit(icon: "x", size: KitMetrics.fieldIcon, tint: theme.secondary, label: RFDesignStrings.text("kit.close"), action: onRemoveAttachment)
                    }
                }
                .padding(.leading, KitMetrics.headerGap)
                .padding(.vertical, KitMetrics.chipPadV)
                .frame(maxWidth: .infinity, minHeight: KitMetrics.attachment)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
            }
            HStack(spacing: KitMetrics.bubbleGap) {
                KitIcon(name: "plus", size: KitMetrics.attachIcon, tint: theme.secondary)
                    .frame(width: KitMetrics.iconButton, height: KitMetrics.iconButton)
                    .opacity(attachEnabled ? 1 : KitMetrics.disabledAlpha)
                    .contentShape(Rectangle())
                    .onTapGesture { if attachEnabled { onAttach() } }
                    .allowsHitTesting(attachEnabled)
                HStack(spacing: KitMetrics.headerGap) {
                    if capturing {
                        KitLabel(value.isEmpty ? placeholder : value, size: theme.size_mobile_body, weight: .regular, color: value.isEmpty ? theme.secondary : theme.text, line: 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        // The draft grows to a few lines. The placeholder and an empty draft start at the
                        // leading edge; typed text aligns by its own direction, like a sent message.
                        TextField("", text: $value, prompt: Text(placeholder).foregroundStyle(theme.secondary), axis: .vertical)
                            .lineLimit(1...KitMetrics.composerLines)
                            .textFieldStyle(.plain)
                            .modifier(KitFieldFont(size: theme.size_mobile_body))
                            .foregroundStyle(theme.text)
                            .multilineTextAlignment(KitMessageText.direction(of: value, surrounding: layoutDirection) == layoutDirection ? .leading : .trailing)
                    }
                    KitHit(enabled: sendActive, label: RFDesignStrings.text("kit.send"), hitTag: tag.map { $0 + "-send" }, action: onSend) {
                        KitIcon(name: "arrow-up", size: KitMetrics.sendIcon, tint: sendActive ? theme.on_accent : theme.control)
                            .frame(width: KitMetrics.send, height: KitMetrics.send)
                            .background(sendActive ? theme.accent : .clear, in: RoundedRectangle(cornerRadius: theme.radius_xl))
                            .kitTag(tag.map { $0 + "-send-icon" })
                    }
                }
                .padding(.leading, KitMetrics.capsulePadStart)
                .padding(.trailing, KitMetrics.capsulePad)
                .padding(.vertical, KitMetrics.capsulePad)
                .frame(maxWidth: .infinity, minHeight: KitMetrics.composerRow)
                .background(theme.input, in: RoundedRectangle(cornerRadius: KitMetrics.capsuleRadius))
                .overlay { RoundedRectangle(cornerRadius: KitMetrics.capsuleRadius).strokeBorder(theme.input_border, lineWidth: KitMetrics.stroke) }
            }
            .frame(minHeight: KitMetrics.composerRow)
        }
        .padding(KitMetrics.composerPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .kitHairline(theme.line, top: true)
        .kitTag(tag)
    }
}
