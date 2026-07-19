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

if [[ -z "$expected" || "$expected" == *$'\n'* ]]; then
  echo "Could not read one TD_MODIFY_RESUME_DISCRIMINATOR from $header." >&2
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
