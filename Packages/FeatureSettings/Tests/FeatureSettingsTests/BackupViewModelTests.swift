// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import Testing
import AppData
@testable import FeatureSettings

private actor BackupFake: BackupRepository {
    var rows: [BackupRecord]
    private(set) var created: [Bool] = []
    private(set) var verified: [URL] = []
    private(set) var installs: [(BackupRecord, Bool)] = []
    private(set) var discarded: [String] = []
    private(set) var jobReads = 0
    let live: AsyncStream<RepositoryUpdate>.Continuation
    let stream: AsyncStream<RepositoryUpdate>
    init(rows: [BackupRecord] = []) {
        self.rows = rows
        let pair = AsyncStream<RepositoryUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1)); stream = pair.stream; live = pair.continuation
    }
    func set(_ rows: [BackupRecord]) { self.rows = rows }
    func jobs(account: String?) -> RepositoryResult<[BackupRecord]> { jobReads += 1; return .success(rows) }
    func jobsPage(account: String?, cursor: String?, limit: Int) -> RepositoryResult<RowPage<BackupRecord>> {
        jobReads += 1
        let start = Int(cursor ?? "0") ?? 0, end = min(rows.count, start + limit)
        return .success(RowPage(rows: Array(rows[start..<end]), nextCursor: end < rows.count ? String(end) : nil))
    }
    func observe(account: String?) -> RepositoryObservation { RepositoryObservation(stream: stream) }
    func create(account: String, credentials: SensitiveSubmission, allowMissingAttachments: Bool, operationID: String) -> RepositoryResult<BackupRecord> {
        credentials.erase(); created.append(allowMissingAttachments)
        let job = BackupRecord(id: "b\(created.count)", kind: "backup", state: "preparing", sequence: UInt64(created.count)); rows.insert(job, at: 0); return .success(job)
    }
    var verifyStarts: BackupRecord?
    func startVerifying(as job: BackupRecord) { verifyStarts = job }
    func verify(account: String?, source: URL, credentials: SensitiveSubmission, operationID: String) -> RepositoryResult<BackupRecord> {
        credentials.erase(); verified.append(source)
        guard let job = verifyStarts else { return .failure(.backup(.wrongPassphrase)) }
        rows.insert(job, at: 0); return .success(job)
    }
    func install(account: String?, expected: BackupRecord, credentials: SensitiveSubmission?, operationID: String) -> RepositoryResult<BackupRecord> {
        installs.append((expected, credentials != nil)); credentials?.erase()
        let done = BackupRecord(id: expected.id, kind: "restore", state: "done", sequence: expected.sequence + 1, accountID: expected.accountID, merge: expected.merge, installedAccountID: expected.accountID)
        rows = [done]; return .success(done)
    }
    func cancel(account: String?, jobID: String, operationID: String) -> RepositoryResult<Void> { .success(()) }
    func discard(account: String?, job: BackupRecord) -> RepositoryResult<Void> { discarded.append(job.id); return .success(()) }
    var installCount: Int { installs.count }
    var lastInstallHadSecret: Bool? { installs.last?.1 }
}
@MainActor private func waitUntil(_ condition: @MainActor () async -> Bool) async {
    for _ in 0..<400 { if await condition() { return }; try? await Task.sleep(for: .milliseconds(5)) }
}
@Suite(.timeLimit(.minutes(1))) @MainActor struct BackupViewModelTests {
    @Test func secretsAreRefusedUntilTheAttendedSubscriptionIsLive() async {
        let fake = BackupFake(), vm = BackupViewModel(repository: fake, account: "a", emit: { _ in })
        vm.send(.startCreate)
        vm.send(.submitCreate(SensitiveSubmission(values: ["passphrase": "a long archive passphrase", "passphraseRepeat": "a long archive passphrase"], archivePassphrase: .new)))
        #expect(vm.state.failure == .backup(.attendanceRequired)); #expect(await fake.created.isEmpty)
        vm.send(.appeared); fake.live.yield(.invalidated)
        await waitUntil { vm.state.attended }
        vm.send(.submitCreate(SensitiveSubmission(values: ["passphrase": "a long archive passphrase", "passphraseRepeat": "a long archive passphrase"], archivePassphrase: .new)))
        await vm.settleWork()
        #expect(await fake.created == [false]); #expect(vm.state.step == .overview); #expect(vm.state.window.rows.first?.id == "b1")
        vm.send(.disappeared)
    }
    @Test func runningJobsArePolledAndFinishedImportsAreDiscarded() async {
        let running = BackupRecord(id: "r", kind: "backup", state: "writing", sequence: 1, progress: .init(category: "messages", itemsDone: 1, bytesDone: 10, bytesTotal: 100))
        let failedImport = BackupRecord(id: "i", kind: "restore", state: "failed", sequence: 2, failure: .init(code: "wrong_passphrase"))
        let fake = BackupFake(rows: [running, failedImport]), vm = BackupViewModel(repository: fake, account: "a", emit: { _ in })
        vm.send(.refresh)
        await waitUntil { await fake.jobReads >= 2 }
        #expect(await fake.jobReads >= 2)
        await waitUntil { await fake.discarded == ["i"] }
        #expect(await fake.discarded == ["i"])
        vm.send(.disappeared)
    }
    @Test func newInstallRestoreAsksForACodeAndReportsTheRestoredAccount() async {
        let verified = BackupRecord(id: "v", kind: "restore", state: "verified", sequence: 3, accountID: "restore-1", merge: false, accountLabel: "Ada")
        let fake = BackupFake(rows: [verified]), events = Mutex<[SettingsEvent]>([])
        let vm = BackupViewModel(repository: fake, account: nil, emit: { event in events.withLock { $0.append(event) } })
        vm.send(.appeared); fake.live.yield(.invalidated)
        await waitUntil { vm.state.attended && !vm.state.window.isEmpty }
        vm.send(.startCreate); #expect(vm.state.step == .overview)
        vm.send(.requestInstall("v")); #expect(vm.state.step == .installCode(verified))
        vm.send(.submitInstallCode(SensitiveSubmission(values: ["passphrase": "111111", "passphraseRepeat": "111111"], accountCode: .new)))
        #expect(vm.state.failure == .accountCode(.trivial)); #expect(await fake.installCount == 0)
        vm.send(.submitInstallCode(SensitiveSubmission(values: ["passphrase": "274915", "passphraseRepeat": "274915"], accountCode: .new)))
        await vm.settleWork(); await waitUntil { vm.state.step == .restored("restore-1") }
        #expect(await fake.lastInstallHadSecret == true); #expect(vm.state.step == .restored("restore-1"))
        vm.send(.finish); #expect(events.withLock { $0 } == [.restored("restore-1")])
        vm.send(.disappeared); #expect(vm.state.step == .restored("restore-1"))
    }
    @Test func aVerifiedArchiveOpensTheInstallStepWithoutASecondTap() async {
        let fake = BackupFake(), vm = BackupViewModel(repository: fake, account: nil, emit: { _ in })
        vm.send(.appeared); fake.live.yield(.invalidated)
        await waitUntil { vm.state.attended }
        let running = BackupRecord(id: "v", kind: "restore", state: "verifying", sequence: 1)
        let verified = BackupRecord(id: "v", kind: "restore", state: "verified", sequence: 2, accountID: "restore-1", merge: false)
        await fake.startVerifying(as: running)
        let url = URL(fileURLWithPath: "/tmp/archive.rfb")
        vm.send(.importSelected(url))
        vm.send(.submitVerify(SensitiveSubmission(values: ["passphrase": "a long archive passphrase"], archivePassphrase: .existing))); await vm.settleWork()
        #expect(vm.state.step == .overview)
        // The job finishes verifying; the poll reads it and the code step opens for that job.
        await fake.set([verified])
        await waitUntil { vm.state.step == .installCode(verified) }
        #expect(vm.state.step == .installCode(verified))
        // Going back keeps the overview; the step does not reopen on the next read.
        vm.send(.back); vm.send(.refresh); await vm.settleWork()
        #expect(vm.state.step == .overview)
        vm.send(.disappeared)
    }
    @Test func mergeInstallNeedsTheHostConfirmationAndSendsNoSecret() async {
        let verified = BackupRecord(id: "m", kind: "restore", state: "verified", sequence: 3, accountID: "a", merge: true)
        let fake = BackupFake(rows: [verified]), vm = BackupViewModel(repository: fake, account: "a", emit: { _ in })
        vm.send(.appeared); fake.live.yield(.invalidated)
        await waitUntil { vm.state.attended && !vm.state.window.isEmpty }
        vm.send(.requestInstall("m")); #expect(vm.state.step == .confirmMerge(verified))
        vm.send(.confirmMerge("other")); #expect(await fake.installCount == 0)
        vm.send(.confirmMerge("m")); await vm.settleWork()
        #expect(await fake.lastInstallHadSecret == false); #expect(vm.state.step == .overview)
        vm.send(.disappeared)
    }
    @Test func verifyFailureKeepsThePassphraseSheetWithATypedMessage() async {
        let fake = BackupFake(), vm = BackupViewModel(repository: fake, account: nil, emit: { _ in })
        vm.send(.appeared); fake.live.yield(.invalidated)
        await waitUntil { vm.state.attended }
        let url = URL(fileURLWithPath: "/tmp/archive.rfb")
        vm.send(.selectImport); #expect(vm.state.importSelecting)
        vm.send(.importSelected(url)); #expect(vm.state.step == .importPassphrase(url)); #expect(!vm.state.importSelecting)
        vm.send(.submitVerify(SensitiveSubmission(values: ["passphrase": "nope"], archivePassphrase: .existing))); await vm.settleWork()
        #expect(vm.state.failure == .backup(.wrongPassphrase)); #expect(vm.state.step == .importPassphrase(url)); #expect(await fake.verified == [url])
        vm.send(.disappeared); #expect(vm.state.step == .overview)
    }
    @Test func jobWindowStaysBoundedOverFiftyThousandRows() async {
        let rows = (0..<50_000).map { BackupRecord(id: "j\($0)", kind: "backup", state: "done", sequence: UInt64(50_000 - $0)) }
        let fake = BackupFake(rows: rows), vm = BackupViewModel(repository: fake, account: "a", emit: { _ in })
        let clock = ContinuousClock(), start = clock.now
        vm.send(.refresh); await waitUntil { !vm.state.window.isEmpty }
        for _ in 0..<20 { vm.send(.loadMore); await vm.settleWork() }
        let elapsed = clock.now - start
        #expect(vm.state.window.count <= RowWindow<BackupRecord>.defaultMaxRows)
        #expect(vm.state.window.canLoadAfter)
        print("BACKUP_WINDOW_50K rows=\(vm.state.window.count) pages=21 elapsed=\(elapsed)")
        vm.send(.disappeared)
    }
}
