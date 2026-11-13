#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Span Brain
set -euo pipefail
if [[ $# != 1 ]]; then echo 'Usage: build-xcframework.sh <product-checkout>' >&2; exit 2; fi
sdk_root=$(cd "$1" && pwd)
package_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$HOME/work/.targets/rf-ios}
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-4}
export IPHONEOS_DEPLOYMENT_TARGET=18.0
if [[ -n "$(git -C "$sdk_root" status --porcelain)" ]]; then
    echo 'SDK checkout must be committed before packaging matching headers and libraries' >&2; exit 1
fi
sdk_commit=$(git -C "$sdk_root" rev-parse HEAD)
python3 "$package_root/scripts/sync-sdk-contract.py" "$sdk_root" --commit "$sdk_commit" --check
output="$package_root/build"
mkdir -p "$output"
# Serial Cargo only. Never mutate the SDK checkout or enable fixture features.
for target in aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin; do
    (cd "$sdk_root" && cargo rustc --locked -p ramflux-sdk --lib --features c-abi \
        --target "$target" --release --crate-type staticlib)
done
cmp "$CARGO_TARGET_DIR/include/ramflux_sdk.h" "$sdk_root/crates/ramflux-sdk/include/ramflux_sdk.h" || {
    echo 'Generated header differs from the committed SDK contract' >&2; exit 1
}
headers="$output/headers"
mkdir -p "$headers"
cp "$package_root/Sources/CRamflux/include/ramflux_sdk.h" "$headers/ramflux_sdk.h"
cat > "$headers/module.modulemap" <<'MODULE'
module RamfluxSDKBinary {
    header "ramflux_sdk.h"
    export *
}
MODULE
# Refuse to replace an existing artifact; the caller chooses when to archive old output.
if [[ -e "$output/RamfluxSDKBinary.xcframework" ]]; then
    echo 'Archive the existing build/RamfluxSDKBinary.xcframework before rebuilding' >&2; exit 1
fi
xcodebuild -create-xcframework \
    -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libramflux_sdk.a" -headers "$headers" \
    -library "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libramflux_sdk.a" -headers "$headers" \
    -library "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/libramflux_sdk.a" -headers "$headers" \
    -output "$output/RamfluxSDKBinary.xcframework"
echo 'XCFramework assembled: build/RamfluxSDKBinary.xcframework'
