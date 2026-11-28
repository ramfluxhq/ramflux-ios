// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
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
        page
            .privacySensitive().rfHidesNavigationBar()
            .sheet(item: Binding(get: { modal }, set: { if $0 == nil { onAction(.dismissModal) } })) { modal in
                NavigationStack { RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                    modalContent(modal)
                    if state.busy { ProgressView(FeatureSettingsStrings.text("settings.busy", locale: locale)) }
                    if let failure = state.failure, !state.codePrompt { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }.padding(theme.gap) } } }.interactiveDismissDisabled(state.busy)
            }

    }
    /// The page: its header (no manual refresh control; the event stream keeps it current), then its content. Only the
    /// devices list pulls to refresh.
    @ViewBuilder private var page: some View {
        if state.route == .devices { scrolling.refreshable { onAction(.refresh) } } else { scrolling }
    }
    private var scrolling: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(title, onBack: { dismiss() }, tag: "settings-header")
            if let pending = state.pendingMutation {
                Text(FeatureSettingsStrings.text("settings.pending", locale: locale))
                Button(FeatureSettingsStrings.text("settings.reconcile", locale: locale)) { onAction(.reconcileOriginal(pending.operationID)) }.disabled(state.busy)
            }
            if state.loading { ProgressView(FeatureSettingsStrings.text("settings.loading", locale: locale)) }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
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
        switch state.route { case .devices, .device: FeatureSettingsStrings.text("settings.devices.title", locale: locale); case .deviceDetails, .accountDetails: FeatureSettingsStrings.text("settings.details.title", locale: locale); case .nodes, .node: FeatureSettingsStrings.text("settings.nodes.title", locale: locale); case .appearance: FeatureSettingsStrings.text("settings.appearance.title", locale: locale)
        case .privacy: FeatureSettingsStrings.text("settings.privacy.title", locale: locale); case .appLock: FeatureSettingsStrings.text("settings.appLock.title", locale: locale); case .backup: FeatureSettingsStrings.text("settings.backup.title", locale: locale); case .account: FeatureSettingsStrings.text("settings.account.title", locale: locale); case .username: FeatureSettingsStrings.text("settings.username.title", locale: locale); case .about: FeatureSettingsStrings.text("settings.about.title", locale: locale); case .systemPermissions: FeatureSettingsStrings.text("settings.systemPermissions", locale: locale); case .delivery: FeatureSettingsStrings.text("settings.delivery", locale: locale); case .permissions: FeatureSettingsStrings.text("settings.connectedServices.title", locale: locale); default: FeatureSettingsStrings.text("settings.title", locale: locale) }
    }
    @ViewBuilder private var content: some View {
        switch state.route {
        case .devices:
            Button(FeatureSettingsStrings.text("settings.devices.link", locale: locale)) { onAction(state.snapshot.accountID == nil ? .unavailable(.pairing) : .open(.pairDevice)) }
            if state.snapshot.accountID == nil { Text(FeatureSettingsStrings.text("settings.devices.noAccount", locale: locale)) }
            ForEach(Array(state.snapshot.devices.enumerated()), id: \.element.id) { index, device in
                row(id: "settings-device-\(index)", title: deviceLabel(device), subtitle: "", route: .device(device.id))
            }
        case .device(let id):
            if let device = state.snapshot.devices.first(where: { $0.id == id }) {
                Text(deviceLabel(device)).rfFont(.page, weight: .semibold)
                if let origin = device.webOrigin { Text(untrusted: origin).textSelection(.enabled); Text(FeatureSettingsStrings.text("settings.devices.webOriginWarning", locale: locale)).foregroundStyle(theme.danger) }
                group(copy("settings.details.section"), [KitRow(copy("settings.details.title"), action: { onAction(.open(.deviceDetails(device.id))) }, tag: "settings-device-details")])
                if !device.isLocal { KitButton(FeatureSettingsStrings.text("settings.devices.revoke", locale: locale), action: { onAction(.requestRevoke(device.id)) }, kind: .destructive, enabled: !state.busy && !state.unknownMutation, tag: "settings-device-revoke") }
            } else { Text(FeatureSettingsStrings.text("settings.devices.missing", locale: locale)) }
        case .deviceDetails(let id):
            // The one place a device id shows: a plain list with a Copy action.
            if let device = state.snapshot.devices.first(where: { $0.id == id }) {
                Text(copy("settings.details.deviceId")).rfFont(.size(theme.size_meta)).foregroundStyle(theme.secondary)
                KitIdentifierText(device.id, tag: "settings-device-id").textSelection(.enabled)
                copyButton(device.id, tag: "settings-device-copy")
                ForEach(device.capabilities, id: \.self) { Text($0).rfFont(.caption).foregroundStyle(theme.secondary) }
            } else { Text(FeatureSettingsStrings.text("settings.devices.missing", locale: locale)) }
        case .accountDetails:
            if let account = state.snapshot.accountID {
                Text(copy("settings.details.accountId")).rfFont(.size(theme.size_meta)).foregroundStyle(theme.secondary)
                KitIdentifierText(account, tag: "settings-account-id").textSelection(.enabled)
                copyButton(account, tag: "settings-account-copy")
            }
        case .nodes:
            if state.snapshot.nodes.isEmpty { Text(FeatureSettingsStrings.text("settings.nodes.empty", locale: locale)) }
            ForEach(Array(state.snapshot.nodes.enumerated()), id: \.element.id) { index, node in row(id: "settings-node-\(index)", title: node.origin, subtitle: node.isDefault ? FeatureSettingsStrings.text("settings.nodes.default", locale: locale) : "", route: .node(node.id)) }
            Button(FeatureSettingsStrings.text("settings.nodes.add", locale: locale)) { onAction(.open(.onboarding)) }
        case .node(let id):
            if let node = state.snapshot.nodes.first(where: { $0.id == id }) {
                Text(untrusted: node.origin).textSelection(.enabled)
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
                    KitRow(Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier, action: { onAction(.openSystemLanguage) }, icon: nil,
                           value: SettingsLanguages.translated.contains(identifier) ? nil : copy("settings.language.pending"),
                           trailing: SettingsLanguages.isCurrent(identifier, locale: locale) ? .check : .none, tag: "settings-language-" + identifier)
                }
            }
        case .account:
            if let account = state.snapshot.accountID {
                let record = state.account ?? AccountRecord(id: account, displayName: "", isLocked: false)
                KitAccountRow(name: record.title(locale: locale), initial: record.initial(locale: locale), large: true, tag: "settings-account-row")
                Text(state.snapshot.networking == .live ? copy("settings.account.networkLive") : copy("settings.account.networkUnconfirmed")).foregroundStyle(theme.secondary)
                group(copy("settings.account.security"), [
                    KitRow(copy("settings.account.lock"), action: { onAction(.lock) }, icon: "lock", value: copy("settings.account.lock.detail"), trailing: .none, enabled: !state.busy && !state.unknownMutation, tag: "settings-lock"),
                    KitRow(copy("settings.account.changeCode"), action: { onAction(.startChangeCode) }, icon: "lock-keyhole", value: copy("settings.account.changeCode.detail"), enabled: !state.busy, tag: "settings-change-code"),
                    KitRow(copy("settings.privacy.title"), action: { onAction(.open(.privacy)) }, icon: "shield", value: copy("settings.index.privacy.detail"), tag: "settings-privacy"),
                    KitRow(copy("settings.details.title"), action: { onAction(.open(.accountDetails)) }, icon: "info", tag: "settings-account-details"),
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
            group(copy("settings.privacy.requests"), [])
            Toggle(isOn: Binding(get: { automatic }, set: { onAction(.requestPolicy(autoAccept: $0)) })) {
                VStack(alignment: .leading, spacing: KitMetrics.labelGap) {
                    Text(copy("settings.privacy.autoAccept"))
                    if !automatic { Text(copy("settings.privacy.autoAccept.off")).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary) }
                }
            }
            .disabled(state.snapshot.requestPolicy == nil || state.busy || state.unknownMutation)
            .accessibilityIdentifier("settings-auto-accept")
            group(copy("settings.privacy.openAccount.section"), [
                KitRow(copy("settings.privacy.openAccount"), icon: "globe", value: copy("settings.state.notAvailable"), trailing: .none, enabled: false, tag: "settings-open-account"),
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
            RFSecureEntryForm(fields: [RFSecureEntryField(id: "passphrase", label: copy("settings.appLock.code.field"), kind: .accountCode)],
                              submitLabel: copy(state.appLockTurningOff ? "settings.appLock.code.submit.turnOff" : "settings.appLock.code.submit.change"), enabled: state.codePrompt) {
                onAction(.submitAccountCode(SensitiveSubmission(values: $0, accountCode: .existing)))
            }
            #endif
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            KitButton(copy("settings.account.changeCode.cancel"), action: { onAction(.cancelAccountCode) }, kind: .text, enabled: true, tag: "settings-app-lock-code-cancel")
        case .revoke(let device):
            Text(FeatureSettingsStrings.text("settings.devices.revoke.title", locale: locale)).rfFont(.page); Text(deviceLabel(device)).rfFont(.body, weight: .semibold)
            if let origin = device.webOrigin { Text(untrusted: origin).textSelection(.enabled) }
            Text(FeatureSettingsStrings.text("settings.devices.revoke.fact", locale: locale))
            RFHostConfirmationActions(summary: FeatureSettingsStrings.sentence("settings.devices.revoke.summary", [.localized(deviceLabel(device))], locale: locale), enabled: !state.busy && !state.unknownMutation, cancelEnabled: !state.busy, destructive: true, confirm: { onAction(.confirmRevoke(device.id)) }, cancel: { onAction(.dismissModal) }).id(device.id)
        case .changeCode:
            Text(copy("settings.account.changeCode")).rfFont(.page)
            Text(copy("settings.account.changeCode.body"))
            #if os(iOS)
            RFSecureEntryForm(fields: [RFSecureEntryField(id: "oldPassphrase", label: copy("settings.account.changeCode.current"), kind: .accountCode),
                                       RFSecureEntryField(id: "passphrase", label: copy("settings.account.changeCode.new"), kind: .accountCode),
                                       RFSecureEntryField(id: "passphraseRepeat", label: copy("settings.account.changeCode.repeat"), kind: .accountCode)],
                              submitLabel: copy("settings.account.changeCode"), enabled: !state.busy) { onAction(.submitChangeCode(SensitiveSubmission(values: $0, accountCode: .new))) }
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
                    RFSecureEntryForm(fields: [RFSecureEntryField(id: "phrase", label: copy("settings.username.claim.phraseField"))], submitLabel: copy("settings.username.claim.submit"), enabled: !state.busy) { onAction(.submitClaimUsername(SensitiveSubmission(values: $0))) }
                    #endif
                }
                KitButton(copy("settings.account.changeCode.cancel"), action: { onAction(.cancelClaimUsername) }, kind: .text, enabled: !state.busy, tag: "username-claim-cancel")
            }
        case .removeLocal(let account):
            let record = state.account ?? AccountRecord(id: account, displayName: "", isLocked: false)
            Text(copy("settings.account.removeLocal.title")).rfFont(.page).accessibilityAddTraits(.isHeader)
            KitAccountRow(name: record.title(locale: locale), initial: record.initial(locale: locale), shortID: record.shortID, tag: "settings-remove-account")
            Text(copy("settings.account.removeLocal.fact"))
            RFHostConfirmationActions(summary: FeatureSettingsStrings.sentence("settings.account.removeLocal.summary", [.untrusted(record.title(locale: locale))], locale: locale), enabled: !state.busy && !state.unknownMutation, cancelEnabled: !state.busy, destructive: true, confirm: { onAction(.confirmRemoveLocal) }, cancel: { onAction(.dismissModal) }).id(account)
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
        if !state.accountOpen {
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
    private func deviceLabel(_ device: DeviceRecord) -> String { copy(device.isLocal ? "settings.devices.thisDevice" : "settings.devices.otherDevice") }
    /// Copies a value to the pasteboard of this device only (no handoff to other devices).
    @ViewBuilder private func copyButton(_ value: String, tag: String) -> some View {
        #if canImport(UIKit)
        KitButton(copy("settings.details.copy"), action: { UIPasteboard.general.setItems([[UTType.plainText.identifier: value]], options: [.localOnly: true]) }, kind: .secondary, tag: tag)
        #endif
    }
    private func row(id: String, title: String, subtitle: String, route: AppRoute) -> some View {
        KitRow(title, action: { onAction(.open(route)) }, value: subtitle.isEmpty ? nil : subtitle, tag: id)
    }
    private func label(_ route: AppRoute) -> String { switch route { case .tasks: FeatureSettingsStrings.text("tasks.title", locale: locale); case .account: FeatureSettingsStrings.text("settings.account.title", locale: locale); case .devices: FeatureSettingsStrings.text("settings.devices.title", locale: locale); case .nodes: FeatureSettingsStrings.text("settings.nodes.title", locale: locale); case .appearance: FeatureSettingsStrings.text("settings.appearance.title", locale: locale); case .privacy: FeatureSettingsStrings.text("settings.privacy.title", locale: locale); case .appLock: FeatureSettingsStrings.text("settings.appLock.title", locale: locale); case .backup: FeatureSettingsStrings.text("settings.backup.title", locale: locale); case .systemPermissions: FeatureSettingsStrings.text("settings.systemPermissions", locale: locale); case .delivery: FeatureSettingsStrings.text("settings.delivery", locale: locale); case .permissions: FeatureSettingsStrings.text("settings.connectedServices.title", locale: locale); default: FeatureSettingsStrings.text("settings.about.title", locale: locale) } }
}
