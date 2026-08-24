#!/usr/bin/env bash

set -euo pipefail

threshold="${1:-84.9}"
scratch_path="${2:-.build/coverage}"

if ! [[ "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "error: coverage threshold must be a non-negative number" >&2
  exit 2
fi

TESTDOUBLES_ENABLE_C_COVERAGE=1 swift test \
  --parallel \
  --experimental-maximum-parallelization-width 4 \
  --enable-code-coverage \
  --scratch-path "$scratch_path"

coverage_path="$(
  TESTDOUBLES_ENABLE_C_COVERAGE=1 swift test \
    --show-codecov-path \
    --scratch-path "$scratch_path"
)"

if [[ ! -f "$coverage_path" ]]; then
  echo "error: SwiftPM did not produce a coverage report at $coverage_path" >&2
  exit 1
fi

python3 - "$coverage_path" "$threshold" <<'PY'
import json
import pathlib
import sys

coverage_path = pathlib.Path(sys.argv[1])
threshold = float(sys.argv[2])

with coverage_path.open(encoding="utf-8") as coverage_file:
    report = json.load(coverage_file)

source_roots = (
    "ManualStubGeneratorCore",
    "InternalRuntimeContract",
    "TestDoubles",
    "TestDoublesTesting",
    "TestDoublesRuntime",
    "CTestDoublesTrampoline",
)
totals = {root: {"covered": 0, "count": 0, "files": 0} for root in source_roots}

for data in report.get("data", []):
    for file in data.get("files", []):
        filename = file.get("filename", "").replace("\\", "/")
        root = next(
            (root for root in source_roots if f"/Sources/{root}/" in filename),
            None,
        )
        if root is None:
            continue
        expected_extension = ".c" if root == "CTestDoublesTrampoline" else ".swift"
        if not filename.endswith(expected_extension):
            continue

        lines = file.get("summary", {}).get("lines", {})
        totals[root]["covered"] += int(lines.get("covered", 0))
        totals[root]["count"] += int(lines.get("count", 0))
        totals[root]["files"] += 1

failed = False
for root in source_roots:
    total = totals[root]
    language = "C" if root == "CTestDoublesTrampoline" else "Swift"
    minimum = min(threshold, 70) if root == "CTestDoublesTrampoline" else threshold
    if total["files"] == 0 or total["count"] == 0:
        print(
            f"error: coverage report contains no {root} {language} sources",
            file=sys.stderr,
        )
        failed = True
        continue

    percentage = total["covered"] * 100 / total["count"]
    print(
        f"{root} {language} source coverage: {percentage:.2f}% "
        f"({total['covered']}/{total['count']} lines across {total['files']} files; "
        f"minimum {minimum:.2f}%)"
    )
    if percentage < minimum:
        print(
            f"error: {root} {language} source coverage {percentage:.2f}% is below "
            f"the {minimum:.2f}% minimum",
            file=sys.stderr,
        )
        failed = True

if failed:
    sys.exit(1)
PY

echo "CTestDoublesTrampoline assembly is validated by architecture-specific ABI integration tests; LLVM has no source-line mapping for the hand-written trampoline."
