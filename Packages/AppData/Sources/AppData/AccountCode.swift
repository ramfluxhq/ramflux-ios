// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// Why an account code was refused, locally or by the SDK. The SDK stays the authority; the local
/// checks mirror its admission rule (`passphrase/code.rs`) so a single-attempt ceremony is never
/// spent on a code the SDK would refuse.
public enum AccountCodeIssue: String, Equatable, Sendable, CaseIterable {
    /// Not exactly six ASCII digits (SDK `not_six_digits`).
    case notSixDigits
    /// All digits equal or a straight run (SDK `trivial_code`).
    case trivial
    /// The repeated new code differs (local only).
    case mismatch
    /// Too many wrong codes; the SDK asks for a wait (`unlock_retry_later`). With the wait it reports,
    /// the failure becomes `AppFailure.accountCodeWait`.
    case retryLater
    /// Ten wrong codes; only the recovery phrase restores the account (`unlock_attempts_exhausted`).
    case attemptsExhausted
    /// The account was locked explicitly; only its code opens it (`account_code_required`).
    case required
    /// The platform vault holds no device unlock secret (`device_unlock_unavailable`).
    case deviceUnlockUnavailable
    /// The code is well formed but not the account's code (SDK `wrong_passphrase`, on unlock and on a weakening change).
    case wrong
    /// A weakening change was refused without a code (SDK `reauth_required`): nothing changed.
    case reauthRequired

    /// SDK reason tokens; never peer text.
    static func sdk(_ reason: String?) -> Self? {
        switch reason {
        case "not_six_digits": .notSixDigits
        case "trivial_code": .trivial
        case "unlock_retry_later": .retryLater
        case "unlock_attempts_exhausted": .attemptsExhausted
        case "account_code_required": .required
        case "device_unlock_unavailable": .deviceUnlockUnavailable
        case "wrong_passphrase": .wrong
        case "reauth_required": .reauthRequired
        default: nil
        }
    }
}

/// Byte-level account code rules. Input is borrowed from an erasable buffer and never becomes a String.
public enum AccountCode {
    public static let digits = 6
    /// An entered code for an existing account: exactly six ASCII digits.
    public static func isWellFormed(_ bytes: UnsafeRawBufferPointer) -> Bool {
        bytes.count == digits && bytes.allSatisfy { (0x30...0x39).contains($0) }
    }
    /// A new code: well formed and not on the SDK's closed trivial list
    /// (all digits equal, or each digit one more or one less than the previous one).
    public static func issue(forNew bytes: UnsafeRawBufferPointer) -> AccountCodeIssue? {
        guard isWellFormed(bytes) else { return .notSixDigits }
        var steps = Set<Int>()
        for index in 1..<bytes.count { steps.insert(Int(bytes[index]) - Int(bytes[index - 1])) }
        if steps.count == 1, let step = steps.first, (-1...1).contains(step) { return .trivial }
        return nil
    }
    /// Length-independent comparison of two borrowed buffers of the same length.
    static func equal(_ lhs: UnsafeRawBufferPointer, _ rhs: UnsafeRawBufferPointer) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<lhs.count { difference |= lhs[index] ^ rhs[index] }
        return difference == 0
    }
}
