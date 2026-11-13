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
    public init(values: [String: String]) {
        var fields: [String: SecretField] = [:], buffers: [SecretBytes] = []
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
