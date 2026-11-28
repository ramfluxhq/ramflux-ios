// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import FeatureChat
import RFDesign

/// The group chat: the shared chat screen driven by `MlsGroupChatModel`.
public struct MlsGroupChatHost: View {
    let model: MlsGroupChatModel
    public init(model: MlsGroupChatModel) { self.model = model }
    public var body: some View {
        ChatScreen(state: model.state, onAction: model.send)
            .onAppear { model.send(.appeared) }
            .onDisappear { model.send(.disappeared) }
    }
}

/// The MLS groups module: the list with its sheets, and the chat, info and members screens it opens. It owns no call; the
/// account's `MlsGroupSession` does.
public struct MlsGroupsHost: View {
    @Bindable var model: MlsGroupsCoordinator
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public init(model: MlsGroupsCoordinator) { self.model = model }
    public var body: some View {
        NavigationStack(path: $model.path) {
            MlsGroupsScreen(model: model)
                .navigationDestination(for: MlsRoute.self) { route in
                    switch route {
                    case .chat(let group): MlsGroupChatHost(model: model.chat(group))
                    case .info(let group): MlsGroupInfoScreen(model: model.detail(group), onMembers: { model.path.append(.members(group)) }, onInvites: { model.sheet = .invite(group: group, fromCreate: false) })
                    case .members(let group): MlsMembersScreen(model: model.detail(group))
                    }
                }
        }
        .task { model.start() }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .create: MlsCreateSheet(model: model)
            case .join: MlsJoinSheet(model: model)
            case .invite(let group, let fromCreate): MlsInvitePanel(model: model.detail(group)) { model.inviteClosed(group: group, fromCreate: fromCreate) }
            case .hostNotice(let host): HostNotice(host: host) { model.sheet = nil }
            }
        }
    }
}

/// The one-time notice after a create: the group's server can see the network address.
struct HostNotice: View {
    let host: String
    let onClose: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        RFPage { VStack(alignment: .leading, spacing: theme.gap) {
            Text(FeatureMlsGroupsStrings.text("group.notice.hostIp.title", locale: locale)).rfFont(.page)
            Text(FeatureMlsGroupsStrings.sentence("group.notice.hostIp.body", [.untrusted(host)], locale: locale)).rfFont(.body)
            KitButton(FeatureMlsGroupsStrings.text("group.notice.hostIp.ok", locale: locale), action: onClose, tag: "mls-host-notice-ok")
        }.padding(theme.gap) }
    }
}
