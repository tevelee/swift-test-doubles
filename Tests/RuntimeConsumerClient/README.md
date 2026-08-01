# Runtime consumer smoke test

This package is built as an external SwiftPM client. Its fixture target enables
library evolution, so its tests exercise the ABI boundary a package consumer
sees rather than the root package's test-target layout.

The scenarios cover imported resilient and frozen structs, `URL`, nested
optional `URL`, generic ranges of imported values, `ClosedRange<Date>`, Spy
forwarding after calibration, and fail-closed resilient results.
