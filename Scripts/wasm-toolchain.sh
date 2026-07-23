#!/usr/bin/env bash

# This file is sourced by CI and validation scripts.
# shellcheck disable=SC2034

readonly WASM_SWIFT_VERSION="6.3.1"
readonly WASM_SWIFT_SDK_ID="swift-6.3.1-RELEASE_wasm"
readonly WASM_SWIFT_SDK_URL="https://download.swift.org/swift-6.3.1-release/wasm-sdk/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE_wasm.artifactbundle.tar.gz"
readonly WASM_SWIFT_SDK_CHECKSUM="bd47baa20771f366d8beed7970afaa30742b2210097afd15f85427226d8f4cf2"
readonly WASM_SWIFT_SDK_TARGET_TRIPLE="wasm32-unknown-wasip1"

# The wasm SDK bundle is pinned to this exact host toolchain version. A
# separate swift.org toolchain install is required regardless of which Xcode
# is selected: Xcode's own bundled clang has no WebAssembly LLVM target
# compiled in at all (confirmed locally; only Xcode 27 betas add it), so
# there is no way to satisfy this from Xcode alone even when its bundled
# Swift version happens to match.
readonly WASM_HOST_TOOLCHAIN_URL="https://download.swift.org/swift-6.3.1-release/xcode/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE-osx.pkg"
readonly WASM_HOST_TOOLCHAIN_CHECKSUM="6e31d6696e7a2819f3effa7ccbbca721a45c9e300ae5f5200cb4da8ced2f82c8"
readonly WASM_HOST_TOOLCHAIN_DIR="/Library/Developer/Toolchains/swift-${WASM_SWIFT_VERSION}-RELEASE.xctoolchain"
readonly WASM_HOST_TOOLCHAIN_BIN="$WASM_HOST_TOOLCHAIN_DIR/usr/bin"
