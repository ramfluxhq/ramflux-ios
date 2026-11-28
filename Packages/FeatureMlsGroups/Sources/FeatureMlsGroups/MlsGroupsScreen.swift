// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign
import RFLocalization

/// The groups list: loading, offline, error with retry, empty (New group, Join with a link), the pending-join row and rows.
public struct MlsGroupsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    let model: MlsGroupsCoordinator
    public init(model: MlsGroupsCoordinator) { self.model = model }
    public var body: some View {
        RFPage {
            VStack(spacing: 0) {
                KitPageHeader(FeatureMlsGroupsStrings.text("group.list.title", locale: locale), large: true, actions: [
                    KitHeaderAction(icon: "plus", label: FeatureMlsGroupsStrings.text("group.list.create", locale: locale), action: { model.openCreateSheet() }),
                    KitHeaderAction(icon: "link", label: FeatureMlsGroupsStrings.text("group.list.join", locale: locale), action: { model.openJoinSheet() })], tag: "mls-groups-header")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.gap) {
                        if !model.list.pendingJoins.isEmpty {
                            HStack(spacing: theme.gap) {
                                ProgressView().controlSize(.small)
                                Text(FeatureMlsGroupsStrings.text("group.join.pending.row", locale: locale)).rfFont(.body)
                            }.accessibilityIdentifier("mls-join-pending-row")
                        }
                        content
                        if model.list.loadingMore { ProgressView().frame(maxWidth: .infinity) }
                    }.padding(.horizontal, theme.gap).padding(.vertical, theme.gap)
                }
                .refreshable { model.refresh() }
                .accessibilityIdentifier("mls-group-list")
            }
        }
        .privacySensitive().rfHidesNavigationBar()
    }
    @ViewBuilder private var content: some View {
        switch model.list.phase {
        case .loading where model.list.rows.isEmpty:
            ProgressView(FeatureMlsGroupsStrings.text("group.list.loading", locale: locale)).frame(maxWidth: .infinity)
        case .failed(let error) where model.list.rows.isEmpty:
            VStack(spacing: theme.gap) {
                Text(error == .offline ? FeatureMlsGroupsStrings.text("group.list.offline", locale: locale) : FeatureMlsGroupsStrings.text("group.list.error", locale: locale)).rfFont(.body)
                Text(MlsChatText.error(error, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).accessibilityIdentifier("mls-list-error")
                KitButton(FeatureMlsGroupsStrings.text("group.list.retry", locale: locale), action: { model.refresh() }, kind: .secondary, tag: "mls-list-retry")
            }.frame(maxWidth: .infinity)
        default:
            if model.list.rows.isEmpty && model.list.phase == .loaded {
                VStack(spacing: theme.gap) {
                    Text(FeatureMlsGroupsStrings.text("group.list.empty", locale: locale)).rfFont(.body)
                    KitButton(FeatureMlsGroupsStrings.text("group.list.create", locale: locale), action: { model.openCreateSheet() }, tag: "mls-group-create")
                    KitButton(FeatureMlsGroupsStrings.text("group.list.join", locale: locale), action: { model.openJoinSheet() }, kind: .secondary, tag: "mls-join-open")
                }.frame(maxWidth: .infinity)
            } else {
                ForEach(model.list.rows) { row in
                    Button { model.open(row.groupID) } label: { MlsGroupRow(row: row) }.buttonStyle(.plain)
                        .accessibilityIdentifier("mls-group-row-" + row.groupID)
                        .onAppear { model.rowAppeared(row.groupID) }
                }
                if case .failed(let error) = model.list.phase {
                    Text(MlsChatText.error(error, locale: locale)).rfFont(.caption).foregroundStyle(theme.danger)
                }
            }
        }
    }
}

struct MlsGroupRow: View {
    let row: MlsGroupInfo
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        HStack(alignment: .top, spacing: theme.gap) {
            KitAvatar(String(row.name.prefix(1)), size: 44, kind: .channel)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(untrusted: row.name).rfFont(.body, weight: .semibold).lineLimit(1)
                    Spacer(minLength: 0)
                    if row.lastActivityAt > 0 {
                        Text(Date(timeIntervalSince1970: TimeInterval(row.lastActivityAt) / 1000).formatted(.relative(presentation: .named).locale(locale))).rfFont(.caption).foregroundStyle(theme.secondary)
                    }
                }
                HStack(spacing: theme.gap / 2) {
                    Text(FeatureMlsGroupsStrings.format("group.list.members", row.members, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                    if row.agents > 0 {
                        KitAIMarker(tag: "mls-row-ai-" + row.groupID)
                        Text(FeatureMlsGroupsStrings.format("group.list.agents", row.agents, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                    }
                }
                if let snippet = row.lastPost?.snippet, !snippet.isEmpty {
                    Text(untrusted: snippet).rfFont(.caption).foregroundStyle(theme.secondary).lineLimit(1)
                } else if row.lastPost != nil {
                    Text(FeatureMlsGroupsStrings.text("group.list.lastPostAttachment", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).lineLimit(1)
                }
            }
            if row.unread > 0 {
                Text(row.unread, format: .number.locale(locale)).rfFont(.caption, weight: .semibold).foregroundStyle(theme.surface_white)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(theme.primary, in: Capsule())
                    .accessibilityLabel(Text(FeatureMlsGroupsStrings.format("group.list.unread", row.unread, locale: locale)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
