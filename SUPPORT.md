# Support

## Release status

TestDoubles is preparing its first tagged release. Until `0.1.0`, `main` is
available for evaluation but may change without a migration window. After the
first release, fixes will target the latest published version; older pre-1.0
versions are not guaranteed backports.

## Supported configuration

This file is the authoritative release-support policy.

- Swift 6.1 or later on Apple platforms; Swift 6.1 on Ubuntu.
- macOS 13 or later on arm64 and x86_64. CI executes x86_64 under Rosetta.
- Mac Catalyst 16 or later on arm64.
- iOS 16, tvOS 16, visionOS 1, and watchOS 9 or later in their arm64
  Simulators.
- Ubuntu 24.04 on arm64 and x86_64.
- The public `TestDoubles` library product and the API listed in
  [PUBLIC_API.md](PUBLIC_API.md).

CI executes the runtime on every supported operating-system and architecture
family above. Apple deployment targets are compiled at their declared minimum
and executed on the simulator or runner versions available to GitHub Actions.
Other operating systems, Linux distributions, and architectures are unsupported.
Physical iOS, tvOS, visionOS, and watchOS devices are also unsupported because
the runtime generates executable trampoline code and CI cannot exercise device
execution policy. The runtime does not implement watchOS's `arm64_32` device
ABI.

Swift 6.2 and later on Linux are currently unsupported because Echo's Swift
Atomics 0.0.x dependency conflicts with the standard-library `Synchronization`
module in those toolchains. CI uses the official Swift 6.1.3 Ubuntu 24.04 image
until that dependency can move to a compatible release.

## Getting help

Search existing [issues](https://github.com/tevelee/swift-test-doubles/issues)
before opening a focused report. Include the TestDoubles version or commit,
Swift and Xcode versions, architecture, a minimal reproducer, and the complete
error or crash output.

Report vulnerabilities privately according to [SECURITY.md](SECURITY.md).
