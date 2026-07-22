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
  local pattern
  pattern="^[[:space:]]*((public|package|internal|fileprivate|private|final|indirect)[[:space:]]+)*(class|struct|enum|actor|protocol|typealias)[[:space:]]+${type_name}\\b"

  local declarations
  if declarations="$(
    grep --recursive --extended-regexp --files-with-matches \
      --include='*.swift' \
      "$pattern" \
      Sources/TestDoubles
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
  '^[[:space:]]*(public[[:space:]]+)?extension[[:space:]]+Stub\.Requirement\b' \
  'Runtime must not extend Stub.Requirement:' \
  Sources/TestDoubles/Runtime

check_absent \
  '^[[:space:]]*public[[:space:]]+(final[[:space:]]+)?(class|struct|enum|actor|protocol|typealias)[[:space:]]+Invocation\b' \
  'Runtime must not define a public Invocation type:' \
  Sources/TestDoubles/Runtime

check_absent \
  '\bStubResources\b' \
  'Metadata and Recording must not depend on concrete StubResources:' \
  Sources/TestDoubles/Metadata \
  Sources/TestDoubles/Recording

check_absent \
  '^[[:space:]]*((public|package|internal|fileprivate|private|final|indirect)[[:space:]]+)*(class|struct|enum|actor|protocol|typealias)[[:space:]]+StubPayload\b' \
  'StubPayload must be declared outside Runtime:' \
  Sources/TestDoubles/Runtime

check_absent \
  '\bStub<' \
  'Runtime must not depend on the generic Stub preparation coordinator:' \
  Sources/TestDoubles/Runtime

check_single_declaration \
  'StubPayload' \
  'Sources/TestDoubles/Metadata/StubPayload.swift'

check_single_declaration \
  'StubExistentialRepresentation' \
  'Sources/TestDoubles/Metadata/StubExistentialRepresentation.swift'

check_single_declaration \
  'LinkedWitnessTableGraph' \
  'Sources/TestDoubles/Metadata/LinkedWitnessTableGraph.swift'

check_single_declaration \
  'ProtocolWitnessTableLayout' \
  'Sources/TestDoubles/Metadata/ProtocolWitnessTableLayout.swift'

if [[ "$failure" -ne 0 ]]; then
  exit 1
fi

echo 'Internal source boundaries match ARCHITECTURE.md.'
