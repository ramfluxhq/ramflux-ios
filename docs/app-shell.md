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
conversation whose id is the agent anchor; this is an assumption not yet verified against a node.
Local search, phone pairing, attachment transfer, replying to a stranger without accepting,
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
