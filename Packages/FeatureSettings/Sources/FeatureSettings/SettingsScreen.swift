// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
public struct SettingsScreen: View {
    @Environment(\.colorScheme) private var scheme
    public let state: SettingsState
    public let onAction: (SettingsAction) -> Void
    public init(state: SettingsState, onAction: @escaping (SettingsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: RFTheme.adaptive(scheme).gap) {
            RFPageHeader(title: title, subtitle: "", theme: RFTheme.adaptive(scheme), leading: { EmptyView() }, trailing: { EmptyView() })
            if state.loading { ProgressView("Loading settings") }
            content
            if let failure = state.failure { RFFailureView(title: failure.title, message: failure.message) }
        }.padding().frame(maxWidth: RFTheme.adaptive(scheme).column_max, alignment: .leading).frame(maxWidth: .infinity) } }
            .navigationTitle(title).privacySensitive()
            .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { onAction(.refresh) } }
            .sheet(item: Binding(get: { modal }, set: { if $0 == nil { onAction(.dismissModal) } })) { modal in
                NavigationStack { RFPage { ScrollView { VStack(alignment: .leading, spacing: 16) {
                    modalContent(modal)
                    if state.busy { ProgressView("Applying operation") }
                    if let failure = state.failure { RFFailureView(title: failure.title, message: failure.message) }
                }.padding() } }.toolbar { Button("Cancel") { onAction(.dismissModal) }.disabled(state.busy) } }.interactiveDismissDisabled(state.busy)
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
        switch state.route { case .devices, .device: "My devices"; case .nodes, .node: "Nodes"; case .appearance: "Appearance and language"
        case .privacy: "Privacy"; case .backup: "Backup and recovery"; case .account: "Account and security"; case .about: "About and diagnostics"; case .permissions: "Connected services"; default: "Settings" }
    }
    @ViewBuilder private var content: some View {
        switch state.route {
        case .devices:
            Button("Link new device") { onAction(.unavailable(.pairing)) }
            if state.snapshot.accountID == nil { Text("Open an account to read its devices.") }
            ForEach(state.snapshot.devices) { device in
                row(id: device.id, title: device.id, subtitle: device.isLocal ? "This device" : "Linked device", route: .device(device.id))
            }
        case .device(let id):
            if let device = state.snapshot.devices.first(where: { $0.id == id }) {
                Text(device.id).textSelection(.enabled); Text(device.isLocal ? "This device" : "Linked device")
                ForEach(device.capabilities, id: \.self) { Text($0).font(.caption) }
                if let origin = device.webOrigin { Text(origin).textSelection(.enabled); Text("The origin's operator can read plaintext on this web device.").foregroundStyle(RFTheme.adaptive(scheme).danger) }
                if !device.isLocal { Button("Revoke device", role: .destructive) { onAction(.requestRevoke(device.id)) }.disabled(state.busy || state.unknownMutation) }
            } else { Text("This device record is unavailable. Refresh before continuing.") }
        case .nodes:
            if state.snapshot.nodes.isEmpty { Text("No saved nodes were returned.") }
            ForEach(state.snapshot.nodes) { node in row(id: node.id, title: node.origin, subtitle: node.isDefault ? "Default node" : node.id, route: .node(node.id)) }
            Button("Add node") { onAction(.open(.onboarding)) }
        case .node(let id):
            if let node = state.snapshot.nodes.first(where: { $0.id == id }) {
                Text(node.origin).textSelection(.enabled); Text(node.id)
                if let key = node.publicKey { Text(key).font(.caption).textSelection(.enabled) }
                Text(node.enabled ? "Enabled" : "Disabled")
                Button("Use as default") { onAction(.setDefault(node.id)) }.disabled(state.busy || state.unknownMutation || !node.enabled)
            }
        case .appearance:
            Picker("Appearance", selection: Binding(get: { state.appearance }, set: { onAction(.appearance($0)) })) {
                Text("System").tag(AppearanceMode.system); Text("Light").tag(AppearanceMode.light); Text("Dark").tag(AppearanceMode.dark)
            }.pickerStyle(.segmented).disabled(state.busy)
            Text("Language follows the per-app language in system settings.")
        case .account:
            if let account = state.snapshot.accountID {
                Text(account).textSelection(.enabled)
                Text(state.snapshot.networking == .live ? "Network connection is live" : "Network connection has not been confirmed")
                Button("Lock account", systemImage: "lock") { onAction(.lock) }.disabled(state.busy || state.unknownMutation)
            } else { Button("Open or create an account") { onAction(.open(.onboarding)) } }
            Picker("Retention for newly sent messages", selection: Binding(get: { state.retentionSeconds }, set: { onAction(.retention($0)) })) {
                Text("1 hour").tag(Int64(3600)); Text("1 day").tag(Int64(86400)); Text("7 days").tag(Int64(604800))
            }
            Button("Save retention") { onAction(.saveRetention) }.disabled(state.busy || state.unknownMutation || state.snapshot.accountID == nil)
            Text("Existing messages keep their original retention.").font(.caption)
        case .privacy:
            Text("Request approval: \(state.snapshot.requestPolicy ?? "Unavailable")")
            if state.snapshot.requestPolicy == "auto_accept" { Button("Require manual approval") { onAction(.manualRequests) }.disabled(state.busy || state.unknownMutation) }
            Button("Open account and username reachability") { onAction(.unavailable(.openAccount)) }
        case .backup: backupContent
        case .permissions:
            Text("Connected services can request actions. Approvals must show the exact operation and origin in the native host.")
            Button("Manage services") { onAction(.unavailable(.connectedServices)) }
        case .about:
            Text("Ramflux").font(.title); Text("AGPL-3.0-or-later with App Store Exception")
            Text("Notifications contain a generic alert. No message preview is sent through push.")
            Button("Export sanitized diagnostics") { onAction(.unavailable(.diagnosticExport)) }
        default:
            ForEach([AppRoute.account, .devices, .nodes, .appearance, .privacy, .backup, .permissions, .about], id: \.self) { route in row(id: label(route), title: label(route), subtitle: "", route: route) }
        }
    }
    @ViewBuilder private var backupContent: some View {
        Text("Archives are encrypted. Keep the backup passphrase separate from the archive.")
        HStack { Button("Create encrypted backup") { onAction(.createBackup) }; Button("Import and verify") { onAction(.selectImport) } }.disabled(!state.attended || state.busy || state.unknownMutation)
        if !state.attended { Text("Open this account and wait for the attended session before starting a backup.").font(.caption) }
        ForEach(state.jobs) { job in
            VStack(alignment: .leading, spacing: 8) {
                Text(job.kind.capitalized + " · " + job.state).font(.headline); Text(job.id).font(.caption)
                if let id = job.accountID { LabeledContent("Archive account", value: id) }
                if job.state == "verified", job.kind == "restore" { Button("Review restore") { onAction(.requestInstall(job.id)) } }
                if job.state == "done", job.shareURL != nil { Button("Share encrypted archive") { onAction(.share(job.id)) } }
                if ["preparing","writing","verifying"].contains(job.state) { Button("Cancel job", role: .destructive) { onAction(.cancelJob(job.id)) } }
            }.disabled(state.busy || state.unknownMutation)
        }
        Text("Refresh reads actual SDK job status. A submitted job is not reported as completed.").font(.caption)
    }
    @ViewBuilder private func modalContent(_ modal: SettingsModal) -> some View {
        switch modal {
        case .revoke(let device):
            Text("Revoke this device?").font(.title2); Text(device.id).textSelection(.enabled)
            if let origin = device.webOrigin { Text(origin).textSelection(.enabled) }
            Text("This removes future access. Previously read copies cannot be erased remotely.")
            HoldToConfirm(label: "Hold to revoke", enabled: !state.busy && !state.unknownMutation) { onAction(.confirmRevoke(device.id)) }
        case .share(let url):
            Text("Share encrypted backup").font(.title2)
            ShareLink(item: url) { Label("Share archive", systemImage: "square.and.arrow.up") }
        case .backup(let intent):
            switch intent {
            case .create: Text("Choose a backup passphrase").font(.title2)
            case .verify(let url): Text("Verify encrypted archive").font(.title2); Text(url.lastPathComponent)
            case .install(let job):
                Text("Restore this verified archive?").font(.title2); Text(job.accountID ?? "Account unavailable").textSelection(.enabled)
                Text(job.merge == true ? "The SDK will merge this archive with the existing account and preserve newer records." : "The SDK will install the archive's account on this phone.")
                Text("Use a local data passphrase for the installed account. This is separate from the archive passphrase.")
                HoldToConfirm(label: "Hold to confirm this restore", enabled: !state.busy && !state.unknownMutation) { onAction(.restoreHold(job.id, job.sequence)) }
            }
            #if os(iOS)
            RFSecretFields(labels: [("passphrase", "Passphrase")], enabled: !state.busy && !state.unknownMutation && (isInstall(intent) ? state.restoreHeld : true)) { onAction(.submitBackup(SensitiveSubmission(values: $0))) }.frame(minHeight: 120).id(intent.id)
            #else
            Text("Complete secure input in the iOS app.")
            #endif
        }
    }
    private func isInstall(_ intent: BackupIntent) -> Bool { if case .install = intent { true } else { false } }
    private func row(id: String, title: String, subtitle: String, route: AppRoute) -> some View {
        RFListRow(id: id, title: title, subtitle: subtitle, theme: RFTheme.adaptive(scheme), leading: { EmptyView() }, trailing: { Image(systemName: "chevron.right").accessibilityHidden(true) }) { onAction(.open(route)) }
    }
    private func label(_ route: AppRoute) -> String { switch route { case .account: "Account and security"; case .devices: "My devices"; case .nodes: "Nodes"; case .appearance: "Appearance and language"; case .privacy: "Privacy"; case .backup: "Backup and recovery"; case .permissions: "Connected services"; default: "About and diagnostics" } }
}
