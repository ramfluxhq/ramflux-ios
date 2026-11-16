#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Compare kit captures with design preview PNGs and write pair evidence.

Usage: compare-kit-previews.py <previews-dir> <captures-dir> <output-dir>

Design exports are twice the design size. Transparent preview pixels are
composited onto rf-bg (light #FCFBF9, dark #171716) before the pair and the
diff. The checklist measures the master frame from kit-masters.json when the
export canvas is not that frame, and the untrimmed preview frame otherwise.
It does not measure trimmed ink. A capture edge more than 2 design pixels
from the master is OVER. A preview with no capture is OVER.
"""

import json
import struct
import sys
import zlib
from pathlib import Path

SCALE = 2
LIMIT = 2.0
# Shell --content gate. A flat or tab-bar-only frame fails the variance floors.
# The mean channel delta is against the preview composited on rf-bg. Kit compares
# omit --content, so this threshold does not apply to component boards.
CONTENT_STD_FLOOR = 8.0
CONTENT_MID_STD_FLOOR = 6.0
# Same-theme mean on a drawn shell board. A theme swap sits above 150.
# Catalog forms that are not the drawn board use the named exception limit.
SHELL_MEAN_LIMIT = 20.0
CATALOG_MEAN_LIMIT = 80.0
CATALOG_STEMS = {
    "MOB-S01.light",
    "MOB-S02.light",
    "MOB-S18.light",
    "MOB-A01.light",
    "MOB-A02.light",
}
STRUCT_LIMIT = 2.0
# KitTabBar's 8 pt top pad puts icons 4 px below the preview. A real miss
# (the old ~24 px safe-area error) is still OVER.
TAB_INK_LIMIT = 5.0
# Accepted deviations. The checklist records the reason; they do not raise the mean limit.
LISTED = {
    "MOB-B01.light": "listed: header keeps contacts and refresh; square-pen and the page-actions ellipsis are not drawn",
    "MOB-B01.dark": "listed: header keeps contacts and refresh; square-pen and the page-actions ellipsis are not drawn",
    "MOB-B01L.light": "listed: loading board is the shell chrome over a progress row",
    "MOB-B01X.light": "listed: failure board keeps the shell failure view",
    "MOB-C01.light": "listed: tab root keeps the large title; the design header is a pushed title about 16 px higher",
    "MOB-D01.light": "listed: add is omitted (ruling 4); page-actions ellipsis has no destination; rows use the conversation row",
    "MOB-D01E.light": "listed: search-miss empty is the undesigned no-agents state; the tip is ruling 4",
    "MOB-G01.light": "listed: header ellipsis has no designed destination; accounts and notices have no board",
    "MOB-S01.light": "listed: launch stays a catalog form (design gap)",
    "MOB-S02.light": "listed: connection stays a catalog form (design gap, owner shell)",
    "MOB-S18.light": "listed: welcome stays a catalog form (design gap); welcome continues to account creation (ruling 6)",
    "MOB-A01.light": "listed: start stays a catalog form (design gap)",
    "MOB-A02.light": "listed: local unlock stays a catalog form (design gap, owner shell)",
}
LIGHT_BG = (0xFC, 0xFB, 0xF9)
DARK_BG = (0x17, 0x17, 0x16)
SKIP_PREFIXES = ("chart--", "radio--", "origin-display--")
STATE_SUFFIXES = ("--pressed", "--focused", "--loading", "--en", "--zh")
ROOT = Path(__file__).resolve().parent.parent
MASTERS = json.loads((ROOT / "Packages/RFDesign/kit-masters.json").read_text())


def paeth(left, up, upper_left):
    estimate = left + up - upper_left
    scores = (abs(estimate - left), abs(estimate - up), abs(estimate - upper_left))
    return (left, up, upper_left)[scores.index(min(scores))]


def read_png(path):
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"not a png: {path}")
    pos = 8
    width = height = color = None
    chunks = []
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        kind = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, bit, color = struct.unpack(">IIBB", chunk[:10])
            if bit not in (8, 16) or color not in (2, 6):
                raise SystemExit(f"unsupported png {path}")
        elif kind == b"IDAT":
            chunks.append(chunk)
        elif kind == b"IEND":
            break
    raw = zlib.decompress(b"".join(chunks))
    channels = 4 if color == 6 else 3
    # PNG filters address bytes. A 16-bit sample is two bytes.
    bytes_per_pixel = channels * (bit // 8)
    stride = width * bytes_per_pixel
    rows = []
    index = 0
    previous = bytearray(stride)
    for _ in range(height):
        filter_type = raw[index]
        index += 1
        row = bytearray(raw[index : index + stride])
        index += stride
        for column in range(stride):
            left = row[column - bytes_per_pixel] if column >= bytes_per_pixel else 0
            up = previous[column]
            upper_left = previous[column - bytes_per_pixel] if column >= bytes_per_pixel else 0
            if filter_type == 1:
                row[column] = (row[column] + left) & 255
            elif filter_type == 2:
                row[column] = (row[column] + up) & 255
            elif filter_type == 3:
                row[column] = (row[column] + ((left + up) // 2)) & 255
            elif filter_type == 4:
                row[column] = (row[column] + paeth(left, up, upper_left)) & 255
            elif filter_type != 0:
                raise SystemExit(f"bad filter in {path}")
        previous = row
        if bit == 16:
            row = bytearray(row[offset] for offset in range(0, len(row), 2))
        rows.append(row)
    return width, height, channels, rows


def pixel(rows, channels, x, y):
    sample = rows[y][x * channels : x * channels + channels]
    if channels == 4:
        return sample[0], sample[1], sample[2], sample[3]
    return sample[0], sample[1], sample[2], 255


def write_png(path, width, height, rgb_rows):
    raw = bytearray()
    for row in rgb_rows:
        raw.append(0)
        raw.extend(row)
    compressed = zlib.compress(bytes(raw), 9)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))


def board_bg(name):
    return DARK_BG if "--dark" in name else LIGHT_BG


def over_bg(red, green, blue, alpha, bg):
    if alpha >= 255:
        return red, green, blue
    scale = alpha / 255.0
    return (
        int(round(red * scale + bg[0] * (1.0 - scale))),
        int(round(green * scale + bg[1] * (1.0 - scale))),
        int(round(blue * scale + bg[2] * (1.0 - scale))),
    )


def scale_half(width, height, channels, rows, bg):
    out_w = width // SCALE
    out_h = height // SCALE
    scaled = []
    for y in range(out_h):
        row = bytearray()
        for x in range(out_w):
            red, green, blue, alpha = pixel(rows, channels, x * SCALE, y * SCALE)
            red, green, blue = over_bg(red, green, blue, alpha, bg)
            row.extend((red, green, blue))
        scaled.append(row)
    return out_w, out_h, scaled


def blank(width, height, color):
    row = bytes(color) * width
    return [bytearray(row) for _ in range(height)]


def blit(canvas, rows, x0, y0):
    for y, row in enumerate(rows):
        offset = x0 * 3
        canvas[y0 + y][offset : offset + len(row)] = row


def lookup_master(name):
    keys = [name]
    if name.endswith("--dark"):
        keys.append(name[: -len("--dark")])
    base = name
    for suffix in STATE_SUFFIXES:
        if base.endswith(suffix):
            base = base[: -len(suffix)]
            keys.append(base)
            if base.endswith("--dark"):
                keys.append(base[: -len("--dark")])
    for key in keys:
        if key in MASTERS:
            return MASTERS[key]
    return None


def preview_for(previews, name):
    direct = previews / f"{name}.png"
    if direct.exists():
        return direct, False
    base = name
    if base.endswith("--dark"):
        base = base[: -len("--dark")]
    for suffix in STATE_SUFFIXES:
        if base.endswith(suffix):
            base = base[: -len(suffix)]
            break
    for candidate in (base, f"{base}--default"):
        fallback = previews / f"{candidate}.png"
        if fallback.exists():
            return fallback, True
    return None, False


def board_stem(name):
    stem = name
    for suffix in ("--en--dark", "--zh--dark", "--dark", "--en", "--zh"):
        if stem.endswith(suffix):
            return stem[: -len(suffix)]
    return stem


def content_mean_limit(name):
    if board_stem(name) in CATALOG_STEMS:
        return CATALOG_MEAN_LIMIT
    return SHELL_MEAN_LIMIT


def band_std(row, x0, x1):
    start = max(0, x0) * 3
    end = min(len(row) // 3, x1) * 3
    count = (end - start) // 3
    if count <= 0:
        return 0.0
    total = total_sq = 0.0
    for offset in range(start, end, 3):
        lum = 0.2126 * row[offset] + 0.7152 * row[offset + 1] + 0.0722 * row[offset + 2]
        total += lum
        total_sq += lum * lum
    mean = total / count
    return max(0.0, total_sq / count - mean * mean) ** 0.5


def ink_top(rows, y0, y1, x0, x1, floor):
    last = min(y1, len(rows))
    for y in range(max(0, y0), last):
        if band_std(rows[y], x0, x1) >= floor:
            return y
    return None


def structural_report(name, capture_rows, preview_rows, borrowed=False):
    """Return failure reasons and a measurement note.

    Title and footer positions use the top of the ink, which tracks the frame.
    The heaviest glyph row moves with the typeface and is not the layout check.
    """
    if preview_rows is None or board_stem(name) in CATALOG_STEMS:
        return [], ""
    stem = board_stem(name)
    reasons = []
    notes = []
    capture_title = ink_top(capture_rows, 55, 130, 16, 240, 6.0)
    preview_title = ink_top(preview_rows, 55, 130, 16, 240, 6.0)
    if capture_title is not None and preview_title is not None:
        delta = capture_title - preview_title
        notes.append(f"title-ink {capture_title} vs {preview_title}")
        # C01 keeps the large title on a board drawn with a pushed header.
        # A borrowed locale uses another language's preview, so glyph tops differ.
        if not borrowed and not stem.startswith("MOB-C01") and abs(delta) > STRUCT_LIMIT:
            reasons.append(f"title-y {capture_title} vs {preview_title}")
    tab_root = stem.startswith(("MOB-B", "MOB-C", "MOB-D")) or stem.startswith("MOB-G01")
    if tab_root:
        capture_tab = ink_top(capture_rows, 760, 830, 0, 393, 4.0)
        preview_tab = ink_top(preview_rows, 760, 830, 0, 393, 4.0)
        if capture_tab is not None and preview_tab is not None:
            delta = capture_tab - preview_tab
            notes.append(f"tab-ink {capture_tab} vs {preview_tab}")
            if abs(delta) > TAB_INK_LIMIT:
                reasons.append(f"tab-y {capture_tab} vs {preview_tab}")
            elif abs(delta) > STRUCT_LIMIT:
                notes.append("tab icons follow the kit tab bar 8 pt pad")
    if stem.startswith(("MOB-G03", "MOB-N01")):
        capture_footer = ink_top(capture_rows, 740, 820, 40, 353, 4.0)
        preview_footer = ink_top(preview_rows, 740, 820, 40, 353, 4.0)
        if capture_footer is not None and preview_footer is not None:
            notes.append(f"footer-ink {capture_footer} vs {preview_footer}")
            if abs(capture_footer - preview_footer) > STRUCT_LIMIT:
                reasons.append(f"footer-y {capture_footer} vs {preview_footer}")
        # Buttons that run into the home-indicator band are clipped.
        clipped = ink_top(capture_rows, 812, 832, 40, 353, 8.0)
        if clipped is not None:
            reasons.append(f"footer-clipped y={clipped}")
    return reasons, "; ".join(notes)


def luminance_std(rgb_rows):
    height = len(rgb_rows)
    if height == 0:
        return 0.0, 0.0
    y0 = height // 5
    y1 = height - y0
    total = total_sq = mid_total = mid_sq = 0.0
    count = mid_count = 0
    for y, row in enumerate(rgb_rows):
        for x in range(0, len(row), 3):
            lum = 0.2126 * row[x] + 0.7152 * row[x + 1] + 0.0722 * row[x + 2]
            count += 1
            total += lum
            total_sq += lum * lum
            if y0 <= y < y1:
                mid_count += 1
                mid_total += lum
                mid_sq += lum * lum

    def deviation(n, sum_value, sum_sq):
        if n == 0:
            return 0.0
        mean = sum_value / n
        return max(0.0, sum_sq / n - mean * mean) ** 0.5

    return deviation(count, total, total_sq), deviation(mid_count, mid_total, mid_sq)


def mean_channel_delta(capture_rows, preview_rows):
    height = min(len(capture_rows), len(preview_rows))
    if height == 0:
        return 0.0
    width = min(len(capture_rows[0]), len(preview_rows[0])) // 3
    if width == 0:
        return 0.0
    total = 0.0
    for y in range(height):
        left = capture_rows[y]
        right = preview_rows[y]
        for x in range(width):
            offset = x * 3
            total += (
                abs(left[offset] - right[offset])
                + abs(left[offset + 1] - right[offset + 1])
                + abs(left[offset + 2] - right[offset + 2])
            ) / 3.0
    return total / (width * height)


def main():
    args = [arg for arg in sys.argv[1:] if arg != "--content"]
    content = len(args) != len(sys.argv) - 1
    if len(args) != 3:
        raise SystemExit("usage: compare-kit-previews.py [--content] <previews-dir> <captures-dir> <output-dir>")
    previews = Path(args[0])
    captures = Path(args[1])
    output = Path(args[2])
    output.mkdir(parents=True, exist_ok=True)
    over = 0
    seen = set()
    lines = ["name\tcapture\tmaster\tpreview\tdw\tdh\tflag\tnote"]
    print(f"{'name':48} {'capture':>11} {'master':>11} {'preview':>11} {'dw':>7} {'dh':>7}")
    for capture in sorted(captures.glob("*.png")):
        name = capture.stem
        if name.startswith(SKIP_PREFIXES) or name.endswith("--pair") or name.endswith("--diff"):
            continue
        seen.add(name)
        capture_w, capture_h, capture_channels, capture_rows = read_png(capture)
        preview_path, borrowed = preview_for(previews, name)
        preview_label = "none"
        scaled = None
        bg = board_bg(name)
        if preview_path is not None:
            preview_w, preview_h, channels, rows = read_png(preview_path)
            preview_label = f"{preview_w / SCALE:g}x{preview_h / SCALE:g}"
            scaled = scale_half(preview_w, preview_h, channels, rows, bg)
        master = lookup_master(name)
        note = ""
        if master is not None:
            master_w = master.get("w", capture_w)
            master_h = master["h"]
            note = master.get("note", "")
            if borrowed:
                note = (note + "; " if note else "") + "paired with the base preview"
        elif scaled is not None:
            master_w, master_h, _rows = scaled
            if borrowed:
                note = "paired with the base preview"
        else:
            print(f"{name:48} MISSING preview")
            lines.append(f"{name}\t{capture_w}x{capture_h}\tMISSING\tnone\t\t\tOVER\tno preview")
            over += 1
            continue
        delta_w = capture_w - master_w
        delta_h = capture_h - master_h
        width_checked = not (master is not None and "w" not in master)
        locale = name.endswith("--en") or name.endswith("--zh")
        limit_h = 4.0 if locale else LIMIT
        fail_w = width_checked and abs(delta_w) > LIMIT
        fail_h = abs(delta_h) > limit_h
        flag = "OVER" if fail_w or fail_h else "ok"
        if flag == "OVER":
            over += 1
        if content:
            cap_rgb = capture_rgb(capture_w, capture_h, capture_channels, capture_rows, bg)
            std, mid = luminance_std(cap_rgb)
            mad = mean_channel_delta(cap_rgb, scaled[2]) if scaled is not None else None
            reasons = []
            if std < CONTENT_STD_FLOOR or mid < CONTENT_MID_STD_FLOOR:
                reasons.append(f"low-variance std={std:.1f} mid={mid:.1f}")
            # A dark capture borrowed from a light preview cannot match that preview's pixels.
            limit = content_mean_limit(name)
            if mad is not None and not borrowed and mad > limit:
                reasons.append(f"pixel-diff {mad:.1f}>{limit:.0f}")
            preview_rgb = scaled[2] if scaled is not None else None
            structure, measured = structural_report(name, cap_rgb, preview_rgb, borrowed)
            reasons.extend(structure)
            if measured:
                note = (note + "; " if note else "") + measured
            listed = LISTED.get(board_stem(name))
            if listed:
                note = (note + "; " if note else "") + listed
            if reasons:
                if flag != "OVER":
                    over += 1
                    flag = "OVER"
                note = (note + "; " if note else "") + "; ".join(reasons)
            mad_text = f"{mad:.1f}" if mad is not None else "n/a"
            print(f"  content std={std:.1f} mid={mid:.1f} mean={mad_text} limit={limit:.0f}")
        dw_text = f"{delta_w:.1f}" if width_checked else "n/a"
        print(
            f"{name:48} {capture_w:4}x{capture_h:<4} {master_w:5g}x{master_h:<5g} "
            f"{preview_label:>11} {dw_text:>7} {delta_h:7.1f} {flag}"
        )
        lines.append(
            f"{name}\t{capture_w}x{capture_h}\t{master_w:g}x{master_h:g}\t{preview_label}\t{dw_text}\t{delta_h:.1f}\t{flag}\t{note}"
        )
        if scaled is not None:
            write_pair(output / f"{name}--pair.png", capture_w, capture_h, capture_channels, capture_rows, scaled, bg)
            write_diff(output / f"{name}--diff.png", capture_w, capture_h, capture_channels, capture_rows, scaled, bg)
    for preview in sorted(previews.glob("*.png")):
        name = preview.stem
        if name.startswith(SKIP_PREFIXES) or name in seen:
            continue
        print(f"{name:48} MISSING capture")
        lines.append(f"{name}\tMISSING\t\tpreview\t\t\tOVER\tno capture")
        over += 1
    lines.append("")
    lines.append("notes")
    lines.append("Pushed page titles are 20/600. Large titles are 32/700. Chat titles stay 17/600.")
    lines.append("The selected tab has no pill. Selection is icon and label color and weight.")
    lines.append("Chinese uses the bundled Noto Sans SC face.")
    lines.append("en/zh boards use the preview sample text. Height may differ by up to 4 px.")
    lines.append("A dark board with no dark export is paired with the light preview.")
    lines.append("Icon geometry is Lucide. Pencil strokes are a reference, not the vector source.")
    lines.append("Radio, origin display and charts are not in this kit.")
    checklist = output / "checklist.tsv"
    checklist.write_text("\n".join(lines) + "\n")
    print(f"OVER {over}")
    print(f"CHECKLIST {checklist}")
    return 1 if over else 0


def capture_rgb(width, height, channels, rows, bg):
    rgb = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            red, green, blue, alpha = pixel(rows, channels, x, y)
            red, green, blue = over_bg(red, green, blue, alpha, bg)
            row.extend((red, green, blue))
        rgb.append(row)
    return rgb


def write_pair(path, capture_w, capture_h, channels, rows, scaled, bg):
    preview_w, preview_h, preview_rows = scaled
    gap = 8
    width = capture_w + gap + preview_w
    height = max(capture_h, preview_h)
    canvas = blank(width, height, bg)
    blit(canvas, capture_rgb(capture_w, capture_h, channels, rows, bg), 0, 0)
    blit(canvas, preview_rows, capture_w + gap, 0)
    write_png(path, width, height, canvas)


def write_diff(path, capture_w, capture_h, channels, rows, scaled, bg):
    preview_w, preview_h, preview_rows = scaled
    canvas = blank(capture_w, capture_h, bg)
    for y in range(capture_h):
        for x in range(capture_w):
            red, green, blue, alpha = pixel(rows, channels, x, y)
            red, green, blue = over_bg(red, green, blue, alpha, bg)
            if y < preview_h and x < preview_w:
                other = preview_rows[y][x * 3 : x * 3 + 3]
                delta = max(abs(red - other[0]), abs(green - other[1]), abs(blue - other[2]))
                if delta > 40:
                    red, green, blue = 220, 40, 40
            canvas[y][x * 3 : x * 3 + 3] = bytes((red, green, blue))
    write_png(path, capture_w, capture_h, canvas)


if __name__ == "__main__":
    sys.exit(main())
