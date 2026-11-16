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
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(visible.enumerated()), id: \.element) { index, id in
                        editorRow(id, index: index, last: visible.count - 1)
                    }
                    KitButton(
                        copy("shell.nav.add"),
                        action: { hidden = ShellShortcuts.reveal(hidden) },
                        kind: .secondary,
                        enabled: !hidden.isEmpty,
                        tag: "shell-nav-add"
                    )
                    Text(copy("shell.nav.core"))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, theme.gap)
                .padding(.top, 12)
                .padding(.bottom, theme.gap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: theme.gap) {
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
            .frame(maxWidth: .infinity)
            .frame(height: 74)
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
                .font(theme.bodyFont)
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
