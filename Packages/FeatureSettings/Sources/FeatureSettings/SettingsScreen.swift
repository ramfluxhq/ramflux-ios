// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
import RFLocalization
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
                Text(pending.operationID).rfFont(.caption)
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
        if state.changingCode { return .changeCode }
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
                KitIdentifierText(device.id).textSelection(.enabled); Text(device.isLocal ? FeatureSettingsStrings.text("settings.devices.thisDevice", locale: locale) : FeatureSettingsStrings.text("settings.devices.linked", locale: locale))
                ForEach(device.capabilities, id: \.self) { Text($0).rfFont(.caption) }
                if let origin = device.webOrigin { Text(untrusted: origin).textSelection(.enabled); Text(FeatureSettingsStrings.text("settings.devices.webOriginWarning", locale: locale)).foregroundStyle(theme.danger) }
                if !device.isLocal { Button(FeatureSettingsStrings.text("settings.devices.revoke", locale: locale), role: .destructive) { onAction(.requestRevoke(device.id)) }.disabled(state.busy || state.unknownMutation) }
            } else { Text(FeatureSettingsStrings.text("settings.devices.missing", locale: locale)) }
        case .nodes:
            if state.snapshot.nodes.isEmpty { Text(FeatureSettingsStrings.text("settings.nodes.empty", locale: locale)) }
            ForEach(state.snapshot.nodes) { node in row(id: node.id, title: node.origin, subtitle: node.isDefault ? FeatureSettingsStrings.text("settings.nodes.default", locale: locale) : node.id, route: .node(node.id)) }
            Button(FeatureSettingsStrings.text("settings.nodes.add", locale: locale)) { onAction(.open(.onboarding)) }
        case .node(let id):
            if let node = state.snapshot.nodes.first(where: { $0.id == id }) {
                Text(untrusted: node.origin).textSelection(.enabled); KitIdentifierText(node.id)
                if let key = node.publicKey { Text(key).rfFont(.caption).textSelection(.enabled) }
                Text(node.enabled ? FeatureSettingsStrings.text("settings.nodes.enabled", locale: locale) : FeatureSettingsStrings.text("settings.nodes.disabled", locale: locale))
                Button(FeatureSettingsStrings.text("settings.nodes.useAsDefault", locale: locale)) { onAction(.setDefault(node.id)) }.disabled(state.busy || state.unknownMutation || !node.enabled)
            }
        case .appearance:
            Picker(copy("settings.appearance.theme"), selection: Binding(get: { state.appearance }, set: { onAction(.appearance($0)) })) {
                Text(copy("settings.appearance.system")).tag(AppearanceMode.system); ForEach(RFThemeRegistry.themes) { entry in
                    if let mode = AppearanceMode(rawValue: entry.id) { Text(RFDesignStrings.text(entry.labelKey, locale: locale)).tag(mode) }
                }
            }.pickerStyle(.segmented).disabled(state.busy)
            Text(copy("settings.language.title")).rfFont(.body, weight: .semibold)
            Text(copy("settings.language.note")).foregroundStyle(theme.secondary)
            KitButton(copy("settings.language.change"), action: { onAction(.openSystemLanguage) }, kind: .secondary, tag: "settings-language-system")
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(SettingsLanguages.launch, id: \.self) { identifier in
                    KitRow(Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier, icon: nil,
                           value: SettingsLanguages.translated.contains(identifier) ? copy("settings.language.translated") : copy("settings.language.pending"),
                           trailing: SettingsLanguages.isCurrent(identifier, locale: locale) ? .check : .none, enabled: false, tag: "settings-language-" + identifier)
                }
            }
        case .account:
            if let account = state.snapshot.accountID {
                KitIdentifierText(account).textSelection(.enabled)
                Text(state.snapshot.networking == .live ? copy("settings.account.networkLive") : copy("settings.account.networkUnconfirmed")).foregroundStyle(theme.secondary)
                group(copy("settings.account.security"), [
                    KitRow(copy("settings.account.lock"), action: { onAction(.lock) }, icon: "lock", value: copy("settings.account.lock.detail"), trailing: .none, enabled: !state.busy && !state.unknownMutation, tag: "settings-lock"),
                    KitRow(copy("settings.account.changeCode"), action: { onAction(.startChangeCode) }, icon: "lock-keyhole", value: copy("settings.account.changeCode.detail"), enabled: !state.busy, tag: "settings-change-code"),
                    KitRow(copy("settings.privacy.title"), action: { onAction(.open(.privacy)) }, icon: "shield", value: copy("settings.index.privacy.detail"), tag: "settings-privacy"),
                ])
                if state.codeChanged { KitTipBar(copy("settings.account.changeCode.done"), icon: "circle-check", tag: "settings-code-changed") }
            } else { KitButton(copy("settings.account.openOrCreate"), action: { onAction(.open(.onboarding)) }) }
            Picker(copy("settings.privacy.retention.label"), selection: Binding(get: { state.retentionSeconds }, set: { onAction(.retention($0)) })) {
                Text(copy("settings.privacy.retention.oneHour")).tag(Int64(3600)); Text(copy("settings.privacy.retention.oneDay")).tag(Int64(86400)); Text(copy("settings.privacy.retention.sevenDays")).tag(Int64(604800))
            }
            Button(copy("settings.privacy.retention.save")) { onAction(.saveRetention) }.disabled(state.busy || state.unknownMutation || state.snapshot.accountID == nil)
            Text(copy("settings.privacy.retention.note")).rfFont(.caption)
        case .privacy:
            let automatic = state.snapshot.requestPolicy == "auto_accept"
            group(copy("settings.privacy.requests"), [
                KitRow(copy("settings.privacy.autoAccept"), action: { onAction(.requestPolicy(autoAccept: !automatic)) }, icon: "user-round-check",
                       value: FeatureSettingsStrings.format("privacy.requestApproval", AppDataStrings.status(state.snapshot.requestPolicy, locale: locale), locale: locale),
                       trailing: automatic ? .check : .none, enabled: state.snapshot.requestPolicy != nil && !state.busy && !state.unknownMutation, tag: "settings-auto-accept"),
            ])
            Text(copy(automatic ? "settings.privacy.autoAccept.on" : "settings.privacy.autoAccept.off")).foregroundStyle(theme.secondary)
            group(copy("settings.privacy.openAccount.section"), [
                KitRow(copy("settings.privacy.openAccount"), action: { onAction(.unavailable(.openAccount)) }, icon: "globe", tag: "settings-open-account"),
                KitRow(copy("settings.privacy.username"), action: { onAction(.unavailable(.username)) }, icon: "at-sign", tag: "settings-username"),
            ])
        case .permissions:
            Text(FeatureSettingsStrings.text("settings.connectedServices.explanation", locale: locale))
            Button(FeatureSettingsStrings.text("settings.connectedServices.manage", locale: locale)) { onAction(.unavailable(.connectedServices)) }
        case .about:
            Text(FeatureSettingsStrings.text("common.appName", locale: locale)).rfFont(.page); Text(FeatureSettingsStrings.text("settings.about.license", locale: locale))
            Text(FeatureSettingsStrings.text("settings.about.notificationPrivacy", locale: locale))
            Text(FeatureSettingsStrings.format("settings.version", Self.appVersion, Self.appBuild, locale: locale)).rfFont(.caption).accessibilityIdentifier("about-version")
            Button(FeatureSettingsStrings.text("settings.about.exportDiagnostics", locale: locale)) { onAction(.unavailable(.diagnosticExport)) }
        default:
            group(copy("settings.section.accountDevices"), [
                indexRow(.account, icon: "user-round", detail: "settings.index.account.detail"),
                indexRow(.devices, icon: "smartphone", detail: "settings.index.devices.detail"),
            ])
            group(copy("settings.section.connectionData"), [
                indexRow(.nodes, icon: "network", detail: "settings.index.nodes.detail"),
                indexRow(.backup, icon: "database-backup", detail: "settings.index.backup.detail"),
                indexRow(.permissions, icon: "plug", detail: "settings.index.connectedServices.detail"),
                KitRow(copy("settings.storage.title"), action: { onAction(.unavailable(.storage)) }, icon: "database", value: copy("settings.index.storage.detail"), tag: "settings-storage"),
            ])
            group(copy("settings.section.app"), [
                indexRow(.appearance, icon: "palette", detail: "settings.index.appearance.detail"),
                indexRow(.about, icon: "activity", detail: "settings.index.about.detail"),
                KitRow(label(.systemPermissions), action: { onAction(.open(.systemPermissions)) }, icon: "sliders-horizontal", tag: "settings-system-permissions"),
            ])
            group(copy("settings.section.activity"), [
                KitRow(label(.calls(nil)), action: { onAction(.open(.calls(nil))) }, icon: "phone", tag: "settings-calls"),
                KitRow(label(.cards), action: { onAction(.open(.cards)) }, icon: "app-window", tag: "settings-cards"),
            ])
        }
    }
    @ViewBuilder private func modalContent(_ modal: SettingsModal) -> some View {
        switch modal {
        case .revoke(let device):
            Text(FeatureSettingsStrings.text("settings.devices.revoke.title", locale: locale)).rfFont(.page); KitIdentifierText(device.id).textSelection(.enabled)
            if let origin = device.webOrigin { Text(untrusted: origin).textSelection(.enabled) }
            Text(FeatureSettingsStrings.text("settings.devices.revoke.fact", locale: locale))
            RFHostConfirmationActions(summary: FeatureSettingsStrings.sentence("settings.devices.revoke.summary", [.identifier(device.id)], locale: locale), enabled: !state.busy && !state.unknownMutation, cancelEnabled: !state.busy, confirm: { onAction(.confirmRevoke(device.id)) }, cancel: { onAction(.dismissModal) }).id(device.id)
        case .changeCode:
            Text(copy("settings.account.changeCode")).rfFont(.page)
            Text(copy("settings.account.changeCode.body"))
            #if os(iOS)
            RFSecureEntryForm(fields: [RFSecureEntryField(id: "oldPassphrase", label: copy("settings.account.changeCode.current"), kind: .accountCode),
                                       RFSecureEntryField(id: "passphrase", label: copy("settings.account.changeCode.new"), kind: .accountCode),
                                       RFSecureEntryField(id: "passphraseRepeat", label: copy("settings.account.changeCode.repeat"), kind: .accountCode)],
                              enabled: !state.busy) { onAction(.submitChangeCode(SensitiveSubmission(values: $0, accountCode: .new))) }
                .frame(minHeight: theme.composer_min * 4)
            #endif
            KitButton(copy("settings.account.changeCode.cancel"), action: { onAction(.cancelChangeCode) }, kind: .text, enabled: !state.busy)
        }
    }
    private func copy(_ key: String) -> String { FeatureSettingsStrings.text(key, locale: locale) }
    private func indexRow(_ route: AppRoute, icon: String, detail: String) -> KitRow {
        KitRow(label(route), action: { onAction(.open(route)) }, icon: icon, value: copy(detail), tag: "settings-" + String(describing: route))
    }
    /// A titled card of rows (board MOB-G02): a section label above rows on one surface with dividers.
    private func group(_ title: String, _ rows: [KitRow]) -> some View {
        VStack(alignment: .leading, spacing: theme.gap / 2) {
            Text(title).rfFont(.caption).foregroundStyle(theme.secondary).padding(.horizontal, theme.gap)
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    rows[index]
                    if index < rows.count - 1 { Divider().padding(.leading, theme.gap) }
                }
            }.background(theme.surface_white).clipShape(RoundedRectangle(cornerRadius: theme.radius_card))
        }
    }
    private func row(id: String, title: String, subtitle: String, route: AppRoute) -> some View {
        KitRow(title, action: { onAction(.open(route)) }, value: subtitle.isEmpty ? nil : subtitle, tag: id)
    }
    private func label(_ route: AppRoute) -> String { switch route { case .cards: FeatureSettingsStrings.text("cards.title", locale: locale); case .tasks: FeatureSettingsStrings.text("tasks.title", locale: locale); case .calls: FeatureSettingsStrings.text("calls.title", locale: locale); case .account: FeatureSettingsStrings.text("settings.account.title", locale: locale); case .devices: FeatureSettingsStrings.text("settings.devices.title", locale: locale); case .nodes: FeatureSettingsStrings.text("settings.nodes.title", locale: locale); case .appearance: FeatureSettingsStrings.text("settings.appearance.title", locale: locale); case .privacy: FeatureSettingsStrings.text("settings.privacy.title", locale: locale); case .backup: FeatureSettingsStrings.text("settings.backup.title", locale: locale); case .systemPermissions: FeatureSettingsStrings.text("settings.systemPermissions", locale: locale); case .permissions: FeatureSettingsStrings.text("settings.connectedServices.title", locale: locale); default: FeatureSettingsStrings.text("settings.about.title", locale: locale) } }
}
