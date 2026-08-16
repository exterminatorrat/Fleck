# Local Dictation Model Installation and Real-App Verification Implementation Plan

> **For agentic workers:** Workstream C is a dependency-ordered phase, not one task. Each numbered task below is its own separate user-visible Codex task running GPT-5.6 Luna/Max with a title of `Agent - <singular task>`. Before each task, the primary Sol session is GPT-5.6 Sol at High reasoning; it first runs the orchestration exactness check and confirms the exact native routing roles are available, then writes a bounded five-part packet: objective/success criteria; owned files, interfaces, and constraints; implementation and explicit non-goals; verification commands and expected evidence; and authority boundaries plus the handoff. The Luna/Max task adapts to concurrent edits and preserves unrelated work. The parent Sol task inspects the actual diff and reruns the required checks; a fresh `sol_advisor_sol_reviewer` must return exactly `ship` before the next dependent numbered task. Both `fix-first` and `rethink` return the corrected bounded packet to the same user-visible Luna/Max task; neither switches tasks or adds an implementation route. Terra/native subagents are forbidden. Steps use checkbox (`- [ ]`) syntax for tracking.

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
- Signed input decodes as `RawAdmittedModelDescriptor`; only the validated
  `AdmittedModelDescriptor` reaches `AdmittedModelCatalog` or an installer. Its
  memberwise construction is private and its checked `requiredCapacityBytes` is
  stored at validation time.
- Validation stores canonical trimmed model identity, revision, runtime ABI,
  conversion, quantization, and license values before nonempty validation, plus
  an absolute HTTPS repository URL with a host, no credentials, fragment,
  traversal, or query. Relative, HTTP,
  userinfo, fragment, traversal, and unsafe-query sources reject before catalog
  recommendation or transport.
- A nonempty `requestedLanguages` set must be a subset of descriptor-supported
  languages. Mixed English/Mandarin requests against an English-only descriptor
  fall back to built-in Apple Speech before transport.
- Installer presentation has explicit `notInstalled`, byte-valued
  `downloading`, `verifying`, `installing`, `starting`, `calibrating`,
  `installed`, `updateAvailable`, `repairRequired`, `removing`, and actionable
  failure states. It never presents an indeterminate operation as Loading.
- Install, repair, update, and removal are explicit actions. Startup and
  calibration are visible phases and installation does not imply readiness or
  release admission.
- Settings action dispatch has one serialized operation task and one
  cancellation guard: Install, Cancel, Repair, Update, and Remove each map to
  their installer method exactly once, while duplicate concurrent operations or
  duplicate cancellation clicks do not start a second call.
- Reuse the existing compile-gated `EnhancedModelManager`,
  `EnhancedModelManifest`, `ModelDownloading`, checksum verification, secure
  resume, repair, update, and removal implementation. Do not add a downloader
  or bypass its path validation.
- Descriptor files and manager manifest files use the same
  `AdmittedModelPathRules.canonicalizeUnique` rule: up to three percent-decoding
  passes, rejection when the decoded canonical path differs from the raw path
  or leaves encoding behind, empty/absolute paths, empty
  components, `.`/`..`, backslashes, encoded traversal, and duplicate canonical
  paths. Manager validation runs before URL resolution and transport.
- Every production and test reference to `EnhancedModelManager`,
  `EnhancedModelManifest`, `ModelDownloading`, or `ModelDownloadResult` is
  enclosed by `#if CLEAN_DICTATION_ENHANCED_CANDIDATE`. Default tests use only
  built-in or non-gated types. A small compile-gated immutable
  `EnhancedModelArtifactIdentity` is built or injected alongside the existing
  manifest; its source repository drives `remoteURL`, and the adapter rejects
  any descriptor/identity mismatch before manager operation. This is not a
  generic model registry.
- Hardware recommendation checks use the descriptor's validated staging
  capacity. `AdmittedModelDescriptor.init(validating:)` computes
  `installedBytes + downloadBytes` with `Int64.addingReportingOverflow` and
  rejects overflow; a device with space above `downloadBytes` but below that
  validated capacity falls back to built-in Apple Speech.
- The artifact identity carries that checked `requiredCapacityBytes` into
  `EnhancedModelManager`. Immediately before every install, repair, and update
  network transfer, the manager re-reads its live `capacityProvider` and fails
  before transport when available bytes are below the bound. It never uses a
  static embedded Parakeet capacity for an admitted descriptor.
- The C3 factory receives one exact `AdmittedModelHardwareProfile`, constructs
  `AdmittedModelCatalog` before `EnhancedModelManagerInstaller`, and proceeds
  only when the catalog returns `.recommended` with the same descriptor.
  Unsupported architecture/language or insufficient validated staging space
  yields a non-operating built-in/failure snapshot, preserves Apple fallback,
  and makes zero transport calls.
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
struct AdmittedModelFile: Codable, Equatable, Sendable {
  let path: String
  let byteCount: Int64
  let sha256: String
}

enum AdmittedModelRole: Codable, Equatable, Sendable {
  case asr
  case cleanup
}

struct RawAdmittedModelDescriptor: Codable, Equatable, Sendable {
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
  let requiredCapacityBytes: Int64

  var immutableIdentity: AdmittedModelImmutableIdentity { get }
  private init(
    role: AdmittedModelRole,
    modelID: String,
    revision: String,
    runtimeABI: String,
    conversion: String,
    quantization: String,
    license: String,
    notices: String,
    source: URL,
    files: [AdmittedModelFile],
    downloadBytes: Int64,
    installedBytes: Int64,
    languages: [String],
    architectures: [String],
    requiredCapacityBytes: Int64
  )
  init(validating raw: RawAdmittedModelDescriptor) throws
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
  let requiredCapacityBytes: Int64
}

enum AdmittedModelDescriptorError: Error, Equatable, Sendable {
  case emptyIdentity
  case emptyRevision
  case emptyRuntimeABI
  case emptyConversion
  case emptyQuantization
  case emptyLicense
  case invalidSource
  case unsafePath(String)
  case duplicateFilePath(String)
  case invalidByteCount
  case invalidChecksum(String)
  case aggregateMismatch
  case requiredCapacityOverflow
  case fileAggregateOverflow
  case emptySupport
}

enum AdmittedModelPathError: Error, Equatable, Sendable {
  case unsafePath(String)
  case duplicatePath(String)
}

enum AdmittedModelPathRules {
  static func canonicalize(_ rawPath: String) throws -> String {
    guard !rawPath.isEmpty else {
      throw AdmittedModelPathError.unsafePath(rawPath)
    }
    var path = rawPath
    for _ in 0..<3 {
      guard let decoded = path.removingPercentEncoding else {
        throw AdmittedModelPathError.unsafePath(rawPath)
      }
      if decoded == path { break }
      path = decoded
    }
    guard path == rawPath,
          !path.isEmpty,
          !path.hasPrefix("/"),
          !path.contains("\\"),
          !path.contains("%") else {
      throw AdmittedModelPathError.unsafePath(rawPath)
    }
    let components = path
      .split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw AdmittedModelPathError.unsafePath(rawPath)
    }
    return components.joined(separator: "/")
  }

  static func canonicalizeUnique(_ rawPaths: [String]) throws -> [String] {
    var seen = Set<String>()
    return try rawPaths.map { rawPath in
      let path = try canonicalize(rawPath)
      guard seen.insert(path).inserted else {
        throw AdmittedModelPathError.duplicatePath(path)
      }
      return path
    }
  }
}

struct AdmittedModelHardwareProfile: Equatable, Sendable {
  let architecture: String
  let requestedLanguages: Set<String>
  let availableBytes: Int64
}

enum AdmittedModelRecommendation: Equatable, Sendable {
  case builtIn
  case recommended(AdmittedModelDescriptor)
}

struct AdmittedModelCatalog: Sendable {
  init(
    signedDescriptor: AdmittedModelDescriptor?,
    hardware: AdmittedModelHardwareProfile
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
  case ready
  case starting
  case calibrating
  case installed
  case updateAvailable
  case repairRequired(message: String)
  case removing
  case cancelled
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
  let requiredCapacityBytes: Int64

  var immutableIdentity: AdmittedModelImmutableIdentity {
    .init(
      sourceRepository: sourceRepository,
      modelID: modelID,
      revision: revision,
      license: license,
      runtimeABI: runtimeABI,
      conversion: conversion,
      quantization: quantization,
      files: files,
      downloadBytes: downloadBytes,
      installedBytes: installedBytes,
      requiredCapacityBytes: requiredCapacityBytes
    )
  }

  var manifestIdentity: EnhancedModelManifestIdentity {
    .init(
      schemaVersion: 1,
      modelID: modelID,
      revision: revision,
      files: files,
      totalByteCount: downloadBytes
    )
  }
}

struct EnhancedModelManifestIdentity: Equatable, Sendable {
  let schemaVersion: Int
  let modelID: String
  let revision: String
  let files: [AdmittedModelFile]
  let totalByteCount: Int64

  init(
    schemaVersion: Int,
    modelID: String,
    revision: String,
    files: [AdmittedModelFile],
    totalByteCount: Int64
  ) {
    self.schemaVersion = schemaVersion
    self.modelID = modelID
    self.revision = revision
    self.files = files
    self.totalByteCount = totalByteCount
  }

  init(manifest: EnhancedModelManifest) {
    schemaVersion = manifest.schemaVersion
    modelID = manifest.modelID
    revision = manifest.revision
    files = manifest.files.map {
      AdmittedModelFile(
        path: $0.path,
        byteCount: $0.byteCount,
        sha256: $0.sha256
      )
    }
    totalByteCount = manifest.totalByteCount
  }
}

enum AdmittedModelArtifactMismatch: Error, Equatable {
  case descriptorArtifactMismatch
  case artifactManifestMismatch
}

enum AdmittedModelArtifactBinding {
  static func validate(
    descriptor: AdmittedModelDescriptor,
    artifact: EnhancedModelArtifactIdentity,
    manifest: EnhancedModelManifest
  ) throws {
    guard descriptor.immutableIdentity == artifact.immutableIdentity else {
      throw AdmittedModelArtifactMismatch.descriptorArtifactMismatch
    }
    guard artifact.manifestIdentity == EnhancedModelManifestIdentity(
      manifest: manifest
    ) else {
      throw AdmittedModelArtifactMismatch.artifactManifestMismatch
    }
  }
}
#endif
~~~

The existing manager receives `artifactIdentity` alongside its manifest and
constructs each download URL from `artifactIdentity.sourceRepository`,
`resolve`, and the immutable revision. The current `EnhancedModelManifest`
represents schema version, model ID (including its repository identity),
revision, per-file paths/checksums/byte counts, and aggregate bytes, so
`EnhancedModelManifestIdentity` compares every one of those actual fields.
The current manifest has no separate source URL, license, or runtime ABI /
conversion / quantization fields; those remain required artifact-identity
fields and are covered by the descriptor-to-artifact comparison rather than
silently invented in the manifest schema. If a future admitted manifest
represents them, its identity projection must include them before admission.
The adapter initializer runs `AdmittedModelArtifactBinding.validate` against
both the descriptor and the actual manager manifest before calling any manager
operation; either mismatch throws before transport, and the Settings boundary
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
deterministic `AdmittedModelHardwareProfile` containing the current
architecture, requested language set, and available capacity.

**Produces:** The descriptor, shared `AdmittedModelPathRules`, file identity,
hardware profile, recommendation, and catalog interfaces above.

### TDD red

- [ ] **Step 1: Write exact catalog tests.**

~~~swift
import Foundation
import Testing

@testable import FleckApp

@Test func ordinaryConfigurationShowsBuiltInState() {
  let catalog = AdmittedModelCatalog(
    signedDescriptor: nil,
    hardware: .init(
      architecture: "arm64",
      requestedLanguages: ["en-US"],
      availableBytes: 16_000_000_000
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
      requestedLanguages: ["en-US"],
      availableBytes: descriptor.requiredCapacityBytes + 1
    )
  )
  #expect(catalog.recommendation() == .recommended(descriptor))
}

@Test func mixedRequestedLanguagesDoNotPassAnEnglishOnlyDescriptor() {
  let descriptor = TestDescriptors.admittedASR
  #expect(descriptor.languages == ["en-US"])
  let catalog = AdmittedModelCatalog(
    signedDescriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      requestedLanguages: ["en-US", "zh-CN"],
      availableBytes: descriptor.requiredCapacityBytes
    )
  )
  #expect(catalog.recommendation() == .builtIn)
}

@Test func unsupportedHardwareFallsBackToBuiltIn() {
  let catalog = AdmittedModelCatalog(
    signedDescriptor: TestDescriptors.admittedASR,
    hardware: .init(
      architecture: "x86_64",
      requestedLanguages: ["zh-CN"],
      availableBytes: 1
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
      requestedLanguages: [descriptor.languages[0]],
      availableBytes: availableBytes
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
  #expect(throws: AdmittedModelDescriptorError.emptyRuntimeABI) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, runtimeABI: "   "))
  }
  #expect(throws: AdmittedModelDescriptorError.emptyConversion) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, conversion: "\t"))
  }
  #expect(throws: AdmittedModelDescriptorError.emptyQuantization) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, quantization: "\n"))
  }
  let invalidSources: [URL] = [
    URL(string: "relative/repository")!,
    URL(string: "http://example.invalid/repository")!,
    URL(string: "https://user:pass@example.invalid/repository")!,
    URL(string: "https://example.invalid/repository#fragment")!,
    URL(string: "https://example.invalid/repository/../escape")!,
    URL(string: "https://example.invalid/repository/%2e%2e/escape")!,
    URL(string: "https://example.invalid/repository/%252e%252e/escape")!,
    URL(string: "https://example.invalid/repository?download=true")!
  ]
  for source in invalidSources {
    #expect(throws: AdmittedModelDescriptorError.invalidSource) {
      _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, source: source))
    }
  }
  #expect(throws: AdmittedModelDescriptorError.unsafePath("../escape.bin")) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(
      valid,
      files: [ .init(path: "../escape.bin", byteCount: 4, sha256: String(repeating: "a", count: 64)) ],
      downloadBytes: 4,
      installedBytes: 4
    ))
  }
  for path in [
    "", "/absolute.bin", "%2fabsolute.bin", ".", "..", "a//b",
    "a/./b", "a/../b", "a\\b", "a\\..\\b", "a/%2e%2e/b",
    "a/%252e%252e/b", "%6dodel.bin"
  ] {
    #expect(throws: AdmittedModelDescriptorError.unsafePath(path)) {
      _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(
        valid,
        files: [ .init(
          path: path,
          byteCount: 4,
          sha256: String(repeating: "a", count: 64)
        ) ],
        downloadBytes: 4,
        installedBytes: 4
      ))
    }
  }
  #expect(throws: AdmittedModelDescriptorError.duplicateFilePath("model.bin")) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(
      valid,
      files: [
        .init(path: "model.bin", byteCount: 4, sha256: String(repeating: "a", count: 64)),
        .init(path: "model.bin", byteCount: 4, sha256: String(repeating: "b", count: 64))
      ],
      downloadBytes: 8,
      installedBytes: 8
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
  #expect(throws: AdmittedModelDescriptorError.requiredCapacityOverflow) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(
      valid,
      installedBytes: Int64.max,
      downloadBytes: 1
    ))
  }
  #expect(throws: AdmittedModelDescriptorError.fileAggregateOverflow) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(
      valid,
      files: [
        .init(path: "one.bin", byteCount: Int64.max, sha256: String(repeating: "a", count: 64)),
        .init(path: "two.bin", byteCount: 1, sha256: String(repeating: "b", count: 64))
      ],
      downloadBytes: Int64.max / 2,
      installedBytes: Int64.max / 2
    ))
  }
  #expect(throws: AdmittedModelDescriptorError.emptySupport) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(valid, languages: [], architectures: []))
  }
}

@Test func descriptorStoresCanonicalTrimmedIdentityFields() throws {
  let descriptor = try AdmittedModelDescriptor(validating: TestDescriptors.make(
    TestDescriptors.neutralAdmitted,
    modelID: " model ",
    revision: " revision ",
    runtimeABI: " runtime ",
    conversion: " conversion ",
    quantization: " quantized ",
    license: " license "
  ))
  #expect(descriptor.modelID == "model")
  #expect(descriptor.revision == "revision")
  #expect(descriptor.runtimeABI == "runtime")
  #expect(descriptor.conversion == "conversion")
  #expect(descriptor.quantization == "quantized")
  #expect(descriptor.license == "license")
}

@Test func doubleEncodedRepositoryTraversalIsRejected() {
  #expect(throws: AdmittedModelDescriptorError.invalidSource) {
    _ = try AdmittedModelDescriptor(validating: TestDescriptors.make(
      TestDescriptors.neutralAdmitted,
      source: URL(string: "https://example.invalid/repository/%252e%252e/escape")!
    ))
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
  private let hardware: AdmittedModelHardwareProfile

  init(
    signedDescriptor: AdmittedModelDescriptor?,
    hardware: AdmittedModelHardwareProfile
  ) {
    self.signedDescriptor = signedDescriptor
    self.hardware = hardware
  }

  func recommendation() -> AdmittedModelRecommendation {
    let supportedLanguages = Set(signedDescriptor?.languages ?? [])
    guard let descriptor = signedDescriptor,
          descriptor.architectures.contains(hardware.architecture),
          (hardware.requestedLanguages.isEmpty
            || hardware.requestedLanguages.isSubset(of: supportedLanguages)),
          hardware.availableBytes >= descriptor.requiredCapacityBytes else {
      return .builtIn
    }
    return .recommended(descriptor)
  }
}
~~~

Add validation at the signed boundary, not in the view:

~~~swift
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
  let requiredCapacityBytes: Int64

  private init(
    role: AdmittedModelRole,
    modelID: String,
    revision: String,
    runtimeABI: String,
    conversion: String,
    quantization: String,
    license: String,
    notices: String,
    source: URL,
    files: [AdmittedModelFile],
    downloadBytes: Int64,
    installedBytes: Int64,
    languages: [String],
    architectures: [String],
    requiredCapacityBytes: Int64
  ) {
    self.role = role
    self.modelID = modelID
    self.revision = revision
    self.runtimeABI = runtimeABI
    self.conversion = conversion
    self.quantization = quantization
    self.license = license
    self.notices = notices
    self.source = source
    self.files = files
    self.downloadBytes = downloadBytes
    self.installedBytes = installedBytes
    self.languages = languages
    self.architectures = architectures
    self.requiredCapacityBytes = requiredCapacityBytes
  }
}

extension AdmittedModelDescriptor {
  init(validating raw: RawAdmittedModelDescriptor) throws {
    let modelID = raw.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    let revision = raw.revision.trimmingCharacters(in: .whitespacesAndNewlines)
    let runtimeABI = raw.runtimeABI.trimmingCharacters(in: .whitespacesAndNewlines)
    let conversion = raw.conversion.trimmingCharacters(in: .whitespacesAndNewlines)
    let quantization = raw.quantization.trimmingCharacters(in: .whitespacesAndNewlines)
    let license = raw.license.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelID.isEmpty else {
      throw AdmittedModelDescriptorError.emptyIdentity
    }
    guard !revision.isEmpty else {
      throw AdmittedModelDescriptorError.emptyRevision
    }
    guard !runtimeABI.isEmpty else {
      throw AdmittedModelDescriptorError.emptyRuntimeABI
    }
    guard !conversion.isEmpty else {
      throw AdmittedModelDescriptorError.emptyConversion
    }
    guard !quantization.isEmpty else {
      throw AdmittedModelDescriptorError.emptyQuantization
    }
    guard !license.isEmpty else {
      throw AdmittedModelDescriptorError.emptyLicense
    }
    guard let source = URLComponents(
      url: raw.source,
      resolvingAgainstBaseURL: false
    ),
      raw.source.baseURL == nil,
      source.scheme?.lowercased() == "https",
      source.host?.isEmpty == false,
      source.user == nil,
      source.password == nil,
      source.fragment == nil,
      source.query == nil,
      !source.path.isEmpty,
      !source.path.split(separator: "/").contains("..") else {
      throw AdmittedModelDescriptorError.invalidSource
    }
    var canonicalPath = source.percentEncodedPath
    for _ in 0..<3 {
      guard let decodedPath = canonicalPath.removingPercentEncoding else {
        throw AdmittedModelDescriptorError.invalidSource
      }
      if decodedPath == canonicalPath { break }
      canonicalPath = decodedPath
    }
    guard !canonicalPath.contains("%"),
          !canonicalPath.split(separator: "/").contains("..") else {
      throw AdmittedModelDescriptorError.invalidSource
    }
    guard !raw.languages.isEmpty, !raw.architectures.isEmpty else {
      throw AdmittedModelDescriptorError.emptySupport
    }
    guard raw.downloadBytes > 0,
          raw.installedBytes > 0,
          raw.files.allSatisfy({ $0.byteCount > 0 }) else {
      throw AdmittedModelDescriptorError.invalidByteCount
    }
    let (requiredCapacityBytes, requiredCapacityOverflow) =
      raw.installedBytes.addingReportingOverflow(raw.downloadBytes)
    guard !requiredCapacityOverflow else {
      throw AdmittedModelDescriptorError.requiredCapacityOverflow
    }
    var aggregate: Int64 = 0
    for file in raw.files {
      let (next, overflow) = aggregate.addingReportingOverflow(file.byteCount)
      guard !overflow else {
        throw AdmittedModelDescriptorError.fileAggregateOverflow
      }
      aggregate = next
    }
    guard aggregate == raw.downloadBytes,
          raw.installedBytes >= raw.downloadBytes else {
      throw AdmittedModelDescriptorError.aggregateMismatch
    }
    let normalizedPaths: [String]
    do {
      normalizedPaths = try AdmittedModelPathRules.canonicalizeUnique(
        raw.files.map(\.path)
      )
    } catch AdmittedModelPathError.unsafePath(let path) {
      throw AdmittedModelDescriptorError.unsafePath(path)
    } catch AdmittedModelPathError.duplicatePath(let path) {
      throw AdmittedModelDescriptorError.duplicateFilePath(path)
    }
    var normalizedFiles: [AdmittedModelFile] = []
    for (file, normalizedPath) in zip(raw.files, normalizedPaths) {
      guard file.sha256.count == 64,
            file.sha256.allSatisfy("0123456789abcdefABCDEF".contains) else {
        throw AdmittedModelDescriptorError.invalidChecksum(file.sha256)
      }
      normalizedFiles.append(.init(
        path: normalizedPath,
        byteCount: file.byteCount,
        sha256: file.sha256
      ))
    }
    self.init(
      role: raw.role,
      modelID: modelID,
      revision: revision,
      runtimeABI: runtimeABI,
      conversion: conversion,
      quantization: quantization,
      license: license,
      notices: raw.notices,
      source: raw.source,
      files: normalizedFiles,
      downloadBytes: raw.downloadBytes,
      installedBytes: raw.installedBytes,
      languages: raw.languages,
      architectures: raw.architectures,
      requiredCapacityBytes: requiredCapacityBytes
    )
  }

  var immutableIdentity: AdmittedModelImmutableIdentity {
    .init(sourceRepository: source, modelID: modelID, revision: revision,
          license: license, runtimeABI: runtimeABI, conversion: conversion,
          quantization: quantization, files: files,
          downloadBytes: downloadBytes, installedBytes: installedBytes,
          requiredCapacityBytes: requiredCapacityBytes)
  }
}
~~~

Have the signed-configuration path decode into `RawAdmittedModelDescriptor` and
call the throwing initializer below before constructing the inaccessible
validated value. `TestDescriptors.neutralAdmitted` is a validated fixture;
`TestDescriptors.raw(_:)` returns its raw copy and `TestDescriptors.make` returns
a raw copy with the named override. The test
cases above cover canonical trimmed identity/revision/runtime ABI/conversion/
quantization/license, trimmed-empty fields, relative/non-HTTPS/userinfo/
fragment/query/traversal sources including double-encoded traversal. Both the
descriptor and manager call `AdmittedModelPathRules.canonicalizeUnique`, which
repeatedly percent-decodes up to three times, rejects any path whose decoded
canonical value differs from its raw value or leaves encoding behind, and
rejects empty and absolute paths, `.`, `..`, empty components such as
`a//b`, dot components, backslashes, encoded traversal, and duplicate
normalized paths. The descriptor maps those shared errors to
`unsafePath`/`duplicateFilePath` before recommendation.
The cases also cover negative byte counts, non-64-hex checksums, aggregate mismatches, the
`installedBytes: Int64.max, downloadBytes: 1` required-capacity overflow, and a
distinct per-file checked-add overflow. The stored `requiredCapacityBytes` is
the checked value from validation, not a recomputed sum. Do not accept an array, picker index, or
fallback descriptor in the catalog. The ordinary constructor passes nil.

- [ ] **Step 4: Run green, inspect, and commit.**

~~~bash
swift test --disable-automatic-resolution --no-parallel --filter AdmittedModelDescriptorTests
git diff --check
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/AdmittedModelDescriptor.swift \
    Tests/FleckAppTests/AdmittedModelDescriptorTests.swift \
  | sort -u
)"
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
checksum/path/repair/update/remove operations. It also consumes Task 1's
`AdmittedModelPathRules` for manager manifest and URL validation. Default builds
consume only the built-in installer seam.

**Produces:** `AdmittedModelInstallPhase`,
`AdmittedModelInstallationSnapshot`, `AdmittedModelInstalling`,
`BuiltInAdmittedModelInstaller`, `FailedAdmittedModelInstaller`, and the compile-gated
`EnhancedModelManagerInstaller`.

### TDD red

- [ ] **Step 1: Add fake transport and lifecycle tests.** The fixture bytes
  are short `Data` values, not model weights.

~~~swift
import Foundation
import CryptoKit
import Testing

@testable import FleckApp

enum TestFixtures {
  static let tinyBytes = Data("fixture!".utf8) // exactly 8 bytes
  static let tinySHA256 = SHA256.hash(data: tinyBytes)
    .map { String(format: "%02x", $0) }
    .joined()
}

final class SynchronousCapacityProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Int64

  init(_ value: Int64) { self.value = value }

  func read() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ value: Int64) {
    lock.lock()
    self.value = value
    lock.unlock()
  }
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
enum TestPaths {
  static func temporaryDirectory() -> URL {
    let candidate = FileManager.default.temporaryDirectory
      .appendingPathComponent("Fleck-\(UUID().uuidString)", isDirectory: true)
      .standardizedFileURL
    do {
      try FileManager.default.createDirectory(
        at: candidate,
        withIntermediateDirectories: false
      )
      return candidate.resolvingSymlinksInPath().standardizedFileURL
    } catch {
      preconditionFailure("Unable to create isolated test directory: \(error)")
    }
  }

  static func remove(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
  }
}

@MainActor
final class TestManagerFixture {
  let root: URL
  let manager: EnhancedModelManager

  init(
    descriptor: AdmittedModelDescriptor,
    artifactIdentity: EnhancedModelArtifactIdentity,
    manifest: EnhancedModelManifest,
    transport: any ModelDownloading,
    refreshFixture: TestRefreshFixture? = nil,
    capacityProvider: @escaping @Sendable () throws -> Int64 = { Int64.max },
    architectureProvider: @escaping @Sendable () -> Bool = { true }
  ) throws {
    root = TestPaths.temporaryDirectory()
    do {
      let trustedManifests = try refreshFixture?.seed(
        root: root,
        current: manifest
      ) ?? [manifest]
      manager = EnhancedModelManager(
        modelRootURL: root,
        manifest: manifest,
        trustedManifests: trustedManifests,
        artifactIdentity: artifactIdentity,
        candidateEnabled: true,
        capacityProvider: capacityProvider,
        architectureProvider: architectureProvider,
        transport: transport
      )
    } catch {
      TestPaths.remove(root)
      throw error
    }
  }

  func cleanup() {
    TestPaths.remove(root)
  }
}

enum TestManagers {
  @MainActor
  static func manager(
    descriptor: AdmittedModelDescriptor,
    artifactIdentity: EnhancedModelArtifactIdentity,
    manifest: EnhancedModelManifest,
    transport: any ModelDownloading,
    refreshFixture: TestRefreshFixture? = nil,
    capacityProvider: @escaping @Sendable () throws -> Int64 = {
      Int64.max
    },
    architectureProvider: @escaping @Sendable () -> Bool = { true }
  ) throws -> TestManagerFixture {
    try TestManagerFixture(
      descriptor: descriptor,
      artifactIdentity: artifactIdentity,
      manifest: manifest,
      transport: transport,
      refreshFixture: refreshFixture,
      capacityProvider: capacityProvider,
      architectureProvider: architectureProvider
    )
  }
}

enum TestRefreshFixture: Equatable {
  case ready
  case updateAvailable
  case repairRequired

  func seed(
    root: URL,
    current: EnhancedModelManifest
  ) throws -> [EnhancedModelManifest] {
    let fileManager = FileManager.default
    let modelName = try #require(current.modelID.split(separator: "/").last)

    func seedInstall(
      _ manifest: EnhancedModelManifest,
      bytes: Data
    ) throws {
      let repository = root
        .appendingPathComponent("installed", isDirectory: true)
        .appendingPathComponent(manifest.revision, isDirectory: true)
        .appendingPathComponent(String(modelName), isDirectory: true)
      try fileManager.createDirectory(
        at: repository,
        withIntermediateDirectories: true
      )
      let file = repository.appendingPathComponent(manifest.files[0].path)
      try fileManager.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try bytes.write(to: file, options: .atomic)
      try JSONEncoder().encode(manifest).write(
        to: repository.deletingLastPathComponent()
          .appendingPathComponent("manifest.json"),
        options: .atomic
      )
    }

    switch self {
    case .ready:
      try seedInstall(current, bytes: TestFixtures.tinyBytes)
      return [current]
    case .updateAvailable:
      let previous = TestManifests.make(
        current,
        revision: "previous-revision"
      )
      try seedInstall(previous, bytes: TestFixtures.tinyBytes)
      return [current, previous]
    case .repairRequired:
      try seedInstall(current, bytes: Data("bad".utf8))
      return [current]
    }
  }
}
#endif

@Test @MainActor
func defaultBuildUsesBuiltInInstallerWithoutManagerReference() async {
  let installer = BuiltInAdmittedModelInstaller()
  await installer.install()
  #expect(installer.snapshot.phase == .builtIn)
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test @MainActor
func existingDictationModelCapabilityCallShapesRemainSourceCompatible() {
  let defaultRoot = TestPaths.temporaryDirectory()
  let testRoot = TestPaths.temporaryDirectory()
  defer {
    TestPaths.remove(defaultRoot)
    TestPaths.remove(testRoot)
  }
  // This call uses the production capacity and arm64 defaults.
  let defaultCapability = DictationModelCapability(
    modelRootURL: defaultRoot
  )
  // This is the existing test shape; only its architecture probe is injected.
  let testCapability = DictationModelCapability(
    modelRootURL: testRoot,
    candidateEnabled: true,
    architectureProvider: { true }
  )
  #expect(defaultCapability.state == .notInstalled)
  #expect(testCapability.state == .notInstalled)
}

@Test @MainActor
func fakeInstallReportsBytesThenVerificationStartupAndCalibration() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  #expect(TestFixtures.tinyBytes.count == 8)
  #expect(descriptor.downloadBytes == 8)
  #expect(TestManifests.tiny.totalByteCount == 8)
  #expect(TestManifests.tiny.files[0].byteCount == 8)
  #expect(TestManifests.tiny.files[0].sha256 == TestFixtures.tinySHA256)
  #expect(TestArtifacts.identity(matching: descriptor).downloadBytes == 8)
  #expect(TestArtifacts.identity(matching: descriptor).files[0].byteCount == 8)
  #expect(TestArtifacts.identity(matching: descriptor).files[0].sha256 == TestFixtures.tinySHA256)
  let lifecycle = PhaseRecorder()
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  let installer = try! EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { await lifecycle.append("startup") },
    calibrate: { await lifecycle.append("calibration") }
  )

  await installer.install()

  #expect(installer.phaseHistory.suffix(9) == [
    .downloading(receivedBytes: 0, totalBytes: descriptor.downloadBytes),
    .downloading(receivedBytes: 4, totalBytes: descriptor.downloadBytes),
    .downloading(receivedBytes: 8, totalBytes: descriptor.downloadBytes),
    .verifying,
    .installing,
    .ready,
    .starting,
    .calibrating,
    .installed
  ])
  #expect(await lifecycle.values == ["startup", "calibration"])
  #expect(installer.snapshot.phase == .installed)
}

@Test @MainActor
func checksumFailureBecomesActionableRepairState() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: ModelDownloadingProbe(bytes: Data("corrupt!".utf8))
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
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
func refreshMapsStaleStateWithoutStartingOperation() async throws {
  let cases: [TestRefreshFixture] = [
    .ready,
    .updateAvailable,
    .repairRequired
  ]

  for refreshFixture in cases {
    let descriptor = TestDescriptors.tinyAdmittedASR
    let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
    let fixture = try TestManagers.manager(
      descriptor: descriptor,
      artifactIdentity: TestArtifacts.identity(matching: descriptor),
      manifest: TestManifests.tiny,
      transport: transport,
      refreshFixture: refreshFixture
    )
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let installer = try EnhancedModelManagerInstaller(
      manager: manager,
      descriptor: descriptor,
      startup: { Issue.record("refresh must not start startup") },
      calibrate: { Issue.record("refresh must not start calibration") }
    )

    #expect(installer.snapshot.phase == .notInstalled)
    await installer.refresh()

    switch refreshFixture {
    case .ready:
      #expect(installer.snapshot.phase == .ready)
    case .updateAvailable:
      #expect(installer.snapshot.phase == .updateAvailable)
    case .repairRequired:
      guard case .repairRequired = installer.snapshot.phase else {
        Issue.record("Expected the manager's filesystem repairRequired state")
        continue
      }
    }
    #expect(transport.downloadCalls == 0)
    #expect(!installer.phaseHistory.contains {
      if case .downloading = $0 { return true }
      return false
    })
  }
}

@Test @MainActor
func liveCapacityGateRejectsInstallRepairAndUpdateBeforeTransport() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let initialAvailableBytes = descriptor.requiredCapacityBytes + 1
  let insufficientAvailableBytes = descriptor.downloadBytes + 1
  #expect(insufficientAvailableBytes > descriptor.downloadBytes)
  #expect(insufficientAvailableBytes < descriptor.requiredCapacityBytes)
  let catalog = AdmittedModelCatalog(
    signedDescriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      requestedLanguages: [descriptor.languages[0]],
      availableBytes: initialAvailableBytes
    )
  )
  #expect(catalog.recommendation() == .recommended(descriptor))
  let operations: [(String, TestRefreshFixture?)] = [
    ("install", nil),
    ("repair", .repairRequired),
    ("update", .updateAvailable)
  ]

  for (operation, refreshFixture) in operations {
    let capacity = SynchronousCapacityProbe(initialAvailableBytes)
    let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
    let fixture = try! TestManagers.manager(
      descriptor: descriptor,
      artifactIdentity: TestArtifacts.identity(matching: descriptor),
      manifest: TestManifests.tiny,
      transport: transport,
      refreshFixture: refreshFixture,
      capacityProvider: { capacity.read() }
    )
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let installer = try! EnhancedModelManagerInstaller(
      manager: manager,
      descriptor: descriptor,
      startup: { },
      calibrate: { }
    )
    if refreshFixture != nil { await installer.refresh() }
    capacity.set(insufficientAvailableBytes)
    switch operation {
    case "install": await installer.install()
    case "repair": await installer.repair()
    case "update": await installer.update()
    default: Issue.record("Unexpected fixture operation")
    }
    #expect(transport.downloadCalls == 0)
    #expect(!installer.phaseHistory.contains {
      if case .downloading = $0 { return true }
      return false
    })
    #expect(installer.snapshot.lastError != nil)
  }
}

@Test @MainActor
func cancellationPublishesCancelledAndCannotPublishInstalledLater() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(
    bytes: TestFixtures.tinyBytes,
    pausesUntilCancelled: true
  )
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  let installer = try! EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { },
    calibrate: { }
  )

  let install = Task { await installer.install() }
  await transport.waitUntilStarted()
  installer.cancel()
  await install.value

  #expect(installer.snapshot.phase == .cancelled)
  #expect(installer.snapshot.lastError == "Model operation cancelled.")
  #expect(installer.phaseHistory.last != .installed)
  #expect(!installer.phaseHistory.contains(.installed))
  #expect(transport.cancelObserved)
}

@Test @MainActor
func descriptorArtifactMismatchFailsBeforeTransport() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identityWith(
      revision: "different-revision"
    ),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  #expect(throws: AdmittedModelArtifactMismatch.descriptorArtifactMismatch) {
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
    TestArtifacts.identity(valid, installedBytes: valid.installedBytes + 1),
    TestArtifacts.identity(
      valid,
      requiredCapacityBytes: valid.requiredCapacityBytes + 1
    )
  ]
  for artifact in mismatches {
    #expect(throws: AdmittedModelArtifactMismatch.descriptorArtifactMismatch) {
      try AdmittedModelArtifactBinding.validate(
        descriptor: descriptor,
        artifact: artifact,
        manifest: TestManifests.tiny
      )
    }
  }
}

@Test @MainActor
func artifactManifestMismatchesAreRejectedBeforeTransport() throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let artifact = TestArtifacts.identity(matching: descriptor)
  let mismatchedManifests = [
    TestManifests.make(TestManifests.tiny, schemaVersion: 2),
    TestManifests.make(TestManifests.tiny, modelID: "other/model"),
    TestManifests.make(TestManifests.tiny, revision: "other-revision"),
    TestManifests.make(
      TestManifests.tiny,
      files: [ .init(
        path: artifact.files[0].path,
        byteCount: artifact.files[0].byteCount,
        sha256: String(repeating: "b", count: 64)
      ) ]
    ),
    TestManifests.make(
      TestManifests.tiny,
      files: [ .init(
        path: artifact.files[0].path,
        byteCount: artifact.files[0].byteCount + 1,
        sha256: artifact.files[0].sha256
      ) ]
    ),
    TestManifests.make(TestManifests.tiny, totalByteCount: 999)
  ]
  for manifest in mismatchedManifests {
    #expect(throws: AdmittedModelArtifactMismatch.artifactManifestMismatch) {
      try AdmittedModelArtifactBinding.validate(
        descriptor: descriptor,
        artifact: artifact,
        manifest: manifest
      )
    }
  }
}

@Test @MainActor
func artifactManifestMismatchFailsBeforeTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.make(TestManifests.tiny, revision: "wrong"),
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  #expect(throws: AdmittedModelArtifactMismatch.artifactManifestMismatch) {
    _ = try EnhancedModelManagerInstaller(
      manager: manager,
      descriptor: descriptor,
      startup: { },
      calibrate: { }
    )
  }
  #expect(transport.downloadCalls == 0)
}

@Test func artifactRemoteURLUsesExplicitSourceAndRevisionAndKeepsDownloadQuery() throws {
  let sourceRepository = URL(string: "https://example.invalid/custom-repository")!
  let revision = "custom-revision-123"
  let url = try EnhancedModelManager.remoteURL(
    for: .init(path: "folder/model.bin", byteCount: 4, sha256: String(repeating: "a", count: 64)),
    sourceRepository: sourceRepository,
    revision: revision
  )
  #expect(url.path == "/custom-repository/resolve/custom-revision-123/folder/model.bin")
  #expect(url.absoluteString == "https://example.invalid/custom-repository/resolve/custom-revision-123/folder/model.bin?download=true")
  #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
    URLQueryItem(name: "download", value: "true")
  ])
}

@Test @MainActor
func managerRejectsDescriptorUnsafePathTableBeforeURLResolution() {
  let unsafePaths = [
    "", "/absolute.bin", "%2fabsolute.bin", ".", "..", "a//b",
    "a/./b", "a/../b", "a\\b", "a\\..\\b", "a/%2e%2e/b",
    "a/%252e%252e/b", "%6dodel.bin"
  ]
  for path in unsafePaths {
    do {
      _ = try EnhancedModelManager.remoteURL(
        for: .init(path: path, byteCount: 8, sha256: String(repeating: "a", count: 64)),
        sourceRepository: URL(string: "https://example.invalid/repository")!,
        revision: "revision"
      )
      Issue.record("Unsafe manager path unexpectedly reached URL construction: \(path)")
    } catch let error as EnhancedModelManagerError {
      #expect(error == .invalidManifestPath(path))
    } catch {
      Issue.record("Unexpected manager path error for \(path): \(error)")
    }
  }
}

@Test @MainActor
func managerRejectsDuplicateNormalizedManifestPathsBeforeTransport() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let duplicateManifest = TestManifests.make(
    TestManifests.tiny,
    files: [
      .init(path: "model.bin", byteCount: 8, sha256: TestFixtures.tinySHA256),
      .init(path: "model.bin", byteCount: 8, sha256: TestFixtures.tinySHA256)
    ],
    totalByteCount: 16
  )
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: duplicateManifest,
    transport: transport,
    capacityProvider: { Int64.max }
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  do {
    try await manager.download()
    Issue.record("Duplicate normalized manifest paths unexpectedly downloaded")
  } catch let error as EnhancedModelManagerError {
    #expect(error == .invalidManifest)
  } catch {
    Issue.record("Unexpected duplicate-path manager error: \(error)")
  }
  #expect(transport.downloadCalls == 0)
}

struct ObservedProgress: Equatable, Sendable {
  let receivedBytes: Int64
  let totalBytes: Int64
}

@Test @MainActor
func installerUpdatesExposeBytesBeforeCompletion() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(
    bytes: TestFixtures.tinyBytes,
    progressSequence: [4, 8, 8],
    pausesAfterFirstProgress: true
  )
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
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
        await recorder.append(ObservedProgress(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes
        ))
      }
    }
  }
  let install = Task { await installer.install() }
  await transport.waitUntilFirstProgress()
  await recorder.waitUntilCount(1)
  let firstSnapshots = await recorder.values
  #expect(firstSnapshots.map(\.receivedBytes) == [4])
  #expect(firstSnapshots.map(\.totalBytes) == [descriptor.downloadBytes])
  await transport.releaseProgress()
  await install.value
  await recorder.waitUntilCount(2)
  let snapshots = await recorder.values
  #expect(snapshots.map(\.receivedBytes) == [4, 8])
  #expect(snapshots.map(\.totalBytes) == [
    descriptor.downloadBytes,
    descriptor.downloadBytes
  ])
  #expect(snapshots.map(\.receivedBytes) ==
    snapshots.map(\.receivedBytes).sorted())
  let publishedDownloads = installer.phaseHistory.compactMap { phase -> Int64? in
    guard case .downloading(let receivedBytes, let totalBytes) = phase else {
      return nil
    }
    #expect(totalBytes == descriptor.downloadBytes)
    return receivedBytes
  }
  #expect(publishedDownloads == [0, 4, 8])
  updates.cancel()
}
#endif
~~~

The gated compile-focused test stays in the Task 2-owned installation test
file; it does not edit the excluded Settings call sites.

`ModelDownloadingProbe` requires the exact artifact identity through its
`TestManagers.manager(descriptor:artifactIdentity:manifest:transport:)` helper, emits progress values
`4`, `8`, and a duplicate `8` with `totalBytes == descriptor.downloadBytes`,
pauses after `4`, and does not complete until the test releases the gate. The
installer publishes the explicit initial `0`, then accepts only a strictly
larger received count in the inclusive `0...descriptor.downloadBytes` range;
the duplicate final `8` is ignored. With
`pausesUntilCancelled`, it remains in the manager operation until
`EnhancedModelManagerInstaller.cancel()` cancels the single operation task and
its manager/download child. The actor-backed
`ProgressSnapshotRecorder.waitUntilCount(_:)` lets the test assert the first
snapshot while installation is still blocked, then assert monotonic bytes and
the exact total after the second snapshot. The only exception is the deliberate
descriptor-mismatch fixture, which passes a different immutable identity to
prove zero transport calls. `TestManagers.manager(descriptor:artifactIdentity:manifest:transport:)`
has no default identity or manifest and returns a `TestManagerFixture` whose
`manager` is constructed with the supplied artifact identity and actual
manifest. Every call site binds the fixture, uses `fixture.manager`, and
defers `fixture.cleanup()`; cleanup removes only that fixture's temporary root.
Normal fixtures pass `TestArtifacts.identity(matching: descriptor)`, whose
required capacity is copied exactly from the descriptor. Its override helper
can change that field for the binding mismatch test, while the checksum
fixture helper takes `descriptor:artifactIdentity:manifest:` in the same order.
`PhaseRecorder` proves startup follows
the manager's `.ready` state and calibration follows startup. The manager's
`@Published state` subscription maps `.verifying`, `.installing`, `.ready`,
`.repairRequired`, `.removing`, and operation failures while the
`@Published byteProgress` subscription maps live byte snapshots. Both
subscriptions are synchronous `@MainActor` sinks with no `receive(on:)`, and
they are cancelled before the operation task's defer returns so the final
byte update cannot queue past teardown. `TestFixtures.tinyBytes` is exactly
8 bytes; `TestDescriptors.tinyAdmittedASR.downloadBytes`,
`TestManifests.tiny.totalByteCount`, its sole file's `byteCount` and checksum,
and `TestArtifacts.identity(matching:)` are all derived from those same eight
bytes. The successful fake install therefore uses total/progress `8`, with no
seven-byte fixture hidden behind an eight-byte assertion.

`refresh()` owns a temporary synchronous `@MainActor` state subscription, calls
only `manager.refreshState()`, maps the final `manager.state`, and cancels that
subscription before returning. It never creates an operation task, subscribes
to byte progress, invokes transport, startup, or calibration, or publishes an
installing phase. `TestRefreshFixture` seeds the real manager assessment root:
`.ready` writes the current revision, manifest JSON, and checksum-valid
eight-byte file; `.updateAvailable` writes a trusted previous revision with
the same tiny file; and `.repairRequired` writes the current manifest with a
wrong-size file. The manager therefore derives each state through its real
`refreshState()` filesystem assessment, not a fake state setter. The test
begins from the installer's stale `.notInstalled` snapshot and proves all three
refresh outcomes without a download. The test-only
`TestManagers.manager` signature is
`descriptor:artifactIdentity:manifest:transport:refreshFixture:capacityProvider:architectureProvider:`;
the first four labels and order remain mandatory for every manager fixture call,
and every fixture's isolated root is explicitly cleaned by its owning test.
Its test-only provider defaults are `Int64.max` and `true`; production and
compatibility initializers retain the live-capacity and arm64 providers shown
above.

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

@MainActor
final class EnhancedModelManager: ObservableObject {
  nonisolated static let resumeAuthenticationService =
    "com.harryjin.fleck.enhanced-model-resume"
  nonisolated static let legacyResumeAuthenticationService =
    "com.motes.enhanced-model-resume"
  nonisolated private static let resumeAuthenticationAccount = "default"
  nonisolated private static let resumeAuthenticationLock = NSLock()
  static let requiredAvailableCapacity: Int64 = 1_197_261_950

  @Published private(set) var state: EnhancedModelState = .notInstalled
  private(set) var verifiedRepositoryURL: URL?
  var verifiedLoadState: EnhancedModelVerifiedLoadState {
    guard candidateEnabled, let verifiedRepositoryURL else {
      return .unavailable
    }
    switch state {
    case .ready, .updateAvailable, .downloading, .verifying, .installing:
      return .ready(repositoryURL: verifiedRepositoryURL)
    case .notInstalled, .repairRequired, .removing:
      return .unavailable
    }
  }
  let isArchitectureSupported: Bool

  private let context: FileContext
  private let manifest: EnhancedModelManifest
  private let trustedManifests: [EnhancedModelManifest]
  private let artifactIdentity: EnhancedModelArtifactIdentity
  private let requiredCapacityBytes: Int64
  private let capacityProvider: @Sendable () throws -> Int64
  private let candidateEnabled: Bool
  private let clock: @Sendable () -> Date
  private let transport: any ModelDownloading
  private let assessmentDidComplete: @Sendable () -> Void
  private let cleanupWillBegin: @Sendable () -> Void
  private let removalWillBegin: @Sendable () -> Void
  private let resumeAuthenticationKeyProvider: @Sendable () throws -> SymmetricKey
  @Published private(set) var byteProgress: EnhancedModelByteProgress? = nil
  private var stateChangedAt: Date
  private var activeOperationID: UUID?
  private var activeAssessmentCount = 0
  private var pendingInferenceLoadFailure: (message: String, repositoryURL: URL)?
  private var lifecycleEpoch: UInt64 = 0
  private var highestProgress = 0.0

  nonisolated static func liveAvailableCapacity() throws -> Int64 {
    let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    )
    return values.volumeAvailableCapacityForImportantUsage ?? 0
  }

  nonisolated static func isAppleSilicon() -> Bool {
    var info = utsname()
    uname(&info)
    let machine = withUnsafePointer(to: &info.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
    return machine == "arm64"
  }

  init(
    modelRootURL: URL? = nil,
    fileManager: FileManager = .default,
    manifest: EnhancedModelManifest,
    artifactIdentity: EnhancedModelArtifactIdentity,
    trustedManifests: [EnhancedModelManifest]? = nil,
    candidateEnabled: Bool = CleanDictationFeatures.enhancedLocalCandidateEnabled,
    capacityProvider: @escaping @Sendable () throws -> Int64 = {
      try EnhancedModelManager.liveAvailableCapacity()
    },
    architectureProvider: @escaping @Sendable () -> Bool = {
      EnhancedModelManager.isAppleSilicon()
    },
    clock: @escaping @Sendable () -> Date = { Date() },
    transport: any ModelDownloading = URLSessionModelDownloader(),
    assessmentDidComplete: @escaping @Sendable () -> Void = {},
    cleanupWillBegin: @escaping @Sendable () -> Void = {},
    removalWillBegin: @escaping @Sendable () -> Void = {},
    resumeAuthenticationKeyProvider: @escaping @Sendable () throws -> SymmetricKey = {
      try EnhancedModelManager.loadOrCreateResumeAuthenticationKey()
    }
  ) {
    let root = modelRootURL ?? fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
      .appendingPathComponent(
        FleckProductPaths.canonicalDirectoryName,
        isDirectory: true
      )
      .appendingPathComponent("DictationModels", isDirectory: true)

    self.context = FileContext(root: root, fileManager: fileManager)
    self.manifest = manifest
    self.trustedManifests = trustedManifests ?? [manifest]
    self.artifactIdentity = artifactIdentity
    self.requiredCapacityBytes = artifactIdentity.requiredCapacityBytes
    self.candidateEnabled = candidateEnabled
    self.capacityProvider = capacityProvider
    self.isArchitectureSupported = architectureProvider()
    self.clock = clock
    self.transport = transport
    self.assessmentDidComplete = assessmentDidComplete
    self.cleanupWillBegin = cleanupWillBegin
    self.removalWillBegin = removalWillBegin
    self.resumeAuthenticationKeyProvider = resumeAuthenticationKeyProvider
    self.stateChangedAt = clock()
  }

  convenience init(
    modelRootURL: URL? = nil,
    fileManager: FileManager = .default,
    trustedManifests: [EnhancedModelManifest]? = nil,
    candidateEnabled: Bool = CleanDictationFeatures.enhancedLocalCandidateEnabled,
    capacityProvider: @escaping @Sendable () throws -> Int64 = {
      try EnhancedModelManager.liveAvailableCapacity()
    },
    architectureProvider: @escaping @Sendable () -> Bool = {
      EnhancedModelManager.isAppleSilicon()
    },
    clock: @escaping @Sendable () -> Date = { Date() },
    transport: any ModelDownloading = URLSessionModelDownloader(),
    assessmentDidComplete: @escaping @Sendable () -> Void = {},
    cleanupWillBegin: @escaping @Sendable () -> Void = {},
    removalWillBegin: @escaping @Sendable () -> Void = {},
    resumeAuthenticationKeyProvider: @escaping @Sendable () throws -> SymmetricKey = {
      try EnhancedModelManager.loadOrCreateResumeAuthenticationKey()
    }
  ) {
    let embedded = Self.embeddedManifestAndArtifactIdentity()
    self.init(
      modelRootURL: modelRootURL,
      fileManager: fileManager,
      manifest: embedded.manifest,
      artifactIdentity: embedded.artifactIdentity,
      trustedManifests: trustedManifests,
      candidateEnabled: candidateEnabled,
      capacityProvider: capacityProvider,
      architectureProvider: architectureProvider,
      clock: clock,
      transport: transport,
      assessmentDidComplete: assessmentDidComplete,
      cleanupWillBegin: cleanupWillBegin,
      removalWillBegin: removalWillBegin,
      resumeAuthenticationKeyProvider: resumeAuthenticationKeyProvider
    )
  }

  private static func embeddedManifestAndArtifactIdentity() -> (
    manifest: EnhancedModelManifest,
    artifactIdentity: EnhancedModelArtifactIdentity
  ) {
    let manifest = Self.embeddedManifest()
    let identity = EnhancedModelArtifactIdentity(
      sourceRepository: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml")!,
      modelID: manifest.modelID,
      revision: manifest.revision,
      license: "experimental-manifest-only",
      runtimeABI: "experimental-manifest-only",
      conversion: "experimental-manifest-only",
      quantization: "experimental-manifest-only",
      files: manifest.files.map {
        .init(path: $0.path, byteCount: $0.byteCount, sha256: $0.sha256)
      },
      downloadBytes: manifest.totalByteCount,
      installedBytes: manifest.totalByteCount,
      requiredCapacityBytes: Self.embeddedCompatibilityRequiredCapacity
    )
    return (manifest: manifest, artifactIdentity: identity)
  }

  // Compatibility only: this is the current experimental embedded Parakeet
  // manager path, never a signed admitted artifact or recommendation.
  private static let embeddedCompatibilityRequiredCapacity: Int64 = 1_197_261_950

  var admittedArtifactIdentity: EnhancedModelArtifactIdentity { artifactIdentity }

  var admittedManifest: EnhancedModelManifest { manifest }

  private func requireLiveTransferCapacity() throws {
    let availableBytes = try capacityProvider()
    guard availableBytes >= requiredCapacityBytes else {
      throw EnhancedModelManagerError.insufficientSpace(
        required: requiredCapacityBytes,
        available: availableBytes
      )
    }
  }

  private func performTransfer(
    from remoteURL: URL,
    resumeToken: ModelResumeToken?,
    progress: @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> ModelDownloadResult {
    try requireLiveTransferCapacity()
    return try await transport.download(
      from: remoteURL,
      resumeToken: resumeToken,
      progress: progress
    )
  }

  nonisolated private static func validateManifestPaths(
    _ manifest: EnhancedModelManifest
  ) throws {
    do {
      _ = try AdmittedModelPathRules.canonicalizeUnique(
        manifest.files.map(\.path)
      )
    } catch AdmittedModelPathError.unsafePath(let path) {
      throw EnhancedModelManagerError.invalidManifestPath(path)
    } catch AdmittedModelPathError.duplicatePath(_) {
      throw EnhancedModelManagerError.invalidManifest
    }
  }

  nonisolated private static func validateRelativePath(
    _ rawPath: String
  ) throws -> String {
    do {
      return try AdmittedModelPathRules.canonicalize(rawPath)
    } catch {
      throw EnhancedModelManagerError.invalidManifestPath(rawPath)
    }
  }

  func remoteURL(for file: EnhancedModelFile) throws -> URL {
    try Self.remoteURL(
      for: file,
      sourceRepository: artifactIdentity.sourceRepository,
      revision: artifactIdentity.revision
    )
  }

  nonisolated static func remoteURL(
    for file: EnhancedModelFile,
    sourceRepository: URL,
    revision: String
  ) throws -> URL {
    let canonicalPath = try validateRelativePath(file.path)
    try validateRevision(revision)
    let revisionRoot = sourceRepository
      .appendingPathComponent("resolve", isDirectory: true)
      .appendingPathComponent(revision, isDirectory: true)
    let artifactURL = canonicalPath.split(separator: "/").reduce(revisionRoot) {
      $0.appendingPathComponent(String($1))
    }
    var components = URLComponents(
      url: artifactURL,
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [URLQueryItem(name: "download", value: "true")]
    return components.url!
  }
}
#endif
~~~

`EnhancedModelManifestIdentity` has an explicit fieldwise initializer
`init(schemaVersion:modelID:revision:files:totalByteCount:)`; the artifact
projection uses that initializer rather than relying on a suppressed
memberwise initializer after `init(manifest:)` exists. The displayed
initializer is the existing manager initializer with every
stored-property assignment retained; it adds only the immutable artifact
identity and its checked required-capacity binding. The existing embedded
manager construction supplies that identity beside the actual manifest. The
source-compatible
`DictationModelCapability(modelRootURL:)` and
`DictationModelCapability(modelRootURL:candidateEnabled:architectureProvider:)`
convenience overloads preserve the current call surface and delegate to the
manifest/artifact designated initializer with exactly
`Self.embeddedManifestAndArtifactIdentity()`. The designated initializer's
declared label order is
`modelRootURL:fileManager:manifest:artifactIdentity:trustedManifests:` followed
by the existing dependency labels. Their default capacity provider
reads the live volume's `volumeAvailableCapacityForImportantUsage`, and their
default architecture provider performs the existing `uname` arm64 check;
neither uses a test-success default. They accept no optional custom manifest and
use only the current experimental Parakeet manifest plus its matching
compatibility identity; they do not construct an admitted descriptor, catalog
recommendation, or installer. Any custom manifest must use the designated
initializer and pass its `artifactIdentity` explicitly, using the declared
argument order above before the existing dependency labels.
The source-compatible embedded path preserves the current experimental manager
capacity of exactly `1_197_261_950` bytes. That constant is used only for the
embedded compatibility identity; signed admitted artifacts carry their own
validated checked `requiredCapacityBytes` and never use it.
At the start of the existing `validateManifest`, call
`try validateManifestPaths(manifest)` before checksum or byte-count checks;
this is the manager-side regression point for the shared path rule.
Both existing `DictationModelCapability` call shapes remain unchanged. The
adapter never substitutes a
descriptor for that value, and the URL root no longer hard-codes a candidate
repository. Keep the manager's existing `validateRevision` check and replace
its path body with `AdmittedModelPathRules.canonicalize`; call
`validateManifestPaths` before the existing checksum/byte loop so duplicate
canonical paths fail before any URL is built. `remoteURL` uses the canonical
path returned by `validateRelativePath`, so empty/absolute paths, empty
components, `.`, `..`, backslashes, single- or double-encoded traversal, and
duplicate manifest paths share the descriptor's exact rule. Preserve the existing
`?download=true` query item exactly. Its verified required-capacity calculation
is the artifact identity's checked `requiredCapacityBytes`, which the manager
stores as its transfer gate. Immediately before each existing network transfer
in install, repair, and update, wrap that exact transport call in
`performTransfer(from:resumeToken:progress:)` with the existing callback that
forwards received bytes to `updateProgress`; the wrapper
retains the existing `transport.download(from:resumeToken:progress:)` call and
re-reads `capacityProvider` immediately before it, throwing
`insufficientSpace` when live available bytes are below the bound. The existing
`EnhancedModelManager.requiredAvailableCapacity` compatibility symbol may
remain for legacy behavior, but this admitted path never reads that Parakeet
constant; it uses only the signed artifact's checked requirement. The catalog
and manager therefore use the same signed descriptor requirement.
The URL test passes a non-default source repository and revision and asserts the
full resolved path plus `?download=true`, proving the explicit identity is not
ignored.
The test-only `TestManagers` helpers may inject `capacityProvider: { Int64.max }`
and `architectureProvider: { true }`; those values are never production or
compatibility defaults. `TestPaths.temporaryDirectory()` creates one unique,
canonical directory below `FileManager.default.temporaryDirectory`; every
`TestManagerFixture` owns and removes only its root, and direct compatibility
call-shape tests use `defer` to remove both named temporary roots.
The manager path regression passes the descriptor's complete unsafe-path table
through `remoteURL` and asserts `invalidManifestPath` before URL construction;
a separate duplicate-normalized-manifest fixture calls `download()` with
`ModelDownloadingProbe` and asserts `invalidManifest` plus zero transport calls.

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
  private var stateSubscription: AnyCancellable?
  private var operationTask: Task<Void, Never>?
  private var operationID: UUID?
  private var lastReceivedBytes: Int64 = 0
  private var managerReady = false
  private var cancellationRequested = false

  init(
    manager: EnhancedModelManager,
    descriptor: AdmittedModelDescriptor,
    startup: @escaping @MainActor () async throws -> Void,
    calibrate: @escaping @MainActor () async throws -> Void
  ) throws {
    try AdmittedModelArtifactBinding.validate(
      descriptor: descriptor,
      artifact: manager.admittedArtifactIdentity,
      manifest: manager.admittedManifest
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

  private func beginOperationSubscriptions() {
    operationID = UUID()
    managerReady = false
    cancellationRequested = false
    lastReceivedBytes = 0
    progressSubscription = manager.$byteProgress
      .compactMap { $0 }
      .sink { [weak self] progress in
        guard let self,
              self.operationID != nil, !self.cancellationRequested,
              progress.totalBytes == self.descriptor.downloadBytes,
              progress.receivedBytes >= 0,
              progress.receivedBytes <= progress.totalBytes,
              progress.receivedBytes > self.lastReceivedBytes else { return }
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
    stateSubscription = manager.$state
      .sink { [weak self] state in
        self?.publishManagerState(state)
      }
  }

  private func publishManagerState(
    _ state: EnhancedModelState,
    allowOutsideOperation: Bool = false
  ) {
    guard allowOutsideOperation
      || (operationID != nil && !cancellationRequested) else { return }
    switch state {
    case .notInstalled:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .notInstalled,
        lastError: nil
      ))
    case .downloading(_):
      break // byteProgress is the authoritative live download phase.
    case .verifying:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .verifying,
        lastError: nil
      ))
    case .installing:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .installing,
        lastError: nil
      ))
    case .ready:
      managerReady = true
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .ready,
        lastError: nil
      ))
    case .updateAvailable:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .updateAvailable,
        lastError: nil
      ))
    case .repairRequired(let message):
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .repairRequired(message: message),
        lastError: message
      ))
    case .removing:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .removing,
        lastError: nil
      ))
    }
  }

  private func endOperation() {
    operationID = nil
    progressSubscription?.cancel()
    progressSubscription = nil
    stateSubscription?.cancel()
    stateSubscription = nil
  }

  private func runManagerOperation(
    initialPhase: AdmittedModelInstallPhase,
    runsStartupAndCalibration: Bool,
    _ operation: @escaping @MainActor () async throws -> Void
  ) async {
    guard operationTask == nil else {
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .failed(message: "Another model operation is already running."),
        lastError: "Another model operation is already running."
      ))
      return
    }
    beginOperationSubscriptions()
    publish(.init(
      recommendation: .recommended(descriptor),
      phase: initialPhase,
      lastError: nil
    ))
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.endOperation() }
      do {
        try await operation()
        guard !Task.isCancelled, !self.cancellationRequested else {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .cancelled,
            lastError: "Model operation cancelled."
          ))
          return
        }
        guard !runsStartupAndCalibration || self.managerReady || self.manager.state == .ready else {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .failed(message: "The model did not reach ready state."),
            lastError: "The model did not reach ready state."
          ))
          return
        }
        guard runsStartupAndCalibration else { return }
        self.publish(.init(
          recommendation: .recommended(self.descriptor),
          phase: .starting,
          lastError: nil
        ))
        try await self.startup()
        guard !Task.isCancelled, !self.cancellationRequested else {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .cancelled,
            lastError: "Model operation cancelled."
          ))
          return
        }
        self.publish(.init(
          recommendation: .recommended(self.descriptor),
          phase: .calibrating,
          lastError: nil
        ))
        try await self.calibrate()
        guard !Task.isCancelled, !self.cancellationRequested else {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .cancelled,
            lastError: "Model operation cancelled."
          ))
          return
        }
        self.publish(.init(
          recommendation: .recommended(self.descriptor),
          phase: .installed,
          lastError: nil
        ))
      } catch is CancellationError {
        self.publish(.init(
          recommendation: .recommended(self.descriptor),
          phase: .cancelled,
          lastError: "Model operation cancelled."
        ))
      } catch {
        if self.cancellationRequested || Task.isCancelled {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .cancelled,
            lastError: "Model operation cancelled."
          ))
        } else if case .repairRequired(let message) = self.manager.state {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .repairRequired(message: message),
            lastError: message
          ))
        } else {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .failed(message: String(describing: error)),
            lastError: String(describing: error)
          ))
        }
      }
    }
    operationTask = task
    await task.value
    operationTask = nil
  }

  func install() async {
    await runManagerOperation(
      initialPhase: .downloading(
        receivedBytes: 0,
        totalBytes: descriptor.downloadBytes
      ),
      runsStartupAndCalibration: true
    ) { try await self.manager.download() }
  }

  func repair() async {
    await runManagerOperation(
      initialPhase: .downloading(
        receivedBytes: 0,
        totalBytes: descriptor.downloadBytes
      ),
      runsStartupAndCalibration: true
    ) { try await self.manager.repair() }
  }

  func update() async {
    await runManagerOperation(
      initialPhase: .downloading(
        receivedBytes: 0,
        totalBytes: descriptor.downloadBytes
      ),
      runsStartupAndCalibration: true
    ) { try await self.manager.update() }
  }

  func refresh() async {
    guard operationTask == nil else { return }
    var refreshSubscription: AnyCancellable?
    refreshSubscription = manager.$state.sink { [weak self] state in
      self?.publishManagerState(state, allowOutsideOperation: true)
    }
    defer { refreshSubscription?.cancel() }
    await manager.refreshState()
    publishManagerState(manager.state, allowOutsideOperation: true)
  }

  func cancel() {
    guard let operationTask else { return }
    cancellationRequested = true
    operationTask.cancel()
  }

  func remove() async {
    await runManagerOperation(
      initialPhase: .removing,
      runsStartupAndCalibration: false
    ) { try await self.manager.deleteModel() }
  }
}
#endif
~~~

Map manager states to the phase enum through both synchronous `@MainActor`
Combine subscriptions. The byte-progress sink publishes monotonic
`downloading(receivedBytes:totalBytes:)` snapshots; the state sink publishes
`verifying`, `installing`, `ready`, `updateAvailable`, `repairRequired`, and
`removing` as they occur. No `receive(on:)` is used, so a final byte update is
delivered before the operation's teardown. One `operationTask` owns each
manager `download`, `repair`, `update`, or `deleteModel` call; each escaping
installer closure names `self.manager` explicitly. `cancel()` sets
the cancellation flag and cancels that task; the manager operation is the
task's awaited child, so cancellation propagates into the manager's existing
`ModelDownloading`/URLSession downloader cancellation handler. The task keeps
its handle until `await task.value` returns, then clears it after the deferred
subscription teardown; this prevents a synchronously completing operation from
leaving a stale task handle. It publishes
exactly `phase: .cancelled` with `lastError: "Model operation cancelled."` and
never publishes `.installed` afterward. After manager `.ready`, the task
publishes `.starting`, awaits startup, publishes `.calibrating`, awaits
calibration, and only then publishes `.installed`. On checksum, size, path,
capacity, transport, startup, or calibration failure, set an actionable
`failed` or `repairRequired` message and retain the safe previous installation
when the manager does. Removal calls only `self.manager.deleteModel()`. The
ordinary release uses `BuiltInAdmittedModelInstaller` and cannot reach the
manager.

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
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/AdmittedModelInstallation.swift \
    Tests/FleckAppTests/AdmittedModelInstallationTests.swift \
    Sources/FleckApp/EnhancedModelManager.swift \
    Tests/FleckAppTests/EnhancedModelManagerTests.swift \
  | sort -u
)"
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

**Consumes:** Task 1 descriptor/catalog and
`AdmittedModelHardwareProfile`, Task 2 installer snapshot/action methods, and
the existing native Settings structure. The factory boundary must construct the
catalog from the signed descriptor and profile before it can construct the
manager installer.

**Produces:** `AdmittedModelSettingsPresentation`,
`AdmittedModelSettingsViewModel`, `AdmittedModelSignedConfiguration`, the
`makeAdmittedModelInstaller` boundary, exactly one Settings card, and
phase-specific Settings/error copy. The factory returns a recommended installer
only for an exact `.recommended(descriptor)` catalog result; all architecture,
language, and staging-capacity mismatches return a non-operating built-in/failure
snapshot with zero transport calls. The Task 3-owned presentation test file also
proves the recommendation card's VoiceOver label/value, exact supported
architecture/language strings, keyboard focus, and finite phase/progress text.
Built-in and failed presentations carry empty custom compatibility arrays.

### TDD red

- [ ] **Step 1: Write presentation tests before changing Settings.**

~~~swift
import Foundation
import Testing

@testable import FleckApp

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
  #expect(presentation.primaryActionLabel == nil)
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
  #expect(presentation.primaryActionLabel == "Install")
  #expect(presentation.identity == descriptor.modelID)
  #expect(presentation.revision == descriptor.revision)
  #expect(presentation.license == descriptor.license)
  #expect(presentation.downloadBytes == descriptor.downloadBytes)
  #expect(presentation.installedBytes == descriptor.installedBytes)
  #expect(presentation.checksums == descriptor.files.map(\.sha256))
  #expect(presentation.supportedArchitectures == descriptor.architectures)
  #expect(presentation.supportedLanguages == descriptor.languages)
}

@Test func recommendationCardHasVoiceOverMetadataAndKeyboardFocus() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(descriptor),
      phase: .notInstalled,
      lastError: nil
    )
  )
  #expect(presentation.accessibilityLabel == "Admitted model recommendation")
  #expect(presentation.accessibilityValue.contains(descriptor.modelID))
  #expect(presentation.accessibilityValue.contains(descriptor.revision))
  #expect(presentation.accessibilityValue.contains(
    descriptor.architectures.joined(separator: ", ")
  ))
  #expect(presentation.accessibilityValue.contains(
    descriptor.languages.joined(separator: ", ")
  ))
  #expect(presentation.detail.contains(
    "Supported architectures: \(descriptor.architectures.joined(separator: ", "))"
  ))
  #expect(presentation.detail.contains(
    "Supported languages: \(descriptor.languages.joined(separator: ", "))"
  ))
  #expect(presentation.isKeyboardFocusable)
}

@Test func builtInAndFailureStatesDoNotInventCustomCompatibilityValues() {
  for phase in [AdmittedModelInstallPhase.builtIn,
                .failed(message: "invalid signed configuration")] {
    let presentation = AdmittedModelSettingsPresentation(
      snapshot: .init(recommendation: .builtIn, phase: phase, lastError: nil)
    )
    #expect(presentation.supportedArchitectures.isEmpty)
    #expect(presentation.supportedLanguages.isEmpty)
  }
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

@Test func inProgressCardHasFinitePhaseAndProgressAccessibilityText() {
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(TestDescriptors.tinyAdmittedASR),
      phase: .downloading(receivedBytes: 4, totalBytes: 8),
      lastError: nil
    )
  )
  #expect(presentation.accessibilityLabel == "Admitted model installation")
  #expect(presentation.accessibilityValue == "Downloading, 4 of 8 bytes")
  #expect(presentation.progressAccessibilityValue == "4 of 8 bytes")
  #expect(!presentation.accessibilityValue.contains("Loading"))
}

@Test func readyAndCancelledHaveFiniteSettingsCopy() {
  for phase in [AdmittedModelInstallPhase.ready, .cancelled] {
    let presentation = AdmittedModelSettingsPresentation(
      snapshot: .init(
        recommendation: .recommended(TestDescriptors.tinyAdmittedASR),
        phase: phase,
        lastError: nil
      )
    )
    #expect(!presentation.title.isEmpty)
    #expect(!presentation.detail.isEmpty)
    #expect(!presentation.detail.contains("Loading"))
  }
}

@MainActor
final class InstallerActionProbe: AdmittedModelInstalling {
  init(holdsOperations: Bool = false)
  private(set) var snapshot: AdmittedModelInstallationSnapshot
  var updates: AsyncStream<AdmittedModelInstallationSnapshot> { get }
  func count(_ action: AdmittedModelSettingsAction) -> Int
  func waitUntilStarted(_ action: AdmittedModelSettingsAction) async
  func waitUntilPhase(_ phase: AdmittedModelInstallPhase) async
  func refresh() async
  func install() async
  func cancel()
  func repair() async
  func update() async
  func remove() async
}

@Test @MainActor
func settingsActionsDispatchExactlyOnceAndUpdatePresentation() async {
  let rows: [(AdmittedModelSettingsAction, AdmittedModelInstallPhase)] = [
    (.install, .ready),
    (.repair, .repairRequired(message: "repair")),
    (.update, .updateAvailable),
    (.remove, .removing)
  ]
  for (action, expectedPhase) in rows {
    let probe = InstallerActionProbe()
    let viewModel = AdmittedModelSettingsViewModel(installer: probe)
    viewModel.perform(action)
    await probe.waitUntilPhase(expectedPhase)
    await Task.yield()
    #expect(probe.count(action) == 1)
    #expect(viewModel.presentation.phase == expectedPhase)
  }

  let cancellingProbe = InstallerActionProbe(holdsOperations: true)
  let cancellingViewModel = AdmittedModelSettingsViewModel(installer: cancellingProbe)
  cancellingViewModel.perform(.install)
  await cancellingProbe.waitUntilStarted(.install)
  cancellingViewModel.perform(.repair)
  cancellingViewModel.perform(.update)
  cancellingViewModel.perform(.remove)
  cancellingViewModel.perform(.cancel)
  cancellingViewModel.perform(.cancel)
  await cancellingProbe.waitUntilPhase(.cancelled)
  await Task.yield()
  #expect(cancellingProbe.count(.install) == 1)
  #expect(cancellingProbe.count(.repair) == 0)
  #expect(cancellingProbe.count(.update) == 0)
  #expect(cancellingProbe.count(.remove) == 0)
  #expect(cancellingProbe.count(.cancel) == 1)
  #expect(cancellingViewModel.presentation.phase == .cancelled)
}

@Test @MainActor
func currentAppConstructionDefaultsToBuiltInInstaller() {
  let installer = makeAdmittedModelInstaller()
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.phase == .builtIn)
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test @MainActor
func nilSignedConfigurationUsesBuiltInInstaller() {
  let installer = makeAdmittedModelInstaller(signedConfiguration: nil)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.phase == .builtIn)
}

func supportedHardware(
  for descriptor: AdmittedModelDescriptor,
  availableBytes: Int64? = nil
) -> AdmittedModelHardwareProfile {
  .init(
    architecture: descriptor.architectures[0],
    requestedLanguages: [descriptor.languages[0]],
    availableBytes: availableBytes ?? descriptor.requiredCapacityBytes
  )
}

struct SignedTestConfiguration {
  let value: AdmittedModelSignedConfiguration
  let fixture: TestManagerFixture
}

func signedConfiguration(
  descriptor: AdmittedModelDescriptor,
  hardware: AdmittedModelHardwareProfile,
  transport: ModelDownloadingProbe
) -> SignedTestConfiguration {
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: transport
  )
  return SignedTestConfiguration(
    value: AdmittedModelSignedConfiguration(
      rawDescriptor: TestDescriptors.raw(descriptor),
      hardware: hardware,
      manager: fixture.manager,
      startup: { },
      calibrate: { }
    ),
    fixture: fixture
  )
}

@Test @MainActor
func architectureMismatchReturnsBuiltInFailureWithoutTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: .init(
      architecture: "x86_64",
      requestedLanguages: [descriptor.languages[0]],
      availableBytes: descriptor.requiredCapacityBytes
    ),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func languageMismatchReturnsBuiltInFailureWithoutTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      requestedLanguages: ["zh-CN"],
      availableBytes: descriptor.requiredCapacityBytes
    ),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func mixedRequestedLanguagesReturnBuiltInFailureWithoutTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  #expect(descriptor.languages == ["en-US"])
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      requestedLanguages: ["en-US", "zh-CN"],
      availableBytes: descriptor.requiredCapacityBytes
    ),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func insufficientStagingCapacityReturnsBuiltInFailureWithoutTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let availableBytes = descriptor.downloadBytes + 1
  #expect(availableBytes > descriptor.downloadBytes)
  #expect(availableBytes < descriptor.requiredCapacityBytes)
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: supportedHardware(for: descriptor, availableBytes: availableBytes),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func supportedHardwareProfileReachesRecommendedInstallerWithoutStartingTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: supportedHardware(for: descriptor),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .recommended(descriptor))
  #expect(installer.snapshot.phase == .notInstalled)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func invalidSignedDescriptorIsCaughtAsNonOperatingBuiltInFailure() {
  let raw = TestDescriptors.make(TestDescriptors.neutralAdmitted, modelID: "")
  let fixture = try! TestManagers.manager(
    descriptor: TestDescriptors.tinyAdmittedASR,
    artifactIdentity: TestArtifacts.identity(matching: TestDescriptors.tinyAdmittedASR),
    manifest: TestManifests.tiny,
    transport: ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  )
  defer { fixture.cleanup() }
  let configuration = AdmittedModelSignedConfiguration(
    rawDescriptor: raw,
    hardware: supportedHardware(for: TestDescriptors.tinyAdmittedASR),
    manager: fixture.manager,
    startup: { },
    calibrate: { }
  )
  let installer = makeAdmittedModelInstaller(signedConfiguration: configuration)
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
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identityWith(revision: "wrong"),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let configuration = AdmittedModelSignedConfiguration(
    rawDescriptor: TestDescriptors.raw(descriptor),
    hardware: supportedHardware(for: descriptor),
    manager: fixture.manager,
    startup: { },
    calibrate: { }
  )
  let installer = makeAdmittedModelInstaller(signedConfiguration: configuration)
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

Expected failure: the presentation, action, snapshot mapping, view-model,
optional signed-configuration, and installer-factory symbols do not exist.

### Minimal implementation, green, and checkpoint

- [ ] **Step 3: Implement pure phase presentation.**

~~~swift
enum AdmittedModelSettingsAction: Equatable {
  case install, cancel, repair, update, remove
}

struct AdmittedModelSettingsPresentation: Equatable {
  let title: String
  let detail: String
  let phase: AdmittedModelInstallPhase
  let identity: String?
  let revision: String?
  let license: String?
  let checksums: [String]
  let supportedArchitectures: [String]
  let supportedLanguages: [String]
  let downloadBytes: Int64?
  let installedBytes: Int64?
  let progress: Double?
  let progressAccessibilityValue: String?
  let accessibilityLabel: String
  let accessibilityValue: String
  let isKeyboardFocusable: Bool
  let primaryAction: AdmittedModelSettingsAction?
  let primaryActionLabel: String?
  let showsModelPicker: Bool

  private static func compatibilityValues(
    for recommendation: AdmittedModelRecommendation
  ) -> (architectures: [String], languages: [String]) {
    guard case .recommended(let descriptor) = recommendation else {
      return ([], [])
    }
    return (descriptor.architectures, descriptor.languages)
  }
}
~~~

`AdmittedModelSettingsPresentation.init(snapshot:)` stores
`phase = snapshot.phase` and maps every phase to finite title/detail/action
text. Use exact byte counts, exact
identity/revision/license/checksum strings, and derive
`supportedArchitectures` and `supportedLanguages` only from the validated
descriptor in `.recommended` (the initializer calls
`compatibilityValues(for:)`). For `.builtIn` and `.failed` snapshots, both
arrays are empty; they must not invent custom compatibility values. Include
the exact arrays in the recommendation detail and stable VoiceOver
label/value. The recommendation card's Install button is keyboard-focusable
and uses the presentation values directly:

~~~swift
if !presentation.supportedArchitectures.isEmpty {
  Text("Supported architectures: \(presentation.supportedArchitectures.joined(separator: ", "))")
  Text("Supported languages: \(presentation.supportedLanguages.joined(separator: ", "))")
}

if let action = presentation.primaryAction,
   let label = presentation.primaryActionLabel {
  Button(label) {
    perform(action)
  }
  .focusable(presentation.isKeyboardFocusable)
  .accessibilityLabel(presentation.accessibilityLabel)
  .accessibilityValue(presentation.accessibilityValue)
}
~~~

The Task 3-owned `AdmittedModelSettingsPresentationTests` file asserts the
recommendation label, identity/revision/license/checksum/size values, exact
supported architecture/language strings in both detail and VoiceOver value,
keyboard focus, finite phase copy, and exact in-progress byte value. It also
asserts that built-in and failed states expose empty compatibility arrays. Use
no indefinite Loading text and no automatic action on view appearance. Its
installer-action probe also asserts
that Install, Cancel, Repair, Update, and Remove each dispatch exactly once and
that each resulting snapshot reaches the presentation. A held operation test
invokes Repair, Update, and Remove while Install is held, then invokes Cancel
twice; it proves the three extra operation counts stay zero and Cancel occurs
exactly once.

- [ ] **Step 4: Add the observable action view model and wire the native UI.**

~~~swift
@MainActor
final class AdmittedModelSettingsViewModel: ObservableObject {
  @Published private(set) var presentation:
    AdmittedModelSettingsPresentation
  private let installer: any AdmittedModelInstalling
  private var updatesTask: Task<Void, Never>?
  private var actionTask: Task<Void, Never>?
  private var cancellationSent = false

  init(installer: any AdmittedModelInstalling) {
    self.installer = installer
    self.presentation = .init(snapshot: installer.snapshot)
    subscribeToUpdates()
  }
  func refresh() async
  func perform(_ action: AdmittedModelSettingsAction) {
    if action == .cancel {
      guard !cancellationSent else { return }
      cancellationSent = true
      installer.cancel()
      return
    }
    guard actionTask == nil else { return }
    cancellationSent = false
    actionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        self.actionTask = nil
        self.cancellationSent = false
      }
      switch action {
      case .install:
        await self.installer.install()
      case .repair:
        await self.installer.repair()
      case .update:
        await self.installer.update()
      case .remove:
        await self.installer.remove()
      case .cancel:
        self.installer.cancel()
      }
    }
  }

  deinit {
    updatesTask?.cancel()
    actionTask?.cancel()
  }

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

`perform(_:)` has no default or no-op action branch: every enum case maps to the
corresponding installer method. Install, Repair, Update, and Remove are guarded
by one `actionTask`; a second operation click while it is non-nil is ignored.
Cancel is allowed to interrupt that task exactly once, guarded by
`cancellationSent`, and the task's `defer` clears both guards after the
installer returns. The probe tests wait for each published phase and assert the
exact per-action count, including zero queued Repair/Update/Remove calls while
Install is held and one Cancel for two cancellation clicks.

In `FleckApp.swift`, construct the empty catalog and
`BuiltInAdmittedModelInstaller` for ordinary release. Under the existing
compile-gated configuration, inject an optional
`AdmittedModelSignedConfiguration` whose manager and exact
`AdmittedModelHardwareProfile` have already been created by the caller; the
current app passes `nil` in both ordinary and gated builds. Store one view model
on `DictationRuntime`; do not create parallel operation dictionaries or a second
manager. Invalid signed configuration, hardware recommendation, or artifact
binding must be caught at this boundary so Settings construction never fails
and Apple Speech/deterministic cleanup remains active.

The construction boundary is explicit:

~~~swift
#if CLEAN_DICTATION_ENHANCED_CANDIDATE
let signedConfiguration: AdmittedModelSignedConfiguration? = nil
let installer = makeAdmittedModelInstaller(
  signedConfiguration: signedConfiguration
)
#else
let installer = makeAdmittedModelInstaller()
#endif
~~~

`AdmittedModelSignedConfiguration` is owned by
`AdmittedModelSettingsPresentation.swift` and is compile-gated with the
manager:

~~~swift
#if CLEAN_DICTATION_ENHANCED_CANDIDATE
struct AdmittedModelSignedConfiguration {
  let rawDescriptor: RawAdmittedModelDescriptor
  let hardware: AdmittedModelHardwareProfile
  let manager: EnhancedModelManager
  let startup: @MainActor () async throws -> Void
  let calibrate: @MainActor () async throws -> Void
}

@MainActor
func makeAdmittedModelInstaller(
  signedConfiguration: AdmittedModelSignedConfiguration? = nil
) -> any AdmittedModelInstalling {
  guard let signedConfiguration else {
    return BuiltInAdmittedModelInstaller()
  }
  do {
    let descriptor = try AdmittedModelDescriptor(
      validating: signedConfiguration.rawDescriptor
    )
    let catalog = AdmittedModelCatalog(
      signedDescriptor: descriptor,
      hardware: signedConfiguration.hardware
    )
    guard case .recommended(let recommended) = catalog.recommendation(),
          recommended == descriptor else {
      return FailedAdmittedModelInstaller(
        message: "This model is not supported by the current Mac, language, or available staging capacity."
      )
    }
    return try EnhancedModelManagerInstaller(
      manager: signedConfiguration.manager,
      descriptor: descriptor,
      startup: signedConfiguration.startup,
      calibrate: signedConfiguration.calibrate
    )
  } catch {
    return FailedAdmittedModelInstaller(message: String(describing: error))
  }
}
#else
@MainActor
func makeAdmittedModelInstaller() -> any AdmittedModelInstalling {
  BuiltInAdmittedModelInstaller()
}
#endif
~~~

`FailedAdmittedModelInstaller` is non-operating and exists only to render the
actionable Settings error. Its `.builtIn` recommendation does not replace the
coordinator's existing Apple Speech/deterministic-cleanup dependencies, so a
bad signed descriptor, unsupported hardware/language profile, insufficient
staging capacity, or artifact binding leaves the production fallback usable and
performs no transport work. The catalog result is compared to the same
validated descriptor before `EnhancedModelManagerInstaller` is constructed;
there is no silent recommendation or install path.

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
`downloading`, `verifying`, `installing`, `ready`, `starting`, `calibrating`,
`installed`, `repairRequired`, `removing`, `cancelled`, or `failed` copy. Errors
name the action and next recovery step. Do not modify `Sources/FleckApp/DictationCapsule.swift`;
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
! rg -n 'Picker\("Engine"|Enhanced Local|ModelConsentView|Download Enhanced Model|Loading' Sources/FleckApp/SettingsView.swift
git diff --
worktree_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$worktree_inventory" = "$(
  printf '%s\n' \
    Sources/FleckApp/AdmittedModelSettingsPresentation.swift \
    Tests/FleckAppTests/AdmittedModelSettingsPresentationTests.swift \
    Sources/FleckApp/SettingsView.swift \
    Sources/FleckApp/FleckApp.swift \
    Tests/FleckAppTests/DictationSettingsTests.swift \
    Tests/FleckAppTests/DictationAvailabilityTests.swift \
  | sort -u
)"
git add Sources/FleckApp/AdmittedModelSettingsPresentation.swift Sources/FleckApp/SettingsView.swift Sources/FleckApp/FleckApp.swift Tests/FleckAppTests/AdmittedModelSettingsPresentationTests.swift Tests/FleckAppTests/DictationSettingsTests.swift Tests/FleckAppTests/DictationAvailabilityTests.swift
git commit -m "feat: present admitted model recommendation"
~~~

Expected scan: no normal model picker, old consent surface, or indefinite
Loading copy remains. The parent reruns the default and candidate-gated checks,
inspects the UI diff, and confirms the four gated hardware-factory cases:
architecture mismatch, language mismatch, insufficient staging capacity, and
one supported profile. Each unsupported case must retain the built-in/failure
snapshot with zero transport calls, while the supported case must reach the
exact recommended descriptor. The parent then obtains the final fresh Sol ship
verdict.

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

The parent inspects that only the file map changed; raw input never reaches the
catalog or installer; both descriptor checked-add overflow cases and complete
requested-language subset gating pass; the compatibility initializer uses only
the embedded manifest; the explicit URL test preserves source/revision and
`?download=true`; default configuration constructs the built-in installer;
candidate-gated tests use only injected transport/fixtures; byte progress is
truthful; Task 3's own Settings tests prove accessibility; manager verification
and filesystem ownership remain authoritative; and no model-weight path was
written. The known viewport assertion is classified separately if present.

## Final real-checkout packaging checkpoint

The source tasks form a dependent accepted commit chain. The parent has already
verified that root
`ab886d9968e6c1ae088d18e085938bec8a80f7c9` is an ancestor of accepted base
`4212314398853091fa85e7aec18318b9650e8604`, and that `AGENTS.md` is unchanged
between those two commits. After every source task has parent verification and
a fresh Sol `ship`, the final parent supplies the exact accepted implementation
SHA through `FINAL_ACCEPTED_SHA`; the following local checkpoint must pass
before packaging. It does not merge, rebase, cherry-pick, push, or modify
`AGENTS.md`:

~~~bash
root=/Users/harryjin/Fleck
final_accepted_sha="${FINAL_ACCEPTED_SHA:?the final accepted implementation SHA must come from the parent ship handoff}"
final_branch=codex/local-dictation-real-app-final
starting_root_sha=ab886d9968e6c1ae088d18e085938bec8a80f7c9
snapshot_dir="$(mktemp -d "${TMPDIR:-/tmp}/fleck-root-handoff.XXXXXX")"
cd "$root"
test "$(git rev-parse --show-toplevel)" = "$root"
test "$(git rev-parse HEAD)" = "$starting_root_sha"
test "$(git branch --show-current)" = "main"
test "$(git status --short)" = " M AGENTS.md"
git merge-base --is-ancestor "$starting_root_sha" 4212314398853091fa85e7aec18318b9650e8604
git merge-base --is-ancestor 4212314398853091fa85e7aec18318b9650e8604 "$final_accepted_sha"
git diff --quiet "$starting_root_sha" "$final_accepted_sha" -- AGENTS.md
git rev-parse HEAD > "$snapshot_dir/head.before"
git status --short --branch > "$snapshot_dir/status.before"
git hash-object AGENTS.md > "$snapshot_dir/agents.hash.before"
git diff --binary -- AGENTS.md > "$snapshot_dir/agents.diff.before"
test "$(git status --short)" = " M AGENTS.md"
test -z "$(git diff --cached --name-only)"
test -z "$(git ls-files --others --exclude-standard)"
test -z "$(git ls-files -u)"
test ! -e .git/MERGE_HEAD
test ! -e .git/rebase-merge
test ! -e .git/rebase-apply
test ! -e .git/CHERRY_PICK_HEAD
test -z "$(git branch --list "$final_branch")"
git switch --create "$final_branch" "$final_accepted_sha"
test "$(git rev-parse HEAD)" = "$final_accepted_sha"
test "$(git branch --show-current)" = "$final_branch"
git diff --quiet "$starting_root_sha" "$final_accepted_sha" -- AGENTS.md
test "$(git hash-object AGENTS.md)" = "$(cat "$snapshot_dir/agents.hash.before")"
git diff --binary -- AGENTS.md > "$snapshot_dir/agents.diff.after"
cmp -s "$snapshot_dir/agents.diff.before" "$snapshot_dir/agents.diff.after"
test "$(git status --short)" = " M AGENTS.md"
test -z "$(git diff --cached --name-only)"
test -z "$(git ls-files --others --exclude-standard)"
test -z "$(git ls-files -u)"
test ! -e .git/MERGE_HEAD
test ! -e .git/rebase-merge
test ! -e .git/rebase-apply
test ! -e .git/CHERRY_PICK_HEAD
post_switch_inventory="$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)"
test "$post_switch_inventory" = "AGENTS.md"

swift test --disable-automatic-resolution --no-parallel
./Scripts/build-fleck-app.sh
test -d /Users/harryjin/Fleck/.build/Fleck.app
codesign --verify --deep --strict /Users/harryjin/Fleck/.build/Fleck.app
open /Users/harryjin/Fleck/.build/Fleck.app
~~~

Any failed snapshot, ancestry, branch, dirty-file, unmerged-state, or
in-progress-operation check aborts before the build. Run the build script
exactly as committed; do not copy it, add another script, or use an
isolated-worktree bundle as evidence. The primary may launch the app and
inspect Settings, but must report only observed process and UI state.

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
