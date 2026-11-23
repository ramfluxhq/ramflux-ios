// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
/// The reactions offered in the message action bar (MOB-B03). The SDK accepts any single
/// grapheme of at most 64 bytes without whitespace or controls; the extended set in the reaction
/// sheet stays inside that rule.
enum ChatReactionPalette {
    static let tokens = ["👍", "❤️", "😂", "😮", "😢", "🙏"]
    static let extended = tokens + ["🎉", "👀", "🔥", "👏", "✅", "🤔"]
    static func accepts(_ token: String) -> Bool { extended.contains(token) }
}
