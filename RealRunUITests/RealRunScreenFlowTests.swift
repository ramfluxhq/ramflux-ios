// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest

/// The screen-level beta flows that need no peer action: settings, pairing invitation, agents, tasks,
/// calls and privacy. They run after RealRunFlowTests (class names sort in run order) on the same account.
final class RealRunScreenFlowTests: RealRunTestCase {

    // MARK: Flow 10: settings (lock is covered by flow 1), devices, language

    func test10_settingsDevicesLanguage() {
        flow("10-settings") {
            try ensureShell()
            try openSettings()
            try tap(element("settings-devices"), "My devices")
            try require(text(containing: "This device"), "this device row in My devices", timeout: 30)
            snap("10-devices")
            back()
            try tap(element("settings-appearance"), "Appearance and language")
            try require(element("settings-language-system"), "change language in system settings button", timeout: 20)
            let current = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'settings-language-'")).count
            snap("10-language")
            return "My devices lists this device; language screen lists \(current - 1) languages with the system change action; lock covered by flow 1"
        }
    }

    // MARK: Flow 2: inviter-side pairing, as far as the invitation

    func test11_pairingInvitation() {
        flow("02-pairing") {
            try ensureShell()
            try openSettings()
            try tap(element("settings-devices"), "My devices")
            try tap(button("Link new device"), "Link new device")
            let name = app.textFields.firstMatch
            if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Realrun second device") }
            try tap(button("Create invitation"), "Create invitation")
            Thread.sleep(forTimeInterval: 10)
            snap("02-pairing")
            let qr = app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS[c] 'qr' OR label CONTAINS[c] 'QR'")).firstMatch
            let shown = visibleFailure()
            if qr.exists { return "pairing invitation shown (\(qr.identifier.isEmpty ? qr.label : qr.identifier))" }
            throw FlowStop.blocked("no invitation after Create invitation; screen says: \(shown). Node note: device_pairing_v2 needs an HTTPS public origin (ops/local-node RUNBOOK section 5)")
        }
    }

    // MARK: Flows 8, 9, 12, 15

    func test12_agentsListEmpty() {
        flow("08-agents") {
            try ensureShell()
            try openTab("agents")
            guard eventually(30, { self.text(containing: "No agents yet").exists || self.text(containing: "No agents found").exists }) else { throw FlowStop.fail("agents list did not show its empty state: \(visibleFailure())") }
            snap("08-agents")
            return "Agents tab loads and shows the empty state (no agents on this account)"
        }
    }

    func test13_tasksListEmpty() {
        flow("09-tasks") {
            try ensureShell()
            try openMore()
            try tap(element("more-tasks"), "Tasks in More")
            // Tasks are listed per conversation: choose the direct conversation with alice when offered.
            if text(containing: "Tasks belong to a conversation").waitForExistence(timeout: 10),
               let conversation = RunSecrets.aliceConversation {
                // Direct rows are titled with the contact's name now, no longer with the dm id.
                let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR identifier == %@ OR label CONTAINS %@", conversation, conversation, config.alice.displayName)).firstMatch
                if row.waitForExistence(timeout: 10) { row.tap() }
            }
            guard text(containing: "No records in this context").waitForExistence(timeout: 30) else { throw FlowStop.fail("tasks list did not show its empty state: \(visibleFailure())") }
            snap("09-tasks")
            return "Tasks loads and shows the empty state"
        }
    }

    func test14_callsHonestUnavailable() {
        flow("12-calls") {
            try ensureShell()
            try openMore()
            try tap(element("more-calls"), "Calls in More")
            try require(text(containing: "Call history"), "call history screen", timeout: 20)
            snap("12-call-history")
            back()
            // The unavailable state belongs to starting a call: try one with alice from the chat header.
            guard let conversation = RunSecrets.aliceConversation else { throw FlowStop.blocked("needs flow 3 (conversation with alice) to start a call") }
            try openTab("messages")
            try tap(element(conversation), "conversation row", timeout: 30)
            try tap(app.buttons.matching(NSPredicate(format: "label == 'Call' OR label == 'Voice call'")).firstMatch, "call button in the chat header")
            let honest = ["Calls are not available", "Voice relay unavailable", "Signaling unavailable", "identity authority is unavailable", "cannot be started"]
            var shown = ""
            let found = eventually(30, { shown = self.visibleFailure(); return honest.contains { shown.contains($0) } })
            snap("12-call-attempt")
            guard found else { throw FlowStop.fail("starting a call showed no unavailable state: \(shown)") }
            return "call history loads empty; starting a call with alice shows an unavailable state: \(honest.first { shown.contains($0) } ?? "")"
        }
    }

    func test15_privacyPolicyAndOpenAccount() {
        flow("15-privacy") {
            try ensureShell()
            try openSettings()
            try tap(element("settings-account"), "Account and security")
            try tap(element("settings-privacy"), "Privacy")
            let policy = try require(element("settings-auto-accept"), "request policy row", timeout: 30)
            guard eventually(20, { policy.isEnabled }) else { throw FlowStop.fail("request policy never loaded (row stays disabled): \(visibleFailure())") }
            snap("15-privacy")
            try tap(element("settings-open-account"), "Open account row")
            guard text(containing: "not available in the account service yet").waitForExistence(timeout: 10) else {
                throw FlowStop.fail("open-account row shows no unavailable state: \(visibleFailure())")
            }
            snap("15-open-account")
            return "request policy loaded from the SDK (auto-accept row enabled); open account shows the typed unavailable state"
        }
    }

    func ensureShell() throws {
        dismissPrompts()
        closeLeftoverSheet()
        for _ in 0..<6 where !element("tab-messages").isHittable { back(); Thread.sleep(forTimeInterval: 0.6) }
        try unlockIfNeeded()
        dismissPrompts()
        for _ in 0..<6 where !element("tab-messages").isHittable { back(); Thread.sleep(forTimeInterval: 0.6) }
        guard element("tab-messages").waitForExistence(timeout: 20) else { throw FlowStop.blocked("no unlocked account (flow 1 did not complete)") }
    }
    func openSettings() throws {
        try openMore()
        try tap(element("more-settings"), "Settings in More")
    }
}
