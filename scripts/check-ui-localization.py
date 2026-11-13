#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Reject visible literal copy and incomplete locale catalogs in every application package."""
from collections import Counter
import json
from pathlib import Path
import re
import sys
ROOT = Path(__file__).resolve().parent.parent
failures = []
# Presentation strings must be resource lookups. Literal image names, accessibility IDs,
# SDK keys, peer text and test/preview fixture data have distinct non-copy roles.
visible = re.compile(r'(?:\b(?:Text|Button|Label|ProgressView|Picker|TextField|SecureField|LabeledContent)\s*\(|\.(?:navigationTitle|accessibilityLabel|accessibilityHint|confirmationDialog|alert)\s*\(|\bsetTitle\s*\(|\bplaceholder\s*=\s*)\s*"([^"\n]+)"')
for directory in [ROOT / 'App', *sorted((ROOT / 'Packages').glob('*/Sources'))]:
    for path in directory.rglob('*.swift'):
        if path.name.endswith('Previews.swift'):
            continue
        source = path.read_text()
        for match in visible.finditer(source):
            failures.append(f'{path.relative_to(ROOT)}: literal UI copy {match.group(1)!r}')
        # Display parameters of native controls/generated presentation cannot bake in labels.
        for match in re.finditer(r'\b(?:title|subtitle|description|message|label)\s*:\s*"([^"\n]+)"', source):
            if match.group(1):
                failures.append(f'{path.relative_to(ROOT)}: literal presentation parameter {match.group(1)!r}')
for path in sorted(ROOT.glob('**/Localizable.xcstrings')):
    if any(part in {'.build', '.git', 'build'} for part in path.parts):
        continue
    document = json.loads(path.read_text())
    for key, item in document['strings'].items():
        values = item.get('localizations', {})
        if set(values) != {'en', 'zh-CN'}:
            failures.append(f'{path.relative_to(ROOT)}:{key}: en/zh-CN keys differ')
        placeholders = []
        for locale in ['en', 'zh-CN']:
            value = values.get(locale, {}).get('stringUnit', {}).get('value', '')
            placeholders.append(Counter(re.findall(r'%(?:[0-9]+\$)?[@dfiu]', value)))
        if placeholders[0] != placeholders[1]:
            failures.append(f'{path.relative_to(ROOT)}:{key}: format placeholders differ')
        for locale in ['en', 'zh-CN']:
            if not values.get(locale, {}).get('stringUnit', {}).get('value'):
                failures.append(f'{path.relative_to(ROOT)}:{key}: empty {locale}')
for name in ['FeatureAppShell', 'FeatureOnboarding', 'FeatureConversations', 'FeatureChat', 'FeatureContacts', 'FeatureSettings', 'FeatureGroups', 'AppData', 'RFDesign']:
    if not (ROOT / 'Packages' / name / 'Tests' / (name + 'Tests') / 'LocalizationTests.swift').is_file():
        failures.append(f'{name}: missing locale-resolution test')
if failures:
    print('\n'.join(failures), file=sys.stderr)
    raise SystemExit(1)
print('UI_LOCALIZATION_OK: complete en/zh-CN catalogs; no literal presentation copy; package locale tests present')
