#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
#
# Opt-in real run of the beta flows: the native app with the real SDK against the local node in
# ops/local-node, with the alice and bob peers driven through the rf CLI.
#
#   scripts/realrun.sh [--out DIR] [--simulator NAME] [--only TEST[,TEST...]] [--keep-app] [--no-clock-sync]
#   scripts/realrun.sh prepare [--out DIR] [--simulator NAME] [--keep-app]
#   scripts/realrun.sh rebuild
#   scripts/realrun.sh run --only TEST[,TEST...]
#   scripts/realrun.sh finish
#
# Steps: check the node and peers, build the native app and the RamfluxRealRun UI tests, reset the
# app's data and Keychain on the simulator, start the loopback peer-control server, run the suite,
# and write DIR/flow-table.md (PASS / FAIL / BLOCKED / NOT RUN per flow) with screenshots.
# Without a phase everything runs in one command. With phases the run is split into commands that each
# stay short: `prepare` does the steps up to the control server and leaves the server running,
# `run` runs some flows on the prepared app (repeat it with further flows; tests are named as for
# --only), `rebuild` builds the app and suite again for the next `run` (the app keeps its data), and `finish` writes the flow table and stops the server. The node origin, operator key and
# fingerprint come from ops/local-node/node-facts.json, the peers from peers.json.
# The account code and recovery words are generated or read inside the test process only; typed
# text is redacted from the saved xcodebuild log and the result bundle is deleted.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
LOCAL_NODE=${RAMFLUX_LOCAL_NODE:-/Users/nn/worker/ramfluxhq/ops/local-node}
MOBILE_ENV=${RAMFLUX_MOBILE_ENV:-/Users/nn/worker/ramfluxhq/ops/mobile-env.sh}
XCFRAMEWORK=${RAMFLUX_CORE_XCFRAMEWORK:-build/RamfluxSDKBinary.xcframework}
SIM_NAME=rf-realrun
OUT=$ROOT/build/realrun/$(date -u '+%Y%m%dT%H%M%SZ')
ONLY=""
KEEP_APP=0
CLOCK_SYNC=1
PHASE=all
CONTROL_PID=""
case "${1:-}" in prepare|rebuild|run|finish) PHASE=$1; shift ;; esac
# Phased runs keep their settings here between commands (public values only).
STATE_FILE=$ROOT/build/realrun/current.env
if [ "$PHASE" = run ] || [ "$PHASE" = rebuild ] || [ "$PHASE" = finish ]; then
  [ -f "$STATE_FILE" ] || { echo "realrun: error: no prepared run ($STATE_FILE); run scripts/realrun.sh prepare first" >&2; exit 1; }
  . "$STATE_FILE"
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=$2; shift 2 ;;
    --simulator) SIM_NAME=$2; shift 2 ;;
    --only) ONLY=$2; shift 2 ;;
    --keep-app) KEEP_APP=1; shift ;;
    --no-clock-sync) CLOCK_SYNC=0; shift ;;
    *) echo "usage: scripts/realrun.sh [prepare|run|finish] [--out DIR] [--simulator NAME] [--only TEST[,TEST...]] [--keep-app] [--no-clock-sync]" >&2; exit 2 ;;
  esac
done

say() { printf 'realrun: %s\n' "$*"; }
die() { printf 'realrun: error: %s\n' "$*" >&2; exit 1; }

[ -f "$MOBILE_ENV" ] && . "$MOBILE_ENV"
PYTHON=/opt/homebrew/bin/python3; [ -x "$PYTHON" ] || PYTHON=python3
cd "$ROOT"
[ -d "$XCFRAMEWORK" ] || die "native SDK artifact $XCFRAMEWORK is missing (scripts/build-xcframework.sh)"
mkdir -p "$OUT"
OUT=$(CDPATH='' cd -- "$OUT" && pwd)
DERIVED=$ROOT/build/realrun-derived
RESULT_BUNDLE=$DERIVED/realrun.xcresult
facts() { "$PYTHON" -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$LOCAL_NODE/node-facts.json" "$1"; }
peer() { "$PYTHON" -I -c 'import json,sys; print(next(p for p in json.load(open(sys.argv[1]))["peers"] if p["name"]==sys.argv[2])[sys.argv[3]])' "$LOCAL_NODE/peers.json" "$1" "$2"; }

# Branch proofs live at most 300 s. On this Mac the podman VM clock has lost minutes per quarter hour
# (chrony sees the offset but does not step), and then every session fails with "branch proof or
# challenge expired". Unless --no-clock-sync is given, a one-command run sets the VM clock from the Mac's
# clock now and every 30 s while the suite runs; the keeper stops on exit. Phased runs never change the
# clock: they check the skew before each phase and stop when it is over 120 s.
node_skew() {
  now=$(podman exec rfbeta_ramflux-gateway_1 date -u +%s 2>/dev/null || echo 0)
  skew=$(( $(date -u +%s) - now )); [ "$skew" -lt 0 ] && skew=$(( -skew )); echo "$skew"
}
sync_node_clock() { podman machine ssh "sudo date -u -s @$(date -u +%s) > /dev/null" > /dev/null 2>&1; }
check_skew() {
  SKEW=$(node_skew)
  [ "$SKEW" -le 120 ] || die "node clock differs from the Mac by ${SKEW} s; set it with: podman machine ssh \"sudo date -u -s @\$(date -u +%s)\""
}
CLOCK_PID=""

# 3. Build the native app and the suite.
build_all() {
  say "building the native app and the real-run suite (log: $OUT/build.log)"
  export RAMFLUX_CORE_XCFRAMEWORK="$XCFRAMEWORK"
  xcodegen generate > "$OUT/build.log" 2>&1 || die "xcodegen failed (see $OUT/build.log)"
  xcodebuild -project Ramflux.xcodeproj -scheme RamfluxRealRun -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" -jobs "${RAMFLUX_XCODEBUILD_JOBS:-6}" build-for-testing >> "$OUT/build.log" 2>&1 \
    || { grep -E "error:|BUILD FAILED" "$OUT/build.log" | sort -u | head -20 >&2; die "build failed (see $OUT/build.log)"; }
}

prepare() {
  START=$(date +%s)
  # 1. Node and peers.
  say "checking the local node"
  "$LOCAL_NODE/status.sh" > "$OUT/node-status.log" 2>&1 || die "local node is not healthy (see $OUT/node-status.log; run $LOCAL_NODE/up.sh)"
  if [ "$CLOCK_SYNC" = 1 ] && [ "$PHASE" = all ]; then
    [ "$(node_skew)" -le 5 ] || { say "setting the node VM clock from the Mac (skew $(node_skew) s)"; sync_node_clock; }
    ( while :; do sleep 30; sync_node_clock; done ) > /dev/null 2>&1 &
    CLOCK_PID=$!
  fi
  check_skew
  "$LOCAL_NODE/peers.sh" status > "$OUT/peers-status.log" 2>&1
  grep -q 'alice: running' "$OUT/peers-status.log" && grep -q 'bob: running' "$OUT/peers-status.log" \
    || "$LOCAL_NODE/peers.sh" start >> "$OUT/peers-status.log" 2>&1 || die "peer daemons are not running"
  # After a clock correction the peer daemons reconnect within seconds; give them a minute.
  i=0; until [ "$("$LOCAL_NODE/peers.sh" status | grep -c 'networking=live')" = 2 ] || [ $i -ge 12 ]; do i=$((i + 1)); sleep 5; done
  for name in alice bob; do
    "$LOCAL_NODE/peers.sh" status | grep -A1 "^$name:" | grep -q 'networking=live' \
      || say "warning: $name is not networking live now (flows that need $name report it; see $OUT/peers-status.log)"
  done

  # 2. Simulator.
  UDID=$(xcrun simctl list devices -j | "$PYTHON" -I -c 'import json,sys
name=sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["name"] == name and d.get("isAvailable"): print(d["udid"]); raise SystemExit' "$SIM_NAME")
  if [ -z "$UDID" ]; then
    RUNTIME=$(xcrun simctl list runtimes -j | "$PYTHON" -I -c 'import json,sys
r=[x for x in json.load(sys.stdin)["runtimes"] if x["platform"]=="iOS" and x["isAvailable"]]
print(sorted(r, key=lambda x: [int(p) for p in x["version"].split(".")])[-1]["identifier"])')
    UDID=$(xcrun simctl create "$SIM_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$RUNTIME")
    say "created simulator $SIM_NAME ($UDID)"
  fi
  # The simulator runs in its window, not headless: on Xcode 27 that window is DeviceHub. It stays open
  # after the run, and so does the simulator, so the app state can be inspected afterwards.
  open /Applications/Xcode.app/Contents/Applications/DeviceHub.app 2>/dev/null || say "DeviceHub is not available; the simulator runs without its window"
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b > /dev/null

  build_all

  # 4. Reset the app: its container and the simulator Keychain (Keychain items survive an uninstall).
  if [ "$KEEP_APP" = 0 ]; then
    say "resetting the app data and Keychain on $SIM_NAME"
    xcrun simctl terminate "$UDID" org.ramflux.ios 2>/dev/null || true
    xcrun simctl uninstall "$UDID" org.ramflux.ios 2>/dev/null || true
    xcrun simctl keychain "$UDID" reset
  fi

  # 5. Peer-control server on a free loopback port. A one-command run stops it on exit; a phased run
  # leaves it running for the run phases and `finish` stops it.
  PORT=$("$PYTHON" -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
  if [ "$PHASE" = prepare ]; then
    # A new session, so the server outlives this command's process group; its pid is kept for `finish`.
    CONTROL_PID=$("$PYTHON" -I -c 'import subprocess,sys
log=open(sys.argv[1],"ab")
p=subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
print(p.pid)' "$OUT/peer-control.log" "$PYTHON" -I "$ROOT/scripts/realrun/peer_control.py" --port "$PORT" --out "$OUT" --local-node "$LOCAL_NODE" \
      --udid "$UDID" --app "$DERIVED/Build/Products/Debug-iphonesimulator/Ramflux.app")
  else
    "$PYTHON" -I "$ROOT/scripts/realrun/peer_control.py" --port "$PORT" --out "$OUT" --local-node "$LOCAL_NODE" \
      --udid "$UDID" --app "$DERIVED/Build/Products/Debug-iphonesimulator/Ramflux.app" > "$OUT/peer-control.log" 2>&1 &
    CONTROL_PID=$!
  fi
  i=0; until curl -sf "http://127.0.0.1:$PORT/health" > /dev/null; do i=$((i + 1)); [ $i -lt 50 ] || die "peer control did not start"; sleep 0.2; done

  # A test image in the simulator photo library for the media flow; its hash is compared on the peer side.
  "$PYTHON" -I -c 'import json,urllib.request,sys
req=urllib.request.Request("http://127.0.0.1:%s/make-file" % sys.argv[1], data=json.dumps({"name":"phone-photo.png","kind":"png","size":120000}).encode(), headers={"Content-Type":"application/json"})
print(json.load(urllib.request.urlopen(req))["path"])' "$PORT" > "$OUT/phone-photo.path"
  xcrun simctl addmedia "$UDID" "$(cat "$OUT/phone-photo.path")" || say "warning: addmedia failed; the send-image step will report it"
  if [ "$PHASE" = prepare ]; then
    printf 'OUT=%s\nUDID=%s\nPORT=%s\nCONTROL_PID=%s\nSTART=%s\n' "$OUT" "$UDID" "$PORT" "$CONTROL_PID" "$START" > "$STATE_FILE"
    say "prepared: control server pid $CONTROL_PID on port $PORT; run flows with: scripts/realrun.sh run --only TEST[,TEST...]; end with: scripts/realrun.sh finish"
  fi
}

# 6. Run the suite (or the tests named by --only, comma separated).
run_suite() {
  export TEST_RUNNER_RF_REALRUN_CONTROL="http://127.0.0.1:$PORT"
  export TEST_RUNNER_RF_NODE_ORIGIN="$(facts discovery_origin)"
  export TEST_RUNNER_RF_NODE_OPERATOR_KEY="$(facts node_public_key)"
  export TEST_RUNNER_RF_NODE_FINGERPRINT="$(facts node_key_fingerprint)"
  for name in alice bob; do
    key=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')
    eval "export TEST_RUNNER_RF_PEER_${key}_PRINCIPAL=\"\$(peer $name principal_id)\""
    eval "export TEST_RUNNER_RF_PEER_${key}_COMMITMENT=\"\$(peer $name principal_commitment)\""
    eval "export TEST_RUNNER_RF_PEER_${key}_NAME=\"\$(peer $name display_name)\""
  done
  export TEST_RUNNER_RF_PHONE_PHOTO="$(cat "$OUT/phone-photo.path")"
  FILTER=""
  for test in $(printf '%s' "$ONLY" | tr ',' ' '); do
    case "$test" in
      */*|RealRun*) FILTER="$FILTER -only-testing:RamfluxRealRunUITests/$test" ;;
      *) FILTER="$FILTER -only-testing:RamfluxRealRunUITests/RealRunFlowTests/$test" ;;
    esac
  done
  rm -rf "$RESULT_BUNDLE"
  # shellcheck disable=SC2086
  xcodebuild -project Ramflux.xcodeproj -scheme RamfluxRealRun -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" -resultBundlePath "$RESULT_BUNDLE" test-without-building $FILTER 2>&1 \
    | sed -E "s/(Type|Typing) '[^']*'/\\1 '<redacted>'/g" >> "$OUT/xcodebuild-test.log"
  # The result bundle holds the test activity log, which names typed text; it is never kept.
  rm -rf "$RESULT_BUNDLE"
}

# 7. Flow table.
flow_table() {
  "$PYTHON" -I "$ROOT/scripts/realrun/flow_table.py" "$OUT" "$(( $(date +%s) - START ))" > "$OUT/flow-table.md"
  cat "$OUT/flow-table.md"
  say "output: $OUT"
}
stop_control() {
  [ -n "$CONTROL_PID" ] && kill "$CONTROL_PID" 2>/dev/null || true
  [ -n "$CLOCK_PID" ] && kill "$CLOCK_PID" 2>/dev/null || true
  rm -rf "$RESULT_BUNDLE"
}

case "$PHASE" in
  prepare)
    trap '[ -f "$STATE_FILE" ] || stop_control' EXIT INT TERM
    mkdir -p "$(dirname "$STATE_FILE")"; rm -f "$STATE_FILE"
    prepare
    ;;
  rebuild)
    build_all
    ;;
  run)
    [ -n "$ONLY" ] || die "run needs --only TEST[,TEST...]"
    curl -sf "http://127.0.0.1:$PORT/health" > /dev/null || die "the control server of the prepared run is not running; prepare again"
    check_skew
    say "running $ONLY (log: $OUT/xcodebuild-test.log)"
    set +e; run_suite; set -e
    "$PYTHON" -I -c 'import json,sys
for k,v in json.load(open(sys.argv[1])).items(): print("realrun:", k, v["status"])' "$OUT/results.json" 2>/dev/null || true
    ;;
  finish)
    flow_table
    stop_control
    rm -f "$STATE_FILE"
    say "control server stopped"
    grep -q '| FAIL |' "$OUT/flow-table.md" && exit 1
    ;;
  all)
    trap stop_control EXIT INT TERM
    prepare
    # The account code and recovery words live only in the test runner's memory, so a runner restart
    # (seen under load: "Restarting after unexpected exit") loses the account for every later flow. When
    # flow 1 left no result, the suite runs once more from a clean app.
    set +e
    for attempt in 1 2; do
      say "running the suite, attempt $attempt (log: $OUT/xcodebuild-test.log)"
      run_suite
      grep -q '"01-onboarding"' "$OUT/results.json" 2>/dev/null && break
      [ -n "$ONLY" ] && break
      say "flow 1 left no result (test runner restart); resetting the app and running again"
      xcrun simctl terminate "$UDID" org.ramflux.ios 2>/dev/null
      xcrun simctl uninstall "$UDID" org.ramflux.ios 2>/dev/null
      xcrun simctl keychain "$UDID" reset
      rm -f "$OUT/results.json"
    done
    set -e
    flow_table
    grep -q '| FAIL |' "$OUT/flow-table.md" && exit 1
    ;;
esac
exit 0
