# Security Policy

## Supported versions

Security fixes are applied to the latest published pre-1.0 version and `main`.
Older pre-1.0 versions are not guaranteed security updates.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Once the repository
is public, use GitHub's
[private vulnerability reporting](https://github.com/tevelee/swift-test-doubles/security/advisories/new)
and include:

- the affected version or commit and platform;
- a minimal reproducer or proof of concept;
- the expected impact; and
- any known mitigations.

The maintainer will aim to acknowledge a report within seven days. Please allow
time to investigate and prepare a fix before public disclosure.

GitHub exposes private vulnerability reporting only after a repository becomes
public. During publication, the maintainer must make the repository public,
immediately enable private vulnerability reporting, verify this advisory link,
and only then announce the repository or publish a release tag.

## Automated checks

GitHub Dependabot vulnerability alerts and automated security updates are
enabled. The repository also defines weekly and change-triggered CodeQL scans
for its Swift, C/C++, and GitHub Actions code. GitHub CodeQL uploads for private
repositories require GitHub Advanced Security, so those jobs activate when the
repository becomes public; workflow linting and the existing test matrix run
while it remains private.
