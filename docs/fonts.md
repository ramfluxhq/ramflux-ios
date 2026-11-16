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
