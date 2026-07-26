#!/usr/bin/env bash

set -euo pipefail

threshold="${1:-85}"
scratch_path="${2:-.build/coverage}"

if ! [[ "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "error: coverage threshold must be a non-negative number" >&2
  exit 2
fi

swift test \
  --parallel \
  --experimental-maximum-parallelization-width 4 \
  --enable-code-coverage \
  --scratch-path "$scratch_path"

coverage_path="$(
  swift test \
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
    "InternalRuntimeContract",
    "TestDoubles",
    "TestDoublesRuntimeMetadata",
    "TestDoublesRuntime",
    "TestDoublesRuntimeSupport",
)
totals = {root: {"covered": 0, "count": 0, "files": 0} for root in source_roots}

for data in report.get("data", []):
    for file in data.get("files", []):
        filename = file.get("filename", "").replace("\\", "/")
        if not filename.endswith(".swift"):
            continue

        root = next(
            (root for root in source_roots if f"/Sources/{root}/" in filename),
            None,
        )
        if root is None:
            continue

        lines = file.get("summary", {}).get("lines", {})
        totals[root]["covered"] += int(lines.get("covered", 0))
        totals[root]["count"] += int(lines.get("count", 0))
        totals[root]["files"] += 1

failed = False
for root in source_roots:
    total = totals[root]
    if total["files"] == 0 or total["count"] == 0:
        print(
            f"error: coverage report contains no {root} Swift sources",
            file=sys.stderr,
        )
        failed = True
        continue

    percentage = total["covered"] * 100 / total["count"]
    print(
        f"{root} Swift source coverage: {percentage:.2f}% "
        f"({total['covered']}/{total['count']} lines across {total['files']} files; "
        f"minimum {threshold:.2f}%)"
    )
    if percentage < threshold:
        print(
            f"error: {root} Swift source coverage {percentage:.2f}% is below "
            f"the {threshold:.2f}% minimum",
            file=sys.stderr,
        )
        failed = True

if failed:
    sys.exit(1)
PY
