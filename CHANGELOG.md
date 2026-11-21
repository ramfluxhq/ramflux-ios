# Changelog

## [0.2.2] - 2026-11-21

- Version line aligned with product 0.2.2.

## [0.2.1] - 2026-11-17

- Version line aligned with product 0.2.1.

## 0.2.0 - 2026-11-16

First release under the shared Ramflux product version (all repos move together).
Changes since 0.1.0, at a high level:

- Message actions in conversations (reply, edit, delete and similar), wired to the new generation-1 messaging.
- Permission handling is steadier: a stale request to open system Settings is cancelled when the permission changes.
- Contact safety numbers can be verified; edit conflicts are detected rather than overwritten.
- Settings, About now shows the app version and build number ("Version 0.2.0 (build 2)"), in English and Simplified Chinese.

The version lives in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`); bump it with the shared `bump-version.sh` script.
