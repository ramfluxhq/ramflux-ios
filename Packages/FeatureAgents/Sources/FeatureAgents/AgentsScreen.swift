// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization
public struct AgentsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    public let state: AgentsState
    public let onAction: (AgentsAction) -> Void
    public init(state: AgentsState, onAction: @escaping (AgentsAction) -> Void) { self.state = state; self.onAction = onAction }
    private func copy(_ key: String) -> String { FeatureAgentsStrings.text("agents." + key, locale: locale) }
    private var showingDirectory: Bool { state.failure == nil && !state.loading && !state.entries.isEmpty }
    public var body: some View {
        RFPage {
            switch state.mode {
            case .directory: directory
            case .profile(let id): detail(id, editing: false)
            case .edit(let id): detail(id, editing: true)
            }
        }
        .rfHidesNavigationBar()
        .privacySensitive()
        .confirmationDialog(copy(state.confirmingDelete ? "remove" : "edit"), isPresented: Binding(get: { state.confirmingDelete || state.confirmingEdit }, set: { if !$0 { onAction(.cancelConfirmation) } }), titleVisibility: .visible) {
            if state.confirmingDelete { Button(copy("remove"), role: .destructive) { onAction(.confirmDelete) } }
            if state.confirmingEdit { Button(copy("save")) { onAction(.confirmSave) } }
            Button(copy("cancel"), role: .cancel) { onAction(.cancelConfirmation) }
        } message: { Text(copy(state.confirmingDelete ? "remove.confirm" : "edit.confirm")) }
    }
    private var directory: some View {
        VStack(spacing: 0) {
            KitPageHeader(AppTab.agents.title(locale: locale), large: true, tag: "agents-header")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.gap) {
                    if state.loading { ProgressView(copy("loading")).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, theme.gap) }
                    if let failure = state.failure {
                        RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) { onAction(.retry) }
                            .padding(.horizontal, theme.gap)
                    }
                    if let creation = state.creation { creationCard(creation).padding(.horizontal, theme.gap) }
                    if showingDirectory || !state.query.isEmpty {
                        KitSearchField(value: Binding(get: { state.query }, set: { onAction(.query($0)) }), placeholder: copy("search"), tag: "agents-search")
                            .padding(.horizontal, theme.gap)
                        if state.entries.isEmpty {
                            searchMiss.padding(.horizontal, theme.gap)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(state.entries) { entry in
                                    KitConversationRow(entry.name, preview: entry.detail, time: "", tag: "agent-" + entry.id, action: { onAction(.mode(.profile(entry.id))) }) {
                                        KitAvatar("", size: 44, kind: .agent, icon: entry.icon, tag: entry.id + "-avatar")
                                    }
                                    .onAppear { if entry.id == state.entries.last?.id && state.canLoadMore { onAction(.loadMore) } }
                                }
                            }
                            if state.loadingMore { ProgressView(copy("loadingMore")).padding(.horizontal, theme.gap) }
                            Text(copy("directory.note")).rfFont(.caption).foregroundStyle(theme.secondary).padding(.horizontal, theme.gap).padding(.top, 12)
                            multiAgentLink.padding(.top, 12)
                        }
                    } else if state.failure == nil && !state.loading {
                        KitTipBar(copy("desktop"), icon: "info", tag: "agents-desktop").padding(.horizontal, theme.gap)
                        noAgents.padding(.horizontal, theme.gap)
                    }
                }
                .padding(.vertical, theme.gap)
                .frame(maxWidth: theme.column_max, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }
    private func detail(_ id: String, editing: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.gap) {
                KitPageHeader(copy(editing ? "edit" : "profile"), onBack: { onAction(.mode(editing ? .profile(id) : .directory)) }, tag: "agent-header")
                if state.loading { ProgressView(copy("loading")) }
                if let agent = state.selected, agent.id == id {
                    if editing {
                        KitTextField(value: Binding(get: { state.draft.name }, set: { onAction(.draftName($0)) }), label: copy("name"), tag: "agent-name")
                        KitTextField(value: Binding(get: { state.draft.responsibility }, set: { onAction(.draftResponsibility($0)) }), label: copy("goal"), tag: "agent-responsibility")
                        KitButton(copy("save"), action: { onAction(.save) }, enabled: !state.busy, loading: state.busy, tag: "agent-save")
                    } else {
                        HStack(spacing: 12) {
                            KitAvatar("", size: 52, kind: .agent, icon: KitAgentIcon.name(agent.persona.avatar), tag: "agent-avatar")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(untrusted: agent.persona.name.isEmpty ? agent.id : agent.persona.name).rfFont(.page)
                                KitIdentifierText(agent.id, color: theme.secondary, tag: "agent-anchor").textSelection(.enabled)
                            }
                        }
                        if !agent.persona.responsibility.isEmpty {
                            Text(copy("goal")).rfFont(.caption).foregroundStyle(theme.secondary)
                            Text(untrusted: agent.persona.responsibility, kind: .messageBody)
                        }
                        KitButton(copy("multi"), action: { onAction(.chat(agent.id)) }, tag: "agent-chat")
                        KitButton(copy("edit"), action: { onAction(.mode(.edit(agent.id))) }, kind: .secondary, enabled: !state.busy, tag: "agent-edit")
                        Text(copy("access")).rfFont(.body, weight: .semibold)
                        KitRow(copy("access.dm"), value: AppDataStrings.status(agent.access.dm, locale: locale), trailing: .none, tag: "agent-access-dm")
                        KitRow(copy("access.groups"), value: AppDataStrings.status(agent.access.groupInviters, locale: locale), trailing: .none, tag: "agent-access-groups")
                        KitButton(copy("access.change"), action: { onAction(.unavailable(.access)) }, kind: .secondary, tag: "agent-access-change")
                        KitButton(copy("remove"), action: { onAction(.delete) }, kind: .destructive, enabled: !state.busy, tag: "agent-remove")
                    }
                }
                if let failure = state.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            }
            .padding(theme.gap)
            .frame(maxWidth: theme.column_max, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
    private func creationCard(_ creation: AgentCreationRequest) -> some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            Text(copy("creation.title")).rfFont(.body, weight: .semibold)
            Text(copy("creation.message")).rfFont(.caption).foregroundStyle(theme.secondary)
            KitIdentifierText(creation.id, color: theme.secondary, tag: "agent-creation-id")
            if let expires = creation.expiresAt {
                LabeledContent(copy("creation.expires"), value: Date(timeIntervalSince1970: TimeInterval(expires > 100_000_000_000 ? expires / 1000 : expires)).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)))
            }
            HStack(spacing: theme.gap) {
                KitButton(copy("creation.decline"), action: { onAction(.unavailable(.creationDecision)) }, kind: .secondary, tag: "agent-creation-decline")
                KitButton(copy("creation.approve"), action: { onAction(.unavailable(.creationDecision)) }, tag: "agent-creation-approve")
            }
        }
        .padding(theme.gap)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radius_card))
    }
    private var noAgents: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            KitStatusHero(icon: "bot", tag: "agents-none")
            Text(copy("none.title")).rfFont(.body, weight: .semibold)
            Text(copy("none.message")).rfFont(.caption).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
    private var multiAgentLink: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                KitIcon(name: "users-round", size: 20, tint: theme.text)
                Text(copy("multi"))
                    .rfFont(.size(theme.size_mobile_body), weight: .medium)
                    .foregroundStyle(theme.text)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, theme.gap)
        .accessibilityIdentifier("agents-multi")
    }

    private var searchMiss: some View {
        VStack(alignment: .leading, spacing: theme.gap) {
            KitStatusHero(icon: "search-x", tag: "agents-empty")
            Text(copy("empty.title")).rfFont(.body, weight: .semibold)
            Text(copy("empty.message")).rfFont(.caption).foregroundStyle(theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
