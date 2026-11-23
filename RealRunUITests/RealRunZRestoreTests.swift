// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest

/// Flow 14, restore: the backup of RealRunLifecycleTests restored on a fresh install as a new account on
/// this device. It reinstalls the app, so this class sorts last.
final class RealRunZRestoreTests: RealRunTestCase {
    func test99_restoreBackupOnFreshInstall() {
        flow("14b-restore") {
            guard let passphrase = RunSecrets.archivePassphrase else { throw FlowStop.blocked("needs flow 14 (a verified backup)") }
            let fresh = control.post("fresh-install", json: [:])
            guard let archive = fresh["archive"] as? String else { throw FlowStop.fail("the harness could not reinstall the app: \(fresh["error"] ?? "no reply")") }
            app.launch()
            dismissPrompts()
            // Fresh install: Accounts, Add account, then Restore from backup on the welcome board.
            try tap(element("shell-accounts"), "Accounts on the empty shell", timeout: 60)
            try tap(button("Add account"), "Add account")
            try tap(element("s02-continue"), "Continue on the node screen", timeout: 30)
            try tap(element("s18-restore-backup"), "Restore from backup")
            try tap(element("backup-import"), "Restore from an archive", timeout: 30)
            // The system document picker: On My iPhone, then the archive the harness placed there.
            let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", String(archive.prefix(while: { $0 != "." })))).firstMatch
            if !file.waitForExistence(timeout: 10) {
                let browse = app.buttons["Browse"].firstMatch
                if browse.waitForExistence(timeout: 5) { browse.tap() }
                let local = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'On My iPhone'")).firstMatch
                if local.waitForExistence(timeout: 10) { local.tap() }
            }
            guard file.waitForExistence(timeout: 20) else { throw FlowStop.fail("the document picker does not show the archive \(archive): \(visibleFailure())") }
            snap("14b-picker")
            file.tap()
            let editor = try require(element("secure-entry-passphrase"), "archive passphrase field", timeout: 60)
            editor.tap(); editor.typeText(passphrase)
            try tap(element("secure-entry-submit"), "verify the archive")
            // Install with a new six-digit code for this device.
            let code = RunSecrets.newCode()
            let newCode = try require(element("secure-entry-passphraseRepeat"), "new account code fields", timeout: 180)
            let first = element("secure-entry-passphrase")
            first.tap(); first.typeText(code)
            newCode.tap(); newCode.typeText(code)
            try tap(element("secure-entry-submit"), "install the restored account")
            let merge = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Confirm:'")).firstMatch
            let restored = element("backup-restored")
            guard eventually(240, every: 2, { restored.exists || merge.exists }) else { throw FlowStop.fail("the restore did not finish within 4 minutes: \(visibleFailure())") }
            if merge.exists { merge.tap(); guard restored.waitForExistence(timeout: 240) else { throw FlowStop.fail("the restore did not finish after the merge confirmation: \(visibleFailure())") } }
            snap("14b-restored")
            RunSecrets.accountCode = code
            try tap(element("backup-restored-continue"), "Continue after restore")
            // The restored account is offered and opens with the new code; alice's conversation is there.
            try unlockIfNeeded()
            guard element("tab-messages").waitForExistence(timeout: 30) else { throw FlowStop.fail("no unlocked account after the restore: \(visibleFailure())") }
            try openTab("messages")
            var detail = "archive verified and installed on a fresh install with a new code; the account opens"
            if let conversation = RunSecrets.aliceConversation {
                detail += element(conversation).waitForExistence(timeout: 60) ? "; alice's conversation is listed" : "; alice's conversation is not listed yet"
            }
            return detail
        }
    }
}
