// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain

/// Which hand-drawn Kit icons mirror under a right-to-left layout.
///
/// This table is the only place that decides mirroring: `KitIcon` applies it, and no screen
/// can flip an icon by hand. Directional glyphs (back, disclosure, reply, forward, incoming
/// call, checklists whose marks lead the lines) mirror. Glyphs that depict time, media
/// transport, vertical movement, symmetric marks or brands do not: `play`, `pause`,
/// `check`, `check-check`, `clock-3`, `timer`, `history`, `refresh-cw`, `arrow-up`,
/// `arrow-down`, `plus`, `x`, `qr-code`, `loader-circle`, charts. The send control uses
/// `arrow-up`, which is vertically symmetric, so its placement mirrors with the layout
/// while the glyph does not change. Message bubble tails (`message-square`,
/// `message-circle`) stay unmirrored until design decides otherwise.
public enum KitIconMirroring {
    public static let mirrored: Set<String> = [
        "chevron-left",
        "chevron-right",
        "reply",
        "forward",
        "phone-incoming",
        "list-checks",
    ]

    public static func mirrorsInRightToLeft(_ name: String) -> Bool { mirrored.contains(name) }
}
