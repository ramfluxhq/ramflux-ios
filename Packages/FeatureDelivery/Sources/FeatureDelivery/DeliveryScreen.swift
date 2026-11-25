// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import Push
import RFDesign

/// "Message delivery": how messages reach this iPhone and what could delay them. Every row is read again when
/// the user comes back from the system Settings.
public struct DeliveryScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: DeliveryState
    public let onAction: (DeliveryAction) -> Void
    public init(state: DeliveryState, onAction: @escaping (DeliveryAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeatureDeliveryStrings.text(key, locale: locale) }
    private func value(_ setting: DeliverySetting) -> String { copy(setting == .on ? "value.on" : (setting == .off ? "value.off" : "value.notSupported")) }
    private func row(_ label: String, _ value: String, tag: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(label).rfFont(.body); Spacer(); Text(value).rfFont(.caption).foregroundStyle(theme.secondary) }
            .accessibilityElement(children: .combine).accessibilityIdentifier(tag)
    }
    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.gap / 2) {
            Text(title).rfFont(.body, weight: .semibold); content()
        }.padding(theme.gap).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface_white, in: .rect(cornerRadius: theme.radius_card))
    }
    private func relative(_ date: Date?) -> String {
        guard let date else { return copy("wake.never") }
        if abs(date.timeIntervalSinceNow) < 60 { return copy("wake.justNow") }
        let formatter = RelativeDateTimeFormatter(); formatter.locale = locale; formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    public var body: some View {
        let settings = state.snapshot.settings
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(copy("title"), onBack: { dismiss() }, tag: "delivery-header")
            card(copy("section.status")) {
                Text(copy("status." + state.snapshot.status.rawValue)).rfFont(.body).accessibilityIdentifier("delivery-status")
            }
            card(copy("section.lastWake")) {
                row(copy("wake.message"), relative(state.snapshot.lastWake[.message]), tag: "delivery-last-message")
                row(copy("wake.test"), relative(state.snapshot.lastWake[.test]), tag: "delivery-last-test")
                row(copy("wake.call"), relative(state.snapshot.lastWake[.call]), tag: "delivery-last-call")
                row(copy("wake.clear"), relative(state.snapshot.lastWake[.clear]), tag: "delivery-last-clear")
            }
            card(copy("section.phone")) {
                row(copy("phone.allowed"), copy(settings.allowed ? "value.on" : "value.off"), tag: "delivery-allowed")
                row(copy("phone.lockScreen"), value(settings.lockScreen), tag: "delivery-lock-screen")
                row(copy("phone.notificationCenter"), value(settings.notificationCenter), tag: "delivery-notification-center")
                row(copy("phone.banners"), value(settings.banners), tag: "delivery-banners")
                row(copy("phone.sounds"), value(settings.sounds), tag: "delivery-sounds")
                row(copy("phone.badges"), value(settings.badges), tag: "delivery-badges")
                row(copy("phone.timeSensitive"), value(settings.timeSensitive), tag: "delivery-time-sensitive")
                row(copy("phone.scheduledSummary"), value(settings.scheduledSummary), tag: "delivery-scheduled-summary")
                if settings.scheduledSummary == .on { Text(copy("phone.summaryOn")).rfFont(.caption).foregroundStyle(theme.secondary) }
                row(copy("phone.previews"), copy("previews." + settings.showPreviews), tag: "delivery-previews")
            }
            card(copy("section.background")) {
                row(copy("background.refresh"), copy("refresh." + String(describing: state.snapshot.backgroundRefresh)), tag: "delivery-background-refresh")
                row(copy("background.lowPower"), copy(state.snapshot.lowPowerMode ? "value.on" : "value.off"), tag: "delivery-low-power")
                if state.snapshot.backgroundRefresh != .enabled || state.snapshot.lowPowerMode { Text(copy("background.late")).rfFont(.caption).foregroundStyle(theme.secondary) }
            }
            card(copy("section.guidance")) {
                Text(copy("guidance.focus")).rfFont(.caption)
                Text(copy("guidance.swipe")).rfFont(.caption)
            }
            card(copy("section.calls")) { Text(copy("calls.interim")).rfFont(.caption) }
            card(copy("section.selfTest")) {
                Text(copy("selfTest.hint")).rfFont(.caption).foregroundStyle(theme.secondary)
                Button(copy("selfTest.action")) { onAction(.selfTest) }.accessibilityIdentifier("delivery-self-test")
                if let result = state.selfTest { Text(copy(result == .sent ? "selfTest.sent" : "selfTest.failed")).rfFont(.caption).accessibilityIdentifier("delivery-self-test-result") }
            }
            Text(copy("late")).rfFont(.caption).foregroundStyle(theme.secondary)
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
        .rfHidesNavigationBar()
    }
}
