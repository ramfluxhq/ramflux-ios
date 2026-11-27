// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
#if RAMFLUX_CARD_GALLERY
import FeatureCards
#endif
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
                    if let failure = state.failure, !state.codePrompt { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }.padding(theme.gap) } } }.interactiveDismissDisabled(state.busy)
            }

    }
    private static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-" }
    private static var appBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-" }
    private var modal: SettingsModal? {
        if let device = state.pendingRevoke { return .revoke(device) }
        if state.codePrompt { return .appLockCode }
        if state.changingCode { return .changeCode }
        if state.confirmingRemoval, let account = state.snapshot.accountID { return .removeLocal(account) }
        if state.claim != nil { return .claimUsername }
        return nil
    }
    private var title: String {
        switch state.route { case .devices, .device: FeatureSettingsStrings.text("settings.devices.title", locale: locale); case .nodes, .node: FeatureSettingsStrings.text("settings.nodes.title", locale: locale); case .appearance: FeatureSettingsStrings.text("settings.appearance.title", locale: locale)
        case .privacy: FeatureSettingsStrings.text("settings.privacy.title", locale: locale); case .appLock: FeatureSettingsStrings.text("settings.appLock.title", locale: locale); case .backup: FeatureSettingsStrings.text("settings.backup.title", locale: locale); case .account: FeatureSettingsStrings.text("settings.account.title", locale: locale); case .username: FeatureSettingsStrings.text("settings.username.title", locale: locale); case .about: FeatureSettingsStrings.text("settings.about.title", locale: locale); case .systemPermissions: FeatureSettingsStrings.text("settings.systemPermissions", locale: locale); case .delivery: FeatureSettingsStrings.text("settings.delivery", locale: locale); case .permissions: FeatureSettingsStrings.text("settings.connectedServices.title", locale: locale); default: FeatureSettingsStrings.text("settings.title", locale: locale) }
    }
    @ViewBuilder private var content: some View {
        switch state.route {
        case .devices:
            Button(FeatureSettingsStrings.text("settings.devices.link", locale: locale)) { onAction(state.snapshot.accountID == nil ? .unavailable(.pairing) : .open(.pairDevice)) }
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
                group(copy("settings.account.thisPhone"), [
                    KitRow(copy("settings.account.signOut"), action: { onAction(.signOut) }, icon: "user-lock", value: copy("settings.account.signOut.detail"), trailing: .none, enabled: !state.busy && !state.unknownMutation, tag: "settings-sign-out"),
                    KitRow(copy("settings.account.removeLocal"), action: { onAction(.requestRemoveLocal) }, icon: "trash-2", value: copy("settings.account.removeLocal.detail"), trailing: .none, enabled: !state.busy && !state.unknownMutation, tag: "settings-remove-local"),
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
                KitRow(copy("settings.privacy.username"), action: { onAction(.open(.username)) }, icon: "at-sign", value: state.username?.name.map { "@" + $0 }, tag: "settings-username"),
            ])
            group(copy("settings.appLock.section"), [
                KitRow(copy("settings.appLock.title"), action: { onAction(.open(.appLock)) }, icon: "lock", value: appLockSummary, tag: "settings-app-lock"),
            ])
        case .appLock:
            appLockContent
        case .username:
            usernameContent
        case .permissions:
            Text(FeatureSettingsStrings.text("settings.connectedServices.explanation", locale: locale))
            Button(FeatureSettingsStrings.text("settings.connectedServices.manage", locale: locale)) { onAction(.unavailable(.connectedServices)) }
        case .about:
            Text(FeatureSettingsStrings.text("common.appName", locale: locale)).rfFont(.page); Text(FeatureSettingsStrings.text("settings.about.license", locale: locale))
            Text(FeatureSettingsStrings.text("settings.about.notificationPrivacy", locale: locale))
            Text(FeatureSettingsStrings.format("settings.version", Self.appVersion, Self.appBuild, locale: locale)).rfFont(.caption).accessibilityIdentifier("about-version")
            Button(FeatureSettingsStrings.text("settings.about.exportDiagnostics", locale: locale)) { onAction(.unavailable(.diagnosticExport)) }
#if RAMFLUX_CARD_GALLERY
            NavigationLink("Card gallery") { CardFixtureGalleryView() }.accessibilityIdentifier("about-card-gallery")
#endif
        default:
            group(copy("settings.section.accountDevices"), [
                indexRow(.account, icon: "user-round", detail: "settings.index.account.detail"),
                indexRow(.devices, icon: "smartphone", detail: "settings.index.devices.detail"),
            ])
            group(copy("settings.section.connectionData"), [
                indexRow(.nodes, icon: "network", detail: "settings.index.nodes.detail"),
                indexRow(.backup, icon: "database-backup", detail: "settings.index.backup.detail"),
                indexRow(.permissions, icon: "plug", detail: "settings.index.connectedServices.detail"),
                KitRow(copy("settings.storage.title"), action: { onAction(.open(.mediaStorage)) }, icon: "database", value: copy("settings.index.storage.detail"), tag: "settings-storage"),
            ])
            group(copy("settings.section.app"), [
                indexRow(.appearance, icon: "palette", detail: "settings.index.appearance.detail"),
                indexRow(.about, icon: "activity", detail: "settings.index.about.detail"),
                KitRow(label(.systemPermissions), action: { onAction(.open(.systemPermissions)) }, icon: "sliders-horizontal", tag: "settings-system-permissions"),
                KitRow(label(.delivery), action: { onAction(.open(.delivery)) }, icon: "bell", tag: "settings-delivery"),
            ])
        }
    }
    @ViewBuilder private func modalContent(_ modal: SettingsModal) -> some View {
        switch modal {
        case .appLockCode:
            // The code is typed into the secure form only; the page keeps no copy of it. Cancel is the only way out while the request is open.
            Text(copy("settings.appLock.code.title")).rfFont(.page)
            Text(copy(state.appLockTurningOff ? "settings.appLock.code.turnOff" : "settings.appLock.code.longer")).foregroundStyle(theme.secondary)
            #if os(iOS)
            RFSecureEntryForm(fields: [RFSecureEntryField(id: "passphrase", label: copy("settings.appLock.code.field"), kind: .accountCode)], enabled: state.codePrompt) {
                onAction(.submitAccountCode(SensitiveSubmission(values: $0, accountCode: .existing)))
            }
            .frame(minHeight: theme.composer_min * 2)
            #endif
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            KitButton(copy("settings.account.changeCode.cancel"), action: { onAction(.cancelAccountCode) }, kind: .text, enabled: true, tag: "settings-app-lock-code-cancel")
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
        case .claimUsername:
            if let claim = state.claim {
                Text(copy("settings.username.claim.title")).rfFont(.page)
                if claim.step == .name {
                    TextField(copy("settings.username.claim.name"), text: Binding(get: { claim.name }, set: { onAction(.claimNameChanged($0)) }))
                        .textFieldStyle(.roundedBorder).rfAddressInput().disabled(state.busy).accessibilityIdentifier("username-claim-name")
                    KitButton(copy("settings.username.claim.continue"), action: { onAction(.continueClaimUsername) }, kind: .primary, enabled: !state.busy && UsernameInput.name(claim.name) != nil, tag: "username-claim-continue")
                } else {
                    Text(copy("settings.username.claim.phrase")).rfFont(.body, weight: .semibold)
                    Text(copy("settings.username.claim.phraseNote")).foregroundStyle(theme.secondary)
                    #if os(iOS)
                    RFSecureEntryForm(fields: [RFSecureEntryField(id: "phrase", label: copy("settings.username.claim.phraseField"))], enabled: !state.busy) { onAction(.submitClaimUsername(SensitiveSubmission(values: $0))) }
                        .frame(minHeight: theme.composer_min * 2)
                    #endif
                }
                KitButton(copy("settings.account.changeCode.cancel"), action: { onAction(.cancelClaimUsername) }, kind: .text, enabled: !state.busy, tag: "username-claim-cancel")
            }
        case .removeLocal(let account):
            Text(copy("settings.account.removeLocal.title")).rfFont(.page); KitIdentifierText(account).textSelection(.enabled)
            Text(copy("settings.account.removeLocal.fact"))
            RFHostConfirmationActions(summary: FeatureSettingsStrings.sentence("settings.account.removeLocal.summary", [.identifier(account)], locale: locale), enabled: !state.busy && !state.unknownMutation, cancelEnabled: !state.busy, confirm: { onAction(.confirmRemoveLocal) }, cancel: { onAction(.dismissModal) }).id(account)
        }
    }
    private func copy(_ key: String) -> String { FeatureSettingsStrings.text(key, locale: locale) }
    /// The Username page: the directory's status of this account's name. Claiming or changing it opens the claim sheet.
    @ViewBuilder private var usernameContent: some View {
        if state.snapshot.accountID == nil {
            Text(copy("settings.username.noAccount")).foregroundStyle(theme.secondary)
        } else if state.usernameLoading {
            ProgressView(copy("settings.loading"))
        } else {
            switch state.username?.state {
            case .committed?:
                Text(untrusted: "@" + (state.username?.name ?? "")).rfFont(.page).textSelection(.enabled)
                Text(copy("settings.username.committed")).foregroundStyle(theme.secondary)
                KitButton(copy("settings.username.change"), action: { onAction(.startClaimUsername) }, kind: .secondary, enabled: !state.busy, tag: "settings-username-change")
            case .pending?:
                Text(copy("settings.username.pending")).foregroundStyle(theme.secondary)
                KitButton(copy("settings.username.refresh"), action: { onAction(.refreshUsername) }, kind: .secondary, enabled: !state.busy, tag: "settings-username-refresh")
            case .aborted?:
                Text(copy("settings.username.aborted")).foregroundStyle(theme.danger)
                KitButton(copy("settings.username.claim"), action: { onAction(.startClaimUsername) }, kind: .primary, enabled: !state.busy, tag: "settings-username-claim")
            case .empty?, nil:
                Text(copy("settings.username.none"))
                KitButton(copy("settings.username.claim"), action: { onAction(.startClaimUsername) }, kind: .primary, enabled: !state.busy, tag: "settings-username-claim")
            }
            Text(copy("settings.username.note")).rfFont(.caption).foregroundStyle(theme.secondary)
        }
    }
    private var appLockSummary: String? { state.appLock.map { copy($0.enabled ? "settings.appLock.on" : "settings.appLock.off") } }
    /// The App lock page (Settings > Privacy). Off by default. Unlock is by account code only: the biometric row
    /// stays disabled until the core offers presence unlock.
    @ViewBuilder private var appLockContent: some View {
        if state.snapshot.accountID == nil {
            Text(copy("settings.appLock.noAccount")).foregroundStyle(theme.secondary)
        } else if let record = state.appLock {
            // The clock ticks once a second so the wait countdown and the weakening controls follow the monotonic deadline.
            TimelineView(.periodic(from: .now, by: 1)) { _ in appLockControls(record, now: ContinuousClock.now) }
        } else {
            ProgressView(copy("settings.loading"))
        }
    }
    /// Weakening (turning off, or a longer timeout) waits for the account-code wait to end and is never offered when
    /// the code is used up. Strengthening stays enabled: it needs no code.
    @ViewBuilder private func appLockControls(_ record: AppLockRecord, now: ContinuousClock.Instant) -> some View {
        let waiting = state.codeRetryDeadline.map { now < $0 } ?? false
        let weakeningBlocked = waiting || record.codeAttemptsExhausted
        let controlsDisabled = state.busy || state.unknownMutation || record.state == .unavailable
        if record.state == .unavailable { Text(copy("settings.appLock.unavailable")).foregroundStyle(theme.danger) }
        if record.codeAttemptsExhausted {
            Text(copy("settings.appLock.code.exhausted")).foregroundStyle(theme.danger)
            KitButton(copy("settings.appLock.code.restore"), action: { onAction(.open(.recoverAccount)) }, kind: .primary, enabled: !state.busy, tag: "settings-app-lock-restore")
        } else if let deadline = state.codeRetryDeadline, now < deadline {
            Text(FeatureSettingsStrings.format("settings.appLock.code.wait", Self.countdown(deadline - now), locale: locale)).foregroundStyle(theme.secondary)
        }
        Toggle(copy("settings.appLock.toggle"), isOn: Binding(get: { record.enabled }, set: { onAction(.configureAppLock(enabled: $0, timeoutMilliseconds: record.timeoutMilliseconds)) }))
            .disabled(controlsDisabled || (record.enabled && weakeningBlocked))
        if record.enabled {
            Picker(copy("settings.appLock.timeout"), selection: Binding(get: { record.timeoutMilliseconds }, set: { onAction(.configureAppLock(enabled: true, timeoutMilliseconds: $0)) })) {
                ForEach(AppLockTimeout.allCases) { Text(appLockTimeoutLabel($0)).tag($0.rawValue) }
            }.disabled(controlsDisabled)
        }
            Text(copy("settings.appLock.explanation")).rfFont(.caption).foregroundStyle(theme.secondary)
            group(copy("settings.appLock.biometric.section"), [
                KitRow(copy("settings.appLock.biometric"), icon: "scan-face", value: copy("settings.appLock.biometric.detail"), enabled: false, tag: "settings-app-lock-biometric"),
            ])
    }
    /// The remaining wait as `m:ss`, rounded up so the last second still shows.
    private static func countdown(_ remaining: Duration) -> String {
        let seconds = max(0, Int((remaining / .seconds(1)).rounded(.up)))
        return "\(seconds / 60):\(seconds % 60 < 10 ? "0" : "")\(seconds % 60)"
    }
    private func appLockTimeoutLabel(_ timeout: AppLockTimeout) -> String {
        switch timeout {
        case .immediately: copy("settings.appLock.timeout.immediately")
        case .oneMinute: copy("settings.appLock.timeout.oneMinute")
        case .fiveMinutes: copy("settings.appLock.timeout.fiveMinutes")
        case .fifteenMinutes: copy("settings.appLock.timeout.fifteenMinutes")
        case .oneHour: copy("settings.appLock.timeout.oneHour")
        }
    }
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
    private func label(_ route: AppRoute) -> String { switch route { case .tasks: FeatureSettingsStrings.text("tasks.title", locale: locale); case .account: FeatureSettingsStrings.text("settings.account.title", locale: locale); case .devices: FeatureSettingsStrings.text("settings.devices.title", locale: locale); case .nodes: FeatureSettingsStrings.text("settings.nodes.title", locale: locale); case .appearance: FeatureSettingsStrings.text("settings.appearance.title", locale: locale); case .privacy: FeatureSettingsStrings.text("settings.privacy.title", locale: locale); case .appLock: FeatureSettingsStrings.text("settings.appLock.title", locale: locale); case .backup: FeatureSettingsStrings.text("settings.backup.title", locale: locale); case .systemPermissions: FeatureSettingsStrings.text("settings.systemPermissions", locale: locale); case .delivery: FeatureSettingsStrings.text("settings.delivery", locale: locale); case .permissions: FeatureSettingsStrings.text("settings.connectedServices.title", locale: locale); default: FeatureSettingsStrings.text("settings.about.title", locale: locale) } }
}
