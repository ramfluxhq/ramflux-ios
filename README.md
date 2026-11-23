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
product checkout. Card sessions (`card.session.*`) need the SDK's `card-runtime`
feature as well, so the card renderer work must build the XCFramework with
`--features c-abi,card-runtime`; without it those methods are listed but have no runtime. `docs/sdk-contract.json` records the source commit and header
hash. Regenerate only from a clean checkout at the recorded full commit:

```sh
python3 scripts/sync-sdk-contract.py /path/to/product-checkout --commit <full-commit> --check
```

Use `--update-pin` explicitly when adopting a newly reviewed SDK checkpoint.
The generator verifies SDK-owned method policy, expected count, Swift-name
uniqueness, and all generated outputs. CI runs that check and the generator's
negative tests. Fixture tests and binary artifact builds are separate
package configurations; fixture symbols must never enter an application.

## Real run against a test node

`scripts/realrun.sh` runs the beta flows on a simulator with the native SDK
against a test node and two peer accounts on it (alice and bob), driven through
the `rf` CLI. It is opt-in: the suite lives in the `RamfluxRealRunUITests`
target and the `RamfluxRealRun` scheme, which the `Ramflux` scheme and CI never
run.

Inputs are environment variables; put them in `scripts/realrun.local.env` (not
tracked) so a run stays one command. `scripts/realrun.local.env.example` lists
them with placeholders:

| Variable | Required | Meaning |
| --- | --- | --- |
| `RAMFLUX_REALRUN_NODE_FACTS` | yes | node facts JSON: `discovery_origin`, `node_id`, `node_public_key`, `node_key_fingerprint` |
| `RAMFLUX_REALRUN_PEERS` | yes | peers JSON: a `peers` list with `name`, `account_id`, `display_name`, `principal_id`, `principal_commitment`, `device_id`, `daemon_socket` for alice and bob |
| `RAMFLUX_REALRUN_RF` | yes | the `rf` CLI that talks to the peer daemons |
| `RAMFLUX_REALRUN_DM_HELPER` | yes | a command printing the direct conversation id for `COMMAND dm-conversation ROOT_A ROOT_B` |
| `RAMFLUX_REALRUN_NODE_CHECK` | no | a command that fails when the node is not healthy |
| `RAMFLUX_REALRUN_PEERS_CTL` | no | a command with `status` and `start` for the peer daemons |
| `RAMFLUX_REALRUN_CLOCK_CONTAINER` | no | a node container whose clock is compared with this machine's (branch proofs expire after 300 s) |
| `RAMFLUX_REALRUN_SIMULATOR` | no | simulator name (default `rf-realrun`, created when missing) |
| `RAMFLUX_MOBILE_ENV` | no | a shell file with toolchain paths, sourced before building |

A missing required input stops the script with a message naming it.

```sh
scripts/realrun.sh                       # all flows in one command, output in build/realrun/<UTC time>/
scripts/realrun.sh --only test04_directChatWithAlice --out /tmp/rr

scripts/realrun.sh prepare --out /tmp/rr # or in short phases
scripts/realrun.sh run --only test01_onboardingCustomNodeAccountLockUnlock,test02_contactsAddAliceAndVerify
scripts/realrun.sh run --only RealRunLifecycleTests
scripts/realrun.sh rebuild               # after a code change; the app keeps its data
scripts/realrun.sh finish                # flow table; stops the control server
```

Requirements: `build/RamfluxSDKBinary.xcframework`, XcodeGen, and the node and
its peer daemons running. The script checks them, builds the app and the suite,
resets the app's data and the simulator Keychain, starts a loopback
peer-control server (`scripts/realrun/peer_control.py`) that runs allow-listed
`rf` commands for the test at the right moments, runs the suite, and writes
`flow-table.md` (PASS, FAIL, BLOCKED or NOT RUN per flow), screenshots and logs,
including the app's debug event trace for every flow that does not pass. The
six-digit code is generated in the test process; the recovery words are read
there through a debug-only accessibility value of the phrase display (launch
argument `-RFRealRunPhraseAccess`, never compiled into release builds) and are
never logged or captured. Between phases the throwaway account code, the
archive passphrase and public ids are kept in the control server's memory only.
Typed text is redacted from the saved test log and the result bundle is
deleted.

The flows cover onboarding with lock, cold start and the known-account unlock;
contacts with alice and bob; the direct chat (send, live receive, reply, edit,
erase for everyone, select text, receipts as alice sees them); media with the
phone's contact card handed to alice; groups with alice and bob and a group
image; background and return (the open chat and its draft come back after the
unlock); the account-code change; backup and, last, restore of that backup on a
fresh install (the peer-control server moves the encrypted archive to the
simulator's "On My iPhone" storage and reinstalls the app; the archive
passphrase stays in the test process and the control server's memory). `--only` takes a test of
`RealRunFlowTests`, a class name, or `Class/test`, comma separated.
The script opens the simulator window (DeviceHub on Xcode 27) before booting the
simulator and leaves both open after the run.
