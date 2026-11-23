// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest

/// The beta flows against the local node, in the order of the real-run brief. Method names sort in run order.
final class RealRunFlowTests: RealRunTestCase {

    // MARK: Flow 1: custom node, account, recovery phrase, account code, lock, unlock

    func test01_onboardingCustomNodeAccountLockUnlock() {
        flow("01-onboarding") {
            try tap(element("shell-accounts"), "Accounts button on the empty shell")
            try tap(button("Add account"), "Add account")
            // S02: change the node to the local origin, typed in full with its http scheme.
            try tap(element("s02-change-node"), "change node row", timeout: 30)
            let field = try require(textField("onboarding-address"), "node address field")
            field.tap(); field.typeText(config.origin)
            snap("01-address-typed")
            try tap(button("Check address"), "Check address")
            try tap(button("Connect to this origin"), "Connect to this origin", timeout: 30)
            let keyInput = try require(textField("onboarding-operator-key"), "operator key field", timeout: 40)
            keyInput.tap(); keyInput.typeText(config.operatorKey)
            try tap(button("Review fingerprint"), "Review fingerprint")
            let print = try require(element("onboarding-node-fingerprint"), "node fingerprint", timeout: 30)
            let shown = (print.label + " " + (print.value as? String ?? "")).lowercased().filter { $0.isHexDigit }
            snap("01-fingerprint")
            guard shown.contains(config.fingerprint) else { throw FlowStop.fail("fingerprint shown (\(shown)) differs from node-facts \(config.fingerprint)") }
            try tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Confirm:'")).firstMatch, "fingerprint confirmation")
            try tap(button("Create an account"), "Create an account (node saved)", timeout: 30)
            // N01: display name, then create.
            let nameInput = try require(textField("n01-name"), "display name field")
            nameInput.tap(); nameInput.typeText(RunSecrets.displayName)
            try tap(button("Create the account"), "Create the account")
            Self.sensitive = true
            try tap(button("Show recovery phrase once"), "Show recovery phrase once", timeout: 60)
            let phrase = try require(app.otherElements["Private recovery phrase display"], "recovery phrase display", timeout: 30)
            Thread.sleep(forTimeInterval: 1)
            let words = try PhraseReader.words(in: phrase, scroll: app.scrollViews.firstMatch, obstruction: button("I saved it. Hide and continue"), progress: { control.log("phrase reading " + $0) })
            let unreadable = words.enumerated().filter { !(3...8).contains($0.element.count) }.map { $0.offset + 1 }
            guard words.count == 24, unreadable.isEmpty else {
                throw FlowStop.fail("text recognition could not read recovery word cells \(unreadable) (lengths only: \(words.map(\.count)))")
            }
            RunSecrets.words = words
            try tap(button("I saved it. Hide and continue"), "Hide and continue")
            Self.sensitive = false
            // Confirm: the challenge lists word positions; the form asks for them in that order.
            try require(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'onboarding-word-'")).firstMatch,
                        "confirmation word positions", timeout: 30)
            let positions = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'onboarding-word-'"))
                .allElementsBoundByIndex.compactMap { Int($0.identifier.dropFirst("onboarding-word-".count)) }
            var seen = Set<Int>(); let ordered = positions.filter { seen.insert($0).inserted }
            guard !ordered.isEmpty, ordered.allSatisfy({ (1...24).contains($0) }) else { throw FlowStop.fail("unexpected word positions \(ordered)") }
            snap("01-confirm-positions")
            try tap(button("Set account code"), "Set account code")
            for (index, position) in ordered.enumerated() {
                let wordField = try require(element("secure-entry-word\(index + 1)"), "word field \(index + 1)")
                wordField.tap(); wordField.typeText(words[position - 1])
            }
            let code = try require(element("secure-entry-passphrase"), "new account code")
            code.tap(); code.typeText(RunSecrets.accountCode)
            let repeatCode = try require(element("secure-entry-passphraseRepeat"), "repeat account code")
            repeatCode.tap(); repeatCode.typeText(RunSecrets.accountCode)
            try tap(element("secure-entry-submit"), "Confirm once")
            let connected = text(containing: "Connected")
            let pending = text(containing: "Network connection has not been confirmed")
            guard eventually(90, { connected.exists || pending.exists }) else { throw FlowStop.fail("account completion did not appear: \(visibleFailure())") }
            let networking = connected.exists ? "networking live at completion" : "completion says network not confirmed"
            let shownID = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'account-'")).firstMatch.label
            RunSecrets.accountID = String(shownID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
            control.log("phone account \(RunSecrets.accountID ?? "?") named \(RunSecrets.displayName)")
            snap("01-complete")
            try tap(button("Continue"), "Continue after completion")
            try require(element("app-shell"), "app shell", timeout: 30)
            // Lock through Settings, then unlock with the code.
            try lockAccount()
            snap("01-locked")
            try unlockIfNeeded()
            try require(element("tab-messages"), "Messages tab after unlock", timeout: 30)
            guard !element("secure-entry-passphrase").waitForExistence(timeout: 3) else { throw FlowStop.fail("unlock form still visible after submit: \(visibleFailure())") }
            throw FlowStop.fail("all steps worked (node \(config.origin) accepted as typed, fingerprint matched, 24 words confirmed, code set, \(networking), lock, unlock), but after lock the account is not offered anywhere: account.list returns only open accounts and the app keeps no known-account list, so unlocking needs the account id typed by hand")
        }
    }

    // MARK: Flow 6: add alice by principal id, alice accepts, safety number, verified

    func test02_contactsAddAliceAndVerify() {
        flow("06-contacts") {
            try ensureReady()
            try openMore()
            try tap(element("more-contacts"), "Contacts in More")
            try tap(element("contacts-add"), "Add contact")
            let address = try require(element("contacts-add-address"), "account address field")
            address.tap(); address.typeText(config.alice.principal)
            try tap(element("contacts-add-send"), "Send contact request")
            snap("06-request-sent")
            // Peer side: the request from this run's phone account reaches alice.
            var request: [String: Any]?
            guard eventually(90, every: 3, {
                request = aliceContacts().first { ($0["display_name"] as? String) == RunSecrets.displayName }
                return request != nil
            }) else {
                throw FlowStop.fail("alice never saw a contact request from \(RunSecrets.displayName); phone shows: \(visibleFailure())")
            }
            guard let principal = request?["principal_id"] as? String,
                  let commitment = (request?["root_commitment"] as? String) ?? (request?["requester_id"] as? String) else {
                throw FlowStop.fail("alice's request row lacks ids: \(request ?? [:])")
            }
            let requestID = (request?["request_id"] as? String) ?? (request?["link_id"] as? String) ?? principal
            RunSecrets.phonePrincipal = principal; RunSecrets.phoneCommitment = commitment
            control.log("alice sees request \(requestID) state=\(request?["state"] ?? "?") from \(principal)")
            if (request?["state"] as? String) != "accepted" {
                var accepted = control.rf("alice", ["contact", "accept", "--principal", principal])
                if accepted.exit != 0, let link = request?["link_id"] as? String {
                    control.log("accept by principal failed (exit \(accepted.exit)): \(accepted.stderr.suffix(300)); trying --link")
                    accepted = control.rf("alice", ["contact", "accept", "--link", link])
                }
                guard accepted.exit == 0 else { throw FlowStop.blocked("alice: rf contact accept failed (exit \(accepted.exit)): \(accepted.stderr.suffix(400))") }
            }
            // Phone: alice becomes a contact.
            let row = element(config.alice.principal)
            guard eventually(90, every: 3, {
                if row.exists { return true }
                element("contacts-header").buttons["Refresh"].firstMatch.tapIfExists(); return false
            }) else { throw FlowStop.fail("alice did not appear in the phone's contacts after she accepted: \(visibleFailure())") }
            snap("06-contact-listed")
            try tap(row, "alice contact row")
            try tap(element("contact-safety"), "View safety number")
            let number = try require(element("contacts-safety-number"), "safety number", timeout: 30)
            let phoneDigits = number.label.filter(\.isNumber)
            let peer = control.rf("alice", ["contact", "safety-number", "--contact", commitment])
            let peerText = (peer.json.map { "\($0)" } ?? peer.stdout)
            let peerDigits = String(describing: peer.json?["safety_number"] ?? peerText).filter(\.isNumber)
            snap("06-safety-number")
            guard !phoneDigits.isEmpty else { throw FlowStop.fail("safety number has no digits") }
            let matches = peer.exit == 0 && peerDigits.contains(phoneDigits)
            try tap(element("contact-verify"), "I compared this number")
            try tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Confirm:'")).firstMatch, "verify confirmation")
            guard eventually(30, { self.text(containing: "You marked this number verified").exists || self.text(containing: "Identity verified").exists }) else {
                throw FlowStop.fail("contact not shown as verified after confirming: \(visibleFailure())")
            }
            guard matches else {
                throw FlowStop.fail("safety number on the phone (\(phoneDigits.count) digits) does not match alice's (exit \(peer.exit)): phone \(phoneDigits) peer \(peerDigits.prefix(80))")
            }
            return "request by principal id reached alice (\(requestID)); accepted with rf; alice listed; safety number equals alice's; marked verified"
        }
    }

    // MARK: Flow 3: the conversation list shows the real direct conversation with alice

    func test03_conversationListShowsAlice() {
        flow("03-conversations") {
            try ensureReady()
            guard let phone = RunSecrets.phoneCommitment else { throw FlowStop.blocked("needs flow 6 (contact with alice)") }
            let derived = control.post("dm-conversation", json: ["first": phone, "second": config.alice.commitment])["conversation"] as? String ?? ""
            guard derived.hasPrefix("dm:") else { throw FlowStop.fail("could not derive the dm conversation id") }
            RunSecrets.aliceConversation = derived
            try openTab("messages")
            let row = element(derived)
            if !row.waitForExistence(timeout: 10) {
                // A conversation row may need a first message; alice sends one.
                let sent = control.rf("alice", ["conversation", "send", "--conversation", derived, "--text", "realrun hello from alice"])
                control.log("alice conversation send exit \(sent.exit) \(sent.stderr.suffix(300))")
            }
            guard row.waitForExistence(timeout: 60) else {
                let ids = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'dm:'")).allElementsBoundByIndex.map(\.identifier)
                throw FlowStop.fail("no conversation row with the derived id \(derived); dm rows shown: \(ids)")
            }
            snap("03-conversation-row")
            return "Messages lists the direct conversation with alice under the client-derived id \(derived)"
        }
    }

    // MARK: Flow 4: direct chat with alice both ways

    func test04_directChatWithAlice() {
        flow("04-direct-chat") {
            try ensureReady()
            guard let conversation = RunSecrets.aliceConversation else { throw FlowStop.blocked("needs flow 3 (conversation id)") }
            try openConversation(conversation)
            var notes: [String] = []
            // Send from the phone; alice reads it in the same conversation id.
            let first = "rr-phone-" + token()
            try send(first)
            try require(text(containing: first), "own message bubble", timeout: 30)
            guard eventually(90, every: 3, { self.aliceMessage(conversation, containing: first) != nil }) else {
                throw FlowStop.fail("alice did not receive the phone's message in \(conversation): \(visibleFailure())")
            }
            snap("04-sent")
            // Receive live from alice, without a manual refresh.
            let incoming = "rr-alice-" + token()
            let sent = control.rf("alice", ["conversation", "send", "--conversation", conversation, "--text", incoming])
            guard sent.exit == 0 else { throw FlowStop.blocked("alice: rf conversation send failed (exit \(sent.exit)): \(sent.stderr.suffix(300))") }
            var liveFailure: String?
            if !text(containing: incoming).waitForExistence(timeout: 60) {
                // Delivered but not shown live? Reopen the conversation and look again.
                back(); try openConversation(conversation)
                liveFailure = text(containing: incoming).waitForExistence(timeout: 20)
                    ? "alice's message was not shown live in the open chat within 60 s; it is there after reopening the conversation"
                    : "alice's message never appeared on the phone, even after reopening"
                guard text(containing: incoming).exists else { throw FlowStop.fail(liveFailure!) }
            }
            snap("04-received")
            // Typing from alice, if the phone shows it.
            let typing = control.rf("alice", ["conversation", "typing", "start", "--conversation", conversation])
            notes.append(typing.exit == 0 ? (text(containing: "Typing").waitForExistence(timeout: 10) ? "typing shown" : "typing not shown within 10 s")
                                          : "typing start refused on alice (exit \(typing.exit))")
            // Reply to alice's message.
            let reply = "rr-reply-" + token()
            try openActions(on: text(containing: incoming), "alice's message")
            try tap(button("Reply"), "Reply action")
            try send(reply)
            guard eventually(90, every: 3, { self.aliceMessage(conversation, containing: reply) != nil }) else { throw FlowStop.fail("alice did not receive the reply") }
            if let row = aliceMessage(conversation, containing: reply) {
                let message = (row["content"] as? [String: Any])?["message"] as? [String: Any] ?? [:]
                notes.append(message.keys.contains { $0.lowercased().contains("reply") } || row.keys.contains { $0.lowercased().contains("reply") }
                             ? "reply reference present on alice" : "reply arrived without a reply reference on alice (keys: \(message.keys.sorted()))")
            }
            // Edit the first message.
            let edited = first + "-edited"
            try openActions(on: text(containing: first), "own first message")
            try tap(button("Edit"), "Edit action")
            let input = try require(element("chat-composer-input"), "composer input")
            input.replaceText(edited)
            try tap(element("chat-composer-send"), "send edit")
            guard eventually(90, every: 3, { (self.aliceMessage(conversation, containing: edited)?["edited"] as? Bool) == true }) else {
                throw FlowStop.fail("alice did not see the edit (text and edited flag)")
            }
            try require(text(containing: edited), "edited bubble on the phone", timeout: 30)
            snap("04-edited")
            // Erase the reply for everyone.
            try openActions(on: text(containing: reply), "own reply")
            try tap(button("Delete for everyone"), "Delete for everyone action")
            try tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Confirm:'")).firstMatch, "delete confirmation")
            guard eventually(90, every: 3, {
                let rows = self.aliceMessages(conversation)
                return !rows.contains { self.messageText($0).contains(reply) } || rows.contains { self.messageText($0).contains(reply) && !($0["erasure"] is NSNull) && $0["erasure"] != nil }
            }) else { throw FlowStop.fail("alice still shows the reply after delete for everyone") }
            snap("04-erased")
            // Receipts as alice sees them for the phone's first message (the phone sends delivered and read receipts).
            if let row = aliceMessage(conversation, containing: first) {
                let receipts = (row["receipts"] as? [[String: Any]] ?? []).map { "\($0["state"] ?? "?")" }
                notes.append("receipts on alice for the phone's message: \(receipts.isEmpty ? "none" : receipts.joined(separator: ","))")
            }
            if let liveFailure { throw FlowStop.fail(liveFailure + "; otherwise: send, reply, edit and erase for everyone reached the peer in \(conversation); " + notes.joined(separator: "; ")) }
            return "send, live receive, reply, edit and erase for everyone all reached the peer in \(conversation); " + notes.joined(separator: "; ")
        }
    }

    // MARK: Flow 7, media M1: receive an image and a file from alice, view them, send an image

    func test04m_mediaReceiveAndSend() {
        flow("07-media") {
            try ensureReady()
            guard let conversation = RunSecrets.aliceConversation, let phoneCommitment = RunSecrets.phoneCommitment else {
                throw FlowStop.blocked("needs flows 3 and 6 (conversation with alice)")
            }
            // The phone's device id, from Settings, My devices; alice's attachment send addresses it directly.
            try openMore()
            try tap(element("more-settings"), "Settings in More")
            try tap(element("settings-devices"), "My devices")
            let deviceRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'device-'")).firstMatch
            try require(deviceRow, "this device's row", timeout: 30)
            let phoneDevice = String(deviceRow.identifier.prefix { $0 != " " })
            let targetJSON = try JSONSerialization.data(withJSONObject: [phoneCommitment, phoneDevice])
            let target = "root~" + targetJSON.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let peers = control.get("config")["peers"] as? [String: [String: Any]] ?? [:]
            guard let aliceDevice = peers["alice"]?["device_id"] as? String else { throw FlowStop.fail("peer config lacks alice's device id") }
            var notes: [String] = []
            var receiveBlocked: String?
            for (name, kind, size) in [("rr-image.png", "png", 60000), ("rr-file.txt", "text", 3000)] {
                let made = control.post("make-file", json: ["name": name, "kind": kind, "size": size])
                guard let path = made["path"] as? String else { throw FlowStop.fail("could not create \(name)") }
                let caption = "rr-media-\(name)-" + token()
                let id = "rr-msg-" + token()
                let sent = control.rf("alice", ["dm", "send", "--conversation", conversation, "--message", id, "--envelope", id,
                                                "--source-principal", config.alice.principal, "--sender", aliceDevice, "--recipient-device", phoneDevice,
                                                "--recipient-principal-commitment", phoneCommitment, "--target", target, "--body", caption, "--attach", path], timeout: 120)
                guard sent.exit == 0 else { receiveBlocked = "alice: rf dm send --attach \(name) failed (exit \(sent.exit)): \(sent.stderr.suffix(300))"; break }
                notes.append("alice sent \(name)")
                RunSecrets.mediaCaptions.append(caption)
            }
            try ensureReady()
            try openConversation(conversation)
            if receiveBlocked == nil {
            for caption in RunSecrets.mediaCaptions {
                guard text(containing: caption).waitForExistence(timeout: 90) else { throw FlowStop.fail("message \(caption) from alice did not appear") }
            }
            let file = app.buttons.matching(NSPredicate(format: "label CONTAINS 'rr-file.txt'")).firstMatch
            let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
            guard file.waitForExistence(timeout: 30) else { throw FlowStop.fail("the file card for rr-file.txt is not shown") }
            guard photo.waitForExistence(timeout: 30) else { throw FlowStop.fail("the photo attachment is not shown") }
            notes.append("phone shows the photo (\(photo.label)) and the file card (\(file.label))")
            snap("07-received")
            photo.tap()
            Thread.sleep(forTimeInterval: 5)
            snap("07-photo-tapped")
            notes.append("after tapping the photo: \(photo.exists ? photo.label : "preview opened")")
            if app.buttons["Close"].firstMatch.exists { app.buttons["Close"].firstMatch.tap() } else { back() }
            }
            // Send the test image from the photo library.
            if !element("chat-composer-input").exists { try openConversation(conversation) }
            try tap(element("chat-composer-attach"), "attach control")
            try tap(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Photos'")).firstMatch, "Photos in the attach sheet")
            let firstPhoto = app.images.firstMatch
            guard firstPhoto.waitForExistence(timeout: 20) else { throw FlowStop.blocked("the system photo picker exposed no images to the UI test; \(([receiveBlocked].compactMap { $0 } + notes).joined(separator: "; "))") }
            firstPhoto.tap()
            let add = app.buttons.matching(NSPredicate(format: "label == 'Add' OR label == 'Done'")).firstMatch
            if add.waitForExistence(timeout: 5) { add.tap() }
            try tap(element("media-draft-send").exists ? element("media-draft-send") : button("Send"), "send the media draft", timeout: 30)
            let expected = ProcessInfo.processInfo.environment["RF_PHONE_PHOTO"].map { control.post("file-info", json: ["path": $0])["sha256"] as? String } ?? nil
            var imported: [String: Any] = [:]
            guard eventually(120, every: 4, {
                guard let row = self.aliceMessages(conversation).last(where: { ($0["is_own"] as? Bool) == false && !((($0["content"] as? [String: Any])?["message"] as? [String: Any])?["media"] as? [Any] ?? []).isEmpty }),
                      let id = row["id"] as? String, !RunSecrets.mediaCaptions.contains(self.messageText(row)) else { return false }
                let out = (self.control.post("fresh-path", json: ["name": "alice-import.bin"])["path"] as? String) ?? ""
                let result = self.control.rf("alice", ["attachment", "import", "--message", id, "--index", "0", "--output", out], timeout: 120)
                guard result.exit == 0 else { return false }
                imported = self.control.post("file-info", json: ["path": out]); return true
            }) else { throw FlowStop.fail("alice never received an importable image from the phone; \(([receiveBlocked].compactMap { $0 } + notes).joined(separator: "; "))") }
            let same = expected != nil && (imported["sha256"] as? String) == expected
            notes.append(same ? "alice imported identical bytes of the phone's image" : "alice imported \(imported["size"] ?? "?") bytes; sha256 differs from the photo-library file (the app or Photos re-encodes)")
            guard same else { throw FlowStop.fail(notes.joined(separator: "; ")) }
            if let receiveBlocked { throw FlowStop.blocked("receive: " + receiveBlocked + "; send: " + notes.joined(separator: "; ")) }
            return notes.joined(separator: "; ")
        }
    }

    func openConversation(_ id: String) throws {
        try openTab("messages")
        try tap(element(id), "conversation row \(id)", timeout: 30)
        try require(element("chat-composer-input"), "chat composer", timeout: 20)
    }
    func send(_ text: String) throws {
        let input = try require(element("chat-composer-input"), "composer input")
        input.tap(); input.typeText(text)
        try tap(element("chat-composer-send"), "send button")
    }
    func openActions(on bubble: XCUIElement, _ what: String) throws {
        try require(bubble, what, timeout: 20)
        bubble.press(forDuration: 1.0)
        guard element("chat-actions").waitForExistence(timeout: 5) || button("Reply").waitForExistence(timeout: 3) else {
            throw FlowStop.fail("message actions did not open on \(what)")
        }
    }
    func token() -> String { String(UUID().uuidString.prefix(8)).lowercased() }
    func aliceMessages(_ conversation: String) -> [[String: Any]] {
        control.rf("alice", ["dm", "read", "--conversation", conversation, "--limit", "100"]).json?["messages"] as? [[String: Any]] ?? []
    }
    func messageText(_ row: [String: Any]) -> String {
        ((row["content"] as? [String: Any])?["message"] as? [String: Any])?["text"] as? String ?? (row["text"] as? String ?? "")
    }
    func aliceMessage(_ conversation: String, containing fragment: String) -> [String: Any]? {
        aliceMessages(conversation).first { messageText($0).contains(fragment) }
    }

    /// Brings the app to an unlocked shell; FlowStop when flow 1 never produced an account.
    func ensureReady() throws {
        dismissPrompts()
        // Leave any pushed screen first; pushed screens hide the tab bar.
        for _ in 0..<6 where !element("tab-messages").exists { back(); Thread.sleep(forTimeInterval: 0.6) }
        try unlockIfNeeded()
        dismissPrompts()
        for _ in 0..<6 where !element("tab-messages").exists { back(); Thread.sleep(forTimeInterval: 0.6) }
        guard element("tab-messages").waitForExistence(timeout: 20) else { throw FlowStop.blocked("no unlocked account (flow 1 did not complete)") }
    }

    func aliceContacts() -> [[String: Any]] {
        control.rf("alice", ["contact", "list"]).json?["contacts"] as? [[String: Any]] ?? []
    }

    func lockAccount() throws {
        try openMore()
        try tap(element("more-settings"), "Settings in More")
        try tap(element("settings-account"), "Account and security")
        try tap(element("settings-lock"), "Lock account")
        // A locked account is no longer active: Messages offers the account chooser instead of content.
        try openTab("messages")
        try require(element("shell-accounts"), "account chooser on Messages after lock", timeout: 20)
    }
}
