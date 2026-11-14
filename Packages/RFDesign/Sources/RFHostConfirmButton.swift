// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
#if !os(iOS)
struct RFHostConfirmButton: View {
    @Environment(\.locale) private var locale
    @State private var gate = RFConfirmationGate()
    let summary: String
    let confirmLabel: String?
    let enabled: Bool
    let confirm: () -> Void
    var body: some View {
        Button(confirmLabel ?? RFDesignStrings.text("confirmation.confirm", locale: locale), role: .destructive) {
            if gate.activate(.tap, enabled: enabled) { confirm() }
        }
        .accessibilityLabel(RFDesignStrings.format("confirmation.action", summary, locale: locale))
        .disabled(!enabled).focusable(false)
        .onKeyPress(keys: [.return, .space], phases: [.down, .repeat, .up]) { _ in .handled }
    }
}
#endif
