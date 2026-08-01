#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v xcrun >/dev/null 2>&1; then
    swift_command=(xcrun swift)
else
    swift_command=(swift)
fi

"${swift_command[@]}" test \
    --package-path "$root/Tests/RuntimeConsumerClient" \
    --scratch-path "$root/.build/runtime-consumer"
"${swift_command[@]}" test \
    -c release \
    --package-path "$root/Tests/RuntimeConsumerClient" \
    --scratch-path "$root/.build/runtime-consumer"
