#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"

# Benchmarks depend on this package by path, so their resolved transitive
# dependencies must match the package's own resolution. `resolve` alone keeps
# an existing compatible pin and therefore cannot detect a stale benchmark lock.
python3 - "$repository_root/Package.resolved" "$repository_root/Benchmarks/Package.resolved" <<'PY'
import json
import pathlib
import sys


def pins(path):
    with pathlib.Path(path).open(encoding="utf-8") as file:
        return {
            pin["identity"]: {
                "location": pin["location"],
                "state": pin["state"],
            }
            for pin in json.load(file)["pins"]
        }


package_pins = pins(sys.argv[1])
benchmark_pins = pins(sys.argv[2])
identities = sorted(set(package_pins) | set(benchmark_pins))
differences = [
    identity
    for identity in identities
    if package_pins.get(identity) != benchmark_pins.get(identity)
]

if differences:
    print(
        "error: Benchmarks/Package.resolved does not match the root package resolution:",
        file=sys.stderr,
    )
    for identity in differences:
        print(
            f"  {identity}: root={package_pins.get(identity)!r}; "
            f"benchmarks={benchmark_pins.get(identity)!r}",
            file=sys.stderr,
        )
    print(
        "Run `swift package --package-path Benchmarks update` and commit the lockfile.",
        file=sys.stderr,
    )
    sys.exit(1)
PY
