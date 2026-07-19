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

covered = 0
count = 0
matched_files = 0

for data in report.get("data", []):
    for file in data.get("files", []):
        filename = file.get("filename", "").replace("\\", "/")
        if "/Sources/TestDoubles/" not in filename or not filename.endswith(".swift"):
            continue

        lines = file.get("summary", {}).get("lines", {})
        covered += int(lines.get("covered", 0))
        count += int(lines.get("count", 0))
        matched_files += 1

if matched_files == 0 or count == 0:
    print("error: coverage report contains no TestDoubles Swift sources", file=sys.stderr)
    sys.exit(1)

percentage = covered * 100 / count
print(
    f"TestDoubles Swift source coverage: {percentage:.2f}% "
    f"({covered}/{count} lines across {matched_files} files; "
    f"minimum {threshold:.2f}%)"
)

if percentage < threshold:
    print(
        f"error: Swift source coverage {percentage:.2f}% is below "
        f"the {threshold:.2f}% minimum",
        file=sys.stderr,
    )
    sys.exit(1)
PY
