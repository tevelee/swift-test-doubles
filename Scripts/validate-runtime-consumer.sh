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

# Xcode 26.6 crashes in LoadableByAddress while compiling several external ABI
# stress fixtures. The root debug and release suites exercise those APIs. Keep
# this check focused on compiling and running an ordinary out-of-package client.
export TESTDOUBLES_MINIMAL_RUNTIME_CONSUMER_TESTS=1

"${swift_command[@]}" test \
    --package-path "$root/Tests/RuntimeConsumerClient" \
    --scratch-path "$root/.build/runtime-consumer"
"${swift_command[@]}" test \
    -c release \
    --package-path "$root/Tests/RuntimeConsumerClient" \
    --scratch-path "$root/.build/runtime-consumer"
