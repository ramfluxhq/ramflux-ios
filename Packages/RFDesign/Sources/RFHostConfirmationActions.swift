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
    public let summary: String
    public let enabled: Bool
    public let cancelEnabled: Bool
    public let confirm: () -> Void
    public let cancel: () -> Void
    public init(summary: String, confirmLabel: String? = nil, enabled: Bool, cancelEnabled: Bool = true, confirm: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.confirmLabel = confirmLabel; self.summary = summary; self.enabled = enabled; self.cancelEnabled = cancelEnabled; self.confirm = confirm; self.cancel = cancel
    }
    public var body: some View {
        #if os(iOS)
        RFNativeConfirmationActions(summary: summary, confirmLabel: confirmLabel, enabled: enabled && phase == .active, cancelEnabled: cancelEnabled, confirm: confirm, cancel: cancel)
        #else
        VStack(spacing: theme.gap) {
            Button(RFDesignStrings.text("confirmation.cancel", locale: locale), role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
                .focused($cancelFocused)
                .accessibilityFocused($cancelAccessibilityFocused)
                .disabled(!cancelEnabled)
            RFHostConfirmButton(summary: summary, confirmLabel: confirmLabel, enabled: enabled && phase == .active, confirm: confirm)
        }
        .defaultFocus($cancelFocused, true)
        .task { cancelFocused = true; cancelAccessibilityFocused = true }
        #endif
    }
}
