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

# Xcode 26.6 can crash in LoadableByAddress when it batch-compiles the async
# stream and closure consumer tests as multiple primary files. Compile each
# source independently while retaining the same debug and release coverage.
"${swift_command[@]}" test \
    --package-path "$root/Tests/RuntimeConsumerClient" \
    --scratch-path "$root/.build/runtime-consumer" \
    -Xswiftc -disable-batch-mode
"${swift_command[@]}" test \
    -c release \
    --package-path "$root/Tests/RuntimeConsumerClient" \
    --scratch-path "$root/.build/runtime-consumer" \
    -Xswiftc -disable-batch-mode
