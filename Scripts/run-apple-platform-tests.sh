#!/bin/bash

# Runs xcodebuild test for one Apple destination and turns a wedged run into a
# diagnosis instead of a silent job timeout.
#
# The Mac Catalyst job has stalled several times (2026-08-31, twice on
# 2026-09-21), always the same way: output stops mid-run, nothing is reported,
# and the 30-minute job cap cancels the job. A cancelled job skips the
# `if: failure()` artifact upload, so every one of those runs produced no
# evidence at all. This watches the test log and, once it goes quiet for
# longer than a test could reasonably take, samples every live test process
# before killing the run, so the stack that holds the lock ends up in the
# job log.

set -uo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
destination="${1:?usage: run-apple-platform-tests.sh <destination> <parallel> <derived-data> <result-bundle>}"
parallel="${2:?missing parallel-testing flag}"
derived_data="${3:?missing derived data path}"
result_bundle="${4:?missing result bundle path}"

# Longest observed healthy test is ~47s; a gap far beyond that is a wedge.
stall_seconds="${APPLE_PLATFORM_STALL_SECONDS:-300}"
poll_seconds=15

log="$(mktemp -t apple-platform-tests)"
trap 'rm -f "$log"' EXIT

xcodebuild \
    -scheme swift-test-doubles-Package \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled "$parallel" \
    -quiet \
    test > "$log" 2>&1 &
build_pid=$!

# Stream the log so the job shows progress; `disown` keeps bash from printing
# a job-control notice when the trap kills it.
tail -f "$log" &
tail_pid=$!
disown "$tail_pid" 2>/dev/null || true
# shellcheck disable=SC2064
trap "kill $tail_pid 2>/dev/null; rm -f '$log'" EXIT

while kill -0 "$build_pid" 2>/dev/null; do
    sleep "$poll_seconds"
    now="$(date +%s)"
    modified="$(stat -f %m "$log" 2>/dev/null || echo "$now")"
    quiet=$((now - modified))
    [ "$quiet" -lt "$stall_seconds" ] && continue

    echo "::error::No test output for ${quiet}s; the run is wedged. Sampling before exit."
    for pid in $(pgrep -f 'xctest|PackageTests' | head -8); do
        echo "::group::sample $pid"
        sample "$pid" 4 -mayDie 2>&1 || echo "sample failed for $pid"
        echo "::endgroup::"
    done
    kill -9 "$build_pid" 2>/dev/null
    pkill -9 -f xctest 2>/dev/null
    wait "$build_pid" 2>/dev/null
    exit 1
done

wait "$build_pid"
exit $?
