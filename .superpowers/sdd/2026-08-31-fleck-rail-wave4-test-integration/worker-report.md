# Fleck Rail and Wave 3/4 integration worker report

Date: 2026-08-31

Branch: `codex/fleck-rail-wave4-test-integration`

First parent: `fbbdb29424eecebc08c41f4f4fb0df1992f8aa82`

Integrated head: `7c03be9d959eba8a032f10b049c977e3bfdfa528`

Commit: the local merge commit containing this report. Its exact hash is returned
to the parent immediately after `git commit`; a commit cannot embed its own hash.

## Merge and conflict resolution

The integration was started with:

```sh
git merge --no-ff --no-commit 7c03be9d959eba8a032f10b049c977e3bfdfa528
```

It produced five conflicts. They were resolved as follows:

1. `AGENTS.md`: selected the first-parent/current-root policy. The resulting file
   is byte-identical to `/Users/harryjin/Fleck/AGENTS.md` without changing the
   root checkout.
2. `Sources/FleckApp/DictationCoordinator.swift`: kept the Rail's externally
   allocated shortcut session and presentation context, then integrated Wave 3's
   capture-first reservation, pinned `captureContextProvider`, dictionary
   snapshot, synchronous physical-release receipt, immutable first stop origin,
   cancellation drain, and no-late-output behavior. Exact physical long-release
   survives suspended startup; the Rail's legacy no-gesture and hands-free
   startup cancellation paths remain cancellation paths.
3. `Sources/FleckApp/GlobalHoldShortcut.swift`: kept first-parent transactional
   ownership and pointer/keyboard session lifecycle while forwarding
   `physicalGesture`, calling synchronous `recordPhysicalRelease`, and sampling
   typed toolbar/hands-free stop origins at action receipt.
4. `Tests/FleckAppTests/DictationAccessibilityTests.swift`: retained the complete
   Rail geometry, identity, motion, accessibility, nonactivation, and docking
   suite and appended the Wave 4 Personal Dictionary accessibility coverage.
5. `Tests/FleckAppTests/GlobalHoldShortcutTests.swift`: retained the complete
   Rail ownership/editor/pointer suite and added Wave 3 physical gesture and
   stop-origin assertions to the shared spy.

`Package.swift` auto-merged as the required target/dependency union.
`Sources/FleckApp/SettingsView.swift` auto-merged as the current Rail/general UI
plus the accepted full Personal Dictionary settings, import/export, preview,
suggestion, and accessibility surface. `Sources/FleckApp/FleckApp.swift` retains
the first-parent Rail controller composition and now supplies one published
dictionary snapshot per capture.

`Sources/FleckApp/DictationCapsule.swift` was not changed. Its pre-merge and
post-package SHA-256 is
`698556bb4cc32f0220a6763acb0463445334576143c4e4a2fe85b32e4c0d06b3`.

## Red/green integration evidence

The first coordinator compile exposed the incompatible shortcut signatures. The
first focused coordinator runs then exposed these semantic failures:

- arming events had no context;
- capture-stage startup failures had no authoritative failure stage;
- an exact physical release during suspended startup was lost;
- hands-free stop during suspended provider/engine startup did not cancel;
- the legacy Rail no-gesture suspended-start path no longer cancelled.

Minimal resolution changes closed those failures. The directly affected tests
were green individually, including:

- `captureFirstPhysicalReleaseSurvivesSuspendedStartup` 1/1;
- `externallyAllocatedHoldSessionNormalizesModeBeforeArming` 1/1;
- `terminalFailuresIdentifyCaptureOrSaveStageWithoutErrorParsing` 1/1;
- `finishingHandsFreeDuringProviderStartupCancelsWithoutNoSpeech` 1/1;
- `finishingHandsFreeDuringEngineStartupCancelsWithoutNoSpeech` 1/1;
- `shortcutReleaseDuringSuspendedStartCancelsUntilStartReturns` 1/1.

A complete sequential `DictationCoordinatorTests` attempt passed more than 90
tests without assertion failure but stalled at
`concurrentRecoveryActivationPerformsUndoOnlyOnce`; that aggregate was stopped
and is not claimed green. The named test passes 1/1 in isolation. Required
coordinator, routing, capture-first, cancellation, dictionary, cleanup fallback,
measurement, receipt, and no-late-output coverage was subsequently exercised by
the nonempty guarded 75-test selection below.

## Required test evidence

All completed commands exited 0.

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.DictationCapsule.*\(\)$'
```

Matched and passed 3/3. This includes the visual state-matrix capture test 1/1.

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.waveform.*\(\)$'
```

Matched and passed 10/10.

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.DictationAccessibility.*\(\)$'
```

Matched and passed 55/55.

```sh
swift test --disable-automatic-resolution --no-parallel --filter GlobalHoldShortcutTests
```

Passed 40/40, including synchronous release-receipt, queued physical gesture,
hands-free stop-origin, and transactional ownership cases.

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(captureFirst|coordinator|physicalGestureReceipt|cancellation|cancelling|cancelDuringLegacy|processing|smartPipeline|focusedPipeline|cleanupFallback|terminalFailures).*\(\)$'
```

Matched and passed 75/75.

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.(personalDictionarySettings|resolver).*\(\)$'
```

Matched and passed 25/25.

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckAppTests\.LocalWritingCorpusStoreTests/.*\(\)$'
```

Matched and passed 28/28.

```sh
swift test --disable-automatic-resolution --no-parallel --filter StreamingDictationProcessorTests
```

Passed 37/37.

```sh
swift test --disable-automatic-resolution --no-parallel --filter AppleSpeechStreamingAdapterTests
swift test --disable-automatic-resolution --no-parallel --filter DictationProcessingModelsTests
```

Passed 2/2 and 13/13.

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckCoreTests\..*\(\)$'
```

Matched and passed the complete FleckCore suite: 357/357 across 6 suites.

```sh
Scripts/run-nonempty-swift-tests.sh '^FleckModelEvaluationTests\..*\(\)$'
```

Matched and passed the complete FleckModelEvaluation suite: 97/97 across 3
suites.

The nonempty wrappers also verified that `Package.resolved` was unchanged during
their test execution.

## Build and package evidence

```sh
swift build -c release --product Fleck --disable-automatic-resolution
```

Succeeded: `Build of product 'Fleck' complete! (107.11s)`.

```sh
Scripts/build-fleck-app.sh
```

Succeeded and produced:

`/Users/harryjin/Fleck/.worktrees/fleck-rail-wave4-test-integration/.build/Fleck.app`

The package script rebuilt `Fleck` and `fleck-agent`, ad-hoc signed both, verified
the bundle, and installed the staged bundle atomically at the path above.

```sh
codesign --verify --deep --strict --verbose=4 .build/Fleck.app
codesign -d -r- --verbose=4 .build/Fleck.app
```

Evidence:

- valid on disk;
- satisfies its designated requirement;
- identifier `com.harryjin.fleck`;
- `Signature=adhoc`;
- designated requirement `identifier "com.harryjin.fleck"`;
- CDHash `5f26093e8af859252cd88545caf552335d728ea0`.

```sh
file .build/Fleck.app/Contents/MacOS/Fleck .build/Fleck.app/Contents/SharedSupport/fleck-agent
lipo -archs .build/Fleck.app/Contents/MacOS/Fleck
```

Both executables are Mach-O 64-bit arm64; `lipo` reports `arm64` for the main
executable.

The bundle is 29 MB. Its complete non-directory payload is:

- `Contents/Info.plist`
- `Contents/MacOS/Fleck`
- `Contents/Resources/fleck-mark.png`
- `Contents/SharedSupport/fleck-agent`
- `Contents/_CodeSignature/CodeResources`

The model-weight/repository search returned zero matches for GGUF, GGML, ONNX,
Core ML models/packages, safetensors, PyTorch weights, TFLite, Hugging Face, and
model-repository paths. No app was launched and no model was downloaded.

## Protected files and final invariants

- `Package.resolved` SHA-256 before and after:
  `ccf30f62d44719e9859266a373bb0219dbbd1e0f73d17667b50d7d87715a09f7`.
- `DictationCapsule.swift` SHA-256 before and after:
  `698556bb4cc32f0220a6763acb0463445334576143c4e4a2fe85b32e4c0d06b3`.
- Worktree and root `AGENTS.md` SHA-256:
  `8a8de543fdb7131138c22c944091a75e301709879e117f91d2d919ebf689d65f`.
- `git diff --check`: clean.
- Unmerged paths: zero.
- Package-lock diff: empty.

## Exact changed paths

Relative to first parent `fbbdb29424eecebc08c41f4f4fb0df1992f8aa82`,
the integration commit contains these paths:

```text
.superpowers/sdd/2026-08-31-fleck-rail-wave4-test-integration/packet-1-brief.md
.superpowers/sdd/2026-08-31-fleck-rail-wave4-test-integration/progress.md
.superpowers/sdd/2026-08-31-fleck-rail-wave4-test-integration/worker-report.md
ARCHITECTURE.md
IMPLEMENTATION_STATUS.md
Package.swift
README.md
Scripts/run-nonempty-enhanced-tests.sh
Scripts/run-nonempty-swift-tests.sh
Scripts/test-nonempty-swift-test-runners.sh
Scripts/validate-macos.sh
Sources/FleckApp/AdmittedModelDescriptor.swift
Sources/FleckApp/AppleSpeechStreamingAdapter.swift
Sources/FleckApp/DictationCoordinator.swift
Sources/FleckApp/DictationInterfaces.swift
Sources/FleckApp/DictationProcessingModels.swift
Sources/FleckApp/FaithfulCleanupValidator.swift
Sources/FleckApp/FleckApp.swift
Sources/FleckApp/GlobalHoldShortcut.swift
Sources/FleckApp/LocalModelCatalog.swift
Sources/FleckApp/LocalModelCatalogSnapshot.swift
Sources/FleckApp/LocalModelUpdateTransition.swift
Sources/FleckApp/LocalWritingCorpusStore.swift
Sources/FleckApp/PersonalDictionarySettingsViewModel.swift
Sources/FleckApp/PersonalDictionaryTranscriptResolver.swift
Sources/FleckApp/SettingsView.swift
Sources/FleckApp/StreamingDictationProcessor.swift
Sources/FleckCore/CompiledPersonalDictionary.swift
Sources/FleckCore/LocalWritingCorpus.swift
Sources/FleckCore/LocalWritingExposureLedger.swift
Sources/FleckCore/PersonalDictionary.swift
Sources/FleckCore/PersonalDictionaryCodec.swift
Sources/FleckCore/PersonalDictionaryResolver.swift
Sources/FleckCore/PersonalDictionaryStore.swift
Sources/FleckModelEvaluation/CandidateBenchmarkEvidence.swift
Sources/FleckModelEvaluation/LocalModelEvaluationArchive.swift
Sources/FleckModelEvaluation/LocalWritingEvidence.swift
Sources/FleckModelEvaluation/ModelEvaluation.swift
TESTING.md
Tests/FleckAppTests/AdmittedModelDescriptorTests.swift
Tests/FleckAppTests/AppleSpeechStreamingAdapterTests.swift
Tests/FleckAppTests/DictationAccessibilityTests.swift
Tests/FleckAppTests/DictationCoordinatorTests.swift
Tests/FleckAppTests/DictationProcessingModelsTests.swift
Tests/FleckAppTests/FaithfulCleanupValidatorTests.swift
Tests/FleckAppTests/GlobalHoldShortcutTests.swift
Tests/FleckAppTests/IncrementalTranscriptCleanerTests.swift
Tests/FleckAppTests/LocalModelCatalogTests.swift
Tests/FleckAppTests/LocalModelUpdateTransitionTests.swift
Tests/FleckAppTests/LocalWritingCorpusStoreTests.swift
Tests/FleckAppTests/PersonalDictionarySettingsTests.swift
Tests/FleckAppTests/PersonalDictionaryTranscriptResolverTests.swift
Tests/FleckAppTests/StreamingDictationProcessorTests.swift
Tests/FleckCoreTests/CompiledPersonalDictionaryTests.swift
Tests/FleckCoreTests/LocalWritingCorpusTests.swift
Tests/FleckCoreTests/LocalWritingExposureLedgerTests.swift
Tests/FleckCoreTests/PersonalDictionaryCodecTests.swift
Tests/FleckCoreTests/PersonalDictionaryPublicationTests.swift
Tests/FleckCoreTests/PersonalDictionaryResolverTests.swift
Tests/FleckCoreTests/PersonalDictionaryStoreTests.swift
Tests/FleckCoreTests/PersonalDictionaryTests.swift
Tests/FleckCoreTests/PersonalDictionaryTransferTests.swift
Tests/FleckModelEvaluationTests/LocalModelEvaluationArchiveTests.swift
Tests/FleckModelEvaluationTests/LocalWritingCorpusTests.swift
Tests/FleckModelEvaluationTests/LocalWritingEvidenceTests.swift
docs/evaluation/local-writing-evaluation-archive.md
docs/research/2026-08-29-local-writing-model-catalog-primary-sources.md
docs/superpowers/plans/2026-08-29-local-writing-intelligence-program.md
docs/superpowers/plans/2026-08-30-local-writing-intelligence-parallel-execution.md
docs/superpowers/specs/2026-08-29-cached-semantic-routing-and-ambiguity-chooser-design.md
docs/superpowers/specs/2026-08-29-curated-local-model-catalog-design.md
docs/superpowers/specs/2026-08-29-dictation-cleanup-and-sorting-quality-design.md
docs/superpowers/specs/2026-08-29-local-writing-intelligence-program-design.md
docs/superpowers/specs/2026-08-29-packaged-local-writing-admission-design.md
docs/superpowers/specs/2026-08-29-real-local-writing-quality-corpus-design.md
docs/superpowers/specs/2026-08-29-shared-personal-dictionary-design.md
docs/testing/local-dictation-routing-checklist.md
```

Before adding the SDD artifacts, the merge diff was 74 paths, 31,858 insertions,
and 547 deletions. The final commit adds the three SDD task/handoff paths above.

## Authority boundary

This worker made no push, pull request, GitHub change, model download, app launch,
root-checkout edit, or external upload. The verified local app path is ready for
the parent to archive and deliver separately.
