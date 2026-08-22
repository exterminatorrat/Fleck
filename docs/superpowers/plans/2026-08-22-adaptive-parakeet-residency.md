# Adaptive Parakeet Residency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adapt Parakeet TDT warm residency to Apple-silicon hardware and live system pressure, then produce a verified model-free Fleck test ZIP for the 8 GB M1 MacBook Pro.

**Architecture:** A pure resource profile and policy compute the maximum safe retention. One shared adaptive inference wrapper owns the real FluidAudio/Core ML lifetime, samples current memory at successful release, and responds to system-pressure events without interrupting active capture.

**Tech Stack:** Swift 6, Swift Testing, Foundation, Darwin Mach VM APIs, Dispatch memory-pressure source, AppKit NSWorkspace notifications, FluidAudio/Core ML, SwiftPM, codesign, ditto.

**Spec:** `docs/superpowers/specs/2026-08-22-adaptive-parakeet-residency-design.md`

## Global Constraints

- Apple Silicon and English only for this candidate test path.
- Apple Speech remains the safe fallback.
- The 8 GiB tier retains for at most 15 seconds only while reclaimable memory is healthy; at-most-four-processor hosts cap at 5 seconds.
- Live pressure may shorten residency but may never load or extend it.
- Cancellation, failure, sleep, model mutation, and termination unload immediately.
- Do not change cleanup behavior or integrate Gemma in these packets.
- Do not bundle model weights in Fleck.app or its ZIP.
- Preserve unrelated work and do not push, merge, open a PR, or change GitHub.
- Each implementation packet runs in the required GPT-5.6 Luna/Max task lane and requires a fresh Sol/High verdict exactly `ship` before the dependent packet starts.

---

### Task 1: Resource profile and pure adaptive policy

**Files:**
- Create: `Sources/FleckApp/DictationResourceProfile.swift`
- Modify: `Sources/FleckApp/DictationRuntimePolicy.swift`
- Create: `Tests/FleckAppTests/DictationResourceProfileTests.swift`
- Modify: `Tests/FleckAppTests/DictationRuntimePolicyTests.swift`

**Interfaces:**
- Produces: `DictationResourceProfile`, `DictationResourceSnapshot`, `DictationMemoryPressure`, `DictationThermalPressure`, `DictationResourceSampling`, and `DictationRuntimePolicy.parakeetRetention(profile:snapshot:) -> Duration`.
- Preserves: `DictationRuntimePolicy.policy(memoryBytes:)`, `warmDuration`, `standbyDuration`, and `targetState(after:activeLease:)` for existing callers.

- [ ] **Step 1: Write fixed-tier failing tests**

Add table-driven tests that assert 8 GiB/8 processors returns 15 seconds,
64 GiB/4 processors returns 5 seconds, 16 GiB/8 processors returns 30 seconds,
24 GiB/10 processors returns 120 seconds, and 32 GiB/12 processors returns 300 seconds
under a normal snapshot with 75% reclaimable memory. Separately assert that an
8 GiB profile at 50% reclaimable memory reduces to 5 seconds.

- [ ] **Step 2: Write dynamic-reduction failing tests**

For a 24 GiB/10-processor profile, assert warning and critical memory pressure,
serious and critical thermal pressure, Low Power Mode, less than 3 GiB, and less
than 25% reclaimable memory return `.zero`. Assert less than 5 GiB or less than
40% returns at most 5 seconds. Assert normal capacity returns 120 seconds.

- [ ] **Step 3: Run the policy tests red**

Run:

```bash
swift test --disable-automatic-resolution --filter 'DictationRuntimePolicy|DictationResourceProfile'
```

Expected: compilation or assertions fail because the new profile and retention
interfaces do not exist.

- [ ] **Step 4: Implement the minimal pure types and decision**

Use binary GiB constants and checked comparisons. Keep the retention decision
side-effect free. The decision order is: fixed constrained tier; pressure,
thermal, and Low Power hard stops; invalid/missing or critical available-memory
threshold; reduced threshold; fixed ceiling.

- [ ] **Step 5: Write sampler failing tests**

Inject page size and VM counters. Assert `free_count` already includes
`speculative_count`, so reclaimable pages are free + inactive + purgeable
without double-counting; reject speculative greater than free. Assert page-sum
and multiplication overflow and a failed Mach provider return `nil`; assert one
host right is reused and deallocated exactly once on success and every failure;
installed memory and active processor count are captured exactly.

- [ ] **Step 6: Implement the production sampler**

Use `ProcessInfo.processInfo.physicalMemory` and `activeProcessorCount` for the
fixed profile. Use `host_page_size` and `host_statistics64(HOST_VM_INFO64)` for
the reclaimable-memory estimate. Map Foundation thermal state into the bounded
project enum. Never shell out to `vm_stat` or poll a command.

- [ ] **Step 7: Run focused and existing runtime tests green**

Run:

```bash
swift test --disable-automatic-resolution --filter 'DictationRuntimePolicy|DictationResourceProfile|LocalDictationRuntime'
git diff --check
```

Expected: all selected tests pass, the pre-existing runtime interface remains
source-compatible, and diff check exits zero.

- [ ] **Step 8: Commit the singular packet**

```bash
git add Sources/FleckApp/DictationResourceProfile.swift \
  Sources/FleckApp/DictationRuntimePolicy.swift \
  Tests/FleckAppTests/DictationResourceProfileTests.swift \
  Tests/FleckAppTests/DictationRuntimePolicyTests.swift
git commit -m "Adapt dictation residency to Mac resources"
```

Expected: the commit contains exactly the four owned paths.

---

### Task 2: Awaitable model-mutation barrier

**Files:**
- Modify: `Sources/FleckApp/EnhancedModelManager.swift`
- Modify: `Sources/FleckApp/ParakeetTDTTestConfiguration.swift`
- Modify: `Sources/FleckApp/ParakeetTDTTestActivation.swift`
- Modify: `Tests/FleckAppTests/EnhancedModelManagerTests.swift`
- Modify: `Tests/FleckAppTests/ParakeetTDTTestConfigurationTests.swift`
- Modify: `Tests/FleckAppTests/ParakeetTDTTestActivationTests.swift`

**Interfaces:**
- Produces: awaitable `@Sendable () async -> Void` cleanup/removal hooks and one `modelMutationWillBegin` hook passed from activation through configuration to both manager mutation boundaries.
- Preserves: manager operation serialization, verified storage ownership, installer state transitions, startup/calibration hooks, and default no-op construction.

- [ ] **Step 1: Write barrier-order failing tests**

Use a controllable async gate. Prove `deleteModel()` reports the mutation hook,
then remains suspended with the selected repository intact until the gate is
released. Prove post-install cleanup likewise does not remove superseded owned
content before the gate releases.

- [ ] **Step 2: Run focused tests red**

Run:

```bash
Scripts/resolve-enhanced-candidate.sh .build-mutation-red \
  swift test --scratch-path .build-mutation-red \
  --disable-automatic-resolution \
  --filter 'EnhancedModelManager|ParakeetTDTTestConfiguration|ParakeetTDTTestActivation'
```

Expected: the async-gate tests fail because the existing callbacks return
before an asynchronous cold-runtime acknowledgement can complete.

- [ ] **Step 3: Implement the minimal awaitable boundary**

Change the two manager hooks to `@Sendable () async -> Void`. Await removal
before entering the detached owned-tree deletion and await cleanup before
entering post-commit cleanup. Add a single `modelMutationWillBegin` hook to the
Parakeet activation/configuration seam and bind it to both manager hooks.
Default construction remains an async no-op.

- [ ] **Step 4: Prove activation/configuration propagation**

Add tests that invoke both bound manager paths and assert the exact injected
hook is awaited once per operation. Preserve existing artifact, manifest,
architecture, and calibration identities.

- [ ] **Step 5: Run focused and candidate checks green**

Run:

```bash
Scripts/resolve-enhanced-candidate.sh .build-mutation-green \
  swift test --scratch-path .build-mutation-green \
  --disable-automatic-resolution \
  --filter 'EnhancedModelManager|ParakeetTDTTestConfiguration|ParakeetTDTTestActivation'
git diff --check
```

Expected: all selected candidate tests pass, Package.resolved is restored, and
the exact six-file diff is clean.

- [ ] **Step 6: Commit the singular packet**

```bash
git add Sources/FleckApp/EnhancedModelManager.swift \
  Sources/FleckApp/ParakeetTDTTestConfiguration.swift \
  Sources/FleckApp/ParakeetTDTTestActivation.swift \
  Tests/FleckAppTests/EnhancedModelManagerTests.swift \
  Tests/FleckAppTests/ParakeetTDTTestConfigurationTests.swift \
  Tests/FleckAppTests/ParakeetTDTTestActivationTests.swift
git commit -m "Await cold runtime before model mutation"
```

Expected: one commit containing exactly the six owned paths.

---

### Task 3: Shared Parakeet residency and live pressure wiring

**Files:**
- Create: `Sources/FleckApp/AdaptiveEnhancedSpeechInference.swift`
- Create: `Sources/FleckApp/DictationResourcePressureMonitor.swift`
- Modify: `Sources/FleckApp/FleckApp.swift`
- Create: `Tests/FleckAppTests/AdaptiveEnhancedSpeechInferenceTests.swift`
- Create: `Tests/FleckAppTests/DictationResourcePressureMonitorTests.swift`
- Modify: `Tests/FleckAppTests/DictationCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 1's resource types/policy and Task 2's awaitable `modelMutationWillBegin` barrier.
- Produces: `AdaptiveEnhancedSpeechInference: EnhancedSpeechInferring` and `DictationResourcePressureMonitor` with explicit `start()` and `stop()` lifecycle.
- Preserves: `EnhancedSpeechCapture`, `SpeechEngineProviding`, verified model paths, Apple Speech fallback, and the existing dictionary/cleanup/insertion pipeline.

- [ ] **Step 1: Write wrapper lifecycle failing tests**

Use an injected fake `EnhancedSpeechInferring`, fake snapshot provider, and
controllable sleeper. Assert a healthy 8 GiB release schedules no more than 15
seconds while a low-memory 8 GiB release unloads immediately; a roomy 24 GiB
release schedules 120 seconds; reacquisition before expiry
cancels the old generation and reuses one underlying load; expiry unloads once.

- [ ] **Step 2: Write pressure and cancellation failing tests**

Assert memory warning while idle unloads immediately. Assert warning during an
active use defers teardown until release. Assert cancel calls underlying cancel
and unload exactly once, never retains the cancelled instance, and the next
capture performs a new cold load. Assert a changed verified repository unloads
the prior repository before loading the new one.

- [ ] **Step 3: Run wrapper tests red in the candidate dependency environment**

Run:

```bash
Scripts/resolve-enhanced-candidate.sh .build-adaptive-red \
  swift test --scratch-path .build-adaptive-red \
  --disable-automatic-resolution \
  --filter AdaptiveEnhancedSpeechInference
```

Expected: compilation fails because the wrapper does not exist. The resolver
must restore the ordinary `Package.resolved` byte-for-byte when it exits.

- [ ] **Step 4: Implement the shared wrapper**

Wrap one existing `FluidEnhancedSpeechInference` owned by the app-level engine
provider. Serialize `load`, `transcribe`, normal release, cancellation, force
cold, and timer expiry on the main actor. Track repository URL, active-use
state, pending force-cold, timer generation, and underlying loaded state. Never
create a second underlying inference object while one is loaded.

- [ ] **Step 5: Write monitor failing tests**

Inject notification centers and a fake memory-pressure source. Assert warning,
critical, thermal, Low Power, sleep, wake, and stop events map exactly. Assert
normal/wake never requests a preload. Assert `stop()` removes observers,
cancels the source, and emits no later callbacks.

- [ ] **Step 6: Implement and wire the monitor**

Use a Dispatch memory-pressure source for `.warning` and `.critical`,
`NSProcessInfoThermalStateDidChange`, `NSProcessInfoPowerStateDidChange`, and
NSWorkspace sleep/wake notifications. In candidate builds, create exactly one
adaptive inference in `DictationRuntime`, inject it through
`DictationSpeechEngineProvider` into every enhanced capture, start monitoring
after construction, and force cold during shutdown. Ordinary builds remain
Apple Speech only and must not link FluidAudio.

- [ ] **Step 7: Add app-wiring regression tests**

Assert two sequential enhanced captures receive the same adaptive inference,
the second capture reuses a warm underlying load, an 8 GiB low-memory snapshot
unloads between captures, standard capture is unchanged, and app shutdown
forces the shared inference cold.

- [ ] **Step 8: Run focused and candidate suites green**

Run:

```bash
Scripts/resolve-enhanced-candidate.sh .build-adaptive-green \
  swift test --scratch-path .build-adaptive-green \
  --disable-automatic-resolution \
  --filter 'AdaptiveEnhancedSpeechInference|DictationResourcePressureMonitor|DictationCoordinator'
Scripts/resolve-enhanced-candidate.sh .build-adaptive-full \
  swift test --scratch-path .build-adaptive-full \
  --disable-automatic-resolution --no-parallel
git diff --check
```

Expected: focused and full candidate tests pass; the ordinary lock file is
restored; diff check exits zero.

- [ ] **Step 9: Commit the singular packet**

```bash
git add Sources/FleckApp/AdaptiveEnhancedSpeechInference.swift \
  Sources/FleckApp/DictationResourcePressureMonitor.swift \
  Sources/FleckApp/FleckApp.swift \
  Tests/FleckAppTests/AdaptiveEnhancedSpeechInferenceTests.swift \
  Tests/FleckAppTests/DictationResourcePressureMonitorTests.swift \
  Tests/FleckAppTests/DictationCoordinatorTests.swift
git commit -m "Keep Parakeet warm only when resources allow"
```

Expected: the commit contains exactly the six owned paths.

---

### Task 4: Build and package the MacBook test ZIP

**Files:**
- No tracked source changes.
- Build artifact: `.build/parakeet-test/Fleck.app`
- ZIP artifact: `.build/parakeet-test/Fleck-Parakeet-Adaptive-arm64.zip`

**Interfaces:**
- Consumes: the accepted Task 3 branch and existing `Scripts/build-parakeet-test-app.sh`.
- Produces: an ad-hoc-signed arm64 local test ZIP containing Fleck.app but no model weights.

- [ ] **Step 1: Verify the accepted source checkpoint**

Run:

```bash
git status --short --branch
git diff --check
git log -3 --oneline
```

Expected: clean accepted adaptive branch, no unmerged entries, and the two
accepted implementation commits above the combined UI/Parakeet base.

- [ ] **Step 2: Build the candidate app**

Run:

```bash
Scripts/build-parakeet-test-app.sh
```

Expected: `.build/parakeet-test/Fleck.app` exists and the ordinary
`Package.resolved` is restored.

- [ ] **Step 3: Verify architecture, signature, and model exclusion**

Run:

```bash
xcrun lipo -archs .build/parakeet-test/Fleck.app/Contents/MacOS/Fleck
xcrun codesign --verify --deep --strict --verbose=2 .build/parakeet-test/Fleck.app
find .build/parakeet-test/Fleck.app -type f \
  \( -iname '*.mlmodelc' -o -iname '*.safetensors' -o -iname '*.gguf' \
     -o -iname '*.onnx' -o -iname '*.bin' \) -print
```

Expected: architecture is `arm64`, codesign exits zero, and the asset scan is
empty.

- [ ] **Step 4: Create and round-trip the ZIP**

Run:

```bash
rm -f .build/parakeet-test/Fleck-Parakeet-Adaptive-arm64.zip
/usr/bin/ditto -c -k --sequesterRsrc --keepParent \
  .build/parakeet-test/Fleck.app \
  .build/parakeet-test/Fleck-Parakeet-Adaptive-arm64.zip
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/fleck-zip-check.XXXXXX")"
/usr/bin/ditto -x -k \
  .build/parakeet-test/Fleck-Parakeet-Adaptive-arm64.zip "$temporary_root"
xcrun codesign --verify --deep --strict --verbose=2 "$temporary_root/Fleck.app"
find "$temporary_root/Fleck.app" -type f \
  \( -iname '*.mlmodelc' -o -iname '*.safetensors' -o -iname '*.gguf' \
     -o -iname '*.onnx' -o -iname '*.bin' \) -print
```

Expected: extraction and strict signature verification pass and the extracted
asset scan is empty. Remove only the exact temporary direct child after
checking its canonical path.

- [ ] **Step 5: Hand off for AirDrop and hands-on testing**

AirDrop the exact ZIP only after its SHA-256 and byte size are recorded. On the
MacBook, extract and launch Fleck, explicitly install Parakeet from Settings,
and test: one cold dictation, three immediate repeats, a 45-second idle repeat,
cancellation, memory pressure during idle, and Apple Speech fallback. Record
the observed first-word behavior, stop-to-text latency, and Fleck/model memory
before claiming the MacBook test passed.

No release-readiness, notarization, redistribution, or Gemma claim is made by
this artifact.
