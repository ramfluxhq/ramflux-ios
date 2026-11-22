#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Maintain the board reference images in shell-previews/ from the design exports.

Usage:
  design-references.py --check
      Verify that every manifest entry has its reference PNG with the recorded
      SHA-256 and that shell-previews/ holds no unlisted PNG. Runs in CI.
  design-references.py --check --boards <exports-dir> [--design-file <file>]
      Also verify that the exports and the design file still have the recorded
      hashes. A changed export means the reference is stale.
  design-references.py --update --boards <exports-dir> --design-file <file>
      Re-derive every reference from its export and rewrite the hashes.

The exports are 2x PNGs of 393x852 pt boards. References are stored at 1x
(one pixel per point), the scale at which board captures are taken and compared.
Each reference pixel is the 2x2 box average of the export in premultiplied
RGBA, so the transparent board corners stay transparent. The conversion is
integer-only and deterministic: the same export always gives the same bytes.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rfpng import read_png, write_png  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
REFERENCES = ROOT / "shell-previews"
MANIFEST = REFERENCES / "manifest.json"
BOARD_SIZE = (393, 852)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def downscale(path, scale):
    width, height, channels, rows = read_png(path)
    if (width, height) != (BOARD_SIZE[0] * scale, BOARD_SIZE[1] * scale):
        raise SystemExit(f"{path}: export is {width}x{height}, expected {BOARD_SIZE[0] * scale}x{BOARD_SIZE[1] * scale}")
    out_w, out_h = width // scale, height // scale
    count = scale * scale
    out = []
    for y in range(out_h):
        row = bytearray()
        sources = rows[y * scale : y * scale + scale]
        for x in range(out_w):
            red = green = blue = alpha = 0
            for source in sources:
                for dx in range(scale):
                    offset = (x * scale + dx) * channels
                    a = source[offset + 3] if channels == 4 else 255
                    red += source[offset] * a
                    green += source[offset + 1] * a
                    blue += source[offset + 2] * a
                    alpha += a
            if alpha == 0:
                row.extend((0, 0, 0, 0))
            else:
                half = alpha // 2
                row.extend(((red + half) // alpha, (green + half) // alpha, (blue + half) // alpha, (alpha + count // 2) // count))
        out.append(row)
    return out_w, out_h, out


def load_manifest():
    return json.loads(MANIFEST.read_text())


def save_manifest(manifest):
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")


def check(manifest, boards, design_file):
    failures = []
    listed = set()
    for entry in manifest["boards"]:
        reference = REFERENCES / entry["reference"]
        listed.add(entry["reference"])
        if not reference.is_file():
            failures.append(f"{entry['reference']}: missing reference image")
        elif sha256(reference) != entry["reference_sha256"]:
            failures.append(f"{entry['reference']}: reference hash differs from the manifest")
        if boards is not None:
            source = boards / entry["source"]
            if not source.is_file():
                failures.append(f"{entry['reference']}: export {entry['source']} is missing")
            elif sha256(source) != entry["source_sha256"]:
                failures.append(f"{entry['reference']}: STALE, export {entry['source']} changed since the reference was derived")
    for path in sorted(REFERENCES.glob("*.png")):
        if path.name not in listed:
            failures.append(f"{path.name}: reference image is not in the manifest")
    if design_file is not None and sha256(design_file) != manifest["design_file_sha256"]:
        failures.append(f"STALE: design file {design_file} has changed since the references were exported")
    return failures


def update(manifest, boards, design_file):
    scale = manifest["export_scale"]
    manifest["design_file_sha256"] = sha256(design_file)
    for entry in manifest["boards"]:
        source = boards / entry["source"]
        width, height, rows = downscale(source, scale)
        reference = REFERENCES / entry["reference"]
        write_png(reference, width, height, rows, channels=4)
        entry["source_sha256"] = sha256(source)
        entry["reference_sha256"] = sha256(reference)
        print(f"{entry['reference']:32} <- {entry['source']}")
    save_manifest(manifest)


def main():
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--update", action="store_true")
    parser.add_argument("--boards", type=Path)
    parser.add_argument("--design-file", type=Path)
    args = parser.parse_args()
    manifest = load_manifest()
    if args.update:
        if args.boards is None or args.design_file is None:
            raise SystemExit("--update needs --boards and --design-file")
        update(manifest, args.boards, args.design_file)
    failures = check(manifest, args.boards, args.design_file)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"DESIGN_REFERENCES_OK: {len(manifest['boards'])} boards match the manifest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
