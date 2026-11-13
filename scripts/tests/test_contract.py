# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
import importlib.util
import pathlib
import unittest
import tempfile
import json
from unittest import mock

source = pathlib.Path(__file__).resolve().parents[1] / "sync-sdk-contract.py"
spec = importlib.util.spec_from_file_location("contract", source)
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)

def policy(*names):
    return dict(abi_major=2, policy_version=1, methods=[dict(name=n, capability="account", secret_input=True,
                                                        secret_output=True, show_once=False) for n in names])

class PolicyTests(unittest.TestCase):
    def test_collision_is_refused(self):
        with self.assertRaisesRegex(ValueError, "collision"):
            contract.validate_policy(policy("account.alpha_beta", "account.alpha.beta"))

    def test_duplicate_is_refused(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            contract.validate_policy(policy("account.alpha", "account.alpha"))

    def test_missing_secret_flags_fail_closed(self):
        value = policy("account.new_method")
        del value["methods"][0]["secret_input"]
        with self.assertRaisesRegex(ValueError, "secret-handling"):
            contract.validate_policy(value)

    def test_new_method_uses_sdk_flags(self):
        rows = contract.validate_policy(policy("account.new_method"))
        self.assertTrue(rows[0]["secret_input"])
        self.assertTrue(rows[0]["secret_output"])

    def test_show_once_requires_sealed_output(self):
        value = policy("account.once")
        value["methods"][0].update(show_once=True, secret_output=False)
        with self.assertRaisesRegex(ValueError, "show_once"):
            contract.validate_policy(value)

    def test_wrong_head_is_refused_before_writes(self):
        with mock.patch.object(contract, "git", return_value=b"2" * 40):
            with self.assertRaisesRegex(ValueError, "HEAD"):
                contract.generate(pathlib.Path("unused"), "1" * 40)

    def test_dirty_source_is_refused_before_writes(self):
        with mock.patch.object(contract, "git", side_effect=[b"1" * 40, b" M source.rs"]):
            with self.assertRaisesRegex(ValueError, "clean"):
                contract.generate(pathlib.Path("unused"), "1" * 40)

    def test_recorded_pin_cannot_drift_silently(self):
        with mock.patch.object(contract, "git", side_effect=[b"1" * 40, b""]):
            with self.assertRaisesRegex(ValueError, "sourceCommit"):
                contract.generate(pathlib.Path("unused"), "1" * 40)

    def test_count_mismatch_is_refused_and_new_secret_method_is_emitted_safely(self):
        pin = "1" * 40
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "docs").mkdir()
            recorded = root / "docs/sdk-contract.json"
            recorded.write_text(json.dumps(dict(sourceCommit=pin, operationCount=2)))
            sources = {
                contract.HEADER_PATH: b"/* generated fixture header */",
                contract.POLICY_PATH: json.dumps(policy("account.new_method")).encode(),
                "crates/ramflux-sdk/src/c_abi/v2/method_policy.rs": b'policies! { "account.new_method" => ("account", true, true, false), }',
                "crates/ramflux-sdk/src/bus/method_table.rs": b'methods! { LocalRead(Always) => Reader: ["account.new_method"]; }',
            }
            def source_git(sdk, *args):
                if args == ("rev-parse", "HEAD"): return pin.encode()
                if args == ("status", "--porcelain"): return b""
                return sources[args[1].split(":", 1)[1]]
            with mock.patch.object(contract, "ROOT", root), mock.patch.object(contract, "git", side_effect=source_git):
                with self.assertRaisesRegex(ValueError, "count"):
                    contract.generate(root, pin)
                self.assertFalse((root / "Sources").exists())
                contract.generate(root, pin, update_pin=True)
                proxy = (root / "Sources/RamfluxCore/OperationProxies.swift").read_text()
                self.assertIn("performSecretRequestResponse(.accountNewMethod", proxy)
                self.assertIn("async throws -> SecretBytes", proxy)
                contract.generate(root, pin, check=True)

if __name__ == "__main__":
    unittest.main()
