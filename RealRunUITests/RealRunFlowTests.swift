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
            // Debug builds started with -RFRealRunPhraseAccess expose the words as the display's accessibility
            // value (never in release builds); the words stay in this process and are never logged.
            var words: [String] = []
            guard eventually(10, every: 0.5, {
                words = (phrase.value as? String ?? "").split(separator: " ").map(String.init)
                return words.count == 24
            }) else { throw FlowStop.fail("the recovery phrase display exposed \(words.count) words to the debug accessibility seam, not 24") }
            guard words.allSatisfy({ (3...8).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isLetter } }) else {
                throw FlowStop.fail("the recovery phrase display exposed malformed words (lengths only: \(words.map(\.count)))")
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
            // Secret fields present as secure text fields to accessibility and automation, without their text.
            guard app.secureTextFields.matching(identifier: "secure-entry-passphrase").firstMatch.exists,
                  app.secureTextFields.matching(identifier: "secure-entry-word1").firstMatch.exists else {
                throw FlowStop.fail("the account code or recovery word fields are not exposed as secure text fields")
            }
            code.tap(); code.typeText(RunSecrets.accountCode)
            let repeatCode = try require(element("secure-entry-passphraseRepeat"), "repeat account code")
            repeatCode.tap(); repeatCode.typeText(RunSecrets.accountCode)
            try tap(element("secure-entry-submit"), "Confirm once")
            let connected = text(containing: "Connected")
            let pending = text(containing: "Network connection has not been confirmed")
            let connecting = text(containing: "Connecting to the network")
            guard eventually(90, { connected.exists || pending.exists || connecting.exists }) else { throw FlowStop.fail("account completion did not appear: \(visibleFailure())") }
            let firstShown = connected.exists ? "Connected" : connecting.exists ? "Connecting" : "not confirmed"
            // The completion step follows the SDK's networking state and turns to Connected when it is live.
            _ = eventually(90, { connected.exists || pending.exists })
            let networking = connected.exists ? "completion showed \(firstShown), then Connected (SDK networking live)" : "completion showed \(firstShown) and ended not confirmed after 90 s"
            let shownID = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'account-'")).firstMatch.label
            RunSecrets.accountID = String(shownID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
            control.log("phone account \(RunSecrets.accountID ?? "?") named \(RunSecrets.displayName)")
            snap("01-complete")
            try tap(button("Continue"), "Continue after completion")
            try require(element("app-shell"), "app shell", timeout: 30)
            // Lock through Settings: the locked Messages tab offers the account by name; unlock asks only for the code.
            try lockAccount()
            guard knownAccountUnlock().waitForExistence(timeout: 20) else { throw FlowStop.fail("after lock the account is not offered by name: \(visibleFailure())") }
            snap("01-locked")
            // Accounts sheet: tapping the locked account's row opens its unlock step.
            try tap(element("shell-accounts"), "Accounts on the locked Messages tab")
            try tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'account-account-'")).firstMatch, "the locked account's row in Accounts")
            try require(element("a02-known-account"), "unlock step after tapping the locked account's row", timeout: 15)
            try unlockIfNeeded()
            try require(element("tab-messages"), "Messages tab after unlock", timeout: 30)
            guard !element("secure-entry-passphrase").waitForExistence(timeout: 3) else { throw FlowStop.fail("unlock form still visible after submit: \(visibleFailure())") }
            // The Messages header names the account by its display name, not its id.
            try openTab("messages")
            guard text(containing: RunSecrets.displayName).waitForExistence(timeout: 20) else { throw FlowStop.fail("Messages header does not show the display name: \(visibleFailure())") }
            if let id = RunSecrets.accountID, !id.isEmpty, text(containing: id).exists { throw FlowStop.fail("the raw account id is still shown on Messages") }
            snap("01-header-name")
            // Cold start: the account is offered again by name.
            app.terminate(); app.launch()
            guard knownAccountUnlock().waitForExistence(timeout: 30) || { try? openTab("messages"); return knownAccountUnlock().waitForExistence(timeout: 20) }() else {
                throw FlowStop.fail("after a cold start the account is not offered by name: \(visibleFailure())")
            }
            snap("01-cold-start")
            try unlockIfNeeded()
            try require(element("tab-messages"), "Messages tab after the cold-start unlock", timeout: 30)
            return "node \(config.origin) accepted as typed, fingerprint matched, 24 words confirmed, code set, \(networking); secret fields are secure text fields; the locked account's row in Accounts opens its unlock step; after lock and after a cold start the locked tab offers \(RunSecrets.displayName) by name and the unlock step asks only for the code; Messages shows the display name"
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
            // The row is titled with alice's contact name, not the raw dm id.
            let titled = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", config.alice.displayName)).firstMatch
            guard titled.waitForExistence(timeout: 30) else {
                throw FlowStop.fail("the direct conversation row is not titled with alice's name \(config.alice.displayName): \(visibleFailure())")
            }
            return "Messages lists the direct conversation with alice under the client-derived id \(derived), titled with her contact name"
        }
    }

    // MARK: Flow 4: direct chat with alice both ways

    func test04_directChatWithAlice() {
        flow("04-direct-chat") {
            try ensureReady()
            guard let conversation = RunSecrets.aliceConversation else { throw FlowStop.blocked("needs flow 3 (conversation id)") }
            try openConversation(conversation)
            var notes: [String] = []
            // The chat header names alice, not the dm id.
            guard element(conversation).label.contains(config.alice.displayName) || text(containing: config.alice.displayName).exists else {
                throw FlowStop.fail("the chat header does not show alice's name: \(visibleFailure())")
            }
            // Send from the phone; alice reads it in the same conversation id.
            let first = "rr-phone-" + token()
            try send(first)
            try require(text(containing: first), "own message bubble", timeout: 30)
            guard eventually(90, every: 3, { self.aliceMessage(conversation, containing: first) != nil }) else {
                throw FlowStop.fail("alice did not receive the phone's message in \(conversation): \(visibleFailure())")
            }
            snap("04-sent")
            // Accessibility: the attach control is a labelled button and the own bubble states its receipt.
            let attach = app.buttons["chat-composer-attach"].firstMatch
            guard attach.exists, attach.label == "Attach" else { throw FlowStop.fail("the attach control is not a button labelled Attach (\(attach.debugDescription.prefix(200)))") }
            let ownBubble = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'message-own' AND label CONTAINS %@", first)).firstMatch
            let receipt = (ownBubble.value as? String ?? "") + " " + ownBubble.label
            guard ["Sent", "Delivered", "Read"].contains(where: { receipt.contains($0) }) else { throw FlowStop.fail("the own bubble does not state its receipt (\(receipt.prefix(160)))") }
            notes.append("attach is a labelled button; own bubble receipt reads \(["Read", "Delivered", "Sent"].first { receipt.contains($0) } ?? "?")")
            // Receive live from alice, without a manual refresh.
            let incoming = "rr-alice-" + token()
            let sent = control.rf("alice", ["conversation", "send", "--conversation", conversation, "--text", incoming])
            guard sent.exit == 0 else { throw FlowStop.blocked("alice: rf conversation send failed (exit \(sent.exit)): \(sent.stderr.suffix(300))") }
            var liveFailure: String?
            if !text(containing: incoming).waitForExistence(timeout: 60) {
                // Delivered but not shown live? Reopen the conversation and look again.
                back(); try openConversation(conversation)
                control.post("device-log", json: ["name": "device-events-live-receive", "minutes": 4])
                liveFailure = text(containing: incoming).waitForExistence(timeout: 20)
                    ? "alice's message was not shown live in the open chat within 60 s; it is there after reopening the conversation"
                    : "alice's message never appeared on the phone, even after reopening"
                guard text(containing: incoming).exists else { throw FlowStop.fail(liveFailure!) }
            }
            snap("04-received")
            // The phone marks alice's message read (message.receipt.read): does alice see a read receipt?
            var aliceReceipts = "none"
            _ = eventually(60, every: 4, {
                let states = (self.aliceMessage(conversation, containing: incoming)?["receipts"] as? [[String: Any]] ?? []).map { "\($0["state"] ?? "?")" }
                aliceReceipts = states.isEmpty ? "none" : states.joined(separator: ",")
                return states.contains("read")
            })
            notes.append("receipts alice sees on her message after the phone displayed it: \(aliceReceipts)")
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
            // The own reply sits on the own (trailing) side like any own message.
            let replyBubble = try require(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", reply)).firstMatch, "own reply bubble", timeout: 30)
            guard replyBubble.identifier == "message-own" else { throw FlowStop.fail("own reply is drawn on the incoming side (\(replyBubble.identifier))") }
            notes.append("own reply drawn on the own side")
            if let row = aliceMessage(conversation, containing: reply) {
                let message = (row["content"] as? [String: Any])?["message"] as? [String: Any] ?? [:]
                notes.append(message.keys.contains { $0.lowercased().contains("reply") } || row.keys.contains { $0.lowercased().contains("reply") }
                             ? "reply reference present on alice" : "reply arrived without a reply reference on alice (keys: \(message.keys.sorted()))")
            }
            // A long press on an own bubble opens the app's actions; "Select text" shows the text selectable.
            try openActions(on: text(containing: first), "own first message")
            try tap(button("Select text"), "Select text action")
            guard element("chat-select-text").waitForExistence(timeout: 10) else { throw FlowStop.fail("Select text did not show the message text") }
            snap("04-select-text")
            try tap(element("chat-select-text-header").buttons["Back"].firstMatch, "close the text selection")
            notes.append("long press opens the message actions on own and incoming bubbles; Select text works")
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
            // Hand the phone's own contact card to alice, so her record of the phone names its home node
            // (a principal lookup alone left her with "no home node is pinned for this contact").
            var notes: [String] = []
            try openMore()
            try tap(element("more-contacts"), "Contacts in More")
            try tap(element("contacts-my-card"), "My contact card")
            let cardText = try require(element("contacts-my-card-text"), "contact card text", timeout: 30)
            snap("07-my-card")
            let shownCard = cardText.label + " " + (cardText.value as? String ?? "")
            guard let range = shownCard.range(of: "ramflux-card:v3:[A-Za-z0-9_=.-]+", options: .regularExpression) else {
                throw FlowStop.fail("My contact card shows no card text: \(visibleFailure())")
            }
            let added = control.rf("alice", ["contact", "add", "--card", String(shownCard[range])])
            notes.append(added.exit == 0 ? "alice added the phone's contact card" : "alice: rf contact add --card exit \(added.exit): \(added.stderr.suffix(200))")
            try ensureReady()
            notes.append(try addPeerCard(config.alice))
            try ensureReady()
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
            // rf dm send --attach declares the image's media type, so the image arrives as a photo (shown inline
            // and downloaded by policy for a contact) and the text file as a file card.
            if let caption = RunSecrets.mediaCaptions.first(where: { $0.contains("rr-image.png") }) {
                let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo' AND label CONTAINS %@", caption)).firstMatch
                guard photo.waitForExistence(timeout: 60) else { throw FlowStop.fail("the image rr-image.png is not shown as a photo") }
                notes.append("phone received rr-image.png as a photo (\(photo.label.components(separatedBy: ", ").prefix(2).joined(separator: ", ")))")
            }
            for name in ["rr-file.txt"] {
                let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND NOT (identifier BEGINSWITH 'message-')", name)).firstMatch
                guard card.waitForExistence(timeout: 30) else { throw FlowStop.fail("the attachment \(name) is not shown") }
                try tap(card, "download \(name)")
                guard eventually(90, every: 2, { !card.exists || !card.label.contains("Tap to download") && !card.label.contains("Downloading") }) else {
                    throw FlowStop.fail("\(name) did not finish downloading: \(card.label)")
                }
                notes.append("phone received and downloaded \(name) (\(card.exists ? card.label : "opened"))")
                Thread.sleep(forTimeInterval: 2)
                if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
                else if app.buttons["Close"].firstMatch.exists { app.buttons["Close"].firstMatch.tap() }
                if !element("chat-composer-input").exists { back() }
            }
            snap("07-received")
            }
            // Send the test image from the photo library.
            if !element("chat-composer-input").exists { try openConversation(conversation) }
            guard try sendLibraryPhoto() else { throw FlowStop.blocked("the system photo picker exposed no images to the UI test; \(([receiveBlocked].compactMap { $0 } + notes).joined(separator: "; "))") }
            // The photo-library image the phone sends, as the harness decodes it (format and pixel size).
            let source = ProcessInfo.processInfo.environment["RF_PHONE_PHOTO"].map { control.post("file-info", json: ["path": $0])["image"] as? [String: Any] } ?? nil
            var imported: [String: Any] = [:]
            guard eventually(120, every: 4, {
                guard let row = self.aliceMessages(conversation).last(where: { ($0["is_own"] as? Bool) == false && !((($0["content"] as? [String: Any])?["message"] as? [String: Any])?["media"] as? [Any] ?? []).isEmpty }),
                      let id = row["id"] as? String, !RunSecrets.mediaCaptions.contains(self.messageText(row)) else { return false }
                let out = (self.control.post("fresh-path", json: ["name": "alice-import.bin"])["path"] as? String) ?? ""
                let result = self.control.rf("alice", ["attachment", "import", "--message", id, "--index", "0", "--output", out], timeout: 120)
                guard result.exit == 0 else { return false }
                imported = self.control.post("file-info", json: ["path": out]); return true
            }) else {
                control.post("device-log", json: ["name": "device-events-media-send", "minutes": 5])
                let detail = ([receiveBlocked].compactMap { $0 } + notes).joined(separator: "; ")
                let offline = text(containing: "messages will be sent when the connection returns").exists
                if retryShown() && !offline {
                    // The SDK refused the send; its typed cause is in device-events-media-send.log.
                    snap("07-not-sent-retry")
                    throw FlowStop.fail("receive works (\(detail)); phone-to-alice image send was refused by the SDK, see device-events-media-send.log for the typed cause; the entry reads not sent with a Retry and no offline banner")
                }
                throw FlowStop.fail("alice never received an importable image from the phone; \(detail)")
            }
            // A photo is sent in compressed mode (media design): re-encoded as JPEG, or PNG when it has alpha,
            // with the long edge capped at 2,560 px. Alice must receive a decodable image of that kind and size.
            guard let source, let width = source["width"] as? Int, let height = source["height"] as? Int else {
                throw FlowStop.fail("the harness could not decode the photo-library image; \(notes.joined(separator: "; "))")
            }
            let scale = min(1.0, 2560.0 / Double(max(width, height)))
            let expectedSize = (Int((Double(width) * scale).rounded()), Int((Double(height) * scale).rounded()))
            let received = imported["image"] as? [String: Any]
            let format = received?["format"] as? String ?? "none"
            let size = (received?["width"] as? Int ?? 0, received?["height"] as? Int ?? 0)
            let matches = ["jpeg", "png"].contains(format) && size == expectedSize
            notes.append("alice imported a decodable \(format) image of \(size.0)x\(size.1) px (\(imported["size"] ?? "?") bytes) for the phone's \(width)x\(height) px photo; expected JPEG or PNG at \(expectedSize.0)x\(expectedSize.1) px")
            guard matches else { throw FlowStop.fail(notes.joined(separator: "; ")) }
            if let receiveBlocked { throw FlowStop.blocked("receive: " + receiveBlocked + "; send: " + notes.joined(separator: "; ")) }
            return notes.joined(separator: "; ")
        }
    }

    // MARK: Flow 5: groups with alice and bob

    func test05_groupsWithAliceAndBob() {
        flow("05-groups") {
            try ensureReady()
            guard RunSecrets.phoneCommitment != nil else { throw FlowStop.blocked("needs flow 6 (contact with alice)") }
            var notes: [String] = []
            // Bob becomes a second contact, the same way as alice.
            try addContact(config.bob)
            notes.append("bob added as a contact")
            try ensureReady()
            // Create the group from the phone.
            let name = "rr-group-" + token()
            try openTab("groups")
            if element("groups-empty-create").waitForExistence(timeout: 5) { try tap(element("groups-empty-create"), "Create group") }
            else { try tap(button("Create group"), "Create group in the Groups header") }
            let field = try require(textField("group-name"), "group name field")
            field.tap(); field.typeText(name)
            try tap(button("Review group creation"), "Review group creation")
            try confirmHost("group creation confirmation")
            // After creation the app opens the new group's conversation.
            let composer = element("chat-composer-input"), refused = text(containing: "could not be accepted")
            guard eventually(90, { composer.exists || refused.exists }) else { throw FlowStop.fail("group creation was not acknowledged: \(visibleFailure())") }
            if !composer.exists {
                control.post("device-log", json: ["name": "device-events-group-create", "minutes": 4])
                throw FlowStop.fail("the group was created but opening it failed: \(visibleFailure())")
            }
            snap("05-group-created")
            notes.append("group created; the app opened its conversation")
            back()
            // Detail, from the Groups list row.
            try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch, "the new group's row", timeout: 30)
            // Members: add alice and bob from the known contacts.
            try tap(button("Members and permissions"), "Members and permissions")
            for peer in [config.alice, config.bob] {
                let add = app.buttons.matching(NSPredicate(format: "label == %@", peer.displayName)).firstMatch
                try require(add, "add \(peer.name) to the group", timeout: 30)
                scrollIntoView(add)
                try tap(add, "add \(peer.name) to the group", timeout: 30)
                try confirmHost("member add confirmation for \(peer.name)")
                guard text(containing: peer.principal.replacingOccurrences(of: "principal-", with: "")).waitForExistence(timeout: 60) || text(containing: peer.principal).exists else {
                    throw FlowStop.fail("\(peer.name) is not listed as a member after the add: \(visibleFailure())")
                }
            }
            snap("05-group-members")
            notes.append("members list shows alice and bob")
            // The group as alice sees it: its group_id and conversation id.
            var group: [String: Any]?
            guard eventually(120, every: 4, {
                group = (self.control.rf("alice", ["group", "list"]).json?["groups"] as? [[String: Any]] ?? []).first { ($0["name"] as? String) == name || ($0["title"] as? String) == name }
                return group != nil
            }) else { throw FlowStop.fail("alice never listed the group \(name); \(notes.joined(separator: "; "))") }
            let groupID = group?["group_id"] as? String ?? ""
            let conversation = group?["conversation_id"] as? String ?? groupID
            notes.append("alice lists the group (group_id \(groupID), conversation \(conversation))")
            RunSecrets.groupName = name; RunSecrets.groupID = groupID; RunSecrets.groupConversation = conversation
            // Phone sends; alice and bob read it.
            back()
            if !button("Open group conversation").waitForExistence(timeout: 5) {
                try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch, "the group's row", timeout: 30)
            }
            try tap(button("Open group conversation"), "Open group conversation", timeout: 30)
            let fromPhone = "rr-gphone-" + token()
            try send(fromPhone)
            for peer in ["alice", "bob"] {
                guard eventually(120, every: 4, { self.groupTexts(peer, group: groupID, conversation: conversation).contains { $0.contains(fromPhone) } }) else {
                    throw FlowStop.fail("\(peer) did not receive the phone's group message; \(notes.joined(separator: "; "))")
                }
            }
            notes.append("alice and bob received the phone's group message")
            // Bob sends; the phone shows it.
            let peers = control.get("config")["peers"] as? [String: [String: Any]] ?? [:]
            let fromBob = "rr-gbob-" + token()
            let sent = control.rf("bob", ["group", "send", "--group", groupID, "--conversation", conversation, "--message", "rr-gmsg-" + token(),
                                          "--sender", peers["bob"]?["device_id"] as? String ?? "", "--body", fromBob], timeout: 120)
            guard sent.exit == 0 else { throw FlowStop.blocked("bob: rf group send failed (exit \(sent.exit)): \(sent.stderr.suffix(300)); \(notes.joined(separator: "; "))") }
            guard text(containing: fromBob).waitForExistence(timeout: 90) else { throw FlowStop.fail("bob's group message did not appear on the phone; \(notes.joined(separator: "; "))") }
            snap("05-group-chat")
            notes.append("bob's group message appeared on the phone")
            return notes.joined(separator: "; ")
        }
    }

    // MARK: Flow 5b: an image in the group

    func test05b_groupImage() {
        flow("05b-group-image") {
            try ensureReady()
            guard let name = RunSecrets.groupName, let groupID = RunSecrets.groupID, let conversation = RunSecrets.groupConversation else {
                throw FlowStop.blocked("needs flow 5 (a group with alice and bob)")
            }
            try openTab("groups")
            try tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch, "the group's row", timeout: 30)
            try tap(button("Open group conversation"), "Open group conversation", timeout: 30)
            try require(element("chat-composer-input"), "group chat composer", timeout: 20)
            guard try sendLibraryPhoto() else { throw FlowStop.blocked("the system photo picker exposed no images to the UI test") }
            snap("05b-image-sent")
            // Alice's group read lists a message with media from the phone.
            var found = false
            _ = eventually(120, every: 4, {
                let rows = self.control.rf("alice", ["group", "read", "--group", groupID, "--conversation", conversation]).json?["messages"] as? [[String: Any]] ?? []
                found = rows.contains { !((($0["content"] as? [String: Any])?["message"] as? [String: Any])?["media"] as? [Any] ?? []).isEmpty }
                return found
            })
            if found { return "the phone's image reached alice in the group (a message with media in \(conversation))" }
            control.post("device-log", json: ["name": "device-events-group-image", "minutes": 4])
            let offline = text(containing: "messages will be sent when the connection returns").exists
            if retryShown() && !offline {
                throw FlowStop.fail("the SDK refused the group image send, see device-events-group-image.log for the typed cause; the entry reads not sent with a Retry and no offline banner")
            }
            throw FlowStop.fail("alice did not receive the phone's group image within 120 s; \(offline ? "the chat shows the offline banner although the node is reachable" : "no not-sent entry with a Retry is shown") (device-events-group-image.log)")
        }
    }

    /// The not-sent media entry offers its retry (the media outbox's Retry button).
    func retryShown() -> Bool { app.buttons.matching(NSPredicate(format: "label == 'Retry'")).firstMatch.waitForExistence(timeout: 30) }

    /// Picks the first photo-library image and sends it from the open chat; false when the picker shows no images.
    func sendLibraryPhoto() throws -> Bool {
        try tap(element("chat-composer-attach"), "attach control")
        try tap(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Photos'")).firstMatch, "Photos in the attach sheet")
        // The picker may open with its "Private Access to Photos" note, whose icon is also an image: take the
        // first large, hittable thumbnail.
        guard app.images.firstMatch.waitForExistence(timeout: 20) else { return false }
        var thumbnail: XCUIElement?
        _ = eventually(10, every: 0.5, {
            thumbnail = self.app.images.allElementsBoundByIndex.first { $0.frame.width >= 80 && $0.frame.height >= 80 && $0.isHittable }
            return thumbnail != nil
        })
        guard let thumbnail else { return false }
        thumbnail.tap()
        let add = app.buttons.matching(NSPredicate(format: "label == 'Add' OR label == 'Done'")).firstMatch
        if add.waitForExistence(timeout: 5) { add.tap() }
        try tap(element("media-draft-send").exists ? element("media-draft-send") : button("Send"), "send the media draft", timeout: 30)
        return true
    }

    /// Adds `peer` as a contact by principal id and lets the peer accept with rf.
    func addContact(_ peer: RealRunConfig.Peer) throws {
        try openMore()
        try tap(element("more-contacts"), "Contacts in More")
        if element(peer.principal).waitForExistence(timeout: 5) { _ = try addPeerCard(peer); return }
        try tap(element("contacts-add"), "Add contact")
        let address = try require(element("contacts-add-address"), "account address field")
        address.tap(); address.typeText(peer.principal)
        try tap(element("contacts-add-send"), "Send contact request")
        var request: [String: Any]?
        guard eventually(90, every: 3, {
            request = (self.control.rf(peer.name, ["contact", "list"]).json?["contacts"] as? [[String: Any]] ?? []).first { ($0["display_name"] as? String) == RunSecrets.displayName }
            return request != nil
        }) else { throw FlowStop.fail("\(peer.name) never saw a contact request from \(RunSecrets.displayName)") }
        if (request?["state"] as? String) != "accepted", let principal = request?["principal_id"] as? String {
            let accepted = control.rf(peer.name, ["contact", "accept", "--principal", principal])
            guard accepted.exit == 0 else { throw FlowStop.blocked("\(peer.name): rf contact accept failed (exit \(accepted.exit)): \(accepted.stderr.suffix(300))") }
        }
        back()
        try tap(element("more-contacts"), "Contacts in More")
        guard eventually(90, every: 3, {
            if self.element(peer.principal).exists { return true }
            self.element("contacts-header").buttons["Refresh"].firstMatch.tapIfExists(); return false
        }) else { throw FlowStop.fail("\(peer.name) did not appear in the phone's contacts after accepting") }
        _ = try addPeerCard(peer)
    }
    /// Adds `peer`'s contact card on the phone for the accepted contact. Attachments need the contact's home
    /// node, which only its card pins; a contact known by principal id alone has none (requests R42, R44).
    func addPeerCard(_ peer: RealRunConfig.Peer) throws -> String {
        guard let card = control.rf(peer.name, ["contact", "card"]).json?["card"] as? String, card.hasPrefix("ramflux-card:") else {
            throw FlowStop.blocked("\(peer.name): rf contact card returned no card")
        }
        try ensureReady()
        try openMore()
        try tap(element("more-contacts"), "Contacts in More")
        try tap(element("contacts-add"), "Add contact")
        let address = try require(element("contacts-add-address"), "account address field")
        address.tap(); address.typeText(card)
        try tap(element("contacts-add-send"), "Add \(peer.name)'s contact card")
        Thread.sleep(forTimeInterval: 2)
        // The add is finished when the screen leaves the add form or its button is enabled again.
        let send = element("contacts-add-send")
        guard eventually(60, { !send.exists || send.isEnabled }) else { throw FlowStop.fail("adding \(peer.name)'s card did not finish: \(visibleFailure())") }
        let labels = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label)
        let failure = labels.first { $0.contains("could not") || $0.contains("refused") }
        // A card whose home is already pinned (an earlier run of this step) is refused as an existing contact.
        let pinned = labels.contains { $0.localizedCaseInsensitiveContains("already") }
        snap("card-\(peer.name)")
        back()
        if pinned { return "\(peer.name)'s card is already on the phone (home node pinned)" }
        if let failure { throw FlowStop.fail("the phone refused \(peer.name)'s contact card: \(failure)") }
        return "the phone added \(peer.name)'s contact card (home node pinned for attachments)"
    }
    func groupTexts(_ peer: String, group: String, conversation: String) -> [String] {
        let value = control.rf(peer, ["group", "read", "--group", group, "--conversation", conversation])
        let rows = value.json?["messages"] as? [[String: Any]] ?? []
        return rows.map(messageText) + [value.stdout]
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
        // A failed chat step can leave the message actions or the text selection sheet open.
        if element("chat-actions").exists { app.buttons["Cancel"].firstMatch.tapIfExists() }
        if element("chat-select-text").exists { element("chat-select-text-header").buttons["Back"].firstMatch.tapIfExists() }
        // Leave any pushed screen first; pushed screens hide the tab bar.
        closeLeftoverSheet()
        for _ in 0..<6 where !element("tab-messages").isHittable { back(); Thread.sleep(forTimeInterval: 0.6) }
        try unlockIfNeeded()
        dismissPrompts()
        for _ in 0..<6 where !element("tab-messages").isHittable { back(); Thread.sleep(forTimeInterval: 0.6) }
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
