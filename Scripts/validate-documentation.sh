#!/bin/bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_path="${SWIFT_TEST_DOUBLES_DOCUMENTATION_BUILD_PATH:-$root/.build/documentation-validation}"
raw_symbols="$build_path/symbols-raw"
symbols="$build_path/symbols"

cd "$root"
rm -rf "$raw_symbols" "$symbols" "$build_path/docc"
mkdir -p "$raw_symbols" "$symbols"

swift build \
    --target TestDoubles \
    --scratch-path "$build_path/package" \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir \
    -Xswiftc "$raw_symbols"

cp \
    "$raw_symbols/TestDoubles.symbols.json" \
    "$symbols/TestDoubles.symbols.json"

xcrun docc convert \
    Sources/TestDoubles/Documentation.docc \
    --additional-symbol-graph-dir "$symbols" \
    --output-path "$build_path/docc" \
    --fallback-display-name TestDoubles \
    --fallback-bundle-identifier com.tevelee.TestDoubles \
    --fallback-bundle-version 0.1.0 \
    --analyze \
    --warnings-as-errors

ruby <<'RUBY'
errors = []
Dir.glob("{*.md,Sources/**/*.md,Tests/**/*.md,IntegrationTests/**/*.md}").each do |file|
  File.read(file).scan(/\]\(([^)]+)\)/).flatten.each do |target|
    next if target.match?(/\A(?:https?:|mailto:|#)/)
    path = File.expand_path(target.split("#", 2).first, File.dirname(file))
    errors << "#{file}: #{target}" unless File.exist?(path)
  end
end
abort(errors.join("\n")) unless errors.empty?
RUBY
