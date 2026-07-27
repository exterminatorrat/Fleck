#if os(macOS)
  import AppKit
  import SwiftUI
  import MenuBarNotesCore

  @main
  struct MenuBarNotesApp: App {
    @StateObject private var appState: AppState
    @StateObject private var dictationRuntime: DictationRuntime

    init() {
      let appState = AppState()
      _appState = StateObject(wrappedValue: appState)
      _dictationRuntime = StateObject(
        wrappedValue: DictationRuntime(appState: appState)
      )
    }

    var body: some Scene {
      MenuBarExtra("Motes", systemImage: "note.text") {
        NotesPanel(dictationRuntime: dictationRuntime)
          .environmentObject(appState)
          .preferredColorScheme(colorScheme)
      }
      .menuBarExtraStyle(.window)

      Window("Motes", id: "pinned-notes") {
        NotesPanel(dictationRuntime: dictationRuntime, isPinned: true)
          .environmentObject(appState)
          .preferredColorScheme(colorScheme)
          .background(FloatingWindowConfigurator())
      }
      .windowResizability(.contentSize)

      Settings {
        SettingsView(runtime: dictationRuntime)
          .environmentObject(appState)
          .frame(width: 520, height: 440)
          .background(FloatingWindowConfigurator())
      }
    }

    private var colorScheme: ColorScheme? {
      switch appState.preferences.theme {
      case .system: nil
      case .light: .light
      case .dark: .dark
      }
    }
  }

  struct DictationToolbarPresentation: Equatable {
    enum PrimaryAction: Equatable {
      case start
      case finish
    }

    let primaryLabel: String
    let primaryAction: PrimaryAction?
    let canCancel: Bool

    init(phase: DictationPhase) {
      switch phase {
      case .idle, .saved, .failed:
        primaryLabel = "Start Dictation"
        primaryAction = .start
        canCancel = false
      case .arming, .listening:
        primaryLabel = "Finish Dictation"
        primaryAction = .finish
        canCancel = true
      case .finalizing:
        primaryLabel = "Finalizing Dictation"
        primaryAction = nil
        canCancel = true
      case .cleaning:
        primaryLabel = "Cleaning Dictation"
        primaryAction = nil
        canCancel = true
      case .routing:
        primaryLabel = "Routing Dictation"
        primaryAction = nil
        canCancel = true
      }
    }
  }

  @MainActor
  final class DictationRuntime: ObservableObject {
    static let usesPeriodicObservation = false

    private enum CapsuleOwner: Equatable {
      case dictation
      case model(UUID)
    }

    private final class ObserverToken: @unchecked Sendable {
      let value: NSObjectProtocol

      init(_ value: NSObjectProtocol) {
        self.value = value
      }
    }

    let modelManager: EnhancedModelManager
    let engineProvider: any SpeechEngineProviding
    let coordinator: DictationCoordinator
    let shortcutController: GlobalHoldShortcut
    let capsuleController: DictationCapsuleController
    let historyController: DictationHistoryController

    @Published private(set) var phase = DictationPhase.idle
    @Published private(set) var shortcutError: String?
    @Published private(set) var modelError: String?
    private(set) var currentCapsuleStatus: DictationCapsuleStatus?

    private weak var appState: AppState?
    private let permissionController: DictationPermissionController
    private let editorRegistry: DictationEditorRegistry
    private let enhancedIsReady: @MainActor () -> Bool
    private var desiredShortcut: DictationShortcut?
    private var needsShortcutApplication = false
    private var modelStateAssessed = false
    private var modelOperation: Task<Void, Never>?
    private var modelOperationID: UUID?
    private var modelOperations: [UUID: Task<Void, Never>] = [:]
    private var capsuleOwner: CapsuleOwner?
    private var startupAssessmentTask: Task<Void, Never>?
    private var terminalSynchronizationTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var terminationObserver: ObserverToken?
    private(set) var shutdownCount = 0

    convenience init(appState: AppState) {
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )[0]
      let root = appSupport.appendingPathComponent("MenuBarNotes", isDirectory: true)
      let modelManager = EnhancedModelManager()
      let historyStore = DictationHistoryStore(rootURL: root)
      let historyController = DictationHistoryController(store: historyStore)
      let permissionController = DictationPermissionController()
      let editorRegistry = DictationEditorRegistry()

      let engineProvider = DictationSpeechEngineProvider(
        modelManager: modelManager,
        permissionController: permissionController,
        microphoneUID: { [weak appState] in
          appState?.preferences.dictationMicrophoneUID
        },
        microphoneSelectionChanged: { [weak appState] selection in
          guard case .missingUsingAutomatic = selection else { return }
          appState?.updatePreferences { $0.dictationMicrophoneUID = nil }
        },
        recommendStandard: { [weak appState] in
          appState?.updatePreferences { $0.dictationSpeechEngine = .standard }
        }
      )
      let languageModel = FoundationModelDictation()
      let coordinator = DictationCoordinator(
        engineProvider: engineProvider,
        preferredEngine: { [weak appState] in
          appState?.preferences.dictationSpeechEngine ?? .standard
        },
        cleaner: languageModel,
        router: languageModel,
        saver: appState,
        historyController: historyController,
        historyEnabled: { [weak appState] in
          appState?.preferences.dictationHistoryEnabled ?? true
        }
      )
      let capsuleController = DictationCapsuleController()
      let shortcutController = GlobalHoldShortcut(
        handler: coordinator,
        editorProvider: { [weak editorRegistry] in
          editorRegistry?.focusedEditor()
        },
        destinationProvider: { [weak appState] in
          appState?.selectedNote.map {
            DictationDestination(noteID: $0.id, title: $0.displayTitle)
          }
        },
        onRegistrationError: { [weak appState] error in
          appState?.saveError = "Dictation shortcut: \(Self.shortcutMessage(error))"
        }
      )

      self.init(
        appState: appState,
        modelManager: modelManager,
        engineProvider: engineProvider,
        coordinator: coordinator,
        shortcutController: shortcutController,
        capsuleController: capsuleController,
        historyController: historyController,
        permissionController: permissionController,
        editorRegistry: editorRegistry,
        startupAssessment: { await modelManager.refreshState() },
        enhancedIsReady: { modelManager.verifiedLoadState.isReady }
      )
    }

    init(
      appState: AppState,
      modelManager: EnhancedModelManager,
      engineProvider: any SpeechEngineProviding,
      coordinator: DictationCoordinator,
      shortcutController: GlobalHoldShortcut,
      capsuleController: DictationCapsuleController,
      historyController: DictationHistoryController,
      permissionController: DictationPermissionController,
      editorRegistry: DictationEditorRegistry,
      startupAssessment: @escaping @MainActor () async -> Void,
      enhancedIsReady: @escaping @MainActor () -> Bool
    ) {
      self.appState = appState
      self.modelManager = modelManager
      self.historyController = historyController
      self.permissionController = permissionController
      self.editorRegistry = editorRegistry
      self.engineProvider = engineProvider
      self.coordinator = coordinator
      self.shortcutController = shortcutController
      self.capsuleController = capsuleController
      self.enhancedIsReady = enhancedIsReady
      phase = coordinator.phase

      coordinator.setEventObserver { [weak self] event in
        self?.receive(event)
      }
      terminationObserver = ObserverToken(
        NotificationCenter.default.addObserver(
          forName: NSApplication.willTerminateNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          Task { @MainActor [weak self] in
            await self?.shutdown()
          }
        }
      )
      let assessment = startupAssessment
      startupAssessmentTask = Task { @MainActor [weak self] in
        await assessment()
        guard !Task.isCancelled else { return }
        self?.modelStateAssessed = true
        self?.synchronizePreferences()
      }
      synchronizePreferences()
    }

    var isListening: Bool {
      if case .listening = phase { return true }
      return phase == .arming
    }

    var canCancel: Bool {
      switch phase {
      case .idle, .saved, .failed:
        false
      case .arming, .listening, .finalizing, .cleaning, .routing:
        true
      }
    }

    var microphoneSymbol: String {
      isListening ? "stop.circle.fill" : "mic"
    }

    var microphoneHelp: String {
      toolbarPresentation.primaryLabel
    }

    var toolbarPresentation: DictationToolbarPresentation {
      DictationToolbarPresentation(phase: phase)
    }

    var actualShortcut: DictationShortcut? {
      shortcutController.registeredShortcut
    }

    func registerEditor(_ editor: any FocusedDictationEditing) {
      editorRegistry.register(editor)
    }

    func unregisterEditor(_ editor: any FocusedDictationEditing) {
      editorRegistry.unregister(editor)
    }

    func toggle() async {
      switch coordinator.phase {
      case .idle, .saved, .failed:
        let editor = editorRegistry.focusedEditor()
        let focusedEditor = editor?.canBeginFocusedDictation == true ? editor : nil
        await coordinator.start(
          mode: focusedEditor == nil ? .smartCapture : .focused,
          editor: focusedEditor,
          destination: focusedEditor == nil ? nil : selectedDestination()
        )
      case .arming, .listening:
        await coordinator.finish()
      case .finalizing, .cleaning, .routing:
        return
      }
    }

    func cancel() async {
      await coordinator.cancel()
    }

    func preferencesDidChange() {
      let current = appState?.preferences.dictationShortcut
      if current != desiredShortcut {
        desiredShortcut = current
        needsShortcutApplication = true
      }
      synchronizePreferences()
    }

    func retryShortcutRegistration() {
      needsShortcutApplication = true
      synchronizePreferences()
    }

    func awaitStartupAssessment() async {
      await startupAssessmentTask?.value
    }

    func waitForTerminalSynchronization() async {
      await terminalSynchronizationTask?.value
    }

    func permissionRecoveryActions() -> [DictationSystemSettingsAction] {
      permissionController.recoveryActions()
    }

    func requestPermissionsAfterShortcutSetup() async {
      _ = await permissionController.requestAccess(after: .shortcutSetupCompleted)
    }

    func downloadModel() {
      runModelOperation(operation: { try await $0.download() })
    }

    func repairModel() {
      runModelOperation(
        showsRepairStatus: true,
        operation: { try await $0.repair() }
      )
    }

    func updateModel() {
      runModelOperation(operation: { try await $0.update() })
    }

    func deleteModel() {
      runModelOperation(
        operation: { try await $0.deleteModel() },
        onSuccess: { [weak self] in
          self?.appState?.updatePreferences { $0.dictationSpeechEngine = .standard }
          self?.synchronizePreferences()
        }
      )
    }

    func cancelModelOperation() {
      modelOperation?.cancel()
    }

    func clearModelError() {
      modelError = nil
    }

    func shutdown() async {
      if let shutdownTask {
        await shutdownTask.value
        return
      }
      shutdownCount += 1
      let modelOperations = Array(modelOperations.values)
      let startupAssessmentTask = startupAssessmentTask
      let terminalSynchronizationTask = terminalSynchronizationTask
      modelOperations.forEach { $0.cancel() }
      startupAssessmentTask?.cancel()
      terminalSynchronizationTask?.cancel()
      coordinator.setEventObserver(nil)
      if let terminationObserver {
        NotificationCenter.default.removeObserver(terminationObserver.value)
        self.terminationObserver = nil
      }
      let coordinator = coordinator
      let shortcutController = shortcutController
      let task = Task { @MainActor [weak self] in
        await coordinator.cancel()
        await coordinator.waitForTerminal()
        await shortcutController.uninstall()
        for modelOperation in modelOperations {
          await modelOperation.value
        }
        await startupAssessmentTask?.value
        await terminalSynchronizationTask?.value
        self?.dismissCapsule()
      }
      shutdownTask = task
      await task.value
    }

    private func synchronizePreferences(applyShortcut: Bool = true) {
      guard let appState else { return }
      if
        modelStateAssessed,
        appState.preferences.dictationSpeechEngine == .enhancedLocal,
        !enhancedIsReady()
      {
        appState.updatePreferences { $0.dictationSpeechEngine = .standard }
      }

      let currentDesiredShortcut = appState.preferences.dictationShortcut
      if desiredShortcut != currentDesiredShortcut {
        desiredShortcut = currentDesiredShortcut
        needsShortcutApplication = true
      }
      if applyShortcut, needsShortcutApplication, coordinator.canConfigureShortcut {
        do {
          try shortcutController.configure(currentDesiredShortcut)
          needsShortcutApplication = false
          shortcutError = nil
        } catch let error as GlobalHoldShortcut.RegistrationError {
          shortcutError = Self.shortcutMessage(error)
          needsShortcutApplication = false
        } catch {
          shortcutError = error.localizedDescription
          needsShortcutApplication = false
        }
      }

      if !appState.preferences.dictationCapsuleEnabled {
        dismissCapsule()
      }
    }

    private func receive(_ event: DictationCoordinatorEvent) {
      phase = event.phase
      guard appState?.preferences.dictationCapsuleEnabled == true else {
        dismissCapsule()
        synchronizeAfter(event)
        return
      }
      if let status = Self.capsuleStatus(for: event) {
        showCapsule(status, owner: .dictation)
      } else {
        dismissCapsule(ifOwnedBy: .dictation)
      }
      synchronizeAfter(event)
    }

    private func synchronizeAfter(_ event: DictationCoordinatorEvent) {
      guard event.terminal != nil else {
        synchronizePreferences()
        return
      }
      synchronizePreferences(applyShortcut: false)
      terminalSynchronizationTask?.cancel()
      let shortcutController = shortcutController
      terminalSynchronizationTask = Task { @MainActor [weak self] in
        await shortcutController.waitForTerminalObservation()
        guard !Task.isCancelled, let self else { return }
        if self.shortcutController.registeredShortcut
          != self.appState?.preferences.dictationShortcut
        {
          self.needsShortcutApplication = true
        }
        self.synchronizePreferences()
      }
    }

    static func capsuleStatus(for event: DictationCoordinatorEvent) -> DictationCapsuleStatus? {
      if let terminal = event.terminal {
        switch terminal {
        case .saved(let mode, let cleanup, let destination):
          let title =
            mode == .focused
            ? "current note"
            : destination?.title ?? "your notes"
          return cleanup == .cleaned
            ? .saved(destination: title)
            : .savedWithoutCleanup(destination: title)
        case .failed(let message):
          return .failed(message)
        case .cancelled:
          return nil
        }
      }
      switch event.phase {
      case .arming, .listening:
        return .listening
      case .finalizing, .cleaning, .routing:
        return .cleaning
      case .saved(let destination):
        return .saved(destination: destination.title)
      case .failed(let message):
        return .failed(message)
      case .idle:
        return nil
      }
    }

    @discardableResult
    func runModelOperation(
      showsRepairStatus: Bool = false,
      operation: @escaping @MainActor (EnhancedModelManager) async throws -> Void,
      onSuccess: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never> {
      modelOperation?.cancel()
      let operationID = UUID()
      modelOperationID = operationID
      let owner = CapsuleOwner.model(operationID)
      if showsRepairStatus, appState?.preferences.dictationCapsuleEnabled == true {
        showCapsule(.repairingModel, owner: owner)
      }
      let task = Task { @MainActor [weak self, modelManager] in
        defer { self?.modelOperationDidFinish(operationID) }
        do {
          try await operation(modelManager)
          guard self?.modelOperationID == operationID else { return }
          onSuccess()
          self?.modelError = nil
          if showsRepairStatus {
            self?.dismissCapsule(ifOwnedBy: owner)
          }
        } catch is CancellationError {
          guard self?.modelOperationID == operationID else { return }
          if showsRepairStatus {
            self?.dismissCapsule(ifOwnedBy: owner)
          }
        } catch ModelDownloadError.cancelled {
          guard self?.modelOperationID == operationID else { return }
          if showsRepairStatus {
            self?.dismissCapsule(ifOwnedBy: owner)
          }
        } catch {
          guard self?.modelOperationID == operationID else { return }
          self?.modelError = error.localizedDescription
          if
            showsRepairStatus,
            self?.appState?.preferences.dictationCapsuleEnabled == true,
            self?.capsuleOwner == owner
          {
            self?.showCapsule(.failed("Enhanced model repair failed."), owner: owner)
          }
        }
      }
      modelOperation = task
      modelOperations[operationID] = task
      return task
    }

    private static func shortcutMessage(
      _ error: GlobalHoldShortcut.RegistrationError
    ) -> String {
      switch error {
      case .activeSession:
        "Finish the active dictation before changing its shortcut."
      case .conflict:
        "That shortcut is already in use."
      case .eventDeliveryPending, .primaryKeyHeld:
        "Release the shortcut keys, then try again."
      case .replacementAndRestoreFailed:
        "The new shortcut failed and the previous shortcut could not be restored. No dictation shortcut is registered."
      case .system:
        "The shortcut could not be registered."
      case .uninstalled:
        "The shortcut controller is unavailable."
      }
    }

    private func selectedDestination() -> DictationDestination? {
      appState?.selectedNote.map {
        DictationDestination(noteID: $0.id, title: $0.displayTitle)
      }
    }

    private func showCapsule(
      _ status: DictationCapsuleStatus,
      owner: CapsuleOwner
    ) {
      currentCapsuleStatus = status
      capsuleOwner = owner
      capsuleController.show(status)
    }

    private func dismissCapsule(ifOwnedBy owner: CapsuleOwner? = nil) {
      guard owner == nil || capsuleOwner == owner else { return }
      currentCapsuleStatus = nil
      capsuleOwner = nil
      capsuleController.dismiss()
    }

    private func modelOperationDidFinish(_ operationID: UUID) {
      modelOperations.removeValue(forKey: operationID)
      guard modelOperationID == operationID else { return }
      modelOperation = nil
      modelOperationID = nil
    }

    deinit {
      modelOperations.values.forEach { $0.cancel() }
      startupAssessmentTask?.cancel()
      terminalSynchronizationTask?.cancel()
      if let terminationObserver {
        NotificationCenter.default.removeObserver(terminationObserver.value)
      }
      guard shutdownCount == 0 else { return }
      let coordinator = coordinator
      let shortcutController = shortcutController
      let capsuleController = capsuleController
      Task { @MainActor in
        await coordinator.cancel()
        await shortcutController.uninstall()
        capsuleController.dismiss()
      }
    }
  }

  @MainActor
  private final class DictationSpeechEngineProvider: SpeechEngineProviding {
    private let modelManager: EnhancedModelManager
    private let permissionController: DictationPermissionController
    private let microphoneUID: @MainActor () -> String?
    private let microphoneSelectionChanged: @MainActor (MicrophoneSelection) -> Void
    private let recommendStandard: @MainActor () -> Void

    init(
      modelManager: EnhancedModelManager,
      permissionController: DictationPermissionController,
      microphoneUID: @escaping @MainActor () -> String?,
      microphoneSelectionChanged: @escaping @MainActor (MicrophoneSelection) -> Void,
      recommendStandard: @escaping @MainActor () -> Void
    ) {
      self.modelManager = modelManager
      self.permissionController = permissionController
      self.microphoneUID = microphoneUID
      self.microphoneSelectionChanged = microphoneSelectionChanged
      self.recommendStandard = recommendStandard
    }

    func engineForCapture(preferred: DictationSpeechEngine) async throws -> any SpeechEngine {
      switch preferred {
      case .standard:
        AppleSpeechCapture(
          microphoneUID: microphoneUID(),
          permissions: permissionController,
          microphoneSelectionChanged: microphoneSelectionChanged
        )
      case .enhancedLocal:
        EnhancedSpeechCapture(
          modelManager: modelManager,
          recommendStandard: recommendStandard
        )
      }
    }
  }

  @MainActor
  final class DictationEditorRegistry {
    private final class WeakEditor {
      weak var value: (any FocusedDictationEditing)?

      init(_ value: any FocusedDictationEditing) {
        self.value = value
      }
    }

    private var editors: [WeakEditor] = []

    func register(_ editor: any FocusedDictationEditing) {
      editors.removeAll { $0.value == nil }
      guard !editors.contains(where: { $0.value === editor }) else { return }
      editors.append(WeakEditor(editor))
    }

    func unregister(_ editor: any FocusedDictationEditing) {
      editors.removeAll { $0.value == nil || $0.value === editor }
    }

    func focusedEditor() -> (any FocusedDictationEditing)? {
      editors.removeAll { $0.value == nil }
      return editors.compactMap(\.value).first { editor in
        guard let commands = editor as? EditorCommands, let textView = commands.textView else {
          return false
        }
        return textView.window?.firstResponder === textView
      }
    }
  }

  extension EnhancedModelVerifiedLoadState {
    var isReady: Bool {
      if case .ready = self { return true }
      return false
    }
  }

  private struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      configure(view)
      return view
    }

    func updateNSView(_ view: NSView, context: Context) {
      configure(view)
    }

    private func configure(_ view: NSView) {
      DispatchQueue.main.async {
        view.window?.level = .floating
        view.window?.hidesOnDeactivate = false
      }
    }
  }
#else
  import Foundation

  @main
  enum MenuBarNotesApp {
    static func main() {
      print("Motes is a native macOS application. Build this package on macOS 14 or later.")
    }
  }
#endif
