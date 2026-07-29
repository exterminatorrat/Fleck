#if os(macOS)
  import AppKit
  import SwiftUI
  import FleckAgentProtocol
  import FleckCore

  struct FleckStartupContext {
    let applicationSupportURL: URL
    let migrationError: FleckProductMigrationError?

    init(outcome: FleckProductMigrationOutcome) {
      switch outcome {
      case .freshInstall(let url), .migrated(let url), .alreadyMigrated(let url):
        applicationSupportURL = url
        migrationError = nil
      case .failed(let url, let error):
        applicationSupportURL = url
        migrationError = error
      }
    }
  }

  @main
  struct FleckApp: App {
    @StateObject private var appState: AppState
    @StateObject private var dictationRuntime: DictationRuntime
    private let agentRuntime: AgentIPCRuntime
    private let statusItemContextMenuController: StatusItemContextMenuController

    init() {
      statusItemContextMenuController = StatusItemContextMenuController()
      let applicationSupportParent = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )[0]
      let startup = FleckStartupContext(
        outcome: FleckProductMigration(
          applicationSupportParent: applicationSupportParent
        ).prepare()
      )
      let appSupport = startup.applicationSupportURL
      let agentProfileStore = AgentProfileStore(
        profilesURL: appSupport
          .appendingPathComponent("AgentIntegrations", isDirectory: true)
          .appendingPathComponent("profiles.json")
      )
      let agentActivityStore = AgentActivityStore(rootURL: appSupport)
      let appState = AppState(
        store: LocalStore(rootURL: appSupport),
        agentProfileStore: agentProfileStore,
        agentActivityStore: agentActivityStore,
        startupMigrationError: startup.migrationError
      )
      let agentService = AgentCommandService(
        state: appState,
        profileStore: agentProfileStore,
        activityStore: agentActivityStore
      )
      let agentServer = AgentIPCServer(
        endpointURL: appSupport
          .appendingPathComponent("AgentBridge", isDirectory: true)
          .appendingPathComponent("fleck.sock")
      ) { profileID, credential, command in
        try await agentService.execute(
          profileID: profileID,
          credential: credential,
          command: command
        )
      }
      agentRuntime = AgentIPCRuntime(
        appState: appState,
        server: agentServer
      )
      _appState = StateObject(wrappedValue: appState)
      _dictationRuntime = StateObject(
        wrappedValue: DictationRuntime(
          appState: appState,
          applicationSupportURL: appSupport
        )
      )
    }

    var body: some Scene {
      MenuBarExtra("Fleck", systemImage: "note.text") {
        NotesPanel(dictationRuntime: dictationRuntime)
          .environmentObject(appState)
          .preferredColorScheme(colorScheme)
      }
      .menuBarExtraStyle(.window)

      Window("Fleck", id: "pinned-notes") {
        NotesPanel(dictationRuntime: dictationRuntime, isPinned: true)
          .environmentObject(appState)
          .preferredColorScheme(colorScheme)
          .background(FloatingWindowConfigurator())
      }
      .windowResizability(.contentSize)
      .commands {
        CommandMenu("Dictation") {
          Button(dictationRuntime.recoveryCommand.title) {
            Task { await dictationRuntime.performRecoveryAction() }
          }
          .keyboardShortcut("r", modifiers: [.command, .shift])
          .disabled(!dictationRuntime.recoveryCommand.isEnabled)
        }
      }

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

  struct DictationRecoveryCommandPresentation: Equatable {
    let title: String
    let isEnabled: Bool
  }

  struct DictationCaptureFailurePresentation: Equatable {
    let message: String
    let actions: [DictationSystemSettingsAction]
  }

  @MainActor
  final class DictationRuntime: ObservableObject {
    static let usesPeriodicObservation = false
    static let savedCapsuleDuration = Duration.milliseconds(1_600)
    static let failureCapsuleDuration = Duration.seconds(3)

    private enum CapsuleOwner: Equatable {
      case idle
      case dictation
      case model(UUID)
    }

    private enum CapsuleUpdate {
      case coordinator(DictationCoordinatorEvent)
      case preflightFailure(String)
    }

    private final class ObserverToken: @unchecked Sendable {
      let value: NSObjectProtocol

      init(_ value: NSObjectProtocol) {
        self.value = value
      }
    }

    let modelManager: DictationModelCapability
    let engineProvider: any SpeechEngineProviding
    let coordinator: DictationCoordinator
    let shortcutController: GlobalHoldShortcut
    let capsuleController: DictationCapsuleController
    let historyController: DictationHistoryController

    @Published private(set) var phase = DictationPhase.idle
    @Published private(set) var modifierMonitorState = ModifierMonitorState.stopped
    @Published private(set) var modelError: String?
    @Published private(set) var availability: DictationAvailability
    @Published private(set) var recoveryAction: DictationCapsuleAction?
    @Published private(set) var recoveryActionInFlight = false
    @Published private(set) var captureFailure: DictationCaptureFailurePresentation?
    private(set) var currentCapsuleStatus: DictationCapsuleStatus?

    private weak var appState: AppState?
    private let permissionController: DictationPermissionController
    private let editorRegistry: DictationEditorRegistry
    private let enhancedIsReady: @MainActor () -> Bool
    private let availabilityProvider: @MainActor () -> DictationAvailability
    private let capsuleSleeper: @MainActor (Duration) async -> Void
    private var desiredModifier: DictationModifierKey?
    private var needsModifierApplication = false
    private var modelStateAssessed = false
    private var modelOperation: Task<Void, Never>?
    private var modelOperationID: UUID?
    private var modelOperations: [UUID: Task<Void, Never>] = [:]
    private var capsuleOwner: CapsuleOwner?
    private var capsuleDock = DictationCapsuleDock.bottom
    private var appliedCapsuleEnabled: Bool?
    private var capsuleReturnTask: Task<Void, Never>?
    private var capsuleGeneration: UInt64 = 0
    private var preloadCapsuleUpdate: CapsuleUpdate?
    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      private var activeModelRepairOwner: CapsuleOwner?
    #endif
    private var startupAssessmentTask: Task<Void, Never>?
    private var initialLoadSynchronizationTask: Task<Void, Never>?
    private var terminalSynchronizationTask: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var historyWindowController: NSWindowController?
    private var terminationObserver: ObserverToken?
    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      private var captureEngine: DictationSpeechEngine?
      private var captureReachedListening = false
    #endif
    private(set) var shutdownCount = 0

    convenience init(
      appState: AppState,
      applicationSupportURL: URL = AgentBridgeEndpoint.applicationSupportURL()
    ) {
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        let modelManager = DictationModelCapability(
          modelRootURL: applicationSupportURL.appendingPathComponent(
            "DictationModels",
            isDirectory: true
          )
        )
      #else
        let modelManager = DictationModelCapability()
      #endif
      let historyStore = DictationHistoryStore(rootURL: applicationSupportURL)
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
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        let startupAssessment: @MainActor () async -> Void = {
          await modelManager.refreshState()
        }
      #else
        let startupAssessment: @MainActor () async -> Void = {}
      #endif

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
        startupAssessment: startupAssessment,
        enhancedIsReady: {
          #if CLEAN_DICTATION_ENHANCED_CANDIDATE
            modelManager.verifiedLoadState.isReady
          #else
            modelManager.isReady
          #endif
        }
      )
    }

    init(
      appState: AppState,
      modelManager: DictationModelCapability,
      engineProvider: any SpeechEngineProviding,
      coordinator: DictationCoordinator,
      shortcutController: GlobalHoldShortcut,
      capsuleController: DictationCapsuleController,
      historyController: DictationHistoryController,
      permissionController: DictationPermissionController,
      editorRegistry: DictationEditorRegistry,
      startupAssessment: @escaping @MainActor () async -> Void,
      enhancedIsReady: @escaping @MainActor () -> Bool,
      availabilityProvider: (@MainActor () -> DictationAvailability)? = nil,
      capsuleSleeper: @escaping @MainActor (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
      }
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
      self.capsuleSleeper = capsuleSleeper
      let resolvedAvailabilityProvider = availabilityProvider ?? {
        DictationAvailability.current(
          permissions: permissionController,
          enhancedModelReady: enhancedIsReady()
        )
      }
      self.availabilityProvider = resolvedAvailabilityProvider
      availability = resolvedAvailabilityProvider()
      phase = coordinator.phase
      modifierMonitorState = shortcutController.monitorState

      coordinator.setEventObserver { [weak self] event in
        self?.receive(event)
      }
      shortcutController.monitorStateHandler = { [weak self] state in
        self?.modifierMonitorState = state
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
        self?.refreshAvailability()
        self?.synchronizePreferences()
      }
      initialLoadSynchronizationTask = Task { @MainActor [weak self, weak appState] in
        await appState?.waitUntilInitialLoad()
        guard !Task.isCancelled, let self, let appState else { return }
        self.applyLoadedPreferences(appState.preferences)
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

    var actualModifier: DictationModifierKey? {
      guard shortcutController.monitorState == .running else { return nil }
      return shortcutController.registeredModifier
    }

    var canChangeModifier: Bool {
      shortcutController.canChangeModifier
    }

    var recoveryCommand: DictationRecoveryCommandPresentation {
      .init(
        title: recoveryAction?.title ?? "Recover Last Dictation",
        isEnabled: recoveryAction != nil
          && !recoveryActionInFlight
          && coordinator.canConfigureShortcut
      )
    }

    func registerEditor(_ editor: any FocusedDictationEditing) {
      editorRegistry.register(editor)
    }

    func unregisterEditor(_ editor: any FocusedDictationEditing) {
      editorRegistry.unregister(editor)
    }

    func toggle() async {
      guard !recoveryActionInFlight, !coordinator.recoveryOperationInFlight else {
        return
      }
      switch coordinator.phase {
      case .idle, .saved, .failed:
        captureFailure = nil
        refreshAvailability()
        let preferredEngine =
          appState?.preferences.dictationSpeechEngine ?? .standard
        if preferredEngine == .standard, !availability.standardAvailable {
          let message =
            availability.standardFailureCopy
            ?? "Standard — Apple Speech is unavailable."
          publishPreflightFailure(
            message: message,
            actions: availability.openSystemSettings
          )
          return
        }
        #if CLEAN_DICTATION_ENHANCED_CANDIDATE
          captureEngine = preferredEngine
          captureReachedListening = false
        #endif
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
      let current = appState?.preferences.dictationModifierKey
      if current != desiredModifier {
        desiredModifier = current
        needsModifierApplication = true
      }
      synchronizePreferences()
    }

    func changeModifier(to modifier: DictationModifierKey) async -> Bool {
      guard shortcutController.canChangeModifier else { return false }
      if !shortcutController.preflightAccess(), !shortcutController.requestAccess() {
        return false
      }
      do {
        try shortcutController.configure(modifier)
      } catch {
        return false
      }
      desiredModifier = modifier
      needsModifierApplication = false
      appState?.updatePreferences { $0.dictationModifierKey = modifier }
      return true
    }

    func retryModifierMonitoring() async -> Bool {
      guard let modifier = appState?.preferences.dictationModifierKey else {
        return false
      }
      return await changeModifier(to: modifier)
    }

    func requestModifierMonitoringAccess() -> Bool {
      shortcutController.requestAccess()
    }

    func awaitStartupAssessment() async {
      await startupAssessmentTask?.value
      await initialLoadSynchronizationTask?.value
    }

    func waitForTerminalSynchronization() async {
      await terminalSynchronizationTask?.value
    }

    func permissionRecoveryActions() -> [DictationSystemSettingsAction] {
      availability.openSystemSettings
    }

    func openSystemSettings(_ action: DictationSystemSettingsAction) {
      NSWorkspace.shared.open(action.url)
    }

    func requestPermissionsAfterShortcutSetup() async {
      _ = await permissionController.requestAccess(
        for: appState?.preferences.dictationSpeechEngine ?? .standard,
        after: .shortcutSetupCompleted
      )
      refreshAvailability()
    }

    func downloadModel() {
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        runModelOperation(operation: { try await $0.download() })
      #endif
    }

    func repairModel() {
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        runModelOperation(
          showsRepairStatus: true,
          operation: { try await $0.repair() }
        )
      #endif
    }

    func updateModel() {
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        runModelOperation(operation: { try await $0.update() })
      #endif
    }

    func deleteModel() {
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        runModelOperation(
          operation: { try await $0.deleteModel() },
          onSuccess: { [weak self] in
            self?.appState?.updatePreferences { $0.dictationSpeechEngine = .standard }
            self?.synchronizePreferences()
          }
        )
      #endif
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
      invalidateCapsuleReturn()
      let modelOperations = Array(modelOperations.values)
      let startupAssessmentTask = startupAssessmentTask
      let initialLoadSynchronizationTask = initialLoadSynchronizationTask
      let terminalSynchronizationTask = terminalSynchronizationTask
      modelOperations.forEach { $0.cancel() }
      startupAssessmentTask?.cancel()
      initialLoadSynchronizationTask?.cancel()
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
        await initialLoadSynchronizationTask?.value
        await terminalSynchronizationTask?.value
        self?.dismissCapsule()
      }
      shutdownTask = task
      await task.value
    }

    private func synchronizePreferences(applyModifier: Bool = true) {
      guard let appState else { return }
      refreshAvailability()
      if !CleanDictationFeatures.enhancedLocalCandidateEnabled,
        appState.preferences.dictationSpeechEngine != .standard
      {
        appState.updatePreferences { $0.dictationSpeechEngine = .standard }
      }
      if
        modelStateAssessed,
        appState.preferences.dictationSpeechEngine == .enhancedLocal,
        !enhancedIsReady()
      {
        appState.updatePreferences { $0.dictationSpeechEngine = .standard }
      }

      guard appState.hasFinishedInitialLoad else { return }
      let currentDesiredModifier = appState.preferences.dictationModifierKey
      if desiredModifier != currentDesiredModifier {
        desiredModifier = currentDesiredModifier
        needsModifierApplication = true
      }
      if
        applyModifier,
        needsModifierApplication,
        shortcutController.canChangeModifier,
        shortcutController.preflightAccess()
      {
        do {
          try shortcutController.configure(currentDesiredModifier)
          needsModifierApplication = false
        } catch {
          return
        }
      }

      synchronizeCapsulePreferences()
    }

    private func receive(_ event: DictationCoordinatorEvent) {
      phase = event.phase
      recoveryAction = capsuleAction(for: coordinator.recoveryAction)
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        switch event.phase {
        case .arming:
          captureEngine =
            captureEngine
            ?? appState?.preferences.dictationSpeechEngine
            ?? .standard
          captureReachedListening = false
        case .listening(_, let engine):
          captureEngine = engine
          captureReachedListening = true
        case .idle, .finalizing, .cleaning, .routing, .saved, .failed:
          break
        }
      #endif
      updateCaptureFailure(for: event)
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        if event.terminal != nil {
          captureEngine = nil
          captureReachedListening = false
        }
      #endif
      presentCapsuleUpdate(.coordinator(event))
      synchronizeAfter(event)
    }

    private func presentCapsuleUpdate(_ update: CapsuleUpdate) {
      guard appState?.hasFinishedInitialLoad == true else {
        preloadCapsuleUpdate = update
        return
      }
      renderCapsuleUpdate(update)
    }

    private func renderCapsuleUpdate(_ update: CapsuleUpdate) {
      guard appState?.preferences.dictationCapsuleEnabled == true else {
        dismissCapsule()
        return
      }
      switch update {
      case .preflightFailure(let message):
        showFailureCapsule(message, action: nil)
      case .coordinator(let event):
        renderCoordinatorCapsule(event)
      }
    }

    private func renderCoordinatorCapsule(_ event: DictationCoordinatorEvent) {
      let action = capsuleAction(for: coordinator.recoveryAction)
      let status = Self.capsuleStatus(for: event)
      if let terminal = event.terminal {
        switch terminal {
        case .saved:
          showCapsule(status, owner: .dictation, action: action)
          scheduleIdle(after: Self.savedCapsuleDuration, owner: .dictation)
        case .failed(let message):
          showFailureCapsule(message, action: action)
        case .cancelled:
          showIdleCapsule()
        }
      } else {
        showCapsule(status, owner: .dictation, action: action)
      }
    }

    private func publishPreflightFailure(
      message: String,
      actions: [DictationSystemSettingsAction]
    ) {
      phase = .failed(message)
      captureFailure = .init(message: message, actions: actions)
      presentCapsuleUpdate(.preflightFailure(message))
    }

    private func showFailureCapsule(
      _ message: String,
      action: DictationCapsuleAction?
    ) {
      showCapsule(.failed(message), owner: .dictation, action: action)
      scheduleIdle(after: Self.failureCapsuleDuration, owner: .dictation)
    }

    private func synchronizeAfter(_ event: DictationCoordinatorEvent) {
      guard event.terminal != nil else {
        synchronizePreferences()
        return
      }
      synchronizePreferences(applyModifier: false)
      terminalSynchronizationTask?.cancel()
      let shortcutController = shortcutController
      terminalSynchronizationTask = Task { @MainActor [weak self] in
        await shortcutController.waitForTerminalObservation()
        guard !Task.isCancelled, let self else { return }
        if self.shortcutController.registeredModifier
          != self.appState?.preferences.dictationModifierKey
        {
          self.needsModifierApplication = true
        }
        self.synchronizePreferences()
      }
    }

    private func updateCaptureFailure(for event: DictationCoordinatorEvent) {
      switch event.phase {
      case .arming, .listening, .finalizing, .cleaning, .routing, .saved:
        captureFailure = nil
      case .idle:
        if event.terminal != nil { captureFailure = nil }
      case .failed(let message):
        let denied = DictationFailure.permissionDenied.localizedDescription
        let unavailable = DictationFailure.unavailable.localizedDescription
        refreshAvailability()
        #if CLEAN_DICTATION_ENHANCED_CANDIDATE
          switch captureEngine ?? .standard {
          case .standard:
            guard message == denied || message == unavailable else { return }
            captureFailure = .init(
              message: availability.standardFailureCopy ?? message,
              actions: availability.openSystemSettings
            )
          case .enhancedLocal:
            guard
              message == denied
                || message == unavailable
                || !captureReachedListening
            else { return }
            captureFailure = .init(
              message: availability.enhancedFailureCopy
                ?? "Enhanced Local could not start. Try again, repair the model in Dictation Settings, or switch to Standard.",
              actions: availability.openSystemSettings.filter {
                $0.pane == .microphone
              }
            )
          }
        #else
          guard message == denied || message == unavailable else { return }
          captureFailure = .init(
            message: availability.standardFailureCopy ?? message,
            actions: availability.openSystemSettings
          )
        #endif
      }
    }

    static func capsuleStatus(for event: DictationCoordinatorEvent) -> DictationCapsuleStatus {
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
          return .idle
        }
      }
      switch event.phase {
      case .arming, .listening:
        return .listening
      case .finalizing:
        return .finalizing
      case .cleaning:
        return .cleaning
      case .routing:
        return .routing
      case .saved(let destination):
        return .saved(destination: destination.title)
      case .failed(let message):
        return .failed(message)
      case .idle:
        return .idle
      }
    }

    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      @discardableResult
      func runModelOperation(
      showsRepairStatus: Bool = false,
      operation: @escaping @MainActor (DictationModelCapability) async throws -> Void,
      onSuccess: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never> {
      guard CleanDictationFeatures.enhancedLocalCandidateEnabled else {
        return Task {}
      }
      modelOperation?.cancel()
      let operationID = UUID()
      modelOperationID = operationID
      let owner = CapsuleOwner.model(operationID)
      if showsRepairStatus {
        activeModelRepairOwner = owner
        if appState?.preferences.dictationCapsuleEnabled == true {
          showCapsule(.repairingModel, owner: owner)
        }
      }
      let task = Task { @MainActor [weak self, modelManager] in
        defer {
          if self?.activeModelRepairOwner == owner {
            self?.activeModelRepairOwner = nil
          }
          self?.modelOperationDidFinish(operationID)
        }
        do {
          try await operation(modelManager)
          guard self?.modelOperationID == operationID else { return }
          onSuccess()
          self?.modelError = nil
          if showsRepairStatus {
            self?.showIdleCapsule(ifOwnedBy: owner)
          }
        } catch is CancellationError {
          guard self?.modelOperationID == operationID else { return }
          if showsRepairStatus {
            self?.showIdleCapsule(ifOwnedBy: owner)
          }
        } catch ModelDownloadError.cancelled {
          guard self?.modelOperationID == operationID else { return }
          if showsRepairStatus {
            self?.showIdleCapsule(ifOwnedBy: owner)
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
            self?.scheduleIdle(after: Self.failureCapsuleDuration, owner: owner)
          }
        }
      }
      modelOperation = task
      modelOperations[operationID] = task
      return task
      }
    #endif

    private static func shortcutMessage(
      _ error: GlobalHoldShortcut.RegistrationError
    ) -> String {
      switch error {
      case .activeSession:
        "Finish the active dictation before changing its shortcut."
      case .eventDeliveryPending, .primaryKeyHeld:
        "Release the shortcut keys, then try again."
      case .monitorFailed, .system:
        "The modifier monitor could not be started."
      case .unauthorized:
        "Input Monitoring access is required for the modifier shortcut."
      case .uninstalled:
        "The shortcut controller is unavailable."
      }
    }

    private func applyLoadedPreferences(_ preferences: AppPreferences) {
      let bufferedCapsuleUpdate = preloadCapsuleUpdate
      preloadCapsuleUpdate = nil
      desiredModifier = preferences.dictationModifierKey
      needsModifierApplication = true
      appliedCapsuleEnabled = preferences.dictationCapsuleEnabled
      synchronizePreferences()
      guard preferences.dictationCapsuleEnabled else { return }
      if let bufferedCapsuleUpdate {
        renderCapsuleUpdate(bufferedCapsuleUpdate)
      } else {
        replayLiveCapsuleOrIdle()
      }
    }

    private func selectedDestination() -> DictationDestination? {
      appState?.selectedNote.map {
        DictationDestination(noteID: $0.id, title: $0.displayTitle)
      }
    }

    private func showCapsule(
      _ status: DictationCapsuleStatus,
      owner: CapsuleOwner,
      action: DictationCapsuleAction? = nil
    ) {
      guard appState?.hasFinishedInitialLoad == true else { return }
      invalidateCapsuleReturn()
      currentCapsuleStatus = status
      capsuleOwner = owner
      capsuleController.render(
        status,
        action: action,
        onAction: { [weak self] in
          Task { @MainActor [weak self] in
            await self?.performRecoveryAction()
          }
        }
      )
    }

    private func showIdleCapsule(ifOwnedBy owner: CapsuleOwner? = nil) {
      guard owner == nil || capsuleOwner == owner else { return }
      guard appState?.hasFinishedInitialLoad == true else { return }
      guard appState?.preferences.dictationCapsuleEnabled == true else {
        dismissCapsule()
        return
      }
      invalidateCapsuleReturn()
      capsuleOwner = .idle
      currentCapsuleStatus = .idle
      capsuleController.presentIdle(
        dock: capsuleDock,
        onOpenFleck: { [weak self] in self?.openFleckPanel() },
        onDockChanged: { [weak self] dock in self?.capsuleDockDidChange(dock) }
      )
    }

    private func scheduleIdle(
      after delay: Duration,
      owner: CapsuleOwner
    ) {
      capsuleGeneration &+= 1
      let generation = capsuleGeneration
      capsuleReturnTask?.cancel()
      let sleeper = capsuleSleeper
      capsuleReturnTask = Task { @MainActor [weak self] in
        await sleeper(delay)
        guard
          !Task.isCancelled,
          let self,
          self.capsuleGeneration == generation,
          self.capsuleOwner == owner
        else { return }
        self.showIdleCapsule()
      }
    }

    private func invalidateCapsuleReturn() {
      capsuleGeneration &+= 1
      capsuleReturnTask?.cancel()
      capsuleReturnTask = nil
    }

    private func synchronizeCapsulePreferences() {
      guard let appState, appState.hasFinishedInitialLoad else { return }
      let enabled = appState.preferences.dictationCapsuleEnabled
      let dock = appState.preferences.dictationCapsuleDock
      let becameEnabled = appliedCapsuleEnabled != true && enabled
      let dockChanged = dock != capsuleDock
      capsuleDock = dock
      appliedCapsuleEnabled = enabled

      if dockChanged {
        capsuleController.setDock(dock)
      }
      guard enabled else {
        preloadCapsuleUpdate = nil
        invalidateCapsuleReturn()
        dismissCapsule()
        return
      }
      if becameEnabled {
        replayLiveCapsuleOrIdle()
      }
    }

    private func replayLiveCapsuleOrIdle() {
      switch phase {
      case .arming, .listening, .finalizing, .cleaning, .routing:
        renderCoordinatorCapsule(.init(phase: phase, terminal: nil))
        return
      case .idle, .saved, .failed:
        break
      }
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        if let activeModelRepairOwner {
          showCapsule(.repairingModel, owner: activeModelRepairOwner)
          return
        }
      #endif
      showIdleCapsule()
    }

    private func capsuleDockDidChange(_ dock: DictationCapsuleDock) {
      capsuleDock = dock
      appState?.updatePreferences { $0.dictationCapsuleDock = dock }
    }

    private func openFleckPanel() {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first {
        $0 !== capsuleController.panel && $0.title == "Fleck"
      }?.makeKeyAndOrderFront(nil)
    }

    private func capsuleAction(
      for action: DictationRecoveryAction?
    ) -> DictationCapsuleAction? {
      switch action {
      case .undo: .undo
      case .copy: .copy
      case .openHistory: .openHistory
      case .openDestination: .openDestination
      case nil: nil
      }
    }

    func performRecoveryAction() async {
      guard recoveryCommand.isEnabled else { return }
      recoveryActionInFlight = true
      recoveryAction = nil
      defer {
        recoveryActionInFlight = false
        recoveryAction = capsuleAction(for: coordinator.recoveryAction)
      }
      guard let result = await coordinator.performRecoveryAction() else { return }
      switch result {
      case .completed:
        showIdleCapsule(ifOwnedBy: .dictation)
      case .copy(let text):
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showIdleCapsule(ifOwnedBy: .dictation)
      case .openHistory:
        openDictationHistory()
      case .openDestination(let noteID):
        openDestination(noteID)
      }
    }

    private func openDestination(_ noteID: UUID) {
      guard appState?.workspace.notes.contains(where: { $0.id == noteID }) == true else {
        return
      }
      appState?.select(noteID)
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first {
        $0 !== capsuleController.panel && $0.title == "Fleck"
      }?.makeKeyAndOrderFront(nil)
      showIdleCapsule(ifOwnedBy: .dictation)
    }

    private func openDictationHistory() {
      if let historyWindowController {
        NSApp.activate(ignoringOtherApps: true)
        historyWindowController.showWindow(nil)
        historyWindowController.window?.makeKeyAndOrderFront(nil)
        showIdleCapsule(ifOwnedBy: .dictation)
        return
      }
      let view = DictationHistoryView(
        history: historyController,
        onOpenDestination: { [weak self] noteID in
          self?.openDestination(noteID)
        }
      )
      let window = NSWindow(contentViewController: NSHostingController(rootView: view))
      window.title = "Dictation History"
      window.setContentSize(NSSize(width: 680, height: 480))
      let controller = NSWindowController(window: window)
      historyWindowController = controller
      NSApp.activate(ignoringOtherApps: true)
      controller.showWindow(nil)
      window.makeKeyAndOrderFront(nil)
      showIdleCapsule(ifOwnedBy: .dictation)
    }

    private func dismissCapsule(ifOwnedBy owner: CapsuleOwner? = nil) {
      guard owner == nil || capsuleOwner == owner else { return }
      invalidateCapsuleReturn()
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

    private func refreshAvailability() {
      availability = availabilityProvider()
    }

    deinit {
      modelOperations.values.forEach { $0.cancel() }
      capsuleReturnTask?.cancel()
      startupAssessmentTask?.cancel()
      initialLoadSynchronizationTask?.cancel()
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
    private let modelManager: DictationModelCapability
    private let permissionController: DictationPermissionController
    private let microphoneUID: @MainActor () -> String?
    private let microphoneSelectionChanged: @MainActor (MicrophoneSelection) -> Void
    private let recommendStandard: @MainActor () -> Void

    init(
      modelManager: DictationModelCapability,
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
        #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        EnhancedSpeechCapture(
          modelManager: modelManager,
          permissions: permissionController,
          microphoneUID: microphoneUID(),
          microphoneSelectionChanged: microphoneSelectionChanged,
          recommendStandard: recommendStandard
        )
        #else
          throw DictationFailure.unavailable
        #endif
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

  #if CLEAN_DICTATION_ENHANCED_CANDIDATE
    extension EnhancedModelVerifiedLoadState {
      var isReady: Bool {
        if case .ready = self { return true }
        return false
      }
    }
  #endif

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
  enum FleckApp {
    static func main() {
      print("Fleck is a native macOS application. Build this package on macOS 14 or later.")
    }
  }
#endif
