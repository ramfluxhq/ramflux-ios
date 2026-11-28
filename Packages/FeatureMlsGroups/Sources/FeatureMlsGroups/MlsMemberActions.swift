// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign

/// The member row menu of common 3.3, by the viewer's role:
/// - the owner: Make admin (a member row), Make member (an admin row), Remove, Ban, on every row but the owner and the own row;
/// - an admin: Remove and Ban on plain member rows only;
/// - a member, a read-only group, the owner row and the own row: nothing.
/// Choosing an entry opens the confirmation; nothing is sent by the menu itself.
enum MlsMemberActions {
    enum Entry: String, CaseIterable { case makeAdmin, makeMember, remove, ban }

    static func entries(for member: MlsMemberRow, viewer: MlsRole, readOnly: Bool) -> [Entry] {
        guard !readOnly, !member.isMe, member.role != .owner else { return [] }
        switch viewer {
        case .owner: return member.role == .admin ? [.makeMember, .remove, .ban] : [.makeAdmin, .remove, .ban]
        case .admin: return member.role == .member ? [.remove, .ban] : []
        default: return []
        }
    }
    static func label(_ entry: Entry, locale: Locale) -> String {
        switch entry {
        case .makeAdmin: FeatureMlsGroupsStrings.text("group.member.action.makeAdmin", locale: locale)
        case .makeMember: FeatureMlsGroupsStrings.text("group.member.action.makeMember", locale: locale)
        case .remove: FeatureMlsGroupsStrings.text("group.member.action.remove", locale: locale)
        case .ban: FeatureMlsGroupsStrings.text("group.member.action.ban", locale: locale)
        }
    }
    static func confirmation(_ entry: Entry, member: MlsMemberRow, groupName: String) -> MlsAdminConfirmation {
        let kind: MlsAdminConfirmation.Kind = switch entry {
        case .makeAdmin: .makeAdmin(anchor: member.anchor)
        case .makeMember: .makeMember(anchor: member.anchor)
        case .remove: .remove(anchor: member.anchor)
        case .ban: .ban(anchor: member.anchor)
        }
        return MlsAdminConfirmation(kind: kind, display: member.display, aiFlag: member.aiFlag, groupName: groupName)
    }
}

/// The trailing control of a member row: "Updating…" while its action runs, else the menu.
struct MlsMemberMenu: View {
    let member: MlsMemberRow
    let index: Int
    let model: MlsGroupModel
    let onPick: (MlsAdminConfirmation) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    private var updating: Bool {
        if let busy = model.admin.busy, case .member(let anchor) = busy.target { anchor == member.anchor } else { false }
    }
    var body: some View {
        let entries = MlsMemberActions.entries(for: member, viewer: model.myRole, readOnly: model.readOnly != nil)
        if updating {
            Text(FeatureMlsGroupsStrings.text("group.member.action.updating", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-member-updating-\(index)")
        } else if !entries.isEmpty {
            Menu {
                ForEach(MlsMemberActions.Entry.allCases.filter(entries.contains), id: \.rawValue) { entry in
                    Button(role: entry == .remove || entry == .ban ? .destructive : nil) { onPick(MlsMemberActions.confirmation(entry, member: member, groupName: model.info?.name ?? "")) } label: { Text(MlsMemberActions.label(entry, locale: locale)) }
                        .accessibilityIdentifier("mls-member-action-" + entry.rawValue)
                }
            } label: { Image(systemName: "ellipsis").padding(theme.gap / 2).contentShape(Rectangle()) }
                .disabled(model.entriesBlocked()).accessibilityIdentifier("mls-member-menu-\(index)")
                .accessibilityLabel(Text(FeatureMlsGroupsStrings.text("group.member.menu", locale: locale)))
        }
    }
}
