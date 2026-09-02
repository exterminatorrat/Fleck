# Packet 1: Integrate Fleck Rail polish with accepted writing intelligence

## 1. Objective and success criteria

Create one local-only integration checkpoint that combines:

- UI/pill base `fbbdb29424eecebc08c41f4f4fb0df1992f8aa82` (`codex/fleck-rail-visual-polish`), including the current general Fleck UI inherited through `2335d2b6147901573ec59f980995d0bf6e83f79b`;
- accepted Wave 3/4 checkpoint `7c03be9d959eba8a032f10b049c977e3bfdfa528` (`codex/local-writing-intelligence-program`), including capture-first dictation reliability, model/catalog/evaluation support, Personal Dictionary settings, and the private quality-corpus workspace.

Success means:

1. The canonical Fleck Rail visual behavior from `fbbdb294` remains intact, including its idle, listening, processing, terminal, hover, dock-mirroring, accessibility, and nonactivation behavior.
2. Wave 3 capture-first guarantees remain intact: synchronous ownership/origin reservation, exact physical key-up handling, cancellation, no late insertion, and toolbar versus global-dictation isolation.
3. Wave 4 Personal Dictionary and private-corpus behavior remains intact.
4. Fleck builds as an arm64 local ad-hoc-signed `.app`, with no model weights bundled.
5. The result is a focused local commit on `codex/fleck-rail-wave4-test-integration`; no GitHub mutation occurs.

## 2. Owned files, interfaces, and constraints

Work only in:

`/Users/harryjin/Fleck/.worktrees/fleck-rail-wave4-test-integration`

The worker owns the integration operation and the minimum semantic conflict resolutions in:

- `AGENTS.md`
- `Package.swift`
- `Sources/FleckApp/DictationCoordinator.swift`
- `Sources/FleckApp/FleckApp.swift`
- `Sources/FleckApp/GlobalHoldShortcut.swift`
- `Sources/FleckApp/SettingsView.swift`
- `Tests/FleckAppTests/DictationAccessibilityTests.swift`
- `Tests/FleckAppTests/DictationCoordinatorTests.swift`
- `Tests/FleckAppTests/GlobalHoldShortcutTests.swift`

Nonconflicting files introduced by the merge are allowed. Do not edit unrelated files. Preserve concurrent and unrelated work; other agents may be inspecting the repository.

Interface rules:

- Preserve `Sources/FleckApp/DictationCapsule.swift` from `fbbdb294` byte-for-byte unless an unexpected compile requirement makes a minimal change unavoidable; report any such change before committing.
- Preserve the rail session/presentation interfaces from the UI base while retaining Wave 3's `physicalGesture`, `recordPhysicalRelease`, and stop-origin semantics.
- Resolve `SettingsView.swift` as a union: keep current UI/rail settings composition and add the accepted Personal Dictionary surface without reverting newer UI.
- Resolve `Package.swift` as a union of all required current-UI, capture-lab, Wave 3, and Wave 4 targets/dependencies. Preserve the existing resolved-package lock.
- Resolve `AGENTS.md` to the exact current repository policy at `/Users/harryjin/Fleck/AGENTS.md`; read it but do not modify that dirty root checkout.

## 3. Required implementation and explicit non-goals

Required:

1. Merge `codex/local-writing-intelligence-program` into this UI-first branch locally with `--no-ff` and resolve conflicts semantically.
2. Keep the pill design and current Fleck UI from the first parent.
3. Restore every accepted Wave 3/4 reliability and product behavior, not merely compilation.
4. Add or adjust only targeted regression tests needed to prove a conflict resolution that existing tests do not already cover.
5. Commit the integrated checkpoint locally with a concise message.

Non-goals:

- No pill redesign, new animations, new model selection, new cleanup behavior, or new product scope.
- No model download, bundling, benchmark execution, microphone claim, or release-readiness claim.
- No edits in `/Users/harryjin/Fleck` or any other worktree.
- No push, pull request, merge on GitHub, or repository-setting change.
- Do not spawn additional agents.

Use a red/green integration loop: establish the conflicts/compile or focused-test failures, make the smallest semantic resolutions, then rerun the required evidence.

## 4. Verification commands and expected evidence

Run from the owned worktree. Use repository wrappers when present and ensure every test filter matches at least one test.

Required focused coverage:

- Fleck Rail visual capture and exact geometry/identity tests.
- `DictationWaveformTests`.
- `GlobalHoldShortcutTests`, including physical-release and transactional ownership cases.
- `DictationCoordinatorTests`, including capture-first, cancellation, routing, dictionary, cleanup fallback, and no-late-output cases.
- `DictationAccessibilityTests`, using bounded individual invocations if the aggregate runner does not print a trustworthy summary.
- Wave 4 Personal Dictionary settings/resolver tests.
- Wave 4 private quality-corpus app, ledger, and schema tests.
- Wave 3 capture, coordinator, streaming, measurement, and receipt groups.
- Complete `FleckCoreTests` and `FleckModelEvaluationTests` suites.

Required build/package evidence:

- `swift build -c release --product Fleck`
- `Scripts/build-fleck-app.sh`
- `codesign --verify --deep --strict` on the produced app.
- Confirm the main executable is arm64.
- Confirm no model-weight extensions or model repositories are bundled.
- `git diff --check`, resolved-package hash comparison, `git status --short --branch`, and exact commit hash.

The handoff must give exact commands, matched/passed counts, failures if any, app path, signature/architecture evidence, diff summary, and commit hash. Do not summarize an incomplete aggregate run as green.

## 5. Authority boundaries and required handoff

Authority is limited to this local integration branch and worktree. A local merge commit is authorized. External writes are not authorized. Do not launch or replace the user's current Fleck app.

Return:

1. What was merged and how each semantic conflict was resolved.
2. Exact changed paths and commit hash.
3. Exact verification evidence and any unverified boundary.
4. The local `.app` path if packaging succeeds.
5. A warning if any rail visual behavior, capture-first guarantee, Personal Dictionary feature, or corpus guarantee could not be preserved.
