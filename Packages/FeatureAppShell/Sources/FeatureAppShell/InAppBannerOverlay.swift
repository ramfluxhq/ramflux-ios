// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign

/// The in-app message banner: a card the app draws over its own window while it is in the foreground.
/// It is never a system notification. It is generic ("New message", no name, no text) while the scene is
/// being captured (recording, mirroring) or the app is locked, and its text is then hidden from accessibility.
/// Nothing here is logged, stored in scene storage or user activities, or donated.
public struct InAppBannerOverlay: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let banner: InAppBanner?
    public let captured: Bool
    public let locked: Bool
    public let onOpen: (InAppBanner) -> Void
    public let onDismiss: (UUID) -> Void
    /// How long a banner stays before it dismisses itself.
    public static let lifetime: Duration = .seconds(4)
    public init(banner: InAppBanner?, captured: Bool, locked: Bool, onOpen: @escaping (InAppBanner) -> Void, onDismiss: @escaping (UUID) -> Void) {
        self.banner = banner; self.captured = captured; self.locked = locked; self.onOpen = onOpen; self.onDismiss = onDismiss
    }
    public var body: some View {
        ZStack(alignment: .top) {
            if let banner {
                InAppBannerCard(banner: banner, generic: captured || locked, hidden: captured, onOpen: { onOpen(banner) }, onDismiss: { onDismiss(banner.id) })
                    .id(banner.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: banner?.id)
        .allowsHitTesting(banner != nil)
    }
}

private struct InAppBannerCard: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let banner: InAppBanner
    let generic: Bool
    /// Capture is active: the text is not exposed to accessibility at all.
    let hidden: Bool
    let onOpen: () -> Void
    let onDismiss: () -> Void
    @State private var lift: CGFloat = 0

    private var title: String {
        generic || banner.sender.isEmpty ? FeatureAppShellStrings.text("banner.generic", locale: locale) : banner.sender
    }
    private var detail: String? {
        guard !generic else { return nil }
        switch banner.content {
        case .text(let preview): return preview
        case .call: return FeatureAppShellStrings.text("banner.call", locale: locale)
        case .other: return FeatureAppShellStrings.text("banner.other", locale: locale)
        }
    }
    /// Short and free of message text; the sender's name is spoken only in the non-generic form.
    private var spoken: String {
        generic || banner.sender.isEmpty ? FeatureAppShellStrings.text("banner.generic", locale: locale)
            : FeatureAppShellStrings.format("banner.accessibility.from", banner.sender, locale: locale)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: theme.gap / 4) {
                Text(title).rfFont(.body, weight: .semibold).lineLimit(1)
                if let detail { Text(detail).rfFont(.caption).lineLimit(1) }
            }
            .foregroundStyle(theme.text)
            .padding(theme.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.overlay, in: RoundedRectangle(cornerRadius: theme.radius_dialog))
            .overlay { RoundedRectangle(cornerRadius: theme.radius_dialog).strokeBorder(theme.overlay_border, lineWidth: KitMetrics.stroke) }
            .shadow(color: theme.shadow, radius: KitMetrics.shadowBlur)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, theme.gap)
        .padding(.top, theme.gap / 2)
        .offset(y: lift)
        .gesture(DragGesture(minimumDistance: 8).onChanged { lift = min(0, $0.translation.height) }
            .onEnded { value in
                if value.translation.height < -24 || value.predictedEndTranslation.height < -64 { onDismiss() } else { withAnimation(.easeOut(duration: 0.15)) { lift = 0 } }
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("in-app-banner")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(FeatureAppShellStrings.text("banner.accessibility.dismiss", locale: locale)), onDismiss)
        .accessibilityHidden(hidden)
        .task {
            if !hidden { AccessibilityNotification.Announcement(spoken).post() }
            try? await Task.sleep(for: InAppBannerOverlay.lifetime)
            if !Task.isCancelled { onDismiss() }
        }
    }
}

/// The opaque cover drawn over the whole window whenever the scene is not active, so that neither the
/// app-switcher snapshot nor a glance at it shows chat content or a banner. It shows the app name only.
public struct PrivacyCoverView: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public init() {}
    public var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            Text(FeatureAppShellStrings.text("common.appName", locale: locale)).rfFont(.page).foregroundStyle(theme.text)
        }
        .accessibilityHidden(true)
    }
}
