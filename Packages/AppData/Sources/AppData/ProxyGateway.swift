// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import RamfluxCore

/// Internal gateway. Only AppData knows SDK operation names, envelopes and secret policy.
struct ProxyGateway: Sendable {
    let proxy: SDKProxy
    func context(_ operation: SDKOperation, account: String? = nil, operationID: String? = nil) throws -> RequestContext {
        RequestContext(accountID: account, operationID: operation.requiresOperationID ? (try operationID.map(OperationID.init) ?? .fresh()) : nil,
                       deadlineUnixMilliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 10_000)
    }
    func call(_ operation: SDKOperation, account: String? = nil, body: JSONValue = .object([:]),
              operationID: String? = nil, secrets: [String: SecretField] = [:]) async throws -> JSONValue {
        let ctx = try context(operation, account: account, operationID: operationID)
        if operation.requiresSecureOutput {
            let value = operation.requiresSecureInput
                ? try await proxy.performSecretRequestResponse(operation, context: ctx, body: body, secrets: secrets)
                : try await proxy.performSecretResponse(operation, context: ctx, body: body)
            do { return try Self.body(value) }
            catch { if operation.requiresOperationID { throw AppFailure.outcomeUnknown }; throw error }
        }
        let frame = operation.requiresSecureInput
            ? try await proxy.performSecret(operation, context: ctx, body: body, secrets: secrets)
            : try await proxy.perform(operation, context: ctx, body: body)
        guard frame["ok"] == .bool(true), let body = frame["body"] else {
            throw operation.requiresOperationID ? AppFailure.outcomeUnknown : .invalidData
        }
        return body
    }
    /// A call that may ask the host for the account code (`account.app_lock.configure` only). The frame is read as `call` reads it.
    func callAttended(_ operation: SDKOperation, account: String, body: JSONValue, operationID: String, credentials: @escaping CredentialAsk) async throws -> JSONValue {
        let ctx = try context(operation, account: account, operationID: operationID)
        let frame = try await proxy.performAttended(operation, context: ctx, body: body, credentials: credentials)
        guard frame["ok"] == .bool(true), let body = frame["body"] else { throw AppFailure.outcomeUnknown }
        return body
    }
    static func body(_ value: SecretBytes) throws -> JSONValue {
        try value.consume { bytes in
            let frame = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
            guard frame["code"] == .number(0), frame["response"]?["ok"] == .bool(true), let body = frame["response"]?["body"] else { throw AppFailure.invalidData }
            return body
        }
    }
    /// The rows of an array field. There is no row-count ceiling: the size guard is the bridge's byte ceiling
    /// (`CoreLimits.frameBytes`, 1 MiB per response, enforced before JSON decoding in RamfluxCore), so a
    /// response can never hold more rows than fit in 1 MiB, whatever their count.
    static func rows(_ body: JSONValue, _ key: String) throws -> [JSONValue] {
        guard case .array(let values) = body[key] else { throw AppFailure.invalidData }; return values
    }
    /// Rows a snapshot path maps per decode step before it yields; bounded work between suspension points.
    static let decodeChunk = 1_024
    /// Maps the rows of an unpaged snapshot in bounded chunks, off the main actor, yielding and checking
    /// cancellation between chunks so a large roster neither blocks an executor nor outlives its reader.
    @concurrent static func mapRows<Row: Sendable>(_ body: JSONValue, _ key: String, _ transform: @Sendable (JSONValue) throws -> Row) async throws -> [Row] {
        let values = try rows(body, key)
        var mapped: [Row] = []; mapped.reserveCapacity(values.count)
        var start = 0
        while start < values.count {
            try Task.checkCancellation()
            let end = min(start + decodeChunk, values.count)
            for value in values[start..<end] { mapped.append(try transform(value)) }
            start = end
            if start < values.count { await Task.yield() }
        }
        return mapped
    }
    static func text(_ body: JSONValue, _ key: String) throws -> String {
        guard let value = body[key]?.string, !value.isEmpty, value.utf8.count <= 65_536 else { throw AppFailure.invalidData }; return value
    }
    static func integer(_ value: JSONValue?) -> Int64? {
        switch value { case .string(let v): Int64(v); case .number(let v): Int64(exactly: v); case .unsigned(let v): Int64(exactly: v); default: nil }
    }
}
