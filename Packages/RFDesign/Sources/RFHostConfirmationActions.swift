// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
/// The host owns the action summary and confirmation; peer content supplies neither callback.
public struct RFHostConfirmationActions: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    @Environment(\.rfTheme) private var theme
    @FocusState private var cancelFocused: Bool
    @AccessibilityFocusState private var cancelAccessibilityFocused: Bool
    public let confirmLabel: String?
    /// The label of the quiet dismiss action; "Cancel" when nil.
    public let cancelLabel: String?
    public let summary: String
    public let enabled: Bool
    public let cancelEnabled: Bool
    /// A destructive confirmation keeps the danger style and starts with focus on Cancel; every other one is a primary action.
    public let destructive: Bool
    public let confirm: () -> Void
    public let cancel: () -> Void
    public init(summary: String, confirmLabel: String? = nil, cancelLabel: String? = nil, enabled: Bool, cancelEnabled: Bool = true, destructive: Bool = false, confirm: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.confirmLabel = confirmLabel; self.cancelLabel = cancelLabel; self.summary = summary; self.enabled = enabled; self.cancelEnabled = cancelEnabled; self.destructive = destructive; self.confirm = confirm; self.cancel = cancel
    }
    public var body: some View {
        #if os(iOS)
        RFNativeConfirmationActions(summary: summary, confirmLabel: confirmLabel, cancelLabel: cancelLabel, enabled: enabled && phase == .active, cancelEnabled: cancelEnabled, destructive: destructive, confirm: confirm, cancel: cancel)
        #else
        VStack(spacing: theme.gap) {
            RFHostConfirmButton(summary: summary, confirmLabel: confirmLabel, enabled: enabled && phase == .active, destructive: destructive, confirm: confirm)
            Button(cancelLabel ?? RFDesignStrings.text("confirmation.cancel", locale: locale), role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
                .focused($cancelFocused)
                .accessibilityFocused($cancelAccessibilityFocused)
                .disabled(!cancelEnabled)
        }
        .defaultFocus($cancelFocused, true)
        .task { cancelFocused = true; cancelAccessibilityFocused = true }
        #endif
    }
}
