// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign
import RFLocalization

/// One confirmation for every admin action that needs one: approve, decline, role, remove, ban and approval off (common
/// 3.1 rule 5). It names the member (display, "this member" for a null name, never an anchor or a request id), shows the AI
/// marker and the agent note when the member is an agent, and names the group. Only its primary button dispatches.
public struct MlsAdminConfirmation: Identifiable, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        case approve(requestID: String), decline(requestID: String)
        case makeAdmin(anchor: String), makeMember(anchor: String), remove(anchor: String), ban(anchor: String)
        case approvalOff
    }
    public let kind: Kind
    /// The member's display name; nil names "this member".
    public let display: String?
    public let aiFlag: Bool
    public let groupName: String
    /// A decline body names when the request expires.
    public let expiresAt: Int64
    public init(kind: Kind, display: String? = nil, aiFlag: Bool = false, groupName: String, expiresAt: Int64 = 0) { self.kind = kind; self.display = display; self.aiFlag = aiFlag; self.groupName = groupName; self.expiresAt = expiresAt }
    /// Neither the anchor nor the request id is printed.
    public var description: String { "MlsAdminConfirmation" }
    public var id: String {
        switch kind {
        case .approve: "approve"; case .decline: "decline"; case .makeAdmin: "makeAdmin"; case .makeMember: "makeMember"
        case .remove: "remove"; case .ban: "ban"; case .approvalOff: "approvalOff"
        }
    }
    /// Remove, ban and approval off use the destructive style.
    public var destructive: Bool {
        switch kind { case .remove, .ban, .approvalOff: true; default: false }
    }
    private func memberName(_ locale: Locale) -> String {
        guard let display, !display.isEmpty else { return FeatureMlsGroupsStrings.text("group.member.this", locale: locale) }
        return RFBidi.isolate(display)
    }
    public func title(locale: Locale) -> String {
        let group = RFBidi.isolate(groupName), who = memberName(locale)
        switch kind {
        case .approve: return FeatureMlsGroupsStrings.format("group.requests.approveConfirm.title", who, group, locale: locale)
        case .decline: return FeatureMlsGroupsStrings.format("group.requests.declineConfirm.title", who, locale: locale)
        case .makeAdmin: return FeatureMlsGroupsStrings.format("group.member.adminConfirm.title", who, group, locale: locale)
        case .makeMember: return FeatureMlsGroupsStrings.format("group.member.demoteConfirm.title", who, group, locale: locale)
        case .remove: return FeatureMlsGroupsStrings.format("group.member.removeConfirm.title", who, group, locale: locale)
        case .ban: return FeatureMlsGroupsStrings.format("group.member.banConfirm.title", who, group, locale: locale)
        case .approvalOff: return FeatureMlsGroupsStrings.text("group.settings.approvalOffConfirm.title", locale: locale)
        }
    }
    public func body(locale: Locale) -> String {
        switch kind {
        case .approve: FeatureMlsGroupsStrings.text("group.requests.approveConfirm.body", locale: locale)
        case .decline: FeatureMlsGroupsStrings.format("group.requests.declineConfirm.body", MlsGroupsText.dateTime(expiresAt, locale: locale), locale: locale)
        case .makeAdmin: FeatureMlsGroupsStrings.text("group.member.adminConfirm.body", locale: locale)
        case .makeMember: FeatureMlsGroupsStrings.text("group.member.demoteConfirm.body", locale: locale)
        case .remove: FeatureMlsGroupsStrings.text("group.member.removeConfirm.body", locale: locale)
        case .ban: FeatureMlsGroupsStrings.text("group.member.banConfirm.body", locale: locale)
        case .approvalOff: FeatureMlsGroupsStrings.text("group.settings.approvalOffConfirm.body", locale: locale)
        }
    }
    public func confirmLabel(locale: Locale) -> String {
        switch kind {
        case .approve: FeatureMlsGroupsStrings.text("group.requests.approveConfirm.confirm", locale: locale)
        case .decline: FeatureMlsGroupsStrings.text("group.requests.declineConfirm.confirm", locale: locale)
        case .makeAdmin: FeatureMlsGroupsStrings.text("group.member.adminConfirm.confirm", locale: locale)
        case .makeMember: FeatureMlsGroupsStrings.text("group.member.demoteConfirm.confirm", locale: locale)
        case .remove: FeatureMlsGroupsStrings.text("group.member.removeConfirm.confirm", locale: locale)
        case .ban: FeatureMlsGroupsStrings.text("group.member.banConfirm.confirm", locale: locale)
        case .approvalOff: FeatureMlsGroupsStrings.text("group.settings.approvalOffConfirm.confirm", locale: locale)
        }
    }
}

/// The confirmation sheet: nothing is sent until the primary button is tapped. No keyboard or default action activates it.
struct MlsAdminConfirmSheet: View {
    let confirmation: MlsAdminConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        RFPage { VStack(alignment: .leading, spacing: theme.gap) {
            Text(confirmation.title(locale: locale)).rfFont(.page).accessibilityIdentifier("mls-confirm-title")
            if confirmation.aiFlag {
                HStack(spacing: theme.gap / 2) { KitAIMarker(tag: "mls-confirm-ai"); Text(FeatureMlsGroupsStrings.text("group.member.agentNote", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary) }
            }
            Text(confirmation.body(locale: locale)).rfFont(.body)
            if confirmation.kind == .approvalOff { Text(MlsChatText.hintMobile(locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-confirm-hint") }
            Spacer(minLength: 0)
            Button(role: confirmation.destructive ? .destructive : nil, action: onConfirm) { Text(confirmation.confirmLabel(locale: locale)).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(confirmation.destructive ? theme.danger : theme.primary).accessibilityIdentifier("mls-confirm-primary")
            Button(role: .cancel, action: onCancel) { Text(FeatureMlsGroupsStrings.text("group.common.cancel", locale: locale)).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).accessibilityIdentifier("mls-confirm-cancel")
        }.padding(theme.gap) }
        .presentationDetents([.medium])
    }
}

extension View {
    /// Presents the confirmation for the item; the primary button clears it first and then calls `perform` once.
    func mlsAdminConfirm(_ item: Binding<MlsAdminConfirmation?>, perform: @escaping (MlsAdminConfirmation) -> Void) -> some View {
        sheet(item: item) { value in
            MlsAdminConfirmSheet(confirmation: value, onConfirm: { item.wrappedValue = nil; perform(value) }, onCancel: { item.wrappedValue = nil })
        }
    }
}
