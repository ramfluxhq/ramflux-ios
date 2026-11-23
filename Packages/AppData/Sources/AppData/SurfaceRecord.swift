// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore
import RFLocalization

/// RFC 8785 (JCS) canonical bytes of a JSON value, as the SDK requires for surface hashes and
/// action frames: object keys sorted by UTF-16 code units, minimal string escapes, integers in
/// decimal. Non-integral numbers use the shortest round-trip form (surface values in the card
/// catalogue are integers, strings, booleans and objects).
enum CanonicalJSON {
    static func bytes(_ value: JSONValue) -> Data { Data(text(value).utf8) }
    static func text(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }
    private static func write(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let flag): out += flag ? "true" : "false"
        case .unsigned(let number): out += String(number)
        case .number(let number):
            if number.rounded() == number, abs(number) < 9_007_199_254_740_992 { out += String(Int64(number)) } else { out += "\(number)" }
        case .string(let string): quote(string, into: &out)
        case .array(let items):
            out += "["
            for (index, item) in items.enumerated() { if index > 0 { out += "," }; write(item, into: &out) }
            out += "]"
        case .object(let fields):
            out += "{"
            for (index, key) in fields.keys.sorted(by: { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }).enumerated() {
                if index > 0 { out += "," }
                quote(key, into: &out); out += ":"
                write(fields[key] ?? .null, into: &out)
            }
            out += "}"
        }
    }
    private static func quote(_ string: String, into out: inout String) {
        out += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        out += "\""
    }
    /// base64url without padding of BLAKE3(domain ‖ canonical bytes).
    static func hash(_ domain: String, _ value: JSONValue) -> String {
        var digest = BLAKE3()
        digest.update(Data(domain.utf8)); digest.update(bytes(value))
        return base64URL(hexBytes(digest.hex()))
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func hexBytes(_ hex: String) -> Data {
        var data = Data(), chars = Array(hex)
        for index in stride(from: 0, to: chars.count - 1, by: 2) { data.append(UInt8(String(chars[index...index + 1]), radix: 16) ?? 0) }
        return data
    }
}

/// One agent surface (card) as `surface.get` returns it. Render and action rules
/// (`docs/conversation_surfaces.md`, the TUI reference renderer):
/// - content is drawn only when the daemon allows it (`render_allowed`), a snapshot is present
///   and its hash matches `surface_hash`; otherwise only the sanitised fallback text is shown;
/// - controls are active only when the surface is renderable, not closed and not out of sync;
/// - an action binds the shown `version` and `surface_hash`.
public struct SurfaceRecord: Identifiable, Equatable, Sendable, CustomStringConvertible {
    public var description: String { "SurfaceRecord(<redacted>)" }
    public var id: String { surfaceRef }
    public let surfaceRef: String
    public let surfaceID: String
    public let conversationID: String
    public let authorPrincipalID: String?
    /// The message that carried the surface; the timeline draws the card under it.
    public let messageID: String?
    public let version: UInt64
    public let hash: String?
    public let closed: Bool
    public let outOfSync: Bool
    public let renderAllowed: Bool
    public let fallbackText: String
    public let snapshot: JSONValue?
    /// Model pointer → "open" (still streaming) or "final".
    public let streams: [String: String]
    /// The snapshot's canonical hash equals `surface_hash`.
    public let verified: Bool
    public var renderable: Bool { renderAllowed && snapshot != nil && verified }
    public var actionable: Bool { renderable && !closed && !outOfSync }

    public init(surfaceRef: String, surfaceID: String, conversationID: String, authorPrincipalID: String?, messageID: String?, version: UInt64, hash: String?, closed: Bool, outOfSync: Bool,
                renderAllowed: Bool, fallbackText: String, snapshot: JSONValue?, streams: [String: String]) {
        self.surfaceRef = surfaceRef; self.surfaceID = surfaceID; self.conversationID = conversationID; self.authorPrincipalID = authorPrincipalID; self.messageID = messageID
        self.version = version; self.hash = hash; self.closed = closed; self.outOfSync = outOfSync; self.renderAllowed = renderAllowed; self.fallbackText = fallbackText
        self.snapshot = snapshot; self.streams = streams
        verified = snapshot.map { hash != nil && CanonicalJSON.hash("ramflux.a2ui.surface_hash.v2", $0) == hash } ?? false
    }

    /// Decodes a `surface.get` body from JSON bytes (previews and tests in feature packages,
    /// which do not see the core JSON type).
    public static func decode(_ data: Data) throws -> SurfaceRecord { try parse(try JSONDecoder().decode(JSONValue.self, from: data)) }

    static func parse(_ body: JSONValue) throws -> SurfaceRecord {
        guard let ref = body["surface_ref"]?.string, !ref.isEmpty, let surface = body["surface_id"]?.string, let conversation = body["conversation_id"]?.string,
              let version = MessagePage.unsigned(body["version"]) else { throw AppFailure.invalidData }
        var streams: [String: String] = [:]
        if case .object(let rows)? = body["streams"] { for (key, value) in rows { if let state = value.string { streams[key] = state } } }
        let snapshot: JSONValue? = if case .object? = body["snapshot"] { body["snapshot"] } else { nil }
        return SurfaceRecord(surfaceRef: ref, surfaceID: surface, conversationID: conversation, authorPrincipalID: body["author_principal_id"]?.string, messageID: body["message_id"]?.string,
                             version: version, hash: body["surface_hash"]?.string, closed: body["closed"] == .bool(true), outOfSync: body["out_of_sync"] != .bool(false),
                             renderAllowed: body["render_allowed"] == .bool(true), fallbackText: body["fallback_text"]?.string ?? "", snapshot: snapshot, streams: streams)
    }

    /// The value at an RFC 6901 pointer in the data model.
    public func value(at pointer: String) -> JSONValue? {
        guard var current = snapshot?["dataModel"] else { return nil }
        guard pointer != "" else { return current }
        guard pointer.hasPrefix("/") else { return nil }
        for raw in pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            let token = raw.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            switch current {
            case .object(let fields): guard let next = fields[token] else { return nil }; current = next
            case .array(let items): guard let index = Int(token), items.indices.contains(index) else { return nil }; current = items[index]
            default: return nil
            }
        }
        return current
    }

    /// The components of the snapshot by id.
    public var components: [String: SurfaceComponent] {
        guard case .array(let rows)? = snapshot?["components"] else { return [:] }
        var result: [String: SurfaceComponent] = [:]
        for row in rows { if let component = SurfaceComponent(row) { result[component.id] = component } }
        return result
    }
}

/// A component of the `rf-card` catalogue that this client renders, or `unsupported` with its
/// kind (shown as a placeholder next to the fallback text).
public struct SurfaceComponent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case text(SurfaceValue, caption: Bool)
        case stack([String], horizontal: Bool)
        case card(String)
        case divider
        case button(child: String, primary: Bool, action: SurfaceButtonAction)
        case textField(label: SurfaceValue, path: String?, placeholder: SurfaceValue, multiline: Bool, obscured: Bool)
        case checkBox(label: SurfaceValue, path: String?)
        case choice(label: SurfaceValue, options: [SurfaceOption], path: String?, multiple: Bool)
        case approval(requestRef: String, explanation: SurfaceValue)
        case unsupported(String)
    }
    public let id: String
    public let kind: Kind

    init?(_ row: JSONValue) {
        guard let id = row["id"]?.string, let type = row["component"]?.string else { return nil }
        self.id = id
        func ids(_ value: JSONValue?) -> [String] { if case .array(let items)? = value { items.compactMap(\.string) } else { [] } }
        func path(_ value: JSONValue?) -> String? { value?["@path"]?.string }
        switch type {
        case "Text": kind = .text(SurfaceValue(row["text"]), caption: row["variant"]?.string == "caption")
        case "Row": kind = .stack(ids(row["children"]), horizontal: true)
        case "Column", "List": kind = .stack(ids(row["children"]), horizontal: row["direction"]?.string == "horizontal")
        case "Card": kind = row["child"]?.string.map { .card($0) } ?? .unsupported(type)
        case "Divider": kind = .divider
        case "Button":
            guard let child = row["child"]?.string else { kind = .unsupported(type); return }
            kind = .button(child: child, primary: row["variant"]?.string == "primary", action: SurfaceButtonAction(row["action"]))
        case "TextField":
            let variant = row["variant"]?.string
            kind = .textField(label: SurfaceValue(row["label"]), path: path(row["value"]), placeholder: SurfaceValue(row["placeholder"]), multiline: variant == "longText", obscured: variant == "obscured")
        case "CheckBox": kind = .checkBox(label: SurfaceValue(row["label"]), path: path(row["value"]))
        case "ChoicePicker":
            var options: [SurfaceOption] = []
            if case .array(let items)? = row["options"] { for item in items { if let value = item["value"]?.string { options.append(SurfaceOption(label: SurfaceValue(item["label"] ?? .string(value)), value: value)) } } }
            kind = .choice(label: SurfaceValue(row["label"]), options: options, path: path(row["value"]), multiple: row["variant"]?.string != "mutuallyExclusive")
        case "Approval": kind = .approval(requestRef: row["requestRef"]?.string ?? "", explanation: SurfaceValue(row["explanation"]))
        default: kind = .unsupported(type)
        }
    }
}

/// A display value: a literal, a data-model binding, or something this client cannot evaluate
/// (a function call), which renders as an unsupported value.
public enum SurfaceValue: Equatable, Sendable {
    case literal(String), path(String), unsupported, none
    init(_ value: JSONValue?) {
        switch value {
        case nil, .null?: self = .none
        case .string(let text)?: self = .literal(text)
        case .number(let number)?: self = .literal(CanonicalJSON.text(.number(number)))
        case .unsigned(let number)?: self = .literal(String(number))
        case .bool(let flag)?: self = .literal(flag ? "true" : "false")
        default: self = value?["@path"]?.string.map { .path($0) } ?? .unsupported
        }
    }
}
public struct SurfaceOption: Equatable, Sendable { public let label: SurfaceValue; public let value: String }
/// An edited input value, keyed by its model pointer.
public enum SurfaceInput: Equatable, Sendable {
    case text(String), flag(Bool), choices([String])
    var json: JSONValue {
        switch self {
        case .text(let text): .string(text)
        case .flag(let flag): .bool(flag)
        case .choices(let values): .array(values.map(JSONValue.string))
        }
    }
}

public extension SurfaceRecord {
    /// The text of a display value; nil when it cannot be shown (unsupported or missing).
    func text(_ value: SurfaceValue) -> String? {
        switch value {
        case .literal(let text): return text
        case .path(let pointer):
            switch self.value(at: pointer) {
            case .string(let text)?: return text
            case .number(let number)?: return CanonicalJSON.text(.number(number))
            case .unsigned(let number)?: return String(number)
            case .bool(let flag)?: return flag ? "true" : "false"
            default: return nil
            }
        case .unsupported, .none: return nil
        }
    }
    /// The destination of a link button, when it passes the same checks the SDK applies when
    /// the surface is committed (HTTPS, a public DNS name, no credentials, at most 2,048 bytes).
    func linkURL(_ value: SurfaceValue) -> URL? { text(value).flatMap(SurfaceLink.validate) }
    /// The current model value of an input as an editable draft.
    func input(at pointer: String) -> SurfaceInput? {
        switch value(at: pointer) {
        case .string(let text)?: .text(text)
        case .bool(let flag)?: .flag(flag)
        case .array(let items)?: .choices(items.compactMap(\.string))
        default: nil
        }
    }
    /// True while the text at `pointer` is still being appended to by the agent.
    func streaming(_ value: SurfaceValue) -> Bool { if case .path(let pointer) = value { streams[pointer] == "open" } else { false } }
}

/// What a button does: send a named event with its context, open a link (the `openUrl`
/// function; the app opens it only after the user confirmed the destination host), or
/// nothing usable.
public enum SurfaceButtonAction: Equatable, Sendable {
    case event(name: String, context: [String: JSONValue], userMessage: String?)
    case link(SurfaceValue)
    case unsupported
    init(_ value: JSONValue?) {
        if let event = value?["event"], let name = event["name"]?.string, !name.isEmpty {
            var context: [String: JSONValue] = [:]
            if case .object(let fields)? = event["context"] { context = fields }
            self = .event(name: name, context: context, userMessage: event["userMessage"]?.string)
        } else if let call = value?["functionCall"] {
            self = call["@call"]?.string == "openUrl" ? .link(SurfaceValue(call["args"]?["url"])) : .unsupported
        } else { self = .unsupported }
    }
}

/// Builds the v3 action frame for a button of a shown surface, bound to its version and hash.
enum SurfaceActionFrame {
    static let schema = "ramflux.surface.action.v3"
    static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]; formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    /// `drafts` holds edited input values by model pointer; other `@path` context entries read
    /// the snapshot's data model.
    static func build(_ surface: SurfaceRecord, buttonID: String, drafts: [String: SurfaceInput], timestamp: Date) -> JSONValue? {
        guard surface.actionable, let hash = surface.hash, case .button(_, _, .event(let name, let context, let message))? = surface.components[buttonID]?.kind else { return nil }
        var resolved: [String: JSONValue] = [:]
        for (key, value) in context {
            if let pointer = value["@path"]?.string { resolved[key] = drafts[pointer]?.json ?? surface.value(at: pointer) ?? .null }
            else if value["@call"] != nil { return nil } else { resolved[key] = value }
        }
        var args: [String: JSONValue] = ["sourceInstance": .array([]), "name": .string(name), "context": .object(resolved)]
        var action: [String: JSONValue] = ["name": .string(name), "surfaceId": .string(surface.surfaceID), "sourceComponentId": .string(buttonID),
                                           "timestamp": .string(rfc3339(timestamp)), "context": .object(resolved)]
        if let message { args["userMessage"] = .string(message); action["userMessage"] = .string(message) }
        return .object(["schema": .string(schema), "conversationId": .string(surface.conversationID), "surfaceVersion": .unsigned(surface.version), "surfaceHash": .string(hash),
                        "sourceInstance": .array([]), "argsHash": .string(CanonicalJSON.hash("ramflux.a2ui.action_args.v2", .object(args))),
                        "a2ui": .object(["version": .string("1.0"), "action": .object(action)])])
    }
}

/// Link checks for card buttons, mirroring `ramflux-protocol` `a2ui::link::validate_url`.
public enum SurfaceLink {
    public static func validate(_ raw: String) -> URL? {
        guard raw.utf8.count <= 2048, !raw.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || RFBidi.isEmbeddingOrIsolate($0) || RFBidi.isMark($0) }) else { return nil }
        guard let components = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)), components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil, authorityHasNoAt(raw),
              var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, labels.count > 1, !["localhost", "local"].contains(labels.last.map(String.init) ?? ""),
              labels.allSatisfy({ label in !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-") && label.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 122) || $0 == 45 } }),
              !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return components.url
    }
    /// The host shown in the confirmation (lowercased, no trailing dot).
    public static func host(_ url: URL) -> String { var host = url.host()?.lowercased() ?? ""; if host.hasSuffix(".") { host.removeLast() }; return host }
    private static func authorityHasNoAt(_ raw: String) -> Bool {
        guard let colon = raw.firstIndex(of: ":") else { return false }
        let rest = raw[raw.index(after: colon)...].drop { $0 == "/" || $0 == "\\" }
        let authority = rest.prefix { !"/\\?#".contains($0) }
        return !authority.contains("@")
    }
}
