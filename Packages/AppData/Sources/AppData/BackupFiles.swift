// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
private final class BackupFileCancellation: Sendable {
    let flag = Mutex(false)
    func cancel() { flag.withLock { $0 = true } }
    var cancelled: Bool { flag.withLock { $0 } }
}
/// Bounded file work stays on one worker, outside the UI and Swift cooperative executor.
final class BackupFiles: Sendable {
    let root: URL
    private let worker = OperationQueue()
    init(root: URL) { self.root = root; worker.maxConcurrentOperationCount = 1 }
    private func run<T: Sendable>(_ operation: @escaping @Sendable (BackupFileCancellation) throws -> T) async throws -> T {
        let cancellation = BackupFileCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                worker.addOperation { continuation.resume(with: Result { try operation(cancellation) }) }
            }
        } onCancel: { cancellation.cancel() }
    }
    private func prepare() throws {
        if FileManager.default.fileExists(atPath: root.path), try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw AppFailure.invalidInput }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw AppFailure.invalidInput }
        var url = root; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
    }
    func exportPath() async throws -> URL { try await run { [self] token in
        guard !token.cancelled else { throw CancellationError() }; try prepare()
        return root.appendingPathComponent(UUID().uuidString + ".rfb")
    } }
    func copyImport(_ source: URL) async throws -> URL { try await run { [self] token in
        guard source.isFileURL else { throw AppFailure.invalidInput }; try prepare()
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw AppFailure.invalidInput }
        // Refuse a known oversize file before copying; the copy loop still enforces the bound.
        if let size = values.fileSize, size > Self.importLimitBytes { throw AppFailure.backup(.importTooLarge) }
        let target = root.appendingPathComponent(UUID().uuidString + ".rfb")
        guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw AppFailure.localStorage }
        var complete = false; defer { if !complete { try? FileManager.default.removeItem(at: target) } }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: target)
        defer { try? input.close(); try? output.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30)); var total = 0
        while true {
            guard !token.cancelled, ContinuousClock.now < deadline else { throw CancellationError() }
            guard let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty else { break }
            total += chunk.count
            guard total <= Self.importLimitBytes else { throw AppFailure.backup(.importTooLarge) }
            try output.write(contentsOf: chunk)
        }
        guard total > 0 else { throw AppFailure.invalidData }; complete = true; return target
    } }
    /// The phone's import bound; larger archives are refused while copying, before the SDK sees them.
    static let importLimitBytes = 256 * 1024 * 1024
    /// Removes a private archive file; paths outside the private directory are ignored.
    func remove(path: String) async {
        guard let url = shareURL(path: path) else { return }
        _ = try? await run { _ in try FileManager.default.removeItem(at: url) }
    }
    func shareURL(path: String) -> URL? {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        guard candidate.deletingLastPathComponent() == root.standardizedFileURL,
              candidate.resolvingSymlinksInPath().deletingLastPathComponent() == root.resolvingSymlinksInPath(),
              (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return candidate
    }
}
