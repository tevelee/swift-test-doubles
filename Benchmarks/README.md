# Runtime benchmarks

This package measures the runtime-generated test-double paths independently of
the correctness test suite. It is deliberately dependency-free so the same
benchmark code can be built against two repository revisions and compared on
the same machine.

Run the complete suite in release mode:

```sh
Scripts/run-benchmarks.sh
```

Write machine-readable results:

```sh
Scripts/run-benchmarks.sh --output candidate.json
```

Compare two result files, normalizing against direct protocol dispatch and
failing when a benchmark regresses by more than 20 percent:

```sh
Scripts/run-benchmarks.sh compare baseline.json candidate.json \
  --max-regression-percent 20
```

The benchmark workflow applies the candidate's benchmark driver to both source
revisions, then runs them on the same hosted runner. This keeps harness changes
out of the runtime comparison. Timing thresholds do not run as part of ordinary
unit tests because absolute timings vary across machines.

The `comparable` suite is the subset that predates the July 2026 ABI expansion.
It exists so that expansion can be audited against `a02b47d`. New benchmarks
join the complete suite immediately and become comparison baselines for future
changes once merged.

The complete suite covers ordinary and stack-spilled async calls, scalar and
128-bit SIMD transport, `Self` and closure arguments, `Void` and reference
values, forwarding spies, matcher capture and lookup, verification, bounded
associated dictionaries, associated typed errors, and `_read` accessors.
Construction cases measure warmed steady-state construction and run last because
generated witness identities intentionally remain alive for the process.
