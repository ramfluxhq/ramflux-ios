#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Compile the sole String Catalog source into portable SwiftPM resources.

SwiftPM's native backend in Xcode 26 copies xcstrings without compiling them.
Checked exports keep both native CLI and Xcode builds on the same catalog content,
including compiler-supported plural/variable rules. Never edit an export directly.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()

def semantic(path):
    output = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)], check=True, capture_output=True, timeout=10)
    return json.loads(output.stdout)

count = 0
for catalog in sorted((ROOT / 'Packages').glob('**/Localizable.xcstrings')):
    if any(part in {'.build', 'build'} for part in catalog.parts):
        continue
    destination = catalog.parent / 'CompiledLocalizations'
    with tempfile.TemporaryDirectory(prefix='ramflux-localizations-') as directory:
        staging = Path(directory)
        subprocess.run(['xcrun', 'xcstringstool', 'compile', str(catalog), '--output-directory', str(staging), '--serialization-format', 'text'], check=True, capture_output=True, timeout=30)
        outputs = {p.relative_to(staging): p for p in staging.rglob('*') if p.is_file()}
        if not outputs or any(p.suffix not in {'.strings', '.stringsdict'} for p in outputs):
            raise SystemExit('Unexpected compiler export inventory: ' + str(catalog))
        existing = {p.relative_to(destination): p for p in destination.rglob('*') if p.is_file()} if destination.exists() else {}
        if args.check:
            if set(existing) != set(outputs) or any(semantic(existing[key]) != semantic(value) for key, value in outputs.items()):
                raise SystemExit('LOCALIZATION_EXPORT_DRIFT: ' + str(catalog.relative_to(ROOT)))
        else:
            for relative, source in outputs.items():
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read_bytes())
            for relative in set(existing) - set(outputs):
                existing[relative].unlink()
        count += 1
print(f'LOCALIZATION_EXPORTS_OK: {count} package catalogs; portable compiler exports match')
