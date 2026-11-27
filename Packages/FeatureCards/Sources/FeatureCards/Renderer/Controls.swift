// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// A Button sends `activate` only when the card is actionable; the label shows "Submitting..." while its own submit is
/// in flight. A consumed button stays disabled until the signed update.
struct CardButtonView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let variant = node.attrs["variant"]?.string ?? "default"
        let enabled = context.actionable && node.attrs["disabled"]?.bool != true
        let busy = context.phase == .submitting && context.local.pressedKey == node.key
        let label = context.tree.children(of: node.key).compactMap { $0.attrs["text"]?.string }.joined(separator: " ")
        let primary = variant == "primary"
        let borderless = variant == "borderless"
        let foreground: Color = !enabled ? theme.control : (primary ? theme.on_primary : theme.text)
        let fill: Color = borderless ? .clear : (!enabled ? theme.surface : (primary ? theme.primary : theme.surface_white))
        Button {
            guard enabled else { return }
            context.local.pressedKey = node.key
            context.onEvent(node.key, .activate)
        } label: {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small) }
                Text(busy ? FeatureCardsStrings.text("cards.chip.submitting", locale: locale) : RFUntrustedText(label, kind: .identity).text)
                    .lineLimit(2)
            }
            .rfFont(.size(theme.size_button), weight: .medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minWidth: 64, minHeight: 44)
            .background(fill, in: RoundedRectangle(cornerRadius: theme.radius_button))
            .overlay {
                if variant == "default" {
                    RoundedRectangle(cornerRadius: theme.radius_button).strokeBorder(enabled ? theme.text : theme.surface, lineWidth: KitMetrics.stroke)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// A TextField keeps its draft locally while focused and sends `input` on each edit; the pool merges queued inputs.
/// Errors show once the field has lost focus.
struct CardTextFieldView: View {
    let node: CardNode
    let context: CardContext
    @FocusState private var focused: Bool
    @State private var text = ""
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let label = node.attrs["label"]?.string ?? ""
        let variant = node.attrs["variant"]?.string ?? "shortText"
        let editable = context.editable && node.attrs["disabled"]?.bool != true
        let errors = cardErrors(node.attrs["errors"])
        let showErrors = !errors.isEmpty && context.local.touched.contains(node.key)
        VStack(alignment: .leading, spacing: 6) {
            Text(RFUntrustedText(label, kind: .identity).text).rfFont(.size(theme.size_secondary), weight: .medium).foregroundStyle(theme.text)
            if variant == "obscured" {
                Text(FeatureCardsStrings.text("cards.contentUnavailable", locale: locale)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
            } else {
                TextField("", text: $text, axis: variant == "longText" ? .vertical : .horizontal)
                    .lineLimit(variant == "longText" ? 3...8 : 1...1)
                    .rfFont(.body)
                    .foregroundStyle(editable ? theme.text : theme.control)
                    .focused($focused)
                    .disabled(!editable)
                    .modifier(CardNumberKeyboard(number: variant == "number"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: variant == "longText" ? 88 : 48, alignment: .topLeading)
                    .background(editable ? theme.input : theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_input))
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.radius_input)
                            .strokeBorder(showErrors ? theme.danger : theme.input_border, lineWidth: focused ? 2 : KitMetrics.stroke)
                    }
            }
            if showErrors {
                ForEach(errors, id: \.self) { Text(RFUntrustedText($0, kind: .messageBody).text).rfFont(.caption).foregroundStyle(theme.danger) }
            }
        }
        .onAppear { text = node.attrs["value"]?.string ?? "" }
        .onChange(of: node.attrs["value"]?.string ?? "") { _, value in if !focused { text = value } }
        .onChange(of: text) { _, value in
            if focused, editable { context.onEvent(node.key, .input(.string(value))) }
        }
        .onChange(of: focused) { _, now in if !now { context.local.touched.insert(node.key) } }
    }
}

/// Numeric keyboard for number fields on phones.
private struct CardNumberKeyboard: ViewModifier {
    let number: Bool
    func body(content: Content) -> some View {
        #if os(iOS)
        content.keyboardType(number ? .decimalPad : .default)
        #else
        content
        #endif
    }
}

struct CardCheckBoxView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme

    var body: some View {
        let on = node.attrs["value"]?.bool == true
        let editable = context.editable && node.attrs["disabled"]?.bool != true
        let errors = cardErrors(node.attrs["errors"])
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard editable else { return }
                context.local.touched.insert(node.key)
                context.onEvent(node.key, .input(.bool(!on)))
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: theme.radius_xs)
                        .fill(on ? (editable ? theme.primary : theme.control) : theme.input)
                        .overlay {
                            if on {
                                KitIcon(name: "check", size: 14, tint: theme.on_primary)
                            } else {
                                RoundedRectangle(cornerRadius: theme.radius_xs).strokeBorder(editable ? theme.control : theme.line_strong, lineWidth: KitMetrics.stroke)
                            }
                        }
                        .frame(width: 18, height: 18)
                    Text(RFUntrustedText(node.attrs["label"]?.string ?? "", kind: .identity).text)
                        .rfFont(.body).foregroundStyle(editable ? theme.text : theme.control)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            if context.local.touched.contains(node.key), !errors.isEmpty {
                ForEach(errors, id: \.self) { Text(RFUntrustedText($0, kind: .messageBody).text).rfFont(.caption).foregroundStyle(theme.danger) }
            }
        }
    }
}

/// Checkbox rows (multiple selection) or radio rows (mutually exclusive), or chips. Options are sent in the order the
/// tree lists them. More than six options use the same rows inline; the platform list sheet is not built yet.
struct CardChoicePickerView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme

    var body: some View {
        let options = (node.attrs["options"]?.array ?? []).map { (label: $0["label"]?.string ?? "", value: $0["value"]?.string ?? "") }
        let selected = Set((node.attrs["value"]?.array ?? []).compactMap(\.string))
        let exclusive = node.attrs["variant"]?.string == "mutuallyExclusive"
        let editable = context.editable && node.attrs["disabled"]?.bool != true
        let chips = node.attrs["displayStyle"]?.string == "chips"
        VStack(alignment: .leading, spacing: 8) {
            Text(RFUntrustedText(node.attrs["label"]?.string ?? "", kind: .identity).text)
                .rfFont(.size(theme.size_secondary), weight: .medium).foregroundStyle(theme.text)
            if chips {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(options, id: \.value) { option in
                        let on = selected.contains(option.value)
                        Button { choose(option.value, in: options, selected: selected, exclusive: exclusive, node: node, context: context) } label: {
                            Text(RFUntrustedText(option.label, kind: .identity).text)
                                .rfFont(.size(theme.size_button))
                                .foregroundStyle(on ? theme.on_primary : theme.text)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .background(on ? theme.primary : theme.surface_white, in: RoundedRectangle(cornerRadius: theme.radius_chip))
                                .overlay { RoundedRectangle(cornerRadius: theme.radius_chip).strokeBorder(on ? theme.primary : theme.line_strong, lineWidth: KitMetrics.stroke) }
                        }
                        .buttonStyle(.plain)
                        .disabled(!editable)
                    }
                }
            } else {
                ForEach(options, id: \.value) { option in
                    let on = selected.contains(option.value)
                    Button { choose(option.value, in: options, selected: selected, exclusive: exclusive, node: node, context: context) } label: {
                        HStack(spacing: 12) {
                            if exclusive {
                                Circle().strokeBorder(on ? theme.primary : theme.control, lineWidth: on ? 1.5 : KitMetrics.stroke)
                                    .overlay { if on { Circle().fill(theme.primary).padding(5) } }
                                    .frame(width: 18, height: 18)
                            } else {
                                RoundedRectangle(cornerRadius: theme.radius_xs)
                                    .fill(on ? (editable ? theme.primary : theme.control) : theme.input)
                                    .overlay {
                                        if on { KitIcon(name: "check", size: 14, tint: theme.on_primary) }
                                        else { RoundedRectangle(cornerRadius: theme.radius_xs).strokeBorder(theme.control, lineWidth: KitMetrics.stroke) }
                                    }
                                    .frame(width: 18, height: 18)
                            }
                            Text(RFUntrustedText(option.label, kind: .identity).text).rfFont(.body).foregroundStyle(editable ? theme.text : theme.control)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!editable)
                }
            }
        }
    }

    private func choose(_ value: String, in options: [(label: String, value: String)], selected: Set<String>, exclusive: Bool,
                        node: CardNode, context: CardContext) {
        context.local.touched.insert(node.key)
        let next: Set<String>
        if exclusive { next = [value] } else if selected.contains(value) { next = selected.subtracting([value]) } else { next = selected.union([value]) }
        let ordered = options.map(\.value).filter { next.contains($0) }
        context.onEvent(node.key, .input(.array(ordered.map { .string($0) })))
    }
}

/// A slider sends its value once a drag ends.
struct CardSliderView: View {
    let node: CardNode
    let context: CardContext
    @State private var dragging: Double?
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let low = node.attrs["min"]?.cardDouble ?? 0
        let high = node.attrs["max"]?.cardDouble ?? 1
        let range = low < high ? low...high : 0...1
        let value = min(max(node.attrs["value"]?.cardDouble ?? low, range.lowerBound), range.upperBound)
        let editable = context.editable && node.attrs["disabled"]?.bool != true
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(RFUntrustedText(node.attrs["label"]?.string ?? "", kind: .identity).text)
                    .rfFont(.size(theme.size_secondary), weight: .medium).foregroundStyle(theme.text)
                Spacer(minLength: 0)
                Text(dragging ?? value, format: .number.locale(context.formatLocale))
                    .rfFont(.size(theme.size_meta)).foregroundStyle(theme.secondary)
            }
            Slider(value: Binding(get: { dragging ?? value }, set: { dragging = $0 }), in: range, onEditingChanged: { editing in
                guard !editing, let final = dragging else { return }
                context.onEvent(node.key, .input(.number(final)))
                context.local.touched.insert(node.key)
            })
            .disabled(!editable)
            .tint(theme.primary)
        }
        .onChange(of: value) { _, _ in dragging = nil }
    }
}

/// A date or date-time field with the system picker. Date-only values are sent as `yyyy-MM-dd`, date-times as RFC 3339.
struct CardDateTimeView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme

    var body: some View {
        let withDate = node.attrs["enableDate"]?.bool ?? true
        let withTime = node.attrs["enableTime"]?.bool ?? false
        let value = node.attrs["value"]?.string ?? ""
        let editable = context.editable && node.attrs["disabled"]?.bool != true
        let label = RFUntrustedText(node.attrs["label"]?.string ?? "", kind: .identity).text
        if !withDate && !withTime {
            HStack {
                Text(label).rfFont(.size(theme.size_secondary), weight: .medium)
                Spacer(minLength: 0)
                Text(RFUntrustedText(value, kind: .identity).text).rfFont(.body)
            }
        } else {
            let parsed = CardDates.parse(value, withTime: withTime) ?? Date()
            DatePicker(selection: Binding(get: { parsed }, set: { next in
                guard editable else { return }
                context.local.touched.insert(node.key)
                context.onEvent(node.key, .input(.string(CardDates.format(next, withTime: withTime))))
            }), displayedComponents: withTime ? (withDate ? [.date, .hourAndMinute] : [.hourAndMinute]) : [.date]) {
                Text(label).rfFont(.size(theme.size_secondary), weight: .medium).foregroundStyle(theme.text)
            }
            .environment(\.locale, context.formatLocale)
            .environment(\.calendar, withTime ? Calendar.current : CardDates.utcCalendar)
            .disabled(!editable)
        }
    }
}
