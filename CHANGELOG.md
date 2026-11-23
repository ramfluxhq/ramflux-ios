# Changelog

## [Unreleased]

- SDK pin: core `next` commit `e39111de54737e8ae2d545a3b256e70f43c5aec5` (header, method policy and generated adapters synced; 219 bridge operations, new: `account.sign_out`, `account.remove_local`, `card.session.*`, `agent.retire`, and `ramflux_v2_set_credential_provider` in the header).
- Accounts: the account list comes from the SDK's `account.list`, which now returns every account on the phone with its display name and lock state; the app's own registry of known accounts (`known-accounts.json`) is removed.
- Accounts: after too many wrong account codes the unlock step names the wait the SDK reports instead of "wait a while".
- Accounts: the account screen offers sign-out (`account.sign_out`) and removal of the account from this phone (`account.remove_local`, after a confirmation); the unlock step's removal of an account the SDK refuses now erases it through the SDK after a confirmation instead of hiding a registry entry.
- Chat: own replies rely on the SDK's `is_own` (fixed in the SDK); the author-device fallback is removed. A media send refused with an internal failure is no longer special-cased; the debug trace keeps the typed failure.
- Real-run suite: before the media flows the phone adds the peer's contact card to the accepted contact, which pins the peer's home node that attachments need; the media flows report a refused send as a failure with the typed cause instead of the earlier SDK block.
- Real-run harness: every machine-specific input (node facts, peers, rf CLI, conversation id helper, optional node check, peer control, clock container, toolchain file) is an environment variable, read from an untracked `scripts/realrun.local.env` (see the committed example); a missing input stops the script with a message naming it.
- Shell: after the code unlock that follows a return from the background, the screens that were open (for example the chat) come back in the same navigation change that closes the unlock step; before, the stack finished popping the unlock step after the chat was pushed and dropped it.
- Chat: a media send that the SDK refuses at `conversation.send` with an internal failure (code 16) reads "not sent" with a retry under the same operation id instead of waiting behind an offline banner; the debug trace records the request shape for the SDK team.
- Groups: a new group opens the conversation named by the creation reply, without reads that could run before the group list caught up; opening a listed group asks the group's metadata for its conversation before history.
- Groups: a contact is added to a group by its principal id alone; the explicit root made the SDK read the principal id as a device id and refuse the add (code 16).
- Backup: once an archive chosen for restore is verified, the install step (new account code, or the merge confirmation) opens by itself.
- Contacts: a verification whose reply was lost is reconciled by reading the verification state again instead of reporting an unknown outcome.
- Real-run harness: phased runs (`prepare`, `rebuild`, `run`, `finish`) so every command stays short; run state kept in the loopback control server's memory between phases; the device event trace is saved for every flow that does not pass.
- Real-run suite reads the recovery phrase through a debug-only accessibility seam of the phrase display (launch argument `-RFRealRunPhraseAccess`, never compiled into release builds) instead of text recognition, so the word check no longer misses a word.
- Repository clean-up: remove the committed simulator evidence capture (CI regenerates it as a build artifact), list the bundled fonts in `NOTICE`, and neutralise design-token metadata and notes that referred to internal tooling and documents.

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

The version lives in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
