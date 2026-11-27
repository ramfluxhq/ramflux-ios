// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest

/// Flow 22: an app-locked account whose code checks are used up is recovered with its recovery phrase and
/// account code, and a second exhaustion is ended by removing the account from this device (G10b).
///
/// It is a single-account flow on a freshly prepared app (no account yet), so it never creates a second account
/// while another account's app lock is on. The recovery phrase and the account code live in this process only:
/// `Self.sensitive` is set while either is on screen or typed, so nothing is snapped or logged then. The class
/// name sorts after the other suites that need flow 1's account; run it alone:
/// `scripts/realrun.sh run --only RealRunLockRecoveryTests/test22_exhaustRecoverRemove`.
/// It takes about 45 minutes: two exhaustions (930 s of waits each) and the waits the recovery meets.
final class RealRunLockRecoveryTests: RealRunTestCase {
    /// The waits core applies after the fifth to the ninth wrong code, in seconds.
    private static let waits = [30, 60, 120, 240, 480]
    /// The wait that applies after the tenth wrong code, before the one code try a correct phrase grants.
    private static let exhaustedWait = 480

    func test22_exhaustRecoverRemove() {
        flow("22-exhaust-recover-remove") {
            // The empty shell also shows the Messages tab; an existing account shows its unlock entry or the code field.
            if knownAccountUnlock().exists || element("secure-entry-passphrase").exists {
                throw FlowStop.blocked("needs a freshly prepared app with no account; run this flow alone after `scripts/realrun.sh prepare`")
            }
            let name = "Lockrr " + String((0..<4).map { _ in "abcdefghjkmnpqrstuvwxyz".randomElement()! })
            let code = RunSecrets.newCode()
            var notes: [String] = []

            // 1. A throwaway account; the phrase and the code stay in memory.
            let (words, accountID) = try createAccount(name: name, code: code)
            control.log("lock-recovery account \(accountID) created")
            notes.append("throwaway account created (phrase and code in memory only)")

            // 2. App lock on, Immediately; lock; ten wrong codes; the exhausted page, also after a relaunch.
            try enableAppLock()
            try lockNow()
            snap("22-locked")
            try exhaust(code: code, notes: &notes, label: "first exhaustion")
            let exhaustedAt = Date()
            try expectExhaustedPage("after the tenth wrong code")
            snap("22-exhausted")
            app.terminate(); app.launch()
            try expectExhaustedPage("after a relaunch")
            snap("22-exhausted-relaunch")
            notes.append("exhausted page (restore and remove, no code field) after the tenth wrong code and after a relaunch")

            // 3. Recover with the phrase and a WRONG code once the wait of the tenth failure is over, so the granted try
            // reaches the code check: the wrong-code line, back on the exhausted page.
            let remaining = Double(Self.exhaustedWait + 10) - Date().timeIntervalSince(exhaustedAt)
            if remaining > 0 { control.log("waiting \(Int(remaining)) s for the wait of the tenth failure"); Thread.sleep(forTimeInterval: remaining) }
            try recover(words: words, code: wrongCode(not: code))
            guard eventually(60, every: 1, { self.text(containing: "That account code is not right").exists }) else {
                throw FlowStop.fail("recovery with the right phrase and a wrong code showed no wrong-code line: \(visibleFailure())")
            }
            try expectExhaustedPage("after recovery with a wrong code")
            snap("22-recover-wrong-code")
            notes.append("recovery with phrase and a wrong code: wrong-code line, still locked on the exhausted page")

            // Background and foreground during the recover form: the inputs are cleared and the recovery is cancelled.
            try openRecoverForm()
            Self.sensitive = true
            let phrase = try require(element("secure-entry-phrase"), "recovery phrase field")
            phrase.tap(); phrase.typeText(words[0])
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 2)
            app.activate()
            guard eventually(30, { !self.element("secure-entry-phrase").exists && self.element("app-lock-restore").exists }) else {
                throw FlowStop.fail("the recover form was still open after background and foreground")
            }
            Self.sensitive = false
            try expectExhaustedPage("after background and foreground during recovery")
            snap("22-recover-cancelled")
            notes.append("background and foreground during the recover form: the form closed, the recovery was cancelled, the cover stayed")

            // 4. Phrase and the correct code: unlocked. The wait of the failed try may still apply: then the phrase is
            // accepted, the countdown shows and the one granted try is taken on the ordinary field after it.
            try recover(words: words, code: code)
            if element("app-lock-screen").exists, eventually(30, { self.text(containing: "Recovery phrase accepted").exists }) {
                let seconds = try countdownSeconds()
                Self.sensitive = false
                snap("22-phrase-accepted-countdown")
                guard !element("secure-entry-passphrase").isEnabled else { throw FlowStop.fail("the code field is enabled during the accepted-phrase countdown") }
                guard eventually(Double(seconds) + 90, every: 5, { self.element("secure-entry-passphrase").isEnabled && !self.text(containing: "Recovery phrase accepted").exists }) else {
                    throw FlowStop.fail("the accepted-phrase countdown never ended: \(visibleFailure())")
                }
                try typeCode(code, into: "ordinary code field")
                notes.append("correct phrase and code met the wait of the failed try: 'Recovery phrase accepted' with a \(seconds) s countdown, then the code opened the account")
            } else {
                notes.append("correct phrase and code opened the account directly")
            }
            Self.sensitive = false
            if button("Continue").waitForExistence(timeout: 3), !element("tab-messages").isHittable { button("Continue").tap() }
            guard element("tab-messages").waitForExistence(timeout: 60), !element("app-lock-screen").exists else {
                throw FlowStop.fail("the account did not open after recovery: \(visibleFailure())")
            }
            snap("22-recovered")
            let toggle = try openAppLockPage()
            guard (toggle.value as? String) == "1" else { throw FlowStop.fail("the app lock is not on after recovery (App lock switch value \(toggle.value ?? "nil"))") }
            snap("22-lock-still-on")
            notes.append("account unlocked; app lock still on")

            // 5. Exhaust again, then remove: no account name, Remove needs the acknowledgement, Cancel keeps the account.
            try lockNow()
            try exhaust(code: code, notes: &notes, label: "second exhaustion")
            try expectExhaustedPage("after the second exhaustion")
            try tap(element("app-lock-remove"), "Remove from this device")
            let idLine = try require(element("app-lock-remove-account"), "account line on the removal confirmation")
            let shown = idLine.label + " " + (idLine.value as? String ?? "")
            guard !shown.contains(name), !text(containing: name).exists else { throw FlowStop.fail("the removal confirmation shows the account name") }
            guard !shown.trimmingCharacters(in: .whitespaces).isEmpty else { throw FlowStop.fail("the removal confirmation shows no account id line") }
            let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Confirm:'")).firstMatch
            try require(confirm, "Remove confirmation button")
            guard !confirm.isEnabled else { throw FlowStop.fail("Remove is enabled before the acknowledgement") }
            snap("22-remove-confirmation")
            try tap(button("Cancel"), "Cancel the removal")
            try require(element("app-lock-remove"), "exhausted page after Cancel")
            guard !element("app-lock-remove-account").exists else { throw FlowStop.fail("the removal confirmation stayed after Cancel") }
            notes.append("removal confirmation shows the id line and no account name; Remove is disabled until the acknowledgement; Cancel keeps the account")
            try tap(element("app-lock-remove"), "Remove from this device (again)")
            let ack = try require(element("app-lock-remove-ack"), "acknowledgement switch")
            try setSwitch(ack, on: true)
            guard eventually(10, { confirm.isEnabled }) else { throw FlowStop.fail("Remove stayed disabled after the acknowledgement") }
            try tap(confirm, "Remove")
            try require(element("app-removed-notice"), "removed notice", timeout: 30)
            snap("22-removed")
            guard eventually(30, { !self.element("app-lock-screen").exists && !self.element("tab-messages").exists }) else {
                throw FlowStop.fail("the lock cover or the account is still shown after the removal: \(visibleFailure())")
            }
            guard !text(containing: name).exists, !text(containing: accountID).exists else { throw FlowStop.fail("the removed account is still shown") }
            if element("shell-accounts").waitForExistence(timeout: 10) {
                try tap(element("shell-accounts"), "Accounts after the removal")
                guard !text(containing: accountID).waitForExistence(timeout: 3), !text(containing: name).exists else { throw FlowStop.fail("the removed account is still listed") }
                snap("22-accounts-after-removal")
            }
            notes.append("Remove: app-removed-notice shown, no account left")
            return notes.joined(separator: "; ")
        }
    }

    // MARK: Account

    /// Flow 1's creation path with this flow's own name and code. Returns the 24 words and the account id.
    private func createAccount(name: String, code: String) throws -> ([String], String) {
        try tap(element("shell-accounts"), "Accounts button on the empty shell", timeout: 60)
        try tap(button("Add account"), "Add account")
        try tap(element("s02-change-node"), "change node row", timeout: 30)
        let field = try require(textField("onboarding-address"), "node address field")
        field.tap(); field.typeText(config.origin)
        try tap(button("Check address"), "Check address")
        try tap(button("Connect to this origin"), "Connect to this origin", timeout: 30)
        let keyInput = try require(textField("onboarding-operator-key"), "operator key field", timeout: 40)
        keyInput.tap(); keyInput.typeText(config.operatorKey)
        try tap(button("Review fingerprint"), "Review fingerprint")
        let print = try require(element("onboarding-node-fingerprint"), "node fingerprint", timeout: 30)
        let shown = (print.label + " " + (print.value as? String ?? "")).lowercased().filter { $0.isHexDigit }
        guard shown.contains(config.fingerprint) else { throw FlowStop.fail("fingerprint shown differs from node-facts") }
        try tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Confirm:'")).firstMatch, "fingerprint confirmation")
        try tap(button("Create an account"), "Create an account (node saved)", timeout: 30)
        let nameInput = try require(textField("n01-name"), "display name field")
        nameInput.tap(); nameInput.typeText(name)
        try tap(button("Create the account"), "Create the account")
        Self.sensitive = true
        defer { Self.sensitive = false }
        try tap(button("Show recovery phrase once"), "Show recovery phrase once", timeout: 60)
        let phrase = try require(app.otherElements["Private recovery phrase display"], "recovery phrase display", timeout: 30)
        // The debug accessibility seam (-RFRealRunPhraseAccess) exposes the words to this process only.
        var words: [String] = []
        guard eventually(10, every: 0.5, {
            words = (phrase.value as? String ?? "").split(separator: " ").map(String.init)
            return words.count == 24
        }) else { throw FlowStop.fail("the recovery phrase display exposed \(words.count) words to the debug accessibility seam, not 24") }
        guard words.allSatisfy({ (3...8).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isLetter } }) else {
            throw FlowStop.fail("the recovery phrase display exposed malformed words (lengths only: \(words.map(\.count)))")
        }
        try tap(button("I saved it. Hide and continue"), "Hide and continue")
        try require(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'onboarding-word-'")).firstMatch,
                    "confirmation word positions", timeout: 30)
        let positions = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'onboarding-word-'"))
            .allElementsBoundByIndex.compactMap { Int($0.identifier.dropFirst("onboarding-word-".count)) }
        var seen = Set<Int>(); let ordered = positions.filter { seen.insert($0).inserted }
        guard !ordered.isEmpty, ordered.allSatisfy({ (1...24).contains($0) }) else { throw FlowStop.fail("unexpected word positions \(ordered)") }
        try tap(button("Set account code"), "Set account code")
        for (index, position) in ordered.enumerated() {
            let wordField = try require(element("secure-entry-word\(index + 1)"), "word field \(index + 1)")
            wordField.tap(); wordField.typeText(words[position - 1])
        }
        let first = try require(element("secure-entry-passphrase"), "new account code")
        first.tap(); first.typeText(code)
        let repeatCode = try require(element("secure-entry-passphraseRepeat"), "repeat account code")
        repeatCode.tap(); repeatCode.typeText(code)
        try tap(element("secure-entry-submit"), "Confirm once")
        let connected = text(containing: "Connected")
        let pending = text(containing: "Network connection has not been confirmed")
        let connecting = text(containing: "Connecting to the network")
        guard eventually(90, { connected.exists || pending.exists || connecting.exists }) else { throw FlowStop.fail("account completion did not appear: \(visibleFailure())") }
        Self.sensitive = false
        let shownID = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'account-'")).firstMatch.label
        let accountID = String(shownID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        guard !accountID.isEmpty else { throw FlowStop.fail("the completion step shows no account id") }
        snap("22-account-created")
        try tap(button("Continue"), "Continue after completion")
        try require(element("app-shell"), "app shell", timeout: 30)
        return (words, accountID)
    }

    // MARK: App lock

    /// Settings > Account > Privacy > App lock; returns the App lock switch.
    @discardableResult
    private func openAppLockPage() throws -> XCUIElement {
        try openMore()
        try tap(element("more-settings"), "Settings in More")
        try tap(element("settings-account"), "Account and security")
        try tap(element("settings-privacy"), "Privacy")
        try tap(element("settings-app-lock"), "App lock row", timeout: 30)
        return try require(app.switches["App lock"], "App lock switch", timeout: 30)
    }

    private func enableAppLock() throws {
        let toggle = try openAppLockPage()
        guard eventually(20, { toggle.isEnabled }) else { throw FlowStop.fail("the App lock switch never became enabled") }
        try setSwitch(toggle, on: true)
        // The timeout picker appears once the lock is on; choose Immediately.
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Lock after'")).firstMatch
        try require(picker, "Lock after picker", timeout: 20)
        if !(picker.label + " " + (picker.value as? String ?? "")).contains("Immediately") {
            heldTap(picker)
            try tap(button("Immediately"), "Immediately option")
            guard eventually(20, { (picker.label + " " + (picker.value as? String ?? "")).contains("Immediately") }) else { throw FlowStop.fail("the lock timeout did not become Immediately") }
        }
        snap("22-app-lock-on")
    }

    /// Engages the lock the way a person does: the app goes to the background and returns (timeout Immediately).
    private func lockNow() throws {
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        guard element("app-lock-screen").waitForExistence(timeout: 30) else { throw FlowStop.fail("the app lock did not engage after background and return: \(visibleFailure())") }
    }

    /// Ten wrong codes: five free, then the waits of 30, 60, 120, 240 and 480 s, each shown as a countdown with the
    /// field disabled. Ends on the exhausted page.
    private func exhaust(code: String, notes: inout [String], label: String) throws {
        for attempt in 1...10 {
            if attempt > 5 {
                // The field is back after the wait of the previous failure.
                guard eventually(Double(Self.waits[attempt - 6]) + 90, every: 5, { self.element("secure-entry-passphrase").isEnabled && !self.text(containing: "Try again in").exists }) else {
                    throw FlowStop.fail("\(label): the wait before wrong code \(attempt) never ended: \(visibleFailure())")
                }
            }
            try typeCode(wrongCode(not: code), into: "wrong code \(attempt)")
            Thread.sleep(forTimeInterval: 1.5)
            if attempt < 5 {
                guard eventually(30, { self.text(containing: "That account code is not right").exists }) else { throw FlowStop.fail("\(label): wrong code \(attempt) showed no wrong-code line: \(visibleFailure())") }
            } else if attempt < 10 {
                let expected = Self.waits[attempt - 5]
                guard eventually(30, { self.text(containing: "Try again in").exists }) else { throw FlowStop.fail("\(label): no countdown after wrong code \(attempt): \(visibleFailure())") }
                let seconds = try countdownSeconds()
                guard seconds <= expected, seconds >= expected - 20 else { throw FlowStop.fail("\(label): countdown after wrong code \(attempt) shows \(seconds) s, expected about \(expected) s") }
                guard !element("secure-entry-passphrase").isEnabled else { throw FlowStop.fail("\(label): the code field is enabled during the \(expected) s wait") }
                if attempt == 5 { snap("22-countdown") }
            } else {
                guard eventually(30, { self.element("app-lock-restore").exists }) else { throw FlowStop.fail("\(label): no exhausted page after the tenth wrong code: \(visibleFailure())") }
            }
        }
        notes.append("\(label): ten wrong codes, countdown with the field disabled after the fifth to the ninth (waits 30/60/120/240/480 s), exhausted page after the tenth")
    }

    private func expectExhaustedPage(_ when: String) throws {
        try require(element("app-lock-screen"), "lock screen \(when)", timeout: 30)
        guard element("app-lock-restore").waitForExistence(timeout: 20), element("app-lock-remove").exists else {
            throw FlowStop.fail("the exhausted page does not offer recover and remove \(when): \(visibleFailure())")
        }
        guard !element("secure-entry-passphrase").waitForExistence(timeout: 3) else { throw FlowStop.fail("a code field is shown \(when)") }
    }

    // MARK: Recovery

    /// Restore on the exhausted page, read the fingerprint, tick the fingerprint check; the form is then open.
    private func openRecoverForm() throws {
        try tap(element("app-lock-restore"), "Recover with recovery phrase")
        try tap(button("Read account fingerprint"), "Read account fingerprint", timeout: 30)
        try require(element("onboarding-recover-fingerprint"), "account fingerprint", timeout: 30)
        let checked = try require(app.switches["I checked this account fingerprint"], "fingerprint check switch")
        try setSwitch(checked, on: true)
        try require(element("secure-entry-phrase"), "recovery phrase field")
    }

    /// Recovery with the 24 words and `code`; returns once the form has been submitted.
    private func recover(words: [String], code: String) throws {
        try openRecoverForm()
        Self.sensitive = true
        let phrase = element("secure-entry-phrase")
        phrase.tap(); phrase.typeText(words.joined(separator: " "))
        let codeField = try require(element("secure-entry-passphrase"), "account code field of the recover form")
        codeField.tap(); codeField.typeText(code)
        try tap(element("secure-entry-submit"), "submit the recovery")
        guard eventually(60, { !self.element("secure-entry-phrase").exists }) else { throw FlowStop.fail("the recover form stayed after the submit") }
        // The secret fields are gone: screenshots are allowed again.
        Self.sensitive = false
    }

    // MARK: Helpers

    private func typeCode(_ code: String, into what: String) throws {
        Self.sensitive = true
        defer { Self.sensitive = false }
        let field = try require(element("secure-entry-passphrase"), what)
        field.replaceText(code)
        try tap(element("secure-entry-submit"), "submit \(what)")
    }

    private func wrongCode(not code: String) -> String {
        var other = RunSecrets.newCode()
        while other == code { other = RunSecrets.newCode() }
        return other
    }

    /// The remaining seconds of the countdown line ("... Try again in 0:30." or "... in 7:59.").
    private func countdownSeconds() throws -> Int {
        let line = text(containing: "Try again in").exists ? text(containing: "Try again in") : text(containing: "Recovery phrase accepted")
        let label = line.label
        guard let range = label.range(of: #"\d+:\d{2}"#, options: .regularExpression) else { throw FlowStop.fail("no countdown in '\(label)'") }
        let parts = label[range].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { throw FlowStop.fail("unreadable countdown '\(label)'") }
        return parts[0] * 60 + parts[1]
    }

    /// A held touch: switches and pickers on the simulator ignore an instant tap.
    private func heldTap(_ element: XCUIElement, dx: CGFloat = 0.93) {
        element.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).press(forDuration: 0.4)
    }

    private func setSwitch(_ element: XCUIElement, on: Bool) throws {
        let want = on ? "1" : "0"
        if (element.value as? String) == want { return }
        heldTap(element)
        if eventually(5, every: 0.5, { (element.value as? String) == want }) { return }
        heldTap(element, dx: 0.5)
        guard eventually(5, every: 0.5, { (element.value as? String) == want }) else {
            throw FlowStop.fail("the switch '\(element.label)' did not turn \(on ? "on" : "off")")
        }
    }
}
