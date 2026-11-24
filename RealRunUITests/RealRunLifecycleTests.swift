// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest

/// Background and return, the account-code change and backup, on the account and conversation of
/// RealRunFlowTests (this class sorts after it and before RealRunScreenFlowTests).
final class RealRunLifecycleTests: RealRunTestCase {

    // MARK: Background and return: no prompt, the open chat, its draft and an in-flight send survive

    func test05_backgroundAndReturn() {
        flow("04c-background") {
            try ensureSession()
            guard let conversation = RunSecrets.aliceConversation else { throw FlowStop.blocked("needs flows 3 and 4 (conversation with alice)") }
            try openChat(conversation)
            // Send, then leave at once: the send is in flight when the app moves to the background.
            let queued = "rr-bg-send-" + token()
            let input = try require(element("chat-composer-input"), "composer input")
            input.tap(); input.typeText(queued)
            try tap(element("chat-composer-send"), "send button")
            // An unsent draft stays in the composer across the background.
            let draft = "rr-draft-" + token()
            input.tap(); input.typeText(draft)
            XCUIDevice.shared.press(.home)
            let whileAway = "rr-while-away-" + token()
            let sent = control.rf("alice", ["conversation", "send", "--conversation", conversation, "--text", whileAway])
            Thread.sleep(forTimeInterval: 20)
            let arrivedInBackground = eventually(5, { self.aliceHas(conversation, queued) })
            app.activate()
            var notes = [arrivedInBackground ? "the in-flight send reached alice while the app was in the background" : "the in-flight send was held while the app was suspended"]
            // The SDK suspends in the background and resumes on return: nothing is asked.
            if element("secure-entry-passphrase").waitForExistence(timeout: 5) || element("shell-accounts").exists || element("a02-known-account").exists {
                snap("04c-asked")
                throw FlowStop.fail("returning from the background asked for the account code: \(visibleFailure())")
            }
            notes.append("returning asked for nothing")
            guard element("chat-composer-input").waitForExistence(timeout: 10) else {
                throw FlowStop.fail("the open chat did not stay open across the background: \(visibleFailure())")
            }
            notes.append("the open chat stayed open")
            snap("04c-returned")
            let composer = element("chat-composer-input")
            let kept = eventually(10, { ((composer.value as? String) ?? "").contains(draft) })
            notes.append(kept ? "the composer draft was kept" : "the composer draft was lost (composer shows \(((composer.value as? String) ?? "").count) characters)")
            guard kept else { throw FlowStop.fail(notes.joined(separator: "; ")) }
            guard eventually(90, every: 3, { self.aliceHas(conversation, queued) }) else { throw FlowStop.fail("the send made before backgrounding never reached alice; \(notes.joined(separator: "; "))") }
            notes.append("the send made before backgrounding reached alice")
            if sent.exit == 0 {
                guard text(containing: whileAway).waitForExistence(timeout: 60) else { throw FlowStop.fail("alice's message sent while the app was in the background did not appear after return; \(notes.joined(separator: "; "))") }
                notes.append("alice's message sent while away appeared after return")
            } else { notes.append("alice could not send while away (exit \(sent.exit))") }
            // Leave the composer empty for the flows that follow.
            composer.replaceText("")
            return notes.joined(separator: "; ")
        }
    }

    // MARK: Terminate and relaunch: the account opens without the code (device-bound key)

    func test05r_terminateAndRelaunch() {
        flow("04d-relaunch") {
            try ensureSession()
            guard let conversation = RunSecrets.aliceConversation else { throw FlowStop.blocked("needs flows 3 and 4 (conversation with alice)") }
            app.terminate()
            let whileClosed = "rr-while-closed-" + token()
            let sent = control.rf("alice", ["conversation", "send", "--conversation", conversation, "--text", whileClosed])
            app.launch()
            var notes: [String] = []
            // A cold start opens the account with its device-bound key; the code is not asked.
            if element("secure-entry-passphrase").waitForExistence(timeout: 8) || knownAccountUnlock().exists || element("a02-known-account").exists {
                snap("04d-asked")
                throw FlowStop.fail("relaunching asked for the account code: \(visibleFailure())")
            }
            guard element("tab-messages").waitForExistence(timeout: 30), !element("shell-accounts").exists else {
                throw FlowStop.fail("after the relaunch no account is open: \(visibleFailure())")
            }
            notes.append("relaunching asked for nothing; the account opened by itself")
            try openTab("messages")
            guard text(containing: RunSecrets.displayName).waitForExistence(timeout: 20) else { throw FlowStop.fail("Messages does not show the account after the relaunch: \(visibleFailure())") }
            guard element(conversation).waitForExistence(timeout: 30) else { throw FlowStop.fail("the conversation with alice is not listed after the relaunch: \(visibleFailure())") }
            snap("04d-relaunched")
            notes.append("Messages lists the conversation with alice")
            try openChat(conversation)
            if sent.exit == 0 {
                guard text(containing: whileClosed).waitForExistence(timeout: 60) else { throw FlowStop.fail("alice's message sent while the app was closed did not appear; \(notes.joined(separator: "; "))") }
                notes.append("alice's message sent while the app was closed arrived")
            } else { notes.append("alice could not send while the app was closed (exit \(sent.exit))") }
            back()
            return notes.joined(separator: "; ")
        }
    }

    // MARK: Flow 10: change the account code (account.passphrase.rotate), then lock and unlock with it

    func test06_changeAccountCode() {
        flow("10b-change-code") {
            try ensureSession()
            try openMore()
            try tap(element("more-settings"), "Settings in More")
            try tap(element("settings-account"), "Account and security")
            try tap(element("settings-change-code"), "Change account code")
            let fresh = RunSecrets.newCode()
            for (field, value) in [("oldPassphrase", RunSecrets.accountCode), ("passphrase", fresh), ("passphraseRepeat", fresh)] {
                let editor = try require(element("secure-entry-" + field), "\(field) field")
                editor.tap(); editor.typeText(value)
            }
            try tap(element("secure-entry-submit"), "submit code change")
            guard element("settings-code-changed").waitForExistence(timeout: 60) else {
                throw FlowStop.fail("no confirmation that the code changed: \(visibleFailure())")
            }
            RunSecrets.accountCode = fresh
            snap("10b-code-changed")
            try tap(element("settings-lock"), "Lock account")
            try unlockIfNeeded()
            guard element("tab-messages").waitForExistence(timeout: 20), !element("secure-entry-passphrase").exists else { throw FlowStop.fail("unlock with the new code failed: \(visibleFailure())") }
            return "account.passphrase.rotate accepted; lock and unlock with the new code work"
        }
    }

    // MARK: Flow 14: create a backup and let it verify

    func test07_backupCreateAndVerify() {
        flow("14-backup") {
            try ensureSession()
            try openMore()
            try tap(element("more-settings"), "Settings in More")
            try tap(element("settings-backup"), "Backup and recovery")
            let create = try require(element("backup-create"), "Create backup", timeout: 30)
            guard eventually(60, { create.isEnabled }) else {
                throw FlowStop.blocked("Create backup stays disabled: the backup connection is not attended (\(visibleFailure()))")
            }
            try tap(create, "Create backup")
            let archive = UUID().uuidString
            RunSecrets.archivePassphrase = archive
            for field in ["passphrase", "passphraseRepeat"] {
                let editor = try require(element("secure-entry-" + field), "archive \(field) field")
                editor.tap(); editor.typeText(archive)
            }
            try tap(element("secure-entry-submit"), "start backup")
            let job = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'backup-job-'")).firstMatch
            try require(job, "backup job row", timeout: 60)
            var label = ""
            guard eventually(240, every: 3, {
                label = job.label
                return label.contains("Done") || label.contains("Failed") || label.contains("Cancelled")
            }) else { throw FlowStop.fail("backup job did not finish within 4 minutes (last: \(label))") }
            snap("14-backup")
            guard label.contains("Done") else { throw FlowStop.fail("backup job ended as: \(label); \(visibleFailure())") }
            return "backup created and verified by the SDK job (\(label)); attended connection accepted"
        }
    }

    // MARK: In-app banner: a message from alice on the conversation list raises it, a tap opens the thread

    func test17_inAppBannerTap() {
        flow("17-in-app-banner") {
            try ensureSession()
            guard let conversation = RunSecrets.aliceConversation else { throw FlowStop.blocked("needs flows 3 and 4 (conversation with alice)") }
            try openTab("messages")
            try require(element(conversation), "conversation row", timeout: 30)
            let phrase = "rr-banner-" + token()
            guard control.rf("alice", ["conversation", "send", "--conversation", conversation, "--text", phrase]).exit == 0 else { throw FlowStop.blocked("alice could not send") }
            let banner = element("in-app-banner")
            guard banner.waitForExistence(timeout: 30) else { throw FlowStop.fail("no in-app banner on the conversation list: \(visibleFailure())") }
            snap("17-banner")
            let label = banner.label
            try tap(banner, "banner")
            guard element("chat-composer-input").waitForExistence(timeout: 15) else { throw FlowStop.fail("tapping the banner did not open the conversation: \(visibleFailure())") }
            guard text(containing: phrase).waitForExistence(timeout: 30) else { throw FlowStop.fail("the opened conversation does not show the message") }
            snap("17-opened")
            // With the thread open a new message raises no banner.
            let second = "rr-banner-open-" + token()
            _ = control.rf("alice", ["conversation", "send", "--conversation", conversation, "--text", second])
            guard text(containing: second).waitForExistence(timeout: 30) else { throw FlowStop.fail("the second message did not arrive in the open thread") }
            Thread.sleep(forTimeInterval: 2)
            guard !banner.exists else { throw FlowStop.fail("a banner appeared with the thread open") }
            back()
            return "banner found by id in-app-banner (label \"\(label)\"); tap opened the conversation; no banner with the thread open"
        }
    }

    // MARK: Snapshot privacy: leave for the Home screen with a chat open and the keyboard up

    func test18_snapshotWithKeyboard() {
        flow("18-snapshot-keyboard") {
            // A fresh process: the list is read again from the SDK.
            app.terminate(); app.launch()
            try ensureSession()
            guard let conversation = RunSecrets.aliceConversation else { throw FlowStop.blocked("needs flows 3 and 4 (conversation with alice)") }
            try openChat(conversation)
            let input = try require(element("chat-composer-input"), "composer input")
            input.tap(); input.typeText("snapshot probe hello wor")
            snap("18-keyboard-up")
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 4)
            return "the chat was open with the keyboard up and typed text when Home was pressed; the app's snapshots are inspected from its data container"
        }
    }

    func ensureSession() throws {
        dismissPrompts()
        closeLeftoverSheet()
        for _ in 0..<6 where !element("tab-messages").isHittable { back(); Thread.sleep(forTimeInterval: 0.6) }
        try unlockIfNeeded()
        dismissPrompts()
        for _ in 0..<6 where !element("tab-messages").isHittable { back(); Thread.sleep(forTimeInterval: 0.6) }
        guard element("tab-messages").waitForExistence(timeout: 20) else { throw FlowStop.blocked("no unlocked account (flow 1 did not complete)") }
    }
    func openChat(_ id: String) throws {
        if element("chat-composer-input").exists { return }
        try openTab("messages")
        try tap(element(id), "conversation row", timeout: 30)
        try require(element("chat-composer-input"), "chat composer", timeout: 20)
    }
    func token() -> String { String(UUID().uuidString.prefix(8)).lowercased() }
    func aliceHas(_ conversation: String, _ fragment: String) -> Bool {
        let rows = control.rf("alice", ["dm", "read", "--conversation", conversation, "--limit", "100"]).json?["messages"] as? [[String: Any]] ?? []
        return rows.contains { (((($0["content"] as? [String: Any])?["message"] as? [String: Any])?["text"] as? String) ?? "").contains(fragment) }
    }
}
