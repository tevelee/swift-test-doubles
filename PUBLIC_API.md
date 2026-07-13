# Public API snapshot

[`PUBLIC_API.snapshot`](PUBLIC_API.snapshot) is the authoritative source-level
API for the first TestDoubles release. It is a canonical, readable projection
of the public Swift symbol graph: declarations, conformances, constraints, and
explicit availability are sorted so CI produces a focused diff.

Runtime implementation types are deliberately absent. The supported behavior
behind these declarations is documented in [README.md](README.md) and the
[Stub Contract](Sources/TestDoubles/Documentation.docc/Articles/StubContract.md).

Check the snapshot with:

```sh
Scripts/check-public-api.sh
```

When a public API change is intentional, review its generated diff and update
the snapshot with:

```sh
Scripts/check-public-api.sh --update
```

The minimum Swift toolchain CI lane is the final check that the projection is
stable at the supported compiler boundary.
