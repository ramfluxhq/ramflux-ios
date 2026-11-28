// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign

/// Members: a lazy list that pages in 20 rows before the end, role headers, the AI marker from `ai_flag`, "You", "Member"
/// for a null name, devices, an error row with "Try again" (the only retry), and search with a progress line.
public struct MlsMembersScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Bindable var model: MlsGroupModel
    public init(model: MlsGroupModel) { self.model = model }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            KitPageHeader(FeatureMlsGroupsStrings.text("group.members.title", locale: locale), tag: "mls-members-header")
            KitSearchField(value: $model.search, placeholder: FeatureMlsGroupsStrings.text("group.members.search", locale: locale), tag: "mls-members-search").padding(.horizontal, theme.gap)
            if model.members.loadingAll && !model.search.isEmpty {
                Text(FeatureMlsGroupsStrings.format("group.members.loadingAll", model.members.rows.count, model.info?.members ?? model.members.rows.count, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary).padding(.horizontal, theme.gap).accessibilityIdentifier("mls-members-progress")
            }
            ScrollView { LazyVStack(alignment: .leading, spacing: theme.gap) {
                ForEach(sections, id: \.0) { section in
                    Text(FeatureMlsGroupsStrings.text(section.0, locale: locale)).rfFont(.caption, weight: .semibold).foregroundStyle(theme.secondary).padding(.top, theme.gap)
                    ForEach(section.1) { member in row(member).onAppear { model.memberAppeared(member.anchor) } }
                }
                if model.filteredMembers.isEmpty, model.members.phase == .done, !model.members.loadingAll { Text(FeatureMlsGroupsStrings.text("group.members.noResults", locale: locale)).rfFont(.body).foregroundStyle(theme.secondary) }
                switch model.members.phase {
                case .loading: ProgressView().frame(maxWidth: .infinity)
                case .pageError:
                    HStack(spacing: theme.gap) {
                        Text(FeatureMlsGroupsStrings.text("group.members.pageError", locale: locale)).rfFont(.caption).foregroundStyle(theme.danger)
                        Button(FeatureMlsGroupsStrings.text("group.list.retry", locale: locale)) { model.retryMembers() }.rfFont(.caption).accessibilityIdentifier("mls-members-retry")
                    }.accessibilityIdentifier("mls-members-error")
                default: EmptyView()
                }
            }.padding(.horizontal, theme.gap) }.accessibilityIdentifier("mls-members-list")
        } }
        .task { model.start(); model.openMembers() }
        .onDisappear { model.stop() }
        .onChange(of: model.search) { _, _ in model.searchChanged() }
    }
    private var sections: [(String, [MlsMemberRow])] {
        let rows = model.filteredMembers
        let parts: [(String, [MlsMemberRow])] = [("group.members.section.owner", rows.filter { $0.role == .owner }), ("group.members.section.admins", rows.filter { $0.role == .admin }), ("group.members.section.members", rows.filter { $0.role != .owner && $0.role != .admin })]
        return parts.filter { !$0.1.isEmpty }
    }
    private func row(_ member: MlsMemberRow) -> some View {
        HStack(spacing: theme.gap) {
            KitAvatar(String(MlsChatText.displayName(MlsAuthor(anchor: member.anchor, display: member.display, isMe: member.isMe), locale: locale).prefix(1)), size: 36, kind: member.aiFlag ? .agent : .person)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: theme.gap / 2) {
                    if member.isMe { Text(FeatureMlsGroupsStrings.text("group.members.you", locale: locale)).rfFont(.body) }
                    else if let display = member.display, !display.isEmpty { Text(untrusted: display).rfFont(.body) }
                    else { Text(FeatureMlsGroupsStrings.text("group.member.unnamed", locale: locale)).rfFont(.body).foregroundStyle(theme.secondary) }
                    if member.aiFlag { KitAIMarker(tag: "mls-member-ai") }
                }
                Text(FeatureMlsGroupsStrings.format("group.members.devices", member.devices, locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
