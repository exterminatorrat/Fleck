# Releases

Fleck has no published binary release. Public source visibility is a source
preview, not an app release. Any future public build will be a Developer
Preview in the 0.x series.

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

## Source preview checklist

The source preview publishes source and retained Git history for inspection. It
does not publish a signed or notarized app, GitHub Release, supported release,
or downloadable binary.

### Source identity and history

- [x] The reviewed launch changes are merged. The source baseline before this
      documentation update is `0fb88088febbde7e0e8e003cd2aadf0b1c4c5a91`
      with tree `2a9032097937b1a15e486a342998d155f64e0790`.
- [x] The maintainer approved MPL-2.0 for Fleck-owned source and documentation
      in the current tree, subject to the documented third-party, data, and
      brand boundaries. Earlier revisions keep their accompanying licenses.
- [x] The maintainer accepted publication of the complete history reachable
      from all 15 remote heads reported by the launch audit, including retained
      author metadata and historical path text. The audit found no remote tags.
      Current-tree sanitization is not history erasure.
- [x] The maintainer confirmed publication and unchanged source-review
      redistribution rights for the current and retained brand, generated, and
      captured assets identified in [`BRANDING.md`](../BRANDING.md), subject to
      its operating-system and third-party rights carve-outs.
- [x] A fresh post-merge inventory found 14 remote heads and no tags after the
      merged launch branches were removed. The earlier 15-head approval remains
      the historical publication record; a fixed head count is not a gate for
      later reviewed pull-request work.
- [ ] Confirm the final current tree contains no secrets, local paths, private
      fixtures, signing material, model weights, or internal-only files.

### Security and participation

- [x] The `exterminatorrat/Fleck` repository is public without an announcement.
      Its API reports ordinary issues and pull requests enabled, with pull
      requests allowed from all eligible contributors.
- [x] GitHub private vulnerability reporting is enabled. Authenticated and
      anonymous repository-setting reads report it enabled, the external
      [report URL](https://github.com/exterminatorrat/Fleck/security/advisories/new)
      reaches GitHub's sign-in flow, and [`SECURITY.md`](../SECURITY.md) names
      that route.
- [x] The owner confirmed that an outside private test report was submitted and
      its maintainer notification was visible. This delivery check does not
      establish a response or remediation timeline.
- [x] The owner approved email to [Harry](mailto:harrythemen@outlook.com) as the
      private Code of Conduct reporting route, and the public documents name the
      route and recipient separately from GitHub private vulnerability
      reporting.
- [x] The owner confirmed that a conduct test email was visible in Harry's
      receiving inbox. This delivery check does not establish a response or
      resolution timeline.
- [x] Ordinary issue and pull-request intake is enabled. The issue chooser
      returned HTTP 200 after GitHub's login redirect, and the issue and pull
      request template sources were inspected.
- [ ] Confirm the issue forms render after an authenticated GitHub sign-in.
- [ ] Announce the source preview only after the final source identity, CI,
      merge, security- and conduct-report delivery, and launch-document gates
      are complete.

### Source verification

- [x] GitHub Actions [run
      34543017175](https://github.com/exterminatorrat/Fleck/actions/runs/34543017175)
      passed at the exact `0fb88088febbde7e0e8e003cd2aadf0b1c4c5a91`
      baseline: 2,268 ordinary tests in 31 suites, 2,476 Enhanced tests in 34
      suites, all seven website tests, the website build, and the release checks
      passed.
- [x] A local website verification on 2026-09-11 used Node.js 26.7 and
      npm 12.0.2 against the same source baseline. `npm ci`, full and
      production-only audits with zero reported vulnerabilities, all seven
      website tests, and the production build passed; the lockfile was
      unchanged. Main CI separately covers the declared Node.js 22.12 baseline.
- [ ] After this documentation update is merged, require green GitHub CI at the
      exact resulting source commit before an announcement. Repeat the website
      install, both audits, tests, and production build there; do not force
      unsupported dependency overrides to obtain that result.
- [ ] Confirm the MPL-2.0 license, notices, third-party attributions, dependency
      pins, and reserved-brand language match the source-preview tree.

## Optional future website deployment

Website deployment and hosting-account configuration do not block the
source-only preview. Before any future deployment:

- [ ] Configure the intended hosting account outside the source tree; do not
      commit a project identifier or substitute a dummy identifier.
- [ ] Confirm the deployed output preserves GSAP's proprietary banner and makes
      the complete `website/public/THIRD_PARTY_LICENSES.txt` notice artifact
      available with the site.

## Future binary distribution

### Candidate and verification

- [ ] Build from the exact synchronized release commit, not an older `.app`.
- [ ] Run the ordinary non-launching macOS validator and require green GitHub CI.
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
