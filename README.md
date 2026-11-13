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
