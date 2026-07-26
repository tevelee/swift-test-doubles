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

check_single_declaration() {
  local type_name="$1"
  local expected_file="$2"
  shift 2
  local pattern
  pattern="^[[:space:]]*((public|package|internal|fileprivate|private|final|indirect)[[:space:]]+)*(class|struct|enum|actor|protocol|typealias)[[:space:]]+${type_name}\\b"

  local declarations
  if declarations="$(
    grep --recursive --extended-regexp --files-with-matches \
      --include='*.swift' \
      "$pattern" \
      "$@"
  )"; then
    :
  else
    local status=$?
    if [[ "$status" -eq 1 ]]; then
      declarations=''
    else
      echo "Boundary scan failed while locating $type_name." >&2
      exit "$status"
    fi
  fi

  if [[ "$declarations" != "$expected_file" ]]; then
    echo "$type_name must have exactly one declaration at $expected_file." >&2
    if [[ -n "$declarations" ]]; then
      printf '%s\n' "$declarations" >&2
    fi
    failure=1
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
  '\b(FabricatedRuntimePlan|RuntimeFabricatedInvocation|FabricatedWitnessTableFactory|FabricatedWitnessTables|FabricatedExistentialStorage|FabricatedRuntimeResources)\b' \
  'Public construction must not name runtime fabrication implementation types:' \
  Sources/TestDoubles

check_absent \
  'TestDoublesRuntime\.RuntimeStubFactory\b' \
  'Only the public RuntimeStubFactory facade may call the runtime factory:' \
  Sources/TestDoubles/Preparation \
  Sources/TestDoubles/Doubles \
  Sources/TestDoubles/Recording

check_absent \
  '^[[:space:]]*import[[:space:]]+(TestDoublesRuntime|Echo|CTestDoublesTrampoline)\b' \
  'ManualStub must remain a source-level semantic API:' \
  Sources/TestDoubles/Doubles/ManualStub.swift

check_absent \
  '\b(MethodDescriptor|ABIClass|Trampoline|WitnessTable)\b' \
  'ManualStub must not name runtime ABI or trampoline implementation types:' \
  Sources/TestDoubles/Doubles/ManualStub.swift

check_single_declaration \
  'FabricatedPayload' \
  'Sources/TestDoublesRuntime/Metadata/FabricatedPayload.swift' \
  Sources/TestDoublesRuntime

check_single_declaration \
  'StubExistentialRepresentation' \
  'Sources/TestDoublesRuntime/Metadata/StubExistentialRepresentation.swift' \
  Sources/TestDoublesRuntime

check_single_declaration \
  'LinkedWitnessTableGraph' \
  'Sources/TestDoublesRuntime/Metadata/LinkedWitnessTableGraph.swift' \
  Sources/TestDoublesRuntime

check_single_declaration \
  'ProtocolWitnessTableLayout' \
  'Sources/TestDoublesRuntime/Metadata/ProtocolWitnessTableLayout.swift' \
  Sources/TestDoublesRuntime

check_single_declaration \
  'MethodDescriptor' \
  'Sources/TestDoublesRuntime/Metadata/MethodDescriptor.swift' \
  Sources/TestDoublesRuntime

check_single_declaration \
  'RuntimeInvocationEndpoint' \
  'Sources/InternalRuntimeContract/RuntimeInvocationContract.swift' \
  Sources

if [[ "$failure" -ne 0 ]]; then
  exit 1
fi

echo 'Internal source boundaries match ARCHITECTURE.md.'
