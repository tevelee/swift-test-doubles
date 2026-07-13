# Releasing TestDoubles

This checklist is the reproducible path for the first `0.1.0` release and later
versions. Run it from `main`; do not create the tag until the exact release
commit has passed every required CI job.

## Prepare the release commit

1. Confirm [SUPPORT.md](SUPPORT.md), [PUBLIC_API.md](PUBLIC_API.md), and the
   README describe only the behavior and platforms exercised by CI.
2. Resolve every open release blocker in [ROADMAP.md](ROADMAP.md). In
   particular, replace Echo's development revision with a compatible tagged
   release before tagging TestDoubles.
3. Move the relevant `Unreleased` changelog entries under
   `## [0.1.0] - YYYY-MM-DD` and add a new empty `Unreleased` section.
4. Update the machine snapshot only after reviewing the corresponding source
   API change:

   ```bash
   Scripts/check-public-api.sh --update
   ```

5. Commit the release preparation, then run the clean-tree local gates:

   ```bash
   Scripts/validate-release.sh 0.1.0
   ```

The validator resolves both package graphs, verifies that their lockfiles do
not change, checks the public API and documentation, and runs debug, release,
and external-consumer tests.

## Verify the release commit

Push the release commit and wait for its complete GitHub Actions matrix:

```bash
commit="$(git rev-parse HEAD)"
git push origin main
run_id=""
for _ in {1..30}; do
    run_id="$(gh run list --workflow CI --commit "$commit" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
    test -n "$run_id" && break
    sleep 2
done
test -n "$run_id"
gh run watch "$run_id" --exit-status
```

Before the repository becomes public, also confirm in GitHub settings that
private vulnerability reporting is enabled and that branch protection requires
the supported CI jobs.

## Tag and publish

From the already validated release commit:

```bash
test -z "$(git status --porcelain --untracked-files=all)"
git tag -a 0.1.0 -m "TestDoubles 0.1.0"
git push origin 0.1.0
gh release create 0.1.0 --verify-tag --title "TestDoubles 0.1.0" --notes-from-tag
```

Finally, run the consumer suite against the published version instead of its
usual local path dependency:

```bash
smoke="$(mktemp -d)"
cp -R IntegrationTests/Consumer "$smoke/Consumer"
rm "$smoke/Consumer/Package.resolved"
perl -0pi -e \
  's|\.package\(path: "../.."\)|.package(url: "https://github.com/tevelee/swift-test-doubles", from: "0.1.0")|' \
  "$smoke/Consumer/Package.swift"
swift test --package-path "$smoke/Consumer"
rm -rf "$smoke"
```

This exact smoke test catches version-resolution failures that a local path
dependency cannot reproduce.
