// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign

/// The accessibility id of a row: the row index in a production build; a fixture id only in the Debug gallery, so a real
/// request id or anchor never reaches an identifier (A13).
func mlsRowTag(_ prefix: String, index: Int, fixtureID: String) -> String {
    #if RAMFLUX_MLS_GALLERY
    return prefix + fixtureID
    #else
    return prefix + String(index)
    #endif
}

/// Join requests (D-M3-1): a lazy list that pages in 20 rows before the end, oldest first. Approve and Decline each open
/// a confirmation; the row shows Approving, Adding and Declining; a row past its time shows Expired and its buttons are off.
public struct MlsRequestsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: MlsGroupModel
    @State private var confirmation: MlsAdminConfirmation?
    public init(model: MlsGroupModel) { self.model = model }
    private var requests: MlsRequestsSnapshot { model.admin.requests }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            KitPageHeader(FeatureMlsGroupsStrings.text("group.requests.title", locale: locale), tag: "mls-requests-header")
            VStack(alignment: .leading, spacing: theme.gap) { notices }.padding(.horizontal, theme.gap).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView { LazyVStack(alignment: .leading, spacing: theme.gap) { content }.padding(.horizontal, theme.gap) }.accessibilityIdentifier("mls-requests-list")
        } }
        .task { model.start(); model.openRequests() }
        .onDisappear { model.stop(); model.clearNotice() }
        .mlsAdminConfirm($confirmation) { model.perform($0) }
    }
    @ViewBuilder private var notices: some View {
        if requests.approvalOff {
            Text(FeatureMlsGroupsStrings.text("group.requests.approvalOff", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-requests-approval-off")
        }
        if let notice = model.admin.notice {
            Text(MlsChatText.error(notice.error, locale: locale)).rfFont(.caption).foregroundStyle(notice.isToast ? theme.secondary : theme.danger).accessibilityIdentifier(notice.isToast ? "mls-requests-toast" : "mls-requests-error")
        }
        if model.admin.busy != nil {
            Text(FeatureMlsGroupsStrings.text("group.member.action.busy", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-requests-busy")
        }
    }
    @ViewBuilder private var content: some View {
        switch requests.phase {
        case .idle where requests.rows.isEmpty, .loading where requests.rows.isEmpty: ProgressView().frame(maxWidth: .infinity).padding(theme.gap)
        case .loadError where requests.rows.isEmpty:
            VStack(alignment: .leading, spacing: theme.gap) {
                Text(FeatureMlsGroupsStrings.text("group.requests.loadError", locale: locale)).rfFont(.body).foregroundStyle(theme.danger)
                Button(FeatureMlsGroupsStrings.text("group.requests.retry", locale: locale)) { model.retryRequests() }.accessibilityIdentifier("mls-requests-retry")
            }.accessibilityIdentifier("mls-requests-error-state")
        default:
            if requests.rows.isEmpty, requests.phase == .loaded { Text(FeatureMlsGroupsStrings.text("group.requests.empty", locale: locale)).rfFont(.body).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-requests-empty") }
            ForEach(Array(requests.rows.enumerated()), id: \.element.id) { index, row in
                requestRow(row, index: index).onAppear { model.requestRowAppeared(index: index) }
            }
            switch requests.phase {
            case .loadingMore, .loading: ProgressView().frame(maxWidth: .infinity)
            case .pageError:
                HStack(spacing: theme.gap) {
                    Text(FeatureMlsGroupsStrings.text("group.requests.pageError", locale: locale)).rfFont(.caption).foregroundStyle(theme.danger)
                    Button(FeatureMlsGroupsStrings.text("group.requests.retry", locale: locale)) { model.retryRequests() }.rfFont(.caption).accessibilityIdentifier("mls-requests-retry")
                }.accessibilityIdentifier("mls-requests-page-error")
            case .loadError:
                HStack(spacing: theme.gap) {
                    Text(FeatureMlsGroupsStrings.text("group.requests.loadError", locale: locale)).rfFont(.caption).foregroundStyle(theme.danger)
                    Button(FeatureMlsGroupsStrings.text("group.requests.retry", locale: locale)) { model.retryRequests() }.rfFont(.caption).accessibilityIdentifier("mls-requests-retry")
                }
            default: EmptyView()
            }
        }
    }
    private func requestRow(_ row: MlsRequestRow, index: Int) -> some View {
        let request = row.request
        let name = request.display.flatMap { $0.isEmpty ? nil : $0 }
        let idle = row.state == .idle && !row.expired
        let blocked = model.entriesBlocked()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: theme.gap) {
                KitAvatar(String((name ?? FeatureMlsGroupsStrings.text("group.member.unnamed", locale: locale)).prefix(1)), size: 36, kind: request.aiFlag ? .agent : .person)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: theme.gap / 2) {
                        if let name { Text(untrusted: name).rfFont(.body) } else { Text(FeatureMlsGroupsStrings.text("group.member.unnamed", locale: locale)).rfFont(.body).foregroundStyle(theme.secondary) }
                        if request.aiFlag { KitAIMarker(tag: "mls-request-ai") }
                    }
                    Text(FeatureMlsGroupsStrings.format("group.requests.requested", MlsGroupsText.dateTime(request.requestedAt, locale: locale), locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                    if row.expired { Text(FeatureMlsGroupsStrings.text("group.requests.expired", locale: locale)).rfFont(.caption).foregroundStyle(theme.danger).accessibilityIdentifier(mlsRowTag("mls-request-expired-", index: index, fixtureID: request.requestID)) }
                    else if request.expiresAt > 0 { Text(FeatureMlsGroupsStrings.format("group.requests.expires", MlsGroupsText.dateTime(request.expiresAt, locale: locale), locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary) }
                }
            }
            if let progress = progressText(row.state) { Text(progress).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier(mlsRowTag("mls-request-state-", index: index, fixtureID: request.requestID)) }
            HStack(spacing: theme.gap) {
                KitButton(FeatureMlsGroupsStrings.text("group.requests.approve", locale: locale), action: { confirmation = confirm(.approve(requestID: request.requestID), row) }, size: .compact, enabled: idle && !blocked, tag: mlsRowTag("mls-request-approve-", index: index, fixtureID: request.requestID))
                KitButton(FeatureMlsGroupsStrings.text("group.requests.decline", locale: locale), action: { confirmation = confirm(.decline(requestID: request.requestID), row) }, kind: .secondary, size: .compact, enabled: idle, tag: mlsRowTag("mls-request-decline-", index: index, fixtureID: request.requestID))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain)
    }
    private func confirm(_ kind: MlsAdminConfirmation.Kind, _ row: MlsRequestRow) -> MlsAdminConfirmation {
        MlsAdminConfirmation(kind: kind, display: row.request.display, aiFlag: row.request.aiFlag, groupName: model.info?.name ?? "", expiresAt: row.request.expiresAt)
    }
    private func progressText(_ state: MlsRequestRowState) -> String? {
        switch state {
        case .approving: FeatureMlsGroupsStrings.text("group.requests.approving", locale: locale)
        case .adding: FeatureMlsGroupsStrings.text("group.requests.adding", locale: locale)
        case .declining: FeatureMlsGroupsStrings.text("group.requests.declining", locale: locale)
        case .idle: nil
        }
    }
}
