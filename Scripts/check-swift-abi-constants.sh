#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
header="$repository_root/Sources/CTestDoublesTrampoline/include/TestDoublesTrampoline.h"

compile_swift_63_modify_probe() {
  xcrun swiftc "$@" - <<'SWIFT'
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
}

compile_swift_63_read_probe() {
  xcrun swiftc "$@" - <<'SWIFT'
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
}

compile_swift_64_yielding_borrow_probe() {
  local developer_directory="$1"
  shift
  DEVELOPER_DIR="$developer_directory" xcrun swiftc "$@" - <<'SWIFT'
public protocol TestDoublesYieldingBorrowProbe {
  var value: Int { yielding borrow }
}

public struct TestDoublesYieldingBorrowConformer: TestDoublesYieldingBorrowProbe {
  private var storage: Int

  public init(storage: Int) {
    self.storage = storage
  }

  public var value: Int {
    yielding borrow { yield storage }
  }
}
SWIFT
}

swift_version="$(xcrun swiftc --version 2>&1)"
if [[ "$swift_version" != *"Apple Swift version 6.3"* ]]; then
  echo "The required accessor ABI baseline must run with Apple Swift 6.3." >&2
  printf '%s\n' "$swift_version" >&2
  exit 1
fi

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
  echo "TD_READ_CONTEXT_SIZE must remain the runtime's 16-byte read context." >&2
  echo "Header: ${read_context_size:-missing}" >&2
  exit 1
fi

modify_sil="$({
  compile_swift_63_modify_probe \
    -emit-silgen \
    -parse-as-library \
    -module-name TestDoublesAccessorABIProbe \
    -o -
})"

modify_convention_count="$({
  printf '%s\n' "$modify_sil" |
    awk '
      /^\/\/ TestDoublesModifyDiscriminatorProbe.value.modify$/ {
        pending = 1
        next
      }
      pending && /^sil / {
        if ($0 ~ /\$@yield_once @convention\(method\)/) count += 1
        pending = 0
      }
      END { print count + 0 }
    '
})"

if [[ "$modify_convention_count" != "1" ]]; then
  echo "Swift 6.3 _modify coroutine convention changed." >&2
  echo "yield_once modify accessors: $modify_convention_count" >&2
  exit 1
fi

assembly="$({
  compile_swift_63_modify_probe \
    -emit-assembly \
    -parse-as-library \
    -module-name TestDoublesAccessorABIProbe \
    -target arm64e-apple-macosx13.0 \
    -o -
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

read_assembly="$({
  compile_swift_63_read_probe \
    -emit-assembly \
    -parse-as-library \
    -enable-experimental-feature CoroutineAccessors \
    -module-name TestDoublesAccessorABIProbe \
    -target arm64e-apple-macosx13.0 \
    -o -
})"

read_sil="$({
  compile_swift_63_read_probe \
    -emit-silgen \
    -parse-as-library \
    -enable-experimental-feature CoroutineAccessors \
    -module-name TestDoublesAccessorABIProbe \
    -o -
})"

read_witness_count="$({
  printf '%s\n' "$read_sil" |
    awk '
      /sil_witness_table .*TestDoublesReadDescriptorConformer: TestDoublesReadDescriptorProbe/ {
        inWitnessTable = 1
        next
      }
      inWitnessTable && /^}/ { inWitnessTable = 0 }
      inWitnessTable && /method #TestDoublesReadDescriptorProbe.value!read2:/ { count += 1 }
      END { print count + 0 }
    '
})"

read_convention_count="$({
  printf '%s\n' "$read_sil" |
    awk '
      /^\/\/ protocol witness for TestDoublesReadDescriptorProbe.value.read2 in conformance/ {
        pending = 1
        next
      }
      pending && /^sil / {
        if ($0 ~ /\$@yield_once_2 @convention\(witness_method:/) count += 1
        pending = 0
      }
      END { print count + 0 }
    '
})"

if [[ "$read_witness_count" != "1" || "$read_convention_count" != "1" ]]; then
  echo "Swift 6.3 read witness contract changed." >&2
  echo "read2 witness-table entries: $read_witness_count" >&2
  echo "yield_once_2 read witnesses: $read_convention_count" >&2
  exit 1
fi

read_descriptor_frame_size="$({
  printf '%s\n' "$read_assembly" |
    awk '
      /TWTwc:$/ {
        getline
        if ($1 != ".long") next
        getline
        if ($1 != ".long") next
        frameSize = $2
        getline
        if ($1 != ".quad") next
        print frameSize
      }
    ' |
    sort -u
})"

if [[ "$read_descriptor_frame_size" != "32" ]]; then
  echo "Swift compiler yield_once_2 descriptor layout changed." >&2
  echo "Expected relative entry, 32-byte compiler caller frame, and malloc type ID." >&2
  echo "Compiler caller frame: ${read_descriptor_frame_size:-missing}" >&2
  exit 1
fi

read_requirement_flags="$({
  printf '%s\n' "$read_assembly" |
    awk '
      /ReadDescriptorProbeMp:$/ { inDescriptor = 1; next }
      inDescriptor && $1 == ".long" {
        longCount += 1
        if (longCount == 5 && $2 != "1") exit
        if (longCount == 7) {
          value = $2
          sub(/;.*/, "", value)
          print value
          exit
        }
      }
    '
})"

if [[ -z "$read_requirement_flags" ]] || (( (read_requirement_flags & 0xffff) != 0x35 )); then
  echo "Swift 6.3 read requirement flags changed." >&2
  echo "Expected low flags: 0x0035" >&2
  echo "Compiler flags word: ${read_requirement_flags:-missing}" >&2
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

echo "Swift 6.3 compiler selected for the required accessor ABI baseline."
echo "Swift 6.3 _modify convention matches: yield_once"
echo "Swift arm64e modify-resume discriminator matches header: $derived"
echo "Swift 6.3 read witness contract matches: one read2 yield_once_2 witness"
echo "Swift 6.3 read requirement low flags match: 0x0035"
echo "Swift 6.3 yield_once_2 descriptor shape and caller frame match: 32 bytes"
echo "Swift 6.3 compiler emitted one Int read-resume discriminator: $read_resume_discriminator"
echo "Runtime read context size matches header contract: $read_context_size bytes"

if [[ -z "${SWIFT_6_4_DEVELOPER_DIR:-}" ]]; then
  echo "Swift 6.4 yielding-borrow compatibility probe skipped; set SWIFT_6_4_DEVELOPER_DIR to enable it."
  exit 0
fi

swift_64_version="$(
  DEVELOPER_DIR="$SWIFT_6_4_DEVELOPER_DIR" xcrun swiftc --version 2>&1
)"
if [[ "$swift_64_version" != *"Apple Swift version 6.4"* ]]; then
  echo "The optional yielding-borrow ABI probe requires Apple Swift 6.4." >&2
  printf '%s\n' "$swift_64_version" >&2
  exit 1
fi

swift_64_modify_sil="$({
  DEVELOPER_DIR="$SWIFT_6_4_DEVELOPER_DIR" \
    compile_swift_63_modify_probe \
      -emit-silgen \
      -parse-as-library \
      -module-name TestDoublesAccessorABIProbe \
      -o -
})"

swift_64_modify_convention_count="$({
  printf '%s\n' "$swift_64_modify_sil" |
    awk '
      /^\/\/ TestDoublesModifyDiscriminatorProbe.value.modify$/ {
        pending = 1
        next
      }
      pending && /^sil / {
        if ($0 ~ /\$@yield_once @convention\(method\)/) count += 1
        pending = 0
      }
      END { print count + 0 }
    '
})"

swift_64_modify_assembly="$({
  DEVELOPER_DIR="$SWIFT_6_4_DEVELOPER_DIR" \
    compile_swift_63_modify_probe \
      -emit-assembly \
      -parse-as-library \
      -module-name TestDoublesAccessorABIProbe \
      -target arm64e-apple-macosx13.0 \
      -o -
})"

swift_64_modify_discriminator="$({
  printf '%s\n' "$swift_64_modify_assembly" |
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

if [[ "$swift_64_modify_convention_count" != "1" ]]; then
  echo "Swift 6.4 _modify coroutine convention changed." >&2
  echo "yield_once modify accessors: $swift_64_modify_convention_count" >&2
  exit 1
fi

if [[ "$swift_64_modify_discriminator" != "$expected" ]]; then
  echo "Swift 6.4 arm64e modify-resume discriminator changed." >&2
  echo "Header: $expected" >&2
  echo "Compiler: ${swift_64_modify_discriminator:-missing}" >&2
  exit 1
fi

swift_64_sil="$({
  compile_swift_64_yielding_borrow_probe \
    "$SWIFT_6_4_DEVELOPER_DIR" \
    -emit-silgen \
    -parse-as-library \
    -enable-experimental-feature CoroutineAccessors \
    -module-name TestDoublesAccessorABIProbe \
    -o -
})"

swift_64_legacy_witnesses="$({
  printf '%s\n' "$swift_64_sil" |
    awk '
      /sil_witness_table .*TestDoublesYieldingBorrowConformer: TestDoublesYieldingBorrowProbe/ {
        inWitnessTable = 1
        next
      }
      inWitnessTable && /^}/ { inWitnessTable = 0 }
      inWitnessTable && /method #TestDoublesYieldingBorrowProbe.value!read:/ { count += 1 }
      END { print count + 0 }
    '
})"

swift_64_yielding_witnesses="$({
  printf '%s\n' "$swift_64_sil" |
    awk '
      /sil_witness_table .*TestDoublesYieldingBorrowConformer: TestDoublesYieldingBorrowProbe/ {
        inWitnessTable = 1
        next
      }
      inWitnessTable && /^}/ { inWitnessTable = 0 }
      inWitnessTable && /method #TestDoublesYieldingBorrowProbe.value!yielding_borrow:/ { count += 1 }
      END { print count + 0 }
    '
})"

if [[ "$swift_64_legacy_witnesses" != "1" || "$swift_64_yielding_witnesses" != "1" ]]; then
  echo "Swift 6.4 yielding-borrow witness-table entries changed." >&2
  echo "Legacy read entries: $swift_64_legacy_witnesses" >&2
  echo "Yielding-borrow entries: $swift_64_yielding_witnesses" >&2
  exit 1
fi

echo "Swift 6.4 _modify convention and arm64e resume discriminator match Swift 6.3."
echo "Swift 6.4 yielding borrow has one legacy read and one yielding-borrow witness."
