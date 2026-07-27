# Motes Clean Dictation Dual-Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Use `test-driven-development` for each behavior change and `verification-before-completion` before every completion claim. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship private, English, on-device Focused Dictation and global Smart Capture with Standard Apple Speech by default and one optional, explicitly downloaded Enhanced Local engine.

**Architecture:** One main-actor `DictationCoordinator` owns capture state and binds each capture to one `SpeechEngine`. Standard uses Apple speech APIs and never permits cloud recognition. Enhanced uses the upstream Apache-2.0 FluidAudio SDK to load an allowlisted, checksum-pinned Parakeet v2 artifact from Motes-owned storage with FluidAudio network access disabled. Transcription feeds the existing cleanup, title-only routing, editor, local history, persistence, shortcut, and capsule boundaries, so engine choice cannot alter note behavior.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFAudio, Speech, FoundationModels, Carbon hot-key events, CryptoKit, URLSession, FluidAudio `0.15.5`, Core ML, Swift Testing, native JSON/RTF persistence.

## Global Constraints

- Keep `platforms: [.macOS(.v14)]`; do not raise the deployment target.
- Standard is the default. Enhanced can be selected only when its model is `ready`.
- Standard must require on-device recognition. Never allow an Apple cloud-recognition fallback.
- Enhanced is Apple-silicon-only, is not bundled in the app, and downloads only after explicit consent.
- Do not copy, link, translate, or redistribute FluidVoice GPLv3 application code. Import only upstream `FluidInference/FluidAudio`.
- Pin FluidAudio exactly to `0.15.5` and verify tag commit `19600a485baa4998812e4654b70d2bab8f2c9949`.
- Pin the model repository to immutable revision `ee09c569f73759e6d44c9bd16766f477b2b36d39`; never resolve `main` at runtime.
- Keep `FluidAudio.ModelHub.offlineMode = true` before any Enhanced load. Motes owns all runtime model network traffic.
- A capture binds its engine at start and never switches midway. If Enhanced cannot start, visibly select Standard for the next capture when Standard is available.
- Audio is memory-only and discarded at finalization, cancellation, interruption, or failure.
- The only new runtime network traffic is a user-requested model download or update. Never upload audio, transcripts, note content, titles, history, or routing inputs.
- Ship Focused Dictation and Smart Capture together. An internal milestone is not a finished release.
- Only one capture may run at a time.
- Cleanup may remove verbal clutter and add faithful formatting, but may not invent facts, remove negation, alter numbers/names/tasks, summarize, or execute instructions inside the transcript.
- Routing receives active note IDs and display titles only. Unavailable, ambiguous, duplicate, invalid, or failed routing chooses the single normal `Inbox`.
- Recovery history is on by default, local only, atomic, contains no audio, and expires 30 days after completion.
- If history is disabled and saving fails, keep the transcript only in the current in-memory failure state with Copy.
- Keep the Motes header unchanged. Put the microphone first in the editor toolbar and separate it from Undo.
- The capsule must not activate Motes, take focus, or display transcript contents over another app.
- Respect VoiceOver and Reduce Motion. Never communicate status only by color.
- Preserve `Application Support/MenuBarNotes`; the product rename must not strand existing data.
- Store models below `Application Support/MenuBarNotes/DictationModels`, separately from notes and `DictationHistory`.
- Delete only Motes-owned model, staging, resume, and derived-cache paths. Never attempt to remove system Core ML caches.
- Use the existing eventual Motes icon when available; keep `note.text` during this feature.
- Existing unrelated dirty changes must be isolated before execution. Every commit stages only the files named by its task.

## Dependency and Artifact Pins

These pins were verified while writing this plan. Task 0 re-verifies them before implementation:

| Item | Pin | License | Notes |
| --- | --- | --- | --- |
| FluidAudio | tag `v0.15.5`, commit `19600a485baa4998812e4654b70d2bab8f2c9949` | Apache-2.0 | No Swift package dependencies; includes two source wrapper targets |
| Parakeet TDT v2 Core ML | repo `FluidInference/parakeet-tdt-0.6b-v2-coreml`, revision `ee09c569f73759e6d44c9bd16766f477b2b36d39` | CC-BY-4.0 metadata; upstream attribution requires review | English, Apple silicon, macOS 14+, reported peak memory about 800 MB |
| Runtime artifact subset | 21 files, `464,413,247` bytes (`442.9 MiB`) | Same model terms | Four compiled bundles plus vocabulary; do not download the full 3.75 GB repository |

The model license and commercial distribution obligations remain a release-blocking human review. An implementer must not silently substitute a model or rename it Enhanced if that review or the quality gate fails.

## File Map

### Core target

- Create `Sources/MenuBarNotesCore/DictationModels.swift`
- Create `Sources/MenuBarNotesCore/DictationHistoryStore.swift`
- Modify `Sources/MenuBarNotesCore/AppPreferences.swift`
- Test in `Tests/MenuBarNotesCoreTests/AppPreferencesTests.swift`
- Create `Tests/MenuBarNotesCoreTests/DictationHistoryStoreTests.swift`

### App target

- Create `Sources/MenuBarNotesApp/Resources/EnhancedModelManifest.json`
- Create `Sources/MenuBarNotesApp/Resources/ThirdPartyNotices.md`
- Create `Sources/MenuBarNotesApp/EnhancedModelManager.swift`
- Create `Sources/MenuBarNotesApp/DictationInterfaces.swift`
- Create `Sources/MenuBarNotesApp/DictationCoordinator.swift`
- Create `Sources/MenuBarNotesApp/DictationAvailability.swift`
- Create `Sources/MenuBarNotesApp/AppleSpeechCapture.swift`
- Create `Sources/MenuBarNotesApp/EnhancedSpeechCapture.swift`
- Create `Sources/MenuBarNotesApp/FoundationModelDictation.swift`
- Create `Sources/MenuBarNotesApp/GlobalHoldShortcut.swift`
- Create `Sources/MenuBarNotesApp/DictationCapsule.swift`
- Create `Sources/MenuBarNotesApp/NoteTextAppender.swift`
- Create `Sources/MenuBarNotesApp/DictationHistoryView.swift`
- Create `Sources/MenuBarNotesApp/Info.plist`
- Modify `Sources/MenuBarNotesApp/NativeRichTextEditor.swift`
- Modify `Sources/MenuBarNotesApp/AppState.swift`
- Modify `Sources/MenuBarNotesApp/MenuBarNotesApp.swift`
- Modify `Sources/MenuBarNotesApp/NotesPanel.swift`
- Modify `Sources/MenuBarNotesApp/SettingsView.swift`
- Modify `Package.swift`
- Add the generated `Package.resolved`

### App tests and release evidence

- Create `Tests/MenuBarNotesAppTests/EnhancedModelManagerTests.swift`
- Create `Tests/MenuBarNotesAppTests/DictationCoordinatorTests.swift`
- Create `Tests/MenuBarNotesAppTests/DictationAvailabilityTests.swift`
- Create `Tests/MenuBarNotesAppTests/FocusedDictationEditorTests.swift`
- Create `Tests/MenuBarNotesAppTests/FoundationModelDictationTests.swift`
- Create `Tests/MenuBarNotesAppTests/GlobalHoldShortcutTests.swift`
- Create `Tests/MenuBarNotesAppTests/NoteTextAppenderTests.swift`
- Create `Tests/MenuBarNotesAppTests/DictationAccessibilityTests.swift`
- Create `Tests/Fixtures/clean-dictation-evaluation.json`
- Create `Scripts/verify-enhanced-model-manifest.swift`
- Modify `Scripts/check-release-size.sh`
- Modify `TESTING.md`, `ARCHITECTURE.md`, and `README.md`

## Stable Interfaces

Use these names consistently:

```swift
public enum DictationMode: String, Codable, Sendable {
  case focused
  case smartCapture
}

public enum DictationSpeechEngine: String, Codable, CaseIterable, Sendable {
  case standard
  case enhancedLocal
}

public enum DictationCleanupOutcome: String, Codable, Sendable {
  case pending
  case cleaned
  case usedRaw
  case failed
}

public enum DictationInsertionOutcome: String, Codable, Sendable {
  case pending
  case saved
  case unsaved
  case cancelled
}

public struct DictationShortcut: Codable, Equatable, Sendable {
  public var keyCode: UInt32?
  public var carbonModifiers: UInt32
  public var isEnabled: Bool { keyCode != nil && carbonModifiers != 0 }

  public init(keyCode: UInt32? = nil, carbonModifiers: UInt32 = 0) {
    self.keyCode = keyCode
    self.carbonModifiers = carbonModifiers
  }
}

public struct DictationDestination: Codable, Equatable, Sendable {
  public let noteID: UUID
  public let title: String

  public init(noteID: UUID, title: String) {
    self.noteID = noteID
    self.title = title
  }
}

public struct DictationHistoryRecord: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let mode: DictationMode
  public let engine: DictationSpeechEngine
  public let startedAt: Date
  public var completedAt: Date
  public var rawTranscript: String
  public var cleanedTranscript: String?
  public var cleanupOutcome: DictationCleanupOutcome
  public var destination: DictationDestination?
  public var insertionOutcome: DictationInsertionOutcome

  public init(
    id: UUID,
    mode: DictationMode,
    engine: DictationSpeechEngine,
    startedAt: Date,
    completedAt: Date,
    rawTranscript: String,
    cleanedTranscript: String? = nil,
    cleanupOutcome: DictationCleanupOutcome,
    destination: DictationDestination? = nil,
    insertionOutcome: DictationInsertionOutcome
  ) {
    self.id = id
    self.mode = mode
    self.engine = engine
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.rawTranscript = rawTranscript
    self.cleanedTranscript = cleanedTranscript
    self.cleanupOutcome = cleanupOutcome
    self.destination = destination
    self.insertionOutcome = insertionOutcome
  }
}

public struct DictationInsertionReceipt: Equatable, Sendable {
  public let captureID: UUID
  public let noteID: UUID
  public let insertedSuffix: String

  public init(captureID: UUID, noteID: UUID, insertedSuffix: String) {
    self.captureID = captureID
    self.noteID = noteID
    self.insertedSuffix = insertedSuffix
  }
}

enum DictationFailure: Error, Equatable {
  case unavailable
  case permissionDenied
  case noSpeech
  case transcriptionFailed
  case saveFailed
  case interrupted
}
```

App preferences gain:

```swift
public var dictationSpeechEngine: DictationSpeechEngine
public var dictationShortcut: DictationShortcut
public var dictationHistoryEnabled: Bool
public var dictationCapsuleEnabled: Bool
public var dictationMicrophoneUID: String?
```

Defaults are `.standard`, an unassigned shortcut, history enabled, capsule enabled, and Automatic microphone.

App-facing boundaries:

```swift
@MainActor
protocol SpeechEngine: AnyObject {
  var kind: DictationSpeechEngine { get }
  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws
  func finish() async throws -> String?
  func cancel() async
  func releaseResources() async
}

@MainActor
protocol SpeechEngineProviding: AnyObject {
  func engineForCapture(
    preferred: DictationSpeechEngine
  ) async throws -> any SpeechEngine
}

protocol TranscriptCleaning: Sendable {
  func clean(_ rawTranscript: String) async throws -> String
}

protocol DestinationRouting: Sendable {
  func route(
    transcript: String,
    candidates: [DictationDestination],
    inboxID: UUID?
  ) async -> UUID?
}

@MainActor
protocol FocusedDictationEditing: AnyObject {
  var canBeginFocusedDictation: Bool { get }
  func beginFocusedDictation() -> Bool
  func updateFocusedDictation(provisionalText: String)
  func commitFocusedDictation(text: String) -> Bool
  func cancelFocusedDictation()
}

@MainActor
protocol DictationSaving: AnyObject {
  func activeDestinations() -> [DictationDestination]
  func saveSmartCapture(
    text: String,
    captureID: UUID,
    destinationID: UUID?
  ) async throws -> DictationInsertionReceipt
  func undoSmartCapture(_ receipt: DictationInsertionReceipt) async -> Bool
  func flushFocusedDictationSave() async throws
}
```

The coordinator initializer is:

```swift
init(
  engineProvider: any SpeechEngineProviding,
  preferredEngine: @escaping @MainActor () -> DictationSpeechEngine,
  cleaner: any TranscriptCleaning,
  router: any DestinationRouting,
  saver: any DictationSaving,
  historyStore: DictationHistoryStore,
  historyEnabled: @escaping @MainActor () -> Bool,
  holdThreshold: Duration = .milliseconds(180)
)
```

Model management uses:

```swift
enum EnhancedModelState: Equatable, Sendable {
  case notInstalled
  case downloading(progress: Double)
  case verifying
  case installing
  case ready
  case updateAvailable
  case repairRequired(message: String)
  case removing
}

struct EnhancedModelFile: Codable, Equatable, Sendable {
  let path: String
  let byteCount: Int64
  let sha256: String
}

struct EnhancedModelManifest: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let modelID: String
  let revision: String
  let totalByteCount: Int64
  let files: [EnhancedModelFile]
}
```

## Execution Preflight

- [ ] Verify the approved spec commit and isolate unrelated changes.

Run:

```bash
git show --stat --oneline 559eb95
git status --short
```

Expected: `559eb95 docs: add enhanced local dictation design` is reachable. Commit or move unrelated Motes rename/live-tab changes before Task 0. Do not use `git reset --hard` or discard user work.

- [ ] Create an isolated feature branch from the intended clean baseline.

Run:

```bash
git switch -c codex/clean-dictation
swift test
swift build
git diff --check
```

Expected: existing tests and build pass before dictation files are added. If baseline checks fail, record the exact pre-existing failure before changing code.

---

### Task 0: Freeze the Dependency, Artifact, and License Evidence

**Files:**
- Create: `Sources/MenuBarNotesApp/Resources/EnhancedModelManifest.json`
- Create: `Sources/MenuBarNotesApp/Resources/ThirdPartyNotices.md`
- Create: `Scripts/verify-enhanced-model-manifest.swift`
- Modify: `Package.swift`
- Add: `Package.resolved`

**Purpose:** Fail before product code if the audited SDK/model identity has drifted.

- [ ] **Step 1: Re-verify the upstream pins.**

Run:

```bash
git ls-remote --tags https://github.com/FluidInference/FluidAudio.git v0.15.5 'v0.15.5^{}'
curl -sS https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v2-coreml
```

Expected: peeled FluidAudio tag commit is `19600a485baa4998812e4654b70d2bab8f2c9949`; model `sha` is `ee09c569f73759e6d44c9bd16766f477b2b36d39`. Stop if either differs.

- [ ] **Step 2: Add FluidAudio as an exact package dependency.**

Add:

```swift
dependencies: [
  .package(
    url: "https://github.com/FluidInference/FluidAudio.git",
    exact: "0.15.5"
  )
],
```

Add to `MenuBarNotesApp.dependencies`:

```swift
.product(name: "FluidAudio", package: "FluidAudio")
```

Add executable resources:

```swift
resources: [.process("Resources")]
```

Resolve and verify:

```bash
swift package resolve
swift package show-dependencies
rg -n '19600a485baa4998812e4654b70d2bab8f2c9949|0.15.5' Package.resolved
```

- [ ] **Step 3: Check in the exact model manifest.**

`EnhancedModelManifest.json` contains `schemaVersion: 1`, model ID, immutable revision, total byte count `464413247`, and these 21 entries:

```text
Preprocessor.mlmodelc/analytics/coremldata.bin  243        03ab3c1327a054c54c07a40325db967ec574f2c91dcc8192bfa44aa561bcf2d8
Preprocessor.mlmodelc/coremldata.bin            494        d88ea1fc349459c9e100d6a96688c5b29a1f0d865f544be103001724b986b6d6
Preprocessor.mlmodelc/metadata.json             2974       9320bc56773f5eb9b53ff8eebb4f6dca5a4844d623f0a2c819766f6d9bd6212f
Preprocessor.mlmodelc/model.mil                 27166      8f8be99d18b1f40aed3b66d2d7addf6cbf68c952ef5b2038d02019d3cd3d0586
Preprocessor.mlmodelc/weights/weight.bin        298880     a5f7df6c7f47147ae9486fe18cc7792f9a44d093ec3c6a11e91ef2dc363c48dc
Encoder.mlmodelc/analytics/coremldata.bin       243        42e638870d73f26b332918a3496ce36793fbb413a81cbd3d16ba01328637a105
Encoder.mlmodelc/coremldata.bin                 485        4def7aa848599ad0e17a8b9a982edcdbf33cf92e1f4b798de32e2ca0bc74b030
Encoder.mlmodelc/metadata.json                  2926       7669e4a9c43357419c68ce581f73e4dd3935a8bef27fc7a94aa6dd3bbc707f1e
Encoder.mlmodelc/model.mil                      959769     821cf00f00f05d6da36d704de708b0c296aed1f14f072ac008f1fd89a2730e4d
Encoder.mlmodelc/weights/weight.bin             445187200  4adc7ad44f9d05e1bffeb2b06d3bb02861a5c7602dff63a6b494aed3bf8a6c3e
Decoder.mlmodelc/analytics/coremldata.bin       243        46de1a6fe2e49d19a2125bc91acf020df7f2aea84ba821532aade8427a440b05
Decoder.mlmodelc/coremldata.bin                 554        d200ca07694a347f6d02a3886a062ae839831e094e443222f2e48a14945966a8
Decoder.mlmodelc/metadata.json                  3427       5983e89e9d9b42fd8df5074041e98558f62c1fe5e258e1788ec1b2ef6ae6332e
Decoder.mlmodelc/model.mil                      13106      b0729665b2540e1012ee034afc2ec65c59d509c6739da702a6467be247bd895b
Decoder.mlmodelc/weights/weight.bin             14429952   27d26890221d82322c1092fd99d7b40578e435d5cf4b83c887c42603caf97aba
JointDecision.mlmodelc/analytics/coremldata.bin 243        f1183ba213bb94a918c8d2cad19ab045320618f97f6ca662245b3936d7b090f7
JointDecision.mlmodelc/coremldata.bin           534        e2c6752f1c8cf2d3f6f26ec93195c9bfa759ad59edf9f806696a138154f96f11
JointDecision.mlmodelc/metadata.json            2936       14a9fe6d9f79e630bc138277365d6af93dab82d0dc905899925b79616057b165
JointDecision.mlmodelc/model.mil                9722       56632cbd11afc3bd9f7aa2c235e92fc975c8ac311e6ed3deee6cd48162831903
JointDecision.mlmodelc/weights/weight.bin       3453388    ca22a65903a05e64137677da608077578a8606090a598abf4875fa6199aaa19d
parakeet_vocab.json                             18762      cf1e92f198acd7e515044f9e9d3d17f5cc916e3503cf3d18aa9e9389a9acec39
```

The verifier decodes the JSON, rejects duplicate/absolute/`..` paths, checks the exact total, optionally hashes a supplied installed directory using `CryptoKit.SHA256`, and exits nonzero on mismatch.

- [ ] **Step 4: Record notices and the human audit gate.**

`ThirdPartyNotices.md` must identify FluidAudio, its exact tag/commit, Apache-2.0 license checksum `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`, Parakeet model repo/revision, CC-BY-4.0 metadata, NVIDIA base-model attribution, and direct links. Include:

```text
Release blocker: legal/product owner must approve commercial distribution,
attribution placement, upstream-base terms, and Mac App Store data-only model
download behavior before Enhanced Local is enabled in a release build.
```

- [ ] **Step 5: Verify and commit.**

Run:

```bash
swift Scripts/verify-enhanced-model-manifest.swift \
  Sources/MenuBarNotesApp/Resources/EnhancedModelManifest.json
swift build
swift test
git diff --check
```

Commit only the named files:

```bash
git add Package.swift Package.resolved \
  Sources/MenuBarNotesApp/Resources/EnhancedModelManifest.json \
  Sources/MenuBarNotesApp/Resources/ThirdPartyNotices.md \
  Scripts/verify-enhanced-model-manifest.swift
git commit -m "build: pin enhanced dictation dependencies"
```

---

### Task 1: Dictation Models, Preferences, and Privacy Metadata

**Files:**
- Create: `Sources/MenuBarNotesCore/DictationModels.swift`
- Modify: `Sources/MenuBarNotesCore/AppPreferences.swift`
- Create: `Sources/MenuBarNotesApp/Info.plist`
- Modify: `Package.swift`
- Modify: `Tests/MenuBarNotesCoreTests/AppPreferencesTests.swift`

- [ ] **Step 1: Add failing default and old-JSON tests.**

```swift
@Test func dictationPreferencesUseStandardPrivateDefaults() throws {
  let value = AppPreferences()
  #expect(value.dictationSpeechEngine == .standard)
  #expect(!value.dictationShortcut.isEnabled)
  #expect(value.dictationHistoryEnabled)
  #expect(value.dictationCapsuleEnabled)
  #expect(value.dictationMicrophoneUID == nil)
}

@Test func oldPreferencesDecodeWithDictationDefaults() throws {
  let data = Data(#"{"fontFamily":".AppleSystemUIFont","fontSize":15}"#.utf8)
  let value = try JSONDecoder().decode(AppPreferences.self, from: data)
  #expect(value.dictationSpeechEngine == .standard)
  #expect(value.dictationHistoryEnabled)
}
```

Run `swift test --filter dictationPreferencesUseStandardPrivateDefaults`; expect compilation failure.

- [ ] **Step 2: Add stable core types and backward-compatible preference fields.**

Implement the declarations in **Stable Interfaces**. Add all five fields to `CodingKeys`; use `decodeIfPresent` with the specified defaults in the custom decoder.

- [ ] **Step 3: Embed privacy descriptions.**

Add `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` to `Info.plist`. Keep executable identity `Motes`, bundle ID `com.harryjin.motes`, and existing macOS floor. Embed it using the package’s existing `__TEXT,__info_plist` linker approach from the superseded plan:

```swift
let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let infoPlistPath = packageRoot
  .appendingPathComponent("Sources/MenuBarNotesApp/Info.plist").path
```

Then add these unsafe linker flags to the executable target:

```swift
.unsafeFlags([
  "-Xlinker", "-sectcreate",
  "-Xlinker", "__TEXT",
  "-Xlinker", "__info_plist",
  "-Xlinker", infoPlistPath,
])
```

- [ ] **Step 4: Verify and commit.**

```bash
swift test --filter dictationPreferences
swift build
otool -s __TEXT __info_plist .build/debug/Motes
git diff --check
git add Package.swift Sources/MenuBarNotesApp/Info.plist \
  Sources/MenuBarNotesCore/DictationModels.swift \
  Sources/MenuBarNotesCore/AppPreferences.swift \
  Tests/MenuBarNotesCoreTests/AppPreferencesTests.swift
git commit -m "feat: add dual-engine dictation preferences"
```

---

### Task 2: Enhanced Model Manager

**Files:**
- Create: `Sources/MenuBarNotesApp/EnhancedModelManager.swift`
- Create: `Tests/MenuBarNotesAppTests/EnhancedModelManagerTests.swift`

**Storage layout:**

```text
Application Support/MenuBarNotes/DictationModels/
├── installed/ee09c569f73759e6d44c9bd16766f477b2b36d39/
│   └── parakeet-tdt-0.6b-v2-coreml/
├── staging/ee09c569f73759e6d44c9bd16766f477b2b36d39/
├── resume/ee09c569f73759e6d44c9bd16766f477b2b36d39/
└── derived/ee09c569f73759e6d44c9bd16766f477b2b36d39/
```

- [ ] **Step 1: Write failing state and filesystem tests.**

Cover:

- no installed directory → `.notInstalled`
- all allowlisted files with matching size/hash → `.ready`
- missing, extra, wrong-size, or wrong-hash file → `.repairRequired`
- Intel machine → Enhanced unavailable without touching disk/network
- available capacity below `1_197_261_950` bytes → clear insufficient-space error
- progress is byte-weighted and monotonic
- cancellation persists only valid `URLSession` resume data
- checksum failure deletes staging and resume data
- install renames verified staging into place atomically
- `Delete Model` removes installed/staging/resume/derived and returns `.notInstalled`
- model root has `URLResourceKey.isExcludedFromBackupKey == true`
- an older installed embedded manifest exposes `.updateAvailable`, but no bytes move until the user invokes Update

Use injected `FileManager`, capacity provider, architecture provider, manifest, clock, and transport. Tests never use the network.

- [ ] **Step 2: Define a narrow resumable transport.**

```swift
protocol ModelDownloading: Sendable {
  func download(
    from remoteURL: URL,
    resumeData: Data?,
    progress: @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> ModelDownloadResult
}

struct ModelDownloadResult: Sendable {
  let temporaryURL: URL
  let resumeData: Data?
}
```

The production implementation wraps `URLSessionDownloadTask`, accepts delegate byte progress, resumes only with session-produced resume data, and maps cancellation separately from failure.

- [ ] **Step 3: Implement immutable, allowlisted downloads.**

For each manifest entry, construct the URL without string interpolation of an unescaped relative path:

```swift
let revisionRoot = URL(
  string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/"
)!.appendingPathComponent(manifest.revision, isDirectory: true)
let artifactURL = file.path.split(separator: "/").reduce(revisionRoot) {
  $0.appendingPathComponent(String($1))
}
var components = URLComponents(url: artifactURL, resolvingAgainstBaseURL: false)!
components.queryItems = [URLQueryItem(name: "download", value: "true")]
let remoteURL = components.url!
```

Reject redirects unless the lowercased final host is exactly `huggingface.co`, has the suffix `.huggingface.co`, or has the suffix `.xethub.hf.co`; compare host labels, not substring matches. Never call the Hugging Face tree API at runtime. Never enumerate or trust remote filenames.

- [ ] **Step 4: Implement verify/install/remove off the main actor.**

For every file:

1. Verify normalized relative path remains under staging.
2. Verify exact byte count.
3. Stream the file through `SHA256` without loading the 445 MB encoder into memory.
4. Reject any extra file below staging.
5. Create the final parent, remove only a prior same-revision repair directory, then `moveItem` staging to the final revision directory.
6. Set backup exclusion on `DictationModels`.

Persist no separate mutable “ready” flag; derive readiness from manifest validation on launch. `Update Available` is created only when a later app build ships a different embedded manifest while the old revision is installed.

Download, repair, update, and delete are separate user-invoked methods. Update reuses the staging, verification, and atomic-install pipeline, leaves the currently Ready revision intact until the new revision verifies, and removes the old revision only after the new one is installed.

- [ ] **Step 5: Verify and commit.**

```bash
swift test --filter EnhancedModelManager
swift test
git diff --check
git add Sources/MenuBarNotesApp/EnhancedModelManager.swift \
  Tests/MenuBarNotesAppTests/EnhancedModelManagerTests.swift
git commit -m "feat: manage the enhanced speech model"
```

---

### Task 3: Atomic 30-Day Recovery History

**Files:**
- Create: `Sources/MenuBarNotesCore/DictationHistoryStore.swift`
- Create: `Tests/MenuBarNotesCoreTests/DictationHistoryStoreTests.swift`

- [ ] **Step 1: Write failing tests for save/update/list/delete/clear/purge.**

Use a temporary root and injected `now`. Assert:

- records are one sorted JSON file each under `DictationHistory`
- save then update preserves the capture ID
- a record at exactly 30 days is removed; a newer record remains
- malformed records do not hide valid records
- individual delete and clear are idempotent
- no serialized key contains `audio`

- [ ] **Step 2: Implement the actor.**

```swift
public actor DictationHistoryStore {
  public init(
    rootURL: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = Date.init
  )
  public func save(_ record: DictationHistoryRecord) throws
  public func list() throws -> [DictationHistoryRecord]
  public func delete(id: UUID) throws
  public func clear() throws
  public func purgeExpired() throws
}
```

Use sorted-key ISO-8601 JSON and `.atomic` writes. Purge on init-facing load/list and after save. Do not put history in `LocalStore` recovery snapshots.

- [ ] **Step 3: Verify and commit.**

```bash
swift test --filter DictationHistoryStore
git diff --check
git add Sources/MenuBarNotesCore/DictationHistoryStore.swift \
  Tests/MenuBarNotesCoreTests/DictationHistoryStoreTests.swift
git commit -m "feat: store dictation recovery history"
```

---

### Task 4: Engine-Neutral Coordinator State Machine

**Files:**
- Create: `Sources/MenuBarNotesApp/DictationInterfaces.swift`
- Create: `Sources/MenuBarNotesApp/DictationCoordinator.swift`
- Create: `Tests/MenuBarNotesAppTests/DictationCoordinatorTests.swift`

- [ ] **Step 1: Write deterministic fake-driven tests.**

Cover:

- `.standard` is requested by default
- Enhanced is bound for the full capture once selected
- no mid-capture failover after `start`
- provider may visibly change the preference to Standard before a later capture
- short hold below 180 ms records nothing
- a shortcut begun while the Motes editor is focused chooses Focused; otherwise it chooses Smart Capture
- second activation while active is ignored
- Escape/cancel restores focused editor state and creates no history
- no speech inserts nothing and creates no history
- valid final transcript creates pending history before cleanup
- cleanup failure uses raw text
- routing failure uses Inbox
- save failure records `.unsaved` or exposes in-memory Copy when history is off
- `releaseResources()` runs on every terminal path

- [ ] **Step 2: Implement explicit state.**

```swift
enum DictationPhase: Equatable {
  case idle
  case arming
  case listening(mode: DictationMode, engine: DictationSpeechEngine)
  case finalizing
  case cleaning
  case routing
  case saved(DictationDestination)
  case failed(String)
}
```

The coordinator captures `preferredEngine()` once, asks the provider once, starts one engine, and stores that exact object until completion. A failure with no final transcript never invokes another engine. Always cancel/release the engine in `defer`-equivalent terminal cleanup.

- [ ] **Step 3: Preserve focused and Smart sequencing.**

Focused:

1. Begin editor transaction before speech.
2. Forward provisional text when the engine emits it.
3. Save raw history after a nonempty final.
4. Clean or use raw.
5. Commit one editor undo group.
6. Flush the existing save path.
7. Update history.

Smart:

1. Finalize raw.
2. Save raw history when enabled.
3. Clean or use raw.
4. Route titles or Inbox.
5. Save through `AppState`.
6. Update history.

- [ ] **Step 4: Verify and commit.**

```bash
swift test --filter DictationCoordinator
swift test
git diff --check
git add Sources/MenuBarNotesApp/DictationInterfaces.swift \
  Sources/MenuBarNotesApp/DictationCoordinator.swift \
  Tests/MenuBarNotesAppTests/DictationCoordinatorTests.swift
git commit -m "feat: coordinate dual-engine dictation"
```

---

### Task 5: Focused Editor Transaction and Rich-Text-Safe Smart Append

**Files:**
- Modify: `Sources/MenuBarNotesApp/NativeRichTextEditor.swift`
- Create: `Sources/MenuBarNotesApp/NoteTextAppender.swift`
- Create: `Tests/MenuBarNotesAppTests/FocusedDictationEditorTests.swift`
- Create: `Tests/MenuBarNotesAppTests/NoteTextAppenderTests.swift`

- [ ] **Step 1: Write failing focused transaction tests.**

Cover insertion point, selected-text replacement, repeated provisional replacement, cancellation restoring the original attributed selection, final commit as one Undo operation, and user edits outside the provisional range surviving.

- [ ] **Step 2: Add a provisional transaction to `EditorCommands`.**

Store the original selected attributed string, original selection, current provisional range, and whether an undo group is open. Apply provisional updates directly to `NSTextStorage` with a temporary visual attribute and do not invoke SwiftUI body/RTF bindings. On commit, replace the provisional range, remove temporary attributes, emit body/RTF bindings once, and register one Undo. On cancel, restore the original attributed selection and caret without autosave.

- [ ] **Step 3: Write and implement Smart append tests.**

`NoteTextAppender.appending(_:to:)` returns body, RTF, and exact inserted suffix. It:

- uses `\n\n` only when existing content is nonempty
- preserves existing attributed runs
- appends with current editor defaults
- lets undo remove only the exact suffix if the note still ends with it

- [ ] **Step 4: Verify and commit.**

```bash
swift test --filter FocusedDictationEditor
swift test --filter NoteTextAppender
git diff --check
git add Sources/MenuBarNotesApp/NativeRichTextEditor.swift \
  Sources/MenuBarNotesApp/NoteTextAppender.swift \
  Tests/MenuBarNotesAppTests/FocusedDictationEditorTests.swift \
  Tests/MenuBarNotesAppTests/NoteTextAppenderTests.swift
git commit -m "feat: insert dictation safely into notes"
```

---

### Task 6: Availability, Permissions, and Standard Apple Speech

**Files:**
- Create: `Sources/MenuBarNotesApp/DictationAvailability.swift`
- Create: `Sources/MenuBarNotesApp/AppleSpeechCapture.swift`
- Create: `Tests/MenuBarNotesAppTests/DictationAvailabilityTests.swift`

- [ ] **Step 1: Write a table-driven capability-matrix test.**

Inject OS major version, architecture, microphone status, speech permission, Apple on-device support, Enhanced state, and Foundation Model availability. Assert:

- Standard may be available on macOS 14+ only when Apple reports on-device English recognition
- Enhanced is unavailable on Intel
- Enhanced requires `.ready`
- cleanup/routing availability is independent of speech engine
- macOS 14–15 routing is Inbox
- denied permissions expose `Open System Settings`

- [ ] **Step 2: Implement permissions only after user intent.**

Do not prompt on launch. Request microphone/speech access after the toolbar mic is pressed or shortcut setup is explicitly completed. After denial, link to the relevant Privacy & Security pane instead of re-prompting.

- [ ] **Step 3: Implement macOS 14–15 Standard.**

Use `SFSpeechRecognizer(locale: Locale(identifier: "en-US"))`. Before starting:

```swift
guard recognizer.supportsOnDeviceRecognition else {
  throw DictationFailure.unavailable
}
request.requiresOnDeviceRecognition = true
request.shouldReportPartialResults = true
```

Feed copied `AVAudioPCMBuffer` instances from `AVAudioEngine` into `SFSpeechAudioBufferRecognitionRequest`. Emit partial text, retain only final text, and end/cancel the task and audio tap on every terminal path. Do not retry with `requiresOnDeviceRecognition = false`.

- [ ] **Step 4: Implement macOS 26 Standard behind availability checks.**

Inside an `@available(macOS 26.0, *)` type, use:

```swift
let transcriber = DictationTranscriber(
  locale: locale,
  preset: .progressiveShortDictation
)
let modules: [any SpeechModule] = [transcriber]
let format = await SpeechAnalyzer.bestAvailableAudioFormat(
  compatibleWith: modules,
  considering: inputNode.inputFormat(forBus: 0)
)
let analyzer = SpeechAnalyzer(
  modules: modules,
  options: .init(priority: .userInitiated, modelRetention: .whileInUse)
)
try await analyzer.prepareToAnalyze(in: format)
```

Use one bounded `AsyncStream<AnalyzerInput>`, emit volatile results as provisional text, retain final results, and call `finalizeAndFinishThroughEndOfInput()` on finish or `cancelAndFinishNow()` on cancel. Do not automatically initiate Apple asset downloads.

- [ ] **Step 5: Share audio-level and microphone selection helpers.**

Use the saved Core Audio device UID when present; otherwise Automatic. If missing, fall back to Automatic and update Settings copy. Emit normalized RMS only to capsule state; never persist it.

- [ ] **Step 6: Verify and commit.**

```bash
swift test --filter DictationAvailability
swift build
swift test
git diff --check
git add Sources/MenuBarNotesApp/DictationAvailability.swift \
  Sources/MenuBarNotesApp/AppleSpeechCapture.swift \
  Tests/MenuBarNotesAppTests/DictationAvailabilityTests.swift
git commit -m "feat: add on-device Apple speech"
```

---

### Task 7: Enhanced FluidAudio Speech Adapter

**Files:**
- Create: `Sources/MenuBarNotesApp/EnhancedSpeechCapture.swift`
- Modify: `Tests/MenuBarNotesAppTests/DictationCoordinatorTests.swift`
- Modify: `Tests/MenuBarNotesAppTests/EnhancedModelManagerTests.swift`

- [ ] **Step 1: Add failing adapter lifecycle tests through injected inference.**

Cover model-not-ready rejection, no network call during start/finish, memory-only sample capture, successful final text, empty result, inference failure, cancellation, and release of audio/model/manager references after every result.

- [ ] **Step 2: Force FluidAudio offline before any load.**

At app runtime construction, before creating an Enhanced adapter:

```swift
ModelHub.offlineMode = true
```

Treat changing this to `false` as a privacy regression. The adapter never calls `AsrModels.download`, `downloadAndLoad`, `ModelHub.download`, or `ModelHub.fetchFile`.

- [ ] **Step 3: Load only the manager-verified local directory.**

```swift
let models = try await AsrModels.load(
  from: verifiedRepositoryURL,
  configuration: AsrModels.defaultConfiguration(),
  version: .v2
)
let manager = AsrManager(config: .default)
try await manager.loadModels(models)
```

Before loading, re-check manager state is `.ready`. If load fails, mark `repairRequired`, return no transcript, and recommend Standard for the next capture.

- [ ] **Step 4: Capture and transcribe memory-only audio.**

Use `AVAudioEngine` plus `AVAudioConverter` to append mono Float32 16 kHz samples to a capture-owned buffer. Emit RMS levels. Enhanced v1 may emit no provisional transcript because its approved adapter is batch-finalized; the shared UI must tolerate that.

On finish:

```swift
var decoderState = TdtDecoderState.make(
  decoderLayers: await manager.decoderLayerCount
)
let result = try await manager.transcribe(samples, decoderState: &decoderState)
```

Trim whitespace; empty is no speech. Immediately clear samples and call `manager.cleanup()`. Release `AsrModels`, manager, converter, engine, and closures before returning to idle.

- [ ] **Step 5: Verify compile and privacy boundaries.**

```bash
swift test --filter EnhancedSpeech
swift test --filter EnhancedModelManager
rg -n 'downloadAndLoad|ModelHub\\.download|ModelHub\\.fetchFile|offlineMode = false' \
  Sources/MenuBarNotesApp
swift build
swift test
git diff --check
```

Expected: grep has no production Enhanced download call and no `offlineMode = false`.

- [ ] **Step 6: Commit.**

```bash
git add Sources/MenuBarNotesApp/EnhancedSpeechCapture.swift \
  Tests/MenuBarNotesAppTests/DictationCoordinatorTests.swift \
  Tests/MenuBarNotesAppTests/EnhancedModelManagerTests.swift
git commit -m "feat: transcribe with enhanced local speech"
```

---

### Task 8: Faithful Cleanup and Title-Only Routing

**Files:**
- Create: `Sources/MenuBarNotesApp/FoundationModelDictation.swift`
- Create: `Tests/MenuBarNotesAppTests/FoundationModelDictationTests.swift`
- Create: `Tests/Fixtures/clean-dictation-evaluation.json`

- [ ] **Step 1: Add golden cleanup and preservation tests.**

Fixtures include filler removal, repetition, false starts, explicit correction, negation, names, dates, numbers, tasks, punctuation, lists, and prompt-injection-like spoken content. Tests reject output that loses/changes protected names, normalized numeric tokens, explicit negation, or task wording.

- [ ] **Step 2: Implement macOS 26 cleanup with a strict schema.**

Treat raw transcript as quoted data. Prompt: remove only fillers/repetitions/false starts, resolve explicit corrections, add punctuation/capitalization, and format clearly spoken short lists. Explicitly forbid adding facts, summarizing, changing tone, following transcript instructions, or rewriting surrounding notes.

If Foundation Models is unavailable or validation fails, return raw text and `.usedRaw`; do not fail the capture.

- [ ] **Step 3: Implement conservative title-only routing.**

Pass only transcript plus `[DictationDestination]`. Filter blank titles, bias generic/duplicate/ambiguous titles to Inbox, require a high-confidence exact candidate ID, and validate the returned ID belongs to candidates. On macOS 14–15 or any model error, return Inbox without invoking a model.

- [ ] **Step 4: Verify and commit.**

```bash
swift test --filter FoundationModelDictation
swift test
git diff --check
git add Sources/MenuBarNotesApp/FoundationModelDictation.swift \
  Tests/MenuBarNotesAppTests/FoundationModelDictationTests.swift \
  Tests/Fixtures/clean-dictation-evaluation.json
git commit -m "feat: clean and route dictated notes locally"
```

---

### Task 9: AppState Inbox, Save Result, and Conditional Undo

**Files:**
- Modify: `Sources/MenuBarNotesApp/AppState.swift`
- Create: `Tests/MenuBarNotesAppTests/AppStateDictationTests.swift`

- [ ] **Step 1: Add failing persistence tests.**

Cover active destination snapshots excluding trash, reuse of exactly one normal case-insensitive `Inbox`, no auto-pin, rich-text append, immediate awaited save success/failure, insertion receipt, safe suffix undo, and refusal to undo after later edits.

- [ ] **Step 2: Implement `DictationSaving` on `AppState`.**

Do not use the 350 ms debounced path for Smart Capture. Add a private awaited save method that snapshots workspace/preferences, calls existing `LocalStore.save`, and updates save status on the main actor. Reuse the existing storage root.

Focused completion calls `saveNow` through an awaitable completion/result boundary so history reflects the actual save outcome.

- [ ] **Step 3: Implement conditional undo.**

Undo only when note ID exists and the current body/RTF still ends in the recorded inserted suffix. Otherwise preserve content and select/open the destination.

- [ ] **Step 4: Verify and commit.**

```bash
swift test --filter AppStateDictation
swift test
git diff --check
git add Sources/MenuBarNotesApp/AppState.swift \
  Tests/MenuBarNotesAppTests/AppStateDictationTests.swift
git commit -m "feat: persist smart captures safely"
```

---

### Task 10: Global Hold Shortcut and Non-Activating Capsule

**Files:**
- Create: `Sources/MenuBarNotesApp/GlobalHoldShortcut.swift`
- Create: `Sources/MenuBarNotesApp/DictationCapsule.swift`
- Create: `Tests/MenuBarNotesAppTests/GlobalHoldShortcutTests.swift`
- Create: `Tests/MenuBarNotesAppTests/DictationAccessibilityTests.swift`

- [ ] **Step 1: Write hold-threshold and registration tests.**

Cover no registration when unassigned, exact chord registration, press once, release once, key repeat ignored, short tap ignored by coordinator, Escape registered only while capture is active, conflicts surfaced, and unregister cleanup.

- [ ] **Step 2: Implement bounded Carbon registration.**

Register only the selected chord using `RegisterEventHotKey`. Use press/release Carbon events; do not install `NSEvent.addGlobalMonitorForEvents`. Temporarily register Escape during active capture and remove it at the terminal transition.

- [ ] **Step 3: Write capsule accessibility/state tests.**

Map listening, cleaning, saved destination, saved-without-cleanup, model repair, and failure to visible and VoiceOver strings. Assert Reduce Motion selects opacity transitions.

- [ ] **Step 4: Implement a non-activating panel.**

Use `NSPanel` with `.nonactivatingPanel`, `canBecomeKey = false`, `canBecomeMain = false`, floating level, all Spaces, lower-center positioning on the active display, and no transcript text. Show within 100 ms of accepted activation. Keep success briefly and dismiss.

- [ ] **Step 5: Verify and commit.**

```bash
swift test --filter GlobalHoldShortcut
swift test --filter DictationAccessibility
swift test
git diff --check
git add Sources/MenuBarNotesApp/GlobalHoldShortcut.swift \
  Sources/MenuBarNotesApp/DictationCapsule.swift \
  Tests/MenuBarNotesAppTests/GlobalHoldShortcutTests.swift \
  Tests/MenuBarNotesAppTests/DictationAccessibilityTests.swift
git commit -m "feat: add dictation shortcut and capsule"
```

---

### Task 11: Shared Runtime, Toolbar, Settings, Model UI, and History UI

**Files:**
- Create: `Sources/MenuBarNotesApp/DictationHistoryView.swift`
- Modify: `Sources/MenuBarNotesApp/MenuBarNotesApp.swift`
- Modify: `Sources/MenuBarNotesApp/NotesPanel.swift`
- Modify: `Sources/MenuBarNotesApp/SettingsView.swift`
- Create: `Tests/MenuBarNotesAppTests/DictationSettingsTests.swift`

- [ ] **Step 1: Add presentation-model tests.**

Assert:

- Standard selected by default
- Enhanced disabled on Intel
- Not Installed shows `Download Enhanced Model`
- consent shows 442.9 MiB download, Apple silicon, English, attribution, and no dictation-data upload
- downloading shows progress and Cancel
- checksum/load failure shows Repair
- Ready allows selection and Delete
- deletion returns selection to Standard
- update is explicit
- Dictation settings participate in the existing matched-geometry sliding section selector
- history clear requires confirmation

- [ ] **Step 2: Construct one runtime in the app root.**

Instantiate one `EnhancedModelManager`, engine provider, coordinator, shortcut controller, capsule controller, and history store next to the shared `AppState`. Inject the same objects into menu-bar, pinned, and Settings scenes. Never create a separate coordinator per window.

- [ ] **Step 3: Add the toolbar mic and Options history entry.**

Place mic first, then a divider, then Undo. Toggle start/finish; expose cancel accessibly. Keep the header scroll behavior and existing layout unchanged. Add `Options → Dictation History`.

- [ ] **Step 4: Add Dictation settings without a model catalog.**

Add a fourth section beside Appearance, Editing, and Shortcuts using the same sliding selection background. Show:

- availability/recovery action
- Standard and Enhanced choices
- model state/actions
- download/installed sizes and Apple-silicon requirement
- attribution link/notices
- hold shortcut recorder
- Automatic/device microphone picker
- English status
- capsule toggle
- 30-day history toggle and confirmed Clear History
- privacy copy

Do not expose model family, parameter count, quantization, decoding settings, alternate sizes, or remote catalog.
Turning history off affects future successful captures only; existing records remain until Clear History or 30-day expiry.

- [ ] **Step 5: Implement Dictation History.**

Rows show time, destination/unsaved, cleaned and raw text, Copy Clean, Copy Raw, Open Destination, and Delete. Clear uses confirmation and immediate local UI removal followed by actor deletion; rollback and error copy if persistence fails.

- [ ] **Step 6: Verify and commit.**

```bash
swift test --filter DictationSettings
swift build
swift test
git diff --check
git add Sources/MenuBarNotesApp/DictationHistoryView.swift \
  Sources/MenuBarNotesApp/MenuBarNotesApp.swift \
  Sources/MenuBarNotesApp/NotesPanel.swift \
  Sources/MenuBarNotesApp/SettingsView.swift \
  Tests/MenuBarNotesAppTests/DictationSettingsTests.swift
git commit -m "feat: integrate clean dictation controls"
```

---

### Task 12: Evaluation, Documentation, and Release Gates

**Files:**
- Modify: `Scripts/check-release-size.sh`
- Modify: `TESTING.md`
- Modify: `ARCHITECTURE.md`
- Modify: `README.md`

- [ ] **Step 1: Document the exact privacy/data flow.**

`ARCHITECTURE.md` records:

```text
microphone -> selected local speech engine -> raw transcript
  -> optional local cleanup -> focused editor OR title-only router -> LocalStore
```

Document that Standard forbids cloud fallback, Enhanced is external data-only model content, FluidAudio is forced offline, audio is memory-only, routing sees titles only, history is local/30-day, and only explicit model download/update uses network.

- [ ] **Step 2: Add release-size and forbidden-call checks.**

Extend `check-release-size.sh` to fail if the app bundle contains `.mlmodel`, `.mlpackage`, `.mlmodelc`, or any model weight file, and record the release-binary delta caused by FluidAudio code separately from the 442.9 MiB optional model.

Add CI grep assertions for:

```text
ModelHub.offlineMode = true
no ModelHub.offlineMode = false
no AsrModels.downloadAndLoad in production
no ModelHub.download/fetchFile in EnhancedSpeechCapture
no NSEvent.addGlobalMonitorForEvents
```

- [ ] **Step 3: Run the quality gate on real Apple-silicon hardware.**

Use the privacy-safe corpus to compare Standard and the pinned candidate. Record:

- WER
- proper-name preservation failures
- number preservation failures
- negation preservation failures
- task preservation failures
- cold/warm finalization latency
- peak and idle memory
- energy/thermal observations

The product label `Enhanced Local` is allowed only if the pinned model materially beats Standard without unacceptable latency/memory/energy. If it fails, keep Task 0–2 infrastructure disabled from release UI and do not claim Enhanced ships.

- [ ] **Step 4: Complete manual matrices.**

Test:

- macOS 26 Apple silicon
- macOS 14 or 15 Apple silicon
- Intel macOS 14+ where available
- built-in, wired, and delayed-wake wireless microphones
- first-run permission grant/denial
- Apple Intelligence disabled/not ready
- Standard on-device recognition unavailable
- Enhanced consent/download/cancel/resume/low-disk/checksum/repair/update/delete
- cold load, warm use, idle unload, memory pressure, corruption
- shortcut conflicts, rapid tap, Escape, active/hidden/pinned/behind another app
- sleep/wake and device disconnect
- VoiceOver and Reduce Motion
- history copy/open/delete/purge/clear
- ordinary notes with no model installed

- [ ] **Step 5: Complete human release blockers.**

Record approval of exact SDK license/notices, model/base-model terms, commercial distribution, attribution placement, checksum manifest, SBOM, and Mac App Store rules for downloaded data-only Core ML assets. Automated tests do not satisfy these gates.

- [ ] **Step 6: Run final automated verification.**

```bash
swift package resolve
swift test
swift build -c release
Scripts/check-release-size.sh
Scripts/validate-macos.sh
rg -n 'NSEvent\\.addGlobalMonitorForEvents|offlineMode = false|AsrModels\\.downloadAndLoad' \
  Sources
git diff --check
git status --short
```

Expected:

- tests and release build pass
- release app contains no model assets
- grep reports no forbidden implementation
- macOS minimum remains 14
- only intended files are changed

- [ ] **Step 7: Commit documentation and gates.**

```bash
git add Scripts/check-release-size.sh TESTING.md ARCHITECTURE.md README.md
git commit -m "docs: add clean dictation release gates"
```

## Final Integration Commit Policy

Do not squash away the task-level evidence until review. Before merging:

```bash
git log --oneline --decorate main..HEAD
git diff --stat main...HEAD
git diff --check main...HEAD
swift test
swift build -c release
```

Merge only after all automated checks pass and the real-device, quality, license, attribution, and App Store gates are recorded. A green CI run alone is not release approval.

## Self-Review Checklist

- [ ] Every approved spec section maps to a task.
- [ ] Standard remains default and never uses cloud speech.
- [ ] Enhanced downloads one curated model only after consent.
- [ ] FluidVoice code is absent.
- [ ] FluidAudio and the model are immutable and checksum-pinned.
- [ ] Runtime model downloads use an embedded allowlist, not a remote file listing.
- [ ] FluidAudio is offline during inference.
- [ ] No capture switches engines midway.
- [ ] Intel and older-system behavior matches the capability matrix.
- [ ] Cleanup/routing degrade independently from transcription.
- [ ] Focused selection rollback and one-step Undo are covered.
- [ ] Smart Capture title-only routing and Inbox behavior are covered.
- [ ] History is atomic, audio-free, optional, and expires at 30 days.
- [ ] Model install/update/repair/delete/backup exclusion are covered.
- [ ] Model and inference resources unload while idle.
- [ ] Toolbar, Settings, capsule, VoiceOver, and Reduce Motion are covered.
- [ ] The release has model-quality, license, artifact, size, and device gates.
- [ ] No placeholder paths, types, hashes, revisions, commands, or “implement later” steps remain.
