# Support

## Release status

TestDoubles is preparing its first tagged release. Until `0.1.0`, `main` is
available for evaluation but may change without a migration window. After the
first release, fixes will target the latest published version; older pre-1.0
versions are not guaranteed backports.

## Supported configuration

This file is the authoritative release-support policy.

- Swift 6.1 or later.
- macOS 15 or later on arm64 and on x86_64 under Rosetta.
- The public `TestDoubles` library product and the API listed in
  [PUBLIC_API.md](PUBLIC_API.md).

The package declares macOS 13 and iOS 16 deployment targets so experimental
builds can be evaluated, but CI does not execute the runtime below macOS 15 or
on iOS. Those configurations and Linux are unsupported. Only the configurations
above should be relied on for released software.

## Getting help

Search existing [issues](https://github.com/tevelee/swift-test-doubles/issues)
before opening a focused report. Include the TestDoubles version or commit,
Swift and Xcode versions, architecture, a minimal reproducer, and the complete
error or crash output.

Report vulnerabilities privately according to [SECURITY.md](SECURITY.md).
