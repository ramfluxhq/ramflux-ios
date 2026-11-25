#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
#
# Debug operations script: injects one of the payloads in scripts/push/payloads into the Debug app on a
# simulator with `xcrun simctl push`. It is not part of any test target. Prints only the class and the outcome.
#
#   scripts/push/inject.sh CLASS [--simulator NAME] [--account ACCOUNT_ID]
#   CLASS: message | test | clear | call-alert | unknown-route | unknown-class | debug-call
#
# ROUTE_TAG in the payload is replaced with the route tag of the account (default: the first one) from the
# route map in the app's App Group container (push/routes.json); neither is printed. When the app has not
# written a route map yet, a tag that no account owns is used, which is what the unknown-route class sends.
#
# Preparation (once per simulator and install): run the suite with RAMFLUX_REALRUN_ALLOW_NOTIFICATIONS=1, for example
#   RAMFLUX_REALRUN_ALLOW_NOTIFICATIONS=1 scripts/realrun.sh run --only test01_onboardingCustomNodeAccountLockUnlock
# so the onboarding flow accepts the notification prompt; without that grant `simctl push` refuses (outcome=refused).
#
# Environment: RAMFLUX_BUNDLE_ID (default org.ramflux.ios.dev) is the Debug bundle id; the App Group is
# group.<bundle id>.
set -eu
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
kind=${1:-}
[ -n "$kind" ] || { echo "usage: inject.sh CLASS [--simulator NAME] [--account ACCOUNT_ID]" >&2; exit 2; }
shift
sim=rf-realrun
account=""
while [ $# -gt 0 ]; do
  case "$1" in
    --simulator) sim=$2; shift 2 ;;
    --account) account=$2; shift 2 ;;
    *) echo "inject: unknown option $1" >&2; exit 2 ;;
  esac
done
bundle=${RAMFLUX_BUNDLE_ID:-org.ramflux.ios.dev}
payload=$here/payloads/$kind.apns
[ -f "$payload" ] || { echo "inject: no payload for class '$kind'" >&2; exit 2; }
python=/opt/homebrew/bin/python3; [ -x "$python" ] || python=python3
udid=$(xcrun simctl list devices -j | "$python" -I -c 'import json,sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["name"] == sys.argv[1] and d.get("isAvailable") and d.get("state") == "Booted": print(d["udid"]); raise SystemExit' "$sim")
[ -n "$udid" ] || { echo "inject: simulator '$sim' is not booted" >&2; exit 1; }
tag=AAAAAAAAAAAAAAAAAAAAAA
group=$(xcrun simctl get_app_container "$udid" "$bundle" "group.$bundle" 2>/dev/null || true)
map=$group/push/routes.json
if [ -n "$group" ] && [ -f "$map" ]; then
  found=$("$python" -I -c 'import json,sys
routes = json.load(open(sys.argv[1]))
want = sys.argv[2]
for tag, owner in routes.items():
    if not want or owner == want:
        print(tag); break' "$map" "$account")
  [ -n "$found" ] && tag=$found
fi
filled=$(mktemp "${TMPDIR:-/tmp}/rf-inject.XXXXXX")
trap 'rm -f "$filled"' EXIT
sed -e "s/ROUTE_TAG/$tag/" -e "s/org\\.ramflux\\.ios\\.dev/$bundle/" "$payload" > "$filled"
if xcrun simctl push "$udid" "$filled" > /dev/null 2>&1; then
  echo "inject: class=$kind outcome=sent"
else
  echo "inject: class=$kind outcome=refused" >&2
  exit 1
fi
