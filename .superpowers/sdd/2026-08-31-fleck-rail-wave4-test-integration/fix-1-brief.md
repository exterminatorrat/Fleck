# Fix 1: Preserve production processing failure semantics

## 1. Objective and success criteria

Correct the production `StreamingDictationProcessor` terminal mapping so that:

- processor `.noSpeech` becomes outcome `.noSpeech` with capture-stage provenance and renders the Rail's truthful amber no-speech state;
- processor finalization/context failures retain an explicit authoritative pipeline stage instead of losing provenance;
- processing-backed regression tests exercise the same path injected by `FleckApp`.

## 2. Owned files, interfaces, and constraints

Own exactly:

- `Sources/FleckApp/DictationCoordinator.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- this packet's progress/report artifacts.

Do not modify the pill, shortcut, Settings, dictionary, corpus, package manifest, lockfile, or unrelated code.

## 3. Required implementation and non-goals

First add a failing processing-backed regression proving `.noSpeech` currently becomes generic failure. Then make the smallest typed-error mapping in `finishProcessingCapture` needed to preserve no-speech outcome and capture-stage provenance. Add focused coverage for processor/context failure provenance only where the existing production path lacks it.

Do not change user-facing copy, redesign error taxonomy, broaden cleanup/model behavior, or refactor the coordinator.

## 4. Verification and expected evidence

- Show the red processing-backed no-speech test before implementation.
- Show the corrected no-speech/provenance tests green.
- Rerun the guarded 75-test capture/coordinator selection.
- Rerun `DictationAccessibility` 55/55 and `StreamingDictationProcessorTests` 37/37.
- Run `git diff --check`, preserve `Package.resolved`, rebuild `.build/Fleck.app`, strict codesign, arm64, and no-weights checks.
- Commit locally and report exact hash/diff.

## 5. Authority and handoff

Work only in the existing isolated branch/worktree. No launch, model download, push, PR, GitHub change, upload, or external write. Return the corrected local commit and exact evidence to the primary for independent verification and a new fresh Sol review.
