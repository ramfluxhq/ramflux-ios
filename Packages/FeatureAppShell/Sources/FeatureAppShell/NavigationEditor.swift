// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// Pushed edit-navigation page. Changes apply immediately. Done only closes.
public struct NavigationEditorScreen: View {
    @Binding var order: String
    @Binding var hidden: String
    public var onBack: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme

    public init(order: Binding<String>, hidden: Binding<String>, onBack: @escaping () -> Void) {
        self._order = order
        self._hidden = hidden
        self.onBack = onBack
    }

    public var body: some View {
        let gone = Set(ShellShortcuts.ids(hidden))
        let visible = ShellShortcuts.ids(order).filter { !gone.contains($0) }
        VStack(spacing: 0) {
            KitPageHeader(copy("shell.nav.title"), onBack: onBack, tag: "shell-nav-header")
            ScrollView {
                VStack(alignment: .leading, spacing: theme.gap) {
                    Text(copy("shell.nav.note"))
                        .rfFont(.caption)
                        .foregroundStyle(theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 12) {
                        ForEach(Array(visible.enumerated()), id: \.element) { index, id in
                            editorRow(id, index: index, last: visible.count - 1)
                        }
                    }
                    KitButton(
                        copy("shell.nav.add"),
                        action: { hidden = ShellShortcuts.reveal(hidden) },
                        kind: .secondary,
                        enabled: !hidden.isEmpty,
                        tag: "shell-nav-add"
                    )
                    Text(copy("shell.nav.core"))
                        .rfFont(.caption)
                        .foregroundStyle(theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, theme.gap)
                .padding(.top, 20)
                .padding(.bottom, theme.gap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            NavigationEditorFooter(spacing: theme.gap) {
                KitButton(
                    copy("shell.nav.restore"),
                    action: {
                        order = ShellShortcuts.defaultOrder
                        hidden = ""
                    },
                    kind: .secondary,
                    tag: "shell-nav-restore"
                )
                KitButton(copy("shell.nav.done"), action: onBack, tag: "shell-nav-done")
            }
            .padding(.horizontal, theme.gap)
            .padding(.vertical, NavigationEditorFooter.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: NavigationEditorFooter.minimumHeight)
            .background(theme.bg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .shellHidesSystemBar()
        .accessibilityIdentifier("shell-navigation-editor")
    }

    private func editorRow(_ id: String, index: Int, last: Int) -> some View {
        let core = ShellShortcuts.isCore(id)
        return HStack(spacing: 0) {
            Text(shortcutLabel(id))
                .rfFont(.body)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            KitIconButton(
                "arrow-up",
                label: copy("shell.nav.up"),
                action: { order = ShellShortcuts.move(order, hidden: hidden, index: index, delta: -1) },
                enabled: index > 0,
                tag: "shell-nav-up-\(index)"
            )
            KitIconButton(
                "arrow-down",
                label: copy("shell.nav.down"),
                action: { order = ShellShortcuts.move(order, hidden: hidden, index: index, delta: 1) },
                enabled: index < last,
                tag: "shell-nav-down-\(index)"
            )
            if core {
                KitIconButton("lock-keyhole", label: copy("shell.nav.lock"), action: {}, enabled: false, tag: "shell-nav-lock-\(index)")
            } else {
                KitIconButton(
                    "x",
                    label: copy("shell.nav.remove"),
                    action: { hidden = ShellShortcuts.hide(hidden, id: id) },
                    tag: "shell-nav-remove-\(index)"
                )
            }
        }
        .frame(height: 64)
        .accessibilityElement(children: .contain)
    }

    private func shortcutLabel(_ id: String) -> String {
        switch id {
        case "groups": AppTab.groups.title(locale: locale)
        case "agents": AppTab.agents.title(locale: locale)
        case "contacts": copy("common.nav.contacts")
        case "tasks": copy("common.nav.tasks")
        default: AppTab.messages.title(locale: locale)
        }
    }

    private func copy(_ key: String) -> String {
        FeatureAppShellStrings.text(key, locale: locale)
    }
}

/// The editor footer: two buttons side by side at equal widths when every label fits on one
/// line in half the width, otherwise stacked at full width in reading order. Long labels
/// (German, Russian, the expanded pseudo-locale) and large text sizes therefore never wrap
/// inside a half-width button. Placement uses the container's leading edge, so the pair
/// mirrors under right to left.
struct NavigationEditorFooter: Layout {
    /// The design footer is 74 pt high with a 48 pt button: 13 pt above and below.
    static let minimumHeight: CGFloat = 74
    static let verticalPadding: CGFloat = 13
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? ideal.map(\.width).reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        if let column = sideBySideWidth(width, ideal) {
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
            return CGSize(width: width, height: height)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        if let column = sideBySideWidth(bounds.width, ideal) {
            for (index, subview) in subviews.enumerated() {
                let x = bounds.minX + CGFloat(index) * (column + spacing)
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: column, height: bounds.height))
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }

    /// The equal column width when every subview's one-line width fits in it.
    private func sideBySideWidth(_ width: CGFloat, _ ideal: [CGSize]) -> CGFloat? {
        guard !ideal.isEmpty else { return nil }
        let column = (width - spacing * CGFloat(ideal.count - 1)) / CGFloat(ideal.count)
        return ideal.allSatisfy { $0.width <= column } ? column : nil
    }
}
