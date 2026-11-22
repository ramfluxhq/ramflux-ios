# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Minimal dependency-free PNG reader and writer shared by the design comparison scripts.

Reads 8-bit and 16-bit RGB and RGBA images (16-bit samples keep their high byte).
Writes 8-bit RGB or RGBA with filter type 0 and zlib level 9, so the same pixels
always produce the same bytes.
"""

import struct
import zlib
from pathlib import Path


def paeth(left, up, upper_left):
    estimate = left + up - upper_left
    scores = (abs(estimate - left), abs(estimate - up), abs(estimate - upper_left))
    return (left, up, upper_left)[scores.index(min(scores))]


def read_png(path):
    """Return (width, height, channels, rows); rows hold 8-bit samples."""
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
            if bit not in (8, 16) or color not in (2, 6) or chunk[12] != 0:
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
        if filter_type == 2:
            row = bytearray((a + b) & 255 for a, b in zip(row, previous))
        elif filter_type != 0:
            for column in range(stride):
                left = row[column - bytes_per_pixel] if column >= bytes_per_pixel else 0
                up = previous[column]
                upper_left = previous[column - bytes_per_pixel] if column >= bytes_per_pixel else 0
                if filter_type == 1:
                    row[column] = (row[column] + left) & 255
                elif filter_type == 3:
                    row[column] = (row[column] + ((left + up) // 2)) & 255
                elif filter_type == 4:
                    row[column] = (row[column] + paeth(left, up, upper_left)) & 255
                else:
                    raise SystemExit(f"bad filter in {path}")
        previous = row
        if bit == 16:
            row = row[0::2]
        rows.append(row)
    return width, height, channels, rows


def write_png(path, width, height, rows, channels=3):
    """Write 8-bit RGB (channels=3) or RGBA (channels=4) rows."""
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)
    compressed = zlib.compress(bytes(raw), 9)

    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

    color = 6 if channels == 4 else 2
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))
