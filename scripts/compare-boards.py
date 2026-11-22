#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Compare board captures with the design references, pixel by pixel.

Usage:
  compare-boards.py <captures-dir> <output-dir> [--manifest FILE] [--expected FILE]
                    [--review] [--write-expected FILE]

Every manifest entry (shell-previews/manifest.json) is compared with the capture
`<board>-<locale>-393-default-<theme>.png`. Both images are one pixel per point.
Reference pixels that are fully transparent (the rounded board corners) are not
compared; partly transparent ones are composited on the theme background.

A pixel differs when its largest channel difference exceeds TOLERANCE and the
anti-aliasing check fails: a pixel is still accepted when the other image has a
pixel within TOLERANCE inside its 3x3 neighbourhood, in both directions, so a
sub-pixel or one-pixel edge shift does not count. Differing pixels are grouped
into regions (8-connected cells of CELL px). A region larger than LIMIT_PT in
either direction is a deviation; smaller specks are noise.

For each region the report gives its box and the ink box of the reference and
of the capture inside it, so a moved or resized element shows as an offset
(dx, dy) and a size change (dw, dh) in points.

Expected deviations (shell-previews/expected-deviations.json) are reviewed
entries: a board-level reason and the rectangles where differences are known.
A region is known when nearly all of its differing pixels fall inside the
expected rectangles (grown by MATCH_MARGIN). Anything else is NEW and fails the
run. Expected rectangles with no differing pixel left are reported as resolved.

--review also checks every other capture in the directory (other widths, text
sizes, locales) with cheap heuristics: blank capture, content cut at a side
edge, content inside the home-indicator band, an unmirrored header in the
right-to-left locale, and a larger text size that changes at most
TEXT_SIZE_ROWS pixel rows. Review findings are
listed in review.tsv; they do not fail the run.

Outputs: checklist.md and checklist.tsv, pairs/<stem>--pair.png (capture,
reference, diff side by side) and diffs/<stem>--diff.png.
Exit status: 0 when no NEW deviation exists, 1 otherwise.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rfpng import read_png, write_png  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
TOLERANCE = 32
CELL = 4
LIMIT_PT = 2
MATCH_MARGIN = 4
NEW_PIXEL_SLACK = 4
NEW_PIXEL_FRACTION = 0.02
BACKGROUND = {"light": (0xFC, 0xFB, 0xF9), "dark": (0x17, 0x17, 0x16)}
COMPARED_WIDTH = 393
COMPARED_SIZE = "default"
UNREVIEWED = "UNREVIEWED"
# A larger text size that changes this few rows has no visible effect.
TEXT_SIZE_ROWS = 20
# Boards whose content stops above the 34 pt home-indicator band (no tab bar).
NO_TAB_PREFIXES = ("MOB-G03", "MOB-S", "MOB-A", "MOB-N", "MOB-B02")


class Image:
    """RGB rows composited on the theme background, plus a compare mask."""

    def __init__(self, path, background):
        width, height, channels, rows = read_png(path)
        self.width, self.height = width, height
        self.rgb = []
        self.mask = []
        for row in rows:
            out = bytearray(width * 3)
            keep = bytearray(width)
            for x in range(width):
                offset = x * channels
                alpha = row[offset + 3] if channels == 4 else 255
                if alpha == 0:
                    out[x * 3 : x * 3 + 3] = bytes(background)
                    continue
                keep[x] = 1
                if alpha == 255:
                    out[x * 3 : x * 3 + 3] = row[offset : offset + 3]
                else:
                    for c in range(3):
                        out[x * 3 + c] = (row[offset + c] * alpha + background[c] * (255 - alpha) + 127) // 255
            self.rgb.append(out)
            self.mask.append(keep)


def delta(a, ax, b, bx):
    return max(abs(a[ax] - b[bx]), abs(a[ax + 1] - b[bx + 1]), abs(a[ax + 2] - b[bx + 2]))


def has_near(x, y, source_row, other, width, height):
    """True when `other` has a pixel within TOLERANCE of source_row[x] in the 3x3 neighbourhood of (x, y)."""
    for ny in (y - 1, y, y + 1):
        if ny < 0 or ny >= height:
            continue
        line = other[ny]
        for nx in (x - 1, x, x + 1):
            if 0 <= nx < width and delta(source_row, x * 3, line, nx * 3) <= TOLERANCE:
                return True
    return False


def diff_mask(capture, reference):
    """Return a set of (x, y) differing pixels and the compared pixel count."""
    width, height = reference.width, reference.height
    differing = set()
    compared = 0
    for y in range(height):
        cap_row = capture.rgb[y]
        ref_row = reference.rgb[y]
        keep = reference.mask[y]
        for x in range(width):
            if not keep[x]:
                continue
            compared += 1
            o = x * 3
            if delta(cap_row, o, ref_row, o) <= TOLERANCE:
                continue
            if has_near(x, y, cap_row, reference.rgb, width, height) and has_near(x, y, ref_row, capture.rgb, width, height):
                continue
            differing.add((x, y))
    return differing, compared


def regions_of(differing):
    """Group differing pixels into regions of 8-connected CELL x CELL cells."""
    cells = {}
    for x, y in differing:
        cells.setdefault((x // CELL, y // CELL), []).append((x, y))
    seen = set()
    regions = []
    for start in cells:
        if start in seen:
            continue
        stack = [start]
        seen.add(start)
        pixels = []
        while stack:
            cx, cy = stack.pop()
            pixels.extend(cells[(cx, cy)])
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    neighbour = (cx + dx, cy + dy)
                    if neighbour in cells and neighbour not in seen:
                        seen.add(neighbour)
                        stack.append(neighbour)
        xs = [p[0] for p in pixels]
        ys = [p[1] for p in pixels]
        x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
        regions.append({"rect": [x0, y0, x1 - x0 + 1, y1 - y0 + 1], "pixels": pixels})
    regions.sort(key=lambda region: -len(region["pixels"]))
    return [region for region in regions if region["rect"][2] > LIMIT_PT or region["rect"][3] > LIMIT_PT]


def ink_box(image, rect, background, margin=6):
    x, y, w, h = rect
    x0, y0 = max(0, x - margin), max(0, y - margin)
    x1, y1 = min(image.width, x + w + margin), min(image.height, y + h + margin)
    found = None
    for yy in range(y0, y1):
        row = image.rgb[yy]
        for xx in range(x0, x1):
            o = xx * 3
            if max(abs(row[o] - background[0]), abs(row[o + 1] - background[1]), abs(row[o + 2] - background[2])) > TOLERANCE:
                if found is None:
                    found = [xx, yy, xx, yy]
                else:
                    found[0] = min(found[0], xx)
                    found[1] = min(found[1], yy)
                    found[2] = max(found[2], xx)
                    found[3] = max(found[3], yy)
    if found is None:
        return None
    return [found[0], found[1], found[2] - found[0] + 1, found[3] - found[1] + 1]


def describe(region, capture, reference, background):
    ref_ink = ink_box(reference, region["rect"], background)
    cap_ink = ink_box(capture, region["rect"], background)
    if ref_ink is None and cap_ink is None:
        return "colour only"
    if ref_ink is None:
        return "extra in capture"
    if cap_ink is None:
        return "missing in capture"
    dx, dy = cap_ink[0] - ref_ink[0], cap_ink[1] - ref_ink[1]
    dw, dh = cap_ink[2] - ref_ink[2], cap_ink[3] - ref_ink[3]
    return f"ink dx={dx:+d} dy={dy:+d} dw={dw:+d} dh={dh:+d}"


def inside(point, rects):
    x, y = point
    for rx, ry, rw, rh in rects:
        if rx - MATCH_MARGIN <= x < rx + rw + MATCH_MARGIN and ry - MATCH_MARGIN <= y < ry + rh + MATCH_MARGIN:
            return True
    return False


def classify(regions, expected_rects):
    known, new = [], []
    for region in regions:
        outside = [p for p in region["pixels"] if not inside(p, expected_rects)]
        covered = len(outside) < len(region["pixels"])
        if covered and len(outside) <= max(NEW_PIXEL_SLACK, NEW_PIXEL_FRACTION * len(region["pixels"])):
            known.append(region)
        else:
            xs = [p[0] for p in outside]
            ys = [p[1] for p in outside]
            region["new_rect"] = [min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1]
            new.append(region)
    return known, new


def resolved_rects(differing, expected_rects):
    resolved = []
    for rect in expected_rects:
        x, y, w, h = rect
        if not any(x <= px < x + w and y <= py < y + h for px, py in differing):
            resolved.append(rect)
    return resolved


def outline(canvas, rect, color, width_px):
    x, y, w, h = rect
    for yy in (y - 1, y + h):
        if 0 <= yy < len(canvas):
            for xx in range(max(0, x - 1), min(width_px, x + w + 1)):
                canvas[yy][xx * 3 : xx * 3 + 3] = bytes(color)
    for xx in (x - 1, x + w):
        if 0 <= xx < width_px:
            for yy in range(max(0, y - 1), min(len(canvas), y + h + 1)):
                canvas[yy][xx * 3 : xx * 3 + 3] = bytes(color)


def diff_canvas(capture, differing, known, new, expected_rects):
    width = capture.width
    canvas = []
    for row in capture.rgb:
        # The capture faded to 25% so the marks stand out in either theme.
        canvas.append(bytearray((value + 3 * 255) // 4 for value in row))
    for x, y in differing:
        canvas[y][x * 3 : x * 3 + 3] = bytes((220, 30, 30))
    for rect in expected_rects:
        outline(canvas, rect, (230, 160, 0), width)
    for region in new:
        outline(canvas, region["new_rect"], (200, 0, 200), width)
    return canvas


def write_pair(path, capture, reference, canvas):
    gap = 8
    width = capture.width * 3 + gap * 2
    height = capture.height
    rows = []
    separator = bytes((128, 128, 128)) * gap
    for y in range(height):
        rows.append(bytes(capture.rgb[y]) + separator + bytes(reference.rgb[y]) + separator + bytes(canvas[y]))
    write_png(path, width, height, rows)


def luminance_std(image):
    total = total_sq = 0.0
    count = 0
    for row in image.rgb[:: 2]:
        for o in range(0, len(row), 6):
            lum = 0.2126 * row[o] + 0.7152 * row[o + 1] + 0.0722 * row[o + 2]
            total += lum
            total_sq += lum * lum
            count += 1
    mean = total / count
    return max(0.0, total_sq / count - mean * mean) ** 0.5


def is_ink(row, x, background):
    o = x * 3
    return max(abs(row[o] - background[0]), abs(row[o + 1] - background[1]), abs(row[o + 2] - background[2])) > TOLERANCE


def edge_rows(image, background, column):
    """Rows where ink touches a side edge and the row is not a full-width rule."""
    hits = 0
    for y in range(44, image.height - 90):
        row = image.rgb[y]
        if not is_ink(row, column, background):
            continue
        filled = sum(1 for x in range(0, image.width, 4) if is_ink(row, x, background))
        if filled * 4 < image.width * 0.6:
            hits += 1
    return hits


def header_centroid(image, background):
    total = count = 0
    for y in range(50, 130):
        row = image.rgb[y]
        for x in range(0, image.width, 2):
            if is_ink(row, x, background):
                total += x
                count += 1
    return total / count if count else None


def parse_name(stem):
    """Split <board>-<locale>-<width>-<size>-<theme>; locales may contain '-'."""
    parts = stem.split("-")
    if len(parts) < 6:
        return None
    theme, size, width = parts[-1], parts[-2], parts[-3]
    if not width.isdigit():
        return None
    board = "-".join(parts[:2])
    locale = "-".join(parts[2:-3])
    return board, locale, int(width), size, theme


def review(captures, compared):
    findings = []
    by_name = {}
    for path in sorted(captures.glob("*.png")):
        parsed = parse_name(path.stem)
        if parsed:
            by_name[path.stem] = (path, parsed)
    for stem, (path, (board, locale, width, size, theme)) in by_name.items():
        if stem in compared:
            continue
        background = BACKGROUND.get(theme, BACKGROUND["light"])
        image = Image(path, background)
        if luminance_std(image) < 6.0:
            findings.append((stem, "blank", "capture has almost no content"))
            continue
        left, right = edge_rows(image, background, 0), edge_rows(image, background, image.width - 1)
        if left >= 3 or right >= 3:
            findings.append((stem, "edge-clip", f"ink touches the side edge on {left} left and {right} right rows"))
        if board.startswith(NO_TAB_PREFIXES):
            band = [y for y in range(image.height - 34, image.height - 18) if any(is_ink(image.rgb[y], x, background) for x in range(0, image.width, 2))]
            if band:
                findings.append((stem, "home-band", f"content enters the home-indicator band at y={band[0]}"))
        if locale == "ar":
            mirror = by_name.get(stem.replace("-ar-", "-en-", 1))
            if mirror:
                reference = Image(mirror[0], background)
                ltr, rtl = header_centroid(reference, background), header_centroid(image, background)
                if ltr is not None and rtl is not None and (ltr - image.width / 2) * (rtl - image.width / 2) > 0:
                    findings.append((stem, "rtl-header", f"header ink centre {rtl:.0f} is on the same side as left-to-right {ltr:.0f}"))
        if size != COMPARED_SIZE:
            base = by_name.get(stem.replace(f"-{width}-{size}-", f"-{width}-{COMPARED_SIZE}-", 1))
            if base:
                changed = sum(1 for left, right in zip(Image(base[0], background).rgb, image.rgb) if left != right)
                if changed <= TEXT_SIZE_ROWS:
                    findings.append((stem, "text-size", f"only {changed} rows differ from the {COMPARED_SIZE} text size"))
    return findings


def load_expected(path):
    if path is None or not path.is_file():
        return {}
    return json.loads(path.read_text()).get("boards", {})


def merge_rects(rects, gap=8):
    merged = [list(rect) for rect in rects]
    changed = True
    while changed:
        changed = False
        for i in range(len(merged)):
            for j in range(i + 1, len(merged)):
                a, b = merged[i], merged[j]
                if a[0] - gap <= b[0] + b[2] and b[0] - gap <= a[0] + a[2] and a[1] - gap <= b[1] + b[3] and b[1] - gap <= a[1] + a[3]:
                    x0, y0 = min(a[0], b[0]), min(a[1], b[1])
                    x1, y1 = max(a[0] + a[2], b[0] + b[2]), max(a[1] + a[3], b[1] + b[3])
                    merged[i] = [x0, y0, x1 - x0, y1 - y0]
                    del merged[j]
                    changed = True
                    break
            if changed:
                break
    return sorted(merged, key=lambda rect: (rect[1], rect[0]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("captures", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--manifest", type=Path, default=ROOT / "shell-previews/manifest.json")
    parser.add_argument("--expected", type=Path, default=ROOT / "shell-previews/expected-deviations.json")
    parser.add_argument("--review", action="store_true")
    parser.add_argument("--write-expected", type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    references = args.manifest.parent
    expected = load_expected(args.expected)
    output = args.output
    (output / "pairs").mkdir(parents=True, exist_ok=True)
    (output / "diffs").mkdir(parents=True, exist_ok=True)
    tsv = ["reference\tdesign\tnode\tcapture\tstatus\tdiff_pct\tregions\tknown\tnew\tdetail"]
    md = [
        "# Board comparison",
        "",
        f"Tolerance {TOLERANCE}/255 per channel with a 1 px anti-aliasing neighbourhood; regions over {LIMIT_PT} pt are deviations. Boxes are x, y, w, h in points.",
        "",
        "| Reference | Design | Status | Differing | Regions (known/new) | Largest regions |",
        "|---|---|---|---|---|---|",
    ]
    new_total = 0
    compared_names = set()
    draft = {}
    unreviewed = [stem for stem, entry in expected.items() if entry.get("reason", UNREVIEWED) == UNREVIEWED]
    for stem in unreviewed:
        print(f"UNREVIEWED expected entry: {stem}")
        new_total += 1
    for entry in manifest["boards"]:
        stem = Path(entry["reference"]).stem
        capture_name = f"{entry['board']}-{entry['locale']}-{COMPARED_WIDTH}-{COMPARED_SIZE}-{entry['theme']}"
        compared_names.add(capture_name)
        known_entry = expected.get(stem, {})
        capture_path = args.captures / f"{capture_name}.png"
        design = f"{entry['key']} ({entry['title']})"
        if not capture_path.is_file():
            status = "known: no capture" if known_entry.get("status") == "no-capture" else "NEW: no capture"
            if status.startswith("NEW"):
                new_total += 1
            print(f"{stem:28} {status}")
            tsv.append(f"{stem}\t{entry['key']}\t{entry['node']}\t-\t{status}\t\t\t\t\t")
            md.append(f"| {stem} | {design} | {status} | - | - | - |")
            draft[stem] = {"status": "no-capture", "reason": known_entry.get("reason", UNREVIEWED)}
            continue
        background = BACKGROUND[entry["theme"]]
        reference = Image(references / entry["reference"], background)
        capture = Image(capture_path, background)
        if (capture.width, capture.height) != (reference.width, reference.height):
            new_total += 1
            status = f"NEW: size {capture.width}x{capture.height} vs {reference.width}x{reference.height}"
            print(f"{stem:28} {status}")
            tsv.append(f"{stem}\t{entry['key']}\t{entry['node']}\t{capture_name}\t{status}\t\t\t\t\t")
            md.append(f"| {stem} | {design} | {status} | - | - | - |")
            continue
        differing, compared = diff_mask(capture, reference)
        regions = regions_of(differing)
        expected_rects = [region["rect"] for region in known_entry.get("regions", [])]
        known, new = classify(regions, expected_rects)
        resolved = resolved_rects(differing, expected_rects)
        percent = 100.0 * len(differing) / compared if compared else 0.0
        if new:
            status = "NEW deviation"
            new_total += 1
        elif known:
            status = "known deviation"
        else:
            status = "pass"
        if resolved:
            status += f"; {len(resolved)} expected rect(s) resolved"
        details = []
        for region in regions[:8]:
            mark = "NEW " if region in new else ""
            details.append(f"{mark}[{', '.join(str(v) for v in region['rect'])}] {describe(region, capture, reference, background)}")
        print(f"{stem:28} {status:30} {percent:6.2f}% regions={len(regions)} known={len(known)} new={len(new)}")
        for line in details:
            print(f"    {line}")
        tsv.append(f"{stem}\t{entry['key']}\t{entry['node']}\t{capture_name}\t{status}\t{percent:.2f}\t{len(regions)}\t{len(known)}\t{len(new)}\t{'; '.join(details)}")
        md.append(f"| {stem} | {design} | {status} | {percent:.2f}% | {len(regions)} ({len(known)}/{len(new)}) | {'<br>'.join(details[:4]) or '-'} |")
        canvas = diff_canvas(capture, differing, known, new, expected_rects)
        write_png(output / "diffs" / f"{stem}--diff.png", capture.width, capture.height, canvas)
        write_pair(output / "pairs" / f"{stem}--pair.png", capture, reference, canvas)
        if regions:
            rects = merge_rects([[max(0, r["rect"][0] - 2), max(0, r["rect"][1] - 2), r["rect"][2] + 4, r["rect"][3] + 4] for r in regions])
            draft[stem] = {
                "status": "deviates",
                "reason": known_entry.get("reason", UNREVIEWED),
                "regions": [{"rect": rect} for rect in rects],
            }
    findings = review(args.captures, compared_names) if args.review else []
    if args.review:
        lines = ["capture\tcheck\tdetail"] + [f"{a}\t{b}\t{c}" for a, b, c in findings]
        (output / "review.tsv").write_text("\n".join(lines) + "\n")
        counts = {}
        for _, check, _ in findings:
            counts[check] = counts.get(check, 0) + 1
        md += ["", "## Review matrix (not compared with boards)", ""]
        md += [f"- {check}: {count} capture(s)" for check, count in sorted(counts.items())] or ["- no findings"]
        md.append("- details: review.tsv")
        print("REVIEW " + ", ".join(f"{check}={count}" for check, count in sorted(counts.items())))
    (output / "checklist.tsv").write_text("\n".join(tsv) + "\n")
    (output / "checklist.md").write_text("\n".join(md) + "\n")
    if args.write_expected:
        document = {
            "note": "Reviewed expected deviations between the app and the design references. Each entry needs a reviewed reason; rectangles are x, y, w, h in points. Remove an entry when the board is aligned.",
            "boards": dict(sorted(draft.items())),
        }
        args.write_expected.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n")
        print(f"EXPECTED DRAFT {args.write_expected}")
    print(f"NEW {new_total}")
    print(f"CHECKLIST {output / 'checklist.md'}")
    return 1 if new_total else 0


if __name__ == "__main__":
    sys.exit(main())
