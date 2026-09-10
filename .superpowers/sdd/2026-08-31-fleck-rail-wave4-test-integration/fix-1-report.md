# Fix 1 report: processing terminal semantics

Date: 2026-08-31

Branch: `codex/fleck-rail-wave4-test-integration`

Starting checkpoint: `4e88e42c9ab2b6c76e056924a6956dbf4fe73e29`

Commit: the local commit containing this report; its exact hash is returned to
the parent after commit because a commit cannot embed its own hash.

## Root cause and correction

`FleckApp` injects `StreamingDictationProcessor`. Its empty-final path throws
`StreamingDictationProcessorError.noSpeech`, but
`DictationCoordinator.finishProcessingCapture` previously mapped every thrown
processing error through the generic inferred `.failed(message)` terminal and
supplied no `failureStage`. Its returned capture-context mismatch branch also
omitted `failureStage`.

The production change is limited to two terminal calls:

- typed `.noSpeech` now supplies terminal outcome `.noSpeech`;
- thrown processing finalization errors and returned processing context
  mismatches supply authoritative `failureStage: .capture`.

No user-facing copy, error taxonomy, processor behavior, pill/UI code, shortcut,
Settings, dictionary, corpus, package manifest, or lockfile changed.

## TDD evidence

The test seam gained an optional processing-session finish error, then the
processing-backed regression was run before production code changed:

```sh
swift test --disable-automatic-resolution --no-parallel --filter processingBackedNoSpeechPublishesNoSpeechWithCaptureProvenance
```

RED, 1 test with 2 issues:

- expected `.noSpeech`, received `.failed("No speech detected.")`;
- expected `failureStage == .capture`, received `nil`.

The two additional provenance regressions were also RED before implementation:

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.processing(FinalizationFailurePublishesCaptureProvenance|ResultContextMismatchPublishesCaptureProvenance)\(\)$'
```

Matched 2; both failed only because `failureStage` was `nil`.

After the minimal mapping:

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.processing(BackedNoSpeechPublishesNoSpeechWithCaptureProvenance|FinalizationFailurePublishesCaptureProvenance|ResultContextMismatchPublishesCaptureProvenance)\(\)$'
```

Matched and passed 3/3.

## Required regression gates

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(captureFirst|coordinator|physicalGestureReceipt|cancellation|cancelling|cancelDuringLegacy|processing|smartPipeline|focusedPipeline|cleanupFallback|terminalFailures).*\(\)$'
```

Matched and passed 78/78. This is the prior 75-test guarded selection plus the
three Fix 1 regressions.

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.DictationAccessibility.*\(\)$'
```

Matched and passed 55/55.

```sh
swift test --disable-automatic-resolution --no-parallel --filter StreamingDictationProcessorTests
```

Passed 37/37, including
`emptyFinalTextThrowsStreamingProcessorNoSpeech`, which proves the concrete
production processor emits the typed error consumed by the new coordinator
mapping.

## Build and package evidence

```sh
swift build -c release --product Fleck --disable-automatic-resolution
```

Succeeded: `Build of product 'Fleck' complete! (60.36s)`.

```sh
Scripts/build-fleck-app.sh
```

Succeeded and rebuilt the development-signed bundle at:

`${FLECK_REPO}/.worktrees/fleck-rail-wave4-test-integration/.build/Fleck.app`

```sh
codesign --verify --deep --strict --verbose=4 .build/Fleck.app
codesign -d -r- --verbose=4 .build/Fleck.app
```

Evidence:

- valid on disk;
- satisfies its designated requirement;
- identifier `com.harryjin.fleck`;
- `Signature=adhoc`;
- CDHash `ad3d722f758c4ed45a17955f37fd70818f6b3f6b`.

`file` reports both `Contents/MacOS/Fleck` and
`Contents/SharedSupport/fleck-agent` as Mach-O 64-bit arm64 executables; `lipo
-archs` reports `arm64` for the main executable.

The complete bundle inventory remains the two executables, `Info.plist`, the
Fleck mark, and signature metadata. The model-weight/repository search returned
zero matches for GGUF, GGML, ONNX, Core ML models/packages, safetensors, PyTorch,
TFLite, Hugging Face, and model-repository paths.

## Invariants and diff

- `Package.resolved` SHA-256:
  `ccf30f62d44719e9859266a373bb0219dbbd1e0f73d17667b50d7d87715a09f7`.
- `DictationCapsule.swift` SHA-256:
  `698556bb4cc32f0220a6763acb0463445334576143c4e4a2fe85b32e4c0d06b3`.
- `git diff --check`: clean before commit.
- Product/test diff: 2 files, 74 insertions, 2 deletions.
- Exact product/test paths:
  - `Sources/FleckApp/DictationCoordinator.swift`
  - `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- Packet artifacts:
  - `.superpowers/sdd/2026-08-31-fleck-rail-wave4-test-integration/fix-1-brief.md`
  - `.superpowers/sdd/2026-08-31-fleck-rail-wave4-test-integration/fix-1-report.md`
  - `.superpowers/sdd/2026-08-31-fleck-rail-wave4-test-integration/progress.md`

No app launch, model download, push, PR, GitHub mutation, upload, or external
write was performed.
