// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RFDesign
/// Native continuous gesture; no card-controlled timer or confirmation callback.
public struct HoldToConfirm: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    @State private var epoch = 0
    public let label: String
    public let enabled: Bool
    public let confirm: () -> Void
    public init(label: String, enabled: Bool, confirm: @escaping () -> Void) { self.label = label; self.enabled = enabled; self.confirm = confirm }
    public var body: some View {
        Text(label).frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(RFTheme.adaptive(scheme).danger)
            .background(RFTheme.adaptive(scheme).danger_bg, in: .rect(cornerRadius: RFTheme.adaptive(scheme).radius_button))
            .onLongPressGesture(minimumDuration: 1.2, maximumDistance: 16) { if enabled && phase == .active { confirm() } }
            .id(epoch).allowsHitTesting(enabled && phase == .active)
            .accessibilityElement().accessibilityLabel(label).accessibilityHint("Touch and hold continuously for 1.2 seconds")
            .accessibilityAddTraits(.isButton)
            .onChange(of: phase) { _, _ in epoch &+= 1 }
            .onDisappear { epoch &+= 1 }
    }
}
