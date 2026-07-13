#!/bin/bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-0.1.0}"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "usage: Scripts/validate-release.sh [semantic-version]" >&2
    exit 64
fi

cd "$root"

if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "Release validation must run from main." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
    echo "Release validation requires a clean working tree." >&2
    exit 1
fi

if git rev-parse --verify --quiet "refs/tags/$version" >/dev/null; then
    echo "Tag $version already exists locally." >&2
    exit 1
fi

if [[ -n "$(git ls-remote --tags origin "refs/tags/$version")" ]]; then
    echo "Tag $version already exists on origin." >&2
    exit 1
fi

swift package resolve
swift package --package-path IntegrationTests/Consumer resolve
git diff --exit-code -- Package.resolved IntegrationTests/Consumer/Package.resolved

Scripts/check-public-api.sh
Scripts/validate-documentation.sh
swift test --scratch-path .build/release-validation
swift test -c release --scratch-path .build/release-validation
swift test \
    --package-path IntegrationTests/Consumer \
    --scratch-path .build/release-validation-consumer

git diff --exit-code
echo "Local release gates passed for $version."
