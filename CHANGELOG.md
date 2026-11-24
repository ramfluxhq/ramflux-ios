# Changelog

## [Unreleased]

- SDK pin: core `next` commit `ab90d1a99d6d090aeb9a02a6d06345e84629af95` (method policy synced; the header and the 239 bridge operations are unchanged, only the `contact.verify` descriptor changed). The core no longer stalls receiving when an entry needs pair recovery (it is skipped with a typed `pair_recovery_unavailable` refusal), so a removed contact's group invitation does not arrive; it also adds media metadata and thumbnails, wipes attachment staging after a send, and retires an attachment on delete for everyone.
- SDK pin: core `next` commit `f2f466be297062c438d2b884baf71e810b4fcc92` (header, method policy and generated adapters synced; 239 bridge operations of 246 policy rows, new: `account.app_lock.configure`, `account.app_lock.state`; new exports `ramflux_v2_shared_snapshot` and `ramflux_v2_wake_fetch`, not used by the app yet). The core fixes a contact re-added from its card losing the pinned node fingerprint and a receive error stopping later events. The attachment send path already follows the core attachment contract (explicit `attachment.enable`, prepare, chunks, BLAKE3 digest, send by `prepare_id`); the SDK now removes its own plaintext staging copy after a send.
- SDK pin: core `next` commit `14e38cda6f7d9c8eb17b811b46ae87750756199d` (header, method policy and generated adapters synced; 237 bridge operations of 244 policy rows, new: `group.leave`, `contact.requests.decline`, the five `username.*`/`profile.update` methods, `agent.host.manage` and related agent methods; new exports `ramflux_v2_client_suspend`, `ramflux_v2_client_resume`, `ramflux_v2_username_authorize`, `ramflux_v2_set_host_credential_provider`; statuses `Suspended` (30) and `VaultLocked` (31)).
- Lifecycle: a return from the background or a relaunch asks for nothing. The app suspends the SDK in the background and resumes it on return (unlocked accounts stay in memory); on a cold start the SDK reopens accounts that were not explicitly locked with their device-bound key. The screens, the open chat and its draft stay as they were; a send interrupted by the suspension stays queued and is flushed again on return. The code is still asked for first set-up, restore, after an explicit lock or sign-out, and to change it.
- Lifecycle: removed the workarounds for the SDK closing in the background: the shell no longer conceals the session and dismisses the navigation on inactivity, no longer parks and reopens screens after an unlock, and the chat outbox is no longer sealed on every background. The optional app lock has a seam (`AppLockGate`, off by default).
- Conversations: direct conversations are named by the SDK (`peer_display_name`) instead of a client-side lookup in the contact list.
- Groups: leave a group (`group.leave`, after a confirmation; an owner transfers ownership first); group invitations refresh on the SDK's `group.invitation` event.
- AI marker: contacts, contact requests, conversation rows, the chat header, group members and incoming group messages show an AI marker for participants the SDK verified as AI agents (`verified_classification` `ai_agent`); agents are otherwise shown exactly like people.
- Usernames: the username row in Settings asks the username directory (`username.status`) and the add-contact field accepts `@name` (`username.contact.add`); the directory's refusal is shown as an honest unavailable state.
- Real-run suite: background and return now fails if the code is asked; new flows for terminate and relaunch without a prompt, read receipts both ways, a group invitation from a non-contact accepted on the phone, leaving that group, and usernames.
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
