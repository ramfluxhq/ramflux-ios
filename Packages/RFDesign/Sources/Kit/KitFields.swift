// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public struct KitTextField: View {
    @Binding var value: String
    var label: String
    var placeholder: String
    var error: String?
    var note: String?
    var enabled: Bool
    var focused: Bool
    var tag: String?
    @FocusState private var editing: Bool
    @Environment(\.rfTheme) private var theme
    @Environment(\.kitCapturing) private var capturing

    public init(value: Binding<String>, label: String, placeholder: String = "", error: String? = nil, note: String? = nil, enabled: Bool = true, focused: Bool = false, tag: String? = nil) {
        self._value = value
        self.label = label
        self.placeholder = placeholder
        self.error = error
        self.note = note
        self.enabled = enabled
        self.focused = focused
        self.tag = tag
    }

    public var body: some View {
        let active = focused || editing
        let border = error != nil ? theme.danger : (active ? theme.focus : theme.input_border)
        VStack(alignment: .leading, spacing: KitMetrics.fieldGap) {
            KitLabel(label, size: theme.size_secondary, weight: .regular, color: theme.secondary, line: KitMetrics.lineSecondary)
            HStack(spacing: KitMetrics.headerGap) {
                fieldText(size: theme.size_mobile_body)
                if error != nil { KitIcon(name: "circle-alert", size: KitMetrics.fieldIcon, tint: theme.danger) }
            }
            .padding(.horizontal, KitMetrics.fieldPad)
            .frame(maxWidth: .infinity)
            .frame(height: KitMetrics.fieldBox)
            .background(theme.input, in: RoundedRectangle(cornerRadius: theme.radius_input))
            .overlay { RoundedRectangle(cornerRadius: theme.radius_input).strokeBorder(border, lineWidth: KitMetrics.stroke) }
            if let error {
                KitLabel(error, size: theme.size_secondary, weight: .regular, color: theme.danger, line: KitMetrics.lineSecondary)
            } else if let note {
                KitLabel(note, size: theme.size_secondary, weight: .regular, color: theme.secondary, line: KitMetrics.lineSecondary)
            }
        }
        .opacity(enabled ? 1 : KitMetrics.fieldDisabledAlpha)
        .allowsHitTesting(enabled)
        .kitTag(tag)
    }

    @ViewBuilder private func fieldText(size: CGFloat) -> some View {
        if capturing {
            KitLabel(value.isEmpty ? placeholder : value, size: size, weight: .regular, color: value.isEmpty ? theme.secondary : theme.text, line: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("", text: $value, prompt: Text(placeholder).foregroundStyle(theme.secondary))
                .textFieldStyle(.plain)
                .font(kitFont(size: size, weight: kitWeight(.regular), role: .ui))
                .foregroundStyle(theme.text)
                .focused($editing)
                .disabled(!enabled)
        }
    }
}

public struct KitSearchField: View {
    @Binding var value: String
    var placeholder: String
    var enabled: Bool
    var focused: Bool
    var showsClear: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme
    @Environment(\.kitCapturing) private var capturing

    public init(value: Binding<String>, placeholder: String, enabled: Bool = true, focused: Bool = false, showsClear: Bool = true, tag: String? = nil) {
        self._value = value
        self.placeholder = placeholder
        self.enabled = enabled
        self.focused = focused
        self.showsClear = showsClear
        self.tag = tag
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius_input)
        HStack(spacing: KitMetrics.headerGap) {
            KitIcon(name: "search", size: KitMetrics.searchIcon, tint: theme.secondary)
            if capturing {
                KitLabel(value.isEmpty ? placeholder : value, size: theme.size_mobile_body, weight: .regular, color: value.isEmpty ? theme.secondary : theme.text, line: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $value, prompt: Text(placeholder).foregroundStyle(theme.secondary))
                    .textFieldStyle(.plain)
                    .font(kitFont(size: theme.size_mobile_body, weight: kitWeight(.regular), role: .ui))
                    .foregroundStyle(value.isEmpty ? theme.secondary : theme.text)
                    .disabled(!enabled)
            }
            if showsClear && !value.isEmpty {
                KitHit(
                    enabled: enabled,
                    label: RFDesignStrings.text("kit.clear"),
                    hitTag: tag.map { $0 + "-clear" },
                    action: { value = "" }
                ) {
                    KitIcon(name: "circle-x", size: KitMetrics.searchIcon, tint: theme.secondary)
                        .frame(width: KitMetrics.searchIcon, height: KitMetrics.searchIcon)
                        .kitTag(tag.map { $0 + "-clear-icon" })
                }
            }
        }
        .padding(.horizontal, KitMetrics.searchPad)
        .frame(maxWidth: .infinity)
        .frame(height: KitMetrics.search)
        .background(theme.surface, in: shape)
        .overlay { if focused { shape.strokeBorder(theme.focus, lineWidth: KitMetrics.focusRing) } }
        .opacity(enabled ? 1 : KitMetrics.disabledAlpha)
        .kitTag(tag)
    }
}
