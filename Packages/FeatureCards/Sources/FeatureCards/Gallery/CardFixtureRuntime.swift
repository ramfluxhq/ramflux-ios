// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
#if RAMFLUX_CARD_GALLERY
import AppData
import CryptoKit
import Foundation
import RamfluxCore

public enum CardFixtureError: Error, Equatable, Sendable {
    case runtimeUnavailable(abi: UInt32)
    case trustUnavailable(status: Int32)
    case trustInvalid(String)
    case fixtureMissing(String)
    case fixtureInvalid(String)
}

/// One standalone-runtime answer: the status, the handle, and the parsed payload of the single callback
/// (the runtime emits `{"session": id, "payload": value}`; the payload is the batch, the tree or the event answer).
public struct CardFixtureCall: Sendable {
    public let status: Int32
    public let session: UInt64
    public let payload: JSONValue?
    public var ok: Bool { status == 0 }
}

/// The bundled trust package, decoded and checked once: the open material and the host presentations.
public struct CardFixtureTrust: Sendable {
    public static let format = "ramflux.sdk.card.trust.v1"
    public static let abiMajor = 5

    public let material: CardFixtureTrustMaterial
    private let presentations: [String: Data]

    /// The presentation JSON `ramflux_card_open` reads for [locale] and [dark]; nil when the package has none.
    public func presentation(locale: String, dark: Bool) -> Data? {
        presentations["\(locale)_\(dark ? "dark" : "light")"]
    }

    /// Refuses (with the reason) when the format, the ABI, the descriptor digest or a field length is off.
    public static func parse(_ json: Data) throws -> CardFixtureTrust {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw CardFixtureError.trustInvalid("not a JSON object")
        }
        guard root["format"] as? String == format else { throw CardFixtureError.trustInvalid("unknown format") }
        guard root["card_abi_major"] as? Int == abiMajor else { throw CardFixtureError.trustInvalid("another card ABI") }
        guard let descriptorText = root["descriptor"] as? String, let descriptorDigest = root["descriptor_sha256"] as? String else {
            throw CardFixtureError.trustInvalid("descriptor missing")
        }
        let descriptor = Data(descriptorText.utf8)
        guard SHA256.hash(data: descriptor).map({ String(format: "%02x", $0) }).joined() == descriptorDigest else {
            throw CardFixtureError.trustInvalid("descriptor digest does not match the package")
        }
        let signature = try base64url(root, "signature_base64url")
        let trustedKey = try base64url(root, "trusted_key_base64url")
        guard signature.count == 64, trustedKey.count == 32 else { throw CardFixtureError.trustInvalid("signature or key length") }
        guard let policy = root["policy"] as? [String: Any], let presentationRows = root["presentations"] as? [String: Any] else {
            throw CardFixtureError.trustInvalid("policy or presentations missing")
        }
        var presentations: [String: Data] = [:]
        for (key, value) in presentationRows {
            guard let object = value as? [String: Any] else { throw CardFixtureError.trustInvalid("presentation is not an object") }
            presentations[key] = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        let material = CardFixtureTrustMaterial(
            bytecode: try base64url(root, "bytecode_base64url"),
            signature: signature,
            trustedKey: trustedKey,
            descriptor: descriptor,
            policy: try JSONSerialization.data(withJSONObject: policy, options: [.sortedKeys, .withoutEscapingSlashes])
        )
        return CardFixtureTrust(material: material, presentations: presentations)
    }

    private static func base64url(_ root: [String: Any], _ name: String) throws -> Data {
        guard let text = root[name] as? String else { throw CardFixtureError.trustInvalid("\(name) missing") }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while standard.count % 4 != 0 { standard += "=" }
        guard let data = Data(base64Encoded: standard) else { throw CardFixtureError.trustInvalid("\(name) is not base64url") }
        return data
    }
}

/// The standalone card runtime for the realrun gallery. The runtime keeps its sessions in thread-local storage, so a
/// handle is valid only on the thread that opened it. A serial dispatch queue is not enough (it hops between worker
/// threads), so the actor runs on `CardFixtureThread`: one dedicated thread for the process. Callback JSON is copied
/// inside each call (`CardFixtureNative`), so results cross back to the main actor as values.
public actor CardFixtureRuntime {
    public static let budgetAttempts = 4
    public static let budgetWait: Duration = .milliseconds(1_100)

    private var cachedTrust: CardFixtureTrust?

    public nonisolated var unownedExecutor: UnownedSerialExecutor { CardFixtureThread.shared.asUnownedSerialExecutor() }

    public init() {}

    /// True when the linked runtime reports the ABI this build was written for.
    public func available() -> Bool {
        CardFixtureNative.abiVersion == UInt32(CardFixtureTrust.abiMajor)
    }

    /// The trust package, decoded once for the life of the runtime.
    public func trust() throws -> CardFixtureTrust {
        if let cachedTrust { return cachedTrust }
        guard available() else { throw CardFixtureError.runtimeUnavailable(abi: CardFixtureNative.abiVersion) }
        let reply = CardFixtureNative.trustPackage()
        guard reply.status == 0, let json = reply.json else { throw CardFixtureError.trustUnavailable(status: reply.status) }
        let decoded = try CardFixtureTrust.parse(json)
        cachedTrust = decoded
        return decoded
    }

    /// Opens one envelope (the fixture's input bytes) for [locale] and [dark].
    public func open(spec: Data, locale: String, dark: Bool) async throws -> CardFixtureCall {
        let trust = try trust()
        guard let presentation = trust.presentation(locale: locale, dark: dark) else {
            return CardFixtureCall(status: 1, session: 0, payload: nil)
        }
        return await attempt {
            CardFixtureNative.open(spec: spec, trust: trust.material, presentation: presentation)
        }
    }

    public func tree(_ session: UInt64) async -> CardFixtureCall {
        await attempt { CardFixtureNative.tree(session) }
    }

    /// One host event as `{token, event}`; the token carries the held tree's session, signed version, edit, tree and key.
    public func event(_ session: UInt64, input: JSONValue) async -> CardFixtureCall {
        let data = (try? JSONEncoder().encode(input)) ?? Data()
        return await attempt { CardFixtureNative.event(session, input: data) }
    }

    public func suspend(_ session: UInt64) async -> CardFixtureCall {
        await attempt { CardFixtureNative.suspend(session) }
    }

    public func resume(_ session: UInt64) async -> CardFixtureCall {
        await attempt { CardFixtureNative.resume(session) }
    }

    public func dispose(_ session: UInt64) -> Int32 {
        CardFixtureNative.dispose(session)
    }

    /// Runs one standalone call; a budget answer (status 5) is retried after a short wait, as the runtime admits
    /// at most two resident VMs per process.
    private func attempt(_ call: () -> CardFixtureNative.Reply) async -> CardFixtureCall {
        var reply = call()
        var tries = 1
        while reply.status == 5, tries < Self.budgetAttempts {
            try? await Task.sleep(for: Self.budgetWait)
            reply = call()
            tries += 1
        }
        return CardFixtureCall(status: reply.status, session: reply.session, payload: Self.payload(reply.json))
    }

    private static func payload(_ json: Data?) -> JSONValue? {
        guard let json, let envelope = try? JSONDecoder().decode(JSONValue.self, from: json) else { return nil }
        return envelope["payload"]
    }
}
/// A serial executor that runs every job on one dedicated thread, started once and kept for the life of the process
/// (the gallery is a test-build instrument; every runtime handle it opens belongs to this thread).
final class CardFixtureThread: SerialExecutor, @unchecked Sendable {
    static let shared = CardFixtureThread()

    private let condition = NSCondition()
    private var jobs: [UnownedJob] = []

    private init() {
        let thread = Thread { [self] in run() }
        thread.name = "org.ramflux.card-fixture-runtime"
        thread.start()
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor { UnownedSerialExecutor(ordinary: self) }

    private func run() {
        while true {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            let job = jobs.removeFirst()
            condition.unlock()
            job.runSynchronously(on: asUnownedSerialExecutor())
        }
    }
}
#endif
