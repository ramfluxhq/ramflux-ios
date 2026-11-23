#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Write the real-run flow table (Markdown) from DIR/results.json; flows without a result are NOT RUN.

Usage: flow_table.py DIR SECONDS
"""
import json
import sys
from pathlib import Path

# Run order of the brief; ids match RealRunFlowTests.
FLOWS = [
    ("01-onboarding", "1 Connect to the custom node, create account, recovery phrase, code, lock, unlock"),
    ("03-conversations", "3 Conversation list shows real rows"),
    ("06-contacts", "6 Add alice, request handled by the peer, safety number, verified"),
    ("04-direct-chat", "4 Direct chat with alice both ways (send, receive, reply, edit, erase, receipts)"),
    ("04b-offline-queue", "4 Offline send queued and delivered after reconnect (needs a network cut; not scripted)"),
    ("04c-background", "4 Background and return keeps the session and queued sends"),
    ("07-media", "7 Media M1: receive image and file, view, send image with identical bytes"),
    ("05-groups", "5 Groups: create with alice and bob, send and receive, members"),
    ("10-settings", "10 Settings: lock, devices, language"),
    ("10b-change-code", "10 Change account code (account.passphrase.rotate)"),
    ("14-backup", "14 Backup: create and verify"),
    ("14b-restore", "14 Restore the backup on a fresh install as a new account"),
    ("02-pairing", "2 Inviter-side pairing (invitation appears)"),
    ("08-agents", "8 Agents list (expected empty)"),
    ("09-tasks", "9 Tasks list (expected empty)"),
    ("12-calls", "12 Calls screen honest unavailable state"),
    ("15-privacy", "15 Privacy: request policy and open-account unavailable state"),
]


# Flows the suite does not script yet, with the reason shown instead of a missing result.
NOT_SCRIPTED = {
    "04b-offline-queue": "not run: the client has no debug seam that makes its transport fail (all traffic is the Rust SDK's own reqwest/quinn), and cutting the node's published ports is not allowed; the background flow covers a send interrupted in flight",
}


def main():
    out, seconds = Path(sys.argv[1]), int(sys.argv[2])
    path = out / "results.json"
    results = json.loads(path.read_text()) if path.exists() else {}
    lines = ["# Real-run flow table", "", f"Duration: {seconds // 60} min {seconds % 60} s", "",
             "| Flow | Status | Detail |", "| --- | --- | --- |"]
    known = {flow for flow, _ in FLOWS}
    for flow, title in FLOWS + [(f, f) for f in results if f not in known]:
        entry = results.get(flow, {"status": "NOT RUN", "detail": NOT_SCRIPTED.get(flow, "no result recorded (suite stopped earlier or test filtered)")})
        detail = entry["detail"].replace("|", "/").replace("\n", " ")
        lines.append(f"| {title} | {entry['status']} | {detail} |")
    counts = {}
    for flow, _ in FLOWS:
        status = results.get(flow, {}).get("status", "NOT RUN")
        counts[status] = counts.get(status, 0) + 1
    lines += ["", "Totals: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())), "",
              "Screenshots: screenshots/. Peer commands: peer-commands.log. Test log (typed text redacted): xcodebuild-test.log."]
    print("\n".join(lines))


if __name__ == "__main__":
    main()
