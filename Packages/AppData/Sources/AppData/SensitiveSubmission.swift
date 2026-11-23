// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Synchronization
import RamfluxCore

/// One-shot user input. UIKit owns its unavoidable editor strings; application buffers erase on use.
public final class SensitiveSubmission: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    private let fields: [String: SecretField]
    private let buffers: [SecretBytes]
    private let used = Mutex(false)
    public var description: String { "SensitiveSubmission" }
    public var debugDescription: String { description }
    public static func == (lhs: SensitiveSubmission, rhs: SensitiveSubmission) -> Bool { lhs === rhs }
    /// How the `passphrase` field is checked when it carries the six-digit account code.
    public enum AccountCodeRule: Sendable { case existing, new }
    /// Set when the account code fails the local rule; the submission must then be erased, not sent.
    public let accountCodeIssue: AccountCodeIssue?
    /// How the `passphrase` field is checked when it carries a backup archive passphrase.
    public enum ArchivePassphraseRule: Sendable { case existing, new }
    /// Set when an archive passphrase fails the local pre-check; the submission must then be erased, not sent.
    public let archivePassphraseIssue: BackupIssue?
    /// `accountCode` checks `passphrase` (and, for `.new`, its repeat under `passphraseRepeat`, which is
    /// compared and erased here and never sent). The check reads transient bytes that are zeroed after use.
    /// `archivePassphrase` pre-checks `passphrase` against the SDK's archive rule (at least 15 Unicode scalars,
    /// counted before NFC; the SDK remains authoritative and also refuses common passphrases) and, for `.new`,
    /// compares it with `passphraseRepeat`, which is never sent.
    public init(values: [String: String], accountCode: AccountCodeRule? = nil, archivePassphrase: ArchivePassphraseRule? = nil) {
        var fields: [String: SecretField] = [:], buffers: [SecretBytes] = []
        accountCodeIssue = accountCode.flatMap { Self.check(values["passphrase"], repeated: values["passphraseRepeat"], rule: $0) }
        archivePassphraseIssue = archivePassphrase.flatMap { Self.checkArchive(values["passphrase"], repeated: values["passphraseRepeat"], rule: $0) }
        for key in ["passphrase", "phrase"] {
            if let value = values[key], !value.isEmpty, value.utf8.count <= 4096,
               let buffer = try? Array(value.utf8).withUnsafeBytes({ try SecretBytes(copying: $0) }) {
                fields[key] = .text(buffer); buffers.append(buffer)
            }
        }
        let words = ["word1", "word2", "word3"].compactMap { key -> SecretBytes? in
            guard let word = values[key], !word.isEmpty, word.utf8.count <= 128 else { return nil }
            return try? Array(word.utf8).withUnsafeBytes { try SecretBytes(copying: $0) }
        }
        if words.count == 3 { fields["words"] = .words(words); buffers += words }
        self.fields = fields; self.buffers = buffers
    }
    private static func check(_ code: String?, repeated: String?, rule: AccountCodeRule) -> AccountCodeIssue? {
        var entered = Array((code ?? "").utf8), again = Array((repeated ?? "").utf8)
        defer { zero(&entered); zero(&again) }
        return entered.withUnsafeBytes { bytes -> AccountCodeIssue? in
            switch rule {
            case .existing: return AccountCode.isWellFormed(bytes) ? nil : .notSixDigits
            case .new:
                if let issue = AccountCode.issue(forNew: bytes) { return issue }
                return again.withUnsafeBytes { AccountCode.equal(bytes, $0) } ? nil : .mismatch
            }
        }
    }
    private static func checkArchive(_ passphrase: String?, repeated: String?, rule: ArchivePassphraseRule) -> BackupIssue? {
        guard let passphrase, !passphrase.isEmpty else { return .passphraseEmpty }
        guard rule == .new else { return nil }
        guard passphrase.unicodeScalars.count >= BackupIssue.minimumScalars else { return .passphraseTooShort }
        var entered = Array(passphrase.utf8), again = Array((repeated ?? "").utf8)
        defer { zero(&entered); zero(&again) }
        return entered.withUnsafeBytes { bytes in again.withUnsafeBytes { AccountCode.equal(bytes, $0) } } ? nil : .passphraseMismatch
    }
    private static func zero(_ bytes: inout [UInt8]) { bytes.withUnsafeMutableBytes { if let base = $0.baseAddress { _ = memset_s(base, $0.count, 0, $0.count) } } }
    func take() -> [String: SecretField]? { used.withLock { taken in guard !taken else { return nil }; taken = true; return fields } }
    public func erase() { buffers.forEach { $0.erase() }; used.withLock { $0 = true } }
    deinit { buffers.forEach { $0.erase() } }
}
public final class RecoveryDisplay: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    private let storage: SecureDisplayBytes
    init(_ frame: SecretBytes) throws { storage = try SecureDisplayBytes(phraseFrame: frame) }
    public var description: String { "RecoveryDisplay" }
    public var debugDescription: String { description }
    public static func == (lhs: RecoveryDisplay, rhs: RecoveryDisplay) -> Bool { lhs === rhs }
    public func withDrawingBytes(_ draw: (UnsafeRawBufferPointer) -> Void) { storage.withBytes(draw) }
    public func erase() { storage.erase() }
}
