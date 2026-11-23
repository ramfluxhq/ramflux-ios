// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest

/// Shared driver for the real-run flows. Each flow records PASS, FAIL or BLOCKED with the control server,
/// which writes the table; screenshots go there too. The app keeps running between flows (the simulator
/// is reset once by scripts/realrun.sh before the suite), so later flows build on the account of flow 1.
class RealRunTestCase: XCTestCase {
    nonisolated(unsafe) static var config: RealRunConfig?
    nonisolated(unsafe) static var shots = 0
    /// True while the recovery phrase is on screen: no screenshot is taken or sent then.
    nonisolated(unsafe) static var sensitive = false
    var config: RealRunConfig { Self.config! }
    var control: PeerControl { PeerControl(base: config.control) }
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = true
        if Self.config == nil { Self.config = try RealRunConfig.load() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if app.state == .notRunning || app.state == .unknown { app.launch() } else { app.activate() }
    }

    /// Runs one flow: records PASS when `body` returns, FAIL or BLOCKED with the reason when it throws.
    func flow(_ id: String, _ body: () throws -> String) {
        control.log("flow \(id) started")
        currentFlow = id
        defer { Self.sensitive = false; currentFlow = nil }
        do {
            let detail = try body()
            control.record(id, "PASS", detail)
            snap("\(id)-pass")
        } catch let stop as FlowStop {
            snap("\(id)-\(stop.status.lowercased())")
            control.log("flow \(id) \(stop.status): \(stop.description)\n\(app.debugDescription.prefix(40000))")
            control.record(id, stop.status, stop.description)
            if stop.status == "FAIL" { XCTFail("\(id): \(stop.description)") }
        } catch {
            snap("\(id)-error")
            control.record(id, "FAIL", "unexpected error: \(error)")
            XCTFail("\(id): \(error)")
        }
    }

    /// The flow in progress; an XCTest issue that aborts the test (an event that cannot be synthesised)
    /// skips `flow`'s own recording, so tearDown records it as FAIL with the last issue.
    var currentFlow: String?
    var lastIssue = ""
    override func record(_ issue: XCTIssue) {
        lastIssue = issue.compactDescription
        super.record(issue)
    }
    override func tearDown() {
        if let id = currentFlow {
            snap("\(id)-interrupted")
            control.log("flow \(id) interrupted: \(lastIssue)\n\(app.debugDescription.prefix(40000))")
            control.record(id, "FAIL", "test interrupted: \(lastIssue.prefix(500))")
            currentFlow = nil; Self.sensitive = false
        }
        super.tearDown()
    }

    func snap(_ name: String) {
        guard !Self.sensitive else { return }
        Self.shots += 1
        let safe = String(format: "%03d-", Self.shots) + name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
        let shot = XCUIScreen.main.screenshot()
        control.screenshot(String(safe.prefix(80)), png: shot.pngRepresentation)
    }

    // MARK: Element helpers

    func textField(_ id: String) -> XCUIElement { app.textFields.matching(identifier: id).firstMatch }
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func button(_ label: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label)).firstMatch }
    func text(containing fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", fragment, fragment)).firstMatch
    }

    @discardableResult
    func require(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 20) throws -> XCUIElement {
        guard element.waitForExistence(timeout: timeout) else { throw FlowStop.fail("\(what) did not appear within \(Int(timeout)) s") }
        return element
    }
    /// Declines the app's notification explanation sheet (Cancel never asks the system) when it covers the screen.
    func dismissPrompts() {
        let prompt = app.staticTexts["Turn on notifications?"]
        if prompt.exists {
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { cancel.tap(); _ = prompt.waitForNonExistence(timeout: 5) }
        }
    }
    func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 20) throws {
        dismissPrompts()
        try require(element, what, timeout: timeout)
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isEnabled || !element.isHittable {
            guard Date() < deadline else { throw FlowStop.fail("\(what) never became enabled and hittable") }
            dismissPrompts()
            Thread.sleep(forTimeInterval: 0.3)
        }
        element.tap()
    }
    /// Polls until `condition` holds (UI state or a peer-side fact); false after `timeout`.
    func eventually(_ timeout: TimeInterval = 30, every: TimeInterval = 1, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat { if condition() { return true }; Thread.sleep(forTimeInterval: every) } while Date() < deadline
        return false
    }
    /// The visible failure view text, if any (for FAIL/BLOCKED details).
    func visibleFailure() -> String {
        let labels = app.staticTexts.allElementsBoundByIndex.prefix(60).map(\.label)
        return labels.joined(separator: " | ").prefix(600).description
    }

    // MARK: Session helpers

    /// Unlocks the run account. The SDK lists only open accounts and the app keeps no list of known
    /// accounts, so after a lock or a cold start the way back is Add account, the existing-account path
    /// and the account id typed into the unlock form (reported as a client defect), then the code.
    func unlockIfNeeded() throws {
        let code = element("secure-entry-passphrase")
        if !code.waitForExistence(timeout: 3) {
            if element("tab-messages").exists && !element("shell-accounts").exists { element("tab-messages").tap() }
            guard element("shell-accounts").waitForExistence(timeout: 3) else { return }
            guard let account = RunSecrets.accountID else { throw FlowStop.fail("account is locked and its id was not captured") }
            element("shell-accounts").tap()
            let listed = app.buttons[RunSecrets.displayName].firstMatch
            if listed.waitForExistence(timeout: 3) { listed.tap() } else {
                try tap(button("Add account"), "Add account")
                try tap(element("s02-continue"), "Continue on the node screen", timeout: 30)
                try tap(element("s18-existing"), "existing account")
                try tap(element("a01-unlock"), "Unlock existing account")
                let field = try require(textField("a02-account"), "account id field")
                field.tap(); field.typeText(account)
            }
            guard code.waitForExistence(timeout: 15) else { throw FlowStop.fail("no unlock form: \(visibleFailure())") }
        }
        code.tap(); code.typeText(RunSecrets.accountCode)
        try tap(element("secure-entry-submit"), "unlock submit")
        guard code.waitForNonExistence(timeout: 30) else { throw FlowStop.fail("unlock form still shown after submit: \(visibleFailure())") }
        // A completion page may follow the unlock.
        let done = button("Continue")
        if done.waitForExistence(timeout: 5) && !element("tab-messages").isHittable { done.tap() }
    }

    func openMore() throws { try openTab("more") }
    /// Tabs by their hit tags: messages, groups, agents, more.
    func openTab(_ name: String) throws { try tap(element("tab-" + name), "\(name) tab") }
    /// Kit page headers and the system bar both label their back control "Back".
    func back() {
        let backButton = app.buttons.matching(NSPredicate(format: "label == 'Back'")).allElementsBoundByIndex.first { $0.isHittable }
        backButton?.tap()
    }
}
