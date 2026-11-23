// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// The 64 short-authentication symbols of the SDK (`ramflux_crypto::custody::pairing::SAS_EMOJI`), in index
/// order. Both devices draw the same glyphs for the seven indices of `device.pair.status`; they are compared
/// symbols, not copy, so they are not localised (VoiceOver reads each glyph's system name).
enum PairingSymbols {
    static let glyphs: [String] = [
        "🐶", "🐱", "🦁", "🐴", "🦄", "🐷", "🐘", "🐰", "🐼", "🐓", "🐧", "🐢", "🐟", "🐙", "🦋", "🌷",
        "🌳", "🌵", "🍄", "🌏", "🌙", "☁️", "🔥", "🍌", "🍎", "🍓", "🌽", "🍕", "🎂", "❤️", "😀", "🤖",
        "🎩", "👓", "🔧", "🎅", "👍", "☂️", "⌛", "⏰", "🎁", "💡", "📕", "✏️", "📎", "✂️", "🔒", "🔑",
        "🔨", "☎️", "🏁", "🚂", "🚲", "✈️", "🚀", "🏆", "⚽", "🎸", "🎺", "🔔", "⚓", "🎧", "📁", "📌",
    ]
    static func glyph(_ index: Int) -> String? { glyphs.indices.contains(index) ? glyphs[index] : nil }
}
