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

compile_swift_63_modify_descriptor_probe() {
  xcrun swiftc "$@" - <<'SWIFT'
public protocol TestDoublesModifyDescriptorProbe {
  var value: Int { get set }
}

public struct TestDoublesModifyDescriptorConformer:
  TestDoublesModifyDescriptorProbe
{
  private var storage: Int

  public init(storage: Int) {
    self.storage = storage
  }

  public var value: Int {
    get { storage }
    set { storage = newValue }
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

compile_swift_63_register_probe() {
  xcrun swiftc "$@" - <<'SWIFT'
public protocol TestDoublesRegisterProbe {
  func work(_ value: Int) throws -> Int
}

public struct TestDoublesRegisterProbeConformer: TestDoublesRegisterProbe {
  public init() {}
  public func work(_ value: Int) throws -> Int { value }
}
SWIFT
}

compile_swift_63_async_register_probe() {
  xcrun swiftc "$@" - <<'SWIFT'
public protocol TestDoublesAsyncRegisterProbe {
  func work(_ value: Int) async -> Int
}

public struct TestDoublesAsyncRegisterProbeConformer: TestDoublesAsyncRegisterProbe {
  public init() {}
  public func work(_ value: Int) async -> Int { value }
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
    's/^#define TD_PTRAUTH_OPAQUE_MODIFY_RESUME_FUNCTION ([0-9]+)$/\1/p' \
    "$header"
} | sort -u)"

read_context_size="$({
  sed -nE \
    's/^#define TD_READ_CONTEXT_SIZE ([0-9]+)$/\1/p' \
    "$header"
} | sort -u)"

modify_context_size="$({
  sed -nE \
    's/^#define TD_MODIFY_CONTEXT_SIZE ([0-9]+)$/\1/p' \
    "$header"
} | sort -u)"

if [[ -z "$expected" || "$expected" == *$'\n'* ]]; then
  echo "Could not read one TD_PTRAUTH_OPAQUE_MODIFY_RESUME_FUNCTION from $header." >&2
  exit 1
fi

# The pointer-auth discriminators the trampoline hardcodes are verbatim copies
# of swiftlang/swift's SpecialPointerAuthDiscriminators
# (include/swift/ABI/MetadataValues.h). Pin every one to its documented value:
# the compiler does not emit the CoroAllocator, async-context, or shape
# discriminators in a small probe, so this guards them against an accidental
# header edit that a live-compiler probe could not catch.
assert_header_discriminator() {
  local name="$1"
  local want="$2"
  local got
  got="$(sed -nE "s/^#define ${name} ([0-9a-fx]+)$/\1/p" "$header" | sort -u)"
  if [[ "$got" != "$want" ]]; then
    echo "${name} must remain ${want} (SpecialPointerAuthDiscriminators);" \
      "header has ${got:-missing}." >&2
    exit 1
  fi
}

assert_header_discriminator TD_PTRAUTH_OPAQUE_MODIFY_RESUME_FUNCTION 3909
assert_header_discriminator TD_PTRAUTH_CORO_ALLOCATION_FUNCTION 24469
assert_header_discriminator TD_PTRAUTH_CORO_DEALLOCATION_FUNCTION 40879
assert_header_discriminator TD_PTRAUTH_CORO_FRAME_ALLOCATION_FUNCTION 53841
assert_header_discriminator TD_PTRAUTH_CORO_FRAME_DEALLOCATION_FUNCTION 23464
assert_header_discriminator TD_PTRAUTH_NONUNIQUE_EXTENDED_EXISTENTIAL_TYPE_SHAPE 0xe798
assert_header_discriminator TD_PTRAUTH_ASYNC_CONTEXT_PARENT 0xbda2
assert_header_discriminator TD_PTRAUTH_ASYNC_CONTEXT_RESUME 0xd707
echo "Header pointer-auth discriminators match SpecialPointerAuthDiscriminators."

if [[ "$read_context_size" != "16" ]]; then
  echo "TD_READ_CONTEXT_SIZE must remain the runtime's 16-byte read context." >&2
  echo "Header: ${read_context_size:-missing}" >&2
  exit 1
fi

if [[ "$modify_context_size" != "32" ]]; then
  echo "TD_MODIFY_CONTEXT_SIZE must remain the runtime's 32-byte modify2 context." >&2
  echo "Header: ${modify_context_size:-missing}" >&2
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

modify_descriptor_assembly="$({
  compile_swift_63_modify_descriptor_probe \
    -emit-assembly \
    -parse-as-library \
    -enable-experimental-feature CoroutineAccessors \
    -module-name TestDoublesAccessorABIProbe \
    -target arm64e-apple-macosx13.0 \
    -o -
})"

modify_descriptor_sil="$({
  compile_swift_63_modify_descriptor_probe \
    -emit-silgen \
    -parse-as-library \
    -enable-experimental-feature CoroutineAccessors \
    -module-name TestDoublesAccessorABIProbe \
    -o -
})"

modify_descriptor_witness_count="$({
  printf '%s\n' "$modify_descriptor_sil" |
    awk '
      /sil_witness_table .*TestDoublesModifyDescriptorConformer: TestDoublesModifyDescriptorProbe/ {
        inWitnessTable = 1
        next
      }
      inWitnessTable && /^}/ { inWitnessTable = 0 }
      inWitnessTable && /method #TestDoublesModifyDescriptorProbe.value!modify2:/ { count += 1 }
      END { print count + 0 }
    '
})"

modify_descriptor_convention_count="$({
  printf '%s\n' "$modify_descriptor_sil" |
    awk '
      /^\/\/ protocol witness for TestDoublesModifyDescriptorProbe.value.modify2 in conformance/ {
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

if [[ "$modify_descriptor_witness_count" != "1" || "$modify_descriptor_convention_count" != "1" ]]; then
  echo "Swift 6.3 modify2 witness contract changed." >&2
  echo "modify2 witness-table entries: $modify_descriptor_witness_count" >&2
  echo "yield_once_2 modify witnesses: $modify_descriptor_convention_count" >&2
  exit 1
fi

modify_descriptor_frame_size="$({
  printf '%s\n' "$modify_descriptor_assembly" |
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

if [[ "$modify_descriptor_frame_size" != "32" ]]; then
  echo "Swift compiler modify2 descriptor layout changed." >&2
  echo "Expected relative entry, 32-byte caller frame, and malloc type ID." >&2
  echo "Compiler caller frame: ${modify_descriptor_frame_size:-missing}" >&2
  exit 1
fi

modify_descriptor_requirement_flags="$({
  printf '%s\n' "$modify_descriptor_assembly" |
    awk '
      /ModifyDescriptorProbeMp:$/ { inDescriptor = 1; next }
      inDescriptor && $1 == ".long" {
        longCount += 1
        if (longCount == 5 && $2 != "3") exit
        if (longCount == 11) {
          value = $2
          sub(/;.*/, "", value)
          print value
          exit
        }
      }
    '
})"

if [[ -z "$modify_descriptor_requirement_flags" ]] || (( (modify_descriptor_requirement_flags & 0xffff) != 0x36 )); then
  echo "Swift 6.3 modify2 requirement flags changed." >&2
  echo "Expected low flags: 0x0036" >&2
  echo "Compiler flags word: ${modify_descriptor_requirement_flags:-missing}" >&2
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

# Whether the library's own resume-discriminator derivation
# (YieldingAccessorRuntime.readResumeDiscriminator /
# modifyResumeDiscriminator) agrees with the compiler is checked by calling
# those real, shipped functions directly -- not by reproducing their spelling
# algorithm a second time here. See
# Tests/TestDoublesTests/Unit/YieldOnce2ResumeDiscriminatorABITests.swift,
# which does this `@testable` for several yield shapes (a hand-copied bash/C
# reproduction could only ever catch a divergence between two transcriptions,
# not a bug in the real Swift source). `swift test` already runs that suite in
# CI, gated on this same live-compiler requirement.

echo "Swift 6.3 compiler selected for the required accessor ABI baseline."
echo "Swift 6.3 _modify convention matches: yield_once"
echo "Swift arm64e modify-resume discriminator matches header: $derived"
echo "Swift 6.3 modify2 witness contract matches: one yield_once_2 descriptor"
echo "Swift 6.3 modify2 requirement low flags match: 0x0036"
echo "Swift 6.3 modify2 descriptor shape and caller frame match: 32 bytes"
echo "Swift 6.3 read witness contract matches: one read2 yield_once_2 witness"
echo "Swift 6.3 read requirement low flags match: 0x0035"
echo "Swift 6.3 yield_once_2 descriptor shape and caller frame match: 32 bytes"
echo "Swift 6.3 compiler emitted one Int read-resume discriminator: $read_resume_discriminator"
echo "Runtime read context size matches header contract: $read_context_size bytes"
echo "Runtime modify2 context size matches header contract: $modify_context_size bytes"

# TestDoublesTrampoline.S hand-writes self/error/async-context register
# traffic (TD_FRAME_SWIFT_SELF_OFFSET/TD_FRAME_SWIFT_ERROR_OFFSET load from
# x20/x21 on arm64 and %r13/%r12 on x86_64; async invoke routines thread
# x22/%r14 the same way) instead of letting the compiler emit that plumbing
# itself. The exact physical register each maps to is
# docs/ABI/CallingConventionSummary.rst's call, not this project's or a
# single compiler version's -- verifying that mapping directly would mean
# inspecting AArch64/X86 backend register allocation, and it's the most
# stable, most widely depended-upon part of the whole platform ABI. The far
# more likely drift is Swift's frontend no longer marking these parameters
# specially at all, which this checks directly via the
# swiftself/swifterror/swiftasync LLVM attributes IRGen emits on every
# protocol witness thunk.
witness_thunk_ir="$({
  compile_swift_63_register_probe \
    -emit-ir \
    -parse-as-library \
    -module-name TestDoublesRegisterABIProbe \
    -o -
})"

witness_thunk_self_error_count="$({
  printf '%s\n' "$witness_thunk_ir" |
    grep -c 'TW"(i64 %0, ptr noalias swiftself .*ptr noalias swifterror' || true
})"

if [[ "$witness_thunk_self_error_count" != "1" ]]; then
  echo "Swift 6.3 protocol witness thunks no longer mark self/error with swiftself/swifterror." >&2
  echo "Matching witness thunk signatures: $witness_thunk_self_error_count" >&2
  exit 1
fi

async_witness_thunk_ir="$({
  compile_swift_63_async_register_probe \
    -emit-ir \
    -parse-as-library \
    -module-name TestDoublesAsyncRegisterABIProbe \
    -o -
})"

async_witness_thunk_context_count="$({
  printf '%s\n' "$async_witness_thunk_ir" |
    grep -c 'TW"(ptr swiftasync %0' || true
})"

if [[ "$async_witness_thunk_context_count" != "1" ]]; then
  echo "Swift 6.3 async protocol witness thunks no longer mark the async context with swiftasync." >&2
  echo "Matching async witness thunk signatures: $async_witness_thunk_context_count" >&2
  exit 1
fi

echo "Swift 6.3 witness thunks mark self/error with swiftself/swifterror (x20/x21 arm64, r13/r12 x86_64 per docs/ABI/CallingConventionSummary.rst)."
echo "Swift 6.3 async witness thunks mark the async context with swiftasync (x22 arm64, r14 x86_64 per docs/ABI/CallingConventionSummary.rst)."

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
