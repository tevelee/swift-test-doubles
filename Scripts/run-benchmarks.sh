#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
repository_root="$(cd "$script_directory/.." && pwd)"
readonly repository_root

if [[ -z "${TEST_DOUBLES_BENCHMARK_COMPILER:-}" ]]; then
  IFS= read -r TEST_DOUBLES_BENCHMARK_COMPILER < <(swift --version)
  export TEST_DOUBLES_BENCHMARK_COMPILER
fi

if [[ -z "${TEST_DOUBLES_BENCHMARK_REVISION:-}" ]]; then
  TEST_DOUBLES_BENCHMARK_REVISION="$(git -C "$repository_root" rev-parse HEAD)"
  export TEST_DOUBLES_BENCHMARK_REVISION
fi

exec swift run \
  --package-path "$repository_root/Benchmarks" \
  --scratch-path "$repository_root/.build/benchmarks" \
  --configuration release \
  TestDoublesBenchmarks \
  "$@"
