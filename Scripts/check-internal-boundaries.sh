#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
cd "$repository_root"

failure=0
import_prefix='^[[:space:]]*(@[[:alnum:]_]+(\([^)]*\))?[[:space:]]+)*'

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

check_public_runtime_imports() {
  local pattern="${import_prefix}import[[:space:]]+(TestDoublesRuntime|TestDoublesRuntimeMetadata|TestDoublesRuntimeSupport)\\b"
  local matches=''
  local file
  local file_matches

  while IFS= read -r file; do
    if file_matches="$(grep --extended-regexp --line-number --with-filename "$pattern" "$file")"; then
      matches+="$file_matches"$'\n'
    else
      local status=$?
      if [[ "$status" -ne 1 ]]; then
        echo "Boundary scan failed while checking public runtime imports." >&2
        exit "$status"
      fi
    fi
  done < <(
    find Sources/TestDoubles -type f -name '*.swift' \
      ! -path 'Sources/TestDoubles/Runtime/RuntimeStubFactory.swift' \
      -print
  )

  if [[ -n "$matches" ]]; then
    echo 'Only RuntimeStubFactory.swift may import runtime implementation targets:' >&2
    printf '%s' "$matches" >&2
    failure=1
  fi
}

check_absent \
  "${import_prefix}import[[:space:]]+(Echo|EchoRuntimeReflection|EchoRuntimeSupport|CTestDoublesTrampoline)\\b" \
  'The public TestDoubles target must not import low-level dependencies:' \
  Sources/TestDoubles

check_absent \
  "${import_prefix}import\\b" \
  'InternalRuntimeContract must remain dependency-free:' \
  Sources/InternalRuntimeContract

check_absent \
  '^[[:space:]]*(@[[:alnum:]_]+(\([^)]*\))?[[:space:]]+)*@_exported[[:space:]]+import\b' \
  'The runtime must not re-export implementation dependencies:' \
  Sources/TestDoublesRuntime

check_absent \
  '^[[:space:]]*(@[[:alnum:]_]+(\([^)]*\))?[[:space:]]+)*@_exported[[:space:]]+import\b' \
  'Runtime metadata must not re-export implementation dependencies:' \
  Sources/TestDoublesRuntimeMetadata

check_public_runtime_imports

check_absent \
  '^[[:space:]]*(@[[:alnum:]_]+(\([^)]*\))?[[:space:]]+)*@_exported[[:space:]]+import\b' \
  'The public Runtime facade must not re-export the ABI runtime:' \
  Sources/TestDoubles/Runtime

check_absent \
  '\b(FabricatedRuntimePlan|RuntimeFabricatedInvocation|FabricatedWitnessTableFactory|FabricatedWitnessTables|FabricatedExistentialStorage|FabricatedRuntimeResources)\b' \
  'Public construction must not name runtime fabrication implementation types:' \
  Sources/TestDoubles

check_absent \
  "${import_prefix}import[[:space:]]+(TestDoublesRuntime|TestDoublesRuntimeMetadata|TestDoublesRuntimeSupport|Echo|EchoRuntimeReflection|EchoRuntimeSupport|CTestDoublesTrampoline)\\b" \
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
