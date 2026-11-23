# Changelog

## [Unreleased]

- Backup: once an archive chosen for restore is verified, the install step (new account code, or the merge confirmation) opens by itself.
- Contacts: a verification whose reply was lost is reconciled by reading the verification state again instead of reporting an unknown outcome.
- Real-run harness: phased runs (`prepare`, `rebuild`, `run`, `finish`) so every command stays short; run state kept in the loopback control server's memory between phases; the device event trace is saved for every flow that does not pass.
- Real-run suite reads the recovery phrase through a debug-only accessibility seam of the phrase display (launch argument `-RFRealRunPhraseAccess`, never compiled into release builds) instead of text recognition, so the word check no longer misses a word.

## [0.2.6] - 2026-11-23

- Align release metadata with product version 0.2.6.

## [0.2.5] - 2026-11-22

- Version line aligned with product 0.2.5.

## [0.2.4] - 2026-11-21

- Version line aligned with product 0.2.4.

## [0.2.3] - 2026-11-21

- Version line aligned with product 0.2.3.

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
