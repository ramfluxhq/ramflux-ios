// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
@testable import RFDesign
struct ConfirmationTests {
    @Test func heldAndRepeatedHardwareKeysNeverAuthorizeThenExplicitTapWorksOnce() {
        var gate = RFConfirmationGate()
        // Down, repeat and up all remain unauthorized, even after opening a new sheet.
        for _ in 0..<4 { let accepted = gate.activate(.hardwareKey, enabled: true); #expect(!accepted) }
        #expect(!gate.consumed)
        let accepted1 = gate.activate(.tap, enabled: true); #expect(accepted1)
        let accepted2 = gate.activate(.tap, enabled: true); #expect(!accepted2)
        let accepted3 = gate.activate(.accessibility, enabled: true); #expect(!accepted3)
    }
    @Test func disabledAndAccessibilityActivationRespectTheSameOneShotFence() {
        var gate = RFConfirmationGate()
        let accepted4 = gate.activate(.accessibility, enabled: false); #expect(!accepted4)
        let accepted5 = gate.activate(.tap, enabled: false); #expect(!accepted5)
        let accepted6 = gate.activate(.accessibility, enabled: true); #expect(accepted6)
        let accepted7 = gate.activate(.accessibility, enabled: true); #expect(!accepted7)
    }
    @Test func confirmationLabelNamesTheActionInEnglishAndChinese() {
        #expect(RFDesignStrings.format("confirmation.action", "Revoke device · phone", locale: Locale(identifier: "en")) == "Confirm: Revoke device · phone")
        #expect(RFDesignStrings.format("confirmation.action", "撤销设备 · 手机", locale: Locale(identifier: "zh-CN")) == "确认：撤销设备 · 手机")
        #expect(RFDesignStrings.text("confirmation.cancel", locale: Locale(identifier: "zh-CN")) == "取消")
    }
}
