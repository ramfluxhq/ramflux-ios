#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Generate names-only Swift adapters from a pinned, SDK-owned method policy."""
import argparse
import hashlib
import json
import pathlib
import re
import struct
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
POLICY_PATH = "crates/ramflux-sdk/include/ramflux_sdk_methods.json"
HEADER_PATH = "crates/ramflux-sdk/include/ramflux_sdk.h"
CARD_HEADER_PATH = "crates/ramflux-card/include/ramflux_card.h"
CARD_ABI_PATH = "crates/ramflux-card/src/package.rs"
CARD_CATALOG_PATH = "crates/ramflux-protocol/catalogs/rf-card-v1.json"
CARD_TRUST_PATH = "crates/ramflux-sdk/include/card/trust.json"
LICENSE = "// SPDX-License-Identifier: AGPL-3.0-or-later\n// Copyright (c) 2026 Span Brain\n"
# A discovery namespace: one or more lowercase segments, including contact.verify.cas.
CAPABILITY = r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*"
CORE_FIELDS = ("name", "capability", "secret_input", "secret_output", "show_once", "key_export", "bridge_allowed")
CAS_FIELDS = {
    "contract": "CONTACT_VERIFY_CAS_CONTRACT",
    "request_type": "CONTACT_VERIFY_CAS_REQUEST_TYPE",
    "response_type": "CONTACT_VERIFY_CAS_RESPONSE_TYPE",
    "message_descriptor_blake3": "CONTACT_VERIFY_CAS_DESCRIPTOR",
    "product_pin": "CONTACT_VERIFY_CAS_PRODUCT_PIN",
}

def cas_constants(source):
    found = {}
    for name in ("CONTACT_VERIFY_CAS_CAPABILITY", *CAS_FIELDS.values()):
        match = re.search(rf'{name}: &str\s*=\s*"([^"]+)"', source)
        if match:
            found[name] = match.group(1)
    return found

def project_policy(row, constants):
    extra = set(row) - set(CORE_FIELDS)
    if row.get("name") == "contact.verify" and constants:
        if extra != set(CAS_FIELDS) or row.get("capability") != constants.get("CONTACT_VERIFY_CAS_CAPABILITY"):
            raise ValueError("contact verify metadata differs from the SDK source")
        if any(row.get(field) != constants.get(constant) for field, constant in CAS_FIELDS.items()):
            raise ValueError("contact verify metadata differs from the SDK source")
    elif extra:
        raise ValueError("unexpected method policy fields")
    return {field: row[field] for field in CORE_FIELDS}

_BLAKE3_IV = (0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19)
_BLAKE3_PERMUTATION = (2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8)
_BLAKE3_CHUNK_START, _BLAKE3_CHUNK_END, _BLAKE3_PARENT, _BLAKE3_ROOT = 1, 2, 4, 8
_BLAKE3_CHUNK_LEN, _BLAKE3_BLOCK_LEN = 1024, 64

def _rotr(value, count):
    return ((value >> count) | (value << (32 - count))) & 0xFFFFFFFF

def _g(state, a, b, c, d, mx, my):
    state[a] = (state[a] + state[b] + mx) & 0xFFFFFFFF
    state[d] = _rotr(state[d] ^ state[a], 16)
    state[c] = (state[c] + state[d]) & 0xFFFFFFFF
    state[b] = _rotr(state[b] ^ state[c], 12)
    state[a] = (state[a] + state[b] + my) & 0xFFFFFFFF
    state[d] = _rotr(state[d] ^ state[a], 8)
    state[c] = (state[c] + state[d]) & 0xFFFFFFFF
    state[b] = _rotr(state[b] ^ state[c], 7)

def _compress(chaining, words, counter, block_len, flags):
    state = list(chaining) + list(_BLAKE3_IV[:4]) + [counter & 0xFFFFFFFF, (counter >> 32) & 0xFFFFFFFF, block_len, flags]
    message = list(words)
    for _ in range(7):
        _g(state, 0, 4, 8, 12, message[0], message[1]); _g(state, 1, 5, 9, 13, message[2], message[3])
        _g(state, 2, 6, 10, 14, message[4], message[5]); _g(state, 3, 7, 11, 15, message[6], message[7])
        _g(state, 0, 5, 10, 15, message[8], message[9]); _g(state, 1, 6, 11, 12, message[10], message[11])
        _g(state, 2, 7, 8, 13, message[12], message[13]); _g(state, 3, 4, 9, 14, message[14], message[15])
        message = [message[i] for i in _BLAKE3_PERMUTATION]
    for i in range(8):
        state[i] ^= state[i + 8]
        state[i + 8] ^= chaining[i]
    return state

def _chunk(data, index, root):
    blocks = [data[i:i + _BLAKE3_BLOCK_LEN] for i in range(0, len(data), _BLAKE3_BLOCK_LEN)] or [b""]
    chaining = list(_BLAKE3_IV)
    for position, block in enumerate(blocks):
        flags = (_BLAKE3_CHUNK_START if position == 0 else 0) | (_BLAKE3_CHUNK_END if position == len(blocks) - 1 else 0)
        if root and position == len(blocks) - 1:
            flags |= _BLAKE3_ROOT
        words = struct.unpack("<16I", block.ljust(_BLAKE3_BLOCK_LEN, b"\0"))
        out = _compress(chaining, words, index, len(block), flags)
        if root and position == len(blocks) - 1:
            return struct.pack("<8I", *out[:8])
        chaining = out[:8]
    return chaining

def _node(chunks, low, high, root):
    if high - low == 1:
        return _chunk(chunks[low], low, root)
    split = 1
    while split * 2 < high - low:
        split *= 2
    left = _node(chunks, low, low + split, False)
    right = _node(chunks, low + split, high, False)
    words = list(left) + list(right)
    if root:
        return struct.pack("<8I", *_compress(_BLAKE3_IV, words, 0, _BLAKE3_BLOCK_LEN, _BLAKE3_PARENT | _BLAKE3_ROOT)[:8])
    return list(_compress(_BLAKE3_IV, words, 0, _BLAKE3_BLOCK_LEN, _BLAKE3_PARENT)[:8])

def _blake3_digest(data):
    chunks = [data[i:i + _BLAKE3_CHUNK_LEN] for i in range(0, len(data), _BLAKE3_CHUNK_LEN)] or [b""]
    result = _node(chunks, 0, len(chunks), True)
    if isinstance(result, list):
        result = struct.pack("<8I", *result)
    return result

def blake3_hex(data):
    # BLAKE3 (unkeyed, 32-byte output) in the standard library, so the contract check needs no extra package.
    # Verified against the reference implementation for chunk and tree boundaries (0 to 100000 bytes).
    return _blake3_digest(data).hex()

def card_runtime(source):
    # The renderer's negotiated identity, read from the pinned commit (never from the working tree).
    abi = re.search(rb"pub const HOST_ABI: u32 = (\d+);", source(CARD_ABI_PATH))
    if not abi:
        raise ValueError("card host ABI not found in the SDK source")
    return dict(abiMajor=int(abi.group(1)), catalogSHA256=hashlib.sha256(source(CARD_CATALOG_PATH)).hexdigest(),
                trustManifestBLAKE3=blake3_hex(source(CARD_TRUST_PATH)))

def git(sdk, *args):
    return subprocess.check_output(["git", "-C", str(sdk), *args])

def swift_name(name):
    parts = name.replace("_", ".").split(".")
    return parts[0] + "".join(part.title() for part in parts[1:])

def validate_policy(policy):
    if policy.get("abi_major") != 2 or policy.get("policy_version") != 2:
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
        if not re.fullmatch(CAPABILITY, row.get("capability", "")):
            raise ValueError("invalid capability")
        if any(type(row.get(flag)) is not bool for flag in ["secret_input", "secret_output", "show_once", "key_export", "bridge_allowed"]):
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
    card_header = source(CARD_HEADER_PATH)
    renderer = card_runtime(source)
    policy_bytes = source(POLICY_PATH)
    policy = json.loads(policy_bytes)
    rows = validate_policy(policy)
    # Compare the committed JSON to its SDK Rust policy source, not a native secret list.
    policy_source = source("crates/ramflux-sdk/src/c_abi/v2/method_policy.rs").decode()
    rust_rows = re.findall(r'"([a-z][a-z0-9_.]*)"\s*=>\s*\(\s*"(' + CAPABILITY + r')"\s*,\s*(true|false)\s*,\s*(true|false)\s*,\s*(true|false)\s*,\s*(true|false)\s*\)', policy_source)
    denied = set()
    if "DENIED_METHODS" in policy_source:
        denied = set(re.findall(r'"([a-z][a-z0-9_.]*)"', policy_source.split("DENIED_METHODS", 1)[1].split(";", 1)[0]))
    expected = sorted([dict(name=n, capability=c, secret_input=i == "true", secret_output=o == "true", show_once=s == "true",
                            key_export=k == "true", bridge_allowed=n not in denied and "itest" not in n)
                       for n, c, i, o, s, k in rust_rows], key=lambda row: row["name"])
    projected = [project_policy(row, cas_constants(policy_source)) for row in rows]
    if projected != expected or len(rows) != len(rust_rows):
        raise ValueError("SDK policy count/content differs from the source registry")
    callable_rows = [row for row in rows if row["bridge_allowed"]]
    if not callable_rows or any(row["name"] in {item["name"] for item in rows if not item["bridge_allowed"]} for row in callable_rows):
        raise ValueError("invalid bridge inventory")
    if not update_pin and recorded["operationCount"] != len(callable_rows):
        raise ValueError("operation count differs from recorded contract")
    method_table = source("crates/ramflux-sdk/src/bus/method_table.rs").decode().split("methods! {", 1)[1].split("#[cfg(test)]", 1)[0]
    reads = set()
    for names in re.findall(r"LocalRead\(\w+\)\s*=>\s*\w+:\s*\[(.*?)\];", method_table, re.S):
        reads.update(re.findall(r'"([a-z0-9_.]+)"', names))
    # The SDK-owned connection-local challenge names are reads; flagging other extra
    # operations as keyed is conservative and never fabricates a mutation identity.
    reads.update(row["name"] for row in rows if row["name"].endswith(".hidden_challenge"))
    reads.update(row["name"] for row in rows if row["name"].startswith(("account.create.", "account.custody.", "account.recover.")))
    # The agent configuration plane refuses any operation id (bus/agent_methods.rs `apply`: a request
    # with `operation_id` is CustodySetupInvalid), so agent methods are sent without one.
    reads.update(row["name"] for row in rows if row["name"].startswith("agent."))
    lines = [LICENSE, "// Generated from the pinned SDK method policy. Do not edit.\n",
             "public enum SDKOperation: String, CaseIterable, Sendable {\n"]
    for row in callable_rows:
        lines.append(f'    case {swift_name(row["name"])} = "{row["name"]}"\n')
    for property_name, flag in [("requiresSecureInput", "secret_input"), ("requiresSecureOutput", "secret_output"), ("showOnce", "show_once"), ("requiresKeyExport", "key_export")]:
        cases = ["." + swift_name(row["name"]) for row in callable_rows if row[flag]]
        if cases:
            lines.append(f'    public var {property_name}: Bool {{\n        switch self {{\n        case ' + ", ".join(cases) + ': true\n        default: false\n        }\n    }\n')
        else:
            lines.append(f'    public var {property_name}: Bool {{ false }}\n')
    read_cases = ["." + swift_name(row["name"]) for row in callable_rows if row["name"] in reads]
    if read_cases:
        lines.append('    public var requiresOperationID: Bool {\n        switch self {\n        case ' + ", ".join(read_cases) + ': false\n        default: true\n        }\n    }\n')
    else:
        lines.append('    public var requiresOperationID: Bool { true }\n')
    lines.append('    public var capability: String {\n        switch self {\n')
    for row in callable_rows:
        lines.append(f'        case .{swift_name(row["name"])}: "{row["capability"]}"\n')
    lines.append('        }\n    }\n}\n')
    proxies = [LICENSE, "// Generated forwarding APIs; SDK payload schemas remain authoritative.\n"]
    for family in sorted({row["name"].split('.')[0] for row in callable_rows}):
        title = family.upper() if family in ("a2i", "a2ui", "mcp") else family.title()
        proxies.append(f'public protocol {title}Proxy: SDKProxyProtocol {{}}\npublic extension {title}Proxy {{\n')
        for row in [row for row in callable_rows if row["name"].split('.')[0] == family]:
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
                    cardHeaderSHA256=hashlib.sha256(card_header).hexdigest(), cardRuntime=renderer,
                    methodPolicySHA256=hashlib.sha256(policy_bytes).hexdigest(), operationCount=len(callable_rows))
    methods_json = json.dumps([row['name'] for row in callable_rows], separators=(',', ':'))
    fixture = LICENSE + '#ifndef RF_GENERATED_METHODS_H\n#define RF_GENERATED_METHODS_H\n#define RF_FIXTURE_METHODS_JSON ' + json.dumps(methods_json) + '\n#define RF_FIXTURE_POLICY_JSON ' + json.dumps(json.dumps(json.loads(policy_bytes), separators=(',', ':'))) + '\n#endif\n'
    outputs = {
        'Sources/CRamflux/include/ramflux_sdk.h': b'// SPDX-License-Identifier: BSD-3-Clause\n// Copyright (c) 2026 Span Brain\n' + header,
        'Sources/CRamflux/include/ramflux_card.h': card_header,
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
