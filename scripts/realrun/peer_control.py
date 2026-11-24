#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Loopback control server for the opt-in real-run UI suite (scripts/realrun.sh).

The XCUITest runner on the simulator shares the Mac's loopback, so it reaches this server over
plain HTTP and asks it to act as the peer side at the right moments: run an allow-listed `rf`
command on the alice or bob daemon, derive a direct conversation id, create a test file, record
a flow result or store a screenshot. The server never receives the phone account's six-digit code
or recovery words through any file or log. It only handles public identifiers and test message text, plus
the run state the suite hands over between its phases (/run-state: the throwaway test account's six-digit
code, the backup archive passphrase and public ids). That state lives in this process's memory only: it is
never written to disk or logged and is gone when the server stops (scripts/realrun.sh finish). The
recovery words never leave the test process.

Usage: peer_control.py --port N --out DIR --facts FILE --peers FILE --rf PATH --dm-helper COMMAND [--udid UDID --app PATH]

--facts is the node facts JSON (discovery_origin, node_id, node_public_key, node_key_fingerprint), --peers the
peers JSON (a "peers" list with name, account_id, display_name, principal_id, principal_commitment, device_id and
daemon_socket of each peer daemon), --rf the rf CLI, and --dm-helper a command that prints the direct conversation
id of two root commitments when called as `COMMAND dm-conversation ROOT_A ROOT_B`.

With --udid and --app it can also reinstall the app for the restore flow (/fresh-install): it copies the
newest backup archive out of the app's container into the simulator's "On My iPhone" storage (an encrypted
archive; its passphrase stays in the test process), uninstalls the app, resets the simulator Keychain and
installs the app again.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import shlex
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# First rf words the test may run on a peer daemon. Every command gets the peer's socket; account
# scoped commands get `--account` from peers.json. Nothing that exports keys or reads secrets.
ALLOWED = {
    ("contact", "card"), ("contact", "list"), ("contact", "accept"), ("contact", "add"), ("contact", "safety-number"),
    ("contact", "verification"), ("conversation", "send"), ("conversation", "reply"), ("conversation", "edit"),
    ("conversation", "delete"), ("conversation", "typing"), ("dm", "read"), ("dm", "list"), ("dm", "send"),
    ("dm", "receipt"), ("group", "list"), ("group", "read"), ("group", "send"), ("group", "accept"), ("group", "show"),
    ("group", "invitation"), ("group", "member"), ("group", "create"), ("group", "members"), ("group", "rename"), ("username", "resolve"), ("attachment", "import"), ("attachment", "enable"), ("account", "status"),
}
SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]{1,80}$")
STATUSES = {"PASS", "FAIL", "BLOCKED", "NOT RUN"}


BUNDLE = "org.ramflux.ios"


def image_info(path: Path):
    """Format and pixel size of an image as macOS decodes it (sips), or None when it is not a decodable image."""
    try:
        shown = subprocess.run(["sips", "-g", "format", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
                               capture_output=True, text=True, timeout=30)
        fields = dict(line.strip().split(": ", 1) for line in shown.stdout.splitlines()[1:] if ": " in line)
        with tempfile.TemporaryDirectory() as folder:
            decoded = subprocess.run(["sips", "-s", "format", "png", str(path), "--out", str(Path(folder) / "decoded.png")],
                                     capture_output=True, text=True, timeout=30)
        if shown.returncode != 0 or decoded.returncode != 0 or "pixelWidth" not in fields:
            return None
        return {"format": fields.get("format", ""), "width": int(fields["pixelWidth"]), "height": int(fields["pixelHeight"])}
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


class Harness:
    def __init__(self, out: Path, facts: Path, peers: Path, rf: str, dm_helper: str, udid: str = "", app: str = ""):
        self.out, self.rf, self.dm_helper, self.udid, self.app = out, rf, dm_helper, udid, app
        self.facts = json.loads(facts.read_text())
        self.peers = {p["name"]: p for p in json.loads(peers.read_text())["peers"]}
        self.lock = threading.Lock()
        self.results = {}
        # Run state between suite phases: memory only, never logged or written.
        self.run_state = {}
        (out / "screenshots").mkdir(parents=True, exist_ok=True)
        (out / "files").mkdir(parents=True, exist_ok=True)
        self.log_path = out / "peer-commands.log"

    def log(self, line: str):
        with self.lock, self.log_path.open("a") as handle:
            handle.write(time.strftime("%H:%M:%S ") + line + "\n")

    def config(self):
        return {"node": {k: self.facts[k] for k in ("discovery_origin", "node_id", "node_public_key", "node_key_fingerprint")},
                "peers": {name: {k: v for k, v in p.items() if k != "daemon_socket"} for name, p in self.peers.items()}}

    def run_rf(self, peer: str, args: list, timeout: float = 60):
        if peer not in self.peers:
            raise ValueError("unknown peer")
        if len(args) < 2 or not all(isinstance(a, str) for a in args) or (args[0], args[1]) not in ALLOWED:
            raise ValueError("command not allowed")
        command = [self.rf, "--socket", self.peers[peer]["daemon_socket"], *args]
        sub = args[2] if len(args) > 2 and not args[2].startswith("-") else None
        if "--account" not in args and not (args[0] == "conversation" and args[1] == "typing" and sub is None):
            command += ["--account", self.peers[peer]["account_id"]]
        # Conversation mutations require an idempotency token; each request is a new logical operation.
        if args[0] == "conversation" and "--operation-id" not in args and \
                (args[1] in ("send", "reply", "edit", "delete") or (args[1] == "typing" and sub in ("start", "stop"))):
            command += ["--operation-id", "realrun-" + os.urandom(8).hex()]
        started = time.time()
        try:
            done = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
            code, stdout, stderr = done.returncode, done.stdout, done.stderr
        except subprocess.TimeoutExpired as error:
            code, stdout, stderr = 124, error.stdout or "", "timeout"
            stdout = stdout.decode() if isinstance(stdout, bytes) else stdout
        self.log(f"{peer}: rf {' '.join(args[:2])} ... exit {code} in {time.time() - started:.1f}s"
                 + ("" if code == 0 else f" stderr={stderr.strip()[-400:]}"))
        value = None
        start = stdout.find("{")
        if start >= 0:
            try:
                value = json.JSONDecoder().raw_decode(stdout[start:])[0]
            except ValueError:
                value = None
        return {"exit": code, "json": value, "stdout": stdout[-20000:], "stderr": stderr[-4000:]}

    def dm_conversation(self, first: str, second: str) -> str:
        done = subprocess.run([*shlex.split(self.dm_helper), "dm-conversation", first, second],
                              capture_output=True, text=True, timeout=30, check=True)
        return done.stdout.strip()

    def make_file(self, name: str, kind: str, size: int) -> dict:
        if not SAFE_NAME.match(name) or not 1 <= size <= 4 * 1024 * 1024:
            raise ValueError("bad file request")
        path = self.out / "files" / name
        if kind == "png":
            path.write_bytes(png(size))
        else:
            seed = hashlib.sha256(name.encode()).digest()
            data = bytearray()
            while len(data) < size:
                seed = hashlib.sha256(seed).digest()
                data += base64.b64encode(seed)[:43] + b"\n"
            path.write_bytes(bytes(data[:size]))
        return {"path": str(path), "sha256": sha256(path), "size": path.stat().st_size}

    def file_info(self, path: str) -> dict:
        target = Path(path).resolve()
        if not str(target).startswith(str((self.out / "files").resolve())):
            raise ValueError("path outside the run folder")
        info = {"exists": target.exists(), "sha256": sha256(target) if target.exists() else None,
                "size": target.stat().st_size if target.exists() else 0}
        if target.exists():
            info["image"] = image_info(target)
        return info

    def simctl(self, *args, timeout: float = 120) -> str:
        return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True, timeout=timeout, check=True).stdout.strip()

    def fresh_install(self) -> dict:
        """Moves the newest backup archive to "On My iPhone", then reinstalls the app with an empty Keychain."""
        if not self.udid or not self.app:
            raise ValueError("fresh install needs --udid and --app")
        archive, data = None, b""
        for _ in range(5):
            # The archive may be replaced while it is listed (write then rename); list again on a miss.
            container = Path(self.simctl("get_app_container", self.udid, BUNDLE, "data"))
            listed = [p for p in (container / "Library" / "Application Support" / "ramflux" / "backups").rglob("*.rfb")]
            self.log("fresh install: archives listed " + ", ".join(f"{p.name}:{p.stat().st_size if p.exists() else -1}" for p in listed))
            for candidate in sorted((p for p in listed if p.exists()), key=lambda p: p.stat().st_mtime, reverse=True):
                try:
                    data, archive = candidate.read_bytes(), candidate
                    break
                except OSError:
                    continue
            if archive:
                break
            time.sleep(2)
        if not archive:
            raise ValueError("no readable backup archive in the app container")
        archives = [archive]
        groups = container.parents[2] / "Shared" / "AppGroup"
        local = None
        for group in groups.iterdir():
            meta = group / ".com.apple.mobile_container_manager.metadata.plist"
            if meta.exists() and "group.com.apple.FileProvider.LocalStorage" in subprocess.run(
                    ["plutil", "-extract", "MCMMetadataIdentifier", "raw", str(meta)], capture_output=True, text=True).stdout:
                local = group / "File Provider Storage"
        if local is None:
            raise ValueError("the simulator has no On My iPhone storage")
        local.mkdir(parents=True, exist_ok=True)
        name = "ramflux-realrun-" + time.strftime("%H%M%S") + (archives[-1].suffix or ".backup")
        (local / name).write_bytes(data)
        subprocess.run(["xcrun", "simctl", "terminate", self.udid, BUNDLE], capture_output=True, timeout=60)
        self.simctl("uninstall", self.udid, BUNDLE)
        self.simctl("keychain", self.udid, "reset")
        self.simctl("install", self.udid, self.app, timeout=300)
        self.log(f"fresh install: archive {name} ({len(data)} bytes) placed in On My iPhone; app reinstalled; keychain reset")
        return {"archive": name}

    def device_log(self, name: str, minutes: int) -> dict:
        """Saves the app's debug event trace (topics, cursors and counts only; see EventDiagnostics)."""
        if not self.udid or not SAFE_NAME.match(name):
            raise ValueError("device log needs --udid and a safe name")
        done = subprocess.run(["xcrun", "simctl", "spawn", self.udid, "log", "show", "--last", f"{max(1, min(minutes, 30))}m", "--debug", "--info",
                               "--style", "compact", "--predicate", 'subsystem == "org.ramflux.ios"'], capture_output=True, text=True, timeout=120)
        path = self.out / (name + ".log")
        path.write_text(done.stdout)
        return {"path": str(path), "lines": done.stdout.count("\n")}

    def record(self, flow: str, status: str, detail: str):
        if status not in STATUSES:
            raise ValueError("bad status")
        with self.lock:
            self.results[flow] = {"status": status, "detail": detail[:2000], "at": time.strftime("%H:%M:%S")}
            (self.out / "results.json").write_text(json.dumps(self.results, indent=2) + "\n")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png(size_hint: int) -> bytes:
    """A small RGB PNG with a deterministic gradient (about `size_hint` bytes of raw pixels)."""
    import struct
    import zlib
    side = max(8, min(512, int((size_hint / 3) ** 0.5)))
    rows = b"".join(b"\0" + bytes(((x * 7 + y * 3) % 256, (x * 2) % 256, (y * 5) % 256) [i] for x in range(side) for i in range(3))
                    for y in range(side))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", side, side, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def handler_for(harness: Harness):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):  # keep the console quiet; commands are logged by the harness
            pass

        def reply(self, status, value):
            body = json.dumps(value).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/config":
                return self.reply(200, harness.config())
            if self.path == "/run-state":
                with harness.lock:
                    return self.reply(200, dict(harness.run_state))
            if self.path == "/health":
                return self.reply(200, {"ok": True})
            return self.reply(404, {"error": "not found"})

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b""
            try:
                if self.path.startswith("/screenshot/"):
                    name = self.path.split("/", 2)[2]
                    if not SAFE_NAME.match(name):
                        raise ValueError("bad name")
                    (harness.out / "screenshots" / (name + ".png")).write_bytes(raw)
                    return self.reply(200, {"ok": True})
                body = json.loads(raw or b"{}")
                if self.path == "/rf":
                    return self.reply(200, harness.run_rf(body["peer"], body["args"], float(body.get("timeout", 60))))
                if self.path == "/dm-conversation":
                    return self.reply(200, {"conversation": harness.dm_conversation(body["first"], body["second"])})
                if self.path == "/make-file":
                    return self.reply(200, harness.make_file(body["name"], body.get("kind", "text"), int(body.get("size", 1024))))
                if self.path == "/fresh-path":
                    name = body.get("name", "import.bin")
                    if not SAFE_NAME.match(name):
                        raise ValueError("bad name")
                    target = harness.out / "files" / (time.strftime("%H%M%S-") + os.urandom(3).hex() + "-" + name)
                    return self.reply(200, {"path": str(target)})
                if self.path == "/file-info":
                    return self.reply(200, harness.file_info(body["path"]))
                if self.path == "/device-log":
                    return self.reply(200, harness.device_log(body.get("name", "device-events"), int(body.get("minutes", 5))))
                if self.path == "/fresh-install":
                    return self.reply(200, harness.fresh_install())
                if self.path == "/run-state":
                    if not isinstance(body, dict) or len(raw) > 65536 or not all(
                            isinstance(k, str) and isinstance(v, (str, list)) for k, v in body.items()):
                        raise ValueError("bad run state")
                    with harness.lock:
                        harness.run_state.update(body)
                    return self.reply(200, {"ok": True})
                if self.path == "/result":
                    harness.record(body["flow"], body["status"], body.get("detail", ""))
                    return self.reply(200, {"ok": True})
                if self.path == "/log":
                    harness.log("test: " + str(body.get("line", ""))[:60000])
                    return self.reply(200, {"ok": True})
                return self.reply(404, {"error": "not found"})
            except (KeyError, ValueError, TypeError, OSError, subprocess.SubprocessError) as error:
                harness.log(f"request {self.path} refused: {error!r}")
                return self.reply(400, {"error": str(error)})
    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--facts", type=Path, required=True)
    parser.add_argument("--peers", type=Path, required=True)
    parser.add_argument("--rf", required=True)
    parser.add_argument("--dm-helper", required=True)
    parser.add_argument("--udid", default="")
    parser.add_argument("--app", default="")
    options = parser.parse_args()
    options.out.mkdir(parents=True, exist_ok=True)
    harness = Harness(options.out, options.facts, options.peers, options.rf, options.dm_helper, options.udid, options.app)
    server = ThreadingHTTPServer(("127.0.0.1", options.port), handler_for(harness))
    print(f"peer control listening on 127.0.0.1:{options.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    os.umask(0o077)
    main()
