# Changelog

## [Unreleased]

- Storage and custody: the SDK data root moves to `ramflux/` in the App Group container (`AppStorage.prepare(groupContainer:)`; `NativeCore` refuses any other root on iOS) and both Keychain classes (`HostCustodyProvider`, `KeychainVault`, which also serves the chat vault) use the shared access group declared in Info.plist. There is no migration: installs made before this start empty. The real-run scripts read backups and the SDK log from the group container. `docs/bridge.md`, `docs/permissions.md` and `docs/app-shell.md` no longer say there is no extension or shared group.
- Push floor: the app catalog has `RF_PUSH_MESSAGE`, `RF_PUSH_CALL` and `RF_PUSH_TEST` (English and Simplified Chinese) so a push alert shows the generic text instead of the key; `Packages/Push` holds the generic content, categories (`RF_MESSAGE`, `RF_CALL`, `RF_TEST`, `RF_NOTICE`) and the `rf` payload parser; the extension builds the fixed text of the wake's class and removes the app's local message notification first. The local notifier keeps one notification per account (fixed request id per account, category `RF_MESSAGE`), and a tap shows that account's chat list.
- Push scaffolding: Debug and real-run builds use the bundle id `org.ramflux.ios.dev` (Release keeps `org.ramflux.ios`), with project-level settings for the App Group, the shared Keychain access group and the APNs environment; a notification service extension target `RamfluxNotificationService` (pass-through, logs `push.nse.received`), an empty-but-linked `Packages/Push`, an app delegate that logs the APNs token length only, and `scripts/push/` (payload files and `inject.sh`) for `simctl push`. The real-run scripts take the bundle id from `RAMFLUX_REALRUN_BUNDLE_ID` (default `org.ramflux.ios.dev`). `docs/push.md` records the simulator facts: `simctl push` does not start the service extension on Xcode 27.2 and iOS 27.2.
- Chat list: the Messages list no longer stays empty after the app returns from another app or the Home screen. SwiftUI can deliver the new screen's appearance before the old one's disappearance, and the inbox reset itself on the late disappearance and stopped observing; it now counts the screens showing it and resets on the last disappearance only.
- In-app banner: a banner is raised only by a new incoming user message or call. The feed keeps the newest item seen in each conversation; a rise of the unread count caused by a service or group event, an own or removed message, or an unread read raises none, and an older message's text is never shown.
- Real run: flows run with banners on; the file-preview sheet that flow 7 opens is dragged closed (it has no close control); a banner is swiped away before Back and in the shared prompt check.
- In-app banner: the banner feed follows the account again after its event stream ends (and when the app returns to the foreground), the 80-character preview is trimmed of a trailing blank, and the banner carries the accessibility identifier `in-app-banner`.
- Real run: new flow 17 (the banner is found by its identifier, a tap opens the conversation, no banner while the thread is open) and flow 18 (Home with a chat open and the keyboard up, for the snapshot check); every tap and Back first swipes an on-screen banner away, because a banner covers the top bar for about four seconds.
- In-app banner and snapshot privacy: a new incoming message while the app is in the foreground on any other screen than its conversation shows a banner the app draws itself (sender or group name and a one-line preview of at most 80 sanitised characters; fixed texts for calls and non-text content; auto-dismiss after about 4 s, tap opens the conversation, swipe up dismisses, a newer message replaces it). It is fed by the conversation directory stream (rising unread count, then the newest message) and is skipped for the open conversation, muted conversations and own messages; it is never a system notification (`willPresent` still returns nothing). While the scene is being recorded or mirrored, or the app is locked, the banner is generic ("New message") and hidden from accessibility. Whenever the scene is about to become inactive any banner is dismissed and an opaque privacy cover is drawn over every window (always on, not tied to the app lock) before the system snapshot; the cover is removed on becoming active and `ignoreSnapshotOnNextApplicationLaunch()` is called on every move to the background. No banner field is logged, stored or donated.
- Usernames: a refusal of the sealed `username.status` call now keeps the SDK's typed directory reason (a new allowlisted scan of the completion root, `rf_completion_directory_reason`), so the Settings row shows "Usernames are not available on this server yet." for `directory_unavailable` and the generic typed-refusal text for the other directory codes, instead of "Outcome not confirmed".
- Real run: flow 5c has carol take the phone's contact card first (one way; the phone never accepts carol) so her group create can add the phone. Debug builds also log the delivery tally on every chat publish and the number of reconfigured rows on every timeline update, to separate a receipt the window never took from one the table did not draw.
- Real run: the SDK log files are copied from the simulator app's data container to `sdk-diag/` of the run's output at the end of every run. Flows 5c and 5d use a third peer, carol, who was never a contact of the phone (a removed contact's invitation no longer arrives by design); they report BLOCKED when the peers file has no carol. Debug builds log the shape of each message change row (kind, state, receipt states, keys; no content) to find why the sender's own bubble stays Delivered.
- Errors: a refusal with code 1, 16 or 25 shows the SDK's typed reason (`CoreFailure.reason`, `statusName`) instead of a bare code; the untyped-16 username fallback is gone. `message.focus` refused with `unsupported_for_group` is ignored.
- Open configuration: the app passes the username directory pin (`url`, `id`, `public_key`, `generation`) from the `RAMFLUX_USERNAME_DIRECTORY_*` build settings through Info.plist; without them username calls refuse with `directory_unavailable`. No address is compiled in. Debug builds also turn on the SDK diagnostic log (`diag`), written to `diag/` in the data root.
- SDK pin: core `next` commit `5d117366773c54bcbfbf64c7a9eb5d7f02ee4f57` (header unchanged since `31ab2296`: only the `ramflux_v2_client_suspend` comment changed there; 239 bridge operations unchanged). The core adds the username directory pin and the `diag` log to the open configuration, names every nonzero completion (`name`, `reason`, `reason_code`), refuses `message.focus` on a group with `unsupported_for_group`, makes suspend all-or-nothing, keeps the account runtime from waiting while it holds the command slot, makes the first attachment step after a cold reopen wait for gateway readiness, publishes one typed update per read receipt (no extra generic invalidation) so the sender's journal row carries Read, and keeps attachment ownership across a backup restore.
- Chat: typing in a group no longer calls `message.focus`, which the core does not support for groups; direct chats still focus and blur around the typing indicator.
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
