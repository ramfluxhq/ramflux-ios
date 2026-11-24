// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization
public struct GroupsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: GroupsState
    public let onAction: (GroupsAction) -> Void
    public init(state: GroupsState, onAction: @escaping (GroupsAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage {
            if state.mode == .list {
                VStack(spacing: 0) {
                    listHeader
                    ScrollView { LazyVStack(alignment: .leading, spacing: theme.gap) { listBody }.padding(.top, 20).padding(.horizontal, theme.gap).padding(.bottom, theme.gap) }
                }
            } else {
                ScrollView { LazyVStack(alignment: .leading, spacing: theme.gap) {
                    pushedHeader
                    listBody
                }.padding(theme.gap).frame(maxWidth: theme.column_max, alignment: .leading).frame(maxWidth: .infinity) }
            }
        }
        .privacySensitive().rfHidesNavigationBar()
        .sheet(item: Binding(get: { state.confirmation }, set: { if $0 == nil { onAction(.cancelConfirmation) } })) { confirmation in
            NavigationStack { RFPage { ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
                RFHostFacts(title: FeatureGroupsStrings.text("groups.review", locale: locale), origin: state.accountID, facts: facts(confirmation.attempt.mutation)) {
                    VStack(spacing: theme.gap) {
                        Text(FeatureGroupsStrings.text("groups.review.message", locale: locale))
                        RFHostConfirmationActions(summary: confirmationSummary(confirmation.attempt.mutation), enabled: !state.busy && state.pending == nil, cancelEnabled: !state.busy, confirm: { onAction(.confirm(confirmation.id)) }, cancel: { onAction(.cancelConfirmation) }).id(confirmation.id)
                    }
                }
                if state.busy { ProgressView(FeatureGroupsStrings.text("groups.applying", locale: locale)) }
                if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            }.padding(theme.gap) } } }.interactiveDismissDisabled(state.busy)
        }
    }

    private var listHeader: some View {
        // A large header draws no text action, so creating a group is an icon action next to refresh.
        KitPageHeader(title, large: true, actions: [KitHeaderAction(icon: "plus", label: FeatureGroupsStrings.text("groups.create", locale: locale), action: { onAction(.mode(.create)) }),
                                                    KitHeaderAction(icon: "refresh-cw", label: FeatureGroupsStrings.text("groups.refresh", locale: locale), action: { onAction(.refresh) })], tag: "groups-header")
    }

    private var pushedHeader: some View {
        KitPageHeader(title, onBack: { onAction(.mode(.list)) }, actions: [KitHeaderAction(icon: "refresh-cw", label: FeatureGroupsStrings.text("groups.refresh", locale: locale), action: { onAction(.refresh) })], tag: "groups-header")
    }

    /// The children of the lazy stack around it: a `Group`, so long lists inside `content` stay lazy.
    private var listBody: some View {
        Group {
            if state.loading { ProgressView(FeatureGroupsStrings.text("groups.loading", locale: locale)) }
            if let pending = state.pending {
                RFHostFacts(title: FeatureGroupsStrings.text("groups.pending", locale: locale), origin: state.accountID, facts: facts(pending.mutation)) {
                    Button(FeatureGroupsStrings.text("groups.reconcile", locale: locale)) { onAction(.reconcileOriginal(pending.operationID)) }.disabled(state.busy)
                }
            }
            if let outcome = state.outcome {
                Text(FeatureGroupsStrings.text(outcome.expired ? "groups.requestExpired" : outcome.waitingForOwner ? "groups.waitingOwner" : "groups.acknowledged", locale: locale)).rfFont(.body, weight: .semibold)
                Text(outcome.groupID).rfFont(.caption).textSelection(.enabled)
                if outcome.waitingForOwner || outcome.expired { Text(FeatureGroupsStrings.text("groups.waitingOwner.message", locale: locale)) }
            }
            if state.detail != nil && !state.authorityFresh { KitTipBar(FeatureGroupsStrings.text("groups.lastConfirmed", locale: locale), icon: "clock-3", tag: "groups-last-confirmed") }
            content
            if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
        }
        .frame(maxWidth: theme.column_max, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        let key: String = switch state.mode { case .list: "groups.title"; case .create: "groups.create"; case .detail: "groups.detail"; case .members: "groups.members"; case .requests: "groups.requests"; case .invitation: "groups.invitation"; case .created: "groups.created"; case .managementUnavailable: "groups.manageUnavailable"; case .accessChanged: "groups.accessChanged" }
        return FeatureGroupsStrings.text(key, locale: locale)
    }
    @ViewBuilder private var content: some View {
        switch state.mode {
        case .list:
            KitSearchField(value: Binding(get: { state.query }, set: { onAction(.filter($0)) }), placeholder: FeatureGroupsStrings.text("groups.filter", locale: locale), tag: "group-search")
            if state.visibleGroups.isEmpty && !state.loading && state.failure == nil {
                VStack(alignment: .leading, spacing: theme.gap) {
                    KitStatusHero(icon: "users", tag: "groups-empty")
                    Text(FeatureGroupsStrings.text("groups.empty.title", locale: locale)).rfFont(.body, weight: .semibold)
                    Text(FeatureGroupsStrings.text("groups.empty.message", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                    KitButton(FeatureGroupsStrings.text("groups.create", locale: locale), action: { onAction(.mode(.create)) }, tag: "groups-empty-create")
                }
            }
            ForEach(state.visibleGroups) { group in
                groupRow(group).onAppear { if group.id == state.visibleGroups.last?.id && state.canLoadMore { onAction(.loadMore) } }
            }
            if let failure = state.invitationsFailure {
                Text(FeatureGroupsStrings.text("groups.invites", locale: locale)).rfFont(.body, weight: .semibold)
                RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale))
            }
            if !state.invitations.isEmpty {
                Text(FeatureGroupsStrings.text("groups.invites", locale: locale)).rfFont(.body, weight: .semibold)
                ForEach(state.invitations) { invitation in Button(invitation.name ?? invitation.id) { onAction(.mode(.invitation(invitation.id))) }.accessibilityIdentifier("group-invitation-" + invitation.id) }
            }
            Text(FeatureGroupsStrings.text("groups.permissions.info", locale: locale)).rfFont(.caption)
        case .create:
            KitTextField(value: Binding(get: { state.name }, set: { onAction(.name($0)) }), label: FeatureGroupsStrings.text("groups.name", locale: locale), tag: "group-name")
            Text(FeatureGroupsStrings.text("groups.creatorOnly", locale: locale))
            Button(FeatureGroupsStrings.text("groups.reviewCreate", locale: locale)) { onAction(.prepareCreate) }.disabled(state.busy || state.loading || state.pending != nil || state.name.isEmpty)
        case .detail, .created:
            if case .created = state.mode { Text(FeatureGroupsStrings.text("groups.created.message", locale: locale)) }
            if let detail = state.detail {
                Text(untrusted: detail.group.name ?? detail.group.id).rfFont(.page)
                Text(detail.group.id).textSelection(.enabled)
                LabeledContent(FeatureGroupsStrings.text("groups.epoch", locale: locale), value: detail.group.epoch.formatted(.number.locale(locale)))
                Button(FeatureGroupsStrings.text("groups.members", locale: locale)) { onAction(.mode(.members(detail.group.id))) }
                Button(FeatureGroupsStrings.text("groups.requests", locale: locale)) { onAction(.mode(.requests(detail.group.id))) }
                Button(FeatureGroupsStrings.text("groups.messages", locale: locale)) { onAction(.openMessages(detail.group.id)) }
                Button(FeatureGroupsStrings.text("groups.history", locale: locale)) { onAction(.unavailable(.threads)) }
                if state.canManage {
                    KitTextField(value: Binding(get: { state.name }, set: { onAction(.name($0)) }), label: FeatureGroupsStrings.text("groups.name", locale: locale), tag: "rename-group")
                    Button(FeatureGroupsStrings.text("groups.rename", locale: locale)) { onAction(.prepareRename) }.disabled(state.name.isEmpty || state.busy || state.pending != nil)
                } else { Text(FeatureGroupsStrings.text("groups.permissions.info", locale: locale)).rfFont(.caption) }
                Button(FeatureGroupsStrings.text("groups.transfer", locale: locale)) { onAction(.unavailable(.ownershipTransfer)) }
                Button(FeatureGroupsStrings.text("groups.leave", locale: locale), role: .destructive) { onAction(.prepareLeave) }
                    .disabled(state.busy || state.pending != nil).accessibilityIdentifier("group-leave")
                Button(FeatureGroupsStrings.text("groups.historyPolicy", locale: locale)) { onAction(.unavailable(.historyPolicy)) }
                Button(FeatureGroupsStrings.text("groups.archive", locale: locale)) { onAction(.unavailable(.archive)) }
            }
        case .members:
            if state.detail != nil {
                ForEach(state.memberRows) { row in
                    let member = row.member
                    VStack(alignment: .leading, spacing: theme.gap / 2) {
                        HStack {
                            Text(untrusted: member.displayName ?? (member.principal.isEmpty ? member.device : member.principal)).rfFont(.body, weight: .semibold)
                            if member.classification.isAIAgent { KitAIMarker(tag: member.id + "-ai") }
                        }
                        if member.displayName != nil, !member.principal.isEmpty { KitIdentifierText(member.principal) }
                        KitIdentifierText(member.device).textSelection(.enabled)
                        if let root = member.root { Text(root).rfFont(.caption).textSelection(.enabled) }
                        Text(role(member.role))
                        if !member.isActive { Text(FeatureGroupsStrings.text("groups.inactive", locale: locale)) }
                        if row.canManage {
                            Button(FeatureGroupsStrings.text("groups.promote", locale: locale)) { onAction(.prepareRole(member.id, "admin")) }
                            Button(FeatureGroupsStrings.text("groups.demote", locale: locale)) { onAction(.prepareRole(member.id, "member")) }
                            Button(FeatureGroupsStrings.text("groups.remove", locale: locale), role: .destructive) { onAction(.prepareRemove(member.id)) }
                        }
                    }.disabled(state.busy || state.pending != nil)
                    .onAppear { if row.id == state.memberRows.last?.id && state.canLoadMoreMembers { onAction(.loadMore) } }
                }
                if state.canManage {
                    Text(FeatureGroupsStrings.text("groups.add", locale: locale)).rfFont(.body, weight: .semibold)
                    if state.eligibleContacts.isEmpty { Text(FeatureGroupsStrings.text("groups.addNone", locale: locale)) }
                    ForEach(state.eligibleContacts) { contact in
                        Button(contact.displayName) { onAction(.prepareAdd(contact.id)) }.disabled(state.busy || state.pending != nil)
                            .onAppear { if contact.id == state.eligibleContacts.last?.id && state.canLoadMoreContacts { onAction(.loadMoreContacts) } }
                    }
                    if state.canLoadMoreContacts && state.eligibleContacts.isEmpty { Button(FeatureGroupsStrings.text("groups.refresh", locale: locale)) { onAction(.loadMoreContacts) } }
                }
            }
        case .requests:
            if state.requests.isEmpty && !state.loading && state.failure == nil { Text(FeatureGroupsStrings.text("groups.noRequests", locale: locale)) }
            ForEach(state.requests) { request in VStack(alignment: .leading) { Text(request.id); Text(requestStatus(request)); expiry(request.expiresAt) } }
        case .invitation(let id):
            if let invitation = state.invitations.first(where: { $0.id == id }) {
                Text(untrusted: invitation.name ?? invitation.id).rfFont(.page); Text(invitation.id)
                LabeledContent(FeatureGroupsStrings.text("groups.creator", locale: locale), value: invitation.creator)
                LabeledContent(FeatureGroupsStrings.text("groups.inviter", locale: locale), value: invitation.inviter); expiry(invitation.expiresAt)
                Button(FeatureGroupsStrings.text("groups.accept", locale: locale)) { onAction(.prepareInvitation(id, true)) }.disabled(state.pending != nil || state.busy).accessibilityIdentifier("group-invitation-accept")
                Button(FeatureGroupsStrings.text("groups.decline", locale: locale), role: .destructive) { onAction(.prepareInvitation(id, false)) }.disabled(state.pending != nil || state.busy).accessibilityIdentifier("group-invitation-decline")
            }
        case .managementUnavailable:
            RFFailureView(title: FeatureGroupsStrings.text("groups.manageUnavailable", locale: locale), message: FeatureGroupsStrings.text("groups.manageUnavailable.message", locale: locale))
        case .accessChanged:
            RFFailureView(title: FeatureGroupsStrings.text("groups.accessChanged", locale: locale), message: FeatureGroupsStrings.text("groups.accessChanged.message", locale: locale))
        }
    }
    private func groupRow(_ group: GroupRecord) -> some View {
        KitRow(RFUntrustedText.clean(group.name ?? group.id), action: { onAction(.mode(.detail(group.id))) }, icon: "users", value: group.id, tag: group.id)
    }
    private func role(_ value: String) -> String { FeatureGroupsStrings.text(["owner","admin","member","bot"].contains(value) ? "groups." + value : "groups.unknownRole", locale: locale) }
    private func requestStatus(_ request: GroupRequestRecord) -> String {
        let key = request.waitingForOwner ? "groups.requestPending" : request.status == "applied" ? "groups.requestApplied" : request.status == "expired" ? "groups.requestExpired" : ["permission_denied","rejected","refused"].contains(request.status) ? "groups.requestRefused" : "groups.requestUnknown"
        return FeatureGroupsStrings.text(key, locale: locale)
    }
    @ViewBuilder private func expiry(_ timestamp: Int64) -> some View {
        if (0...253402300799).contains(timestamp) { LabeledContent(FeatureGroupsStrings.text("groups.expires", locale: locale), value: Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(.dateTime.year().month().day().hour().minute().locale(locale))) }
    }
    private func confirmationSummary(_ change: GroupMutation) -> String {
        let key: String = switch change {
        case .create: "groups.create"
        case .rename: "groups.rename"
        case .role: "groups.newRole"
        case .remove: "groups.remove"
        case .add: "groups.add"
        case .invitation(_, let accept): accept ? "groups.accept" : "groups.decline"
        case .leave: "groups.leave"
        }
        // Fact values are names and identifiers: each is isolated, and the locale's list format joins them.
        let values = facts(change).map { RFBidi.isolate($0.value) }.formatted(.list(type: .and, width: .narrow).locale(locale))
        return FeatureGroupsStrings.sentence("groups.confirm.summary", [.localized(FeatureGroupsStrings.text(key, locale: locale)), .localized(values)], locale: locale)
    }
    private func facts(_ change: GroupMutation) -> [RFHostFact] {
        var values = [RFHostFact(id: "account", label: FeatureGroupsStrings.text("groups.account", locale: locale), value: state.accountID), RFHostFact(id: "group", label: FeatureGroupsStrings.text("groups.id", locale: locale), value: change.groupID)]
        func append(_ key: String, _ value: String) { values.append(RFHostFact(id: key, label: FeatureGroupsStrings.text("groups." + key, locale: locale), value: value)) }
        switch change {
        case .create(_, let name): append("create", FeatureGroupsStrings.text("groups.create", locale: locale)); append("name", name)
        case .rename(_, let epoch, let name): append("epoch", epoch.formatted(.number.locale(locale))); append("name", name)
        case .role(_, let epoch, let member, let selected): append("epoch", epoch.formatted(.number.locale(locale))); append("principal", member.principal); append("root", member.root ?? ""); append("device", member.device); append("newRole", role(selected))
        case .remove(_, let epoch, let member): append("epoch", epoch.formatted(.number.locale(locale))); append("remove.action", FeatureGroupsStrings.text("groups.remove.action", locale: locale)); append("principal", member.principal); append("root", member.root ?? ""); append("device", member.device)
        case .add(_, let epoch, let principal, let root): append("epoch", epoch.formatted(.number.locale(locale))); append("add.action", FeatureGroupsStrings.text("groups.add.action", locale: locale)); append("principal", principal); append("root", root)
        case .leave(_, let epoch): append("epoch", epoch.formatted(.number.locale(locale))); append("leave.action", FeatureGroupsStrings.text("groups.leave.action", locale: locale))
        case .invitation(let invitation, let accept): append(accept ? "accept.action" : "decline.action", FeatureGroupsStrings.text(accept ? "groups.accept.action" : "groups.decline.action", locale: locale)); append("creator", invitation.creator); append("inviter", invitation.inviter); if (0...253402300799).contains(invitation.expiresAt) { append("expires", Date(timeIntervalSince1970: TimeInterval(invitation.expiresAt)).formatted(.dateTime.year().month().day().hour().minute().locale(locale))) }
        }
        return values
    }
}
