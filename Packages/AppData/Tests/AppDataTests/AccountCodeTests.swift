// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Testing
import RamfluxCore
@testable import AppData
struct AccountCodeTests {
    private func newIssue(_ code: String) -> AccountCodeIssue? { Array(code.utf8).withUnsafeBytes { AccountCode.issue(forNew: $0) } }
    @Test func newCodeMirrorsTheSdkAdmissionRule() {
        for code in ["12345", "1234567", "12a456", "", "١٢٣٤٥٦", "12 456"] { #expect(newIssue(code) == .notSixDigits, "\(code)") }
        for code in ["000000", "999999", "012345", "123456", "456789", "987654", "543210"] { #expect(newIssue(code) == .trivial, "\(code)") }
        for code in ["135790", "112233", "123457", "024680", "908172"] { #expect(newIssue(code) == nil, "\(code)") }
    }
    @Test func submissionChecksCodeAndRepeatWithoutSendingTheRepeat() {
        #expect(SensitiveSubmission(values: ["passphrase": "123456", "passphraseRepeat": "123456"], accountCode: .new).accountCodeIssue == .trivial)
        #expect(SensitiveSubmission(values: ["passphrase": "135790", "passphraseRepeat": "135791"], accountCode: .new).accountCodeIssue == .mismatch)
        let valid = SensitiveSubmission(values: ["passphrase": "135790", "passphraseRepeat": "135790"], accountCode: .new)
        #expect(valid.accountCodeIssue == nil)
        #expect(valid.take()?.keys.sorted() == ["passphrase"])
        #expect(SensitiveSubmission(values: ["passphrase": "1234"], accountCode: .existing).accountCodeIssue == .notSixDigits)
        #expect(SensitiveSubmission(values: ["passphrase": "123456"], accountCode: .existing).accountCodeIssue == nil)
        #expect(SensitiveSubmission(values: ["passphrase": "free text"]).accountCodeIssue == nil)
    }
    @Test func sdkRefusalReasonsMapToTypedCodeFailures() {
        let rows: [(String, AccountCodeIssue)] = [("not_six_digits", .notSixDigits), ("trivial_code", .trivial), ("wrong_passphrase", .wrong), ("reauth_required", .reauthRequired), ("unlock_retry_later", .retryLater), ("unlock_attempts_exhausted", .attemptsExhausted), ("account_code_required", .required), ("device_unlock_unavailable", .deviceUnlockUnavailable)]
        for (reason, issue) in rows {
            #expect(AppFailure.map(CoreFailure(code: 1, operationID: "op", reasonCode: reason)) == .accountCode(issue))
        }
        #expect(!AppFailure.accountCode(.attemptsExhausted).canRetry); #expect(AppFailure.accountCode(.retryLater).canRetry)
        for issue in AccountCodeIssue.allCases {
            #expect(AppFailure.accountCode(issue).message(locale: .init(identifier: "en")) != AppFailure.failed.message(locale: .init(identifier: "en")))
        }
    }
}
