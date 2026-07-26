#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
cd "$repository_root"

failure=0

check_absent() {
  local pattern="$1"
  local description="$2"
  shift 2

  local matches
  if matches="$(grep --recursive --extended-regexp --line-number --include='*.swift' "$pattern" "$@")"; then
    echo "$description" >&2
    printf '%s\n' "$matches" >&2
    failure=1
  else
    local status=$?
    if [[ "$status" -ne 1 ]]; then
      echo "Boundary scan failed while checking: $description" >&2
      exit "$status"
    fi
  fi
}

check_absent \
  '^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+(Echo|CTestDoublesTrampoline)\b' \
  'The public TestDoubles target must not import low-level dependencies:' \
  Sources/TestDoubles

check_absent \
  '^[[:space:]]*import\b' \
  'InternalRuntimeContract must remain dependency-free:' \
  Sources/InternalRuntimeContract

check_absent \
  '^[[:space:]]*@_exported[[:space:]]+import\b' \
  'The runtime must not re-export implementation dependencies:' \
  Sources/TestDoublesRuntime

check_absent \
  '\b(StubRecorder|StubError|Dummy|Spy|IssueReporting)\b' \
  'Runtime must not depend on TestDoubles semantic or diagnostic types:' \
  Sources/TestDoublesRuntime

check_absent \
  '^[[:space:]]*@_exported[[:space:]]+import\b' \
  'Runtime metadata must not re-export implementation dependencies:' \
  Sources/TestDoublesRuntimeMetadata

check_absent \
  '\b(StubRecorder|StubError|Dummy|Spy|IssueReporting)\b' \
  'Runtime metadata must not depend on TestDoubles semantic or diagnostic types:' \
  Sources/TestDoublesRuntimeMetadata

check_absent \
  '^[[:space:]]*import[[:space:]]+(TestDoublesRuntime|TestDoublesRuntimeMetadata)\b' \
  'Only Sources/TestDoubles/Runtime may import ABI runtime targets:' \
  Sources/TestDoubles/Doubles \
  Sources/TestDoubles/Metadata \
  Sources/TestDoubles/Recording

check_absent \
  '^[[:space:]]*@_exported[[:space:]]+import\b' \
  'The public Runtime facade must not re-export the ABI runtime:' \
  Sources/TestDoubles/Runtime

check_absent \
  '^[[:space:]]*import[[:space:]]+(TestDoublesRuntime|TestDoublesRuntimeMetadata|Echo|CTestDoublesTrampoline)\b' \
  'ManualStub must remain a source-level semantic API:' \
  Sources/TestDoubles/Doubles/ManualStub.swift

check_absent \
  '\b(MethodDescriptor|ABIClass|Trampoline|WitnessTable)\b' \
  'ManualStub must not name runtime ABI or trampoline implementation types:' \
  Sources/TestDoubles/Doubles/ManualStub.swift

if [[ "$failure" -ne 0 ]]; then
  exit 1
fi

echo 'Internal source boundaries match ARCHITECTURE.md.'
