# Releases

Fleck has no published release history yet. The first public build will be a
Developer Preview in the 0.x series.

## 0.x strategy

- Minor versions may change storage, UI, and contributor-facing interfaces while
  the product is still stabilizing.
- Patch versions should contain compatible fixes and documentation corrections.
- Every published version must come from an annotated source tag and a GitHub
  Release that states the supported macOS versions, known limitations, upgrade
  risks, and exact artifact checksums.
- A preview label must remain visible until compatibility and support promises
  are ready for a stable release.

Do not create retroactive release entries or imply that an untagged development
bundle was publicly shipped.

## Maintainer launch checklist

### Community and repository

- [ ] Decide the visibility date and confirm the intended public tree contains
      no secrets, local paths, private fixtures, signing material, model weights,
      or internal-only history.
- [ ] Choose and test a private security contact before visibility, then replace
      the gate in [`SECURITY.md`](../SECURITY.md) with verified instructions.
      After visibility, optionally enable and test GitHub private vulnerability
      reporting before announcing the repository or opening issues.
- [ ] Publish and test a private Code of Conduct reporting route, name the
      moderators, and update [`CODE_OF_CONDUCT.md`](../CODE_OF_CONDUCT.md).
- [ ] Enable the issue and pull-request workflows only when maintainers can
      review them; confirm the templates render and links resolve.
- [ ] Configure the intended hosting account separately from the source tree;
      do not commit a project identifier or substitute a dummy identifier.
- [ ] Confirm the MPL-2.0 license, notices, third-party attributions, dependency
      pins, and reserved-brand language match the release tree.

### Candidate and verification

- [ ] Build from the exact synchronized release commit, not an older `.app`.
- [ ] Run the ordinary non-launching macOS validator and require green GitHub CI.
- [ ] Clear the website development/build dependency audit gate. The production-
      only `npm audit --omit=dev` graph currently reports zero vulnerabilities,
      but the full `npm audit` reports eight vulnerable package entries (seven
      high and one low), so the production result does not clear the tooling used
      locally and in CI. Do not force unsupported dependency overrides to make
      the audit green.
- [ ] Run packaged native checks in a disposable macOS account with reviewed
      synthetic fixtures; retain only sanitized evidence.
- [ ] Complete accessibility, keyboard, privacy, memory, CPU, energy, sleep/wake,
      and failure-recovery checks relevant to the candidate.
- [ ] Keep Enhanced Local disabled unless every separate model quality,
      integrity, licensing, attribution, resource, and distribution gate is
      explicitly approved.

### Distribution

- [ ] Set the version and build metadata, sign with the intended Developer ID,
      use the reviewed hardened-runtime and entitlement configuration, notarize,
      staple, and verify Gatekeeper on a clean Mac.
- [ ] Record the source commit, absolute built artifact, bundle identifier,
      executable SHA-256, archive SHA-256, signature identity, and notarization
      result.
- [ ] Create the annotated tag and GitHub Release notes only after the accepted
      artifact and source agree; attach checksums and accurate limitations.

### Launch materials

- [ ] Capture new screenshots from the accepted release candidate. Use synthetic
      notes, check every frame for private data, and provide useful alt text.
- [ ] Prepare a concise announcement for the chosen social channels without
      claiming unavailable features or support.
- [ ] Add sponsorship or funding links only if the maintainer selects and
      verifies an account. Sponsorship is optional; do not create a placeholder
      funding file.

After release, verify the tag, release page, artifacts, checksums, download path,
security route, and issue templates as an outside visitor.
