import AppKit
import FleckCore
import Foundation
import Testing

@testable import FleckApp

@Test(arguments: [false, true]) @MainActor
func runtimeEscapeToolbarEscapeCancelsListeningCapture(focused: Bool) async throws {
  let fixture = try await RuntimeEscapeFixture(focused: focused)
  await fixture.runtime.toggle()
  #expect(fixture.runtime.phase == .listening(mode: fixture.mode, engine: .standard))

  let registered = fixture.escape.isRegistered
  fixture.escape.emit()
  for _ in 0..<100 where fixture.runtime.phase != .idle {
    await Task.yield()
  }
  let phaseAfterEscape = fixture.runtime.phase
  let cancellationsAfterEscape = fixture.engine.cancelCount
  let recordsAfterEscape = fixture.history.records.count
  await fixture.runtime.shutdown()

  #expect(registered, "Expected a toolbar capture to install its Escape cancellation route")
  #expect(phaseAfterEscape == .idle, "Expected Escape to cancel capture, not leave it listening")
  #expect(cancellationsAfterEscape == 1)
  #expect(recordsAfterEscape == 0)
}

@Test(arguments: [false, true]) @MainActor
func runtimeEscapeToolbarDirectCancelWorks(focused: Bool) async throws {
  let fixture = try await RuntimeEscapeFixture(focused: focused)
  await fixture.runtime.toggle()
  #expect(fixture.runtime.phase == .listening(mode: fixture.mode, engine: .standard))
  await fixture.runtime.cancel()

  #expect(fixture.runtime.phase == .idle)
  #expect(fixture.engine.cancelCount == 1)
  #expect(fixture.engine.finishCount == 0)
  #expect(fixture.history.records.isEmpty)
  #expect(fixture.textView.string.isEmpty)
  await fixture.runtime.shutdown()
}

@Test(arguments: [false, true]) @MainActor
func runtimeEscapeToolbarStopStillFinishesAndSaves(focused: Bool) async throws {
  let fixture = try await RuntimeEscapeFixture(focused: focused)
  await fixture.runtime.toggle()
  #expect(fixture.runtime.phase == .listening(mode: fixture.mode, engine: .standard))
  await fixture.runtime.toggle()

  #expect(fixture.engine.finishCount == 1)
  #expect(fixture.history.records.count == 1)
  #expect(fixture.history.records.first?.insertionOutcome == .saved)
  #expect(fixture.history.records.first?.mode == fixture.mode)
  if focused {
    #expect(fixture.textView.string == "Synthetic diagnostic transcript.")
  }
  await fixture.runtime.shutdown()
}

@Test(arguments: [false, true]) @MainActor
func runtimeEscapeOwnedPointerEscapeCancelsListeningCapture(focused: Bool) async throws {
  let fixture = try await RuntimeEscapeFixture(focused: focused)
  #expect(fixture.shortcut.startPointerHandsFree())
  for _ in 0..<100 where fixture.runtime.phase == .arming {
    await Task.yield()
  }
  #expect(fixture.runtime.phase == .listening(mode: fixture.mode, engine: .standard))
  #expect(fixture.escape.isRegistered)
  #expect(fixture.shortcut.activeOwnership?.mode == fixture.mode)

  fixture.escape.emit()
  for _ in 0..<100 where fixture.runtime.phase != .idle {
    await Task.yield()
  }
  await fixture.shortcut.waitForTerminalObservation()

  #expect(fixture.runtime.phase == .idle)
  #expect(fixture.engine.cancelCount == 1)
  #expect(fixture.engine.finishCount == 0)
  #expect(fixture.history.records.isEmpty)
  #expect(fixture.textView.string.isEmpty)
  #expect(!fixture.escape.isRegistered)
  await fixture.runtime.shutdown()
}

@Test(arguments: [false, true]) @MainActor
func runtimeEscapeOwnedHoldEscapeCancelsListeningCapture(focused: Bool) async throws {
  let fixture = try await RuntimeEscapeFixture(focused: focused)
  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()
  for _ in 0..<100 where fixture.runtime.phase == .arming {
    await Task.yield()
  }

  #expect(fixture.runtime.phase == .listening(mode: fixture.mode, engine: .standard))
  #expect(fixture.shortcut.activeOwnership?.trigger == .hold)
  #expect(fixture.escape.modifiers == [.rightOption])

  fixture.escape.emit()
  for _ in 0..<100 where fixture.runtime.phase != .idle {
    await Task.yield()
  }
  await fixture.shortcut.waitForTerminalObservation()

  #expect(fixture.runtime.phase == .idle)
  #expect(fixture.engine.cancelCount == 1)
  #expect(fixture.engine.finishCount == 0)
  #expect(fixture.history.records.isEmpty)
  await fixture.runtime.shutdown()
}

@Test(arguments: [false, true]) @MainActor
func runtimeEscapeOwnedDoubleTapEscapeCancelsHandsFreeCapture(focused: Bool) async throws {
  let fixture = try await RuntimeEscapeFixture(focused: focused)
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(40))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()
  await fixture.shortcut.waitForTerminalObservation()
  #expect(fixture.history.records.count == 1)

  fixture.clock.advance(by: .milliseconds(100))
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()
  for _ in 0..<100 where fixture.runtime.phase == .arming {
    await Task.yield()
  }

  #expect(fixture.runtime.phase == .listening(mode: fixture.mode, engine: .standard))
  #expect(fixture.shortcut.activeOwnership?.trigger == .doubleTap)
  #expect(fixture.shortcut.activeOwnership?.isHandsFree == true)

  fixture.escape.emit()
  for _ in 0..<100 where fixture.runtime.phase != .idle {
    await Task.yield()
  }
  await fixture.shortcut.waitForTerminalObservation()

  #expect(fixture.runtime.phase == .idle)
  #expect(fixture.engine.finishCount == 1)
  #expect(fixture.history.records.count == 1)
  await fixture.runtime.shutdown()
}

@Test @MainActor
func runtimeEscapeDuringSuspendedHoldDoesNotArmNextPressAsDoubleTap() async throws {
  let queue = RuntimeEscapeQueue()
  let fixture = try await RuntimeEscapeFixture(
    focused: false,
    scheduleEscapeCancellation: { operation in queue.append(operation) }
  )
  let startGate = RuntimeEscapeGate()
  fixture.engine.startGate = startGate

  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()
  await startGate.waitUntilWaiting()

  fixture.escape.emit()
  fixture.clock.advance(by: .milliseconds(40))
  fixture.monitor.emit(.released(.rightOption))
  await Task.yield()
  let cancelling = Task { await queue.runFirst() }
  await Task.yield()
  await startGate.open()
  await cancelling.value
  await fixture.shortcut.drainEvents()
  await fixture.shortcut.waitForTerminalObservation()

  fixture.clock.advance(by: .milliseconds(100))
  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.shortcut.activeOwnership?.trigger == .hold)
  await fixture.runtime.cancel()
  await fixture.shortcut.waitForTerminalObservation()
  await fixture.runtime.shutdown()
}

@MainActor
private final class RuntimeEscapeFixture {
  let appState: AppState
  let engine = RuntimeEscapeEngine()
  let escape = RuntimeEscapeRegistrar()
  let monitor = RuntimeEscapeMonitor()
  let clock = RuntimeEscapeClock()
  let history: DictationHistoryController
  let shortcut: GlobalHoldShortcut
  let runtime: DictationRuntime
  let mode: DictationMode
  let commands = EditorCommands()
  let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let window: RuntimeEscapeKeyWindow

  init(
    focused: Bool,
    scheduleEscapeCancellation: @escaping @MainActor (
      @escaping @MainActor () async -> Void
    ) -> Void = { operation in
      _ = Task { @MainActor in await operation() }
    }
  ) async throws {
    mode = focused ? .focused : .smartCapture
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("runtime-escape-\(UUID().uuidString)")
    let store = LocalStore(rootURL: root)
    let preferences = AppPreferences(
      dictationSpeechEngine: .standard,
      dictationCapsuleEnabled: false
    )
    var workspace = Workspace()
    workspace.ensureNoteExists()
    try await store.save(workspace: workspace, preferences: preferences, trashedNotes: [])
    appState = AppState(store: store, saveOperation: { _, _, _ in })
    await appState.waitUntilInitialLoad()
    appState.preferences = preferences

    window = RuntimeEscapeKeyWindow(
      contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = textView
    window.reportsKey = focused
    commands.textView = textView
    window.makeFirstResponder(textView)
    let registry = DictationEditorRegistry()
    registry.register(commands)
    history = DictationHistoryController(load: { [] }, save: { _ in }, delete: { _ in }, clear: {})
    let coordinator = DictationCoordinator(
      engineProvider: engine,
      preferredEngine: { .standard },
      cleaner: RuntimeEscapeCleaner(),
      router: RuntimeEscapeRouter(),
      saver: appState,
      historyController: history,
      historyEnabled: { true },
      holdThreshold: .zero,
      holdSleeper: { _ in }
    )
    shortcut = GlobalHoldShortcut(
      handler: coordinator,
      editorProvider: { registry.focusedEditor() },
      destinationProvider: { [appState] in
        appState.selectedNote.map {
          DictationDestination(noteID: $0.id, title: $0.displayTitle)
        }
      },
      monitor: monitor,
      clock: clock,
      escapeRegistrar: escape
    )
    runtime = DictationRuntime(
      appState: appState,
      modelManager: DictationModelCapability(),
      engineProvider: engine,
      coordinator: coordinator,
      shortcutController: shortcut,
      capsuleController: DictationCapsuleController(),
      historyController: history,
      permissionController: DictationPermissionController(),
      editorRegistry: registry,
      startupAssessment: {},
      admittedModelSettingsViewModel: AdmittedModelSettingsViewModel(
        installer: BuiltInAdmittedModelInstaller()
      ),
      personalDictionaryStore: PersonalDictionaryStore(rootURL: root),
      availabilityProvider: {
        .evaluate(.init(
          osMajorVersion: 26,
          architecture: .appleSilicon,
          microphonePermission: .authorized,
          speechPermission: .authorized,
          appleOnDeviceRecognitionSupported: true,
          enhancedModelReady: false,
          foundationModelAvailable: false
        ))
      },
      scheduleEscapeCancellation: scheduleEscapeCancellation
    )
    await runtime.awaitStartupAssessment()
  }
}

private final class RuntimeEscapeKeyWindow: NSWindow {
  var reportsKey = false
  override var isKeyWindow: Bool { reportsKey }
}

@MainActor
private final class RuntimeEscapeEngine: SpeechEngine, SpeechEngineProviding {
  let kind = DictationSpeechEngine.standard
  var cancelCount = 0
  var finishCount = 0
  var startGate: RuntimeEscapeGate?

  func engineForCapture(preferred: DictationSpeechEngine) async throws -> any SpeechEngine {
    self
  }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    if let startGate { await startGate.wait() }
  }

  func finish() async throws -> String? {
    finishCount += 1
    return "Synthetic diagnostic transcript."
  }

  func cancel() async { cancelCount += 1 }
  func releaseResources() async {}
}

@MainActor
private final class RuntimeEscapeRegistrar: EscapeHotKeyRegistering {
  var eventHandler: (() -> Void)?
  var isRegistered = false
  private(set) var modifiers: [DictationModifierKey?] = []
  func register() throws { isRegistered = true }
  func register(modifier: DictationModifierKey?) throws {
    modifiers.append(modifier)
    isRegistered = true
  }
  func unregister() { isRegistered = false }
  func emit() {
    if isRegistered { eventHandler?() }
  }
}

@MainActor
private final class RuntimeEscapeMonitor: ModifierKeyMonitoring {
  var transitionHandler: ((ModifierKeyTransition) -> Void)?
  var stateHandler: ((ModifierMonitorState) -> Void)?
  var accessGranted: Bool { true }
  func start() throws { stateHandler?(.running) }
  func stop() { stateHandler?(.stopped) }
  func requestAccess() -> Bool { true }
  func emit(_ transition: ModifierKeyTransition) { transitionHandler?(transition) }
}

@MainActor
private final class RuntimeEscapeClock: GestureClock {
  private(set) var now = ContinuousClock().now
  func advance(by duration: Duration) { now = now.advanced(by: duration) }
}

@MainActor
private final class RuntimeEscapeQueue {
  private var operations: [@MainActor () async -> Void] = []
  func append(_ operation: @escaping @MainActor () async -> Void) {
    operations.append(operation)
  }
  func runFirst() async {
    guard !operations.isEmpty else { return }
    await operations.removeFirst()()
  }
}

private actor RuntimeEscapeGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var observers: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    let current = observers
    observers.removeAll()
    current.forEach { $0.resume() }
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilWaiting() async {
    guard !waiters.isEmpty else {
      await withCheckedContinuation { observers.append($0) }
      return
    }
  }

  func open() {
    isOpen = true
    let current = waiters
    waiters.removeAll()
    current.forEach { $0.resume() }
  }
}

private struct RuntimeEscapeCleaner: TranscriptCleaning {
  func clean(_ rawTranscript: String) async throws -> String { rawTranscript }
}

private struct RuntimeEscapeRouter: DestinationRouting {
  func route(
    transcript: String,
    candidates: [DictationRoutingCandidate],
    inboxID: UUID?
  ) async -> DictationRoutingDecision { .inbox }
}
