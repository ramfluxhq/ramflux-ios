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
        let started = Date()
        while !element.isEnabled || !element.isHittable {
            // XCUITest sometimes reports an enabled, visible control as not hittable (seen with the keyboard
            // up under an overlay); after a few seconds an enabled control on screen is tapped at its centre.
            if element.isEnabled, Date().timeIntervalSince(started) > 4, app.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); return
            }
            guard Date() < deadline else { throw FlowStop.fail("\(what) never became enabled and hittable") }
            dismissPrompts()
            Thread.sleep(forTimeInterval: 0.3)
        }
        element.tap()
    }
    /// Taps the host confirmation ("Confirm: ..."); a long review sheet keeps it below the fold, so scroll first.
    func confirmHost(_ what: String, timeout: TimeInterval = 30) throws {
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Confirm:'")).firstMatch
        try require(confirm, what, timeout: timeout)
        for _ in 0..<4 where !(confirm.isHittable && app.frame.contains(CGPoint(x: confirm.frame.midX, y: confirm.frame.midY))) {
            app.swipeUp(); Thread.sleep(forTimeInterval: 0.5)
        }
        try tap(confirm, what, timeout: timeout)
    }
    /// Closes a review sheet a failed step left open (its Cancel, scrolled into view).
    func closeLeftoverSheet() {
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel'")).firstMatch
        guard cancel.exists else { return }
        for _ in 0..<4 where !cancel.isHittable { app.swipeUp(); Thread.sleep(forTimeInterval: 0.3) }
        cancel.tapIfExists()
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

    /// The "Unlock <name>" action the locked Messages tab offers for this run's account (known-account registry).
    func knownAccountUnlock() -> XCUIElement {
        // A Kit button's hit target carries the tag with "-hit"; its label holds the isolated display name.
        app.buttons.matching(NSPredicate(format: "identifier == 'shell-unlock-account-hit' AND label CONTAINS %@", RunSecrets.displayName)).firstMatch
    }
    /// Unlocks the run account: the locked Messages tab offers it by display name (the device's registry
    /// of known accounts); the unlock step shows the name and asks only for the six-digit code.
    func unlockIfNeeded() throws {
        let code = element("secure-entry-passphrase")
        if !code.waitForExistence(timeout: 3) {
            if element("tab-messages").exists && !knownAccountUnlock().exists { element("tab-messages").tap() }
            guard element("shell-accounts").waitForExistence(timeout: 3) else { return }
            try tap(knownAccountUnlock(), "Unlock \(RunSecrets.displayName) on the locked Messages tab", timeout: 10)
            let shown = try require(element("a02-known-account"), "known account name on the unlock step", timeout: 15)
            guard shown.label.contains(RunSecrets.displayName), !textField("a02-account").exists else {
                throw FlowStop.fail("unlock step does not show the account by name only (label: \(shown.label))")
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
