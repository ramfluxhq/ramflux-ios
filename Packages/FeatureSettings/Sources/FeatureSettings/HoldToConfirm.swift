// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFDesign
/// Native continuous gesture; no card-controlled timer or confirmation callback.
public struct HoldToConfirm: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var phase
    @Environment(\.rfTheme) private var theme
    @State private var epoch = 0
    public let label: String
    public let enabled: Bool
    public let confirm: () -> Void
    public init(label: String, enabled: Bool, confirm: @escaping () -> Void) { self.label = label; self.enabled = enabled; self.confirm = confirm }
    public var body: some View {
        Text(label).frame(maxWidth: .infinity, minHeight: theme.composer_min)
            .foregroundStyle(theme.danger)
            .background(theme.danger_bg, in: .rect(cornerRadius: theme.radius_button))
            .onLongPressGesture(minimumDuration: 1.2, maximumDistance: 16) { if enabled && phase == .active { confirm() } }
            .id(epoch).allowsHitTesting(enabled && phase == .active)
            .accessibilityElement().accessibilityLabel(label).accessibilityHint(FeatureSettingsStrings.text("copy.a1ec4eb88afb", locale: locale))
            .accessibilityAddTraits(.isButton)
            .onChange(of: phase) { _, _ in epoch &+= 1 }
            .onDisappear { epoch &+= 1 }
    }
}
