#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
# shellcheck source-path=SCRIPTDIR
# shellcheck source=android-toolchain.sh
source "$script_directory/android-toolchain.sh"

fail() {
  echo "error: $*" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fail "docker is required to configure the Swift Android SDK."
[[ -n "${ANDROID_SWIFT_SDKS_PATH:-}" ]] || fail "ANDROID_SWIFT_SDKS_PATH is not set."
[[ -n "${ANDROID_NDK_HOME:-}" ]] || fail "ANDROID_NDK_HOME is not set."
[[ -d "$ANDROID_SWIFT_SDKS_PATH" ]] || fail "ANDROID_SWIFT_SDKS_PATH is not a directory: $ANDROID_SWIFT_SDKS_PATH"
[[ -d "$ANDROID_NDK_HOME" ]] || fail "ANDROID_NDK_HOME is not a directory: $ANDROID_NDK_HOME"
ensure_android_swift_host_image || fail "Unable to pull the Swift Android host image: $ANDROID_SWIFT_HOST_IMAGE"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "$ANDROID_SWIFT_SDKS_PATH:/swift-sdks" \
  --volume "$ANDROID_NDK_HOME:/android-ndk:ro" \
  --env ANDROID_NDK_HOME=/android-ndk \
  --entrypoint bash \
  "$ANDROID_SWIFT_HOST_IMAGE" \
  -lc "cd \"/swift-sdks/${ANDROID_SWIFT_SDK_ID}.artifactbundle/swift-android\" && ./scripts/setup-android-sdk.sh"
