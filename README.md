# Motes

Motes is a lightweight, native macOS menu-bar app for keeping multiple quick notes in tabs. The goal is a fast, local-first editor with rich-text formatting, bullets, numbered lists, installed-font support, and low idle resource use.

See the [product plan](PRODUCT_PLAN.md) for the complete vision, feature requirements, technical direction, performance goals, and delivery roadmap.

## Project status

Motes is implemented as a native SwiftPM executable. It is not yet a signed or
exported `.app`.

Clean Dictation is implemented as a release-disabled candidate. **Enhanced
Local is a non-shippable candidate:** it must not be included in a release
until the pinned model materially beats Standard on the privacy-safe
real-device corpus and every device, accessibility, resource, legal,
attribution, SBOM, signing/notarization, and Mac App Store gate in
[TESTING.md](TESTING.md) has recorded evidence. A green build or CI run is not
release approval. Until those gates pass, keep Enhanced Local out of release UI
and do not describe it as shipping.

## Development workflow

GitHub is the source of truth for this project. Changes should be made on a focused branch, committed with a descriptive message, pushed to GitHub, and submitted through a pull request. Keep application changes, relevant tests, and documentation together so the repository always reflects the current state of the product.

Run Motes through its development app bundle so macOS can associate microphone
and Speech permissions with Motes:

```sh
./Scripts/build_and_run.sh
```

Do not use `swift run Motes` for interactive testing. That launches a bare
executable without the app-bundle privacy identity required by dictation.

Ordinary builds have no external package dependencies and exclude the Enhanced
Local SDK, implementation, manifest, and resources. The exact FluidAudio pin
lives in the resolver-only
`Packages/MotesEnhancedCandidateDependencies` package. To compile and run the
developer-only Enhanced candidate tests, opt in explicitly with a separate
scratch directory:

```sh
MOTES_ENHANCED_CANDIDATE=1 swift test --scratch-path .build-candidate
```

Never set that variable for release validation; `Scripts/validate-macos.sh` and
`Scripts/check-release-size.sh` fail closed when it is present. A requested
candidate release is also rejected at compile time before linking.

Do not commit credentials, signing keys, provisioning profiles, local configuration containing secrets, or generated build output.
