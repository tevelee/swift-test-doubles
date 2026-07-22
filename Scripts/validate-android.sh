#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
# shellcheck source-path=SCRIPTDIR
# shellcheck source=android-toolchain.sh
source "$script_directory/android-toolchain.sh"
repository_root="$(cd "$script_directory/.." && pwd)"
readonly repository_root
swift_sdk_path_arguments=()
swift_sdk_install_path_hint=""
if [[ -n "${ANDROID_SWIFT_SDKS_PATH:-}" ]]; then
  swift_sdk_path_arguments=(--swift-sdks-path "$ANDROID_SWIFT_SDKS_PATH")
  swift_sdk_install_path_hint=" --swift-sdks-path '$ANDROID_SWIFT_SDKS_PATH'"
fi
readonly swift_sdk_path_arguments
readonly swift_sdk_install_path_hint

fail() {
  echo "error: $*" >&2
  exit 1
}

command -v swift >/dev/null 2>&1 || fail "Swift $ANDROID_SWIFT_VERSION is required but 'swift' is not on PATH."

swift_version_output="$(swift --version 2>&1)"
if [[ "$swift_version_output" != *"Swift version $ANDROID_SWIFT_VERSION"* ]]; then
  fail "the official Android SDK requires a matching Swift $ANDROID_SWIFT_VERSION host toolchain; found: ${swift_version_output//$'\n'/ }"
fi

installed_sdks="$(swift sdk list "${swift_sdk_path_arguments[@]}" 2>&1)" \
  || fail "unable to list installed Swift SDKs: $installed_sdks"
prerequisites_available=true
if ! grep -Fqx "$ANDROID_SWIFT_SDK_ID" <<<"$installed_sdks"; then
  cat >&2 <<EOF
error: Swift SDK '$ANDROID_SWIFT_SDK_ID' is not installed.
Install it with the official checksum-verified command, then configure it with Android NDK r27d or later:
  swift sdk install '$ANDROID_SWIFT_SDK_URL' --checksum '$ANDROID_SWIFT_SDK_CHECKSUM'$swift_sdk_install_path_hint
EOF
  prerequisites_available=false
fi

readonly android_ndk_directory="${ANDROID_NDK_HOME:-}"
if [[ -z "$android_ndk_directory" ]]; then
  echo "error: ANDROID_NDK_HOME is not set. Point it at Android NDK r27d or later, after configuring the installed Swift Android SDK with its setup-android-sdk.sh script." >&2
  prerequisites_available=false
elif [[ ! -d "$android_ndk_directory" ]]; then
  fail "ANDROID_NDK_HOME is not a directory: $android_ndk_directory"
fi

readonly ndk_properties="$android_ndk_directory/source.properties"
if [[ -n "$android_ndk_directory" && ! -f "$ndk_properties" ]]; then
  fail "cannot verify the Android NDK revision because '$ndk_properties' is missing. Android NDK r27d or later is required."
fi

ndk_revision=""
if [[ -n "$android_ndk_directory" ]]; then
  ndk_revision="$(sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*//p' "$ndk_properties" | head -n 1)"
  if [[ -z "$ndk_revision" ]]; then
    fail "cannot read Pkg.Revision from '$ndk_properties'. Android NDK r27d or later is required."
  fi

  ndk_major="${ndk_revision%%.*}"
  ndk_remainder="${ndk_revision#*.}"
  ndk_minor="${ndk_remainder%%.*}"
  if [[ ! "$ndk_major" =~ ^[0-9]+$ || ! "$ndk_minor" =~ ^[0-9]+$ ]]; then
    fail "cannot compare Android NDK revision '$ndk_revision'; expected a numeric Pkg.Revision."
  fi
  if ((
    ndk_major < ANDROID_NDK_MINIMUM_MAJOR
    || (ndk_major == ANDROID_NDK_MINIMUM_MAJOR && ndk_minor < ANDROID_NDK_MINIMUM_MINOR)
  )); then
    fail "Android NDK $ANDROID_NDK_RELEASE or later is required; found Pkg.Revision $ndk_revision."
  fi
fi

if [[ "$prerequisites_available" != true ]]; then
  exit 1
fi

echo "Swift host toolchain: $ANDROID_SWIFT_VERSION"
echo "Swift Android SDK: $ANDROID_SWIFT_SDK_ID"
echo "Android NDK: $ndk_revision"
echo "Dependency prerequisite: Echo 0.0.5 or newer with Android ELF metadata support."

readonly target_triples=(
  "x86_64-unknown-linux-android${ANDROID_API_LEVEL}"
  "aarch64-unknown-linux-android${ANDROID_API_LEVEL}"
)
readonly configurations=(debug release)

for target_triple in "${target_triples[@]}"; do
  for configuration in "${configurations[@]}"; do
    echo "Building package for $target_triple ($configuration)"
    swift build \
      --package-path "$repository_root" \
      --scratch-path "$repository_root/.build/android/$target_triple" \
      --configuration "$configuration" \
      --swift-sdk "$target_triple" \
      "${swift_sdk_path_arguments[@]}" \
      --static-swift-stdlib
  done
done
