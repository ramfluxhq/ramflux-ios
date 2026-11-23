# Application shell

`FeatureAppShell` is the independently buildable application shell. It owns
navigation, account selection, session presentation and lifecycle privacy. Feature
screens are installed by independent feature packages; missing capabilities have
an explicit unavailable presentation.

- `AppShellScreen` and `AccountPickerScreen` render a value State and emit Action.
  They have no SDK imports, async calls, repositories or mutable application data.
- `AppShellState` is an Equatable, Sendable value. `AppShellAction` is the only
  ViewModel input. `AppShellEvent` is a separate, one-shot coordinator callback.
- `AppShellViewModel` owns its operation and observation tasks. Inactive scenes
  immediately conceal account records and cancel pending UI work. Generations
  reject late completions. Background/disappearance asks the Repository to suspend.
- `AppShellCoordinator` owns navigation and sheets. Deep links can only navigate
  to the allowlisted read destinations; query-bearing links cannot approve actions.
- `AppData.SessionRepository` owns the session domain and returns typed
  `RepositoryResult` values. Its native implementation consumes RamfluxCore Proxy
  responses, maps account records and manages PhoneLifecycle. No SDK values cross
  this boundary. Its bounded snapshot stream retains only the newest state.
- `RFDesign` imports manifest-owned generated tokens/components. Handwritten
  extensions and layout live outside `Generated`. Licensed Noto Sans SC, Hanken Grotesk and JetBrains Mono variable fonts are
  bundled and registered by their actual PostScript names before rendering.
  Clean-process tests verify the resolved names and packaged font URLs.

- `AppRepositories.lifecycle` (`AccountLifecycleHooks`) lets account-scoped stores register for
  `willLock` (awaited before `account.lock` is sent) and `willRemove` (for sign-out or removal; the
  pinned SDK has no account removal method, so nothing triggers it yet).
- `AppComposition.requestPermission(_:resolved:)` runs the permission explanation and system prompt for
  a feature and calls back with whether the permission is usable (`PermissionsEvent.ready` or
  `.declined`). Feature hosts receive it as their permission-request handler.

## Build modes

Without `RAMFLUX_CORE_XCFRAMEWORK`, the application factory returns a typed
unavailable Repository. The bridge links a weak, refusing C provider, which never
opens storage, transports messages or returns accounts. ABI tests override it
with their strong test-only fixture definitions. `CABIFixture` is not an app
dependency. The bridge product uses automatic linkage so app/test consumers share
its framework when Xcode requires it.

With `RAMFLUX_CORE_XCFRAMEWORK` set to the matching artifact's package-relative path,
AppData compiles its native factory and the bridge depends on that artifact;
the unavailable C provider is excluded from its dependency graph. Prepare the
matching artifact using [the bridge instructions](bridge.md), then regenerate the
project with the same environment and keep it set for Xcode package resolution.
No native artifact or real account runtime has been validated by source-only tests.

```sh
xcodegen generate
swift build --package-path Packages/FeatureAppShell
swift test --package-path Packages/FeatureAppShell
swift test --package-path Packages/AppData
swift test --package-path Packages/RFDesign
xcodebuild -project Ramflux.xcodeproj -scheme Ramflux \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

Use persistent `--scratch-path`/`-derivedDataPath` locations for local work.
The iOS CI workflow selects installed Xcode 27.2 on hosted `macos-15`, runs the
host checks and builds/tests the application on an available iPhone simulator.
`AppShellSnapshotTests` captures all six major states in both themes and at large
Dynamic Type, plus the tab presentations, over every locale and canvas of
`AppTests/CaptureMatrix.swift`. Feature snapshot attachments are review
artifacts. Design boards are verified separately: `ShellBoardCaptureTests`
renders each board at exactly 393x852 pt and `scripts/compare-boards.py` compares
it pixel by pixel with the design reference; see
[board verification](board-verification.md). Source compilation alone does not
prove those captures executed.

The app immediately shields UI on inactivity; proving actual writer release
before OS suspension still requires a linked SDK/device test. No recovery words,
keys, message bodies or operation payloads are logged or exported by the shell.

## Feature modules

`FeatureOnboarding`, `FeatureConversations`, `FeatureChat`, `FeatureContacts` and
`FeatureSettings` and `FeatureGroups` each expose Screen, State, Action, Event, ViewModel and Coordinator
types. Screens render State and emit Action; ViewModels own cancellable asynchronous
work. AppData owns repositories shared over one RamfluxClient and maps SDK responses
into application records. Every visible feature observes account invalidations through
the shared event fan-out (`NativeUpdateSource`, see `docs/bridge.md`), so a list and a
detail can be live at once. UIKit owns the message timeline (a `UITableViewController` whose cells host
SwiftUI `MessageBubble`s) and the secure input editors. The composer is the
SwiftUI `KitComposer`, a `TextField` that grows vertically. Message text is system
text (`KitMessageText`): selectable, with detected links, and running in the
direction of its own content, while the bubble side follows sender and own
messages. Recovery output is painted from erasable bytes rather than decoded
into a Swift String; spoken recovery-word accessibility is currently limited.

The account code is six ASCII digits. Creation asks for the code twice and confirmation,
recovery and unlock take it through `RFSecureEntryForm` account-code editors (number pad,
left to right, at most six digits). `SensitiveSubmission(values:accountCode:)` checks the
code on transient bytes before the erasable buffers are built and mirrors the SDK admission
rule (six digits, not all equal, not a straight run), so a single-attempt ceremony is never
spent on a code the SDK would refuse. SDK refusals `not_six_digits`, `trivial_code`,
`unlock_retry_later`, `unlock_attempts_exhausted`, `account_code_required` and
`device_unlock_unavailable` map to `AppFailure.accountCode`. The SDK computes the wait after
repeated wrong codes but its C ABI error projection drops `retry_after_secs`, so the app can
only say "wait a while".

The conversation list reads `conversation.directory` one page (50 rows) at a time through
`ConversationsRepository.page(account:cursor:limit:)` and follows `next_cursor` when the last
row appears. The SDK orders directory pages by conversation id and offers no activity-ordered
cursor (`conversation.list` is recent first but unpaged), so `ConversationsWindow` sorts only the
loaded rows by `last_activity` off the main actor and says so in a footnote; a refresh re-reads at
most six pages. The window keeps at most 300 rows: scrolling further evicts rows from the top
(and, while evicted, drops later rows that would sort above the first kept row); reaching the first
row of an evicted window reloads the first six pages. With no rows, the list shows the skeleton
(MOB-B01L) while loading, a centred failure with a retry button (MOB-B01X), or the centred empty
state with an add-contact action (MOB-B12); once rows exist a failure is shown above them. Time labels come from `last_activity` (Unix seconds); the SDK provides no preview,
so none is shown. The message-requests row counts pending inbound `contact.requests.list` rows.

Message sending uses the high-level conversation intent. An uncertain send retains
its original operation key and text for explicit retry. Device revocation and verified
archive installation require host-drawn single-tap confirmation bound to the selected facts. Confirmation opens with Cancel focused for keyboard and accessibility. Hardware-key events cannot activate Confirm; its accessibility label names the action and target.
Backup and restore run on the phone (`BackupRepository`, screen `BackupScreen`, board MOB-G09). The SDK
admits `account.backup.create`, `account.backup.cancel`, `account.restore.verify` and
`account.restore.install` only on an attended connection (`bus/backup_jobs/routing.rs`): the in-process
connection is attended once a subscription opened with `attended_frontend` is live. With an account that
is the shared account subscription; on a new install it is the daemon-scoped job stream
(`NativeUpdateSource.observeBackupJobs()`, topic `account.backup.job.changed`, no account). The screen
keeps that observation while it is visible and refuses a secret until it is live. A backup is sealed with
its own archive passphrase (at least 15 Unicode scalars and not a common password, SDK
`passphrase/archive.rs`; the six-digit code never qualifies); it is not derived from the recovery phrase.
The app pre-checks length and the repeat, the SDK stays authoritative. The archive is written into
private, backup-excluded storage and handed to the user with the system file mover, which moves it out,
so no copy stays behind; "Delete from this phone" removes an archive that was not moved. A picked
archive is copied on a serial file worker into private storage (security-scoped access, regular files
only, refused above 256 MiB before and while copying), verified with its passphrase, and the private
copy is removed when the restore job ends or the request is refused. Installing an archive whose
`archive.merge` is true merges into the existing account with host-drawn confirmation and no secret
(the SDK refuses one); otherwise the archive becomes a new account and takes a new six-digit code. The
SDK reports job changes only on the daemon stream, so the screen re-reads `account.backup.jobs` every
second while a job runs. Onboarding offers "Restore from a backup" (the backup screen without an
account) as the recovery path on a new install, because phrase recovery needs the account on the phone.

Onboarding follows the boards: get started (MOB-S02, 2026-11-16 revision: the selected node, "change
node", Continue) leads to the welcome (MOB-S18: create an account, continue with an existing account,
recover with the recovery phrase, and "Restore from a backup" in the board's empty middle). "Continue
with an existing account" opens MOB-A01 (the selected node and "change node", the device-not-authorised
row that explains why joining from this phone is unavailable, and unlock); unlocking a stored account is
MOB-A02 (local account id, the six-digit code entry in the local-only card) with the device unlock
information MOB-A07 one tap away. The splash is MOB-S01 and account creation MOB-N01. Steps without a
board (node address and identity, the recovery phrase, the six-digit code, recovery, completion) use the
same page frame: Kit header whose back action cancels setup, content, and the step's action pinned
above the home indicator. The secure entry forms, the single-attempt confirmation and the erasure are
unchanged.

Settings follow board MOB-G02: grouped cards for account and devices, connection and data (nodes,
backup and restore, connected services, storage) and app (appearance and language, diagnostics and
about, system permissions), plus call history and cards until their own module places those entries.
Account and security offers lock, changing the six-digit code (`account.passphrase.rotate` with the
current code as `old_passphrase`; both codes are checked locally first and never journaled) and privacy.
Privacy switches `contact.requests.policy.set` between `manual` and `auto_accept`, the only honest part of
"open account" at this SDK pin; the open-account and @username boards (MOB-G27–G30) show typed
unavailable states because the SDK has no username, open-account or reach methods. The language list
shows the fifteen launch languages with their translation state from the package catalogs (English and
Simplified Chinese today; no placeholder translations ship) and opens the app's system settings, where
iOS offers the per-app language. Storage management is the media module's screen; its entry shows a
typed unavailable state until then. Devices offers "Link new device" (route `pairDevice`, board MOB-G24): this phone, as the primary,
names the new device, shows the show-once invitation as a QR code (covered while the app is not active),
compares the seven symbols, reviews the joining device's name, id, rights and lease before a host-confirmed
approval (MOB-P02/P02S facts) and shows the completed, cancelled, expired or declined result
(`device.pair.begin/status/confirm/approve/cancel`; see the bridge notes). Joining another account from
this phone stays unavailable (request R32).

Unpaged snapshots (`contact.list`, `contact.requests.list`, `group.list`) decode through
`ProxyGateway.mapRows`, which maps 1,024 rows per step off the main actor and yields between steps. There is no
row-count ceiling; the size guard is the 1 MiB per-response byte ceiling (`CoreLimits.frameBytes`), the same
as the SDK's own local-bus frame limit (`MAX_LOCAL_BUS_FRAME_BYTES`). A roster larger than 1 MiB of JSON
(several thousand contacts) is therefore refused by the SDK and the bridge alike until `contact.list` pages.

Contacts and contact requests read through `RowWindow` (AppData), a bounded window of
at most 300 rows over a `RowPageReader`. `contact.list` and `contact.requests.list` are unpaged
in the SDK, so `SnapshotPager` reads each once per first page, keeps the matching rows in the data
layer and pages them by offset; the filter runs there, off the main actor. A contact profile offers
block, unblock and remove (`contact.block`, `contact.unblock`, `contact.remove` with scope `me`, each
selected by `link_id`) behind host-drawn confirmation. Marking a safety number verified reads
`contact.verification.status` and passes its `expected` snapshot to `contact.verify`, a
compare-and-set, so a number that changed after the user compared it is not recorded as verified.
The group list reads `group.list` through the same snapshot pager and window, filtered in the data
layer. `group.members` returns the whole roster in one response, so the members screen renders a
growing window of projected rows (50 more per scroll step) over the roster held by the detail; the
add-member picker pages contacts through `contactsPage`. The SDK has no `group.leave`: a non-owner's
`group.member.remove` is staged as a change request to the owner, so leaving stays unavailable.
Tasks, task conversations and permissions read through bounded `RowWindow`s (`task.list` by cursor,
`grant.list` through `SnapshotPager`). A pending approval shows the Kit approval card; approving or denying
sends `grant.approve`/`grant.deny` with its `approval_id` after host-drawn confirmation and after re-reading
the approval unchanged. Approvals whose `confirmation_mode` is `remote_app` need an app-signed
`mcp.approval.granted` (SDK `error.rs`), which the C ABI gives this app no way to produce, so they can only be
denied here, as the reference CLI also refuses to approve them.
Agents read `agent.list` page by page (cursor `next`) into the bounded window; the search filters the
held window because `agent.list` takes no query. Account invalidations carry no agent topic, so on
each one the directory asks `agent.watch` for records changed since its journal cursor and patches
them by id. The profile reads `agent.get`; editing the name and responsibility sends
`agent.persona.edit` and deleting sends `agent.delete`, both with `confirmed` after a confirmation.
Agent methods carry no operation id (the SDK refuses one). A pending desktop-started creation
(`agent.operation.get` with an empty id) is shown with its request id and expiry, but approving or
declining is unavailable: `agent.creation.decide` needs `request_hash`, which the CLI computes from the
plan bytes with Rust code the C ABI does not expose. Changing access is unavailable because
`agent.access.set` needs the record's event identity as `base` and the wire record does not carry it.
Pausing, hiding and goal settings have no SDK methods. Opening an agent's chat navigates to the
SDK's direct conversation id for this account's root (`account.status` `principal_commitment`) and the agent
anchor: `"dm:" + base64url(BLAKE3(lp(domain) || lp(lower root) || lp(higher root)))` (`message/dm_scope.rs`),
derived in AppData (`DirectConversationID`, a single-chunk BLAKE3 checked against the reference crate). The
SDK creates that conversation only for an accepted contact; whether an owner's agents are always linked
that way is not verified against a node.

Unsent chat state (queued and failed sends with their original operation ids, staged
media references, composer drafts and erase-for-everyone revokes still to retry) is
kept per account in one AES-GCM sealed file under Application Support/RamfluxChat,
written atomically with complete file protection and excluded from backup. The key
is a per-account keychain item (`org.ramflux.chat.vault`, this device only). The
repository restores it on first use after unlock and resumes queued sends with the
same keys; admitted and discarded entries leave the file, and the account purge
erases the file, the key, staged files and stored media. Staged media lives in the
account media outbox (complete-unless-open, excluded from backup). Shared files are
temporary copies under the sanitised original name, removed when the sheet closes.

Downloaded originals live in `RamfluxMedia/<account>/originals/<conversation>/` (hashed
names, complete-unless-open, excluded from backup). Eviction policy: nothing is evicted
silently. Originals leave the device when the sender erases the message, the user deletes
it, or the user clears media in storage management (the chat details sheet per
conversation, `MediaStorageScreen` for the account, both behind a confirmation); staged
files of queued sends are never cleared there, and unreferenced staged files older than
ten minutes are swept after unlock. Decoded images live only in the bounded memory cache
of the image pipeline. The conversation gallery pages the message read model (the SDK has
no media filter yet) in bounded steps and keeps at most 2,000 items.

Background transfer: uploads and downloads run inside the SDK over its gateway session,
so a background URL session cannot carry them. Each active transfer holds a
`UIApplication` background task assertion; when iOS ends it (about 30 seconds) the app is
suspended, the queued send stays sealed and resumes with the same operation id on the next
activation, and an import restarts because the SDK keeps import handles in memory only.

## Calls and the media engine boundary

Calls use the SDK's one-to-one voice contract: `call.invite {conversation_id}` (voice only),
`call.answer`, `call.reject` and `call.hangup {call_id}`, `call.list {}` (at most 128 rows,
newest first, read as one history page with no cursor) and live state through the explicit
`call.changed` topic of the shared event fan-out. Calls reach `active` through relay
signalling alone; audio and video need a media engine. `NativeCallsRepository` takes a
`CallMediaEngine` (default `RefusingCallMediaEngine`) and sends invite and answer only while
the engine reports itself available, because a real invite rings the peer. While it refuses,
the call screens say that voice and video are not available in this build; incoming calls can
be seen and declined but not answered, and no connected state is shown.

`call.media.session {call_id}` is read at most once per call, only for an `active` call, and
only by the repository. The SDK returns the material once (`media_taken`); a lost read or an
engine restart requires a new call. The reply is a secret-output frame: the repository checks
only `code`, `response.ok` and the presence of `relay` and `sframe`, copies the frame into an
erasable `SecretBytes` and hands it to `CallMediaEngine.start(_:)` as a `CallMediaSession`.
The engine reads it once with `consume`; the bytes are the UTF-8 JSON frame
`{"code":0,"response":{"ok":true,"body":BODY}}` where BODY is exactly:

```text
relay:  {endpoint: "host:port", token: base64url(32 bytes), lease_id: base64url(16 bytes),
         side: 0 (caller) | 1 (callee), rebind_key: base64url(32 bytes)}
sframe: {cipher_suite: 5 (AES_256_GCM_SHA512_128),
         send: {kid, base_key: base64url(32 bytes)}, receive: {kid, base_key: base64url(32 bytes)}}
```

KIDs are 0 for caller-to-callee and 1 for the reverse; counters start at zero per key with a
128-counter receive replay window. Media is Opus 48 kHz mono, 20 ms frames, minimal RTP with
payload type 111, SFrame (RFC 9605) over the RTP payload with the RTP header as authenticated
data. Datagrams to the relay are `u32be(token length) || token || RTP/SFrame`; empty framed
datagrams every 5 s keep NAT bindings; on an address change the relay sends the `RFVC`
challenge and the engine answers `RFVE || cookie || HMAC-SHA256(rebind_key, ...)[0..16]`
within five seconds (the core repository's `docs/voice-calls.md` is the normative source).
Never log, persist or journal any of these values.

An engine implements `CallMediaEngine`: `availability()` (synchronous; capabilities audio,
video, camera switch, speaker route), `start(_:)` (owns and erases the material; the result is
final for that call), `stop(callID:)`, `control(_:callID:)` (mute, route, camera on or off,
switch camera), `audioSession(active:)` (CallKit activated or deactivated the audio session,
or an interruption began or ended; audio I/O runs only while active), `events()` (state
`starting`, `connected`, `reconnecting`, `stopped`, `failed`, audio levels and remote video
on or off) and `attach(_:slot:callID:)` on the main actor (a `CallVideoSurface` view for the
local or remote slot, nil to detach). The rf side supplies the production engine (request
R28); the app constructs it in the factory's `NativeCallsRepository(... engine:)`.

`FeatureCalls` owns the system call integration: `CallKitProvider` (one `CXProvider` and
`CXCallController`, generic handles, not added to Recents, hold refused), `CallSystemBridge`
(maps `call.*` state to the system UI and system actions to repository intents; inert while
the engine refuses, because the system incoming-call UI always offers Answer),
`CallAudioSession` (play-and-record in voice or video chat mode with Bluetooth, speaker
override, interruption and route-change events) and `CallSystemService` (the app-lifetime
owner for the active account). Microphone and camera are requested through
`CallPermissionRequesting`, which `AppComposition.requestPermission(_:resolved:)` satisfies,
right before an invite or answer the engine can carry. Incoming calls while the app is not
running need a VoIP push from the node and PushKit registration; the node has no VoIP push
today (requests R21 and R28), so incoming calls appear only while the app is running and
connected.

Local search, joining another account from this phone, replying to a stranger without accepting,
stranger reporting and batch request actions are unavailable until their SDK/integration
contracts exist. Message send, reply, edit, reaction and delete use the published
conversation contract. Open-account reachability is not inferred from automatic contact
request acceptance. No synthetic identity, routing, delivery or verification state
is used as a substitute. Previews use isolated illustrative fixtures; production
repositories do not.

Each feature package supports `swift build --package-path Packages/FeatureName` and
`swift test --package-path Packages/FeatureName`. CI also captures major feature
states in both themes. Generated design files are hash-owned and read-only;
platform compatibility extensions remain in RFDesign/Sources.

## Localization and themes

Every package owns a String Catalog; English is the development and fallback
language. Every package `*Strings` helper and the app's `RamfluxAppStrings` look
keys up through `RFLocalization.CatalogLookup`, which picks the best localisation
for the locale and falls back to the English entry (with English plural rules)
for any key the localisation lacks, so a missing translation never shows a raw
key. The app's `CFBundleLocalizations` in `project.yml` must list exactly the
locales present in the catalogs and `CFBundleDevelopmentRegion` must be the
fallback language; the UI copy check fails otherwise, so adding a language
updates that list in the same change.
`export-localizations.py` compiles catalogs into checked portable `.strings`/`.stringsdict`
resources for SwiftPM native CLI compatibility. Catalogs remain the sole source;
CI verifies exported semantics with the pinned Apple catalog compiler.
Peer text and protocol identifiers are data rather than translation keys. Catalog
format entries carry variable labels; dates and numbers use the active locale.
The UI copy check rejects literal presentation labels and is language-agnostic:
the shipped locales are the locales present in the catalogs, so adding a
language is a resources-only change. Every key needs its English entry and every
shipped locale, plural variations must have exactly the CLDR categories of their
language (`scripts/cldr-plural-categories.json`), and new keys without a
translator comment and localised text assembled with `+` or a literal separator
fail. Keys are readable hierarchical names (`feature.screen.element[.state]`); a
hashed `copy.<hash>` key in a catalog or a Swift source always fails. Existing
debt is listed in `scripts/localization-baseline.json`, which may only shrink.
Text that combines catalog copy with values is one catalog format composed by
`CatalogLookup.sentence` (`RFSentence`) with typed arguments: peer-controlled
text (names, group names, titles, origins) is stripped of directional controls
and isolated (FSI ... PDI), identifiers keep Western digits inside a
left-to-right isolate, and lists use the locale's list format. These string
rules (`RFBidi`, `RFUntrustedText`, `RFFileName`, `RFIdentifier`,
`RFSentence`) live in RFLocalization so AppData applies them when it builds a
display string without depending on RFDesign. On screen, peer text shown on its
own uses `Text(untrusted:)`, compared identifiers (safety numbers, fingerprints,
device ids, principals) use `KitIdentifierText`, which the UI copy check
enforces for safety numbers, fingerprints and device ids, and screen fonts come
only from `rfFont` (see [fonts](fonts.md)).
Captures run over English, Chinese, the expanded pseudo-locale `en-XA` and
Arabic (right to left, English fallback copy) in both themes.

RFThemeScope supplies the active RFTheme environment value. Themes are bounded,
validated JSON token files copied from the shared token source; adding another
file and its localized label requires no renderer changes. The per-device Settings
selection applies immediately and survives relaunch. Follow-system respects the
system scheme; Increase Contrast remaps weaker semantic roles to strong token
roles. Contrast tests cover shipped foreground/background and control pairs.

## Native simulator account verification

Native account ceremonies use the app's private Keychain. Generate the Xcode
project and build with signing enabled (the simulator uses ad-hoc signing):

```sh
RAMFLUX_CORE_XCFRAMEWORK=build/RamfluxSDKBinary.xcframework xcodegen generate
RAMFLUX_CORE_XCFRAMEWORK=build/RamfluxSDKBinary.xcframework xcodebuild \
  -project Ramflux.xcodeproj -scheme Ramflux \
  -destination 'generic/platform=iOS Simulator' \
  build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

`App/Ramflux.entitlements` supplies the app identifier and its own Keychain group;
no extension or shared group is granted. Xcode embeds simulator entitlements in
the executable. `CODE_SIGNING_ALLOWED=NO` source builds do not prove Keychain
access. Device signing still requires the caller's normal development team and
provisioning profile.

Node discovery accepts the same HTTP(S) origins as the SDK CLI. Discovery is an
untrusted candidate: the host shows the fingerprint, requires the independently
supplied operator key, and sends `node.confirm` with `pin_source=operator` and that
exact key. HTTP TOFU profiles cannot authorize new accounts. SDK signature/key
verification remains authoritative. No ATS relaxation is needed: this discovery
path uses the SDK's reqwest/Tokio sockets, not URLSession. Native simulator HTTP
discovery is verified with ATS defaults; adding a global arbitrary-load exception
would weaken unrelated Foundation requests without affecting this path.

Native signing is configured on the app target per configuration: simulator builds use ad hoc signing; physical-device Debug uses Apple Development and Release/archive uses Apple Distribution. Set `RAMFLUX_DEVELOPMENT_TEAM=<your Apple team ID>` and provide the corresponding automatic-signing account/profile. Device/archive builds without a team fail explicitly. CI compilation can use `CODE_SIGNING_ALLOWED=NO`; it does not prove device installation or distribution signing.

Node setup accepts HTTP(S), IP addresses and IDNA-normalized ASCII hostnames. Enter the operator key obtained independently before the app reveals the fingerprint review. Confirming the fingerprint forces fresh signed discovery and refuses changes in node id, origin, fingerprint or key. The pinned SDK checks the expected public key again against its pending record before persistence.
