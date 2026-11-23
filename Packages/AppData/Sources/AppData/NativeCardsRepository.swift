// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// Surfaces through the SDK: `surface.list` (paged by `next_cursor`) then `surface.get` per row
/// for the render gate and snapshot, and `surface.action` with the canonical v3 action frame.
public struct NativeCardsRepository: CardsRepository {
    private let gateway: ProxyGateway
    private let updates: NativeUpdateSource
    private let now: @Sendable () -> Date
    public init(client: RamfluxClient, updates: NativeUpdateSource) { self.init(client: client, updates: updates, now: Date.init) }
    init(client: RamfluxClient, updates: NativeUpdateSource, now: @escaping @Sendable () -> Date) {
        gateway = ProxyGateway(proxy: SDKProxy(client: client)); self.updates = updates; self.now = now
    }
    public func availability() async -> RepositoryResult<Void> { .success(()) }
    public func surfaces(account: String, conversation: String, cursor: String?) async -> RepositoryResult<SurfacePage> {
        guard !conversation.isEmpty, conversation.utf8.count <= 256 else { return .failure(.invalidInput) }
        do {
            var body: [String: JSONValue] = ["conversation_id": .string(conversation), "limit": .number(20)]
            if let cursor { body["cursor"] = .string(cursor) }
            let page = try await gateway.call(.surfaceList, account: account, body: .object(body))
            var records: [SurfaceRecord] = []
            for row in try ProxyGateway.rows(page, "surfaces") where row["removed"] != .bool(true) {
                guard let ref = row["surface_ref"]?.string else { throw AppFailure.invalidData }
                if case .success(let record?) = await surface(account: account, surfaceRef: ref) { records.append(record) }
            }
            let next = page["next_cursor"]?.string.flatMap { $0.isEmpty || $0 == cursor ? nil : $0 }
            return .success(SurfacePage(surfaces: records, nextCursor: next))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func surface(account: String, surfaceRef: String) async -> RepositoryResult<SurfaceRecord?> {
        guard !surfaceRef.isEmpty, surfaceRef.utf8.count <= 512 else { return .failure(.invalidInput) }
        do {
            let body = try await gateway.call(.surfaceGet, account: account, body: .object(["surface_ref": .string(surfaceRef)]))
            if body == .null { return .success(nil) }
            return .success(try SurfaceRecord.parse(body))
        } catch { return .failure(AppFailure.map(error)) }
    }
    public func act(account: String, shown: SurfaceRecord, buttonID: String, drafts: [String: SurfaceInput], messageID: String) async -> RepositoryResult<SurfaceActionOutcome> {
        guard shown.actionable, !messageID.isEmpty, messageID.utf8.count <= 64 else { return .failure(.invalidInput) }
        // The surface must still be the one the user saw.
        switch await surface(account: account, surfaceRef: shown.surfaceRef) {
        case .success(let current?):
            guard current.version == shown.version, current.hash == shown.hash else { return .failure(.typedRefusal("stale_version")) }
            guard current.actionable else { return .failure(.typedRefusal(current.closed ? "closed" : "out_of_sync")) }
        case .success(nil): return .failure(.typedRefusal("not_found"))
        case .failure(let error): return .failure(error)
        }
        guard let frame = SurfaceActionFrame.build(shown, buttonID: buttonID, drafts: drafts, timestamp: now()) else { return .failure(.invalidInput) }
        var body: [String: JSONValue] = ["conversation_id": .string(shown.conversationID), "message_id": .string(messageID), "wire_base64": .string(CanonicalJSON.base64URL(CanonicalJSON.bytes(frame)))]
        if let author = shown.authorPrincipalID { body["author_principal_id"] = .string(author) }
        do {
            let result = try await gateway.call(.surfaceAction, account: account, body: .object(body), operationID: messageID)
            return .success(SurfaceActionOutcome(accepted: result["accepted"] == .bool(true), queued: result["queued"] == .bool(true), reasonCode: result["reason_code"]?.string))
        } catch {
            if let code = Self.refusal(error) { return .failure(.typedRefusal(code)) }
            return .failure(AppFailure.map(error))
        }
    }
    public func observe(account: String) async -> RepositoryObservation { await updates.observe(account: account) }
    static let refusals: Set<String> = ["stale_version", "stale_hash", "not_author", "not_out_of_sync", "rate_limited", "too_large", "not_found", "out_of_sync", "not_action_executor", "already_used", "closed", "not_permitted", "invalid_request"]
    private static func refusal(_ error: any Error) -> String? {
        guard let failure = error as? CoreFailure else { return nil }
        return [failure.typedName, failure.reasonCode, failure.response?["error"]?["code"]?.string].compactMap { $0 }.first { refusals.contains($0) }
    }
}
