#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Print the UDID of the capture simulator: one named device on one iOS runtime.

Usage:
  select-simulator.py --device "iPhone 17 Pro" --ios 26.5

Board and Kit captures are rasterised by the simulator runtime, so the runtime
is part of the capture toolchain. CI pins both the device and the runtime
instead of taking the first iPhone the image lists, which can be an older
runtime than the pinned Xcode and changes when the image changes. Exits 1 and
lists what is installed when the pinned simulator is missing.
"""
import argparse
import json
import subprocess
import sys

RUNTIME_PREFIX = "com.apple.CoreSimulator.SimRuntime.iOS-"


def select(devices, device, ios):
    runtime = RUNTIME_PREFIX + ios.replace(".", "-")
    for item in devices.get(runtime, []):
        if item.get("isAvailable") and item.get("name") == device:
            return item["udid"]
    return None


def installed(devices):
    lines = []
    for runtime, items in sorted(devices.items()):
        if not runtime.startswith(RUNTIME_PREFIX):
            continue
        names = sorted({item["name"] for item in items if item.get("isAvailable") and item["name"].startswith("iPhone")})
        version = runtime[len(RUNTIME_PREFIX):].replace("-", ".")
        lines.append(f"  iOS {version}: {', '.join(names) or '-'}")
    return lines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--ios", required=True, help="runtime version, for example 26.5")
    args = parser.parse_args()
    listing = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        check=True, capture_output=True, text=True,
    ).stdout
    devices = json.loads(listing)["devices"]
    udid = select(devices, args.device, args.ios)
    if udid is None:
        print(f"SIMULATOR_MISSING: {args.device} on iOS {args.ios}; installed:", file=sys.stderr)
        print("\n".join(installed(devices)) or "  none", file=sys.stderr)
        return 1
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
