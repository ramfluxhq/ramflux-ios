// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
public struct SettingsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: SettingsState
    public let onAction: (SettingsAction) -> Void
    public init(state: SettingsState, onAction: @escaping (SettingsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            RFPageHeader(title: title, subtitle: "", theme: theme, leading: { EmptyView() }, trailing: { EmptyView() })
            if state.loading { ProgressView(FeatureSettingsStrings.text("copy.509c3e500d38", locale: locale)) }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
            .navigationTitle(title).privacySensitive()
            .toolbar { Button(FeatureSettingsStrings.text("copy.0e9161011702", locale: locale), systemImage: "arrow.clockwise") { onAction(.refresh) } }
            .sheet(item: Binding(get: { modal }, set: { if $0 == nil { onAction(.dismissModal) } })) { modal in
                NavigationStack { RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                    modalContent(modal)
                    if state.busy { ProgressView(FeatureSettingsStrings.text("copy.1d70139d93b4", locale: locale)) }
                    if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }.padding(theme.gap) } }.toolbar { Button(FeatureSettingsStrings.text("copy.19766ed6ccb2", locale: locale)) { onAction(.dismissModal) }.disabled(state.busy) } }.interactiveDismissDisabled(state.busy)
            }
            .fileImporter(isPresented: Binding(get: { state.importSelecting }, set: { if !$0 { onAction(.cancelImport) } }), allowedContentTypes: [.data]) { result in
                switch result { case .success(let url): onAction(.importSelected(url)); case .failure: onAction(.cancelImport) }
            }
    }
    private var modal: SettingsModal? {
        if let device = state.pendingRevoke { return .revoke(device) }
        if let intent = state.backupIntent { return .backup(intent) }
        return state.shareURL.map(SettingsModal.share)
    }
    private var title: String {
        switch state.route { case .devices, .device: FeatureSettingsStrings.text("copy.6f3cba5e5a8e", locale: locale); case .nodes, .node: FeatureSettingsStrings.text("copy.7ac362063b9f", locale: locale); case .appearance: FeatureSettingsStrings.text("copy.dfe87d5e5bba", locale: locale)
        case .privacy: FeatureSettingsStrings.text("copy.54a57c3147c4", locale: locale); case .backup: FeatureSettingsStrings.text("copy.32c46f7c19e7", locale: locale); case .account: FeatureSettingsStrings.text("copy.e8e01909593a", locale: locale); case .about: FeatureSettingsStrings.text("copy.5548cdf42bc6", locale: locale); case .permissions: FeatureSettingsStrings.text("copy.5da7ca5ffda2", locale: locale); default: FeatureSettingsStrings.text("copy.74a883a037bc", locale: locale) }
    }
    @ViewBuilder private var content: some View {
        switch state.route {
        case .devices:
            Button(FeatureSettingsStrings.text("copy.01a234cb80c4", locale: locale)) { onAction(.unavailable(.pairing)) }
            if state.snapshot.accountID == nil { Text(FeatureSettingsStrings.text("copy.21696a2dd237", locale: locale)) }
            ForEach(state.snapshot.devices) { device in
                row(id: device.id, title: device.id, subtitle: device.isLocal ? FeatureSettingsStrings.text("copy.d052579c6a31", locale: locale) : FeatureSettingsStrings.text("copy.a7ba6a12696a", locale: locale), route: .device(device.id))
            }
        case .device(let id):
            if let device = state.snapshot.devices.first(where: { $0.id == id }) {
                Text(device.id).textSelection(.enabled); Text(device.isLocal ? FeatureSettingsStrings.text("copy.d052579c6a31", locale: locale) : FeatureSettingsStrings.text("copy.a7ba6a12696a", locale: locale))
                ForEach(device.capabilities, id: \.self) { Text($0).font(theme.captionFont) }
                if let origin = device.webOrigin { Text(origin).textSelection(.enabled); Text(FeatureSettingsStrings.text("copy.2aeef869fc03", locale: locale)).foregroundStyle(theme.danger) }
                if !device.isLocal { Button(FeatureSettingsStrings.text("copy.548139b9e4bc", locale: locale), role: .destructive) { onAction(.requestRevoke(device.id)) }.disabled(state.busy || state.unknownMutation) }
            } else { Text(FeatureSettingsStrings.text("copy.cfd40d618f8e", locale: locale)) }
        case .nodes:
            if state.snapshot.nodes.isEmpty { Text(FeatureSettingsStrings.text("copy.103639eac40d", locale: locale)) }
            ForEach(state.snapshot.nodes) { node in row(id: node.id, title: node.origin, subtitle: node.isDefault ? FeatureSettingsStrings.text("copy.61c34ddaed9f", locale: locale) : node.id, route: .node(node.id)) }
            Button(FeatureSettingsStrings.text("copy.1ba44456db5e", locale: locale)) { onAction(.open(.onboarding)) }
        case .node(let id):
            if let node = state.snapshot.nodes.first(where: { $0.id == id }) {
                Text(node.origin).textSelection(.enabled); Text(node.id)
                if let key = node.publicKey { Text(key).font(theme.captionFont).textSelection(.enabled) }
                Text(node.enabled ? FeatureSettingsStrings.text("copy.92c1cdfdf4cb", locale: locale) : FeatureSettingsStrings.text("copy.75081b593d15", locale: locale))
                Button(FeatureSettingsStrings.text("copy.1440cdc8faae", locale: locale)) { onAction(.setDefault(node.id)) }.disabled(state.busy || state.unknownMutation || !node.enabled)
            }
        case .appearance:
            Picker(FeatureSettingsStrings.text("copy.3907fa7f8072", locale: locale), selection: Binding(get: { state.appearance }, set: { onAction(.appearance($0)) })) {
                Text(FeatureSettingsStrings.text("copy.6725e7bbcd28", locale: locale)).tag(AppearanceMode.system); ForEach(RFThemeRegistry.themes) { entry in
                    if let mode = AppearanceMode(rawValue: entry.id) { Text(RFDesignStrings.text(entry.labelKey, locale: locale)).tag(mode) }
                }
            }.pickerStyle(.segmented).disabled(state.busy)
            Text(FeatureSettingsStrings.text("copy.f4faccd0c67d", locale: locale))
        case .account:
            if let account = state.snapshot.accountID {
                Text(account).textSelection(.enabled)
                Text(state.snapshot.networking == .live ? FeatureSettingsStrings.text("copy.c322afd72270", locale: locale) : FeatureSettingsStrings.text("copy.ef187b43e1da", locale: locale))
                Button(FeatureSettingsStrings.text("copy.18a702c5399d", locale: locale), systemImage: "lock") { onAction(.lock) }.disabled(state.busy || state.unknownMutation)
            } else { Button(FeatureSettingsStrings.text("copy.ececf6457703", locale: locale)) { onAction(.open(.onboarding)) } }
            Picker(FeatureSettingsStrings.text("copy.d822cfc2d621", locale: locale), selection: Binding(get: { state.retentionSeconds }, set: { onAction(.retention($0)) })) {
                Text(FeatureSettingsStrings.text("copy.f8b8883f0c9d", locale: locale)).tag(Int64(3600)); Text(FeatureSettingsStrings.text("copy.fa665d95d29e", locale: locale)).tag(Int64(86400)); Text(FeatureSettingsStrings.text("copy.7f920bb639c9", locale: locale)).tag(Int64(604800))
            }
            Button(FeatureSettingsStrings.text("copy.0370bcb8f79e", locale: locale)) { onAction(.saveRetention) }.disabled(state.busy || state.unknownMutation || state.snapshot.accountID == nil)
            Text(FeatureSettingsStrings.text("copy.e6728991cc16", locale: locale)).font(theme.captionFont)
        case .privacy:
            Text(FeatureSettingsStrings.format("privacy.requestApproval", AppDataStrings.status(state.snapshot.requestPolicy, locale: locale), locale: locale))
            if state.snapshot.requestPolicy == "auto_accept" { Button(FeatureSettingsStrings.text("copy.68c7da5c0ea2", locale: locale)) { onAction(.manualRequests) }.disabled(state.busy || state.unknownMutation) }
            Button(FeatureSettingsStrings.text("copy.495799da310f", locale: locale)) { onAction(.unavailable(.openAccount)) }
        case .backup: backupContent
        case .permissions:
            Text(FeatureSettingsStrings.text("copy.f2c50525757d", locale: locale))
            Button(FeatureSettingsStrings.text("copy.8542eab86011", locale: locale)) { onAction(.unavailable(.connectedServices)) }
        case .about:
            Text(FeatureSettingsStrings.text("copy.28f2d4300544", locale: locale)).font(theme.pageFont); Text(FeatureSettingsStrings.text("copy.ab50f8bde1ab", locale: locale))
            Text(FeatureSettingsStrings.text("copy.902c4d2aff10", locale: locale))
            Button(FeatureSettingsStrings.text("copy.4d9b709adaef", locale: locale)) { onAction(.unavailable(.diagnosticExport)) }
        default:
            ForEach([AppRoute.account, .devices, .nodes, .appearance, .privacy, .backup, .permissions, .about], id: \.self) { route in row(id: label(route), title: label(route), subtitle: "", route: route) }
        }
    }
    @ViewBuilder private var backupContent: some View {
        Text(FeatureSettingsStrings.text("copy.16b8400e47c7", locale: locale))
        HStack { Button(FeatureSettingsStrings.text("copy.7e9d26bfdf5c", locale: locale)) { onAction(.createBackup) }; Button(FeatureSettingsStrings.text("copy.150d3477a59a", locale: locale)) { onAction(.selectImport) } }.disabled(!state.attended || state.busy || state.unknownMutation)
        if !state.attended { Text(FeatureSettingsStrings.text("copy.53a6e343d08e", locale: locale)).font(theme.captionFont) }
        ForEach(state.jobs) { job in
            VStack(alignment: .leading, spacing: theme.gap / 2) {
                Text(FeatureSettingsStrings.format("backup.jobSummary", AppDataStrings.status(job.kind, locale: locale), AppDataStrings.status(job.state, locale: locale), locale: locale)).font(theme.bodyFont.weight(.semibold)); Text(job.id).font(theme.captionFont)
                if let id = job.accountID { LabeledContent(FeatureSettingsStrings.text("copy.c031af609a56", locale: locale), value: id) }
                if job.state == "verified", job.kind == "restore" { Button(FeatureSettingsStrings.text("copy.967bd624c2d5", locale: locale)) { onAction(.requestInstall(job.id)) } }
                if job.state == "done", job.shareURL != nil { Button(FeatureSettingsStrings.text("copy.f697c1b7ba14", locale: locale)) { onAction(.share(job.id)) } }
                if ["preparing","writing","verifying"].contains(job.state) { Button(FeatureSettingsStrings.text("copy.a5032d26d61d", locale: locale), role: .destructive) { onAction(.cancelJob(job.id)) } }
            }.disabled(state.busy || state.unknownMutation)
        }
        Text(FeatureSettingsStrings.text("copy.948d4afeba2b", locale: locale)).font(theme.captionFont)
    }
    @ViewBuilder private func modalContent(_ modal: SettingsModal) -> some View {
        switch modal {
        case .revoke(let device):
            Text(FeatureSettingsStrings.text("copy.e7e35e2c6b94", locale: locale)).font(theme.pageFont); Text(device.id).textSelection(.enabled)
            if let origin = device.webOrigin { Text(origin).textSelection(.enabled) }
            Text(FeatureSettingsStrings.text("copy.20cb3df08ed4", locale: locale))
            RFHostHoldToConfirm(label: FeatureSettingsStrings.text("copy.953e554960b1", locale: locale), enabled: !state.busy && !state.unknownMutation) { onAction(.confirmRevoke(device.id)) }.id(device.id)
        case .share(let url):
            Text(FeatureSettingsStrings.text("copy.53e6cce56bee", locale: locale)).font(theme.pageFont)
            ShareLink(item: url) { Label(FeatureSettingsStrings.text("copy.cf211c6c4ba0", locale: locale), systemImage: "square.and.arrow.up") }
        case .backup(let intent):
            switch intent {
            case .create: Text(FeatureSettingsStrings.text("copy.8b2af02164d1", locale: locale)).font(theme.pageFont)
            case .verify(let url): Text(FeatureSettingsStrings.text("copy.048d49a605a8", locale: locale)).font(theme.pageFont); Text(url.lastPathComponent)
            case .install(let job):
                Text(FeatureSettingsStrings.text("copy.fbd0df19e20e", locale: locale)).font(theme.pageFont); Text(job.accountID ?? FeatureSettingsStrings.text("copy.72830405351a", locale: locale)).textSelection(.enabled)
                Text(job.merge == true ? FeatureSettingsStrings.text("copy.8802d45c10a5", locale: locale) : FeatureSettingsStrings.text("copy.6491d8373952", locale: locale))
                Text(FeatureSettingsStrings.text("copy.e58ff986d436", locale: locale))
                RFHostHoldToConfirm(label: FeatureSettingsStrings.text("copy.eea8986208e1", locale: locale), enabled: !state.busy && !state.unknownMutation) { onAction(.restoreHold(job.id, job.sequence)) }.id(job.id + ":" + String(job.sequence))
            }
            #if os(iOS)
            RFSecretFields(labels: [("passphrase", FeatureSettingsStrings.text("copy.e7611f0537df", locale: locale))], enabled: !state.busy && !state.unknownMutation && (isInstall(intent) ? state.restoreHeld : true)) { onAction(.submitBackup(SensitiveSubmission(values: $0))) }.frame(minHeight: theme.composer_min * 3).id(intent.id)
            #else
            Text(FeatureSettingsStrings.text("copy.a1bcb108941e", locale: locale))
            #endif
        }
    }
    private func isInstall(_ intent: BackupIntent) -> Bool { if case .install = intent { true } else { false } }
    private func row(id: String, title: String, subtitle: String, route: AppRoute) -> some View {
        RFListRow(id: id, title: title, subtitle: subtitle, theme: theme, leading: { EmptyView() }, trailing: { Image(systemName: "chevron.right").accessibilityHidden(true) }) { onAction(.open(route)) }
    }
    private func label(_ route: AppRoute) -> String { switch route { case .account: FeatureSettingsStrings.text("copy.e8e01909593a", locale: locale); case .devices: FeatureSettingsStrings.text("copy.6f3cba5e5a8e", locale: locale); case .nodes: FeatureSettingsStrings.text("copy.7ac362063b9f", locale: locale); case .appearance: FeatureSettingsStrings.text("copy.dfe87d5e5bba", locale: locale); case .privacy: FeatureSettingsStrings.text("copy.54a57c3147c4", locale: locale); case .backup: FeatureSettingsStrings.text("copy.32c46f7c19e7", locale: locale); case .permissions: FeatureSettingsStrings.text("copy.5da7ca5ffda2", locale: locale); default: FeatureSettingsStrings.text("copy.5548cdf42bc6", locale: locale) } }
}
