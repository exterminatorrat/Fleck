# Local Dictation Model Installation and Real-App Verification Implementation Plan

> **For agentic workers:** Workstream C is a dependency-ordered phase, not one task. Each numbered task below is its own separate user-visible Codex task running GPT-5.6 Luna/Max with a title of `Agent - <singular task>`; the parent Sol task inspects and reruns that task, and a fresh `sol_advisor_sol_reviewer` must return exactly `ship` before the next dependent numbered task. Terra/native subagents are forbidden. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the smallest admitted-model descriptor/catalog, a production-shaped
installation presentation that is empty for ordinary release, and fake-backed
verification of the existing model manager. Then package and launch the actual
development app from the real checkout and separate automated evidence from a
human microphone observation.

**Dependency:** Start only after Workstream B Task 5's parent verification and
fresh Sol ship verdict. The implementation begins from that dependent commit on
top of `4212314398853091fa85e7aec18318b9650e8604`; Workstream A Task 0 has
already restored the four final `898ceae` personal-dictionary files. This
workstream does not cherry-pick or rewrite accepted history.

**Architecture:** `AdmittedModelCatalog` receives either no signed descriptor
or exactly one hardware-appropriate descriptor. No descriptor produces the
built-in Apple state; one descriptor produces one automatic recommendation and
one explicit Install action. `EnhancedModelManager` remains the only downloader
and verifier for the compile-gated candidate path. An adapter maps its existing
manifest/checksum/repair/update/removal work into phase-specific presentation
state. The ordinary app never routes dictation through that adapter.

**Tech Stack:** Swift 6, Foundation, SwiftUI/AppKit, Combine where already used,
CryptoKit and the existing compile-gated manager, Swift Testing, and the
existing `Scripts/build-fleck-app.sh` path. No new dependency, model weight,
resource, downloader, or build script.

## Global constraints

- The ordinary release catalog is empty: Settings shows only
  “Apple Speech — Built in”, “On-device recognition”, and “No custom model is
  installed.” It has no model picker and no Advanced selector.
- Ordinary and compile-gated candidate Settings use the same single
  recommendation/built-in card. Remove the old `Picker`, `ModelConsentView`,
  and `Download Enhanced Model` surfaces; the compile gate changes available
  manager wiring, not the Settings choice model.
- A signed configuration may provide exactly one automatic recommendation after
  hardware/language checks. The UI never chooses among a list and never
  auto-starts an install.
- The descriptor exposes exact model identity, immutable revision, runtime ABI,
  conversion, quantization, license/notices, source, per-file paths,
  checksums, byte counts, total download/installed sizes, languages, and
  architectures.
- Installer presentation has explicit `notInstalled`, byte-valued
  `downloading`, `verifying`, `installing`, `starting`, `calibrating`,
  `installed`, `updateAvailable`, `repairRequired`, `removing`, and actionable
  failure states. It never presents an indeterminate operation as Loading.
- Install, repair, update, and removal are explicit actions. Startup and
  calibration are visible phases and installation does not imply readiness or
  release admission.
- Reuse the existing compile-gated `EnhancedModelManager`,
  `EnhancedModelManifest`, `ModelDownloading`, checksum verification, secure
  resume, repair, update, and removal implementation. Do not add a downloader
  or bypass its path validation.
- Every production and test reference to `EnhancedModelManager`,
  `EnhancedModelManifest`, `ModelDownloading`, or `ModelDownloadResult` is
  enclosed by `#if CLEAN_DICTATION_ENHANCED_CANDIDATE`. Default tests use only
  built-in or non-gated types. A small compile-gated immutable
  `EnhancedModelArtifactIdentity` is built or injected alongside the existing
  manifest; its source repository drives `remoteURL`, and the adapter rejects
  any descriptor/identity mismatch before manager operation. This is not a
  generic model registry.
- Hardware recommendation checks use explicit staging capacity:
  `requiredCapacityBytes = installedBytes + downloadBytes`. A device with
  space above `downloadBytes` but below that required capacity falls back to
  built-in Apple Speech.
- Preserve the existing debug-only `EnhancedModelManager` installer behind
  `CLEAN_DICTATION_ENHANCED_CANDIDATE`; this workstream does not turn its candidate
  route into ordinary-release routing or release evidence.
- The existing FluidInference Parakeet v2 Core ML manifest remains an
  experimental English-only artifact. It is not selected, bundled as evidence,
  or made a normal-release recommendation by this workstream.
- Tests use an injected `ModelDownloading` fake and tiny in-memory byte
  fixtures only. No plan command downloads or writes model weights.
- Preserve Apple Speech and deterministic/Apple cleanup as the only development
  fallbacks. No cloud transcription, transcript upload, hidden network fallback,
  transcript logging, audio persistence, model-driven routing authority, or
  candidate release admission is added by this workstream.
- Preserve the later benchmark/admission lane: ASR candidates are Apple
  control, Qwen3-ASR 0.6B first and 1.7B conditional, Whisper multilingual
  base/small/turbo, Nemotron 3.5 ASR Streaming 0.6B, and Parakeet v2 as an
  English-only control. Cleanup candidates are dictionary baseline,
  deterministic cleanup, Apple Foundation Models, Qwen3.5 0.8B and 2B, and
  Qwen3.5 4B as a lab ceiling only. No candidate wins here.
- Use native macOS Settings structure, semantic colors/styles, keyboard and
  VoiceOver labels/values, and no frequent decorative animation. Keyboard-
  initiated dictation has no animation.
- Installer phases and truthful byte progress are Settings-only. This
  workstream does not own dictation status presentation or modify
  `Sources/FleckApp/DictationCapsule.swift`.
- Use serialized offline-safe commands:
  `swift test --disable-automatic-resolution --no-parallel [--filter ...]`.
- Reuse `./Scripts/build-fleck-app.sh`. The evidence artifact is
  `/Users/harryjin/Fleck/.build/Fleck.app` only when the script runs from
  `/Users/harryjin/Fleck`; an isolated-worktree bundle is not evidence for that
  exact path.
- Preserve and classify the known unrelated `AppStateTests.swift` viewport
  assertion around line 916 (`18.0 >= 48.0`) if it appears on the inherited
  baseline.
- No push, PR, merge, GitHub mutation, model download, model-weight write,
  candidate selection, or release-admission claim is authorized.

## File map

### Create

- `Sources/FleckApp/AdmittedModelDescriptor.swift` — descriptor, hardware
  profile, and exactly-one-or-built-in catalog.
- `Sources/FleckApp/AdmittedModelInstallation.swift` — phase state, installer
  protocol, built-in implementation, and compile-gated manager adapter.
- `Sources/FleckApp/AdmittedModelSettingsPresentation.swift` — pure settings
  presentation and its observable action view model.
- `Tests/FleckAppTests/AdmittedModelDescriptorTests.swift`
- `Tests/FleckAppTests/AdmittedModelInstallationTests.swift`
- `Tests/FleckAppTests/AdmittedModelSettingsPresentationTests.swift`

### Modify

- `Sources/FleckApp/EnhancedModelManager.swift` — expose truthful byte progress
  to the adapter while retaining the existing downloader and verifier.
- `Sources/FleckApp/SettingsView.swift` — render the built-in or one-
  recommendation surface in ordinary builds while retaining the existing
  debug-only installer branch behind its compile flag.
- `Sources/FleckApp/FleckApp.swift` — inject one installer/view model, map
  Settings-only phase state, and remove duplicate model-operation ownership.
- `Tests/FleckAppTests/EnhancedModelManagerTests.swift` — byte-progress and
  adapter lifecycle tests under the existing compile gate.
- `Tests/FleckAppTests/DictationSettingsTests.swift` — built-in,
  recommendation, accessibility, and phase-copy tests.
- `Tests/FleckAppTests/DictationAvailabilityTests.swift` — confirm the
  development availability remains Apple Speech plus safe cleanup when the
  catalog is empty.

### Explicitly excluded

`Package.swift`, `Package.resolved`, `Scripts/build-fleck-app.sh`,
`Sources/FleckApp/Resources/EnhancedModelManifest.json`,
`Sources/FleckApp/DictationCapsule.swift`, `EnhancedSpeechCapture.swift`,
`AppleSpeechCapture.swift`, all streaming/cleanup/coordinator files from
Workstreams A and B, candidate adapters, model weights, and every file outside
this map.

## Interfaces produced

~~~swift
struct AdmittedModelFile: Equatable, Sendable {
  let path: String
  let byteCount: Int64
  let sha256: String
}

enum AdmittedModelRole: Equatable, Sendable {
  case asr
  case cleanup
}

struct AdmittedModelDescriptor: Equatable, Sendable {
  let role: AdmittedModelRole
  let modelID: String
  let revision: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let license: String
  let notices: String
  let source: URL
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
  let languages: [String]
  let architectures: [String]

  var requiredCapacityBytes: Int64 {
    installedBytes + downloadBytes
  }

  var immutableIdentity: AdmittedModelImmutableIdentity { get }
  init(validating raw: Self) throws
}

struct AdmittedModelImmutableIdentity: Equatable, Sendable {
  let sourceRepository: URL
  let modelID: String
  let revision: String
  let license: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
}

enum AdmittedModelDescriptorError: Error, Equatable, Sendable {
  case emptyIdentity
  case emptyRevision
  case emptyLicense
  case unsafePath(String)
  case invalidByteCount
  case invalidChecksum(String)
  case aggregateMismatch
  case emptySupport
}

struct AdmittedHardwareProfile: Equatable, Sendable {
  let architecture: String
  let availableBytes: Int64
  let languages: Set<String>
}

enum AdmittedModelRecommendation: Equatable, Sendable {
  case builtIn
  case recommended(AdmittedModelDescriptor)
}

struct AdmittedModelCatalog: Sendable {
  init(
    signedDescriptor: AdmittedModelDescriptor?,
    hardware: AdmittedHardwareProfile
  )
  func recommendation() -> AdmittedModelRecommendation
}
~~~

The installer seam is:

~~~swift
enum AdmittedModelInstallPhase: Equatable, Sendable {
  case builtIn
  case notInstalled
  case downloading(receivedBytes: Int64, totalBytes: Int64)
  case verifying
  case installing
  case starting
  case calibrating
  case installed
  case updateAvailable
  case repairRequired(message: String)
  case removing
  case failed(message: String)
}

struct AdmittedModelInstallationSnapshot: Equatable, Sendable {
  let recommendation: AdmittedModelRecommendation
  let phase: AdmittedModelInstallPhase
  let lastError: String?
}

@MainActor
protocol AdmittedModelInstalling: AnyObject {
  var snapshot: AdmittedModelInstallationSnapshot { get }
  var updates: AsyncStream<AdmittedModelInstallationSnapshot> { get }
  func refresh() async
  func install() async
  func cancel()
  func repair() async
  func update() async
  func remove() async
}
~~~

Under `#if CLEAN_DICTATION_ENHANCED_CANDIDATE`, keep the manager seam small and
immutable. Build or inject this value at the same point as the existing
`EnhancedModelManifest`; do not create a registry or a second manifest:

~~~swift
#if CLEAN_DICTATION_ENHANCED_CANDIDATE
struct EnhancedModelArtifactIdentity: Equatable, Sendable {
  let sourceRepository: URL
  let modelID: String
  let revision: String
  let license: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
}

enum AdmittedModelArtifactMismatch: Error, Equatable {
  case immutableIdentityMismatch
}

enum AdmittedModelArtifactBinding {
  static func validate(
    descriptor: AdmittedModelDescriptor,
    artifact: EnhancedModelArtifactIdentity
  ) throws {
    let expected = AdmittedModelImmutableIdentity(
      sourceRepository: artifact.sourceRepository,
      modelID: artifact.modelID,
      revision: artifact.revision,
      license: artifact.license,
      runtimeABI: artifact.runtimeABI,
      conversion: artifact.conversion,
      quantization: artifact.quantization,
      files: artifact.files,
      downloadBytes: artifact.downloadBytes,
      installedBytes: artifact.installedBytes
    )
    guard descriptor.immutableIdentity == expected else {
      throw AdmittedModelArtifactMismatch.immutableIdentityMismatch
    }
  }
}
#endif
~~~

The existing manager receives `artifactIdentity` alongside its manifest and
constructs each download URL from `artifactIdentity.sourceRepository`,
`resolve`, and the immutable revision. The adapter initializer runs
`AdmittedModelArtifactBinding.validate` before calling any manager operation;
on mismatch construction throws before transport, and the Settings boundary
maps that actionable error to a failed presentation without starting an
operation.

## Task 1: Define the admitted descriptor and one-recommendation catalog

**Separate user-visible task title:** `Agent - admitted model catalog`

**Dependency:** Begin only after Workstream B Task 5's fresh Sol `ship` gate.

**Owned files:** Create
`Sources/FleckApp/AdmittedModelDescriptor.swift` and
`Tests/FleckAppTests/AdmittedModelDescriptorTests.swift`.

**Excluded files:** All other Workstream C paths, including
`EnhancedModelManager.swift`, `SettingsView.swift`, `FleckApp.swift`, package
files, manifests, and model resources.

**Consumes:** Signed-app configuration input supplied by the caller and a
deterministic `AdmittedHardwareProfile`.

**Produces:** The descriptor, file identity, hardware profile, recommendation,
and catalog interfaces above.

### TDD red

- [ ] **Step 1: Write exact catalog tests.**

~~~swift
@Test func ordinaryConfigurationShowsBuiltInState() {
  let catalog = AdmittedModelCatalog(
    signedDescriptor: nil,
    hardware: .init(
      architecture: "arm64",
      availableBytes: 16_000_000_000,
      languages: ["en-US"]
    )
  )
  #expect(catalog.recommendation() == .builtIn)
}

@Test func admittedConfigurationProducesExactlyOneRecommendation() {
  let descriptor = TestDescriptors.admittedASR
  let catalog = AdmittedModelCatalog(
    signedDescriptor: descriptor,
    hardware: .init(
      architecture: "arm64",
      availableBytes: descriptor.requiredCapacityBytes + 1,
      languages: ["en-US"]
    )
  )
  #expect(catalog.recommendation() == .recommended(descriptor))
}

@Test func unsupportedHardwareFallsBackToBuiltIn() {
  let catalog = AdmittedModelCatalog(
    signedDescriptor: TestDescriptors.admittedASR,
    hardware: .init(
      architecture: "x86_64",
      availableBytes: 1,
      languages: ["zh-CN"]
    )
  )
  #expect(catalog.recommendation() == .builtIn)
}

@Test func spaceAboveDownloadBytesButBelowStagingRequirementFallsBackToBuiltIn() {
  let descriptor = TestDescriptors.neutralAdmitted
  let availableBytes = descriptor.downloadBytes + 1
  #expect(availableBytes > descriptor.downloadBytes)
  #expect(availableBytes < descriptor.requiredCapacityBytes)
  let catalog = AdmittedModelCatalog(
    signedDescriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      availableBytes: availableBytes,
      languages: [descriptor.languages[0]]
    )
  )
  #expect(catalog.recommendation() == .builtIn)
}

@Test func invalidSignedDescriptorInputsAreRejected() {
  let valid = TestDescriptors.neutralAdmitted
  #expect(throws: AdmittedModelDescriptorError.emptyIdentity) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, modelID: ""))
  }
  #expect(throws: AdmittedModelDescriptorError.emptyRevision) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, revision: ""))
  }
  #expect(throws: AdmittedModelDescriptorError.emptyLicense) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, license: ""))
  }
  #expect(throws: AdmittedModelDescriptorError.unsafePath("../escape.bin")) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(
      valid,
      files: [ .init(path: "../escape.bin", byteCount: 4, sha256: String(repeating: "a", count: 64)) ],
      downloadBytes: 4,
      installedBytes: 4
    ))
  }
  #expect(throws: AdmittedModelDescriptorError.invalidByteCount) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, downloadBytes: -1))
  }
  #expect(throws: AdmittedModelDescriptorError.invalidChecksum("abc")) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(
      valid,
      files: [ .init(path: "model.bin", byteCount: 4, sha256: "abc") ],
      downloadBytes: 4,
      installedBytes: 4
    ))
  }
  #expect(throws: AdmittedModelDescriptorError.aggregateMismatch) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, installedBytes: 1))
  }
  #expect(throws: AdmittedModelDescriptorError.emptySupport) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, languages: [], architectures: []))
  }
}
~~~

- [ ] **Step 2: Run the red command.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelDescriptorTests
~~~

Expected failure: the descriptor, recommendation, catalog, and test fixture
types do not exist.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Implement the single-descriptor rule.**

~~~swift
struct AdmittedModelCatalog: Sendable {
  private let signedDescriptor: AdmittedModelDescriptor?
  private let hardware: AdmittedHardwareProfile

  init(
    signedDescriptor: AdmittedModelDescriptor?,
    hardware: AdmittedHardwareProfile
  ) {
    self.signedDescriptor = signedDescriptor
    self.hardware = hardware
  }

  func recommendation() -> AdmittedModelRecommendation {
    guard let descriptor = signedDescriptor,
          descriptor.architectures.contains(hardware.architecture),
          descriptor.languages.contains(where: hardware.languages.contains),
          hardware.availableBytes >= descriptor.requiredCapacityBytes else {
      return .builtIn
    }
    return .recommended(descriptor)
  }
}
~~~

Add validation at the signed boundary, not in the view:

~~~swift
extension AdmittedModelDescriptor {
  init(validating raw: Self) throws {
    guard !raw.modelID.isEmpty else { throw AdmittedModelDescriptorError.emptyIdentity }
    guard !raw.revision.isEmpty else { throw AdmittedModelDescriptorError.emptyRevision }
    guard !raw.license.isEmpty else { throw AdmittedModelDescriptorError.emptyLicense }
    guard !raw.languages.isEmpty, !raw.architectures.isEmpty else {
      throw AdmittedModelDescriptorError.emptySupport
    }
    guard raw.downloadBytes > 0,
          raw.installedBytes > 0,
          raw.files.allSatisfy({ $0.byteCount > 0 }) else {
      throw AdmittedModelDescriptorError.invalidByteCount
    }
    guard raw.files.reduce(0) { $0 + $1.byteCount } == raw.downloadBytes,
          raw.installedBytes >= raw.downloadBytes else {
      throw AdmittedModelDescriptorError.aggregateMismatch
    }
    for file in raw.files {
      guard !file.path.hasPrefix("/"),
            !file.path.split(separator: "/").contains("..") else {
        throw AdmittedModelDescriptorError.unsafePath(file.path)
      }
      guard file.sha256.count == 64,
            file.sha256.allSatisfy("0123456789abcdefABCDEF".contains) else {
        throw AdmittedModelDescriptorError.invalidChecksum(file.sha256)
      }
    }
    self = raw
  }

  var immutableIdentity: AdmittedModelImmutableIdentity {
    .init(sourceRepository: source, modelID: modelID, revision: revision,
          license: license, runtimeABI: runtimeABI, conversion: conversion,
          quantization: quantization, files: files,
          downloadBytes: downloadBytes, installedBytes: installedBytes)
  }
}
~~~

Have the signed-configuration path call the throwing initializer below before
constructing this immutable value. `TestDescriptors.make` is a test-only helper
that starts from one valid neutral descriptor and applies the named override;
the test cases above cover empty identity/revision/license, unsafe paths,
negative byte counts, non-64-hex checksums, aggregate mismatches, and empty
support sets. Do not accept an array, picker index, or fallback descriptor. The
ordinary constructor passes nil.

- [ ] **Step 4: Run green, inspect, and commit.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelDescriptorTests
git diff --check
git add Sources/FleckApp/AdmittedModelDescriptor.swift Tests/FleckAppTests/AdmittedModelDescriptorTests.swift
git commit -m "feat: define admitted model catalog"
~~~

Expected: all tests pass, and only the two Task 1 paths differ. The parent
reruns the command and obtains a fresh Sol ship verdict before Workstream C
Task 2.

## Task 2: Reuse the existing manager through a truthful fake-backed installer

**Separate user-visible task title:** `Agent - admitted model installer`

**Dependency:** Begin only after Workstream C Task 1's parent rerun and fresh
Sol `ship` gate.

**Owned files:** Create
`Sources/FleckApp/AdmittedModelInstallation.swift` and
`Tests/FleckAppTests/AdmittedModelInstallationTests.swift`; modify only
`Sources/FleckApp/EnhancedModelManager.swift` and
`Tests/FleckAppTests/EnhancedModelManagerTests.swift`.

**Excluded files:** `SettingsView.swift`, `FleckApp.swift`, all descriptor
catalog code except Task 1 interfaces, package files, resources, the manifest,
audio/streaming/cleanup/coordinator files, and all model-weight paths.

**Consumes:** Task 1 `AdmittedModelDescriptor`; under
`CLEAN_DICTATION_ENHANCED_CANDIDATE`, the existing `EnhancedModelManifest`,
`EnhancedModelManager`, `ModelDownloading`, `ModelDownloadResult`, and its
checksum/path/repair/update/remove operations. Default builds consume only the
built-in installer seam.

**Produces:** `AdmittedModelInstallPhase`,
`AdmittedModelInstallationSnapshot`, `AdmittedModelInstalling`,
`BuiltInAdmittedModelInstaller`, `FailedAdmittedModelInstaller`, and the compile-gated
`EnhancedModelManagerInstaller`.

### TDD red

- [ ] **Step 1: Add fake transport and lifecycle tests.** The fixture bytes
  are short `Data` values, not model weights.

~~~swift
@Test @MainActor
func defaultBuildUsesBuiltInInstallerWithoutManagerReference() async {
  let installer = BuiltInAdmittedModelInstaller()
  await installer.install()
  #expect(installer.snapshot.phase == .builtIn)
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test @MainActor
func fakeInstallReportsBytesThenVerificationStartupAndCalibration() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: Data("fixture".utf8))
  let manager = EnhancedModelManager(
    modelRootURL: TestPaths.temporaryDirectory(),
    manifest: TestManifests.tiny,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    candidateEnabled: true,
    capacityProvider: { Int64.max },
    architectureProvider: { true },
    transport: transport
  )
  let installer = try! EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { },
    calibrate: { }
  )

  await installer.install()

  #expect(installer.phaseHistory.contains(
    .downloading(receivedBytes: 0, totalBytes: descriptor.downloadBytes)
  ))
  #expect(installer.phaseHistory.contains(.verifying))
  #expect(installer.phaseHistory.contains(.starting))
  #expect(installer.phaseHistory.contains(.calibrating))
  #expect(installer.snapshot.phase == .installed)
}

@Test @MainActor
func checksumFailureBecomesActionableRepairState() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let manager = TestManagers.managerWithWrongFixtureChecksum(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor)
  )
  let installer = try! EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { },
    calibrate: { }
  )
  await installer.install()
  guard case .repairRequired(let message) = installer.snapshot.phase else {
    Issue.record("Expected repair state")
    return
  }
  #expect(message.contains("checksum"))
}

@Test @MainActor
func descriptorArtifactMismatchFailsBeforeTransport() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: Data("fixture".utf8))
  let manager = TestManagers.manager(
    descriptor: descriptor,
    transport: transport,
    artifactIdentity: TestArtifacts.identityWith(
      revision: "different-revision"
    )
  )
  #expect(throws: AdmittedModelArtifactMismatch.immutableIdentityMismatch) {
    _ = try EnhancedModelManagerInstaller(
      manager: manager,
      descriptor: descriptor,
      startup: { },
      calibrate: { }
    )
  }
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func immutableArtifactMismatchesAreRejectedBeforeTransport() throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let valid = TestArtifacts.identity(matching: descriptor)
  let mismatches = [
    TestArtifacts.identity(valid, sourceRepository: URL(string: "https://example.invalid/other")!),
    TestArtifacts.identity(valid, modelID: "different-model"),
    TestArtifacts.identity(valid, revision: "different-revision"),
    TestArtifacts.identity(valid, license: "different-license"),
    TestArtifacts.identity(valid, runtimeABI: "different-runtime"),
    TestArtifacts.identity(valid, conversion: "different-conversion"),
    TestArtifacts.identity(valid, quantization: "different-quantization"),
    TestArtifacts.identity(valid, files: [ .init(path: "other.bin", byteCount: 4, sha256: String(repeating: "a", count: 64)) ]),
    TestArtifacts.identity(valid, files: [ .init(path: valid.files[0].path, byteCount: valid.files[0].byteCount, sha256: String(repeating: "b", count: 64)) ]),
    TestArtifacts.identity(valid, files: [ .init(path: valid.files[0].path, byteCount: valid.files[0].byteCount + 1, sha256: valid.files[0].sha256) ]),
    TestArtifacts.identity(valid, downloadBytes: valid.downloadBytes + 1),
    TestArtifacts.identity(valid, installedBytes: valid.installedBytes + 1)
  ]
  for artifact in mismatches {
    #expect(throws: AdmittedModelArtifactMismatch.immutableIdentityMismatch) {
      try AdmittedModelArtifactBinding.validate(descriptor: descriptor, artifact: artifact)
    }
  }
}

@Test @MainActor
func installerUpdatesExposeBytesBeforeCompletion() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(
    bytes: Data("fixture".utf8),
    progressSequence: [4, 8],
    pausesAfterFirstProgress: true
  )
  let manager = TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    transport: transport
  )
  let installer = try! EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { },
    calibrate: { }
  )
  let recorder = ProgressSnapshotRecorder()
  let updates = Task {
    for await snapshot in installer.updates {
      if case .downloading(let receivedBytes, let totalBytes) = snapshot.phase,
         receivedBytes > 0 {
        await recorder.append((receivedBytes, totalBytes))
      }
    }
  }
  let install = Task { await installer.install() }
  await transport.waitUntilFirstProgress()
  await recorder.waitUntilCount(1)
  #expect(await recorder.values == [
    (4, descriptor.downloadBytes)
  ])
  await transport.releaseProgress()
  await install.value
  await recorder.waitUntilCount(2)
  #expect(await recorder.values == [
    (4, descriptor.downloadBytes),
    (8, descriptor.downloadBytes)
  ])
  let receivedBytes = await recorder.values.map(\.0)
  #expect(receivedBytes == receivedBytes.sorted())
  updates.cancel()
}
#endif
~~~

`ModelDownloadingProbe` requires the exact artifact identity through its
`TestManagers.manager(descriptor:artifactIdentity:transport:)` helper, emits progress values
`4` and `8` with `totalBytes == descriptor.downloadBytes`, pauses after `4`,
and does not complete until the test releases the gate. The actor-backed
`ProgressSnapshotRecorder.waitUntilCount(_:)` lets the test assert the first
snapshot while installation is still blocked, then assert monotonic bytes and
the exact total after the second snapshot. The only exception is the deliberate
descriptor-mismatch fixture, which passes a different immutable identity to
prove zero transport calls. `TestManagers.manager(descriptor:artifactIdentity:transport:)`
has no default identity and constructs `EnhancedModelManager` with the supplied
artifact identity; normal fixtures pass
`TestArtifacts.identity(matching: descriptor)`, while the checksum fixture
helper takes the same explicit identity.

- [ ] **Step 2: Run the red commands.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelInstallationTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelInstallationTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter EnhancedModelManagerTests
~~~

Expected failure: the phase protocol, byte-progress bridge, installer adapter,
and fake lifecycle assertions do not exist. The candidate command remains
offline because its transport is injected.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Expose byte progress without replacing manager work.** Under
  `CLEAN_DICTATION_ENHANCED_CANDIDATE`, add a small
  `EnhancedModelByteProgress` value and
  `@Published private(set) var byteProgress` to the existing manager. Update it
  from the existing
  `updateProgress(completedBytes:receivedBytes:operationID:)` callback; clear it
  when entering verification, installation, ready, removal, repair, or
  not-installed states. Keep `ModelDownloading`,
  `URLSessionModelDownloader`, manifest validation, checksum verification,
  staging, secure resume, and filesystem ownership unchanged.

~~~swift
#if CLEAN_DICTATION_ENHANCED_CANDIDATE
struct EnhancedModelByteProgress: Equatable, Sendable {
  let receivedBytes: Int64
  let totalBytes: Int64
}

final class EnhancedModelManager: ObservableObject {
  private let artifactIdentity: EnhancedModelArtifactIdentity
  @Published private(set) var byteProgress: EnhancedModelByteProgress?

  init(
    manifest: EnhancedModelManifest,
    artifactIdentity: EnhancedModelArtifactIdentity,
    /* existing manager dependencies */
  ) {
    self.artifactIdentity = artifactIdentity
  }

  var admittedArtifactIdentity: EnhancedModelArtifactIdentity { artifactIdentity }

  func remoteURL(for file: EnhancedModelFile) -> URL {
    artifactIdentity.sourceRepository
      .appendingPathComponent("resolve")
      .appendingPathComponent(artifactIdentity.revision)
      .appendingPathComponent(file.path)
  }
}
#endif
~~~

The existing embedded manager construction supplies its immutable artifact
identity beside the manifest. The adapter never substitutes a descriptor for
that value, and the URL root no longer hard-codes a candidate repository. Its
verified required-capacity calculation remains authoritative for install
admission; the catalog's `installedBytes + downloadBytes` check is the signed
configuration equivalent.

- [ ] **Step 4: Add the two installer implementations.**

~~~swift
@MainActor
final class BuiltInAdmittedModelInstaller: AdmittedModelInstalling {
  private(set) var snapshot: AdmittedModelInstallationSnapshot
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>
  private let continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation

  init() {
    var continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation!
    updates = AsyncStream { continuation = $0 }
    self.continuation = continuation
    snapshot = .init(
      recommendation: .builtIn,
      phase: .builtIn,
      lastError: nil
    )
    continuation.yield(snapshot)
  }

  func refresh() async {}
  func install() async {}
  func cancel() {}
  func repair() async {}
  func update() async {}
  func remove() async {}
}

@MainActor
final class FailedAdmittedModelInstaller: AdmittedModelInstalling {
  let snapshot: AdmittedModelInstallationSnapshot
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>

  init(message: String) {
    let initial = AdmittedModelInstallationSnapshot(
      recommendation: .builtIn,
      phase: .failed(message: message),
      lastError: message
    )
    snapshot = initial
    updates = AsyncStream { continuation in continuation.yield(initial) }
  }

  func refresh() async {}
  func install() async {}
  func cancel() {}
  func repair() async {}
  func update() async {}
  func remove() async {}
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@MainActor
final class EnhancedModelManagerInstaller: AdmittedModelInstalling {
  let manager: EnhancedModelManager
  let descriptor: AdmittedModelDescriptor
  private let startup: @MainActor () async throws -> Void
  private let calibrate: @MainActor () async throws -> Void
  private(set) var snapshot: AdmittedModelInstallationSnapshot
  private(set) var phaseHistory: [AdmittedModelInstallPhase] = []
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>
  private let continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation
  private var progressSubscription: AnyCancellable?
  private var operationID: UUID?
  private var lastReceivedBytes: Int64 = 0

  init(
    manager: EnhancedModelManager,
    descriptor: AdmittedModelDescriptor,
    startup: @escaping @MainActor () async throws -> Void,
    calibrate: @escaping @MainActor () async throws -> Void
  ) throws {
    try AdmittedModelArtifactBinding.validate(
      descriptor: descriptor,
      artifact: manager.admittedArtifactIdentity
    )
    var continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation!
    updates = AsyncStream { continuation = $0 }
    self.continuation = continuation
    self.manager = manager
    self.descriptor = descriptor
    self.startup = startup
    self.calibrate = calibrate
    self.snapshot = .init(
      recommendation: .recommended(descriptor),
      phase: .notInstalled,
      lastError: nil
    )
    continuation.yield(snapshot)
  }

  private func publish(_ next: AdmittedModelInstallationSnapshot) {
    snapshot = next
    phaseHistory.append(next.phase)
    continuation.yield(next)
  }

  private func beginProgressForwarding() {
    operationID = UUID()
    lastReceivedBytes = 0
    progressSubscription = manager.$byteProgress
      .compactMap { $0 }
      .receive(on: RunLoop.main)
      .sink { [weak self] progress in
        guard let self,
              self.operationID != nil,
              progress.totalBytes == self.descriptor.downloadBytes,
              progress.receivedBytes >= self.lastReceivedBytes else { return }
        self.lastReceivedBytes = progress.receivedBytes
        self.publish(.init(
          recommendation: .recommended(self.descriptor),
          phase: .downloading(
            receivedBytes: progress.receivedBytes,
            totalBytes: progress.totalBytes
          ),
          lastError: nil
        ))
      }
  }

  private func endProgressForwarding() {
    operationID = nil
    progressSubscription?.cancel()
    progressSubscription = nil
  }

  private func runManagerOperation(
    _ operation: @escaping @MainActor () async throws -> Void
  ) async {
    beginProgressForwarding()
    publish(.init(
      recommendation: .recommended(descriptor),
      phase: .downloading(receivedBytes: 0, totalBytes: descriptor.downloadBytes),
      lastError: nil
    ))
    defer { endProgressForwarding() }
    do {
      try await operation()
      // Existing manager state is mapped to verifying/installing/ready here.
    } catch {
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .failed(message: String(describing: error)),
        lastError: String(describing: error)
      ))
    }
  }

  func install() async {
    await runManagerOperation { try await manager.download() }
  }

  func repair() async {
    await runManagerOperation { try await manager.repair() }
  }

  func update() async {
    await runManagerOperation { try await manager.update() }
  }

  func refresh() async
  func cancel()
  func remove() async
}
#endif
~~~

Map manager states to the phase enum. On install/repair/update, call only the
manager's existing method, forward `byteProgress` as
`downloading(receivedBytes:totalBytes:)`, then run injected startup and
calibration closures as separate phases. On checksum, size, path, capacity,
transport, startup, or calibration failure, set an actionable `failed` or
`repairRequired` message and retain the safe previous installation when the
manager does. Cancellation cancels the one operation task and never reports
installed. Removal calls only `manager.deleteModel()`. The ordinary release
uses `BuiltInAdmittedModelInstaller` and cannot reach the manager.

- [ ] **Step 5: Run green and broader checks.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelInstallationTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelInstallationTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter EnhancedModelManagerTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAvailabilityTests
~~~

Expected: all commands pass when the candidate package cache is present; no
command performs a network transfer or writes model weights. If the candidate
package cache is unavailable, report that environment prerequisite separately
from the default-build result.

- [ ] **Step 6: Inspect and commit.**

~~~bash
git diff --check
rg -n "URLSessionModelDownloader\\(\\)|ModelDownloading|byteProgress|verifyRepository|deleteModel" Sources/FleckApp/EnhancedModelManager.swift Sources/FleckApp/AdmittedModelInstallation.swift
git add Sources/FleckApp/EnhancedModelManager.swift Sources/FleckApp/AdmittedModelInstallation.swift Tests/FleckAppTests/EnhancedModelManagerTests.swift Tests/FleckAppTests/AdmittedModelInstallationTests.swift
git commit -m "feat: expose admitted model installation phases"
~~~

Expected: the scan shows reuse of the existing transport/verification path and
no second downloader. The parent runs both default and candidate-gated checks,
inspects the complete diff, and obtains a fresh Sol ship verdict before
Workstream C Task 3.

## Task 3: Present one recommendation or the built-in state in Settings

**Separate user-visible task title:** `Agent - admitted model Settings`

**Dependency:** Begin only after Workstream C Task 2's parent rerun and fresh
Sol `ship` gate.

**Owned files:** Create
`Sources/FleckApp/AdmittedModelSettingsPresentation.swift` and
`Tests/FleckAppTests/AdmittedModelSettingsPresentationTests.swift`; modify only
`Sources/FleckApp/SettingsView.swift`, `Sources/FleckApp/FleckApp.swift`,
`Tests/FleckAppTests/DictationSettingsTests.swift`, and
`Tests/FleckAppTests/DictationAvailabilityTests.swift`.

**Excluded files:** All manager/downloader implementation beyond Workstream C Task 2,
`Package.swift`, `Scripts/build-fleck-app.sh`, resources/manifests, every
audio/streaming/cleanup/coordinator file, `Sources/FleckApp/DictationCapsule.swift`,
and candidate model files.

**Consumes:** Task 1 catalog/recommendation, Task 2 installer snapshot/action
methods, and the existing native Settings structure.

**Produces:** `AdmittedModelSettingsPresentation`,
`AdmittedModelSettingsViewModel`, exactly one Settings card, and phase-specific
Settings/error copy.

### TDD red

- [ ] **Step 1: Write presentation tests before changing Settings.**

~~~swift
@Test func builtInStateHasNoInstallActionOrPicker() {
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .builtIn,
      phase: .builtIn,
      lastError: nil
    )
  )
  #expect(presentation.title == "Apple Speech — Built in")
  #expect(presentation.primaryAction == nil)
  #expect(presentation.showsModelPicker == false)
  #expect(presentation.detail.contains("No custom model is installed"))
}

@Test func recommendationHasExplicitInstallAndExactMetadata() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(descriptor),
      phase: .notInstalled,
      lastError: nil
    )
  )
  #expect(presentation.primaryAction == .install)
  #expect(presentation.identity == descriptor.modelID)
  #expect(presentation.revision == descriptor.revision)
  #expect(presentation.downloadBytes == descriptor.downloadBytes)
  #expect(presentation.installedBytes == descriptor.installedBytes)
  #expect(presentation.checksums == descriptor.files.map(\.sha256))
}

@Test func downloadingUsesTruthfulByteProgressAndVoiceOverValue() {
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(TestDescriptors.tinyAdmittedASR),
      phase: .downloading(receivedBytes: 25, totalBytes: 100),
      lastError: nil
    )
  )
  #expect(presentation.progress == 0.25)
  #expect(presentation.progressAccessibilityValue == "25 of 100 bytes")
  #expect(presentation.primaryAction == .cancel)
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test @MainActor
func invalidSignedDescriptorIsCaughtAsNonOperatingBuiltInFailure() {
  let installer: any AdmittedModelInstalling
  do {
    let raw = TestDescriptors.make(TestDescriptors.neutralAdmitted, modelID: "")
    _ = try AdmittedModelDescriptor(validating: raw)
    Issue.record("Expected signed descriptor validation to fail")
    return
  } catch {
    installer = FailedAdmittedModelInstaller(message: String(describing: error))
  }
  #expect(installer.snapshot.recommendation == .builtIn)
  guard case .failed(let message) = installer.snapshot.phase else {
    Issue.record("Expected a failed non-operating Settings snapshot")
    return
  }
  #expect(!message.isEmpty)
  let presentation = AdmittedModelSettingsPresentation(snapshot: installer.snapshot)
  #expect(presentation.detail.contains(message))
}

@Test @MainActor
func artifactBindingFailureIsCaughtBeforeTransportAndKeepsAppleFallback() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: Data("fixture".utf8))
  let manager = TestManagers.manager(
    descriptor: descriptor,
    transport: transport,
    artifactIdentity: TestArtifacts.identityWith(revision: "wrong")
  )
  let installer: any AdmittedModelInstalling
  do {
    installer = try EnhancedModelManagerInstaller(
      manager: manager,
      descriptor: descriptor,
      startup: { },
      calibrate: { }
    )
  } catch {
    installer = FailedAdmittedModelInstaller(message: String(describing: error))
  }
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(transport.downloadCalls == 0)
  #expect(installer.snapshot.lastError != nil)
}
#endif
~~~

- [ ] **Step 2: Run the red command.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelSettingsPresentationTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelSettingsPresentationTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter DictationSettingsTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter DictationAvailabilityTests
~~~

Expected failure: the presentation, action, snapshot mapping, and view-model
symbols do not exist.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Implement pure phase presentation.**

~~~swift
enum AdmittedModelSettingsAction: Equatable {
  case install, cancel, repair, update, remove
}

struct AdmittedModelSettingsPresentation: Equatable {
  let title: String
  let detail: String
  let identity: String?
  let revision: String?
  let license: String?
  let checksums: [String]
  let downloadBytes: Int64?
  let installedBytes: Int64?
  let progress: Double?
  let progressAccessibilityValue: String?
  let primaryAction: AdmittedModelSettingsAction?
  let showsModelPicker: Bool
}
~~~

Map every phase to finite title/detail/action text. Use exact byte counts, exact
identity/revision/license/checksum strings, and stable accessibility labels.
Use no indefinite Loading text and no automatic action on view appearance.

- [ ] **Step 4: Add the observable action view model and wire the native UI.**

~~~swift
@MainActor
final class AdmittedModelSettingsViewModel: ObservableObject {
  @Published private(set) var presentation:
    AdmittedModelSettingsPresentation
  private let installer: any AdmittedModelInstalling
  private var updatesTask: Task<Void, Never>?

  init(installer: any AdmittedModelInstalling) {
    self.installer = installer
    self.presentation = .init(snapshot: installer.snapshot)
    subscribeToUpdates()
  }
  func refresh() async
  func perform(_ action: AdmittedModelSettingsAction)

  deinit { updatesTask?.cancel() }

  private func subscribeToUpdates() {
    updatesTask = Task { [weak self, installer] in
      for await snapshot in installer.updates {
        guard !Task.isCancelled else { return }
        self?.apply(snapshot)
      }
    }
  }

  private func apply(_ snapshot: AdmittedModelInstallationSnapshot) {
    presentation = .init(snapshot: snapshot)
  }
}
~~~

In `FleckApp.swift`, construct the empty catalog and
`BuiltInAdmittedModelInstaller` for ordinary release. Under the existing
compile-gated configuration, inject the one signed descriptor and
`EnhancedModelManagerInstaller` only when the caller explicitly supplies that
configuration. Store one view model on `DictationRuntime`; do not create
parallel operation dictionaries or a second manager. Invalid signed
configuration or artifact binding must be caught at this boundary so Settings
construction never fails and Apple Speech/deterministic cleanup remains active.

The construction boundary is explicit:

~~~swift
#if CLEAN_DICTATION_ENHANCED_CANDIDATE
let installer: any AdmittedModelInstalling
do {
  let descriptor = try AdmittedModelDescriptor(validating: signedRawDescriptor)
  installer = try EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: startup,
    calibrate: calibrate
  )
} catch {
  installer = FailedAdmittedModelInstaller(message: String(describing: error))
}
#else
let installer: any AdmittedModelInstalling = BuiltInAdmittedModelInstaller()
#endif
~~~

`FailedAdmittedModelInstaller` is non-operating and exists only to render the
actionable Settings error. Its `.builtIn` recommendation does not replace the
coordinator's existing Apple Speech/deterministic-cleanup dependencies, so a
bad signed descriptor or artifact binding leaves the production fallback
usable and performs no transport work.

In `SettingsView.swift`, make the ordinary-build Dictation section render one
native card from the view model: its recommendation card has one explicit
Install button and metadata, and its built-in card has no install action.
Repair/update/removal are explicit buttons when a signed recommendation is
present. Under `CLEAN_DICTATION_ENHANCED_CANDIDATE`, use this same single card
and `AdmittedModelSettingsViewModel`; remove the old `Picker`,
`ModelConsentView`, and `Download Enhanced Model` surfaces. The manager remains
compile-gated and is not ordinary-release UI or candidate routing authority.
Use semantic colors, keyboard-focusable buttons,
VoiceOver labels/values for phase and byte progress, and no decorative progress
animation. Do not change the existing shortcut, permission, history, or editor
settings.

Keep installer phases and errors in Settings only: map them to finite
`downloading`, `verifying`, `installing`, `starting`, `calibrating`,
`installed`, `repairRequired`, `removing`, or `failed` copy. Errors name the
action and next recovery step. Do not modify `Sources/FleckApp/DictationCapsule.swift`;
all installer phase state remains in Settings. Dictation stays on Apple
Speech/deterministic cleanup when the catalog is built-in or an operation
fails.

- [ ] **Step 5: Run green and broader UI checks.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelSettingsPresentationTests
swift test --disable-automatic-resolution --no-parallel --filter DictationSettingsTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAvailabilityTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAccessibilityTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelSettingsPresentationTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter DictationSettingsTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter DictationAvailabilityTests
~~~

Expected: all commands pass; default settings show built-in state with no model
picker or Advanced selector, the debug-only installer remains compile-gated,
recommendation actions are explicit, phase copy is finite/actionable, and
accessibility values expose byte progress.

- [ ] **Step 6: Inspect and commit.**

~~~bash
git diff --check
rg -n 'Picker\("Engine"|Enhanced Local|ModelConsentView|Download Enhanced Model|Loading' Sources/FleckApp/SettingsView.swift
git add Sources/FleckApp/AdmittedModelSettingsPresentation.swift Sources/FleckApp/SettingsView.swift Sources/FleckApp/FleckApp.swift Tests/FleckAppTests/AdmittedModelSettingsPresentationTests.swift Tests/FleckAppTests/DictationSettingsTests.swift Tests/FleckAppTests/DictationAvailabilityTests.swift
git commit -m "feat: present admitted model recommendation"
~~~

Expected scan: no normal model picker, old consent surface, or indefinite
Loading copy remains. The parent reruns the default and candidate-gated checks,
inspects the UI diff, and obtains the final fresh Sol ship verdict.

## Parent verification and real-app handoff

The parent runs these serialized checks after Task 3:

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelDescriptorTests
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelInstallationTests
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelSettingsPresentationTests
swift test --disable-automatic-resolution --no-parallel --filter DictationSettingsTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAvailabilityTests
swift test --disable-automatic-resolution --no-parallel --filter DictationAccessibilityTests
swift test --disable-automatic-resolution --no-parallel
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelInstallationTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelSettingsPresentationTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter DictationSettingsTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter DictationAvailabilityTests
FLECK_ENHANCED_CANDIDATE=1 swift test --disable-automatic-resolution --no-parallel --filter EnhancedModelManagerTests
git diff --check
~~~

The parent inspects that only the file map changed; default configuration
constructs the built-in installer; candidate-gated tests use only injected
transport/fixtures; byte progress is truthful; manager verification and
filesystem ownership remain authoritative; and no model-weight path was
written. The known viewport assertion is classified separately if present.

## Automated package/build verification

These commands establish packaging evidence but do not establish speech words:

~~~bash
cd /Users/harryjin/Fleck
swift test --disable-automatic-resolution --no-parallel
./Scripts/build-fleck-app.sh
test -d /Users/harryjin/Fleck/.build/Fleck.app
codesign --verify --deep --strict /Users/harryjin/Fleck/.build/Fleck.app
open /Users/harryjin/Fleck/.build/Fleck.app
~~~

Run the build script exactly as committed; do not copy it into the worktree,
add another script, or use an isolated-worktree bundle as evidence. The primary
may launch the app and inspect Settings, but must report only observed process
and UI state.

## Final human microphone verification

The primary cannot fabricate a microphone result. A human operator records each
observation separately from automated evidence:

1. Grant Microphone and Speech Recognition permissions and confirm the app
   refuses the network when on-device Speech is unavailable.
2. Open a Fleck note and hold the existing dictation shortcut. Speak a known
   sentence containing punctuation, an isolated filler, an immediate repetition,
   a name/number/path, and a negation or commitment.
3. Record the actual provisional display, which prefix became stable, the final
   inserted text, whether the dictionary form survived, and whether cleanup
   rejected unsafe output to the exact baseline.
4. Cancel a second capture after provisional text appears. Record that no late
   update, final insertion, history mutation, route, or recovery receipt
   appeared.
5. Open Dictation Settings. Record the built-in state and absence of a model
   picker. If a signed recommendation is intentionally present in a separate
   admitted configuration, record that the UI shows exactly one descriptor and
   that Install was explicit; do not click it as part of this no-weight
   workstream.

The completion report labels automated tests, build/launch evidence, and human
speech observations as separate evidence classes. No ordinary release or
custom-model winner is claimed.

## Later signed-app admission boundary

This workstream leaves the benchmark/admission path open. A later workstream may admit
only a measured candidate with exact upstream identity/revision, conversion,
quantization, license/notices, checksums/bytes, locale/hardware support,
offline/cancellation results, memory/latency measurements, local calibration,
signed-app configuration, and a fresh Sol ship verdict. Until then, Apple
Speech and deterministic/Apple cleanup remain the safe production truth.

## Authority boundary

This workstream authorizes only its file map and the listed local build/launch
checks. Each numbered task has separate ownership and a separate ship gate. It
does not authorize model downloads, model-weight writes, candidate enablement,
release admission, a second downloader, a second audio path, push, PR, merge,
or GitHub mutation.
