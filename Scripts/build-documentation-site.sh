#!/bin/bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_path="${SWIFT_TEST_DOUBLES_DOCUMENTATION_SITE_BUILD_PATH:-$root/.build/documentation-site}"
symbol_build_path="${SWIFT_TEST_DOUBLES_SYMBOL_GRAPH_BUILD_PATH:-$root/.build/symbol-graph-site}"
raw_symbols="$symbol_build_path/symbols"
symbols="$build_path/symbols"
site="$build_path/site"
hosting_base_path="${SWIFT_TEST_DOUBLES_DOCUMENTATION_HOSTING_BASE_PATH:-swift-test-doubles}"

cd "$root"
rm -rf "$symbols" "$site"
mkdir -p "$symbols"

SWIFT_TEST_DOUBLES_SYMBOL_GRAPH_BUILD_PATH="$symbol_build_path" \
    Scripts/generate-symbol-graph.sh

cp "$raw_symbols"/TestDoubles*.symbols.json "$symbols/"

xcrun docc convert \
    Sources/TestDoubles/Documentation.docc \
    --additional-symbol-graph-dir "$symbols" \
    --output-path "$site" \
    --fallback-display-name TestDoubles \
    --fallback-bundle-identifier com.tevelee.TestDoubles \
    --fallback-bundle-version 0.0.3 \
    --transform-for-static-hosting \
    --hosting-base-path "$hosting_base_path"

echo "$site"
