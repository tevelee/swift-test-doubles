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

command -v adb >/dev/null 2>&1 || fail "adb is required to deploy AndroidRuntimeDemo."

readonly android_serial="${ANDROID_SERIAL:-}"
[[ -n "$android_serial" ]] || fail "ANDROID_SERIAL is not set. Start an Android emulator or select a device first."

readonly build_directory="${ANDROID_RUNTIME_BUILD_PATH:-$repository_root/.build/android-runtime}"
readonly target_triple="x86_64-unknown-linux-android${ANDROID_API_LEVEL}"
readonly remote_directory="/data/local/tmp/test-doubles-runtime-demo"
readonly configurations=(debug release)

adb -s "$android_serial" wait-for-device
adb -s "$android_serial" shell mkdir -p "$remote_directory"

for configuration in "${configurations[@]}"; do
  local_binary="$build_directory/$target_triple/$configuration/AndroidRuntimeDemo"
  [[ -f "$local_binary" ]] || fail "AndroidRuntimeDemo is missing: $local_binary"

  remote_binary="$remote_directory/AndroidRuntimeDemo-$configuration"
  echo "Deploying AndroidRuntimeDemo ($configuration) to $android_serial"
  adb -s "$android_serial" push "$local_binary" "$remote_binary" >/dev/null
  adb -s "$android_serial" shell chmod 755 "$remote_binary"
  adb -s "$android_serial" shell "$remote_binary"
done

adb -s "$android_serial" shell rm -rf "$remote_directory"
