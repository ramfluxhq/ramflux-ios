# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "select-simulator.py"
SPEC = importlib.util.spec_from_file_location("select_simulator", SCRIPT)
selector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(selector)

DEVICES = {
    "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
        {"name": "iPhone 16 Pro", "udid": "OLD", "isAvailable": True},
        {"name": "iPhone 17 Pro", "udid": "OLD-17", "isAvailable": True},
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
        {"name": "iPhone 17", "udid": "OTHER", "isAvailable": True},
        {"name": "iPhone 17 Pro", "udid": "BROKEN", "isAvailable": False},
        {"name": "iPhone 17 Pro", "udid": "PINNED", "isAvailable": True},
    ],
    "com.apple.CoreSimulator.SimRuntime.watchOS-26-5": [
        {"name": "Apple Watch Ultra 3 (49mm)", "udid": "WATCH", "isAvailable": True},
    ],
}


class SelectSimulatorTests(unittest.TestCase):
    def test_selects_the_named_device_on_the_pinned_runtime(self):
        self.assertEqual(selector.select(DEVICES, "iPhone 17 Pro", "26.5"), "PINNED")

    def test_never_falls_back_to_another_runtime_or_device(self):
        self.assertIsNone(selector.select(DEVICES, "iPhone 17 Pro", "26.4"))
        self.assertIsNone(selector.select(DEVICES, "iPhone 16 Pro", "26.5"))

    def test_lists_installed_iphones_per_ios_runtime(self):
        self.assertEqual(
            selector.installed(DEVICES),
            ["  iOS 18.5: iPhone 16 Pro, iPhone 17 Pro", "  iOS 26.5: iPhone 17, iPhone 17 Pro"],
        )


if __name__ == "__main__":
    unittest.main()
