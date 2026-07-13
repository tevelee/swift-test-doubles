#!/bin/bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_path="${SWIFT_TEST_DOUBLES_SYMBOL_GRAPH_BUILD_PATH:-$root/.build/symbol-graph-validation}"
symbols="$build_path/symbols"

cd "$root"
mkdir -p "$symbols"

swift build \
    --target TestDoubles \
    --scratch-path "$build_path/package" \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir \
    -Xswiftc "$symbols" \
    -Xswiftc -symbol-graph-minimum-access-level \
    -Xswiftc public

test -f "$symbols/TestDoubles.symbols.json"
