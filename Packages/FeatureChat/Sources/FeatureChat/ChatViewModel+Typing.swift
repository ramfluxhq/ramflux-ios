// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import AppData

/// Peers' typing indicator from `message.transient`: shown while at least one peer device has an
/// unexpired start; a stop, the expiry or leaving the chat hides it. Own devices are ignored.
extension ChatViewModel {
    func followTyping() {
        guard typingTask == nil else { return }
        let current = epoch
        typingTask = Task { [weak self, repository, account, conversation] in
            let stream = await repository.typing(account: account, conversation: conversation)
            for await event in stream {
                guard let self, self.epoch == current, !Task.isCancelled else { break }
                self.apply(event)
            }
        }
    }

    func stopTyping() {
        typingTask?.cancel(); typingTask = nil; typingExpiry?.cancel(); typingExpiry = nil
        typingPeers = [:]; state.peerTyping = false
    }

    private func apply(_ event: TypingEvent) {
        let own = Set(state.messages.lazy.filter { $0.isOwn == true }.compactMap(\.authorAnchor))
        guard !own.contains(event.author) else { return }
        let nowSeconds = Int64(now().timeIntervalSince1970)
        if event.active && event.expiresAt > nowSeconds { typingPeers[event.author] = min(event.expiresAt, nowSeconds + Self.typingCap) } else { typingPeers[event.author] = nil }
        refreshTyping()
    }

    /// Drops expired peers and schedules the next expiry.
    private func refreshTyping() {
        let nowSeconds = Int64(now().timeIntervalSince1970)
        typingPeers = typingPeers.filter { $0.value > nowSeconds }
        state.peerTyping = !typingPeers.isEmpty
        typingExpiry?.cancel(); typingExpiry = nil
        guard let next = typingPeers.values.min() else { return }
        let current = epoch
        typingExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next - nowSeconds)))
            guard !Task.isCancelled, let self, self.epoch == current else { return }
            self.refreshTyping()
        }
    }
    /// A start is honoured for at most this many seconds without a renewal.
    static let typingCap: Int64 = 15
}
