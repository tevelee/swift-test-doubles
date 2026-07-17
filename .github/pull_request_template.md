## Summary

Describe the observable behavior changed and why.

Closes #

## Validation

- [ ] I added or updated focused tests for the change.
- [ ] `swift test` passes.
- [ ] `swift test -c release` passes.
- [ ] Public usage examples remain covered by focused package tests.
- [ ] `Scripts/check-public-api.sh` passes; any intentional API snapshot change was reviewed.
- [ ] `Scripts/validate-documentation.sh` passes; public source and DocC documentation are current.
- [ ] `git diff --check` passes.

## Runtime and release impact

- [ ] I ran Address Sanitizer and Thread Sanitizer, or this change cannot affect runtime memory or concurrency behavior.
- [ ] I ran the full Rosetta package suite, or this change cannot affect ABI, assembly, trampolines, or dispatch.
- [ ] I documented changes to supported ABI shapes, ownership, effects, concurrency, or failure behavior.
- [ ] I updated `CHANGELOG.md` or explained why no user-facing release note is needed.

## Notes

Call out follow-up work, known limitations, and checks that a maintainer must run.
