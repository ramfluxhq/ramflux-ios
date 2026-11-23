// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import Observation
import AppData
import RFDesign
import RFLocalization

/// Media storage of one account on this device (MOB-B30 is not designed yet): downloaded
/// originals and files waiting to be sent, measured by the repository, with "clear downloaded
/// media" behind a confirmation. Staged files of queued sends are never cleared here. The host
/// (settings) presents it; per-conversation storage is in the chat's details sheet.
public struct MediaStorageState: Equatable, Sendable {
    public var usage: MediaUsage?
    public var confirming = false
    public var clearing = false
    public init(usage: MediaUsage? = nil) { self.usage = usage }
}
public enum MediaStorageAction: Equatable, Sendable { case appeared, clearRequested, clearCancelled, clearConfirmed }

@Observable @MainActor public final class MediaStorageViewModel {
    public private(set) var state = MediaStorageState()
    private let repository: any ChatRepository
    private let account: String
    @ObservationIgnored private var task: Task<Void, Never>?
    public init(repository: any ChatRepository, account: String) { self.repository = repository; self.account = account }
    public func send(_ action: MediaStorageAction) {
        switch action {
        case .appeared: measure()
        case .clearRequested: state.confirming = true
        case .clearCancelled: state.confirming = false
        case .clearConfirmed:
            guard state.confirming, !state.clearing else { return }
            state.confirming = false; state.clearing = true
            task = Task { [weak self, repository, account] in
                await repository.purgeAccountMedia(account: account)
                let usage = await repository.mediaUsage(account: account)
                guard let self else { return }
                self.state.clearing = false; self.state.usage = usage
            }
        }
    }
    private func measure() {
        task = Task { [weak self, repository, account] in
            let usage = await repository.mediaUsage(account: account)
            self?.state.usage = usage
        }
    }
    public func settle() async { await task?.value }
}

public struct MediaStorageScreen: View {
    let state: MediaStorageState
    let onAction: (MediaStorageAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    public init(state: MediaStorageState, onAction: @escaping (MediaStorageAction) -> Void) { self.state = state; self.onAction = onAction }
    public var body: some View {
        RFPage { VStack(spacing: 0) {
            KitPageHeader(FeatureChatStrings.text("chat.storage.title", locale: locale), onBack: { dismiss() }, tag: "media-storage-header")
            ScrollView { VStack(alignment: .leading, spacing: theme.gap) {
            if let usage = state.usage {
                KitRow(FeatureChatStrings.text("chat.storage.downloaded", locale: locale), icon: "image-down", value: bytes(usage.originals), trailing: .none)
                KitRow(FeatureChatStrings.text("chat.storage.waiting", locale: locale), icon: "clock-3", value: bytes(usage.outbox), trailing: .none)
                Text(FeatureChatStrings.text("chat.storage.policy", locale: locale)).rfFont(.caption).foregroundStyle(theme.secondary)
                if state.confirming {
                    Text(FeatureChatStrings.text("chat.storage.clearFact", locale: locale)).rfFont(.caption)
                    HStack(spacing: theme.gap) {
                        KitButton(FeatureChatStrings.text("chat.composer.cancel", locale: locale), action: { onAction(.clearCancelled) }, kind: .secondary, tag: "media-storage-cancel")
                        KitButton(FeatureChatStrings.text("chat.storage.clear", locale: locale), action: { onAction(.clearConfirmed) }, kind: .destructive, tag: "media-storage-confirm")
                    }
                } else {
                    KitButton(FeatureChatStrings.text("chat.storage.clearAll", locale: locale), action: { onAction(.clearRequested) }, kind: .destructive, enabled: usage.originals > 0 && !state.clearing, loading: state.clearing, tag: "media-storage-clear")
                }
            } else {
                ProgressView(FeatureChatStrings.text("chat.loading", locale: locale))
            }
        }.padding(theme.gap) } } }
        .onAppear { onAction(.appeared) }
        .privacySensitive().rfHidesNavigationBar()
    }
    private func bytes(_ value: Int64) -> String { value.formatted(.byteCount(style: .file).locale(locale)) }
}

/// Hosts the account's media storage page for a route; the view model lives as long as the page.
public struct MediaStorageHost: View {
    @State private var model: MediaStorageViewModel
    public init(repository: any ChatRepository, account: String) { _model = State(initialValue: MediaStorageViewModel(repository: repository, account: account)) }
    public var body: some View { MediaStorageScreen(state: model.state, onAction: model.send) }
}
