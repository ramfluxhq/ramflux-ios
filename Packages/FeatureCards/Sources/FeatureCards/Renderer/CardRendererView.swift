// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RamfluxCore
import AppData
import RFDesign
import RFLocalization

/// Draws one node of a card's native tree by its kind. An unknown kind draws the content-unavailable note.
struct CardNodeView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme

    var body: some View {
        switch node.kind {
        case "Text": CardTextView(node: node)
        case "Icon": CardIconView(node: node)
        case "Row": CardRowView(node: node, context: context)
        case "Column": CardColumnView(node: node, context: context)
        case "List": CardListView(node: node, context: context)
        case "Card": CardInsetView(node: node, context: context)
        case "Tabs": CardTabsView(node: node, context: context)
        case "Modal": CardModalView(node: node, context: context)
        case "Divider": CardDividerView(node: node)
        case "Button": CardButtonView(node: node, context: context)
        case "TextField": CardTextFieldView(node: node, context: context)
        case "CheckBox": CardCheckBoxView(node: node, context: context)
        case "ChoicePicker": CardChoicePickerView(node: node, context: context)
        case "Slider": CardSliderView(node: node, context: context)
        case "DateTimeInput": CardDateTimeView(node: node, context: context)
        case "Image": CardImageView(node: node)
        case "Approval": CardApprovalView(node: node, context: context)
        case "Task": CardTaskView(node: node)
        case "Chart": CardChartView(node: node, context: context)
        case "Table": CardTableView(node: node)
        default:
            Text(FeatureCardsStrings.text("cards.contentUnavailable", locale: locale))
                .rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
        }
    }
}

/// The children of a node in document order.
struct CardChildren: View {
    let node: CardNode
    let context: CardContext
    var body: some View {
        ForEach(context.tree.children(of: node.key), id: \.key) { child in
            CardNodeView(node: child, context: context)
        }
    }
}

struct CardTextView: View {
    let node: CardNode
    @Environment(\.rfTheme) private var theme

    var body: some View {
        let raw = node.attrs["text"]?.string ?? ""
        if !raw.isEmpty {
            let caption = node.attrs["variant"]?.string == "caption"
            Text(CardMarkdown.attributed(raw))
                .rfFont(caption ? .size(theme.size_secondary) : .body)
                .foregroundStyle(caption ? theme.secondary : theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CardIconView: View {
    let node: CardNode
    @Environment(\.rfTheme) private var theme
    var body: some View {
        if let name = node.attrs["name"]?.string {
            KitIcon(name: name, size: 20, tint: theme.text)
                .accessibilityHidden(node.attrs["accessibility"]?["label"]?.string == nil)
        }
    }
}

struct CardRowView: View {
    let node: CardNode
    let context: CardContext
    var body: some View {
        let justify = node.attrs["justify"]?.string
        HStack(alignment: .center, spacing: 8) {
            if justify == "end" || justify == "center" { Spacer(minLength: 0) }
            CardChildren(node: node, context: context)
            if justify == "start" || justify == "center" { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardColumnView: View {
    let node: CardNode
    let context: CardContext
    var body: some View {
        let align = node.attrs["align"]?.string
        let alignment: HorizontalAlignment = align == "center" ? .center : (align == "end" ? .trailing : .leading)
        VStack(alignment: alignment, spacing: 12) { CardChildren(node: node, context: context) }
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

/// A vertical list shows five items and then "Show all"; a horizontal list is a carousel of 200-point items.
struct CardListView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let items = context.tree.children(of: node.key)
        if items.isEmpty {
            Text(FeatureCardsStrings.text("cards.list.empty", locale: locale)).rfFont(.size(theme.size_secondary))
                .foregroundStyle(theme.secondary).frame(maxWidth: .infinity, minHeight: 48)
        } else if node.attrs["direction"]?.string == "horizontal" {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(items, id: \.key) { CardNodeView(node: $0, context: context).frame(width: 200, alignment: .leading) }
                }
            }
        } else {
            let expanded = context.local.expanded.contains(node.key)
            let shown = expanded ? items : Array(items.prefix(5))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.key) { index, item in
                    if index > 0 { Rectangle().fill(theme.line_soft).frame(height: 1) }
                    CardNodeView(node: item, context: context).padding(.vertical, 12)
                }
                if items.count > 5, !expanded {
                    Button(FeatureCardsStrings.format("cards.list.showAll", items.count, locale: locale)) { context.local.expanded.insert(node.key) }
                        .rfFont(.size(theme.size_button), weight: .medium).foregroundStyle(theme.text)
                }
            }
        }
    }
}

/// A Card nested in a card: an inset block with no border.
struct CardInsetView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { CardChildren(node: node, context: context) }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
    }
}

struct CardDividerView: View {
    let node: CardNode
    @Environment(\.rfTheme) private var theme
    var body: some View {
        if node.attrs["axis"]?.string == "vertical" {
            Rectangle().fill(theme.line).frame(width: 1).frame(maxHeight: .infinity)
        } else {
            Rectangle().fill(theme.line).frame(height: 1).padding(.vertical, 4)
        }
    }
}

/// Segmented tabs: the host keeps the selection by key and sends `select_tab`; only the selected panel is drawn.
struct CardTabsView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme

    var body: some View {
        let titles = (node.attrs["tabs"]?.array ?? []).map { $0["title"]?.string ?? "" }
        let selected = min(context.local.selectedTabs[node.key] ?? 0, max(titles.count - 1, 0))
        let panel = context.tree.children(of: node.key).first { $0.slot["slot"]?.string == "tab" && $0.slot["position"]?.cardInt == selected }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    Button {
                        guard context.editable, index != selected else { return }
                        context.local.selectedTabs[node.key] = index
                        context.onEvent(node.key, .selectTab(index: index))
                    } label: {
                        Text(RFUntrustedText(title, kind: .identity).text)
                            .rfFont(.size(theme.size_button), weight: index == selected ? .semibold : .regular)
                            .foregroundStyle(index == selected ? theme.text : theme.secondary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(index == selected ? theme.surface_white : Color.clear, in: RoundedRectangle(cornerRadius: theme.radius_xs))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_input))
            if let panel { CardNodeView(node: panel, context: context) }
        }
    }
}

/// A Modal is its trigger child and a sheet holding its content child. The host owns the sheet; open and close are
/// sent as events, and a signed update closes it.
struct CardModalView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.locale) private var locale

    var body: some View {
        let children = context.tree.children(of: node.key)
        let trigger = children.first { $0.slot["slot"]?.string == "trigger" }
        let content = children.first { $0.slot["slot"]?.string == "content" }
        VStack(alignment: .leading, spacing: 8) {
            if let trigger {
                Button {
                    guard context.actionable else { return }
                    context.local.openModals.insert(node.key)
                    context.onEvent(node.key, .modalOpen)
                } label: { CardNodeView(node: trigger, context: context) }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: Binding(
            get: { context.local.openModals.contains(node.key) },
            set: { open in
                guard !open, context.local.openModals.contains(node.key) else { return }
                closeModal()
            })) {
            NavigationStack {
                ScrollView {
                    if let content { CardNodeView(node: content, context: context).padding(16) }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(FeatureCardsStrings.text("cards.modal.close", locale: locale)) { closeModal() }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private func closeModal() {
        guard context.local.openModals.contains(node.key) else { return }
        context.local.openModals.remove(node.key)
        context.onEvent(node.key, .modalClose)
    }
}

extension JSONValue {
    /// A non-negative integer from a JSON number, or nil.
    var cardInt: Int? {
        switch self {
        case .unsigned(let value): Int(exactly: value)
        case .number(let value): value >= 0 && value.rounded() == value && value < 9_007_199_254_740_991 ? Int(value) : nil
        default: nil
        }
    }
    var cardDouble: Double? {
        switch self {
        case .unsigned(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }
    var array: [JSONValue]? { if case .array(let rows) = self { rows } else { nil } }
}
