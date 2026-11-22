// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI

public struct KitSwitch: View {
    var checked: Bool
    var onChecked: (Bool) -> Void
    var enabled: Bool
    var label: String
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(checked: Bool, onChecked: @escaping (Bool) -> Void = { _ in }, enabled: Bool = true, label: String = "", tag: String? = nil) {
        self.checked = checked
        self.onChecked = onChecked
        self.enabled = enabled
        self.label = label
        self.tag = tag
    }

    public var body: some View {
        KitHit(enabled: enabled, label: label, hitTag: tag.map { $0 + "-hit" }, action: { onChecked(!checked) }) {
            ZStack(alignment: checked ? .trailing : .leading) {
                Capsule().fill(checked ? theme.primary : theme.line_strong)
                Circle()
                    .fill(checked ? theme.on_primary : theme.surface_white)
                    .frame(width: KitMetrics.switchKnob, height: KitMetrics.switchKnob)
                    .padding(KitMetrics.switchInset)
            }
            .frame(width: KitMetrics.switchWidth, height: KitMetrics.switchHeight)
            .opacity(enabled ? 1 : KitMetrics.disabledAlpha)
            .kitTag(tag)
        }
    }
}

public struct KitCheckbox: View {
    var checked: Bool
    var onChecked: (Bool) -> Void
    var enabled: Bool
    var size: CGFloat
    var radius: CGFloat?
    var strokeColor: Color?
    var label: String
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(
        checked: Bool,
        onChecked: @escaping (Bool) -> Void = { _ in },
        enabled: Bool = true,
        size: CGFloat = KitMetrics.checkbox,
        radius: CGFloat? = nil,
        strokeColor: Color? = nil,
        label: String = "",
        tag: String? = nil
    ) {
        self.checked = checked
        self.onChecked = onChecked
        self.enabled = enabled
        self.size = size
        self.radius = radius
        self.strokeColor = strokeColor
        self.label = label
        self.tag = tag
    }

    public var body: some View {
        let corner = radius ?? theme.radius_sm
        let shape = RoundedRectangle(cornerRadius: corner)
        KitHit(enabled: enabled, label: label, hitTag: tag.map { $0 + "-hit" }, action: { onChecked(!checked) }) {
            ZStack {
                if checked {
                    shape.fill(theme.primary)
                    KitIcon(name: "check", size: KitMetrics.check * size / KitMetrics.checkbox, tint: theme.on_primary)
                } else {
                    shape.strokeBorder(strokeColor ?? theme.control, lineWidth: KitMetrics.controlStroke)
                }
            }
            .frame(width: size, height: size)
            .opacity(enabled ? 1 : KitMetrics.disabledAlpha)
            .kitTag(tag)
        }
    }
}

public struct KitSegmented: View {
    var labels: [String]
    var selected: Int
    var onSelect: (Int) -> Void
    var enabled: Bool
    var tag: String?
    @Environment(\.rfTheme) private var theme

    public init(labels: [String], selected: Int, onSelect: @escaping (Int) -> Void = { _ in }, enabled: Bool = true, tag: String? = nil) {
        self.labels = labels
        self.selected = selected
        self.onSelect = onSelect
        self.enabled = enabled
        self.tag = tag
    }

    public var body: some View {
        HStack(spacing: KitMetrics.segmentedPad) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let on = index == selected
                KitHit(enabled: enabled, label: label, hitTag: tag.map { "\($0)-\(index)" }, action: { onSelect(index) }) {
                    KitLabel(
                        label,
                        size: theme.size_secondary,
                        weight: on ? .semibold : .regular,
                        color: on ? theme.text : theme.secondary,
                        line: KitMetrics.lineSecondary,
                        lines: nil
                    )
                    .multilineTextAlignment(.center)
                    .padding(.vertical, KitMetrics.tagPadV)
                    .frame(maxWidth: .infinity, minHeight: KitMetrics.segmented - KitMetrics.segmentedPad * 2)
                    .background { if on { RoundedRectangle(cornerRadius: theme.radius_sm).fill(theme.surface_white) } }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(KitMetrics.segmentedPad)
        .frame(maxWidth: .infinity, minHeight: KitMetrics.segmented)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
        .opacity(enabled ? 1 : KitMetrics.disabledAlpha)
        .kitTag(tag)
    }
}
