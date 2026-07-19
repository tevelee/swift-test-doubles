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

expected_payload='Sources/TestDoubles/Metadata/StubPayload.swift'
payload_pattern='^[[:space:]]*((public|package|internal|fileprivate|private|final|indirect)[[:space:]]+)*(class|struct|enum|actor|protocol|typealias)[[:space:]]+StubPayload\b'
if payload_declarations="$(
  grep --recursive --extended-regexp --files-with-matches \
    --include='*.swift' \
    "$payload_pattern" \
    Sources/TestDoubles
)"; then
  :
else
  status=$?
  if [[ "$status" -eq 1 ]]; then
    payload_declarations=''
  else
    echo 'Boundary scan failed while locating StubPayload.' >&2
    exit "$status"
  fi
fi
if [[ "$payload_declarations" != "$expected_payload" ]]; then
  echo "StubPayload must have exactly one declaration at $expected_payload." >&2
  if [[ -n "$payload_declarations" ]]; then
    printf '%s\n' "$payload_declarations" >&2
  fi
  failure=1
fi

if [[ "$failure" -ne 0 ]]; then
  exit 1
fi

echo 'Internal source boundaries match ARCHITECTURE.md.'
