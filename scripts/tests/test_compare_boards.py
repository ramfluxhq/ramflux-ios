# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from rfpng import write_png  # noqa: E402

WIDTH, HEIGHT = 60, 40
LIGHT = (0xFC, 0xFB, 0xF9)


def image(blocks, channels=3, transparent_corner=False):
    rows = []
    for y in range(HEIGHT):
        row = bytearray()
        for x in range(WIDTH):
            color = LIGHT
            for bx, by, bw, bh, value in blocks:
                if bx <= x < bx + bw and by <= y < by + bh:
                    color = value
            if channels == 4:
                alpha = 0 if transparent_corner and x < 3 and y < 3 else 255
                row.extend((*color, alpha))
            else:
                row.extend(color)
        rows.append(row)
    return rows


class CompareBoardsTests(unittest.TestCase):
    def run_compare(self, reference_blocks, capture_blocks, expected=None, capture=True, corner_ink=False):
        directory = Path(tempfile.mkdtemp())
        references = directory / "refs"
        captures = directory / "caps"
        references.mkdir()
        captures.mkdir()
        write_png(references / "MOB-T01-en-light.png", WIDTH, HEIGHT, image(reference_blocks, channels=4, transparent_corner=True), channels=4)
        manifest = {"boards": [{"key": "MOB-T01", "title": "test", "node": "n", "board": "MOB-T01", "locale": "en", "theme": "light", "reference": "MOB-T01-en-light.png"}]}
        (references / "manifest.json").write_text(json.dumps(manifest))
        if capture:
            blocks = list(capture_blocks)
            if corner_ink:
                blocks.append((0, 0, 3, 3, (0, 0, 0)))
            write_png(captures / "MOB-T01-en-393-default-light.png", WIDTH, HEIGHT, image(blocks))
        expected_path = directory / "expected.json"
        expected_path.write_text(json.dumps({"boards": expected or {}}))
        result = subprocess.run(
            [sys.executable, str(SCRIPTS / "compare-boards.py"), str(captures), str(directory / "out"), "--manifest", str(references / "manifest.json"), "--expected", str(expected_path)],
            capture_output=True, text=True, timeout=60,
        )
        checklist = (directory / "out" / "checklist.tsv").read_text()
        return result, checklist, directory / "out"

    def test_identical_capture_passes(self):
        result, checklist, out = self.run_compare([(10, 10, 20, 8, (30, 30, 30))], [(10, 10, 20, 8, (30, 30, 30))])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("\tpass\t0.00\t0\t", checklist)
        self.assertTrue((out / "pairs" / "MOB-T01-en-light--pair.png").is_file())
        self.assertTrue((out / "diffs" / "MOB-T01-en-light--diff.png").is_file())

    def test_one_pixel_edge_shift_is_antialiasing(self):
        result, checklist, _ = self.run_compare([(10, 10, 20, 8, (30, 30, 30))], [(11, 10, 20, 8, (30, 30, 30))])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("\tpass\t", checklist)

    def test_transparent_reference_corner_is_not_compared(self):
        result, checklist, _ = self.run_compare([], [], corner_ink=True)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_moved_element_fails_and_is_measured(self):
        result, checklist, _ = self.run_compare([(10, 10, 8, 8, (30, 30, 30))], [(14, 13, 8, 8, (30, 30, 30))])
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("NEW deviation", checklist)
        self.assertIn("ink dx=+4 dy=+3 dw=+0 dh=+0", checklist)

    def test_colour_change_beyond_tolerance_fails(self):
        result, checklist, _ = self.run_compare([(10, 10, 8, 8, (30, 30, 30))], [(10, 10, 8, 8, (200, 30, 30))])
        self.assertEqual(result.returncode, 1, result.stdout)

    def test_reviewed_expected_region_is_known_and_new_region_still_fails(self):
        expected = {"MOB-T01-en-light": {"status": "deviates", "reason": "reviewed", "regions": [{"rect": [8, 8, 16, 16]}]}}
        result, checklist, _ = self.run_compare([(10, 10, 8, 8, (30, 30, 30))], [(14, 13, 8, 8, (30, 30, 30))], expected)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("known deviation", checklist)
        result, checklist, _ = self.run_compare([(10, 10, 8, 8, (30, 30, 30))], [(14, 13, 8, 8, (30, 30, 30)), (40, 25, 10, 10, (0, 0, 0))], expected)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("NEW deviation", checklist)

    def test_unreviewed_expected_entry_fails(self):
        expected = {"MOB-T01-en-light": {"status": "deviates", "reason": "UNREVIEWED", "regions": [{"rect": [0, 0, 60, 40]}]}}
        result, _, _ = self.run_compare([], [], expected)
        self.assertEqual(result.returncode, 1, result.stdout)

    def test_missing_capture_fails_unless_expected(self):
        result, checklist, _ = self.run_compare([], [], capture=False)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("NEW: no capture", checklist)
        expected = {"MOB-T01-en-light": {"status": "no-capture", "reason": "no screen yet"}}
        result, checklist, _ = self.run_compare([], [], expected, capture=False)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("known: no capture", checklist)

    def test_resolved_expected_region_is_reported(self):
        expected = {"MOB-T01-en-light": {"status": "deviates", "reason": "reviewed", "regions": [{"rect": [8, 8, 16, 16]}]}}
        result, checklist, _ = self.run_compare([], [], expected)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("1 expected rect(s) resolved", checklist)


if __name__ == "__main__":
    unittest.main()
