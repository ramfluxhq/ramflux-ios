// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// This phone as the account's primary device inviting and approving another device
/// (`device.pair.begin`, `status`, `confirm`, `approve`, `cancel`; reference caller `apps/rf/src/handlers/pairing.rs`).
/// The joining side (`device.pair.join`) needs the SDK's attended credential channel, which the in-process
/// ABI does not open; it is not offered here.
public protocol PairingRepository: Sendable {
    /// Starts a ceremony for a new device labelled `deviceName`. The invitation is a show-once secret.
    func begin(account: String, deviceName: String, operationID: String) async -> RepositoryResult<PairingInvitation>
    func status(account: String, operation: PairingOperation) async -> RepositoryResult<PairingProgress>
    /// Records whether the seven symbols on both devices match. A positive answer re-reads the status first and
    /// refuses when the transcript changed since `shown`; a negative answer ends the ceremony on both devices.
    func confirm(account: String, shown: PairingProgress, matches: Bool, operationID: String) async -> RepositoryResult<PairingProgress>
    /// Approves or declines the joining device's enrolment proposal reviewed in `reviewed`.
    func approve(account: String, reviewed: PairingProgress, approved: Bool, operationID: String) async -> RepositoryResult<PairingProgress>
    func cancel(account: String, operation: PairingOperation, operationID: String) async -> RepositoryResult<PairingProgress>
}

public struct NativePairingRepository: PairingRepository {
    private let gateway: ProxyGateway
    /// The rights a linked device receives (the reference caller's default set).
    static let capabilities = ["message", "register", "sync"]
    /// The device lease: the SDK's maximum branch lease (`MAX_BRANCH_LEASE_SECONDS`, 30 days).
    static let leaseSeconds: UInt64 = 2_592_000
    private let now: @Sendable () -> Date
    public init(client: RamfluxClient, now: @escaping @Sendable () -> Date = Date.init) { gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.now = now }

    public func begin(account: String, deviceName: String, operationID: String) async -> RepositoryResult<PairingInvitation> {
        guard let name = Self.validName(deviceName) else { return .failure(.pairing(.deviceName)) }
        let start = UInt64(max(0, now().timeIntervalSince1970))
        let body: JSONValue = .object([
            "schema": .string("ramflux.pairing.Begin.v2"), "version": .number(2), "display_name": .string(name),
            "capabilities": .array(Self.capabilities.sorted().map(JSONValue.string)),
            "lease_not_before": .unsigned(start), "lease_expires_at": .unsigned(start + Self.leaseSeconds),
        ])
        do {
            let context = try gateway.context(.devicePairBegin, account: account, operationID: operationID)
            let frame = try await gateway.proxy.performSecretRequestResponse(.devicePairBegin, context: context, body: body, secrets: [:])
            return .success(try SealedPairingFrame.invitation(frame))
        } catch { return .failure(Self.failure(error)) }
    }
    public func status(account: String, operation: PairingOperation) async -> RepositoryResult<PairingProgress> {
        await run(.devicePairStatus, account: account, operationID: nil, body: Self.base("StatusRequest", operation))
    }
    public func confirm(account: String, shown: PairingProgress, matches: Bool, operationID: String) async -> RepositoryResult<PairingProgress> {
        guard let transcript = shown.transcriptHash else { return .failure(.invalidInput) }
        if matches {
            switch await status(account: account, operation: shown.operation) {
            case .failure(let failure): return .failure(failure)
            case .success(let current):
                guard current.canCompare, current.transcriptHash == transcript, current.emoji == shown.emoji else { return .failure(.pairing(.comparisonChanged)) }
            }
        }
        var body = Self.base("Confirm", shown.operation)
        body["transcript_hash"] = .string(transcript); body["match"] = .bool(matches)
        return await run(.devicePairConfirm, account: account, operationID: operationID, body: body)
    }
    public func approve(account: String, reviewed: PairingProgress, approved: Bool, operationID: String) async -> RepositoryResult<PairingProgress> {
        guard reviewed.canApprove, let transcript = reviewed.transcriptHash, let proposal = reviewed.proposalHash else { return .failure(.invalidInput) }
        var body = Self.base("Approve", reviewed.operation)
        body["transcript_hash"] = .string(transcript); body["proposal_hash"] = .string(proposal); body["approved"] = .bool(approved)
        return await run(.devicePairApprove, account: account, operationID: operationID, body: body)
    }
    public func cancel(account: String, operation: PairingOperation, operationID: String) async -> RepositoryResult<PairingProgress> {
        await run(.devicePairCancel, account: account, operationID: operationID, body: Self.base("Cancel", operation))
    }

    private func run(_ operation: SDKOperation, account: String, operationID: String?, body: [String: JSONValue]) async -> RepositoryResult<PairingProgress> {
        do { return .success(try Self.progress(await gateway.call(operation, account: account, body: .object(body), operationID: operationID))) }
        catch { return .failure(Self.failure(error)) }
    }
    private static func base(_ name: String, _ operation: PairingOperation) -> [String: JSONValue] {
        ["schema": .string("ramflux.pairing.\(name).v2"), "version": .number(2), "operation_id": .string(operation.id), "generation": .unsigned(operation.generation)]
    }
    /// The SDK's display-name rule (`local_dto::name`): at most 128 bytes of free text without control or format characters.
    static func validName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 128,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format }) else { return nil }
        return name
    }
    /// Maps a `ramflux.pairing.LocalResult.v2` body with an `update` or `error` outcome.
    static func progress(_ body: JSONValue) throws -> PairingProgress {
        guard body["schema"]?.string == "ramflux.pairing.LocalResult.v2", let outcome = body["outcome"] else { throw AppFailure.invalidData }
        if outcome["tag"]?.string == "error" { throw AppFailure.pairing(PairingIssue.sdk(outcome["error"]?["code"]?.string) ?? .other) }
        guard outcome["tag"]?.string == "update", let value = outcome["value"] else { throw AppFailure.invalidData }
        guard let phase = value["phase"]?.string.flatMap(PairingPhase.init(rawValue:)), let generation = unsigned(value["generation"]), generation >= 1,
              let expires = unsigned(value["expires_at"]) else { throw AppFailure.invalidData }
        let emoji: [Int]? = try value["emoji_indices"].flatMap { indices in
            guard case .array(let rows) = indices else { return nil }
            let values = try rows.map { row -> Int in guard let index = unsigned(row), index <= 63 else { throw AppFailure.invalidData }; return Int(index) }
            guard values.count == 7 else { throw AppFailure.invalidData }
            return values
        }
        let capabilities = try ProxyGateway.rows(value, "capabilities").map { row -> String in guard let text = row.string else { throw AppFailure.invalidData }; return text }
        let peerName = value["peer_name"]?.string, peerDevice = value["peer_ref"]?["device_id"]?.string
        guard (peerName == nil) == (peerDevice == nil) else { throw AppFailure.invalidData }
        return PairingProgress(operation: PairingOperation(id: try ProxyGateway.text(value, "operation_id"), generation: generation), phase: phase,
            expiresAt: date(expires), transcriptHash: value["transcript_hash"]?.string, emoji: emoji, peerDeviceID: peerDevice, peerName: peerName,
            capabilities: capabilities, leaseNotBefore: date(unsigned(value["lease_not_before"]) ?? 0), leaseExpiresAt: date(unsigned(value["lease_expires_at"]) ?? 0),
            proposalHash: value["proposal_hash"]?.string, result: value["result"]?.string)
    }
    private static func date(_ seconds: UInt64) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }
    private static func unsigned(_ value: JSONValue?) -> UInt64? {
        switch value { case .unsigned(let v): v; case .number(let v): v >= 0 && v == v.rounded() ? UInt64(exactly: v) : nil; case .string(let v): UInt64(v); default: nil }
    }
    static func failure(_ error: any Error) -> AppFailure {
        if let failure = error as? AppFailure { return failure }
        if let failure = error as? CoreFailure {
            let error = failure.response?["error"]
            if let issue = PairingIssue.sdk(failure.reasonCode) ?? PairingIssue.sdk(error?["code"]?.string) { return .pairing(issue) }
            // The bus reports `SdkError::PairingCode` as "pairing <Code>".
            if let message = error?["message"]?.string, message.hasPrefix("pairing "), let issue = PairingIssue.sdk(String(message.dropFirst(8))) { return .pairing(issue) }
        }
        return AppFailure.map(error)
    }
}

public struct UnavailablePairingRepository: PairingRepository {
    public init() {}
    public func begin(account: String, deviceName: String, operationID: String) async -> RepositoryResult<PairingInvitation> { .failure(.sdkUnavailable) }
    public func status(account: String, operation: PairingOperation) async -> RepositoryResult<PairingProgress> { .failure(.sdkUnavailable) }
    public func confirm(account: String, shown: PairingProgress, matches: Bool, operationID: String) async -> RepositoryResult<PairingProgress> { .failure(.sdkUnavailable) }
    public func approve(account: String, reviewed: PairingProgress, approved: Bool, operationID: String) async -> RepositoryResult<PairingProgress> { .failure(.sdkUnavailable) }
    public func cancel(account: String, operation: PairingOperation, operationID: String) async -> RepositoryResult<PairingProgress> { .failure(.sdkUnavailable) }
}
