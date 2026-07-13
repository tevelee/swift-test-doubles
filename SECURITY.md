# Security Policy

## Supported versions

Before `0.1.0`, security fixes are applied to `main`. After releases begin, only
the latest published pre-1.0 version is guaranteed security updates.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's
[private vulnerability reporting](https://github.com/tevelee/swift-test-doubles/security/advisories/new)
and include:

- the affected version or commit and platform;
- a minimal reproducer or proof of concept;
- the expected impact; and
- any known mitigations.

The maintainer will aim to acknowledge a report within seven days. Please allow
time to investigate and prepare a fix before public disclosure.

Private vulnerability reporting must be enabled as a release-blocking
repository setting before TestDoubles becomes public.

## Automated checks

GitHub Dependabot vulnerability alerts and automated security updates are
enabled. The repository also defines weekly and change-triggered CodeQL scans
for its Swift and GitHub Actions code. GitHub CodeQL uploads for private
repositories require GitHub Advanced Security, so those jobs activate when the
repository becomes public; workflow linting and the existing test matrix run
while it remains private.
