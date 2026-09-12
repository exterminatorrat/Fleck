# Fleck version and build identity

`VERSION` is the single product-version authority. It uses SemVer and currently identifies
the beta product as `1.0.1-beta.1`. `CHANGELOG.md` records factual product changes under a
matching version heading.

## Product-version decisions

- Small fixes and small features increment PATCH (`1.0.3` → `1.0.4`).
- Substantial feature sets increment MINOR. The boundary remains a human product decision.
- During beta, product changes increment PATCH or MINOR according to the size rules above and
  reset the prerelease to `beta.1`.
- A prerelease-only iteration increments `beta.N` without changing the numeric triple.
- Removing the prerelease suffix to create a stable version requires an explicit decision.
- Rebuilding unchanged source keeps the product version and allocates a new build identity.

Update `VERSION` and add its matching changelog heading in the same product-change commit.
Do not derive the version from Git, a branch name, an artifact name, or a prior bundle.

## Packaging identity

Every packaging attempt allocates and commits a monotonically increasing local number plus a
random canonical UUID in `/Users/harryjin/Fleck-builds/build-metadata/identities.sqlite3`.
SQLite `AUTOINCREMENT` transactions serialize allocations on that metadata store. Failed
attempts burn their allocated numbers. UUIDs distinguish builds across machines and after a
database replacement; the local number does not claim global ordering.

The decimal build number maps to Apple's numeric `CFBundleVersion` as follows, for `n >= 1`:

```text
(1 + (n - 1) // 10000).((n - 1) // 100 % 100).((n - 1) % 100)
```

The allocator rejects a value whose first component would exceed four digits. Packagers copy
the source plist into a staging bundle and stamp only that staged copy. The source plist is
never a version authority.

Packaged bundles carry the full product version, decimal build number, encoded bundle version,
UUID, UTC build time, complete source commit and tree, flavor, configuration, candidate
status, and accepted-baseline record/hash/status. Corrected repacks allocate a new outer UUID
and also retain the input app UUID and complete input-tree manifest hash.

The one artifact-label formatter is `Scripts/fleck-build-identity.py name --capture`; it emits
`Fleck <productVersion> Build <buildNumber>` from the already captured identity. Packagers use
that value for `CFBundleName`, `CFBundleDisplayName`, `FleckBuildLabel`, and every newly
published app or corrected-handoff name. They never reread `VERSION` or predict an allocator
value after capture.

All three packagers accept optional `--result-file ABSOLUTE_PATH`. The result destination must
not exist and must be below the canonical worktree `.build` directory through existing,
non-symlink parents. Only after publication and final bundle verification, the packager creates
the result atomically without replacement as an object containing exactly the absolute
`appPath` and captured `buildID`. A failed invocation leaves no success result. Consumers pin
that per-invocation path; they do not select a newest artifact or rely on the preserved legacy
unversioned outputs.

Versioned publications are immutable. Development and Parakeet builds publish one app at
`.build/<label>.app` and `.build/parakeet-test/<label>.app`. Corrected packaging consumes only
its nested Parakeet result and publishes `.build/<label>/`, containing `<label>.app`,
`Launch <label>.command`, provenance files, and `<label>-arm64.zip`; extracting the ZIP yields
one top-level `<label>` directory. A collision aborts without replacing, deleting, renaming, or
aliasing any prior versioned or legacy artifact.

## Canonical accepted baseline

`BuildBaseline.json` pins the expected canonical manifest digest and selected accepted source.
Local packaging reads `/Users/harryjin/Fleck-builds/accepted/manifest.json`, its sidecar, and
the preserved validator. It requires an active registry matching the pin, verifies the selected
record and artifacts, requires a clean descendant HEAD, and captures the exact HEAD commit and
tree. Source and registry verification run again immediately before publication. Missing,
inactive, malformed, changed, unrelated, or unverifiable state fails closed. No packager updates
the pin, promotes acceptance, relabels an existing artifact, or falls back to a weaker mode.
Clean-source verification also rejects Git `assume-unchanged` and `skip-worktree` flags so an
on-disk edit cannot be hidden behind index metadata. Before the preserved validator runs, its
bytes and size must match its authenticated `supportFiles` entry in the pinned manifest.

Hosted CI must explicitly use `ci-unverified`. It uses an ephemeral allocator and stamps a
status that is not a handoff or acceptance claim. Corrected handoff packaging refuses that mode.
Production local packaging has no accepted-root or allocator override: it always uses the fixed
canonical paths above. Tests can inject state only with explicitly test-named arguments, a
tracked fixture marker, a test-only environment flag, and paths confined below the temporary
fixture's ignored `.identity-test` directory; those builds are labeled as non-handoff fixtures.

All packagers share a fail-fast operation guard under their worktree's ignored `.build`
directory. The corrected packager explicitly lends its guard token only to its nested Parakeet
build. Separate worktrees remain independent. Packaging also requires exclusive ownership of
the source checkout for the operation; the guard cannot prevent an arbitrary editor from
changing files mid-compile, so the final source check is mandatory.

## About metadata

Settings → About shows readable short values but copies complete metadata, including the stable
bundle identifier. It never copies paths, branch names, environment values, or personal data.
A raw SwiftPM executable or otherwise unstamped app reports `Unpackaged development build` and
does not invent a build number, UUID, date, source revision, or acceptance state.
