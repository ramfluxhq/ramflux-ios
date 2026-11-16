#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Turn the Lucide 24px stroke vectors into a Swift path table.

The Android kit already vendors those vectors as ic_kit_*.xml. This script
flattens each path, including arcs, into cubics so SwiftUI can stroke them.
"""
import math
import re
import sys
from pathlib import Path

DRAWABLE = Path(__file__).resolve().parent.parent / "Packages/RFDesign/Resources/KitIcons"
OUT = Path(__file__).resolve().parent.parent / "Packages/RFDesign/Sources/Kit/KitIconPaths.swift"
TOKEN = re.compile(r"[MmLlHhVvCcSsAaZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?")


def tokens(data):
    return TOKEN.findall(data)


def arc_cubics(x1, y1, rx, ry, phi, large, sweep, x2, y2):
    if abs(x1 - x2) < 1e-9 and abs(y1 - y2) < 1e-9:
        return []
    if rx == 0 or ry == 0:
        return [(x1, y1, x2, y2, x2, y2)]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(phi % 360)
    cos, sin = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cos * dx + sin * dy
    y1p = -sin * dx + cos * dy
    radius = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if radius > 1:
        scale = math.sqrt(radius)
        rx *= scale
        ry *= scale
    sign = -1 if large == sweep else 1
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = sign * math.sqrt(max(0, num / den)) if den else 0
    cxp = coef * rx * y1p / ry
    cyp = coef * -ry * x1p / rx
    cx = cos * cxp - sin * cyp + (x1 + x2) / 2
    cy = sin * cxp + cos * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        length = math.hypot(ux, uy) * math.hypot(vx, vy)
        value = math.acos(max(-1, min(1, dot / length))) if length else 0
        if ux * vy - uy * vx < 0:
            value = -value
        return value

    theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi
    curves = []
    pieces = max(1, math.ceil(abs(delta) / (math.pi / 2)))
    step = delta / pieces
    for index in range(pieces):
        start = theta1 + index * step
        end = start + step
        alpha = math.sin(step) * (math.sqrt(4 + 3 * math.tan(step / 2) ** 2) - 1) / 3

        def point(theta, derivative):
            px = cx + rx * cos * math.cos(theta) - ry * sin * math.sin(theta)
            py = cy + rx * sin * math.cos(theta) + ry * cos * math.sin(theta)
            dx_ = -rx * cos * math.sin(theta) - ry * sin * math.cos(theta)
            dy_ = -rx * sin * math.sin(theta) + ry * cos * math.cos(theta)
            return (px, py) if derivative == 0 else (dx_, dy_)

        p1 = point(start, 0)
        d1 = point(start, 1)
        p2 = point(end, 0)
        d2 = point(end, 1)
        curves.append((p1[0] + alpha * d1[0], p1[1] + alpha * d1[1], p2[0] - alpha * d2[0], p2[1] - alpha * d2[1], p2[0], p2[1]))
    return curves


def flatten(data):
    parts = tokens(data)
    index = 0
    command = ""
    x = y = 0.0
    start_x = start_y = 0.0
    prev_cx = prev_cy = None
    out = []

    def number():
        nonlocal index
        value = float(parts[index])
        index += 1
        return value

    while index < len(parts):
        if parts[index].isalpha():
            command = parts[index]
            index += 1
        relative = command.islower()
        kind = command.upper()
        if kind == "Z":
            out.append(("z",))
            x, y = start_x, start_y
            prev_cx = prev_cy = None
            continue
        if kind == "M":
            nx, ny = number(), number()
            if relative:
                nx += x
                ny += y
            x, y = nx, ny
            start_x, start_y = x, y
            out.append(("m", x, y))
            command = "l" if relative else "L"
            prev_cx = prev_cy = None
            continue
        if kind == "L":
            nx, ny = number(), number()
            if relative:
                nx += x
                ny += y
            out.append(("l", nx, ny))
            x, y = nx, ny
            prev_cx = prev_cy = None
            continue
        if kind == "H":
            nx = number() + (x if relative else 0)
            out.append(("l", nx, y))
            x = nx
            prev_cx = prev_cy = None
            continue
        if kind == "V":
            ny = number() + (y if relative else 0)
            out.append(("l", x, ny))
            y = ny
            prev_cx = prev_cy = None
            continue
        if kind == "C":
            values = [number() for _ in range(6)]
            if relative:
                values = [values[i] + (x if i % 2 == 0 else y) for i in range(6)]
            out.append(("c", *values))
            prev_cx, prev_cy = values[2], values[3]
            x, y = values[4], values[5]
            continue
        if kind == "S":
            x2, y2, nx, ny = number(), number(), number(), number()
            if relative:
                x2 += x
                y2 += y
                nx += x
                ny += y
            c1x = x * 2 - prev_cx if prev_cx is not None else x
            c1y = y * 2 - prev_cy if prev_cy is not None else y
            out.append(("c", c1x, c1y, x2, y2, nx, ny))
            prev_cx, prev_cy = x2, y2
            x, y = nx, ny
            continue
        if kind == "A":
            rx, ry, phi, large, sweep, nx, ny = number(), number(), number(), number(), number(), number(), number()
            if relative:
                nx += x
                ny += y
            for curve in arc_cubics(x, y, rx, ry, phi, large != 0, sweep != 0, nx, ny):
                out.append(("c", *curve))
            prev_cx = prev_cy = None
            x, y = nx, ny
            continue
        raise SystemExit(f"unsupported path command {command}")
    return out


def swift_number(value):
    return f"{value:.4f}".rstrip("0").rstrip(".")


def emit(name, paths):
    lines = [f'    "{name}": [']
    for path in paths:
        body = []
        for item in flatten(path):
            if item[0] == "z":
                body.append(".close")
            else:
                numbers = ", ".join(swift_number(part) for part in item[1:])
                kind = {"m": "move", "l": "line", "c": "cubic"}[item[0]]
                body.append(f".{kind}({numbers})")
        lines.append("        [" + ", ".join(body) + "],")
    lines.append("    ],")
    return lines


def main():
    files = sorted(DRAWABLE.glob("ic_kit_*.xml"))
    if len(files) != 122:
        raise SystemExit(f"expected 122 lucide vectors, found {len(files)}")
    rows = ["// SPDX-License-Identifier: AGPL-3.0-or-later", "// Copyright (c) 2026 Span Brain", "enum KitIconOp {", "    case move(CGFloat, CGFloat)", "    case line(CGFloat, CGFloat)", "    case cubic(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)", "    case close", "}", "", "enum KitIconPaths {", "    static let glyphs: [String: [[KitIconOp]]] = ["]
    for file in files:
        name = file.name.removeprefix("ic_kit_").removesuffix(".xml").replace("_", "-")
        data = re.findall(r'android:pathData="([^"]*)"', file.read_text())
        rows.extend(emit(name, data))
    rows.append("    ]")
    rows.append("}")
    rows.append("")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(rows))
    print(f"ICONS {len(files)} {OUT}")


if __name__ == "__main__":
    main()
