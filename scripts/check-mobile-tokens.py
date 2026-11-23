#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Compare hand-written RFTokens with the design token file.

The design file's SHA-256 is pinned. CI passes that file and fails if the
bytes drift from the pin or if RFTokens disagrees with it. A second path,
when the caller has the spec file, must be byte-identical to the first.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESIGN_SHA256 = "20493443ec546b65fb7d283f2b35a6fec258c14a004201886e5c620c0d10b6c5"
SOURCE = ROOT / "Packages/RFDesign/Generated/RFTokens.swift"
THEMES = ROOT / "Packages/RFDesign/Resources/Themes"
COLOR = re.compile(
    r"(\w+):\s*Color\(\.sRGB,\s*red:\s*([0-9.]+),\s*green:\s*([0-9.]+),\s*blue:\s*([0-9.]+),\s*opacity:\s*([0-9.]+)\)",
    re.S,
)
NUMBER = re.compile(r"(\w+):\s*(-?\d+(?:\.\d+)?)")
STRING = re.compile(r'(\w+):\s*"([^"]*)"')


def argb(value):
    raw = value.removeprefix("#")
    if len(raw) == 6:
        return int(raw, 16) | 0xFF000000
    if len(raw) == 8:
        return int(raw[6:8] + raw[0:6], 16)
    raise ValueError(f"bad color {value}")


def channel_byte(component):
    return int(round(float(component) * 255))


def theme_block(text, name):
    match = re.search(rf"public static let {name} = RFTheme\((.*?)\n    \)", text, re.S)
    if not match:
        raise SystemExit(f"missing RFDesign.{name}")
    return match.group(1)


def field_map(block):
    found = {}
    for match in COLOR.finditer(block):
        red, green, blue, alpha = (channel_byte(match.group(i)) for i in range(2, 6))
        found[match.group(1)] = (alpha << 24) | (red << 16) | (green << 8) | blue
    stripped = COLOR.sub(lambda match: f"{match.group(1)}: 0", block)
    for match in STRING.finditer(stripped):
        found[match.group(1)] = match.group(2)
    for match in NUMBER.finditer(stripped):
        name = match.group(1)
        if name not in found:
            found[name] = float(match.group(2))
    return found


def component_hex(node):
    parts = node["components"]
    alpha = node.get("alpha", 1)
    channels = [int(round(float(part) * 255)) for part in parts]
    alpha_byte = int(round(float(alpha) * 255))
    return (alpha_byte << 24) | (channels[0] << 16) | (channels[1] << 8) | channels[2]


def close(left, right):
    return isinstance(left, float) and isinstance(right, float) and abs(left - right) < 1e-6


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit("usage: check-mobile-tokens.py <design-tokens.json> [spec-tokens.json]")
    token_path = Path(sys.argv[1])
    raw = token_path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != DESIGN_SHA256:
        raise SystemExit(f"TOKEN_DIGEST {digest} != {DESIGN_SHA256}")
    if len(sys.argv) == 3:
        spec_bytes = Path(sys.argv[2]).read_bytes()
        spec_digest = hashlib.sha256(spec_bytes).hexdigest()
        if spec_bytes != raw or spec_digest != DESIGN_SHA256:
            raise SystemExit(f"TOKEN_SPEC_MISMATCH {spec_digest} != {DESIGN_SHA256}")
    spec = json.loads(raw)
    text = SOURCE.read_text()
    light = field_map(theme_block(text, "light"))
    dark = field_map(theme_block(text, "dark"))
    errors = []
    for key, modes in spec["color"]["values"].items():
        field = key.removeprefix("rf-").replace("-", "_")
        for mode, block in (("light", light), ("dark", dark)):
            expected = argb(modes[mode])
            actual = block.get(field)
            if actual != expected:
                errors.append(f"{mode} {field}: {actual} != {expected:#010x}")
    numbers = {}
    numbers.update({key.removeprefix("rf-").replace("-", "_"): float(value) for key, value in spec["typography"]["sizesPx"]["values"].items()})
    numbers.update({key.removeprefix("rf-").replace("-", "_"): float(value) for key, value in spec["radii"]["variables"].items()})
    numbers.update({key.removeprefix("rf-").replace("-", "_"): float(value) for key, value in spec["dimensions"]["variables"].items()})
    for field, expected in numbers.items():
        if not close(light.get(field), expected) or not close(dark.get(field), expected):
            errors.append(f"{field}: light {light.get(field)} dark {dark.get(field)} != {expected}")
    families = {
        "font": spec["typography"]["families"]["rf-font"],
        "font_latin": spec["typography"]["families"]["rf-font-latin"],
        "font_serif": spec["typography"]["families"]["rf-font-serif"],
        "font_mono": spec["typography"]["families"]["rf-font-mono"],
    }
    for field, expected in families.items():
        if light.get(field) != expected or dark.get(field) != expected:
            errors.append(f"{field}: {light.get(field)}/{dark.get(field)} != {expected}")
    for name in ("light", "dark"):
        theme = json.loads((THEMES / f"{name}.json").read_text())["tokens"]
        block = light if name == "light" else dark
        for field, value in block.items():
            token = theme.get(field.replace("_", "-"))
            if token is None:
                errors.append(f"theme {name} missing {field}")
                continue
            kind = token["$type"]
            if kind == "color":
                actual = component_hex(token["$value"])
                if actual != value:
                    errors.append(f"theme {name} {field}: {actual:#010x} != {value:#010x}")
            elif kind == "dimension":
                actual = float(token["$value"]["value"])
                if not close(actual, value):
                    errors.append(f"theme {name} {field}: {actual} != {value}")
            elif kind == "fontFamily":
                if token["$value"] != value:
                    errors.append(f"theme {name} {field}: {token['$value']} != {value}")
            else:
                errors.append(f"theme {name} {field}: unsupported {kind}")
    if errors:
        raise SystemExit("TOKEN_MISMATCH\n" + "\n".join(errors))
    print(f"TOKENS_OK {len(spec['color']['values'])} colors")


if __name__ == "__main__":
    main()
