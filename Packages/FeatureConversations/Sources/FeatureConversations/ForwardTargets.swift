// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import Observation
import AppData
import RFDesign

/// A conversation chosen as the target of a forwarded message: the conversation id and, for a
/// group, its SDK `group_id`.
public struct ForwardTarget: Equatable, Sendable {
    public let conversation: String
    public let groupID: String?
    public init(conversation: String, groupID: String?) { self.conversation = conversation; self.groupID = groupID }
}

public struct ForwardTargetsState: Equatable, Sendable {
    public var rows: [ConversationRecord] = []
    public var loading = false
    public var loadingMore = false
    public var canLoadMore = false
    public var failure: AppFailure?
    public init() {}
}

/// The conversation picker for forwarding: the same bounded, cursor-following directory window as
/// the inbox (`ConversationsWindow`), without search or live updates. The source conversation is left out.
@Observable @MainActor public final class ForwardTargetsViewModel {
    public private(set) var state = ForwardTargetsState()
    private let repository: any ConversationsRepository
    private let account: String
    private let excluding: String
    @ObservationIgnored private var window = ConversationsWindow()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    public init(repository: any ConversationsRepository, account: String, excluding: String) {
        self.repository = repository; self.account = account; self.excluding = excluding
    }
    public func appeared(locale: Locale) {
        generation &+= 1; let current = generation; work?.cancel()
        state.loading = true; state.failure = nil
        work = Task { [weak self, repository, account] in
            let result = await Task.detached { await ConversationsWindow.load(repository, account: account, pages: 1, locale: locale, now: Date()) }.value
            guard let self, !Task.isCancelled, self.generation == current else { return }
            self.state.loading = false; self.apply(result)
        }
    }
    public func loadMore(locale: Locale) {
        guard window.canLoadMore, !state.loading, !state.loadingMore else { return }
        state.loadingMore = true; let current = generation; let window = self.window
        work = Task { [weak self, repository, account] in
            let result = await Task.detached { await window.appending(repository, account: account, locale: locale, now: Date()) }.value
            guard let self, !Task.isCancelled, self.generation == current else { return }
            self.state.loadingMore = false; self.apply(result)
        }
    }
    public func target(_ id: String) -> ForwardTarget? {
        state.rows.first { $0.id == id }.map { ForwardTarget(conversation: $0.id, groupID: $0.groupID) }
    }
    public func disappeared() { generation &+= 1; work?.cancel(); work = nil; window = ConversationsWindow(); state = ForwardTargetsState() }
    public func settle() async { await work?.value }
    private func apply(_ result: RepositoryResult<ConversationsWindow>) {
        switch result {
        case .failure(let failure): state.failure = failure
        case .success(let next):
            window = next; state.failure = nil
            state.rows = next.rows.filter { $0.id != excluding }; state.canLoadMore = next.canLoadMore
        }
    }
    deinit { work?.cancel() }
}

/// Presents the picker; `onPick` receives the chosen target, `onCancel` closes without one.
public struct ForwardTargetsScreen: View {
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @State private var model: ForwardTargetsViewModel
    private let onPick: (ForwardTarget) -> Void
    private let onCancel: () -> Void
    public init(repository: any ConversationsRepository, account: String, excluding: String, onPick: @escaping (ForwardTarget) -> Void, onCancel: @escaping () -> Void) {
        _model = State(initialValue: ForwardTargetsViewModel(repository: repository, account: account, excluding: excluding))
        self.onPick = onPick; self.onCancel = onCancel
    }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            KitPageHeader(FeatureConversationsStrings.text("conversations.forward.title", locale: locale), onBack: onCancel, tag: "forward-header")
            if model.state.rows.isEmpty {
                if let failure = model.state.failure {
                    RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) { model.appeared(locale: locale) }.padding(theme.gap)
                } else if model.state.loading {
                    ProgressView(FeatureConversationsStrings.text("conversations.loading", locale: locale)).padding(theme.gap)
                } else {
                    Text(FeatureConversationsStrings.text("conversations.forward.empty", locale: locale)).foregroundStyle(theme.secondary).padding(theme.gap)
                }
                Spacer(minLength: 0)
            } else {
                ScrollView { LazyVStack(spacing: 0) {
                    ForEach(model.state.rows) { row in
                        KitConversationRow(row.title, preview: "", time: "", tag: "forward-" + row.id, action: { if let target = model.target(row.id) { onPick(target) } }) {
                            KitAvatar(String(row.title.prefix(1)), size: 44, kind: .person, icon: "orbit", tag: "forward-" + row.id + "-avatar")
                        }
                        .onAppear { if row.id == model.state.rows.last?.id { model.loadMore(locale: locale) } }
                    }
                    if model.state.loadingMore { ProgressView(FeatureConversationsStrings.text("conversations.loadingMore", locale: locale)).padding(theme.gap) }
                } }
            }
        } }
        .onAppear { model.appeared(locale: locale) }
        .onDisappear { model.disappeared() }
        .privacySensitive()
    }
}
