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
    static func body(_ value: SecretBytes) throws -> JSONValue {
        try value.consume { bytes in
            let frame = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
            guard frame["code"] == .number(0), frame["response"]?["ok"] == .bool(true), let body = frame["response"]?["body"] else { throw AppFailure.invalidData }
            return body
        }
    }
    static func rows(_ body: JSONValue, _ key: String) throws -> [JSONValue] {
        guard case .array(let values) = body[key], values.count <= 4096 else { throw AppFailure.invalidData }; return values
    }
    static func text(_ body: JSONValue, _ key: String) throws -> String {
        guard let value = body[key]?.string, !value.isEmpty, value.utf8.count <= 65_536 else { throw AppFailure.invalidData }; return value
    }
    static func integer(_ value: JSONValue?) -> Int64? {
        switch value { case .string(let v): Int64(v); case .number(let v): Int64(exactly: v); case .unsigned(let v): Int64(exactly: v); default: nil }
    }
}
