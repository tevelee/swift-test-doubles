#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
header="$repository_root/Sources/CTestDoublesTrampoline/include/TestDoublesTrampoline.h"

expected="$({
  sed -nE \
    's/^#define TD_MODIFY_RESUME_DISCRIMINATOR ([0-9]+)$/\1/p' \
    "$header"
} | sort -u)"

read_context_size="$({
  sed -nE \
    's/^#define TD_READ_CONTEXT_SIZE ([0-9]+)$/\1/p' \
    "$header"
} | sort -u)"

if [[ -z "$expected" || "$expected" == *$'\n'* ]]; then
  echo "Could not read one TD_MODIFY_RESUME_DISCRIMINATOR from $header." >&2
  exit 1
fi

if [[ "$read_context_size" != "16" ]]; then
  echo "TD_READ_CONTEXT_SIZE must remain the 16-byte yield_once_2 caller frame." >&2
  echo "Header: ${read_context_size:-missing}" >&2
  exit 1
fi

assembly="$({
  xcrun swiftc \
    -emit-assembly \
    -parse-as-library \
    -target arm64e-apple-macosx13.0 \
    -o - \
    - <<'SWIFT'
public struct TestDoublesModifyDiscriminatorProbe {
  private var storage: Int

  public init(storage: Int) {
    self.storage = storage
  }

  public var value: Int {
    get { storage }
    _modify { yield &storage }
  }
}
SWIFT
})"

derived="$({
  printf '%s\n' "$assembly" |
    awk '
      /movk[[:space:]]+x17, #[0-9]+, lsl #48/ {
        candidate = $0
        sub(/^.*movk[[:space:]]+x17, #/, "", candidate)
        sub(/,.*/, "", candidate)
        candidateLine = NR
        next
      }
      /pacia[[:space:]]+x16,[[:space:]]*x17/ && candidateLine == NR - 1 {
        print candidate
      }
    ' |
    sort -u
})"

if [[ -z "$derived" || "$derived" == *$'\n'* ]]; then
  echo "Could not derive one arm64e modify-resume discriminator from compiler assembly." >&2
  exit 1
fi

if [[ "$derived" != "$expected" ]]; then
  echo "Swift compiler arm64e modify-resume discriminator changed." >&2
  echo "Header: $expected" >&2
  echo "Compiler: $derived" >&2
  exit 1
fi

echo "Swift arm64e modify-resume discriminator matches: $derived"

read_assembly="$({
  xcrun swiftc \
    -emit-assembly \
    -parse-as-library \
    -enable-experimental-feature CoroutineAccessors \
    -target arm64e-apple-macosx13.0 \
    -o - \
    - <<'SWIFT'
public protocol TestDoublesReadDescriptorProbe {
  var value: Int { read }
}

public struct TestDoublesReadDescriptorConformer: TestDoublesReadDescriptorProbe {
  private var storage: Int

  public init(storage: Int) {
    self.storage = storage
  }

  public var value: Int {
    read { yield storage }
  }
}
SWIFT
})"

read_descriptor_fields="$({
  printf '%s\n' "$read_assembly" |
    awk '
      /TWTwc:$/ {
        getline
        if ($1 != ".long") next
        getline
        if ($1 != ".long") next
        getline
        if ($1 != ".quad") next
        print "relative-frame-malloc"
      }
    ' |
    sort -u
})"

if [[ "$read_descriptor_fields" != "relative-frame-malloc" ]]; then
  echo "Swift compiler yield_once_2 descriptor layout changed." >&2
  echo "Expected a relative entry, caller-frame size, and malloc type ID." >&2
  exit 1
fi

read_resume_discriminator="$({
  printf '%s\n' "$read_assembly" |
    awk '
      /mov[[:space:]]+x17,[[:space:]]*x0/ {
        candidateLine = NR
        next
      }
      /movk[[:space:]]+x17, #[0-9]+, lsl #48/ && candidateLine == NR - 1 {
        candidate = $0
        sub(/^.*movk[[:space:]]+x17, #/, "", candidate)
        sub(/,.*/, "", candidate)
        candidateLine = NR
        next
      }
      /pacia[[:space:]]+x16,[[:space:]]*x17/ && candidateLine == NR - 1 {
        print candidate
      }
    ' |
    sort -u
})"

if [[ -z "$read_resume_discriminator" || "$read_resume_discriminator" == *$'\n'* ]]; then
  echo "Could not derive one arm64e read-resume discriminator from compiler assembly." >&2
  exit 1
fi

echo "Swift compiler emits the expected yield_once_2 descriptor fields."
echo "Swift compiler Int read-resume discriminator: $read_resume_discriminator"
