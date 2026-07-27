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

command -v docker >/dev/null 2>&1 || fail "docker is required to build AndroidRuntimeDemo with Swift $ANDROID_SWIFT_VERSION."
[[ -n "${ANDROID_SWIFT_SDKS_PATH:-}" ]] || fail "ANDROID_SWIFT_SDKS_PATH is not set."
[[ -n "${ANDROID_NDK_HOME:-}" ]] || fail "ANDROID_NDK_HOME is not set."
[[ -d "$ANDROID_SWIFT_SDKS_PATH" ]] || fail "ANDROID_SWIFT_SDKS_PATH is not a directory: $ANDROID_SWIFT_SDKS_PATH"
[[ -d "$ANDROID_NDK_HOME" ]] || fail "ANDROID_NDK_HOME is not a directory: $ANDROID_NDK_HOME"

readonly build_directory="${ANDROID_RUNTIME_BUILD_PATH:-$repository_root/.build/android-runtime}"
mkdir -p "$build_directory"

echo "Building AndroidRuntimeDemo in $ANDROID_SWIFT_HOST_IMAGE"
docker run --rm \
  --volume "$repository_root:$repository_root" \
  --volume "$build_directory:/build" \
  --volume "$ANDROID_SWIFT_SDKS_PATH:/swift-sdks" \
  --volume "$ANDROID_NDK_HOME:/android-ndk:ro" \
  --workdir "$repository_root" \
  --env HOME=/tmp/test-doubles-swift-home \
  --env ANDROID_NDK_HOME=/android-ndk \
  --env ANDROID_RUNTIME_BUILD_PATH=/build \
  --env ANDROID_SWIFT_SDKS_PATH=/swift-sdks \
  --entrypoint bash \
  "$ANDROID_SWIFT_HOST_IMAGE" \
  "$script_directory/build-android-runtime-demo.sh"

ANDROID_RUNTIME_BUILD_PATH="$build_directory" \
  "$script_directory/run-android-runtime-demo.sh"
