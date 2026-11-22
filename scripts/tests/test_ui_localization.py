# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]


def unit(value):
    return {'stringUnit': {'state': 'translated', 'value': value}}


def plural(**forms):
    return {'variations': {'plural': {name: unit(value) for name, value in forms.items()}}}


class LocalizationGuardTests(unittest.TestCase):
    def check(self, strings=None, swift=None, baseline=None, extra=None):
        directory = tempfile.mkdtemp()
        root = Path(directory)
        (root / 'scripts').mkdir()
        shutil.copyfile(SCRIPTS / 'check-ui-localization.py', root / 'scripts/check-ui-localization.py')
        shutil.copyfile(SCRIPTS / 'cldr-plural-categories.json', root / 'scripts/cldr-plural-categories.json')
        lookup = root / 'Packages/RFLocalization/Sources/RFLocalization'
        lookup.mkdir(parents=True)
        (lookup / 'CatalogLookup.swift').write_text('public enum CatalogLookup { public static let developmentLanguage = "en" }\n')
        (root / 'App').mkdir()
        if strings is not None:
            (root / 'App/Localizable.xcstrings').write_text(json.dumps({'sourceLanguage': 'en', 'strings': strings}))
        if swift is not None:
            (root / 'App/Screen.swift').write_text(swift)
        if baseline is not None:
            (root / 'scripts/localization-baseline.json').write_text(json.dumps(baseline))
        for path, content in (extra or {}).items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        return subprocess.run(['python3', str(root / 'scripts/check-ui-localization.py')], capture_output=True, text=True, timeout=10)

    def test_rejects_literal_copy_and_incomplete_locale_catalog(self):
        result = self.check(
            strings={'a.title': {'comment': 'c', 'localizations': {'en': unit('Title'), 'zh-CN': unit('标题')}},
                     'b.title': {'comment': 'c', 'localizations': {'en': unit('Only English')}}},
            swift='Text("Hard coded visible copy")\n',
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('literal UI copy', result.stderr)
        self.assertIn('b.title: missing locale zh-CN', result.stderr)

    def test_generated_accessibility_and_plural_signature_drift_are_rejected(self):
        result = self.check(
            strings={'key %lld': {'comment': 'c', 'localizations': {'en': plural(one='%lld message', other='%lld messages'), 'zh-CN': plural(one='%@ message')}}},
            extra={'Packages/RFDesign/Generated/Row.swift': 'String(localized: "Unread messages")'},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('generated accessibility must receive host-localized text', result.stderr)
        self.assertIn('missing plural other in zh-CN', result.stderr)
        self.assertIn('plural one is not a CLDR category of zh-CN', result.stderr)
        self.assertIn('format placeholders differ', result.stderr)

    def test_any_locale_set_is_accepted_without_script_changes(self):
        strings = {
            'files.count %lld': {'comment': 'Number of files', 'localizations': {
                'en': plural(one='%lld file', other='%lld files'),
                'zh-CN': plural(other='%lld 个文件'),
                'ar': plural(zero='%lld ملفات', one='ملف %lld', two='ملفان %lld', few='%lld ملفات', many='%lld ملفًا', other='%lld ملف'),
                'ru': plural(one='%lld файл', few='%lld файла', many='%lld файлов', other='%lld файла'),
                'pt-BR': plural(one='%lld arquivo', many='%lld de arquivos', other='%lld arquivos'),
            }},
            'files.title': {'comment': 'Title', 'localizations': {'en': unit('Files'), 'zh-CN': unit('文件'), 'ar': unit('الملفات'), 'ru': unit('Файлы'), 'pt-BR': unit('Arquivos')}},
        }
        result = self.check(strings=strings)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ar, en, pt-BR, ru, zh-CN', result.stdout)

    def test_new_locale_must_be_complete_and_plural_categories_follow_cldr(self):
        strings = {
            'files.count %lld': {'comment': 'Number of files', 'localizations': {
                'en': plural(one='%lld file', other='%lld files'),
                'ar': plural(one='ملف %lld', other='%lld ملف'),
                'ru': plural(one='%lld файл', two='%lld файла', few='%lld файла', many='%lld файлов', other='%lld файла'),
                'xx': plural(other='%lld'),
            }},
            'files.title': {'comment': 'Title', 'localizations': {'en': unit('Files'), 'ar': unit('الملفات')}},
        }
        result = self.check(strings=strings)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('files.title: missing locale ru', result.stderr)
        self.assertIn('missing plural few in ar', result.stderr)
        self.assertIn('plural two is not a CLDR category of ru', result.stderr)
        self.assertIn('no CLDR plural data for xx', result.stderr)

    def test_bundle_localizations_must_follow_the_catalogs(self):
        strings = {'a.title': {'comment': 'c', 'localizations': {'en': unit('Title'), 'zh-CN': unit('标题'), 'ar': unit('عنوان')}}}
        stale = 'info:\n  properties:\n    CFBundleDevelopmentRegion: en\n    CFBundleLocalizations: [en, zh-CN]\n'
        result = self.check(strings=strings, extra={'project.yml': stale})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CFBundleLocalizations ['en', 'zh-CN'] must equal the catalog locales ['ar', 'en', 'zh-CN']", result.stderr)
        current = 'info:\n  properties:\n    CFBundleDevelopmentRegion: en\n    CFBundleLocalizations: [ar, en, zh-CN]\n'
        self.assertEqual(self.check(strings=strings, extra={'project.yml': current}).returncode, 0)
        wrong_region = current.replace('Region: en', 'Region: zh-CN')
        result = self.check(strings=strings, extra={'project.yml': wrong_region})
        self.assertIn("CFBundleDevelopmentRegion must be the fallback language 'en'", result.stderr)

    def test_every_key_needs_the_english_fallback(self):
        result = self.check(strings={'a.title': {'comment': 'c', 'localizations': {'zh-CN': unit('标题')}}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('a.title: missing in fallback language en', result.stderr)

    def test_uncommented_keys_are_rejected_unless_baselined(self):
        strings = {'feature.screen.title': {'localizations': {'en': unit('New')}}}
        result = self.check(strings=strings)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('feature.screen.title: new key without a translator comment', result.stderr)
        baseline = {'uncommented_keys': {'App/Localizable.xcstrings': ['feature.screen.title']}}
        result = self.check(strings=strings, baseline=baseline)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_hashed_keys_are_rejected_even_when_listed_or_prefixed(self):
        strings = {'copy.0123456789ab': {'comment': 'c', 'localizations': {'en': unit('Old')}},
                   'FeatureChat.copy.89abcdef0123': {'comment': 'c', 'localizations': {'en': unit('Prefixed')}}}
        baseline = {'hashed_keys': {'App/Localizable.xcstrings': ['copy.0123456789ab']},
                    'uncommented_keys': {'App/Localizable.xcstrings': ['copy.0123456789ab']}}
        result = self.check(strings=strings, baseline=baseline, swift='let key = "copy.fedcba987654"\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('copy.0123456789ab: hashed key', result.stderr)
        self.assertIn('FeatureChat.copy.89abcdef0123: hashed key', result.stderr)
        self.assertIn("App/Screen.swift: hashed key 'copy.fedcba987654'", result.stderr)
        readable = {'chat.copy.title': {'comment': 'c', 'localizations': {'en': unit('Copy')}}}
        self.assertEqual(self.check(strings=readable).returncode, 0)

    def test_assembled_localized_text_is_rejected_unless_baselined(self):
        swift = 'let a = FooStrings.text("x", locale: locale) + " · " + name\nlet b = name + FooStrings.text("y", locale: locale)\nlet c = parts.joined(separator: " · ")\nlet d = rows + [(1, FooStrings.text("z", locale: locale))]\n'
        result = self.check(strings={}, swift=swift)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr.count('localized text assembled in code'), 3, result.stderr)
        baseline = {'assembly': [{'path': 'App/Screen.swift', 'line': line.strip()} for line in swift.splitlines()[:3]]}
        result = self.check(strings={}, swift=swift, baseline=baseline)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_package_with_catalog_needs_a_locale_test(self):
        catalog = json.dumps({'sourceLanguage': 'en', 'strings': {}})
        result = self.check(strings={}, extra={'Packages/FeatureNew/Sources/FeatureNew/Resources/Localizable.xcstrings': catalog})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('FeatureNew: missing locale-resolution test', result.stderr)


if __name__ == '__main__':
    unittest.main()
