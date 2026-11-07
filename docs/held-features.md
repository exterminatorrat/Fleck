# Held features

These features exist as finished source outside the public branches. The
maintainer has decided to hold them, so they are not in any open pull request.
When the maintainer asks a future task to integrate features, ask whether to
release one of these holds first. If the maintainer approves, start from the
recorded source below instead of rewriting the feature.

## Sparkle embedding, signing and build-operation records

**Status:** held by the maintainer on 2026-11-06. Do not port without explicit
approval.

**Boundary with public work:** the update-information pull request (#85, now
part of the consolidated status/update branch) already adds the pinned Sparkle
2.10.0 dependency, `FLECK_BUILD_WITHOUT_SPARKLE`, framework staging in
`Scripts/build-fleck-app.sh`, `AppUpdateController` and
`SparkleUpdateInformationChecker`. The held work is the release-side layer on
top of that:

- `Scripts/fleck-build-identity.py` commands `embed-sparkle`, `verify-sparkle`
  and `sign-sparkle`, plus the Sparkle pin and symlink validation.
- The same script's build-operation lifecycle: `reserve-operation`,
  `prepare-builder`, `validate-operation-capture`, `operation-field`,
  `write-operation-stage`, `verify-operation-stage`, `finalize-operation` and
  `recover-operation`.
- About 16 matching tests in `Tests/Scripts/test_build_identity.py`.
- Callers and checks in `Scripts/build-fleck-app.sh`,
  `Scripts/build-parakeet-test-app.sh`,
  `Scripts/build-pre-astra-corrected-build.sh`,
  `Tests/Scripts/build-fleck-app-symbols.test.sh`,
  `Tests/Scripts/pre-astra-corrected-build.test.sh`,
  `Tests/FleckAppTests/ParakeetTestAppPackagingTests.swift`, and the
  `@loader_path/../Frameworks` rpath in `Package.swift`.

**Source:** the private retained-source handoff.

| Field | Value |
| --- | --- |
| Repository | `exterminatorrat/Fleck-development-archive` (private) |
| Branch | `handoff/f75-source-49726c715959-20261105` |
| Archive commit | `5ea84b12117179514b5f9be2ba35daf771fa51bd` |
| ZIP | `Fleck-source-49726c715959-20261105.zip`, 9,623,321 bytes |
| ZIP SHA-256 | `b97d21da0253f25b2cc742d5107b688ed8a735f3ecda9effef9bc5fa606c505f` |
| Retained source | commit `49726c7159597420c45ed189410acf7ea25c7e28`, VERSION `1.7.11-beta.1` |

The archive's `README.md` has the retrieval, checksum and extraction steps.
Extract into a new directory, never over a checkout. The files listed above are
under `source/` in the extracted tree.

**Integration notes for a future task:**

1. Port onto the branch that contains the status/update work, because it
   depends on the Sparkle dependency from #85.
2. Compare each listed file with the current branch and port only the held
   hunks. Public files can be newer than the retained snapshot.
3. Sparkle signing is release behavior, so it needs the macOS packaging checks
   in `TESTING.md` and a maintainer decision on signing material. Do not add
   keys or credentials to the repository.
