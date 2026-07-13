# Support

## Release status

TestDoubles is preparing its first tagged release. Until `0.1.0`, `main` is
available for evaluation but may change without a migration window. After the
first release, fixes will target the latest published version; older pre-1.0
versions are not guaranteed backports.

## Supported configuration

This file is the authoritative release-support policy.

- Swift 6.1 or later.
- macOS 13 or later on arm64 and x86_64. CI executes x86_64 under Rosetta.
- iOS 16 or later in the arm64 Simulator.
- Ubuntu 24.04 on arm64 and x86_64.
- The public `TestDoubles` library product and the API listed in
  [PUBLIC_API.md](PUBLIC_API.md).

CI executes the runtime on every supported operating-system and architecture
family above. Apple deployment targets are compiled at their declared minimum
and executed on the simulator or runner versions available to GitHub Actions.
Other operating systems, Linux distributions, and architectures are unsupported.
Physical iOS devices are also unsupported because the runtime generates
executable trampoline code and CI cannot exercise device execution policy.

## Getting help

Search existing [issues](https://github.com/tevelee/swift-test-doubles/issues)
before opening a focused report. Include the TestDoubles version or commit,
Swift and Xcode versions, architecture, a minimal reproducer, and the complete
error or crash output.

Report vulnerabilities privately according to [SECURITY.md](SECURITY.md).
