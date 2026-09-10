# Packet 1D — Fresh review correction

Review verdict: `fix-first` on source/test diff SHA-256 `39b477e2220b6806e7b3e000010d4f31e9a363e2107b5182756d8a1b7746728c`. Parent verification before correction passed 147 default and 79 Enhanced tests. This correction uses the same native Sol/High worker and requires new parent verification and a new fresh Sol review.

Status: corrected and accepted in source `2fb3a1a`; new fresh Sol/High verdict `ship`. Final parent verification passed 161 default and 83 Enhanced tests. See the main 1D plan for exact final diff and evidence. The subsequent bounded typed-source precedence correction also included `StreamingDictationProcessor.swift` and its tests, preserving the original packet ownership.

## 1. Objective and success criteria

Close two diagnostic contract gaps: resolve known terminal outcomes and report the actual failure category on early/recovery paths; ensure decoding and re-encoding cannot export arbitrary stage keys or omit known unavailable stages.

## 2. Ownership and constraints

Own only `Sources/FleckApp/DictationCoordinator.swift`, `Sources/FleckApp/DictationProcessingModels.swift`, `Tests/FleckAppTests/DictationCoordinatorTests.swift`, and `Tests/FleckAppTests/DictationProcessingModelsTests.swift`. Preserve the already verified changes in other files. Parent owns docs. You are not alone in the codebase; preserve and adapt to concurrent work. No source/UI behavior changes, new dependencies, or edits outside these four paths.

## 3. Required implementation and non-goals

Resolve the direct focused-editor reservation failure before clearing capture and publishing its terminal failure. Categorize it as a processing failure and freeze that completed early snapshot. Record processing failure for a rejected/mismatched returned capture context. Record persistence failure for failed smart-capture undo, unsafe focused cancellation when rollback/persistence cannot be confirmed, and History deletion failure during cancellation. Inspect other direct terminal publication paths for the same omission.

Use existing stable categories where they faithfully describe known sites. Do not infer a source failure from an absent pipeline stage. Genuinely unknown evidence remains nil. A small explicit diagnostic-failure argument or per-site metadata assignment is acceptable; preserve existing phase, UI failureStage, recovery action, and cancellation/compensation control flow. Keep actual known source failures classified at their source call sites. Do not freeze successful ambiguity measurements or erase cancellation drain timings.

Normalize decoded `stages` to exactly `Stage.allCases`: discard or reject unknown keys and fill missing known keys with nil. Keep explicit null encoding, original known numeric values, stable metadata, and invalid-clock behavior. Do not introduce a custom parser, new import/export surface, or content-bearing fields.

## 4. Verification

Add regression assertions before product correction and capture red evidence. Cover rejected focused reservation, post-result context rejection, failed undo, unsafe focused cancellation, cancellation History deletion failure, and a hostile-key/missing-key Codable round trip. Reuse existing failure fixtures and deterministic gates. Ensure known source errors remain source failures and unknown metadata is not invented. Tests should demonstrate the defect against the current patch, not fail for unrelated compile issues.

Run the nonempty default diagnostics filter and the exact changed existing recovery tests; save filters, counts and full logs under `.build/dictation-diagnostics-1d`. Parent then independently reruns diagnostics plus existing processing/feedback/recovery selections and the bounded Enhanced regression selection. Keep Swift execution sequential and preserve Package.resolved.

## 5. Authority and handoff

No commits, GitHub writes, model weights, packaging, install, launch, microphone, or device actions. Return changed paths, red/green counts, exact filters/logs, final diff hash, and an explicit release of Swift execution. Parent reviews and verifies, then obtains a new fresh Sol/High `ship` verdict before local acceptance.
