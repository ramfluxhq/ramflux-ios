#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Reject visible literal copy and incomplete or unsafe String Catalogs in every package.

The check is language-agnostic. The shipped locales are the locales present in
the catalogs: adding a language is adding its translations, never a change here.
- The fallback language is CatalogLookup.developmentLanguage (RFLocalization);
  every key must have a non-empty value in it, because the runtime falls back to it.
- Every key must have every shipped locale, with identical format placeholders.
- Plural variations must have exactly the CLDR cardinal categories of their
  language (scripts/cldr-plural-categories.json); `zero` is also accepted as an
  explicit Apple case. A locale without CLDR data fails until the data is added.
- New keys must not be hashed (`copy.<12 hex>`) and must carry a translator
  comment. Existing exceptions are listed in scripts/localization-baseline.json.
- Localised text must not be assembled in code (`+` next to a lookup, or a
  literal " · " separator). Existing exceptions are listed in the baseline.
- Every package with a catalog has a locale-resolution test.
- The app's Info.plist declarations in project.yml follow the catalogs:
  CFBundleLocalizations lists exactly the shipped locales and
  CFBundleDevelopmentRegion is the fallback language.
"""
from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = Path(__file__).resolve().parent
LOOKUP = ROOT / 'Packages/RFLocalization/Sources/RFLocalization/CatalogLookup.swift'
CLDR = json.loads((SCRIPTS / 'cldr-plural-categories.json').read_text())['cardinal']
BASELINE_PATH = SCRIPTS / 'localization-baseline.json'
BASELINE = json.loads(BASELINE_PATH.read_text()) if BASELINE_PATH.is_file() else {}
HASHED = re.compile(r'^copy\.[0-9a-f]{12}$')
# The pseudo-locale expansion is review tooling, not translation assembly.
ASSEMBLY_EXEMPT = {'Packages/RFLocalization/Sources/RFLocalization/CatalogLookup.swift'}
failures = []
notes = []


def relative(path):
    return str(path.relative_to(ROOT))


def fallback_language():
    if LOOKUP.is_file():
        match = re.search(r'developmentLanguage\s*=\s*"([^"]+)"', LOOKUP.read_text())
        if match:
            return match.group(1)
    failures.append(f'{relative(LOOKUP) if LOOKUP.is_relative_to(ROOT) else LOOKUP}: CatalogLookup.developmentLanguage not found')
    return 'en'


def plural_categories(locale):
    tag = locale.lower().replace('_', '-')
    while tag:
        if tag in CLDR:
            return set(CLDR[tag])
        tag = tag.rpartition('-')[0]
    return None


def swift_sources():
    for directory in [ROOT / 'App', ROOT / 'Packages/RFDesign/Generated', *sorted((ROOT / 'Packages').glob('*/Sources'))]:
        for path in sorted(directory.rglob('*.swift')):
            if any(part in {'.build', 'build'} for part in path.parts) or path.name.endswith('Previews.swift'):
                continue
            yield path


# Presentation strings must be resource lookups. Literal image names, accessibility IDs,
# SDK keys, peer text and test/preview fixture data have distinct non-copy roles.
visible = re.compile(r'(?:\b(?:Text|Button|Label|ProgressView|Picker|TextField|SecureField|LabeledContent)\s*\(|\.(?:navigationTitle|accessibilityLabel|accessibilityHint|confirmationDialog|alert)\s*\(|\bsetTitle\s*\(|\bplaceholder\s*=\s*)\s*"([^"\n]+)"')
lookup_call = r'(?:\b\w+Strings\.\w+|\bString\(localized:|\bcopy)\('
balanced = r'\((?:[^()\n]|\((?:[^()\n]|\([^()\n]*\))*\))*\)'
assembly = [
    re.compile(r'(?:\b\w+Strings\.\w+|\bString(?=\(localized:)|\bcopy)' + balanced + r'\s*\+(?!=)'),
    re.compile(r'(?<![+=])\+\s*' + lookup_call),
    re.compile(r'"\s*·\s*"'),
]
baseline_assembly = Counter((item['path'], item['line']) for item in BASELINE.get('assembly', []))
found_assembly = Counter()
for path in swift_sources():
    source = path.read_text()
    name = relative(path)
    for match in visible.finditer(source):
        failures.append(f'{name}: literal UI copy {match.group(1)!r}')
    if 'Generated' in path.parts and re.search(r'String\(localized:', source):
        failures.append(f'{name}: generated accessibility must receive host-localized text')
    # Display parameters of native controls/generated presentation cannot bake in labels.
    for match in re.finditer(r'\b(?:title|subtitle|description|message|label)\s*:\s*"([^"\n]+)"', source):
        if match.group(1):
            failures.append(f'{name}: literal presentation parameter {match.group(1)!r}')
    if name in ASSEMBLY_EXEMPT:
        continue
    for line in source.splitlines():
        if any(pattern.search(line) for pattern in assembly):
            found_assembly[(name, line.strip())] += 1
for (name, line), count in sorted(found_assembly.items()):
    if count > baseline_assembly[(name, line)]:
        failures.append(f'{name}: localized text assembled in code; use one catalog format string: {line[:160]}')
for (name, line), count in sorted(baseline_assembly.items()):
    if found_assembly[(name, line)] < count:
        notes.append(f'baseline assembly entry no longer present, remove it: {name}: {line[:120]}')

fallback = fallback_language()
catalogs = []
for path in sorted(ROOT.glob('**/Localizable.xcstrings')):
    if any(part in {'.build', '.git', 'build'} for part in path.parts):
        continue
    catalogs.append((path, json.loads(path.read_text())))
shipped = set()
for _, document in catalogs:
    for item in document['strings'].values():
        shipped.update(item.get('localizations', {}))
shipped.add(fallback)
baseline_hashed = {key: set(values) for key, values in BASELINE.get('hashed_keys', {}).items()}
baseline_uncommented = {key: set(values) for key, values in BASELINE.get('uncommented_keys', {}).items()}
hashed_count = 0
for path, document in catalogs:
    name = relative(path)
    if document.get('sourceLanguage') != fallback:
        failures.append(f'{name}: sourceLanguage must be the fallback language {fallback!r}')
    for key, item in document['strings'].items():
        values = item.get('localizations', {})
        if HASHED.match(key):
            hashed_count += 1
            if key not in baseline_hashed.get(name, set()):
                failures.append(f'{name}:{key}: new hashed key; use a semantic key feature.screen.element')
        if not item.get('comment', '').strip() and key not in baseline_uncommented.get(name, set()):
            failures.append(f'{name}:{key}: new key without a translator comment')
        if fallback not in values:
            failures.append(f'{name}:{key}: missing in fallback language {fallback}')
        for locale in sorted(shipped - set(values)):
            failures.append(f'{name}:{key}: missing locale {locale}')
        signatures = []
        for locale in sorted(values):
            entry = values[locale]
            plural = entry.get('variations', {}).get('plural')
            units = list(plural.values()) if plural else [entry]
            if plural is not None:
                required = plural_categories(locale)
                if required is None:
                    failures.append(f'{name}:{key}: no CLDR plural data for {locale}; add it to scripts/cldr-plural-categories.json')
                else:
                    for category in sorted(required - set(plural)):
                        failures.append(f'{name}:{key}: missing plural {category} in {locale}')
                    for category in sorted(set(plural) - required - {'zero'}):
                        failures.append(f'{name}:{key}: plural {category} is not a CLDR category of {locale}')
            for unit in units:
                value = unit.get('stringUnit', {}).get('value', '')
                if not value:
                    failures.append(f'{name}:{key}: empty {locale}')
                signatures.append(Counter(re.findall(r'%(?:[0-9]+\$)?(?:ll|l)?[@dfiu]', value)))
        if signatures and any(value != signatures[0] for value in signatures):
            failures.append(f'{name}:{key}: format placeholders differ')
for name, keys in sorted(baseline_hashed.items()):
    present = next((document['strings'] for path, document in catalogs if relative(path) == name), {})
    for key in sorted(keys - set(present)):
        notes.append(f'baseline hashed key no longer present, remove it: {name}:{key}')

project = ROOT / 'project.yml'
if project.is_file():
    text = project.read_text()
    declared = re.search(r'^\s*CFBundleLocalizations:\s*\[([^\]]*)\]', text, re.M)
    region = re.search(r'^\s*CFBundleDevelopmentRegion:\s*(\S+)', text, re.M)
    if declared is None:
        failures.append('project.yml: CFBundleLocalizations must list the shipped catalog locales')
    else:
        listed = [item.strip().strip('\'"') for item in declared.group(1).split(',') if item.strip()]
        if sorted(listed) != sorted(shipped):
            failures.append(f'project.yml: CFBundleLocalizations {sorted(listed)} must equal the catalog locales {sorted(shipped)}')
    if region is None or region.group(1).strip('\'"') != fallback:
        failures.append(f'project.yml: CFBundleDevelopmentRegion must be the fallback language {fallback!r}')

for path, _ in catalogs:
    parts = path.relative_to(ROOT).parts
    if parts[0] != 'Packages':
        continue
    package = parts[1]
    if not (ROOT / 'Packages' / package / 'Tests' / (package + 'Tests') / 'LocalizationTests.swift').is_file():
        failures.append(f'{package}: missing locale-resolution test')

for note in notes:
    print('note: ' + note)
if failures:
    print('\n'.join(failures), file=sys.stderr)
    raise SystemExit(1)
print(f'UI_LOCALIZATION_OK: {len(catalogs)} catalogs complete for {", ".join(sorted(shipped))} (fallback {fallback}); '
      f'CLDR plural categories; {hashed_count} baselined hashed keys, no new ones; '
      f'{sum(baseline_assembly.values())} baselined assembly sites, no new ones; no literal presentation copy; package locale tests present; '
      f'CFBundleLocalizations matches the catalogs')
