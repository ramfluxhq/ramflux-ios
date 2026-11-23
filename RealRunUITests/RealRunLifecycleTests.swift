// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest

/// Background and return, the account-code change and backup, on the account and conversation of
/// RealRunFlowTests (this class sorts after it and before RealRunScreenFlowTests).
final class RealRunLifecycleTests: RealRunTestCase {

    // MARK: Background and return: session and an in-flight send survive

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
            // An unsent draft stays in the composer across the background and the lock.
            let draft = "rr-draft-" + token()
            input.tap(); input.typeText(draft)
            XCUIDevice.shared.press(.home)
            let whileAway = "rr-while-away-" + token()
            let sent = control.rf("alice", ["conversation", "send", "--conversation", conversation, "--text", whileAway])
            Thread.sleep(forTimeInterval: 20)
            let arrivedInBackground = eventually(5, { self.aliceHas(conversation, queued) })
            app.activate()
            var notes = [arrivedInBackground ? "the in-flight send reached alice while the app was in the background" : "the in-flight send had not reached alice while in the background"]
            var askedForCode = false
            if element("secure-entry-passphrase").waitForExistence(timeout: 5) || element("shell-accounts").exists || text(containing: "Unlock your account").exists {
                askedForCode = true
                notes.append("returning asked for the account code (the locked tab offered the account by name)")
                // Nothing of the conversation is shown before the unlock.
                guard !text(containing: queued).exists, !text(containing: draft).exists, !element("chat-composer-input").exists else {
                    throw FlowStop.fail("conversation content is visible before the unlock: \(visibleFailure())")
                }
                notes.append("no conversation content before the unlock")
                try unlockIfNeeded()
                // After unlock the app reopens the screen the user had open.
                guard element("chat-composer-input").waitForExistence(timeout: 20) else {
                    throw FlowStop.fail("after unlock the app did not return to the open chat: \(visibleFailure())")
                }
                notes.append("after unlock the app returned to the open chat")
                snap("04c-reopened")
            } else { notes.append("session kept without unlock") }
            snap("04c-returned")
            let composer = element("chat-composer-input")
            let kept = eventually(10, { ((composer.value as? String) ?? "").contains(draft) })
            notes.append(kept ? "the composer draft was kept" : "the composer draft was lost (composer shows \(((composer.value as? String) ?? "").count) characters)")
            guard kept else { throw FlowStop.fail(notes.joined(separator: "; ")) }
            guard eventually(90, every: 3, { self.aliceHas(conversation, queued) }) else { throw FlowStop.fail("the send made before backgrounding never reached alice; \(notes.joined(separator: "; "))") }
            notes.append("the send made before backgrounding reached alice")
            if sent.exit == 0 {
                guard text(containing: whileAway).waitForExistence(timeout: 60) else { throw FlowStop.fail("alice's message sent while the app was in the background did not appear after return") }
                notes.append("alice's message sent while away appeared after return")
            } else { notes.append("alice could not send while away (exit \(sent.exit))") }
            // Asking for the code on return is expected: the C ABI v2 has no suspend, so releasing the data-root
            // writer in the background closes the SDK and locks every account (see docs/app-shell.md).
            return notes.joined(separator: "; ") + (askedForCode ? " (the code is asked on return because the C ABI v2 has no suspend; the SDK closes in the background)" : "")
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
