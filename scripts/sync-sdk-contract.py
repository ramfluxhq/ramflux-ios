#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Copy the SDK-owned ABI and emit names-only Swift forwarding APIs (no payload schema)."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("sdk", type=pathlib.Path)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
sdk = args.sdk.resolve()
def committed(path):
    return subprocess.check_output(["git", "-C", str(sdk), "show", "HEAD:" + path])
source = committed("crates/ramflux-sdk/include/ramflux_sdk.h")
if b"ramflux_v2_operation_poll" not in source or len(source) > 1_048_576:
    raise SystemExit("SDK v2 header missing or oversized")
license_header = b"// SPDX-License-Identifier: BSD-3-Clause\n// Copyright (c) 2026 Span Brain\n"
(root / "Sources/CRamflux/include/ramflux_sdk.h").write_bytes(license_header + source)
methods_source = committed("crates/ramflux-sdk/src/bus/method_table.rs").decode()
methods_source = methods_source.split("methods! {", 1)[1].split("#[cfg(test)]", 1)[0]
entries = []
for classification, names in re.findall(r"(\w+)\(\w+\)\s*=>\s*\w+:\s*\[(.*?)\];", methods_source, re.S):
    entries.extend((name, classification == "LocalRead") for name in re.findall(r'"([a-z0-9_.]+)"', names)
                   if "itest" not in name and name != "daemon.stop")
entries.extend(("account." + name, name in ("create.hidden_challenge",)) for name in [
    "create.begin", "create.show_once", "create.hidden_challenge", "create.confirm", "create.cancel",
    "recover.begin", "recover.confirm", "recover.cancel"])
entries = sorted(set(entries))
secret_methods = {"account.unlock", "account.passphrase.rotate", "account.backup.import",
                  "account.backup.export", "account.export_agent_credentials", "account.create.confirm", "account.recover.confirm"}
license_swift = "// SPDX-License-Identifier: AGPL-3.0-or-later\n// Copyright (c) 2026 Span Brain\n"
lines = [license_swift, "// Generated names-only adapter. SDK request/response bodies remain authoritative.\n",
         "public enum SDKOperation: String, CaseIterable, Sendable {\n"]
def swift_name(name):
    parts = name.replace("_", ".").split(".")
    return parts[0] + "".join(x.title() for x in parts[1:])
for name, _ in entries:
    lines.append(f'    case {swift_name(name)} = "{name}"\n')
lines.append("    public var requiresOperationID: Bool {\n        switch self {\n")
reads = ["." + swift_name(name) for name, read in entries if read]
lines.append("        case " + ", ".join(reads) + ": false\n        default: true\n        }\n    }\n")
lines.append("    public var requiresSecureInput: Bool {\n        switch self {\n        case " + ", ".join("." + swift_name(n) for n in sorted(secret_methods)) + ": true\n        default: false\n        }\n    }\n}\n")
(root / "Sources/RamfluxCore/SDKOperation.swift").write_text("".join(lines))
protocols = []
for family in sorted({n.split('.')[0] for n, _ in entries}):
    title = family.upper() if family in ("a2i", "a2ui", "mcp") else family.title()
    protocols.append(f'public protocol {title}Proxy: SDKProxyProtocol {{}}\n')
    protocols.append(f'public extension {title}Proxy {{\n')
    for name, _ in entries:
        if name.split('.')[0] != family:
            continue
        method = swift_name(name)
        if name in secret_methods:
            protocols.append(f'    func {method}(context: RequestContext, body: JSONValue = .object([:]), secrets: [String: SecretField]) async throws -> JSONValue {{\n        try await performSecret(.{method}, context: context, body: body, secrets: secrets)\n    }}\n')
        else:
            protocols.append(f'    func {method}(context: RequestContext, body: JSONValue = .object([:])) async throws -> JSONValue {{\n        try await perform(.{method}, context: context, body: body)\n    }}\n')
    protocols.append('}\n')
(root / "Sources/RamfluxCore/OperationProxies.swift").write_text(license_swift + "// Generated forwarding methods; no business logic or payload schema.\n" + "".join(protocols))
sha = subprocess.check_output(["git", "-C", str(sdk), "rev-parse", "HEAD"], text=True).strip()
(root / "docs/sdk-contract.json").write_text(json.dumps({"sourceCommit": sha,
    "headerSHA256": hashlib.sha256(source).hexdigest(), "operationCount": len(entries)}, indent=2) + "\n")
print(f"Synced ABI header and {len(entries)} forwarding operations")
