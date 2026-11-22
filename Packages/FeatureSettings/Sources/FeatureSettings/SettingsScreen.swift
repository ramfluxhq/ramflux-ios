// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
public struct SettingsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: SettingsState
    public let onAction: (SettingsAction) -> Void
    public init(state: SettingsState, onAction: @escaping (SettingsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(title, onBack: { dismiss() }, actions: [KitHeaderAction(icon: "refresh-cw", label: FeatureSettingsStrings.text("common.action.refresh", locale: locale), action: { onAction(.refresh) })], tag: "settings-header")
            if let pending = state.pendingMutation {
                Text(FeatureSettingsStrings.text("settings.pending", locale: locale))
                Text(pending.operationID).font(theme.captionFont)
                Button(FeatureSettingsStrings.text("settings.reconcile", locale: locale)) { onAction(.reconcileOriginal(pending.operationID)) }.disabled(state.busy)
            }
            if state.loading { ProgressView(FeatureSettingsStrings.text("settings.loading", locale: locale)) }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
            .privacySensitive().rfHidesNavigationBar()
            .sheet(item: Binding(get: { modal }, set: { if $0 == nil { onAction(.dismissModal) } })) { modal in
                NavigationStack { RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                    modalContent(modal)
                    if state.busy { ProgressView(FeatureSettingsStrings.text("settings.busy", locale: locale)) }
                    if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }.padding(theme.gap) } } }.interactiveDismissDisabled(state.busy)
            }

    }
    private static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-" }
    private static var appBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-" }
    private var modal: SettingsModal? {
        if let device = state.pendingRevoke { return .revoke(device) }
        return nil
    }
    private var title: String {
        switch state.route { case .devices, .device: FeatureSettingsStrings.text("settings.devices.title", locale: locale); case .nodes, .node: FeatureSettingsStrings.text("settings.nodes.title", locale: locale); case .appearance: FeatureSettingsStrings.text("settings.appearance.title", locale: locale)
        case .privacy: FeatureSettingsStrings.text("settings.privacy.title", locale: locale); case .backup: FeatureSettingsStrings.text("settings.backup.title", locale: locale); case .account: FeatureSettingsStrings.text("settings.account.title", locale: locale); case .about: FeatureSettingsStrings.text("settings.about.title", locale: locale); case .systemPermissions: FeatureSettingsStrings.text("settings.systemPermissions", locale: locale); case .permissions: FeatureSettingsStrings.text("settings.connectedServices.title", locale: locale); default: FeatureSettingsStrings.text("settings.title", locale: locale) }
    }
    @ViewBuilder private var content: some View {
        switch state.route {
        case .devices:
            Button(FeatureSettingsStrings.text("settings.devices.link", locale: locale)) { onAction(.unavailable(.pairing)) }
            if state.snapshot.accountID == nil { Text(FeatureSettingsStrings.text("settings.devices.noAccount", locale: locale)) }
            ForEach(state.snapshot.devices) { device in
                row(id: device.id, title: device.id, subtitle: device.isLocal ? FeatureSettingsStrings.text("settings.devices.thisDevice", locale: locale) : FeatureSettingsStrings.text("settings.devices.linked", locale: locale), route: .device(device.id))
            }
        case .device(let id):
            if let device = state.snapshot.devices.first(where: { $0.id == id }) {
                Text(device.id).textSelection(.enabled); Text(device.isLocal ? FeatureSettingsStrings.text("settings.devices.thisDevice", locale: locale) : FeatureSettingsStrings.text("settings.devices.linked", locale: locale))
                ForEach(device.capabilities, id: \.self) { Text($0).font(theme.captionFont) }
                if let origin = device.webOrigin { Text(origin).textSelection(.enabled); Text(FeatureSettingsStrings.text("settings.devices.webOriginWarning", locale: locale)).foregroundStyle(theme.danger) }
                if !device.isLocal { Button(FeatureSettingsStrings.text("settings.devices.revoke", locale: locale), role: .destructive) { onAction(.requestRevoke(device.id)) }.disabled(state.busy || state.unknownMutation) }
            } else { Text(FeatureSettingsStrings.text("settings.devices.missing", locale: locale)) }
        case .nodes:
            if state.snapshot.nodes.isEmpty { Text(FeatureSettingsStrings.text("settings.nodes.empty", locale: locale)) }
            ForEach(state.snapshot.nodes) { node in row(id: node.id, title: node.origin, subtitle: node.isDefault ? FeatureSettingsStrings.text("settings.nodes.default", locale: locale) : node.id, route: .node(node.id)) }
            Button(FeatureSettingsStrings.text("settings.nodes.add", locale: locale)) { onAction(.open(.onboarding)) }
        case .node(let id):
            if let node = state.snapshot.nodes.first(where: { $0.id == id }) {
                Text(node.origin).textSelection(.enabled); Text(node.id)
                if let key = node.publicKey { Text(key).font(theme.captionFont).textSelection(.enabled) }
                Text(node.enabled ? FeatureSettingsStrings.text("settings.nodes.enabled", locale: locale) : FeatureSettingsStrings.text("settings.nodes.disabled", locale: locale))
                Button(FeatureSettingsStrings.text("settings.nodes.useAsDefault", locale: locale)) { onAction(.setDefault(node.id)) }.disabled(state.busy || state.unknownMutation || !node.enabled)
            }
        case .appearance:
            Picker(FeatureSettingsStrings.text("settings.appearance.theme", locale: locale), selection: Binding(get: { state.appearance }, set: { onAction(.appearance($0)) })) {
                Text(FeatureSettingsStrings.text("settings.appearance.system", locale: locale)).tag(AppearanceMode.system); ForEach(RFThemeRegistry.themes) { entry in
                    if let mode = AppearanceMode(rawValue: entry.id) { Text(RFDesignStrings.text(entry.labelKey, locale: locale)).tag(mode) }
                }
            }.pickerStyle(.segmented).disabled(state.busy)
            Text(FeatureSettingsStrings.text("settings.appearance.languageNote", locale: locale))
        case .account:
            if let account = state.snapshot.accountID {
                Text(account).textSelection(.enabled)
                Text(state.snapshot.networking == .live ? FeatureSettingsStrings.text("settings.account.networkLive", locale: locale) : FeatureSettingsStrings.text("settings.account.networkUnconfirmed", locale: locale))
                Button(FeatureSettingsStrings.text("settings.account.lock", locale: locale), systemImage: "lock") { onAction(.lock) }.disabled(state.busy || state.unknownMutation)
            } else { Button(FeatureSettingsStrings.text("settings.account.openOrCreate", locale: locale)) { onAction(.open(.onboarding)) } }
            Picker(FeatureSettingsStrings.text("settings.privacy.retention.label", locale: locale), selection: Binding(get: { state.retentionSeconds }, set: { onAction(.retention($0)) })) {
                Text(FeatureSettingsStrings.text("settings.privacy.retention.oneHour", locale: locale)).tag(Int64(3600)); Text(FeatureSettingsStrings.text("settings.privacy.retention.oneDay", locale: locale)).tag(Int64(86400)); Text(FeatureSettingsStrings.text("settings.privacy.retention.sevenDays", locale: locale)).tag(Int64(604800))
            }
            Button(FeatureSettingsStrings.text("settings.privacy.retention.save", locale: locale)) { onAction(.saveRetention) }.disabled(state.busy || state.unknownMutation || state.snapshot.accountID == nil)
            Text(FeatureSettingsStrings.text("settings.privacy.retention.note", locale: locale)).font(theme.captionFont)
        case .privacy:
            Text(FeatureSettingsStrings.format("privacy.requestApproval", AppDataStrings.status(state.snapshot.requestPolicy, locale: locale), locale: locale))
            if state.snapshot.requestPolicy == "auto_accept" { Button(FeatureSettingsStrings.text("settings.privacy.requireApproval", locale: locale)) { onAction(.manualRequests) }.disabled(state.busy || state.unknownMutation) }
            Button(FeatureSettingsStrings.text("settings.privacy.openAccount", locale: locale)) { onAction(.unavailable(.openAccount)) }
        case .backup: backupContent
        case .permissions:
            Text(FeatureSettingsStrings.text("settings.connectedServices.explanation", locale: locale))
            Button(FeatureSettingsStrings.text("settings.connectedServices.manage", locale: locale)) { onAction(.unavailable(.connectedServices)) }
        case .about:
            Text(FeatureSettingsStrings.text("common.appName", locale: locale)).font(theme.pageFont); Text(FeatureSettingsStrings.text("settings.about.license", locale: locale))
            Text(FeatureSettingsStrings.text("settings.about.notificationPrivacy", locale: locale))
            Text(FeatureSettingsStrings.format("settings.version", Self.appVersion, Self.appBuild, locale: locale)).font(theme.captionFont).accessibilityIdentifier("about-version")
            Button(FeatureSettingsStrings.text("settings.about.exportDiagnostics", locale: locale)) { onAction(.unavailable(.diagnosticExport)) }
        default:
            ForEach([AppRoute.cards, .tasks, .calls(nil), .account, .devices, .nodes, .appearance, .privacy, .backup, .systemPermissions, .about], id: \.self) { route in row(id: label(route), title: label(route), subtitle: "", route: route) }
        }
    }
    @ViewBuilder private var backupContent: some View {
        RFUnavailableView(title: FeatureSettingsStrings.text("settings.backup.title", locale: locale), message: AppFailure.unavailableResource("settings.mobileBackup").message(locale: locale))
    }
    @ViewBuilder private func modalContent(_ modal: SettingsModal) -> some View {
        switch modal {
        case .revoke(let device):
            Text(FeatureSettingsStrings.text("settings.devices.revoke.title", locale: locale)).font(theme.pageFont); Text(device.id).textSelection(.enabled)
            if let origin = device.webOrigin { Text(origin).textSelection(.enabled) }
            Text(FeatureSettingsStrings.text("settings.devices.revoke.fact", locale: locale))
            RFHostConfirmationActions(summary: FeatureSettingsStrings.text("settings.devices.revoke", locale: locale) + " · " + device.id, enabled: !state.busy && !state.unknownMutation, cancelEnabled: !state.busy, confirm: { onAction(.confirmRevoke(device.id)) }, cancel: { onAction(.dismissModal) }).id(device.id)
        case .backup, .share: backupContent
        }
    }
    private func row(id: String, title: String, subtitle: String, route: AppRoute) -> some View {
        KitRow(title, action: { onAction(.open(route)) }, value: subtitle.isEmpty ? nil : subtitle, tag: id)
    }
    private func label(_ route: AppRoute) -> String { switch route { case .cards: FeatureSettingsStrings.text("cards.title", locale: locale); case .tasks: FeatureSettingsStrings.text("tasks.title", locale: locale); case .calls: FeatureSettingsStrings.text("calls.title", locale: locale); case .account: FeatureSettingsStrings.text("settings.account.title", locale: locale); case .devices: FeatureSettingsStrings.text("settings.devices.title", locale: locale); case .nodes: FeatureSettingsStrings.text("settings.nodes.title", locale: locale); case .appearance: FeatureSettingsStrings.text("settings.appearance.title", locale: locale); case .privacy: FeatureSettingsStrings.text("settings.privacy.title", locale: locale); case .backup: FeatureSettingsStrings.text("settings.backup.title", locale: locale); case .systemPermissions: FeatureSettingsStrings.text("settings.systemPermissions", locale: locale); case .permissions: FeatureSettingsStrings.text("settings.connectedServices.title", locale: locale); default: FeatureSettingsStrings.text("settings.about.title", locale: locale) } }
}
