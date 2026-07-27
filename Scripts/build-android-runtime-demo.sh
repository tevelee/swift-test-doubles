#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
# shellcheck source-path=SCRIPTDIR
# shellcheck source=android-toolchain.sh
source "$script_directory/android-toolchain.sh"
repository_root="$(cd "$script_directory/.." && pwd)"
readonly repository_root

fail() {
  echo "error: $*" >&2
  exit 1
}

command -v swift >/dev/null 2>&1 || fail "Swift $ANDROID_SWIFT_VERSION is required but 'swift' is not on PATH."

swift_version_output="$(swift --version 2>&1)"
if [[ "$swift_version_output" != *"Swift version $ANDROID_SWIFT_VERSION"* ]]; then
  fail "the official Android SDK requires a matching Swift $ANDROID_SWIFT_VERSION host toolchain; found: ${swift_version_output//$'\n'/ }"
fi

swift_sdk_path_arguments=()
if [[ -n "${ANDROID_SWIFT_SDKS_PATH:-}" ]]; then
  swift_sdk_path_arguments=(--swift-sdks-path "$ANDROID_SWIFT_SDKS_PATH")
fi
readonly swift_sdk_path_arguments

installed_sdks="$(swift sdk list "${swift_sdk_path_arguments[@]}" 2>&1)" \
  || fail "unable to list installed Swift SDKs: $installed_sdks"
if ! grep -Fqx "$ANDROID_SWIFT_SDK_ID" <<<"$installed_sdks"; then
  cat >&2 <<EOF
error: Swift SDK '$ANDROID_SWIFT_SDK_ID' is not installed.
Install it with the official checksum-verified command, then configure it with Android NDK r27d or later:
  swift sdk install '$ANDROID_SWIFT_SDK_URL' --checksum '$ANDROID_SWIFT_SDK_CHECKSUM'
EOF
  exit 1
fi

readonly android_ndk_directory="${ANDROID_NDK_HOME:-}"
[[ -n "$android_ndk_directory" ]] || fail "ANDROID_NDK_HOME is not set."
[[ -d "$android_ndk_directory" ]] || fail "ANDROID_NDK_HOME is not a directory: $android_ndk_directory"

readonly build_directory="${ANDROID_RUNTIME_BUILD_PATH:-$repository_root/.build/android-runtime}"
readonly target_triple="x86_64-unknown-linux-android${ANDROID_API_LEVEL}"
readonly configurations=(debug release)

echo "Swift host toolchain: $ANDROID_SWIFT_VERSION"
echo "Swift Android SDK: $ANDROID_SWIFT_SDK_ID"
echo "Android runtime target: $target_triple"

for configuration in "${configurations[@]}"; do
  echo "Building AndroidRuntimeDemo for $target_triple ($configuration)"
  swift build \
    --package-path "$repository_root" \
    --scratch-path "$build_directory" \
    --configuration "$configuration" \
    --swift-sdk "$target_triple" \
    "${swift_sdk_path_arguments[@]}" \
    --product AndroidRuntimeDemo \
    --static-swift-stdlib
done
