// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation

/// One in-app banner: a new incoming message announced by a view the app draws itself while it is in the
/// foreground. It lives in memory only and is never logged, restored, donated or posted as a system
/// notification. Its text is redacted from every description, so interpolating it prints nothing.
public struct InAppBanner: Identifiable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// What the banner may say when it is not generic. Only a user text message carries a preview.
    public enum Content: Sendable, Equatable, CustomStringConvertible {
        /// A user text message; `preview` is one sanitised line of at most `InAppBannerFeed.previewLimit` characters.
        case text(preview: String)
        /// A call record: fixed text.
        case call
        /// Anything else (media, deleted, unsupported, system events): fixed text.
        case other
        public var description: String { "InAppBanner.Content" }
    }
    public let id: UUID
    public let account: String
    public let conversation: String
    /// The route that opens the conversation, the same one the inbox row uses.
    public let route: AppRoute
    /// The conversation's display name: the peer for a direct conversation, the group name for a group.
    public let sender: String
    public let content: Content
    public init(id: UUID = UUID(), account: String, conversation: String, route: AppRoute, sender: String, content: Content) {
        self.id = id; self.account = account; self.conversation = conversation; self.route = route; self.sender = sender; self.content = content
    }
    public var description: String { "InAppBanner" }
    public var debugDescription: String { description }
}

/// Raises an `InAppBanner` for a message that arrives while the app is in the foreground, driven by the same
/// shared event source and conversation directory the inbox and `MessageNotifier` use: on every invalidation
/// it reads the first directory page and compares unread counts with the previous read, then reads the
/// newest message of the conversation that rose. Rules: nothing for the conversation that is open, for a
/// muted conversation, or for an own message. Limits of the pinned SDK are the notifier's: the directory is
/// ordered by conversation id and the first `window` conversations are watched. In a group the directory
/// has no per-sender name, so the group name is the banner's title.
@MainActor public final class InAppBannerFeed {
    public nonisolated static let previewLimit = 80
    public static let defaultWindow = 100
    private let conversations: any ConversationsRepository
    private let chat: any ChatRepository
    private let window: Int
    private let isOpen: @MainActor (String) -> Bool
    private let deliver: @MainActor (InAppBanner) -> Void
    private var account: String?
    private var foreground = true
    private var previous: [String: UInt]?
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    /// `isOpen` answers whether a conversation id is the one on screen; `deliver` receives each banner.
    public init(conversations: any ConversationsRepository, chat: any ChatRepository, window: Int = InAppBannerFeed.defaultWindow,
                isOpen: @escaping @MainActor (String) -> Bool, deliver: @escaping @MainActor (InAppBanner) -> Void) {
        self.conversations = conversations; self.chat = chat; self.window = window; self.isOpen = isOpen; self.deliver = deliver
    }
    /// Follows `account` (nil stops). Following the same account while it runs does nothing.
    public func follow(account: String?) {
        guard account != self.account || (account != nil && task == nil) else { return }
        generation &+= 1; task?.cancel(); task = nil; previous = nil
        self.account = account
        guard let account else { return }
        let current = generation
        task = Task { [weak self, conversations] in
            let observation = await conversations.observe(account: account)
            for await update in observation.stream {
                guard !Task.isCancelled, let self, self.generation == current else { break }
                guard case .invalidated = update else { break }
                await self.read(account: account, generation: current)
            }
            await observation.stop()
            // The stream ended (a failure, or the source closed): follow again after a short pause, unless
            // the account changed or following was stopped meanwhile.
            guard let self, self.generation == current else { return }
            self.task = nil
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self.generation == current, self.task == nil else { return }
            self.follow(account: account)
        }
    }
    /// Banners are raised only while the app is in the foreground and active. Unread counts keep being tracked
    /// otherwise, so a message that arrived meanwhile never produces a banner on return.
    public func setForeground(_ value: Bool) {
        foreground = value
        // A return to the foreground also restarts a feed whose stream ended while the app was away.
        if value, let account, task == nil { follow(account: account) }
    }

    private func read(account: String, generation current: UInt64) async {
        guard case .success(let page) = await conversations.page(account: account, cursor: nil, limit: window), self.generation == current else { return }
        let before = previous
        previous = Dictionary(page.rows.map { ($0.id, $0.unreadCount ?? 0) }, uniquingKeysWith: { first, _ in first })
        guard foreground, let before else { return }
        guard let row = Self.candidate(previous: before, rows: page.rows), !isOpen(row.id) else { return }
        let content = await newest(account: account, conversation: row.id)
        // The user may have opened the conversation, left the foreground or switched account while the read ran.
        guard self.generation == current, foreground, !isOpen(row.id), let content else { return }
        deliver(InAppBanner(account: account, conversation: row.id, route: row.route, sender: row.title, content: content))
    }
    /// The audible conversation whose unread count rose most recently (the newest activity wins).
    nonisolated static func candidate(previous: [String: UInt], rows: [ConversationRecord]) -> ConversationRecord? {
        rows.filter { !$0.muted && ($0.unreadCount ?? 0) > (previous[$0.id] ?? 0) }.max { ($0.lastActivity ?? .min) < ($1.lastActivity ?? .min) }
    }
    /// The banner content for the conversation's newest message; nil for an own message. A failed read still
    /// raises a banner with the fixed text, because the unread count rose.
    private func newest(account: String, conversation: String) async -> InAppBanner.Content? {
        guard case .success(let page) = await chat.messages(account: account, conversation: conversation, before: nil), let record = page.records.first else { return .other }
        if record.isOwn == true { return nil }
        switch record.kind {
        case .text(let text):
            guard record.attachments.isEmpty, let line = Self.line(text) else { return .other }
            return .text(preview: line)
        case .callHistory: return .call
        case .deleted, .unsupported: return .other
        }
    }
    /// One line of at most `previewLimit` characters: control characters, newlines and line or paragraph
    /// separators become spaces, bidirectional override and isolate controls are dropped, runs of spaces
    /// collapse and the ends are trimmed. Nil when nothing is left.
    nonisolated static func line(_ text: String) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value) { continue }
            let spacing = CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) || scalar.properties.isWhitespace
            scalars.append(spacing ? " " : scalar)
        }
        let collapsed = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(previewLimit)).trimmingCharacters(in: .whitespaces)
    }
}
