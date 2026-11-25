#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
#
# Fails when a Release app binary still contains the debug wake injector (App/Debug/DebugWakeInjector.swift,
# compiled only with RAMFLUX_DEBUG_WAKE).
#   scripts/check-release-symbols.sh path/to/Ramflux.app [--expect-present]
# With --expect-present the check is inverted: it passes only when the symbol is there (a Debug build), which
# proves the check can see it.
set -eu
app=${1:-}
[ -d "$app" ] || { echo "usage: check-release-symbols.sh path/to/Ramflux.app [--expect-present]" >&2; exit 2; }
binary=$app/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
# Debug simulator builds keep the code in <name>.debug.dylib next to the stub executable.
found=0
for candidate in "$binary" "$app"/*.debug.dylib; do
  [ -f "$candidate" ] || continue
  if strings -a "$candidate" | grep -q 'DebugWakeInjector'; then found=1; fi
done
if [ "${2:-}" = "--expect-present" ]; then
  [ "$found" = 1 ] && { echo "check-release-symbols: DebugWakeInjector present (expected in a Debug build)"; exit 0; }
  echo "check-release-symbols: DebugWakeInjector not found in a build that should have it" >&2; exit 1
fi
if [ "$found" = 1 ]; then echo "check-release-symbols: DebugWakeInjector found in $app" >&2; exit 1; fi
echo "check-release-symbols: no DebugWakeInjector in $app"
