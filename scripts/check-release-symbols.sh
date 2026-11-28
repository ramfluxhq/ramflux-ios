#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
#
# Fails when a Release app binary still contains the debug wake injector (App/Debug/DebugWakeInjector.swift,
# compiled only with RAMFLUX_DEBUG_WAKE) or the MLS gallery and its fixtures (App/Debug/MlsGallery.swift and
# Packages/AppData/Sources/AppData/Gallery, compiled only with RAMFLUX_MLS_GALLERY).
#   scripts/check-release-symbols.sh path/to/Ramflux.app [--expect-present]
# With --expect-present the check is inverted: it passes only when the symbol is there (a Debug build), which
# proves the check can see it.
set -eu
app=${1:-}
[ -d "$app" ] || { echo "usage: check-release-symbols.sh path/to/Ramflux.app [--expect-present]" >&2; exit 2; }
binary=$app/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
# Debug simulator builds keep the code in <name>.debug.dylib next to the stub executable.
patterns='DebugWakeInjector MlsGallery FixtureContactIdentityRepository FixtureMlsGroupRepository MlsGroupFixtures'
found=0
present=""
for candidate in "$binary" "$app"/*.debug.dylib; do
  [ -f "$candidate" ] || continue
  text=$(strings -a "$candidate")
  for pattern in $patterns; do
    if printf '%s\n' "$text" | grep -q -e "$pattern"; then found=1; present="$present $pattern"; fi
  done
done
if [ "${2:-}" = "--expect-present" ]; then
  # Every pattern must be present, not any one of them.
  missing=""
  for pattern in $patterns; do
    case " $present " in *" $pattern "*) ;; *) missing="$missing $pattern" ;; esac
  done
  [ -z "$missing" ] && { echo "check-release-symbols: debug wake injector and MLS gallery present (expected in a Debug build)"; exit 0; }
  echo "check-release-symbols: not found in a build that should have them:$missing" >&2; exit 1
fi
if [ "$found" = 1 ]; then echo "check-release-symbols: debug wake injector or MLS gallery found in $app" >&2; exit 1; fi
echo "check-release-symbols: no debug wake injector or MLS gallery in $app"
