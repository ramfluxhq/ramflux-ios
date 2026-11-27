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

def renderer_sources():
    # The card runtime identity the contract records, read from the pinned SDK source.
    return {
        contract.CARD_HEADER_PATH: b"/* card header fixture */",
        contract.CARD_ABI_PATH: b"pub const HOST_ABI: u32 = 5;",
        contract.CARD_CATALOG_PATH: b"{}",
        contract.CARD_TRUST_PATH: b"{}",
    }

def policy(*names):
    return dict(abi_major=2, policy_version=2, methods=[dict(name=n, capability="account", secret_input=True,
                                                        secret_output=True, show_once=False, key_export=False,
                                                        bridge_allowed=True) for n in names])

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

    def test_dotted_capability_namespace_is_accepted(self):
        rows = contract.validate_policy(policy("contact.verify"))
        rows[0]["capability"] = "contact.verify.cas"
        self.assertEqual(contract.validate_policy({"abi_major": 2, "policy_version": 2, "methods": rows})[0]["capability"], "contact.verify.cas")

    def test_broken_capability_namespace_is_refused(self):
        for capability in ["", ".cas", "contact.", "contact..cas", "Contact", "contact.verify.", "1cas"]:
            value = policy("contact.verify")
            value["methods"][0]["capability"] = capability
            with self.assertRaisesRegex(ValueError, "invalid capability"):
                contract.validate_policy(value)

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
                **renderer_sources(),
                contract.HEADER_PATH: b"/* generated fixture header */",
                contract.POLICY_PATH: json.dumps(policy("account.new_method")).encode(),
                "crates/ramflux-sdk/src/c_abi/v2/method_policy.rs": b'policies! { "account.new_method" => ("account", true, true, false, false), }',
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

def cas_sources(row):
    rust = "\n".join([
        'policies! { "contact.verify" => ("contact.verify.cas", true, true, false, false), }',
        'pub(super) const CONTACT_VERIFY_CAS_CAPABILITY: &str = "contact.verify.cas";',
        'pub(super) const CONTACT_VERIFY_CAS_CONTRACT: &str = "CONTACT-VERIFY-CAS-01";',
        'pub(super) const CONTACT_VERIFY_CAS_REQUEST_TYPE: &str = "ramflux.message.v1.ContactSafetyVerifyRequest";',
        'pub(super) const CONTACT_VERIFY_CAS_RESPONSE_TYPE: &str = "ramflux.message.v1.ContactSafetyVerifyResult";',
        'pub(super) const CONTACT_VERIFY_CAS_DESCRIPTOR: &str = "%s";' % ("ab" * 32),
        'pub(super) const CONTACT_VERIFY_CAS_PRODUCT_PIN: &str = "%s";' % ("cd" * 20),
    ])
    return {
        **renderer_sources(),
        contract.HEADER_PATH: b"/* generated fixture header */",
        contract.POLICY_PATH: json.dumps({"abi_major": 2, "policy_version": 2, "methods": [row]}).encode(),
        "crates/ramflux-sdk/src/c_abi/v2/method_policy.rs": rust.encode(),
        "crates/ramflux-sdk/src/bus/method_table.rs": b'methods! { LocalRead(Always) => Reader: ["contact.verify"]; }',
    }

class CasMetadataTests(unittest.TestCase):
    def generate(self, row, pin="1" * 40):
        root = pathlib.Path(self.directory)
        (root / "docs").mkdir()
        (root / "docs/sdk-contract.json").write_text(json.dumps(dict(sourceCommit=pin, operationCount=0)))
        sources = cas_sources(row)
        def source_git(sdk, *args):
            if args == ("rev-parse", "HEAD"): return pin.encode()
            if args == ("status", "--porcelain"): return b""
            return sources[args[1].split(":", 1)[1]]
        with mock.patch.object(contract, "ROOT", root), mock.patch.object(contract, "git", side_effect=source_git):
            contract.generate(root, pin, update_pin=True)
        return (root / "Sources/RamfluxCore/SDKOperation.swift").read_text()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = self.temporary.name

    def tearDown(self):
        self.temporary.cleanup()

    def row(self):
        value = policy("contact.verify")["methods"][0]
        value["capability"] = "contact.verify.cas"
        value.update(contract="CONTACT-VERIFY-CAS-01",
                     request_type="ramflux.message.v1.ContactSafetyVerifyRequest",
                     response_type="ramflux.message.v1.ContactSafetyVerifyResult",
                     message_descriptor_blake3="ab" * 32, product_pin="cd" * 20)
        return value

    def test_cas_metadata_is_admitted_and_capability_is_not_rewritten(self):
        generated = self.generate(self.row())
        self.assertIn('case contactVerify = "contact.verify"', generated)
        self.assertIn('case .contactVerify: "contact.verify.cas"', generated)

    def test_cas_metadata_mismatch_is_refused(self):
        value = self.row()
        value["product_pin"] = "ee" * 20
        with self.assertRaisesRegex(ValueError, "contact verify metadata"):
            self.generate(value)

    def test_unexpected_policy_field_is_refused(self):
        value = policy("account.new_method")["methods"][0]
        value["product_pin"] = "ee" * 20
        with self.assertRaisesRegex(ValueError, "unexpected method policy"):
            self.generate(value)

if __name__ == "__main__":
    unittest.main()
