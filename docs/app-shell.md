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
  extensions and layout live outside `Generated`. Font names come from the design
  tokens; dedicated font assets are not bundled yet, so system fallback can apply.

## Build modes

Without `RAMFLUX_CORE_XCFRAMEWORK`, the application factory returns a typed
unavailable Repository. The bridge links a weak, refusing C provider, which never
opens storage, transports messages or returns accounts. ABI tests override it
with their strong test-only fixture definitions. `CABIFixture` is not an app
dependency. The bridge product uses automatic linkage so app/test consumers share
its framework when Xcode requires it.

With `RAMFLUX_CORE_XCFRAMEWORK` set to the matching artifact's absolute path,
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
`FeatureSettings` each expose Screen, State, Action, Event, ViewModel and Coordinator
types. Screens render State and emit Action; ViewModels own cancellable asynchronous
work. AppData owns repositories shared over one RamfluxClient and maps SDK responses
into application records. One visible feature observes the native event subscription;
replacement stops and joins the previous subscription before resetting and reloading
the projection. UIKit owns the message timeline, marked-text composer and secure
input editors. Recovery output is painted from erasable bytes rather than decoded
into a Swift String; spoken recovery-word accessibility is currently limited.

Message sending uses the high-level conversation intent. An uncertain send retains
its original operation key and text for explicit retry. Device revocation and verified
archive installation require native 1.2-second holds bound to the selected facts.
Backup imports are copied on a serial file worker with a 256 MiB bound; encrypted
archive sharing accepts regular files within private backup storage only.

Local search, phone pairing, attachment transfer, revisions, stranger reporting and
atomic safety-fingerprint verification are unavailable until their SDK/integration
contracts exist. Open-account reachability is not inferred from automatic contact
request acceptance. No synthetic identity, routing, delivery or verification state
is used as a substitute. Previews use isolated illustrative fixtures; production
repositories do not.

Each feature package supports `swift build --package-path Packages/FeatureName` and
`swift test --package-path Packages/FeatureName`. CI also captures major feature
states in both themes. Generated design files are hash-owned and read-only;
platform compatibility extensions remain in RFDesign/Sources.
