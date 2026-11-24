// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest

/// Settings handed in by scripts/realrun.sh as `TEST_RUNNER_*` environment (the runner strips the prefix).
/// Without them the suite skips, so opening the RamfluxRealRun scheme by hand never fails on a missing node.
struct RealRunConfig {
    let control: URL
    let origin: String
    let operatorKey: String
    let fingerprint: String
    let alice: Peer
    let bob: Peer
    struct Peer { let name: String; let principal: String; let commitment: String; let displayName: String }

    static func load() throws -> RealRunConfig {
        let env = ProcessInfo.processInfo.environment
        func value(_ key: String) throws -> String {
            guard let text = env[key], !text.isEmpty else { throw XCTSkip("\(key) is not set; run scripts/realrun.sh") }
            return text
        }
        guard let control = URL(string: try value("RF_REALRUN_CONTROL")) else { throw XCTSkip("RF_REALRUN_CONTROL is not a URL") }
        func peer(_ name: String) throws -> Peer {
            let key = name.uppercased()
            return Peer(name: name, principal: try value("RF_PEER_\(key)_PRINCIPAL"), commitment: try value("RF_PEER_\(key)_COMMITMENT"),
                        displayName: try value("RF_PEER_\(key)_NAME"))
        }
        return RealRunConfig(control: control, origin: try value("RF_NODE_ORIGIN"), operatorKey: try value("RF_NODE_OPERATOR_KEY"),
                             fingerprint: try value("RF_NODE_FINGERPRINT"), alice: try peer("alice"), bob: try peer("bob"))
    }
}

/// Synchronous client of scripts/realrun/peer_control.py on the Mac's loopback.
struct PeerControl {
    let base: URL

    struct RFResult { let exit: Int; let json: [String: Any]?; let stdout: String; let stderr: String }

    @discardableResult
    func post(_ path: String, json: [String: Any]) -> [String: Any] {
        guard let body = try? JSONSerialization.data(withJSONObject: json) else { return [:] }
        return decode(send(path, body: body, type: "application/json"))
    }
    func get(_ path: String) -> [String: Any] {
        var request = URLRequest(url: base.appendingPathComponent(path)); request.timeoutInterval = 30
        return decode(perform(request))
    }
    func rf(_ peer: String, _ args: [String], timeout: Double = 60) -> RFResult {
        let value = post("rf", json: ["peer": peer, "args": args, "timeout": timeout])
        return RFResult(exit: value["exit"] as? Int ?? -1, json: value["json"] as? [String: Any],
                        stdout: value["stdout"] as? String ?? "", stderr: value["stderr"] as? String ?? (value["error"] as? String ?? "no reply"))
    }
    func log(_ line: String) { post("log", json: ["line": line]) }
    func record(_ flow: String, _ status: String, _ detail: String) { post("result", json: ["flow": flow, "status": status, "detail": detail]) }
    func screenshot(_ name: String, png: Data) { _ = send("screenshot/" + name, body: png, type: "image/png") }

    private func send(_ path: String, body: Data, type: String) -> Data? {
        var request = URLRequest(url: base.appendingPathComponent(path)); request.httpMethod = "POST"
        request.httpBody = body; request.setValue(type, forHTTPHeaderField: "Content-Type"); request.timeoutInterval = 200
        return perform(request)
    }
    private func perform(_ request: URLRequest) -> Data? {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in result = data; done.signal() }.resume()
        _ = done.wait(timeout: .now() + request.timeoutInterval + 5)
        return result
    }
    private func decode(_ data: Data?) -> [String: Any] {
        guard let data, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
}

/// A flow check that failed on purpose: the message becomes the FAIL or BLOCKED detail.
struct FlowStop: Error, CustomStringConvertible {
    let status: String
    let description: String
    static func fail(_ text: String) -> FlowStop { FlowStop(status: "FAIL", description: text) }
    static func blocked(_ text: String) -> FlowStop { FlowStop(status: "BLOCKED", description: text) }
}

/// Per-run values: a six-digit account code generated in memory, public ids and the backup archive
/// passphrase. scripts/realrun.sh may run the suite in several xcodebuild phases; between them these values
/// are handed to the loopback control server's memory (/run-state), never to a file or a log. The recovery
/// words are not handed over: they stay in this process.
enum RunSecrets {
    nonisolated(unsafe) static var accountCode: String = newCode()
    static func newCode() -> String { (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined() }
    nonisolated(unsafe) static var words: [String] = []
    nonisolated(unsafe) static var accountID: String?
    /// The phone account's public identifiers as alice sees them after the contact request (flow 6).
    nonisolated(unsafe) static var phonePrincipal: String?
    nonisolated(unsafe) static var phoneCommitment: String?
    /// The direct conversation id derived from both root commitments (the rf harness derivation).
    nonisolated(unsafe) static var aliceConversation: String?
    nonisolated(unsafe) static var mediaCaptions: [String] = []
    /// The group of flow 5 (name, group id and conversation as alice lists it).
    nonisolated(unsafe) static var groupName: String?
    nonisolated(unsafe) static var groupID: String?
    nonisolated(unsafe) static var groupConversation: String?
    /// The group of flow 5c (bob's group the phone joined through an invitation).
    nonisolated(unsafe) static var invitedGroupID: String?
    /// The backup archive passphrase of flow 14 (memory only), for the restore on a fresh install.
    nonisolated(unsafe) static var archivePassphrase: String?
    /// Unique per run so the peers can tell this run's phone account from earlier runs' accounts.
    nonisolated(unsafe) static var displayName = "Realrun " + String((0..<4).map { _ in "abcdefghjkmnpqrstuvwxyz".randomElement()! })

    static func load(from control: PeerControl) {
        let state = control.get("run-state")
        guard let code = state["accountCode"] as? String, let name = state["displayName"] as? String else { return }
        accountCode = code; displayName = name
        accountID = state["accountID"] as? String; phonePrincipal = state["phonePrincipal"] as? String
        phoneCommitment = state["phoneCommitment"] as? String; aliceConversation = state["aliceConversation"] as? String
        archivePassphrase = state["archivePassphrase"] as? String; mediaCaptions = state["mediaCaptions"] as? [String] ?? []
        groupName = state["groupName"] as? String; groupID = state["groupID"] as? String; groupConversation = state["groupConversation"] as? String
        invitedGroupID = state["invitedGroupID"] as? String
    }
    static func save(to control: PeerControl) {
        var state: [String: Any] = ["accountCode": accountCode, "displayName": displayName, "mediaCaptions": mediaCaptions]
        for (key, value) in [("accountID", accountID), ("phonePrincipal", phonePrincipal), ("phoneCommitment", phoneCommitment),
                             ("aliceConversation", aliceConversation), ("archivePassphrase", archivePassphrase),
                             ("groupName", groupName), ("groupID", groupID), ("groupConversation", groupConversation), ("invitedGroupID", invitedGroupID)] { if let value { state[key] = value } }
        control.post("run-state", json: state)
    }
}

extension XCUIElement {
    func tapIfExists() { if exists && isHittable { tap() } }
    @discardableResult
    func waitFor(_ timeout: TimeInterval = 20) -> Bool { waitForExistence(timeout: timeout) }

    /// Types into a field after clearing whatever it holds.
    func replaceText(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty, current != placeholderValue {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
