# Bundled design fonts

The variable fonts in RFDesign/Resources/Fonts originate from the
Google Fonts repository, under ofl/notosanssc, ofl/hankengrotesk and ofl/jetbrainsmono.
Each asset ships with its SIL Open Font License; PROVENANCE.json records its SHA-256.
Hanken Grotesk and JetBrains Mono are the upstream variable files.
Noto Sans SC is a glyph subset of the upstream variable file. The wght axis
(100-900) and the face names stay. The non-CJK ranges from the earlier subset
stay (ASCII, Latin, punctuation, kana, CJK punctuation, compatibility
ideographs, and fullwidth forms). CJK Unified Ideographs cover the 8105
characters of the 2013 Table of General Standard Chinese Characters
(通用规范汉字表, State Council of the PRC, 国发〔2013〕23号, promulgated
2013-06-05), listed in scripts/tongyong-8105.txt, plus every zh-CN catalog
character. The list is levels 1, 2 and 3, in that order, from
https://github.com/shengdoushi/common-standard-chinese-characters-table.
scripts/check-zh-font-glyphs.py fails when one of those characters is missing.
Characters outside that set may use the platform fallback. PROVENANCE.json
records the subset method.
The resource names preserve the original font metadata and copyright notices.
Registration and resolution checks use the actual PostScript names, including the
Noto Sans SC variable regular instance. Font assets never come from a device cache.

## Face per script

Kit text never forces a bundled face on text that face cannot draw. `KitTypeface`
(Packages/RFDesign/Sources/Kit/KitType.swift) chooses the face from the text and
the active locale; callers name only a role (UI, Latin, mono). Feature screens never pass
the Latin role or `latin: true` for translatable text; the Latin role is used only inside
the Kit for times and for Kit masters that reproduce the design.

| Text | Face |
|---|---|
| Latin and Simplified Chinese UI text | Noto Sans SC subset, as the design specifies |
| Latin role (message times inside the Kit; Kit masters that reproduce the design's Latin labels) | Hanken Grotesk |
| UI text in a Latin-script locale whose exemplar letters the Noto Sans SC subset lacks (French œ, Turkish ğ ı ş, Vietnamese) | Hanken Grotesk for all UI text of that locale, so one screen keeps one face |
| Identifiers and code | JetBrains Mono |
| Text with a letter no bundled face draws: Arabic, Hebrew, Cyrillic, Greek, Hangul, Devanagari, Thai, ideographs outside the subset | System font |
| CJK text (ideographs, kana, hangul) under Traditional Chinese, Japanese or Korean locales | System font, which uses the locale's Han glyph forms |
| Editable text (fields, composer) | Bundled face for Latin and Simplified Chinese locales whose letters it covers, system font otherwise |
| Screen text outside the Kit | `rfFont(.body / .caption / .page / .size(token) / .fixed(token), weight:)`, same rule by locale; it is the only font API for screens (the former bundled-only `RFTheme.bodyFont`, `captionFont` and `pageFont` are removed) |

Coverage measured on the bundled files: the Noto Sans SC subset covers the exemplar
letters of en, es, de, pt-BR, it and id, not fr, tr or vi, and no Cyrillic, Greek or
Arabic-Indic digits. Hanken Grotesk covers en, es, fr, de, pt-BR, it, id, tr and vi,
not Cyrillic or Greek. JetBrains Mono covers Latin, Cyrillic and Greek.

## Size and line height

Kit text sizes are the design sizes at the default (`large`) text size and follow
Dynamic Type through `UIFontMetrics` for the text style nearest the design size.
Text inside fixed shapes (avatar initials, reaction emoji, the simulated status
bar) keeps the design size. Bundled faces take the exact design line height on
iOS 26 and later. System faces are never given less than their own ascent plus
descent: the design line height only adds spacing, so Arabic marks and other tall
glyphs are not clipped. Message text has no maximum line height.
