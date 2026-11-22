// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public enum KitButtonKind { case primary, secondary, destructive, disabled, text }

public enum KitButtonSize { case regular, compact }

public struct KitButton: View {
    var label: String
    var action: () -> Void
    var kind: KitButtonKind
    var size: KitButtonSize
    var enabled: Bool
    var loading: Bool
    var focused: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme
    @Environment(\.kitPreviewPressed) private var previewPressed
    @State private var holding = false

    public init(
        _ label: String,
        action: @escaping () -> Void,
        kind: KitButtonKind = .primary,
        size: KitButtonSize = .regular,
        enabled: Bool = true,
        loading: Bool = false,
        focused: Bool = false,
        tag: String? = nil
    ) {
        self.label = label
        self.action = action
        self.kind = kind
        self.size = size
        self.enabled = enabled
        self.loading = loading
        self.focused = focused
        self.tag = tag
    }

    public var body: some View {
        let designedDisabled = kind == .disabled || (kind == .primary && !enabled)
        let active = enabled && kind != .disabled && !loading
        let height = kind == .text || size == .compact ? KitMetrics.buttonCompact : KitMetrics.buttonHeight
        let weight: Font.Weight = kind == .text ? .medium : .semibold
        let fill: Color = switch (designedDisabled, kind) {
        case (true, _): theme.surface
        case (_, .primary): theme.primary
        case (_, .destructive): theme.danger
        default: .clear
        }
        let labelColor: Color = switch (designedDisabled, kind) {
        case (true, _): theme.control
        case (_, .primary): theme.on_primary
        case (_, .destructive): theme.on_danger
        default: theme.text
        }
        let stroke: Color? = kind == .secondary && !designedDisabled ? theme.text : nil
        let filled = kind == .primary || kind == .destructive
        let pressed = (holding || previewPressed) && filled && active
        let alpha = (pressed ? KitMetrics.pressedAlpha : 1) * ((!enabled && !designedDisabled) ? KitMetrics.disabledAlpha : 1)
        let shape = RoundedRectangle(cornerRadius: theme.radius_button)
        KitHit(enabled: active, label: label, hitTag: tag.map { $0 + "-hit" }, onPress: { holding = $0 }, action: action) {
            HStack(spacing: KitMetrics.headerGap) {
                if loading { KitSpinner(size: KitMetrics.tileGlyph, tint: labelColor, tag: tag.map { $0 + "-spinner" }) }
                KitLabel(label, size: theme.size_mobile_body, weight: weight, color: labelColor, line: KitMetrics.lineTitle, lines: nil)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, KitMetrics.buttonPadH)
            .padding(.vertical, KitMetrics.headerPadV)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill, in: shape)
            .overlay { if let stroke { shape.strokeBorder(stroke, lineWidth: KitMetrics.stroke) } }
            .overlay { if focused { shape.strokeBorder(kitFocusRing(fill: fill, theme: theme), lineWidth: KitMetrics.focusRing) } }
            .opacity(alpha)
            .kitTag(tag)
        }
    }
}
