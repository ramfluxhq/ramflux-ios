// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import SwiftUI
import AppData
import RFDesign
import RFLocalization

/// The conversation's media and files (MOB-B29 is not designed yet). The SDK has no media
/// filter (request R10), so the gallery pages the same read model as the timeline, newest
/// first, and keeps only messages' attachments. Each step reads a bounded number of pages; the
/// window holds at most `capacity` items and drops the newest when the user pages further back.
public struct ChatGalleryState: Equatable, Sendable {
    public enum Tab: String, Equatable, Sendable { case media, files }
    public var tab: Tab = .media
    public var media: [AttachmentRecord] = []
    public var files: [AttachmentRecord] = []
    public var loading = false
    /// The read model has no older pages.
    public var exhausted = false
    /// Newer items were dropped to keep the window bounded; "Back to newest" reloads.
    public var detached = false
    public var failure: AppFailure?
    public init() {}
    var ids: Set<String> { Set(media.map(\.id) + files.map(\.id)) }
}

extension ChatViewModel {
    static let galleryPagesPerStep = 8
    static let galleryItemsPerStep = 60
    static let galleryCapacity = 2_000

    func handleGallery(_ action: ChatAction) {
        switch action {
        case .openGallery:
            state.details = nil
            state.gallery = ChatGalleryState(); galleryCursor = nil
            loadGallery()
        case .closeGallery:
            galleryTask?.cancel(); galleryTask = nil
            state.gallery = nil; galleryCursor = nil
            syncMedia()
        case .galleryTab(let tab): state.gallery?.tab = tab
        case .galleryMore: loadGallery()
        default: break
        }
    }

    /// Reads up to `galleryPagesPerStep` pages after the cursor, collecting attachments off the
    /// main thread, then resolves which items are already stored (a local file check).
    func loadGallery() {
        guard var gallery = state.gallery, !gallery.loading, !gallery.exhausted, galleryTask == nil else { return }
        gallery.loading = true; gallery.failure = nil; state.gallery = gallery
        let start = galleryCursor
        let current = epoch
        galleryTask = Task { [weak self, repository, account, conversation] in
            var cursor = start, found: [AttachmentRecord] = [], own: Set<String> = [], exhausted = false, failure: AppFailure?
            for _ in 0..<Self.galleryPagesPerStep {
                switch await repository.messages(account: account, conversation: conversation, before: cursor) {
                case .success(let page):
                    let rows = await Task.detached { page.records.filter { $0.kind != .deleted } }.value
                    found += rows.flatMap(\.attachments)
                    own.formUnion(rows.filter { $0.isOwn == true }.flatMap { $0.attachments.map(\.id) })
                    cursor = page.nextBefore
                    if cursor == nil { exhausted = true }
                case .failure(let error): failure = error
                }
                if failure != nil || exhausted || found.count >= Self.galleryItemsPerStep || Task.isCancelled { break }
            }
            var stored: [String: MediaTransferState] = [:]
            for item in found { if let known = await repository.mediaState(account: account, attachment: item) { stored[item.id] = known } }
            guard let self, self.epoch == current, !Task.isCancelled else { return }
            let sender = await self.resolveTrust()
            guard self.epoch == current, !Task.isCancelled, var next = self.state.gallery else { return }
            self.galleryTask = nil
            next.loading = false; next.failure = failure
            if failure == nil { self.galleryCursor = cursor; next.exhausted = exhausted }
            let known = next.ids
            let fresh = found.filter { !known.contains($0.id) }
            next.media += fresh.filter { $0.kind != .file }
            next.files += fresh.filter { $0.kind == .file }
            let overflow = next.media.count + next.files.count - Self.galleryCapacity
            if overflow > 0 {
                next.detached = true
                let dropMedia = min(overflow, next.media.count)
                next.media.removeFirst(dropMedia); next.files.removeFirst(min(overflow - dropMedia, next.files.count))
            }
            for item in fresh {
                if let known = stored[item.id] { self.state.media[item.id] = known }
                else if self.state.media[item.id] == nil {
                    // Strangers' items stay hidden until tapped, as in the timeline.
                    self.state.media[item.id] = item.isExpired(now: self.now()) ? .expired : (sender == .untrusted && !own.contains(item.id) ? .blockedByPolicy : .idle)
                }
            }
            self.state.gallery = next
        }
    }
}

/// The gallery sheet: Media and Files tabs, a lazy grid and a lazy list; the next step loads
/// when the last item appears. Items download only on tap.
struct ChatGallerySheet: View {
    let gallery: ChatGalleryState
    let states: [String: MediaTransferState]
    let revealed: Set<String>
    let onAction: (ChatAction) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.rfTheme) private var theme
    var body: some View {
        RFPage { VStack(alignment: .leading, spacing: theme.gap) {
            HStack {
                Text(FeatureChatStrings.text("chat.gallery.title", locale: locale)).rfFont(.page)
                Spacer()
                Button(FeatureChatStrings.text("chat.details.close", locale: locale)) { onAction(.closeGallery) }
            }
            Picker(FeatureChatStrings.text("chat.gallery.title", locale: locale), selection: Binding(get: { gallery.tab }, set: { onAction(.galleryTab($0)) })) {
                Text(FeatureChatStrings.text("chat.gallery.media", locale: locale)).tag(ChatGalleryState.Tab.media)
                Text(FeatureChatStrings.text("chat.gallery.files", locale: locale)).tag(ChatGalleryState.Tab.files)
            }
            .pickerStyle(.segmented)
            if gallery.detached { Button(FeatureChatStrings.text("chat.gallery.newest", locale: locale)) { onAction(.openGallery) }.rfFont(.caption) }
            if let failure = gallery.failure { RFFailureView(title: failure.title(locale: locale), message: failure.message(locale: locale)) }
            ScrollView {
                if gallery.tab == .media {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: ChatMediaText.albumCell), spacing: theme.gap / 2)], spacing: theme.gap / 2) {
                        ForEach(gallery.media) { item in
                            MediaTile(attachment: item, state: states[item.id] ?? .idle, revealed: revealed.contains(item.id), compact: true, onAction: onAction)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius_md))
                                .onAppear { if item.id == gallery.media.last?.id { onAction(.galleryMore) } }
                        }
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: theme.gap / 2) {
                        ForEach(gallery.files) { item in
                            MediaAttachmentView(attachment: item, state: states[item.id] ?? .idle, revealed: true, isOwn: false, time: nil, onAction: onAction)
                                .onAppear { if item.id == gallery.files.last?.id { onAction(.galleryMore) } }
                        }
                    }
                }
                if gallery.loading { ProgressView(FeatureChatStrings.text("chat.loading", locale: locale)).padding(theme.gap) }
                else if gallery.exhausted && (gallery.tab == .media ? gallery.media.isEmpty : gallery.files.isEmpty) {
                    RFUnavailableView(title: FeatureChatStrings.text("chat.gallery.empty", locale: locale), message: "")
                } else if !gallery.exhausted {
                    Button(FeatureChatStrings.text("chat.gallery.more", locale: locale)) { onAction(.galleryMore) }.rfFont(.caption).padding(theme.gap)
                }
            }
        }.padding(theme.gap) }
    }
}
