#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Generate names-only Swift adapters from a pinned, SDK-owned method policy."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
POLICY_PATH = "crates/ramflux-sdk/include/ramflux_sdk_methods.json"
HEADER_PATH = "crates/ramflux-sdk/include/ramflux_sdk.h"
LICENSE = "// SPDX-License-Identifier: AGPL-3.0-or-later\n// Copyright (c) 2026 Span Brain\n"

def git(sdk, *args):
    return subprocess.check_output(["git", "-C", str(sdk), *args])

def swift_name(name):
    parts = name.replace("_", ".").split(".")
    return parts[0] + "".join(part.title() for part in parts[1:])

def validate_policy(policy):
    if policy.get("abi_major") != 2 or policy.get("policy_version") != 1:
        raise ValueError("unsupported SDK method policy")
    rows = policy.get("methods", [])
    if not rows or len(rows) > 4096:
        raise ValueError("invalid policy count")
    names, swift_names = set(), set()
    for row in rows:
        name = row.get("name", "")
        if not re.fullmatch(r"[a-z][a-z0-9_.]*", name) or "itest" in name:
            raise ValueError("invalid method name")
        identifier = swift_name(name)
        if name in names or identifier in swift_names:
            raise ValueError("duplicate method or Swift name collision")
        names.add(name); swift_names.add(identifier)
        if not re.fullmatch(r"[a-z][a-z0-9_]*", row.get("capability", "")):
            raise ValueError("invalid capability")
        if any(type(row.get(flag)) is not bool for flag in ["secret_input", "secret_output", "show_once"]):
            raise ValueError("missing SDK secret-handling policy")
        if row["show_once"] and not row["secret_output"]:
            raise ValueError("show_once must have secret output")
    return sorted(rows, key=lambda row: row["name"])

def generate(sdk, commit, update_pin=False, check=False):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("--commit must be a full immutable commit SHA")
    if git(sdk, "rev-parse", "HEAD").decode().strip() != commit:
        raise ValueError("SDK HEAD does not equal --commit")
    if git(sdk, "status", "--porcelain").strip():
        raise ValueError("SDK checkout must be clean")
    recorded = json.loads((ROOT / "docs/sdk-contract.json").read_text())
    if recorded["sourceCommit"] != commit and not update_pin:
        raise ValueError("commit differs from recorded sourceCommit; explicit --update-pin required")
    def source(path):
        return git(sdk, "show", commit + ":" + path)
    header = source(HEADER_PATH)
    policy_bytes = source(POLICY_PATH)
    policy = json.loads(policy_bytes)
    rows = validate_policy(policy)
    # Compare the committed JSON to its SDK Rust policy source, not a native secret list.
    policy_source = source("crates/ramflux-sdk/src/c_abi/v2/method_policy.rs").decode()
    rust_rows = re.findall(r'"([a-z][a-z0-9_.]*)"\s*=>\s*\(\s*"([a-z][a-z0-9_]*)"\s*,\s*(true|false)\s*,\s*(true|false)\s*,\s*(true|false)\s*\)', policy_source)
    expected = sorted([dict(name=n, capability=c, secret_input=i == "true", secret_output=o == "true", show_once=s == "true")
                       for n, c, i, o, s in rust_rows], key=lambda row: row["name"])
    if rows != expected or len(rows) != len(rust_rows):
        raise ValueError("SDK policy count/content differs from the source registry")
    if not update_pin and recorded["operationCount"] != len(rows):
        raise ValueError("operation count differs from recorded contract")
    method_table = source("crates/ramflux-sdk/src/bus/method_table.rs").decode().split("methods! {", 1)[1].split("#[cfg(test)]", 1)[0]
    reads = set()
    for names in re.findall(r"LocalRead\(\w+\)\s*=>\s*\w+:\s*\[(.*?)\];", method_table, re.S):
        reads.update(re.findall(r'"([a-z0-9_.]+)"', names))
    # The SDK-owned connection-local challenge names are reads; flagging other extra
    # operations as keyed is conservative and never fabricates a mutation identity.
    reads.update(row["name"] for row in rows if row["name"].endswith(".hidden_challenge"))
    reads.update(row["name"] for row in rows if row["name"].startswith(("account.create.", "account.custody.", "account.recover.")))
    lines = [LICENSE, "// Generated from the pinned SDK method policy. Do not edit.\n",
             "public enum SDKOperation: String, CaseIterable, Sendable {\n"]
    for row in rows:
        lines.append(f'    case {swift_name(row["name"])} = "{row["name"]}"\n')
    for property_name, flag in [("requiresSecureInput", "secret_input"), ("requiresSecureOutput", "secret_output"), ("showOnce", "show_once")]:
        cases = ["." + swift_name(row["name"]) for row in rows if row[flag]]
        lines.append(f'    public var {property_name}: Bool {{\n        switch self {{\n        case ' + ", ".join(cases) + ': true\n        default: false\n        }\n    }\n')
    lines.append('    public var requiresOperationID: Bool {\n        switch self {\n        case ' + ", ".join("." + swift_name(row["name"]) for row in rows if row["name"] in reads) + ': false\n        default: true\n        }\n    }\n')
    lines.append('    public var capability: String {\n        switch self {\n')
    for row in rows:
        lines.append(f'        case .{swift_name(row["name"])}: "{row["capability"]}"\n')
    lines.append('        }\n    }\n}\n')
    proxies = [LICENSE, "// Generated forwarding APIs; SDK payload schemas remain authoritative.\n"]
    for family in sorted({row["name"].split('.')[0] for row in rows}):
        title = family.upper() if family in ("a2i", "a2ui", "mcp") else family.title()
        proxies.append(f'public protocol {title}Proxy: SDKProxyProtocol {{}}\npublic extension {title}Proxy {{\n')
        for row in [row for row in rows if row["name"].split('.')[0] == family]:
            name = swift_name(row["name"])
            params = 'context: RequestContext, body: JSONValue = .object([:])'
            if row['secret_input']:
                params += ', secrets: [String: SecretField] = [:]'
            output = 'SecretBytes' if row['secret_output'] else 'JSONValue'
            method = ('performSecretRequestResponse' if row['secret_input'] else 'performSecretResponse') if row['secret_output'] else ('performSecret' if row['secret_input'] else 'perform')
            args = f'.{name}, context: context, body: body' + (', secrets: secrets' if row['secret_input'] else '')
            proxies.append(f'    func {name}({params}) async throws -> {output} {{\n        try await {method}({args})\n    }}\n')
        proxies.append('}\n')
    manifest = dict(sourceCommit=commit, headerSHA256=hashlib.sha256(header).hexdigest(),
                    methodPolicySHA256=hashlib.sha256(policy_bytes).hexdigest(), operationCount=len(rows))
    methods_json = json.dumps([row['name'] for row in rows], separators=(',', ':'))
    fixture = LICENSE + '#ifndef RF_GENERATED_METHODS_H\n#define RF_GENERATED_METHODS_H\n#define RF_FIXTURE_METHODS_JSON ' + json.dumps(methods_json) + '\n#define RF_FIXTURE_POLICY_JSON ' + json.dumps(json.dumps(json.loads(policy_bytes), separators=(',', ':'))) + '\n#endif\n'
    outputs = {
        'Sources/CRamflux/include/ramflux_sdk.h': b'// SPDX-License-Identifier: BSD-3-Clause\n// Copyright (c) 2026 Span Brain\n' + header,
        'Sources/RamfluxCore/SDKOperation.swift': ''.join(lines).encode(),
        'Sources/RamfluxCore/OperationProxies.swift': ''.join(proxies).encode(),
        'Tests/CABIFixture/include/generated_methods.h': fixture.encode(),
        'docs/sdk-method-policy.json': policy_bytes,
        'docs/sdk-contract.json': (json.dumps(manifest, indent=2) + '\n').encode(),
    }
    for path, data in outputs.items():
        file = ROOT / path
        if check:
            if not file.exists() or file.read_bytes() != data:
                raise ValueError('stale generated file: ' + path)
        else:
            file.parent.mkdir(parents=True, exist_ok=True); file.write_bytes(data)
    print(f'SDK_CONTRACT_OK: {len(rows)} policy-classified operations at {commit}')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sdk', type=pathlib.Path)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--update-pin', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check and args.update_pin:
        parser.error('--check and --update-pin are mutually exclusive')
    generate(args.sdk.resolve(), args.commit, args.update_pin, args.check)

if __name__ == '__main__':
    main()
