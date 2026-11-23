# Ramflux iOS

Ramflux iOS is the native iPhone and iPad client for Ramflux, built with Swift
and Xcode. It embeds the Ramflux core SDK through its C ABI.

This repository contains only the AGPL client. The Ramflux core SDK and protocol
crates live in `ramfluxhq/ramflux`.

Status: native shell, onboarding, conversations, UIKit chat, contacts/strangers,
groups and settings/devices/backup modules over the C ABI bridge. See
[application structure and build modes](docs/app-shell.md). Missing SDK
capabilities are explicit unavailable states.

## License

AGPL-3.0-or-later with the Ramflux App Store Exception. See `LICENSE`,
`LICENSING.md` and `NOTICE`.

## Swift bridge

`RamfluxCore` contains the headless C ABI v2 bridge and application Proxy protocols.
See [bridge ownership and security](docs/bridge.md).

Compile and run the isolated headless ABI contract tests:

```sh
swift build
swift test
xcodebuild -scheme RamfluxCore -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

The source-only build uses a refusing C provider and returns typed unavailable
account services. Tests override that provider with the test-only `CABIFixture`
target, which is excluded from the library product. These commands
do not prove that the Rust SDK has been linked or exercised.

Build the matching Rust SDK XCFramework from a reviewed product checkout, then
select it explicitly for application builds:

```sh
scripts/build-xcframework.sh /path/to/product-checkout
RAMFLUX_CORE_XCFRAMEWORK=build/RamfluxSDKBinary.xcframework swift build
```

The script builds device, simulator and host static libraries serially, with
`c-abi` only, and copies the matching cbindgen header. It never updates the
product checkout. `docs/sdk-contract.json` records the source commit and header
hash. Regenerate only from a clean checkout at the recorded full commit:

```sh
python3 scripts/sync-sdk-contract.py /path/to/product-checkout --commit <full-commit> --check
```

Use `--update-pin` explicitly when adopting a newly reviewed SDK checkpoint.
The generator verifies SDK-owned method policy, expected count, Swift-name
uniqueness, and all generated outputs. CI runs that check and the generator's
negative tests. Fixture tests and binary artifact builds are separate
package configurations; fixture symbols must never enter an application.

## Real run against a local node

`scripts/realrun.sh` runs the beta flows on a simulator with the native SDK
against the local node and its two `rf` peers (alice and bob). It is opt-in:
the suite lives in the `RamfluxRealRunUITests` target and the `RamfluxRealRun`
scheme, which the `Ramflux` scheme and CI never run.

```sh
source /path/to/mobile-env.sh
scripts/realrun.sh                       # all flows, output in build/realrun/<UTC time>/
scripts/realrun.sh --only test04_directChatWithAlice --out /tmp/rr
```

Requirements: `build/RamfluxSDKBinary.xcframework`, XcodeGen, and the local node
up (`ops/local-node/up.sh`, `peers.sh start`). The script checks the node,
builds the app and the suite, resets the app's data and the simulator Keychain,
starts a loopback peer-control server (`scripts/realrun/peer_control.py`) that
runs allow-listed `rf` commands for the test at the right moments, runs the
suite, and writes `flow-table.md` (PASS, FAIL, BLOCKED or NOT RUN per flow),
screenshots and logs. The six-digit code and the recovery words are generated
or read inside the test process only; typed text is redacted from the saved
test log and the result bundle is deleted. Unless `--no-clock-sync` is given,
the podman VM clock is set from the Mac's clock before and during the run,
because branch proofs expire after 300 seconds and that VM clock drifts.

The flows cover onboarding with lock, cold start and the known-account unlock;
contacts with alice and bob; the direct chat (send, live receive, reply, edit,
erase for everyone, select text, receipts as alice sees them); media with the
phone's contact card handed to alice; groups with alice and bob; background and
return; the account-code change; backup and, last, restore of that backup on a
fresh install (the peer-control server moves the encrypted archive to the
simulator's "On My iPhone" storage and reinstalls the app; the archive
passphrase stays in the test process). `--only` takes a test of
`RealRunFlowTests`, a class name, or `Class/test`.
The script opens the simulator window (DeviceHub on Xcode 27) before booting the
`rf-realrun` simulator and leaves both open after the run.
