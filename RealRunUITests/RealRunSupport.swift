// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import XCTest
import Vision
import UIKit

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

/// Reads the recovery words drawn by the glyph view (it exposes no text to accessibility) with on-device
/// text recognition. The words stay in this process's memory only; they are never logged or attached.
enum PhraseReader {
    /// The glyph view lays the 24 words out in `rows` rows of height (H - pointSize) / rows, in one column,
    /// or two columns when the view is at least 20 points-sizes wide; each cell is recognised on its own.
    /// The visible band is the scroll view minus the pinned footer (`obstruction`). Each pass recognises the
    /// visible part of the view in one request and assigns every observation to its row (and column) by
    /// position; rows are accepted only when fully visible. Scrolls up until all 24 cells were read.
    static func words(in element: XCUIElement, scroll: XCUIElement, obstruction: XCUIElement, pointSize: CGFloat = 17,
                      progress: (String) -> Void = { _ in }) throws -> [String] {
        var result = [String?](repeating: nil, count: 24)
        for pass in 0..<8 {
            guard let image = XCUIScreen.main.screenshot().image.cgImage else { throw FlowStop.fail("screen has no image") }
            let screen = XCUIApplication().frame
            let scale = CGFloat(image.width) / max(screen.width, 1)
            let frame = element.frame
            let columns = frame.width >= pointSize * 20 ? 2 : 1
            let rows = 24 / columns
            let line = (frame.height - pointSize) / CGFloat(rows)
            let top = max(scroll.frame.minY, frame.minY)
            let bottom = min(scroll.frame.maxY, obstruction.exists ? obstruction.frame.minY : .greatestFiniteMagnitude, frame.maxY)
            guard bottom - top > line else { progress("pass \(pass): no visible band"); break }
            let band = CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
            let pixels = CGRect(x: band.minX * scale, y: band.minY * scale, width: band.width * scale, height: band.height * scale).integral
            guard let crop = image.cropping(to: pixels) else { throw FlowStop.fail("phrase band outside the screen image") }
            var cells = [Int: [(CGFloat, String)]]()
            for (box, text) in try recognise(crop) {
                // Vision boxes are normalised with the origin at the bottom left.
                let midY = band.minY + (1 - box.midY) * band.height
                let minX = band.minX + box.minX * band.width
                let row = Int(((midY - frame.minY) / line).rounded(.down))
                let column = columns == 2 && minX >= frame.minX + frame.width / 2 - pointSize ? 1 : 0
                guard (0..<rows).contains(row) else { continue }
                let cellTop = frame.minY + CGFloat(row) * line, cellBottom = cellTop + line
                guard cellTop >= top, cellBottom <= bottom else { continue }
                cells[column * rows + row, default: []].append((minX, text))
            }
            for (index, parts) in cells where result[index] == nil {
                // A cell read as nothing (a glyph the recogniser dropped) stays unread for the next pass.
                let word = parts.sorted { $0.0 < $1.0 }.map(\.1).joined().lowercased().filter { $0.isLetter && $0.isASCII }
                if (3...8).contains(word.count) { result[index] = word }
            }
            progress("pass \(pass): \(result.compactMap { $0 }.count) of 24 cells read")
            if !result.contains(where: { $0 == nil }) { break }
            // When every unread cell lies above what this pass saw, scroll back up to read it again.
            let unread = result.indices.filter { result[$0] == nil }
            if let seen = cells.keys.min(), unread.allSatisfy({ $0 < seen }) {
                let up = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                up.press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
                Thread.sleep(forTimeInterval: 0.8)
                continue
            }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
            Thread.sleep(forTimeInterval: 0.8)
        }
        return result.map { $0 ?? "" }
    }

    private static func recognise(_ crop: CGImage) throws -> [(CGRect, String)] {
        // Upscale on white so short words are large enough for the recogniser.
        let factor = 2, margin = 20
        let width = crop.width * factor, height = crop.height * factor
        guard let context = CGContext(data: nil, width: width + 2 * margin, height: height + 2 * margin, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return [] }
        context.setFillColor(UIColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width + 2 * margin, height: height + 2 * margin))
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: margin, y: margin, width: width, height: height))
        guard let large = context.makeImage() else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: large, options: [:]).perform([request])
        // Map boxes from the padded image back to the crop's normalised space.
        let fullW = CGFloat(width + 2 * margin), fullH = CGFloat(height + 2 * margin)
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let b = observation.boundingBox
            let x = (b.minX * fullW - CGFloat(margin)) / CGFloat(width), y = (b.minY * fullH - CGFloat(margin)) / CGFloat(height)
            return (CGRect(x: x, y: y, width: b.width * fullW / CGFloat(width), height: b.height * fullH / CGFloat(height)), text)
        }
    }
}

/// A per-run six-digit account code; generated in memory, never written anywhere.
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
    /// The backup archive passphrase of flow 14 (memory only), for the restore on a fresh install.
    nonisolated(unsafe) static var archivePassphrase: String?
    /// Unique per run so the peers can tell this run's phone account from earlier runs' accounts.
    static let displayName = "Realrun " + String((0..<4).map { _ in "abcdefghjkmnpqrstuvwxyz".randomElement()! })
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
