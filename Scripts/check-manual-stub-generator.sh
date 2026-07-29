#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT="$ROOT_DIR/Tests/ManualStubGeneratorIntegrationFixtures/Protocol.swift"
EXPECTED="$ROOT_DIR/Tests/ManualStubGeneratorIntegrationFixtures/GeneratedManualStub.swift"
OUTPUT_DIR="$ROOT_DIR/.build/manual-stub-generator-validation"
ACTUAL="$OUTPUT_DIR/GeneratedManualStub.swift"

mkdir -p "$OUTPUT_DIR"
swift package --package-path "$ROOT_DIR" --traits ManualStubGenerator plugin \
    --allow-writing-to-package-directory generate-manual-stub \
    GeneratedManualStubService "$INPUT" "$ACTUAL"
swift-format format --in-place "$ACTUAL"
diff -u "$EXPECTED" "$ACTUAL"

echo "Formatted ManualStubGenerator command-plugin output matches the compiling fixture."
