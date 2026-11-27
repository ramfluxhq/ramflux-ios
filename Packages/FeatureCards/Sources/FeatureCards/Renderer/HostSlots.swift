// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import RamfluxCore
import AppData
import RFDesign
import RFLocalization

/// The verified facts of an approval, read only from the SDK's slot (`facts`). The card tree never supplies them.
struct CardApprovalFacts: Equatable {
    let requester: String?
    let action: String?
    let scope: [(name: String, value: String)]
    let risk: String?

    init?(_ json: JSONValue?) {
        guard let json, case .object = json else { return nil }
        requester = json["requester"]?.string
        action = json["action"]?.string
        risk = json["risk"]?.string
        scope = (json["scope"]?.array ?? []).compactMap { row in
            guard let name = row["name"]?.string, let value = row["value"]?.string else { return nil }
            return (name, value)
        }
    }

    static func == (lhs: CardApprovalFacts, rhs: CardApprovalFacts) -> Bool {
        lhs.requester == rhs.requester && lhs.action == rhs.action && lhs.risk == rhs.risk
            && lhs.scope.map(\.name) == rhs.scope.map(\.name) && lhs.scope.map(\.value) == rhs.scope.map(\.value)
    }
}

/// An approval card. Without a verified record (no facts in the slot) it shows no buttons: nothing can be decided.
/// Deny answers the slot directly; Allow opens the host's confirmation sheet with the verified facts.
struct CardApprovalView: View {
    let node: CardNode
    let context: CardContext
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let slot = context.slot(for: node.key)
        let facts = CardApprovalFacts(slot?.fields["facts"])
        let decided = slot?.requestID.map { context.decided.contains($0) } ?? false
        let explanation = RFUntrustedText(node.attrs["explanation"]?.string ?? "", kind: .messageBody).text
        let canDecide = facts != nil && slot?.requestID != nil && context.actionable && !decided
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(RFUntrustedText(facts?.action ?? "", kind: .messageBody).text.isEmpty
                     ? FeatureCardsStrings.text("cards.approval.title", locale: locale)
                     : RFUntrustedText(facts?.action ?? "", kind: .messageBody).text)
                    .rfFont(.size(theme.size_subheading), weight: .semibold).foregroundStyle(theme.text)
                Spacer(minLength: 0)
                if decided {
                    CardChip(text: FeatureCardsStrings.text("cards.chip.waiting", locale: locale), tone: .neutral)
                } else if canDecide {
                    CardChip(text: FeatureCardsStrings.text("cards.chip.waitingForYou", locale: locale), tone: .neutral)
                }
            }
            if let facts {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(facts.scope.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(RFUntrustedText(row.name, kind: .identity).text).rfFont(.size(theme.size_secondary), weight: .semibold)
                            Text(RFUntrustedText(row.value, kind: .messageBody).text).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
                        }
                    }
                    if let risk = facts.risk {
                        CardChip(text: RFUntrustedText(risk, kind: .identity).text, tone: risk == "high" ? .danger : .neutral)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
            }
            if !explanation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(FeatureCardsStrings.text("cards.approval.agentSays", locale: locale)).rfFont(.size(theme.size_secondary), weight: .semibold)
                        .foregroundStyle(theme.secondary)
                    Text(explanation).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
                }
            }
            if canDecide, let slot, let requestID = slot.requestID {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    CardActionButton(title: FeatureCardsStrings.text("cards.approval.deny", locale: locale), primary: false) {
                        context.onAnswer(CardAnswer(token: slot.token, slotID: slot.id, requestID: requestID, outcome: .deny))
                    }
                    CardActionButton(title: FeatureCardsStrings.text("cards.approval.allow", locale: locale), primary: true) {
                        context.local.approvalKey = node.key
                    }
                }
            }
        }
    }
}

/// The approval confirmation sheet, presented by the card rather than by the Approval node: an Approval inside a Modal
/// lives in the modal's sheet, and the security sheet must outlive the modal being deferred under it.
struct CardApprovalSheetModifier: ViewModifier {
    let context: CardContext

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { target != nil }, set: { if !$0 { context.local.approvalKey = nil } })) {
            if let target {
                CardApprovalSheet(facts: CardApprovalFacts(target.slot.fields["facts"]), onConfirm: {
                    context.local.approvalKey = nil
                    // The card may have closed or started generating while the sheet was up: no answer then.
                    guard context.editable else { return }
                    context.onAnswer(CardAnswer(token: target.slot.token, slotID: target.slot.id, requestID: target.requestID, outcome: .confirm))
                }, onCancel: { context.local.approvalKey = nil })
                .presentationDetents([.medium, .large])
            }
        }
    }

    /// The Approval node the host is confirming, with its slot and request. Nil when there is none to answer.
    private var target: (key: String, slot: CardHostSlot, requestID: String)? {
        guard let key = context.local.approvalKey, let slot = context.slot(for: key), let requestID = slot.requestID else { return nil }
        return (key, slot, requestID)
    }
}

/// The host's security sheet for an approval: verified facts only, Cancel and a single-tap Confirm.
struct CardApprovalSheet: View {
    let facts: CardApprovalFacts?
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(FeatureCardsStrings.text("cards.approval.sheetTitle", locale: locale)).rfFont(.size(theme.size_subheading), weight: .semibold)
            if let facts {
                if let requester = facts.requester {
                    Text(FeatureCardsStrings.format("cards.approval.requester", RFUntrustedText(requester, kind: .identity).text, locale: locale))
                        .rfFont(.body)
                }
                if let action = facts.action {
                    Text(RFUntrustedText(action, kind: .messageBody).text).rfFont(.body)
                }
                ForEach(Array(facts.scope.enumerated()), id: \.offset) { _, row in
                    Text(FeatureCardsStrings.format("cards.approval.scopeRow", RFUntrustedText(row.name, kind: .identity).text, RFUntrustedText(row.value, kind: .messageBody).text, locale: locale))
                        .rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
                }
                if let risk = facts.risk {
                    Text(FeatureCardsStrings.format("cards.approval.risk", RFUntrustedText(risk, kind: .identity).text, locale: locale))
                        .rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
                }
            }
            HStack(spacing: 8) {
                CardActionButton(title: FeatureCardsStrings.text("cards.link.cancel", locale: locale), primary: false, action: onCancel)
                CardActionButton(title: FeatureCardsStrings.text("cards.approval.confirm", locale: locale), primary: true, action: onConfirm)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The link sheet: the identical canonical https URL, the author and the privacy note. Cancel answers cancel; Open answers
/// confirm, and the browser opens only after the runtime answers `opened`.
struct CardLinkSheet: View {
    let item: CardLinkItem
    let author: String?
    let onOpen: () -> Void
    let onCancel: () -> Void
    @Environment(\.rfTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let link = SurfaceLink.validate(item.url)
        VStack(alignment: .leading, spacing: 16) {
            Text(FeatureCardsStrings.format("cards.link.confirm.title", RFUntrustedText(link.map(SurfaceLink.host) ?? "", kind: .identity).text, locale: locale))
                .rfFont(.size(theme.size_subheading), weight: .semibold)
            Text(verbatim: link?.absoluteString ?? item.url)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(theme.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_md))
            if let author, !author.isEmpty {
                Text(FeatureCardsStrings.format("cards.link.from", RFUntrustedText(author, kind: .identity).text, locale: locale))
                    .rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
            }
            Text(FeatureCardsStrings.text("cards.link.confirm.message", locale: locale)).rfFont(.size(theme.size_secondary)).foregroundStyle(theme.secondary)
            HStack(spacing: 8) {
                CardActionButton(title: FeatureCardsStrings.text("cards.link.cancel", locale: locale), primary: false, action: onCancel)
                CardActionButton(title: FeatureCardsStrings.text("cards.link.open", locale: locale), primary: true, enabled: link != nil, action: onOpen)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A plain host-owned action button for sheets and approval rows.
struct CardActionButton: View {
    let title: String
    let primary: Bool
    var enabled: Bool = true
    let action: () -> Void
    @Environment(\.rfTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .rfFont(.size(theme.size_button), weight: .medium)
                .foregroundStyle(!enabled ? theme.control : (primary ? theme.on_primary : theme.text))
                .padding(.horizontal, 12)
                .frame(minWidth: 64, minHeight: 44)
                .background(!enabled ? theme.surface : (primary ? theme.primary : theme.surface_white), in: RoundedRectangle(cornerRadius: theme.radius_button))
                .overlay {
                    if !primary { RoundedRectangle(cornerRadius: theme.radius_button).strokeBorder(enabled ? theme.text : theme.surface, lineWidth: KitMetrics.stroke) }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
