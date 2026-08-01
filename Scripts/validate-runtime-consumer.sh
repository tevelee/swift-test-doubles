#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v xcrun >/dev/null 2>&1; then
    xcrun swift test \
        --package-path "$root/Tests/RuntimeConsumerClient" \
        --scratch-path "$root/.build/runtime-consumer"
else
    swift test \
        --package-path "$root/Tests/RuntimeConsumerClient" \
        --scratch-path "$root/.build/runtime-consumer"
fi
