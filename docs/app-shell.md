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
into application records. One visible feature observes the native event subscription;
replacement stops and joins the previous subscription before resetting and reloading
the projection. UIKit owns the message timeline (a `UITableViewController` whose cells host
SwiftUI `MessageBubble`s) and the secure input editors. The composer is the
SwiftUI `KitComposer`, a `TextField` that grows vertically. Message text is system
text (`KitMessageText`): selectable, with detected links, and running in the
direction of its own content, while the bubble side follows sender and own
messages. Recovery output is painted from erasable bytes rather than decoded
into a Swift String; spoken recovery-word accessibility is currently limited.

Message sending uses the high-level conversation intent. An uncertain send retains
its original operation key and text for explicit retry. Device revocation and verified
archive installation require host-drawn single-tap confirmation bound to the selected facts. Confirmation opens with Cancel focused for keyboard and accessibility. Hardware-key events cannot activate Confirm; its accessibility label names the action and target.
Backup imports are copied on a serial file worker with a 256 MiB bound; encrypted
archive sharing accepts regular files within private backup storage only.

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

Local search, phone pairing, stranger reporting and
atomic safety-fingerprint verification are unavailable until their SDK/integration
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
