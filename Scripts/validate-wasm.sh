#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
# shellcheck source-path=SCRIPTDIR
# shellcheck source=wasm-toolchain.sh
source "$script_directory/wasm-toolchain.sh"
repository_root="$(cd "$script_directory/.." && pwd)"
readonly repository_root

fail() {
  echo "error: $*" >&2
  exit 1
}

command -v swift >/dev/null 2>&1 || fail "Swift $WASM_SWIFT_VERSION is required but 'swift' is not on PATH."

swift_version_output="$(swift --version 2>&1)"
if [[ "$swift_version_output" != *"Swift version $WASM_SWIFT_VERSION"* ]]; then
  fail "the official wasm SDK requires a matching Swift $WASM_SWIFT_VERSION host toolchain; found: ${swift_version_output//$'\n'/ }"
fi

installed_sdks="$(swift sdk list 2>&1)" \
  || fail "unable to list installed Swift SDKs: $installed_sdks"
if ! grep -Fqx "$WASM_SWIFT_SDK_ID" <<<"$installed_sdks"; then
  cat >&2 <<EOF
error: Swift SDK '$WASM_SWIFT_SDK_ID' is not installed.
Install it with the official checksum-verified command:
  swift sdk install '$WASM_SWIFT_SDK_URL' --checksum '$WASM_SWIFT_SDK_CHECKSUM'
EOF
  exit 1
fi

command -v wasmtime >/dev/null 2>&1 || fail "wasmtime is required to run WasmDemo but is not on PATH."

echo "Swift host toolchain: $WASM_SWIFT_VERSION"
echo "Swift WASI SDK: $WASM_SWIFT_SDK_ID"
echo "wasmtime: $(wasmtime --version)"

# The runtime-fabricated Stub/Spy path needs neither: ManualStub is the
# supported way to use TestDoubles on wasm32-wasi, the same as on physical
# Apple devices. `--build-tests` compiles the whole suite, including the
# parts that intentionally aren't wasm-safe since they exercise the
# arm64/x86_64 trampoline directly (see AsyncStackSpyForwardingTests.swift
# and ConcurrencyTests.swift) — those stay out of the wasm32 build via their
# own `#if arch(...)`/`#if canImport(Dispatch)` guards, not by being skipped
# here. Running is filtered to TestDoublesWasmTests, the suite written
# specifically for this platform.
for configuration in debug release; do
  echo "Building TestDoubles for $WASM_SWIFT_SDK_TARGET_TRIPLE ($configuration)"
  swift build \
    --package-path "$repository_root" \
    --scratch-path "$repository_root/.build/wasm/$configuration" \
    --configuration "$configuration" \
    --swift-sdk "$WASM_SWIFT_SDK_ID" \
    --target TestDoubles
done

echo "Building and running WasmDemo for $WASM_SWIFT_SDK_TARGET_TRIPLE (debug)"
swift build \
  --package-path "$repository_root" \
  --scratch-path "$repository_root/.build/wasm/debug" \
  --configuration debug \
  --swift-sdk "$WASM_SWIFT_SDK_ID" \
  --product WasmDemo

wasmtime run \
  "$repository_root/.build/wasm/debug/wasm32-unknown-wasip1/debug/WasmDemo.wasm"

echo "Building and running TestDoublesWasmTests for $WASM_SWIFT_SDK_TARGET_TRIPLE"
OMIT_DYNAMIC_TEST_SUPPORT=1 swift build \
  --package-path "$repository_root" \
  --scratch-path "$repository_root/.build/wasm/test" \
  --configuration debug \
  --swift-sdk "$WASM_SWIFT_SDK_ID" \
  --build-tests

wasmtime run --dir "$repository_root" \
  "$repository_root/.build/wasm/test/wasm32-unknown-wasip1/debug/swift-test-doublesPackageTests.xctest" \
  -- --testing-library swift-testing --filter WasmPlatformTests
