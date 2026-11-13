// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
struct TaskPermissionDetails: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let row: PermissionRecord
    private func copy(_ key: String) -> String { FeatureTasksStrings.text("tasks." + key, locale: locale) }
    private func status(_ value: String) -> String { copy(["pending", "approved", "denied", "submitted", "applied", "rejected", "failed"].contains(value) ? "permission." + value : "unknown") }
    var body: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Text(copy(kind)).font(theme.pageFont)
            Text(row.referenceID).textSelection(.enabled)
            switch row {
            case .grant(let grant):
                LabeledContent(copy("server"), value: grant.state.server); LabeledContent(copy("tool"), value: grant.state.tool)
                LabeledContent(copy("capability"), value: grant.state.allowedCapabilities.joined(separator: " · "))
                LabeledContent(copy("status"), value: copy(grant.state.revoked ? "revoked" : "notRevoked"))
                if let scope = grant.state.scope { LabeledContent(copy("scope"), value: scope) }
                if let hash = grant.argumentsHash { LabeledContent(copy("hash"), value: hash) }
            case .approval(let approval):
                LabeledContent(copy("server"), value: approval.server); LabeledContent(copy("tool"), value: approval.tool)
                LabeledContent(copy("capability"), value: approval.capability); LabeledContent(copy("status"), value: status(approval.status))
                if let scope = approval.scope { LabeledContent(copy("scope"), value: scope) }
                if let hash = approval.argumentsHash { LabeledContent(copy("hash"), value: hash) }
            case .receipt(let receipt):
                LabeledContent(copy("status"), value: status(receipt.status)); LabeledContent(copy("delivery"), value: status(receipt.deliveryState))
                LabeledContent(copy("decision"), value: receipt.decisionID); LabeledContent(copy("grant"), value: receipt.grantID)
                LabeledContent(copy("conversation"), value: receipt.binding.conversationID); LabeledContent(copy("task"), value: receipt.binding.taskID)
                LabeledContent(copy("step"), value: receipt.binding.stepID); LabeledContent(copy("version"), value: receipt.binding.openingRevision.formatted(.number.locale(locale)))
                LabeledContent(copy("requester"), value: receipt.binding.requester); LabeledContent(copy("assignee"), value: receipt.binding.assignee)
                if let reason = receipt.reasonCode { Text(copy(["retry_exhausted", "transport_unavailable", "intervention_closed", "invalid_decision", "submit_conflict"].contains(reason) ? "reason." + reason : "unknown")) }
            }
            LabeledContent(copy("expiry"), value: Date(timeIntervalSince1970: TimeInterval(row.expiresAt)).formatted(.dateTime.year().month().day().hour().minute().locale(locale)))
        }
    }
    private var kind: String { switch row { case .grant: "grant"; case .approval: "approval"; case .receipt: "receipt" } }
}
