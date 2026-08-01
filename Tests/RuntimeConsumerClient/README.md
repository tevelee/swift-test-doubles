# Runtime consumer smoke test

This package is built as an external SwiftPM client. Its fixture target enables
library evolution, so its tests exercise the ABI boundary a package consumer
sees rather than the root package's test-target layout.

The scenarios cover imported resilient and frozen structs, `URL`, nested
optional `URL`, all standard generic range forms over imported values,
reference-backed `Array` and `Dictionary` batches, `ClosedRange<Date>`, nominal,
generic, and recursive model shells, and `Result` payloads. They also cover
composed and custom matchers, optional captures, Spy forwarding after
calibration, static methods with hidden metatype payloads, main-actor calls,
async and async-throwing requirements, sync and async initializer requirements,
and fail-closed resilient method and property results.
