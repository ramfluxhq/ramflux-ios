// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import RamfluxCore
@testable import AppData
struct OnboardingRefusalTests {
    @Test func sdkRefusalsRemainTypedAndLocalizedWithoutPeerErrorText() {
        let pairs: [(String, AppFailure)] = [("vault_permission", .vaultPermission), ("vault_locked", .vaultLocked), ("vault_missing", .vaultMissing), ("vault_corrupt", .vaultCorrupt), ("vault_busy", .vaultBusy), ("vault_primary_unavailable", .vaultUnavailable)]
        for (reason, expected) in pairs {
            #expect(AppFailure.map(CoreFailure(code: 16, reasonCode: reason)) == expected)
            let en = expected.message(locale: Locale(identifier: "en")), zh = expected.message(locale: Locale(identifier: "zh-CN"))
            #expect(en != zh); #expect(!en.isEmpty); #expect(!zh.isEmpty)
        }
        #expect(AppFailure.map(CoreFailure(code: 99, reasonCode: "private input")) == .sdkRefusal(99))
        #expect(AppFailure.map(CoreFailure(code: 16, operationID: "original", reasonCode: "vault_permission")) == .outcomeUnknown)
    }
    @Test func httpSavedTofuPinDoesNotAuthorizeNewAccount() {
        #expect(!NodeRecord(id: "node", origin: "http://example.org", isConfirmed: true, pinSource: "tofu").canCreateAccount)
        #expect(NodeRecord(id: "node", origin: "http://example.org", isConfirmed: true, pinSource: "operator").canCreateAccount)
        #expect(!NodeRecord(id: "node", origin: "http://example.org", pinSource: "operator").canCreateAccount)
    }
}
