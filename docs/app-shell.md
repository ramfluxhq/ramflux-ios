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
The iOS CI workflow selects installed Xcode 26.2 on hosted `macos-15`, runs the
host checks and builds/tests the application on an available iPhone simulator.
`AppShellSnapshotTests` captures all six major states in both themes and at large
Dynamic Type, plus the tab presentations. XCTest image attachments are review
artifacts; they are not a reviewed pixel-comparison baseline. Source compilation
alone does not prove those captures executed.

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
the projection. UIKit owns the message timeline, marked-text composer and secure
input editors. Recovery output is painted from erasable bytes rather than decoded
into a Swift String; spoken recovery-word accessibility is currently limited.

Message sending uses the high-level conversation intent. An uncertain send retains
its original operation key and text for explicit retry. Device revocation and verified
archive installation require host-drawn single-tap confirmation bound to the selected facts. Confirmation opens with Cancel focused for keyboard and accessibility. Hardware-key events cannot activate Confirm; its accessibility label names the action and target.
Backup imports are copied on a serial file worker with a 256 MiB bound; encrypted
archive sharing accepts regular files within private backup storage only.

Local search, phone pairing, attachment transfer, stranger reporting and
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

Every package owns an English/Simplified Chinese String Catalog. Handwritten native
controls, errors and accessibility labels use explicit package-bundle lookups.
`export-localizations.py` compiles catalogs into checked portable `.strings`/`.stringsdict`
resources for SwiftPM native CLI compatibility. Catalogs remain the sole source;
CI verifies exported semantics with the pinned Apple catalog compiler.
Peer text and protocol identifiers are data rather than translation keys. Catalog
format entries carry variable labels; dates and numbers use the active locale.
The UI copy check rejects literal presentation labels and incomplete locale keys.
Major-state captures cover both shipped themes in English, Chinese and expanded
pseudo-localized copy. These are render artifacts for design review.

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
