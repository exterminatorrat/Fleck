# Fleck version and build identity

`VERSION` is the single product-version authority. It uses SemVer and currently
identifies the local development line as `1.0.3-beta.1`. `CHANGELOG.md` records
factual development changes under a matching version heading; neither file is
evidence of a public binary release.

## Product-version decisions

- Small fixes and small features increment PATCH.
- A substantial feature set requires an explicit human decision to increment
  MINOR.
- During beta, a product-version change resets the prerelease suffix to
  `beta.1`. A prerelease-only iteration increments `beta.N` without changing
  the numeric triple.
- Removing the prerelease suffix requires an explicit release decision.
- Rebuilding unchanged source keeps its product version but receives a fresh
  build number and build UUID.

Update `VERSION` and its dated `CHANGELOG.md` heading in the same product-change
commit. Do not derive the version from Git, a branch, an artifact name, or a
prior bundle.

The local `1.0.3-beta.1` development identity does not change the public
release policy in [`RELEASES.md`](RELEASES.md): Fleck has no published binary,
and any future public preview remains in the 0.x series unless the owner makes
an explicit release-version decision. Do not create retroactive releases from
development history.

## Packaging identity

Every local packaging attempt allocates a monotonically increasing number and
a random canonical UUID in `$HOME/Fleck-builds/build-metadata/identities.sqlite3`.
SQLite `AUTOINCREMENT` transactions serialize allocations. Failed attempts burn
their numbers, and UUIDs distinguish builds across machines or allocator-store
replacement; a local number does not claim global ordering.

The decimal build number maps to Apple's numeric `CFBundleVersion` as follows,
for `n >= 1`:

```text
(1 + (n - 1) // 10000).((n - 1) // 100 % 100).((n - 1) % 100)
```

Packaged bundles carry the full product version, decimal build number, encoded
bundle version, UUID, UTC build time, complete source commit and tree, flavor,
configuration, candidate status, and accepted-baseline identity. Corrected
repacks allocate a new outer UUID while retaining the input app UUID and input
tree-manifest hash.

`Scripts/fleck-build-identity.py name --capture` is the only artifact-label
formatter. It emits `Fleck <productVersion> Build <buildNumber>` from an already
captured identity. Packagers use that value for bundle names and every newly
published app, folder, launcher, and ZIP; they never reread `VERSION` or predict
an allocator value after capture.

All three packagers accept optional `--result-file ABSOLUTE_PATH`. The result
must not exist and must be below the owning worktree's canonical `.build`
directory through existing non-symlink parents. Only after publication and
final bundle verification does a packager atomically create the result with
exactly `appPath` and `buildID`. Consumers pin that per-invocation result instead
of selecting a newest artifact.

Versioned publications are immutable. Development and Parakeet builds publish
`.build/<label>.app` and `.build/parakeet-test/<label>.app`. Corrected packaging
publishes `.build/<label>/`, containing `<label>.app`,
`Launch <label>.command`, provenance files, and `<label>-arm64.zip`; extracting
the ZIP yields one top-level `<label>` directory. A collision aborts without
replacing, deleting, renaming, or aliasing any prior versioned or legacy
artifact.

## Accepted baseline and CI

`BuildBaseline.json` pins the expected canonical accepted-manifest digest and
selected accepted source. When a maintainer's project continuity instructions
make the private registry available, local handoff packaging reads
`$HOME/Fleck-builds/accepted/manifest.json`, its sidecar, and its preserved
validator. It requires the pinned active record, authenticated source and
artifacts, a clean descendant HEAD, no hidden index state or symlink
substitution, exclusive operation ownership, and unchanged registry and source
state through publication. Missing, changed, unrelated, or unverifiable state
fails closed; packaging never falls back from local mode to hosted mode.

Hosted CI must explicitly use `ci-unverified`. That mode needs no private local
registry, uses an ephemeral allocator, and stamps every packaged consumer as
not a handoff or acceptance candidate. Corrected handoff packaging refuses it.
Production local packaging exposes no accepted-root or allocator override;
tests can inject fixture state only through the tracked, confined test contract.

The packaging-operation guard is shared by all three packagers within one
worktree. Corrected packaging lends its token only to its nested Parakeet build,
and a final clean-source check closes the gap left by editors that can change
files while compilation is running.

## Development continuity

The reviewed development source chosen for this integration is
`77918cfcbcdb4d370202a146079618f980ed5996` plus this version-identity change.
It already includes the source-preview, editor, capsule, and native-fixture
work that must remain intact. Future tasks must name their reviewed development
source explicitly and preserve every accumulated feature rather than treating
a filename, timestamp, branch name, running app, or public `main` alone as
proof of the newest accepted work.

When project-scoped continuity instructions and a private accepted registry are
available, maintainers follow them. Contributors without that private state use
the base named in their issue or pull request and can run local Swift builds and
tests without making packaging or acceptance claims. Only hosted CI uses
`ci-unverified` for non-handoff packaging; contributors must not spoof its CI
environment guards locally. They must not claim an unknown public commit is the
newest accepted build.

Before a local handoff, run relevant checks, obtain the required review, verify
package identity and signatures, extract and inspect the archive, and preserve
earlier candidates. Never automatically accept, release, push, open a pull
request, merge, or alter the accepted pointer.

## About metadata

Settings → About shows readable short values but copies complete metadata,
including the stable bundle identifier. It never copies paths, branch names,
environment values, or personal data. A raw SwiftPM executable or otherwise
unstamped app reports `Unpackaged development build` and does not invent a build
number, UUID, date, source revision, or acceptance state.
