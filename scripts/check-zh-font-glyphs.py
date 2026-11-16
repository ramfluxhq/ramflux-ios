#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Fail when a zh-CN catalog character or a general-standard character is missing.

scripts/tongyong-8105.txt is the 2013 Table of General Standard Chinese
Characters (通用规范汉字表, State Council of the PRC, Guo Fa [2013] No. 23,
promulgated 2013-06-05). Levels 1, 2 and 3, in that order, come from
https://github.com/shengdoushi/common-standard-chinese-characters-table.
The file is one character per line. A comment line would be checked as a glyph.
"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "Packages/RFDesign/Resources/Fonts/NotoSansSC.ttf"
TABLE = ROOT / "scripts/tongyong-8105.txt"


def cmap_ranges(data):
    if data[:4] not in (b"\x00\x01\x00\x00", b"OTTO"):
        raise SystemExit("not a truetype or opentype font")
    count = struct.unpack(">H", data[4:6])[0]
    cmap = None
    for index in range(count):
        offset = 12 + index * 16
        tag, _, table = struct.unpack(">4sII", data[offset:offset + 12])
        if tag == b"cmap":
            cmap = table
            break
    if cmap is None:
        raise SystemExit("font has no cmap")
    records = struct.unpack(">H", data[cmap + 2:cmap + 4])[0]
    ranges = []
    for index in range(records):
        platform, encoding, offset = struct.unpack(">HHI", data[cmap + 4 + index * 8:cmap + 12 + index * 8])
        if platform == 0:
            pass
        elif platform == 3 and encoding in (1, 10):
            pass
        else:
            continue
        start = cmap + offset
        fmt = struct.unpack(">H", data[start:start + 2])[0]
        if fmt == 4:
            seg = struct.unpack(">H", data[start + 6:start + 8])[0] // 2
            end = start + 14
            ends = struct.unpack(f">{seg}H", data[end:end + seg * 2])
            starts = struct.unpack(f">{seg}H", data[end + seg * 2 + 2:end + seg * 4 + 2])
            ranges.extend(zip(starts, ends))
        elif fmt == 12:
            groups = struct.unpack(">I", data[start + 12:start + 16])[0]
            cursor = start + 16
            for _ in range(groups):
                first, last, _glyph = struct.unpack(">III", data[cursor:cursor + 12])
                ranges.append((first, last))
                cursor += 12
    if not ranges:
        raise SystemExit("font cmap has no Unicode ranges")
    return ranges


def covered(ranges, value):
    return any(first <= value <= last for first, last in ranges)


def catalog_text():
    chars = set()
    for path in (ROOT / "Packages").rglob("Localizable.xcstrings"):
        if any(part in {".build", "build"} for part in path.parts):
            continue
        payload = json.loads(path.read_text())
        for entry in payload.get("strings", {}).values():
            unit = entry.get("localizations", {}).get("zh-CN", {}).get("stringUnit", {})
            value = unit.get("value", "")
            chars.update(value)
            for variation in entry.get("localizations", {}).get("zh-CN", {}).get("variations", {}).values():
                for form in variation.values():
                    text = form.get("stringUnit", {}).get("value", "")
                    chars.update(text)
    return chars


def table_chars():
    chars = [line.strip() for line in TABLE.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(chars) != 8105 or len(set(chars)) != 8105:
        raise SystemExit(f"ZH_FONT_TABLE: expected 8105 unique characters, found {len(set(chars))}")
    return chars


def main():
    data = FONT.read_bytes()
    ranges = cmap_ranges(data)
    catalog = catalog_text()
    missing = sorted(char for char in catalog if not covered(ranges, ord(char)))
    if missing:
        shown = "".join(missing[:40])
        raise SystemExit(f"ZH_FONT_GLYPHS_MISSING: {len(missing)} {shown}")
    table = table_chars()
    missing_table = [char for char in table if not covered(ranges, ord(char))]
    if missing_table:
        shown = "".join(missing_table[:40])
        raise SystemExit(f"ZH_FONT_TABLE_MISSING: {len(missing_table)} {shown}")
    print(f"ZH_FONT_GLYPHS_OK: {len(catalog)} zh-CN characters are in NotoSansSC")
    print(f"ZH_FONT_TABLE_OK: {len(table)} general-standard characters are in NotoSansSC")
    return 0


if __name__ == "__main__":
    sys.exit(main())
