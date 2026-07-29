#!/bin/bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_path="${SWIFT_TEST_DOUBLES_SYMBOL_GRAPH_BUILD_PATH:-$root/.build/symbol-graph-validation}"
symbols="$build_path/symbols"

cd "$root"
swift package --scratch-path "$build_path/package" clean
mkdir -p "$symbols"
for stale_symbol_graph in "$symbols"/TestDoubles*.symbols.json; do
    [[ -e "$stale_symbol_graph" ]] || continue
    rm "$stale_symbol_graph"
done

for target in TestDoubles TestDoublesTesting TestDoublesMacros; do
    swift build \
        --target "$target" \
        --scratch-path "$build_path/package" \
        -Xswiftc -emit-symbol-graph \
        -Xswiftc -emit-symbol-graph-dir \
        -Xswiftc "$symbols" \
        -Xswiftc -symbol-graph-minimum-access-level \
        -Xswiftc public
    test -f "$symbols/$target.symbols.json"
done
