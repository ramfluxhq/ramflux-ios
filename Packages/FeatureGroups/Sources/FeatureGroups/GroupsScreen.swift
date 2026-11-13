// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
public struct GroupsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: GroupsState
    public let onAction: (GroupsAction) -> Void
    public init(state: GroupsState, onAction: @escaping (GroupsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            RFPageHeader(title: title, subtitle: "", theme: theme, leading: { EmptyView() }, trailing: {
                if state.mode == .list { Button(FeatureGroupsStrings.text("groups.create", locale: locale), systemImage: "plus") { onAction(.mode(.create)) } }
                else { Button(FeatureGroupsStrings.text("groups.title", locale: locale)) { onAction(.mode(.list)) } }
            })
            if state.loading { ProgressView(FeatureGroupsStrings.text("groups.loading", locale: locale)) }
            if let pending = state.pending {
                RFApprovalPresentation(title: FeatureGroupsStrings.text("groups.pending", locale: locale), origin: state.accountID, facts: facts(pending.mutation), theme: theme) {
                    RFHostHoldToConfirm(label: FeatureGroupsStrings.text("groups.reconcile", locale: locale), enabled: !state.busy) { onAction(.reconcileOriginal(pending.operationID)) }.id(pending.operationID)
                }
            }
            if let outcome = state.outcome {
                Text(FeatureGroupsStrings.text(outcome.expired ? "groups.requestExpired" : outcome.waitingForOwner ? "groups.waitingOwner" : "groups.acknowledged", locale: locale)).font(theme.bodyFont.weight(.semibold))
                Text(outcome.groupID).font(theme.captionFont).textSelection(.enabled)
                if outcome.waitingForOwner || outcome.expired { Text(FeatureGroupsStrings.text("groups.waitingOwner.message", locale: locale)) }
            }
            if state.detail != nil && !state.authorityFresh { RFTrustBanner(title: FeatureGroupsStrings.text("groups.lastConfirmed", locale: locale), description: "", danger: false, theme: theme, icon: { Image(systemName: "clock") }, action: { EmptyView() }) }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) } }
        .privacySensitive().toolbar { Button(FeatureGroupsStrings.text("groups.refresh", locale: locale), systemImage: "arrow.clockwise") { onAction(.refresh) } }
        .sheet(item: Binding(get: { state.confirmation }, set: { if $0 == nil { onAction(.cancelConfirmation) } })) { confirmation in
            NavigationStack { RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                RFApprovalPresentation(title: FeatureGroupsStrings.text("groups.review", locale: locale), origin: state.accountID, facts: facts(confirmation.attempt.mutation), theme: theme) {
                    VStack(spacing: theme.gap) {
                        Text(FeatureGroupsStrings.text("groups.review.message", locale: locale))
                        RFHostHoldToConfirm(label: FeatureGroupsStrings.text("groups.confirm", locale: locale), enabled: !state.busy && state.pending == nil) { onAction(.confirm(confirmation.id)) }.id(confirmation.id)
                    }
                }
                if state.busy { ProgressView(FeatureGroupsStrings.text("groups.applying", locale: locale)) }
                if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            }.padding(theme.gap) } }.toolbar { Button(FeatureGroupsStrings.text("groups.cancel", locale: locale)) { onAction(.cancelConfirmation) }.disabled(state.busy) } }.interactiveDismissDisabled(state.busy)
        }
    }
    private var title: String {
        let key: String = switch state.mode { case .list: "groups.title"; case .create: "groups.create"; case .detail: "groups.detail"; case .members: "groups.members"; case .requests: "groups.requests"; case .invitation: "groups.invitation"; case .created: "groups.created"; case .managementUnavailable: "groups.manageUnavailable"; case .accessChanged: "groups.accessChanged" }
        return FeatureGroupsStrings.text(key, locale: locale)
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .list:
            RFSearchField(id: "group-search", label: FeatureGroupsStrings.text("groups.filter", locale: locale), value: Binding(get: { state.query }, set: { onAction(.filter($0)) }), theme: theme)
            if state.visibleGroups.isEmpty && !state.loading && state.failure == nil { RFStateBlock(title: FeatureGroupsStrings.text("groups.empty.title", locale: locale), description: FeatureGroupsStrings.text("groups.empty.message", locale: locale), kind: .empty, theme: theme) { EmptyView() } }
            ForEach(state.visibleGroups) { group in groupRow(group) }
            if !state.invitations.isEmpty {
                RFSectionHeader(title: FeatureGroupsStrings.text("groups.invites", locale: locale), theme: theme) { EmptyView() }
                ForEach(state.invitations) { invitation in Button(invitation.name ?? invitation.id) { onAction(.mode(.invitation(invitation.id))) } }
            }
            Text(FeatureGroupsStrings.text("groups.permissions.info", locale: locale)).font(theme.captionFont)
        case .create:
            RFTextField(id: "group-name", label: FeatureGroupsStrings.text("groups.name", locale: locale), value: Binding(get: { state.name }, set: { onAction(.name($0)) }), theme: theme)
            Text(FeatureGroupsStrings.text("groups.creatorOnly", locale: locale))
            Button(FeatureGroupsStrings.text("groups.reviewCreate", locale: locale)) { onAction(.prepareCreate) }.disabled(state.busy || state.loading || state.pending != nil || state.name.isEmpty)
        case .detail, .created:
            if case .created = state.mode { Text(FeatureGroupsStrings.text("groups.created.message", locale: locale)) }
            if let detail = state.detail {
                Text(detail.group.name ?? detail.group.id).font(theme.pageFont)
                Text(detail.group.id).textSelection(.enabled)
                LabeledContent(FeatureGroupsStrings.text("groups.epoch", locale: locale), value: detail.group.epoch.formatted(.number.locale(locale)))
                Button(FeatureGroupsStrings.text("groups.members", locale: locale)) { onAction(.mode(.members(detail.group.id))) }
                Button(FeatureGroupsStrings.text("groups.requests", locale: locale)) { onAction(.mode(.requests(detail.group.id))) }
                Button(FeatureGroupsStrings.text("groups.messages", locale: locale)) { onAction(.openMessages(detail.group.id)) }
                Button(FeatureGroupsStrings.text("groups.history", locale: locale)) { onAction(.unavailable(.threads)) }
                if state.canManage {
                    RFTextField(id: "rename-group", label: FeatureGroupsStrings.text("groups.name", locale: locale), value: Binding(get: { state.name }, set: { onAction(.name($0)) }), theme: theme)
                    Button(FeatureGroupsStrings.text("groups.rename", locale: locale)) { onAction(.prepareRename) }.disabled(state.name.isEmpty || state.busy || state.pending != nil)
                } else { Text(FeatureGroupsStrings.text("groups.permissions.info", locale: locale)).font(theme.captionFont) }
                Button(FeatureGroupsStrings.text("groups.transfer", locale: locale)) { onAction(.unavailable(.ownershipTransfer)) }
                Button(FeatureGroupsStrings.text("groups.leave", locale: locale)) { onAction(.unavailable(.leave)) }
                Button(FeatureGroupsStrings.text("groups.historyPolicy", locale: locale)) { onAction(.unavailable(.historyPolicy)) }
                Button(FeatureGroupsStrings.text("groups.archive", locale: locale)) { onAction(.unavailable(.archive)) }
            }
        case .members:
            if let detail = state.detail {
                ForEach(state.memberRows) { row in
                    let member = row.member
                    VStack(alignment: .leading, spacing: theme.gap / 2) {
                        Text(member.principal.isEmpty ? member.device : member.principal).font(theme.bodyFont.weight(.semibold))
                        Text(member.device).textSelection(.enabled)
                        if let root = member.root { Text(root).font(theme.captionFont).textSelection(.enabled) }
                        Text(role(member.role))
                        if !member.isActive { Text(FeatureGroupsStrings.text("groups.inactive", locale: locale)) }
                        if row.canManage {
                            Button(FeatureGroupsStrings.text("groups.promote", locale: locale)) { onAction(.prepareRole(member.id, "admin")) }
                            Button(FeatureGroupsStrings.text("groups.demote", locale: locale)) { onAction(.prepareRole(member.id, "member")) }
                            Button(FeatureGroupsStrings.text("groups.remove", locale: locale), role: .destructive) { onAction(.prepareRemove(member.id)) }
                        }
                    }.disabled(state.busy || state.pending != nil)
                }
                if state.canManage {
                    RFSectionHeader(title: FeatureGroupsStrings.text("groups.add", locale: locale), theme: theme) { EmptyView() }
                    if state.eligibleContacts.isEmpty { Text(FeatureGroupsStrings.text("groups.addNone", locale: locale)) }
                    ForEach(state.eligibleContacts) { contact in Button(contact.displayName) { onAction(.prepareAdd(contact.id)) }.disabled(state.busy || state.pending != nil) }
                }
            }
        case .requests:
            if state.requests.isEmpty && !state.loading && state.failure == nil { Text(FeatureGroupsStrings.text("groups.noRequests", locale: locale)) }
            ForEach(state.requests) { request in VStack(alignment: .leading) { Text(request.id); Text(requestStatus(request)); expiry(request.expiresAt) } }
        case .invitation(let id):
            if let invitation = state.invitations.first(where: { $0.id == id }) {
                Text(invitation.name ?? invitation.id).font(theme.pageFont); Text(invitation.id)
                LabeledContent(FeatureGroupsStrings.text("groups.creator", locale: locale), value: invitation.creator)
                LabeledContent(FeatureGroupsStrings.text("groups.inviter", locale: locale), value: invitation.inviter); expiry(invitation.expiresAt)
                Button(FeatureGroupsStrings.text("groups.accept", locale: locale)) { onAction(.prepareInvitation(id, true)) }.disabled(state.pending != nil || state.busy)
                Button(FeatureGroupsStrings.text("groups.decline", locale: locale), role: .destructive) { onAction(.prepareInvitation(id, false)) }.disabled(state.pending != nil || state.busy)
            }
        case .managementUnavailable:
            RFStateBlock(title: FeatureGroupsStrings.text("groups.manageUnavailable", locale: locale), description: FeatureGroupsStrings.text("groups.manageUnavailable.message", locale: locale), kind: .error, theme: theme) { EmptyView() }
        case .accessChanged:
            RFStateBlock(title: FeatureGroupsStrings.text("groups.accessChanged", locale: locale), description: FeatureGroupsStrings.text("groups.accessChanged.message", locale: locale), kind: .error, theme: theme) { EmptyView() }
        }
    }
    private func groupRow(_ group: GroupRecord) -> some View {
        RFListRow(id: group.id, title: group.name ?? group.id, subtitle: group.id, theme: theme, leading: { Image(systemName: "person.3") }, trailing: { Image(systemName: "chevron.right") }) { onAction(.mode(.detail(group.id))) }
    }
    private func role(_ value: String) -> String { FeatureGroupsStrings.text(["owner","admin","member","bot"].contains(value) ? "groups." + value : "groups.unknownRole", locale: locale) }
    private func requestStatus(_ request: GroupRequestRecord) -> String {
        let key = request.waitingForOwner ? "groups.requestPending" : request.status == "applied" ? "groups.requestApplied" : request.status == "expired" ? "groups.requestExpired" : ["permission_denied","rejected","refused"].contains(request.status) ? "groups.requestRefused" : "groups.requestUnknown"
        return FeatureGroupsStrings.text(key, locale: locale)
    }
    @ViewBuilder private func expiry(_ timestamp: Int64) -> some View {
        if (0...253402300799).contains(timestamp) { LabeledContent(FeatureGroupsStrings.text("groups.expires", locale: locale), value: Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(.dateTime.year().month().day().hour().minute().locale(locale))) }
    }
    private func facts(_ change: GroupMutation) -> [RFApprovalFact] {
        var values = [RFApprovalFact(id: "account", label: FeatureGroupsStrings.text("groups.account", locale: locale), value: state.accountID), RFApprovalFact(id: "group", label: FeatureGroupsStrings.text("groups.id", locale: locale), value: change.groupID)]
        func append(_ key: String, _ value: String) { values.append(RFApprovalFact(id: key, label: FeatureGroupsStrings.text("groups." + key, locale: locale), value: value)) }
        switch change {
        case .create(_, let name): append("create", FeatureGroupsStrings.text("groups.create", locale: locale)); append("name", name)
        case .rename(_, let epoch, let name): append("epoch", epoch.formatted(.number.locale(locale))); append("name", name)
        case .role(_, let epoch, let member, let selected): append("epoch", epoch.formatted(.number.locale(locale))); append("principal", member.principal); append("root", member.root ?? ""); append("device", member.device); append("newRole", role(selected))
        case .remove(_, let epoch, let member): append("epoch", epoch.formatted(.number.locale(locale))); append("remove.action", FeatureGroupsStrings.text("groups.remove.action", locale: locale)); append("principal", member.principal); append("root", member.root ?? ""); append("device", member.device)
        case .add(_, let epoch, let principal, let root): append("epoch", epoch.formatted(.number.locale(locale))); append("add.action", FeatureGroupsStrings.text("groups.add.action", locale: locale)); append("principal", principal); append("root", root)
        case .invitation(let invitation, let accept): append(accept ? "accept.action" : "decline.action", FeatureGroupsStrings.text(accept ? "groups.accept.action" : "groups.decline.action", locale: locale)); append("creator", invitation.creator); append("inviter", invitation.inviter); if (0...253402300799).contains(invitation.expiresAt) { append("expires", Date(timeIntervalSince1970: TimeInterval(invitation.expiresAt)).formatted(.dateTime.year().month().day().hour().minute().locale(locale))) }
        }
        return values
    }
}
