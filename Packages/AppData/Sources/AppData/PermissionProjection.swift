// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import RamfluxCore
/// SDK grant state and compact approval receipts are separate wire shapes.
enum PermissionProjection {
    static func grant(_ row: JSONValue) throws -> PermissionRecord {
        guard let state = row["state"], case .bool(let revoked) = state["revoked"], case .bool(let full) = state["full_delegation"] else { throw AppFailure.invalidData }
        let capabilities = try ProxyGateway.rows(state, "allowed_capabilities").map { value -> String in guard let text = value.string else { throw AppFailure.invalidData }; return text }
        return .grant(PermissionGrant(referenceID: try ProxyGateway.text(row, "grant_id"), state: PermissionGrantState(
            server: try ProxyGateway.text(state, "server_id"), tool: try ProxyGateway.text(state, "tool_name"), scope: state["tool_scope"]?.string,
            registryHash: try ProxyGateway.text(state, "registry_hash"), manifestHash: try ProxyGateway.text(state, "tool_manifest_set_hash"), fullDelegation: full,
            allowedCapabilities: capabilities, revoked: revoked, expiresAt: try expiry(state)), argumentsHash: row["signing_body"]?["arguments_hash"]?.string))
    }
    static func approval(_ row: JSONValue) throws -> PermissionRecord {
        let reference = try ProxyGateway.text(row, "approval_id"), status = try ProxyGateway.text(row, "status"), expires = try expiry(row)
        if row["delivery_state"] != nil {
            guard let binding = row["task_binding"], let revision = unsigned(binding["opening_revision"]) else { throw AppFailure.invalidData }
            return .receipt(PermissionReceipt(referenceID: reference, decisionID: try ProxyGateway.text(row, "decision_id"), grantID: try ProxyGateway.text(row, "grant_id"),
                binding: PermissionTaskBinding(conversationID: try ProxyGateway.text(binding, "conversation_id"), taskID: try ProxyGateway.text(binding, "task_id"), stepID: try ProxyGateway.text(binding, "step_id"), openingRevision: revision,
                    requester: try ProxyGateway.text(binding, "requester"), assignee: try ProxyGateway.text(binding, "assignee"), executorDeviceID: try ProxyGateway.text(binding, "executor_device_id")),
                status: status, deliveryState: try ProxyGateway.text(row, "delivery_state"), reasonCode: row["reason_code"]?.string, expiresAt: expires))
        }
        return .approval(PermissionApproval(referenceID: reference, server: try ProxyGateway.text(row, "server_id"), tool: try ProxyGateway.text(row, "tool_name"), capability: try ProxyGateway.text(row, "capability"), status: status, expiresAt: expires, scope: row["tool_scope"]?.string, argumentsHash: row["details"]?["arguments_hash"]?.string))
    }
    private static func unsigned(_ value: JSONValue?) -> UInt64? { switch value { case .unsigned(let value): value; case .number(let value): UInt64(exactly: value); default: nil } }
    private static func expiry(_ row: JSONValue) throws -> Int64 {
        guard let value = ProxyGateway.integer(row["expires_at"]), (0...253402300799).contains(value) else { throw AppFailure.invalidData }; return value
    }
}
