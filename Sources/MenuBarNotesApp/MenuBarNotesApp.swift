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

  @MainActor
  final class DictationRuntime: ObservableObject {
    let modelManager: EnhancedModelManager
    let engineProvider: any SpeechEngineProviding
    let coordinator: DictationCoordinator
    let shortcutController: GlobalHoldShortcut
    let capsuleController: DictationCapsuleController
    let historyStore: DictationHistoryStore

    @Published private(set) var phase = DictationPhase.idle
    @Published private(set) var shortcutError: String?
    @Published private(set) var modelError: String?

    private weak var appState: AppState?
    private let permissionController: DictationPermissionController
    private let editorRegistry: DictationEditorRegistry
    private var configuredShortcut: DictationShortcut?
    private var modelStateAssessed = false
    private var modelOperation: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?

    init(appState: AppState) {
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )[0]
      let root = appSupport.appendingPathComponent("MenuBarNotes", isDirectory: true)
      let modelManager = EnhancedModelManager()
      let historyStore = DictationHistoryStore(rootURL: root)
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
        historyStore: historyStore,
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
        onRegistrationError: { [weak appState] error in
          appState?.saveError = "Dictation shortcut: \(Self.shortcutMessage(error))"
        }
      )

      self.appState = appState
      self.modelManager = modelManager
      self.historyStore = historyStore
      self.permissionController = permissionController
      self.editorRegistry = editorRegistry
      self.engineProvider = engineProvider
      self.coordinator = coordinator
      self.shortcutController = shortcutController
      self.capsuleController = capsuleController

      Task { @MainActor [weak self, modelManager] in
        await modelManager.refreshState()
        self?.modelStateAssessed = true
        self?.synchronizePreferences()
      }
      observationTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          self?.synchronize()
          try? await Task.sleep(for: .milliseconds(50))
        }
      }
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
      isListening ? "Finish Dictation" : "Start Dictation"
    }

    func registerEditor(_ editor: any FocusedDictationEditing) {
      editorRegistry.register(editor)
    }

    func unregisterEditor(_ editor: any FocusedDictationEditing) {
      editorRegistry.unregister(editor)
    }

    func toggle(editor: (any FocusedDictationEditing)?) async {
      switch coordinator.phase {
      case .idle, .saved, .failed:
        let focusedEditor = editor?.canBeginFocusedDictation == true ? editor : nil
        phase = .arming
        presentCapsule(for: .arming)
        await coordinator.start(
          mode: focusedEditor == nil ? .smartCapture : .focused,
          editor: focusedEditor
        )
      case .arming, .listening:
        await coordinator.finish()
      case .finalizing, .cleaning, .routing:
        return
      }
      synchronizePhase()
    }

    func cancel() async {
      await coordinator.cancel()
      synchronizePhase()
    }

    func preferencesDidChange() {
      synchronizePreferences()
    }

    func permissionRecoveryActions() -> [DictationSystemSettingsAction] {
      permissionController.recoveryActions()
    }

    func requestPermissionsAfterShortcutSetup() async {
      _ = await permissionController.requestAccess(after: .shortcutSetupCompleted)
    }

    func downloadModel() {
      runModelOperation { try await $0.download() }
    }

    func repairModel() {
      runModelOperation { try await $0.repair() }
    }

    func updateModel() {
      runModelOperation { try await $0.update() }
    }

    func deleteModel() {
      runModelOperation { try await $0.deleteModel() } onSuccess: { [weak self] in
        self?.appState?.updatePreferences { $0.dictationSpeechEngine = .standard }
        self?.synchronizePreferences()
      }
    }

    func cancelModelOperation() {
      modelOperation?.cancel()
    }

    func clearModelError() {
      modelError = nil
    }

    private func synchronize() {
      synchronizePreferences()
      synchronizePhase()
    }

    private func synchronizePreferences() {
      guard let appState else { return }
      if
        modelStateAssessed,
        appState.preferences.dictationSpeechEngine == .enhancedLocal,
        !modelManager.verifiedLoadState.isReady
      {
        appState.updatePreferences { $0.dictationSpeechEngine = .standard }
      }

      let desiredShortcut = appState.preferences.dictationShortcut
      if configuredShortcut != desiredShortcut, coordinator.phase == .idle {
        do {
          try shortcutController.configure(desiredShortcut)
          configuredShortcut = desiredShortcut
          shortcutError = nil
        } catch let error as GlobalHoldShortcut.RegistrationError {
          shortcutError = Self.shortcutMessage(error)
          if case .conflict = error {
            configuredShortcut = desiredShortcut
          } else if case .system = error {
            configuredShortcut = desiredShortcut
          } else if case .uninstalled = error {
            configuredShortcut = desiredShortcut
          }
        } catch {
          shortcutError = error.localizedDescription
          configuredShortcut = desiredShortcut
        }
      }

      if !appState.preferences.dictationCapsuleEnabled {
        capsuleController.dismiss()
      }
    }

    private func synchronizePhase() {
      let newPhase = coordinator.phase
      guard phase != newPhase else { return }
      phase = newPhase
      presentCapsule(for: newPhase)
    }

    private func presentCapsule(for phase: DictationPhase) {
      guard appState?.preferences.dictationCapsuleEnabled == true else {
        capsuleController.dismiss()
        return
      }
      switch phase {
      case .arming, .listening:
        capsuleController.show(.listening)
      case .finalizing, .cleaning, .routing:
        capsuleController.show(.cleaning)
      case .saved(let destination):
        capsuleController.show(.saved(destination: destination.title))
      case .failed(let message):
        capsuleController.show(.failed(message))
      case .idle:
        capsuleController.dismiss()
      }
    }

    private func runModelOperation(
      _ operation: @escaping @MainActor (EnhancedModelManager) async throws -> Void,
      onSuccess: @escaping @MainActor () -> Void = {}
    ) {
      modelOperation?.cancel()
      modelOperation = Task { @MainActor [weak self, modelManager] in
        do {
          try await operation(modelManager)
          onSuccess()
          self?.modelError = nil
        } catch is CancellationError {
          return
        } catch ModelDownloadError.cancelled {
          return
        } catch {
          self?.modelError = error.localizedDescription
        }
      }
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
      case .system:
        "The shortcut could not be registered."
      case .uninstalled:
        "The shortcut controller is unavailable."
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
  private final class DictationEditorRegistry {
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
