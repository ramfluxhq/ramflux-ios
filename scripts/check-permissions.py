#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
"""Check generated app declarations and both localized usage-description resources."""
from pathlib import Path
import plistlib
ROOT = Path(__file__).resolve().parent.parent
EXPECTED = {'NSMicrophoneUsageDescription', 'NSCameraUsageDescription', 'NSPhotoLibraryAddUsageDescription'}
info = plistlib.loads((ROOT / 'build/App-Info.plist').read_bytes())
assert {key for key in info if key.endswith('UsageDescription')} == EXPECTED, 'Unexpected privacy usage declaration'
assert info.get('UIBackgroundModes') == ['remote-notification'], 'Unexpected background mode'
for language in ['en', 'zh-CN']:
    localized = plistlib.loads((ROOT / f'App/Resources/{language}.lproj/InfoPlist.strings').read_bytes())
    assert set(localized) == EXPECTED, 'Usage descriptions must match the exact permission allowlist'
    assert all(isinstance(value, str) and value.strip() for value in localized.values()), 'Empty usage description'
extension = plistlib.loads((ROOT / 'build/NotificationService-Info.plist').read_bytes())
assert extension['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.usernotifications.service', 'Unexpected extension point'
assert not {key for key in extension if key.endswith('UsageDescription')}, 'The notification extension declares no usage description'
for name in ['App/Ramflux.entitlements', 'NotificationService/RamfluxNotificationService.entitlements']:
    entitlements = plistlib.loads((ROOT / name).read_bytes())
    assert entitlements['com.apple.security.application-groups'] == ['$(RAMFLUX_APP_GROUP)'], name + ': App Group missing'
    assert entitlements['keychain-access-groups'] == ['$(RAMFLUX_KEYCHAIN_GROUP)'], name + ': shared Keychain group missing'
    assert 'com.apple.developer.usernotifications.filtering' not in entitlements, name + ': filtering is added only once Apple grants it'
assert 'NSLocalNetworkUsageDescription' not in info and 'NSBonjourServices' not in info
print('PERMISSIONS_OK: three localized usage descriptions; add-only Photos; remote-notification only; extension and entitlement groups; no broad or unrelated grants')
