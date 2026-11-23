// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import UniformTypeIdentifiers
import AppData
import RFDesign
import RFLocalization
/// Backup and restore (board MOB-G09, built from the Kit; no export of the board yet).
public struct BackupScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public let state: BackupState
    public let onAction: (BackupAction) -> Void
    public init(state: BackupState, onAction: @escaping (BackupAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeatureSettingsStrings.text(key, locale: locale) }
    public var body: some View {
        RFPage { ScrollView { LazyVStack(alignment: .leading, spacing: theme.gap) {
            KitPageHeader(copy("settings.backup.title"), onBack: { dismiss() }, actions: [KitHeaderAction(icon: "refresh-cw", label: copy("common.action.refresh"), action: { onAction(.refresh) })], tag: "backup-header")
            if case .restored = state.step { restored } else { overview }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
            .privacySensitive().rfHidesNavigationBar()
            .fileImporter(isPresented: Binding(get: { state.importSelecting }, set: { if !$0 { onAction(.cancelImport) } }), allowedContentTypes: [.data]) { result in
                switch result { case .success(let url): onAction(.importSelected(url)); case .failure: onAction(.importFailed) }
            }
            .fileMover(isPresented: Binding(get: { state.exporting != nil }, set: { if !$0 && state.exporting != nil { onAction(.exportFinished(false)) } }), file: state.exporting?.shareURL) { result in
                if case .success = result { onAction(.exportFinished(true)) } else { onAction(.exportFinished(false)) }
            }
            .sheet(isPresented: Binding(get: { sheetVisible }, set: { if !$0 { onAction(.back) } })) {
                NavigationStack { RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                    sheet
                    if state.busy { ProgressView(copy("settings.busy")) }
                    if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
                }.padding(theme.gap) } } }.interactiveDismissDisabled(state.busy)
            }
    }
    private var sheetVisible: Bool {
        switch state.step { case .createPassphrase, .importPassphrase, .installCode, .confirmMerge: true; case .overview, .restored: false }
    }
    @ViewBuilder private var overview: some View {
        if !state.attended { KitTipBar(copy("settings.backup.connecting"), icon: "info", loading: true, tag: "backup-connecting") }
        if state.account != nil {
            section(copy("settings.backup.create.title"), body: copy("settings.backup.create.body"))
            KitButton(copy("settings.backup.create.action"), action: { onAction(.startCreate) }, enabled: state.attended && !state.busy, tag: "backup-create")
        }
        section(copy("settings.backup.restore.title"), body: copy(state.account == nil ? "settings.backup.restore.newInstall" : "settings.backup.restore.body"))
        Text(copy("settings.backup.restore.limit")).rfFont(.caption).foregroundStyle(theme.secondary)
        KitButton(copy("settings.backup.restore.action"), action: { onAction(.selectImport) }, kind: .secondary, enabled: !state.busy, tag: "backup-import")
        if let failure = state.failure, !sheetVisible { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        Text(copy("settings.backup.jobs.title")).rfFont(.body, weight: .semibold)
        if state.window.isEmpty {
            if state.loading { ProgressView(copy("settings.loading")) } else { Text(copy("settings.backup.jobs.empty")).foregroundStyle(theme.secondary) }
        }
        ForEach(state.window.rows) { job in jobRow(job).onAppear { if job.id == state.window.rows.last?.id { onAction(.loadMore) } } }
    }
    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: theme.gap / 2) { Text(title).rfFont(.body, weight: .semibold); Text(body).foregroundStyle(theme.secondary) }
    }
    @ViewBuilder private func jobRow(_ job: BackupRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.gap / 2) {
            KitRow(FeatureSettingsStrings.format("settings.backup.job.title", copy(job.kind == "backup" ? "settings.backup.kind.backup" : "settings.backup.kind.restore"), copy(Self.stateKey(job.state)), locale: locale),
                   value: detail(job), trailing: .none, tag: "backup-job-" + job.id)
            if job.isRunning, let fraction = fraction(job) { ProgressView(value: fraction) }
            HStack(spacing: theme.gap) {
                if job.isRunning || job.state == "verified" { KitButton(copy("settings.backup.action.cancel"), action: { onAction(.cancelJob(job.id)) }, kind: .text, size: .compact, enabled: state.attended && !state.busy) }
                if job.state == "verified" { KitButton(copy("settings.backup.action.install"), action: { onAction(.requestInstall(job.id)) }, size: .compact, enabled: state.attended && !state.busy) }
                if job.shareURL != nil { KitButton(copy("settings.backup.action.save"), action: { onAction(.export(job.id)) }, kind: .secondary, size: .compact) }
                if job.kind == "backup" && job.failure?.code == "attachments_unavailable" && state.account != nil {
                    KitButton(copy("settings.backup.action.allowMissing"), action: { onAction(.retryAllowingMissing) }, kind: .secondary, size: .compact, enabled: state.attended && !state.busy)
                }
                if job.shareURL != nil { KitButton(copy("settings.backup.action.delete"), action: { onAction(.discard(job.id)) }, kind: .destructive, size: .compact, enabled: !state.busy) }
            }
        }
    }
    private static func stateKey(_ state: String) -> String {
        switch state {
        case "preparing": "settings.backup.state.preparing"
        case "writing": "settings.backup.state.writing"
        case "verifying": "settings.backup.state.verifying"
        case "verified": "settings.backup.state.verified"
        case "installing": "settings.backup.state.installing"
        case "done": "settings.backup.state.done"
        case "cancelled": "settings.backup.state.cancelled"
        default: "settings.backup.state.failed"
        }
    }
    private func detail(_ job: BackupRecord) -> String? {
        if let failure = job.failure { return AppFailure.backup(BackupIssue.sdk(failure.code)).message(locale: locale) }
        if job.isRunning, let progress = job.progress {
            let done = ByteCountFormatter.string(fromByteCount: Int64(clamping: progress.bytesDone), countStyle: .file)
            guard let total = progress.bytesTotal else { return FeatureSettingsStrings.format("settings.backup.progress.partial", done, locale: locale) }
            return FeatureSettingsStrings.format("settings.backup.progress.bytes", done, ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .file), locale: locale)
        }
        if job.kind == "restore", let label = job.accountLabel { return RFUntrustedText(label, kind: .identity).text }
        return nil
    }
    private func fraction(_ job: BackupRecord) -> Double? {
        guard let progress = job.progress, let total = progress.bytesTotal, total > 0 else { return nil }
        return min(1, Double(progress.bytesDone) / Double(total))
    }
    @ViewBuilder private var sheet: some View {
        switch state.step {
        case .createPassphrase:
            Text(copy("settings.backup.passphrase.title")).rfFont(.page)
            Text(copy("settings.backup.create.body"))
            Text(copy("settings.backup.passphrase.rule")).foregroundStyle(theme.secondary)
            secureForm(.newArchive) {
                onAction(.submitCreate(SensitiveSubmission(values: $0, archivePassphrase: .new)))
            }
        case .importPassphrase:
            Text(copy("settings.backup.verify.title")).rfFont(.page)
            Text(copy("settings.backup.verify.body"))
            secureForm(.existingArchive) {
                onAction(.submitVerify(SensitiveSubmission(values: $0, archivePassphrase: .existing)))
            }
        case .installCode(let job):
            Text(copy("settings.backup.install.code.title")).rfFont(.page)
            archiveFacts(job)
            Text(copy("settings.backup.install.code.body"))
            secureForm(.newCode) {
                onAction(.submitInstallCode(SensitiveSubmission(values: $0, accountCode: .new)))
            }
        case .confirmMerge(let job):
            Text(copy("settings.backup.install.merge.title")).rfFont(.page)
            archiveFacts(job)
            Text(copy("settings.backup.install.merge.fact"))
            RFHostConfirmationActions(summary: FeatureSettingsStrings.sentence("settings.backup.install.merge.summary", [.identifier(job.accountID ?? "")], locale: locale),
                enabled: state.attended && !state.busy, cancelEnabled: !state.busy, confirm: { onAction(.confirmMerge(job.id)) }, cancel: { onAction(.back) }).id(job.id)
        case .overview, .restored: EmptyView()
        }
    }
    @ViewBuilder private func archiveFacts(_ job: BackupRecord) -> some View {
        if let label = job.accountLabel { Text(untrusted: label).rfFont(.body, weight: .semibold) }
        if let created = job.archiveCreatedAt {
            Text(FeatureSettingsStrings.format("settings.backup.archive.created", Date(timeIntervalSince1970: TimeInterval(created)).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)), locale: locale)).foregroundStyle(theme.secondary)
        }
        if let id = job.accountID { KitIdentifierText(id).textSelection(.enabled) }
    }
    /// The secret editors of each sheet; UIKit owns the editor strings and the submission erases them.
    private enum SecretForm { case newArchive, existingArchive, newCode }
    @ViewBuilder private func secureForm(_ form: SecretForm, submit: @escaping ([String: String]) -> Void) -> some View {
        #if os(iOS)
        let fields: [RFSecureEntryField] = switch form {
        case .newArchive: [RFSecureEntryField(id: "passphrase", label: copy("settings.backup.passphrase.new")), RFSecureEntryField(id: "passphraseRepeat", label: copy("settings.backup.passphrase.repeat"))]
        case .existingArchive: [RFSecureEntryField(id: "passphrase", label: copy("settings.backup.passphrase.existing"))]
        case .newCode: [RFSecureEntryField(id: "passphrase", label: copy("settings.backup.install.code.new"), kind: .accountCode), RFSecureEntryField(id: "passphraseRepeat", label: copy("settings.backup.install.code.repeat"), kind: .accountCode)]
        }
        RFSecureEntryForm(fields: fields, enabled: state.attended && !state.busy, submit: submit).frame(minHeight: theme.composer_min * CGFloat(fields.count + 1))
        #else
        RFUnavailableView(title: copy("settings.backup.title"), message: AppFailure.unsupported.message(locale: locale))
        #endif
    }
    @ViewBuilder private var restored: some View {
        KitStatusHero(icon: "check", tag: "backup-restored")
        Text(copy("settings.backup.restored.title")).rfFont(.page)
        Text(copy("settings.backup.restored.body"))
        KitButton(copy("settings.backup.restored.action"), action: { onAction(.finish) }, tag: "backup-restored-continue")
    }
}
