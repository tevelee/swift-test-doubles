#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v xcrun >/dev/null 2>&1; then
    swift_command=(xcrun swift)
else
    swift_command=(swift)
fi

# This consumer points at the root package by path. Reset its generated build
# graph so newly added root sources are compiled before either configuration.
"${swift_command[@]}" package clean \
    --package-path "$root/Tests/RuntimeConsumerClient" \
    --scratch-path "$root/.build/runtime-consumer"

# Xcode 26.6 crashes in LoadableByAddress while compiling the external async
# stream consumer. The root debug and release suites already exercise that API;
# retain the other out-of-package checks until the compiler bug is fixed.
export TESTDOUBLES_EXCLUDE_STREAM_CONSUMER_TESTS=1

"${swift_command[@]}" test \
    --package-path "$root/Tests/RuntimeConsumerClient" \
    --scratch-path "$root/.build/runtime-consumer"
"${swift_command[@]}" test \
    -c release \
    --package-path "$root/Tests/RuntimeConsumerClient" \
    --scratch-path "$root/.build/runtime-consumer"
