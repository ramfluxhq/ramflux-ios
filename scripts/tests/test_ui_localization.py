# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

class LocalizationGuardTests(unittest.TestCase):
    def test_rejects_literal_copy_and_incomplete_locale_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            source = Path(__file__).resolve().parents[1] / 'check-ui-localization.py'
            shutil.copyfile(source, root / 'scripts/check-ui-localization.py')
            screen = root / 'App'
            screen.mkdir()
            (screen / 'Screen.swift').write_text('Text("Hard coded visible copy")\n')
            (screen / 'Localizable.xcstrings').write_text(json.dumps({'strings': {'key': {'localizations': {'en': {'stringUnit': {'value': 'Only English'}}}}}}))
            result = subprocess.run(['python3', str(root / 'scripts/check-ui-localization.py')], capture_output=True, text=True, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('literal UI copy', result.stderr)
            self.assertIn('en/zh-CN keys differ', result.stderr)
