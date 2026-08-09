#if os(macOS)
  import AppKit
  import AVFoundation
  import Carbon
  import SwiftUI
  import FleckCore

  enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case editing = "Editing"
    case shortcuts = "Shortcuts"
    case dictation = "Dictation"
    case agents = "Agents"

    static let allCases: [SettingsSection] = [.appearance, .editing, .shortcuts, .dictation]
    static let selectorCases = allCases + [.agents]
    static let selectionEffectID = "settings-section"
    var id: Self { self }
  }

  struct SettingsShortcutRecordingState: Equatable {
    private(set) var action: Shortcut.Action?

    mutating func begin(_ action: Shortcut.Action) {
      self.action = action
    }

    mutating func cancel() {
      action = nil
    }

    mutating func transition(to section: SettingsSection) {
      if section != .shortcuts {
        cancel()
      }
    }
  }

  #if CLEAN_DICTATION_ENHANCED_CANDIDATE
    enum DictationModelAction: Equatable {
    case download
    case cancel
    case repair
    case delete
    case update

    var title: String {
      switch self {
      case .download: "Download Enhanced Model"
      case .cancel: "Cancel"
      case .repair: "Repair"
      case .delete: "Delete"
      case .update: "Update"
      }
    }
    }

    struct DictationModelConsentPresentation: Equatable {
    let downloadSize: String
    let installedSize: String
    let requirement: String
    let language: String
    let attribution: String
    let privacyCopy: String

    static let standard = Self(
      downloadSize: "442.9 MiB",
      installedSize: "442.9 MiB",
      requirement: "Apple silicon",
      language: "English",
      attribution: "Parakeet TDT 0.6B V2 by NVIDIA, adapted for Core ML by FluidInference.",
      privacyCopy:
        "Fleck downloads model files only after you confirm. It does not upload audio, transcripts, notes, titles, history, routing inputs, or other dictation data."
    )
    }

    struct DictationSettingsPresentation {
    let selectedEngine: DictationSpeechEngine
    let enhancedChoiceEnabled: Bool
    let primaryAction: DictationModelAction?
    let secondaryAction: DictationModelAction?
    let downloadProgress: Double?
    let statusCopy: String
    let architectureCopy: String?

    init(
      preferences: AppPreferences,
      modelState: EnhancedModelState,
      isArchitectureSupported: Bool,
      enhancedIsReady: Bool
    ) {
      enhancedChoiceEnabled = isArchitectureSupported && enhancedIsReady
      selectedEngine =
        preferences.dictationSpeechEngine == .enhancedLocal && enhancedChoiceEnabled
        ? .enhancedLocal : .standard
      architectureCopy =
        isArchitectureSupported ? nil : "Enhanced dictation requires Apple silicon."

      switch modelState {
      case .notInstalled:
        primaryAction = isArchitectureSupported ? .download : nil
        secondaryAction = nil
        downloadProgress = nil
        statusCopy = "Not Installed"
      case .downloading(let progress):
        primaryAction = .cancel
        secondaryAction = nil
        downloadProgress = progress
        statusCopy = "Downloading"
      case .verifying:
        primaryAction = nil
        secondaryAction = nil
        downloadProgress = nil
        statusCopy = "Verifying"
      case .installing:
        primaryAction = nil
        secondaryAction = nil
        downloadProgress = nil
        statusCopy = "Installing"
      case .ready:
        primaryAction = .delete
        secondaryAction = nil
        downloadProgress = nil
        statusCopy = "Ready"
      case .updateAvailable:
        primaryAction = .update
        secondaryAction = .delete
        downloadProgress = nil
        statusCopy = "Update Available"
      case .repairRequired(let message):
        primaryAction = isArchitectureSupported ? .repair : nil
        secondaryAction = nil
        downloadProgress = nil
        statusCopy = message
      case .removing:
        primaryAction = nil
        secondaryAction = nil
        downloadProgress = nil
        statusCopy = "Removing"
      }
    }
    }
  #endif

  struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var runtime: DictationRuntime
    @ObservedObject private var modelManager: DictationModelCapability
    @ObservedObject private var historyController: DictationHistoryController
    @State private var selectedSection = SettingsSection.appearance
    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      @State private var showsModelConsent = false
      @State private var showsModelDeleteConfirmation = false
    #endif
    @State private var showsHistoryClearConfirmation = false
    @State private var recoveryActions: [DictationSystemSettingsAction] = []
    @State private var microphones: [DictationMicrophoneOption] = []
    @State private var recordingSelection = SettingsShortcutRecordingState()
    @Namespace private var selectedSectionHighlight

    init(runtime: DictationRuntime) {
      self.runtime = runtime
      _modelManager = ObservedObject(wrappedValue: runtime.modelManager)
      _historyController = ObservedObject(wrappedValue: runtime.historyController)
    }

    var body: some View {
      ZStack {
        Form {
          sectionSelector

          switch selectedSection {
          case .appearance:
            appearance
          case .editing:
            editing
          case .shortcuts:
            shortcuts
          case .dictation:
            dictation
          case .agents:
            AgentSettingsView()
          }
        }
        .formStyle(.grouped)
        .id(selectedSection)
        .transition(.opacity)
      }
      .animation(motion.standard, value: selectedSection)
      .onChange(of: selectedSection) { _, newSection in
        recordingSelection.transition(to: newSection)
      }
      .onDisappear { recordingSelection.cancel() }
      .task {
        await runtime.awaitStartupAssessment()
        recoveryActions = runtime.permissionRecoveryActions()
        microphones = DictationMicrophoneOption.available()
        runtime.preferencesDidChange()
        await appState.refreshAgentProfiles()
        appState.refreshAgentActivity()
      }
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      .sheet(isPresented: $showsModelConsent) {
        ModelConsentView {
          showsModelConsent = false
        } onConfirm: {
          showsModelConsent = false
          runModelOperation(.download)
        }
      }
      .confirmationDialog(
        "Delete the Enhanced model?",
        isPresented: $showsModelDeleteConfirmation
      ) {
        Button("Delete Model", role: .destructive) {
          runModelOperation(.delete)
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Enhanced dictation returns to Standard. You can download the model again later.")
      }
      #endif
      .confirmationDialog(
        "Clear all dictation history?",
        isPresented: $showsHistoryClearConfirmation
      ) {
        Button("Clear History", role: .destructive) {
          Task {
            await historyController.clear()
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This removes all local transcript records. This cannot be undone.")
      }
      .alert(
        "Dictation",
        isPresented: Binding(
          get: {
            runtime.modelError != nil
              || historyController.errorMessage != nil
          },
          set: {
            if !$0 {
              runtime.clearModelError()
              historyController.errorMessage = nil
            }
          }
        )
      ) {
        Button("OK") {
          runtime.clearModelError()
          historyController.errorMessage = nil
        }
      } message: {
        Text(
          runtime.modelError
            ?? historyController.errorMessage
            ?? ""
        )
      }
    }

    private var sectionSelector: some View {
      HStack(spacing: 4) {
        ForEach(SettingsSection.selectorCases) { section in
          let isSelected = section == selectedSection
          Button {
            withAnimation(motion.spatial) {
              selectedSection = section
            }
          } label: {
            Text(section.rawValue)
              .font(.callout.weight(.medium))
              .foregroundStyle(isSelected ? Color.white : Color.primary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 7)
              .background {
                if isSelected {
                  RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
                    .matchedGeometryEffect(
                      id: SettingsSection.selectionEffectID,
                      in: selectedSectionHighlight
                    )
                }
              }
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(section.rawValue)
          .accessibilityValue(isSelected ? "Selected" : "Not selected")
          .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
      }
      .padding(3)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
      .padding()
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private var appearance: some View {
      Section("Editor") {
        Picker("Theme", selection: preferenceBinding(\.theme)) {
          ForEach(AppTheme.allCases, id: \.self) { theme in
            Text(theme.rawValue.capitalized).tag(theme)
          }
        }
        SettingsColorButton(
          title: "Accent color",
          currentHex: appState.preferences.accentHex,
          fallbackColor: .controlAccentColor
        ) { hex in
          guard let hex else { return }
          appState.updatePreferences { $0.accentHex = hex }
        }
        SettingsColorButton(
          title: "Editor text color",
          currentHex: appState.preferences.editorTextHex,
          resetTitle: "Use System",
          fallbackColor: .labelColor
        ) { hex in
          appState.updatePreferences { $0.editorTextHex = hex }
        }
        SettingsColorButton(
          title: "Editor background",
          currentHex: appState.preferences.editorBackgroundHex,
          resetTitle: "Use System",
          fallbackColor: .textBackgroundColor
        ) { hex in
          appState.updatePreferences { $0.editorBackgroundHex = hex }
        }
        Slider(value: preferenceBinding(\.panelOpacity), in: 0.55...1) {
          Text("Glass opacity")
        }
        HStack {
          Stepper(
            "Menu width: \(Int(appState.preferences.panelWidth))",
            value: preferenceBinding(\.panelWidth), in: 380...800, step: 20)
          Stepper(
            "Menu height: \(Int(appState.preferences.panelHeight))",
            value: preferenceBinding(\.panelHeight), in: 300...800, step: 20)
        }
      }
    }

    private var editing: some View {
      Section("Behavior") {
        Toggle("Create lists automatically", isOn: preferenceBinding(\.automaticLists))
        Toggle(
          "Confirm before moving notes to Trash",
          isOn: preferenceBinding(\.confirmBeforeMovingNotesToTrash)
        )
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { appState.preferences.launchAtLogin },
            set: { appState.setLaunchAtLogin($0) }
          ))
        Text(
          "Notes are stored locally as readable Markdown files with a small JSON workspace manifest."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }

    private var shortcuts: some View {
      Section("Keyboard shortcuts") {
        let conflicts = Shortcut.conflicts(in: appState.preferences.shortcuts)
        ForEach(Shortcut.Action.allCases, id: \.self) { action in
          let shortcut = appState.preferences.shortcuts.first(where: { $0.action == action })
          VStack(alignment: .leading, spacing: 5) {
            HStack {
              Text(action.title)
              Spacer()
              ShortcutRecorder(
                action: action,
                shortcut: shortcut,
                isRecording: recordingSelection.action == action,
                onBegin: { recordingSelection.begin(action) },
                onCapture: { chord in
                  recordShortcut(action, chord: chord)
                },
                onCancel: { recordingSelection.cancel() }
              )
              Button(shortcut?.key == nil ? "Restore" : "Remove") {
                recordingSelection.cancel()
                setShortcutEnabled(action, enabled: shortcut?.key == nil)
              }
            }
            if shortcut?.isEnabled == true, shortcut?.modifiers.isEmpty == true {
              Text(
                "This shortcut may replace normal typing or navigation while Fleck is active."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            if conflicts.contains(action) {
              Label("Conflicts with another shortcut", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
            }
          }
        }
        Text(
          "Click a shortcut and press the complete chord. Conflicting combinations are highlighted and disabled shortcuts can be restored at any time."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }

    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      private var dictationPresentation: DictationSettingsPresentation {
        DictationSettingsPresentation(
          preferences: appState.preferences,
          modelState: modelManager.state,
          isArchitectureSupported: modelManager.isArchitectureSupported,
          enhancedIsReady: modelManager.verifiedLoadState.isReady
        )
      }
    #endif

    @ViewBuilder
    private var dictation: some View {
      Section("Availability") {
        let compatibility = DictationCompatibilityPresentation(
          availability: runtime.availability
        )
        ForEach(
          [
            compatibility.notes,
            compatibility.appleSpeech,
            compatibility.cleanup,
            compatibility.smartCapture,
          ],
          id: \.title
        ) { row in
          Label(
            "\(row.title) — \(row.detail)",
            systemImage: row.available ? "checkmark.shield" : "info.circle"
          )
          .foregroundStyle(row.available ? .primary : .secondary)
        }
        if !recoveryActions.isEmpty {
          ForEach(recoveryActions, id: \.pane) { action in
            Button(action.title) {
              NSWorkspace.shared.open(action.url)
            }
          }
        }
        #if CLEAN_DICTATION_ENHANCED_CANDIDATE
          if let architectureCopy = dictationPresentation.architectureCopy {
            Label(architectureCopy, systemImage: "desktopcomputer.trianglebadge.exclamationmark")
              .foregroundStyle(.secondary)
          }
        #endif
      }

      Section("Speech Engine") {
        Picker("Engine", selection: dictationEngineBinding) {
          Text("Standard — Apple Speech").tag(DictationSpeechEngine.standard)
          #if CLEAN_DICTATION_ENHANCED_CANDIDATE
          Text("Enhanced Local")
            .tag(DictationSpeechEngine.enhancedLocal)
            .disabled(!dictationPresentation.enhancedChoiceEnabled)
          #endif
        }
        .pickerStyle(.radioGroup)

        #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        HStack {
          Text("Enhanced model")
          Spacer()
          Text(dictationPresentation.statusCopy)
            .foregroundStyle(.secondary)
        }

        if let progress = dictationPresentation.downloadProgress {
          ProgressView(value: progress)
            .accessibilityLabel("Enhanced model download")
            .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
        }

        HStack {
          if let action = dictationPresentation.primaryAction {
            Button(action.title) {
              handleModelAction(action)
            }
          }
          if let action = dictationPresentation.secondaryAction {
            Button(action.title, role: action == .delete ? .destructive : nil) {
              handleModelAction(action)
            }
          }
        }

        let consent = DictationModelConsentPresentation.standard
        LabeledContent("Download size", value: consent.downloadSize)
        LabeledContent("Installed size", value: consent.installedSize)
        LabeledContent("Requirement", value: consent.requirement)
        LabeledContent("Language", value: consent.language)
        Text(consent.attribution)
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack {
          Link(
            "Model attribution",
            destination: URL(
              string:
                "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml"
            )!
          )
          Button("Third-Party Notices") {
            if let notices = Bundle.module.url(
              forResource: "ThirdPartyNotices",
              withExtension: "md"
            ) {
              NSWorkspace.shared.open(notices)
            }
          }
        }
        #endif
      }

      Section("Controls") {
        Picker("Modifier key", selection: dictationModifierBinding) {
          ForEach(DictationModifierKey.allCases, id: \.self) { key in
            Text(
              key == .rightOption
                ? "\(key.displayName) — Recommended"
                : key.displayName
            ).tag(key)
          }
        }
        .disabled(!dictationModifierPresentation.isPickerEnabled)

        Text(dictationModifierPresentation.statusCopy)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let guidance = dictationModifierPresentation.guidanceCopy {
          Text(guidance)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let action = dictationModifierPresentation.recoveryAction {
          switch action {
          case .enableInputMonitoring:
            Button("Enable Input Monitoring") {
              Task { @MainActor in
                guard let settings = await runtime.recoverModifierMonitoring() else { return }
                runtime.openSystemSettings(settings)
              }
            }
          case .retry:
            Button("Retry") {
              Task {
                _ = await runtime.retryModifierMonitoring()
              }
            }
          }
        }

        Picker("Microphone", selection: dictationMicrophoneBinding) {
          Text("Automatic").tag(String?.none)
          ForEach(microphones) { microphone in
            Text(microphone.name).tag(Optional(microphone.id))
          }
        }

        LabeledContent("Recognition language", value: "English")
        Toggle("Show status capsule", isOn: dictationPreferenceBinding(\.dictationCapsuleEnabled))
        Toggle(
          "Keep local history for 30 days",
          isOn: dictationPreferenceBinding(\.dictationHistoryEnabled)
        )
        Button("Clear History", role: .destructive) {
          showsHistoryClearConfirmation = true
        }
      }

      Section("Privacy") {
        #if CLEAN_DICTATION_ENHANCED_CANDIDATE
        Text(DictationModelConsentPresentation.standard.privacyCopy)
        #endif
        Text(
          "Audio stays in memory only and is discarded when capture finishes, is cancelled, is interrupted, or fails. History is local, contains no audio, and expires after 30 days. Turning history off affects future successful captures only."
        )
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }

    private var dictationEngineBinding: Binding<DictationSpeechEngine> {
      Binding(
        get: {
          #if CLEAN_DICTATION_ENHANCED_CANDIDATE
            dictationPresentation.selectedEngine
          #else
            .standard
          #endif
        },
        set: { engine in
          #if CLEAN_DICTATION_ENHANCED_CANDIDATE
          guard engine == .standard || dictationPresentation.enhancedChoiceEnabled else { return }
          #else
            guard engine == .standard else { return }
          #endif
          appState.updatePreferences { $0.dictationSpeechEngine = engine }
          runtime.preferencesDidChange()
        }
      )
    }

    private var dictationModifierPresentation: DictationModifierSettingsPresentation {
      .init(
        selected: appState.preferences.dictationModifierKey,
        monitorStatus: runtime.modifierMonitorState,
        canChange: runtime.canChangeModifier
      )
    }

    private var dictationModifierBinding: Binding<DictationModifierKey> {
      Binding(
        get: { appState.preferences.dictationModifierKey },
        set: { modifier in
          Task { @MainActor in
            guard await runtime.changeModifier(to: modifier) else { return }
            await runtime.requestPermissionsAfterShortcutSetup()
            recoveryActions = runtime.permissionRecoveryActions()
          }
        }
      )
    }

    private var dictationMicrophoneBinding: Binding<String?> {
      Binding(
        get: { appState.preferences.dictationMicrophoneUID },
        set: { uid in
          appState.updatePreferences { $0.dictationMicrophoneUID = uid }
          runtime.preferencesDidChange()
        }
      )
    }

    private func dictationPreferenceBinding(
      _ keyPath: WritableKeyPath<AppPreferences, Bool>
    ) -> Binding<Bool> {
      Binding(
        get: { appState.preferences[keyPath: keyPath] },
        set: { value in
          appState.updatePreferences { $0[keyPath: keyPath] = value }
          runtime.preferencesDidChange()
        }
      )
    }

    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      private func handleModelAction(_ action: DictationModelAction) {
      switch action {
      case .download:
        showsModelConsent = true
      case .cancel:
        runtime.cancelModelOperation()
      case .delete:
        showsModelDeleteConfirmation = true
      case .repair, .update:
        runModelOperation(action)
      }
      }

      private func runModelOperation(_ action: DictationModelAction) {
      switch action {
      case .download:
        runtime.downloadModel()
      case .repair:
        runtime.repairModel()
      case .update:
        runtime.updateModel()
      case .delete:
        runtime.deleteModel()
      case .cancel:
        runtime.cancelModelOperation()
      }
      }
    #endif

    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>)
      -> Binding<Value>
    {
      Binding(
        get: { appState.preferences[keyPath: keyPath] },
        set: { value in
          appState.updatePreferences { $0[keyPath: keyPath] = value }
        }
      )
    }

    private func setShortcutEnabled(_ action: Shortcut.Action, enabled: Bool) {
      appState.updatePreferences { preferences in
        guard let index = preferences.shortcuts.firstIndex(where: { $0.action == action }) else {
          return
        }
        if enabled, let defaultShortcut = Shortcut.defaults.first(where: { $0.action == action }) {
          preferences.shortcuts[index] = defaultShortcut
        } else {
          preferences.shortcuts[index].key = nil
          preferences.shortcuts[index].modifiers = []
        }
      }
    }

    private func recordShortcut(_ action: Shortcut.Action, chord: ShortcutChord) {
      appState.updatePreferences { preferences in
        guard let index = preferences.shortcuts.firstIndex(where: { $0.action == action }) else {
          return
        }
        preferences.shortcuts[index] = Shortcut(
          action: action,
          key: chord.key,
          modifiers: chord.modifiers
        )
      }
      recordingSelection.cancel()
    }
  }

  private struct SettingsColorButton: View {
    let title: String
    let currentHex: String?
    let resetTitle: String?
    let fallbackColor: NSColor
    let onCommit: (String?) -> Void
    @State private var isPresented = false

    init(
      title: String,
      currentHex: String?,
      resetTitle: String? = nil,
      fallbackColor: NSColor,
      onCommit: @escaping (String?) -> Void
    ) {
      self.title = title
      self.currentHex = currentHex
      self.resetTitle = resetTitle
      self.fallbackColor = fallbackColor
      self.onCommit = onCommit
    }

    var body: some View {
      Button {
        isPresented = true
      } label: {
        HStack(spacing: 10) {
          Text(title)
          Spacer()
          RoundedRectangle(cornerRadius: 5)
            .fill(currentColor)
            .frame(width: 24, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
          Text(currentValue)
            .foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(title)
      .accessibilityValue(currentValue)
      .popover(isPresented: $isPresented, arrowEdge: .bottom) {
        FleckColorPicker(
          currentHex: currentHex,
          currentLabel: currentValue,
          resetTitle: resetTitle,
          fallbackHex: FleckColorHex.hex(from: fallbackColor) ?? "#7C6CF2",
          onCommit: { value in
            onCommit(value)
            isPresented = false
          },
          onCancel: { isPresented = false }
        )
      }
    }

    private var currentColor: Color {
      if let currentHex, let color = Color(hex: currentHex) {
        return color
      }
      return Color(nsColor: fallbackColor)
    }

    private var currentValue: String {
      guard let currentHex else { return resetTitle ?? "Automatic" }
      return FleckPaletteOption.paletteName(for: NSColor(hex: currentHex)) ?? "Custom"
    }
  }

  private struct DictationMicrophoneOption: Identifiable {
    let id: String
    let name: String

    static func available() -> [Self] {
      AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
      ).devices
        .map { Self(id: $0.uniqueID, name: $0.localizedName) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
  }

  #if CLEAN_DICTATION_ENHANCED_CANDIDATE
    private struct ModelConsentView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private let consent = DictationModelConsentPresentation.standard

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text("Download Enhanced Model?")
          .font(.title2.weight(.semibold))
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
          GridRow {
            Text("Download")
            Text(consent.downloadSize)
          }
          GridRow {
            Text("Installed")
            Text(consent.installedSize)
          }
          GridRow {
            Text("Requirement")
            Text(consent.requirement)
          }
          GridRow {
            Text("Language")
            Text(consent.language)
          }
        }
        Text(consent.attribution)
        Text(consent.privacyCopy)
          .foregroundStyle(.secondary)
        HStack {
          Spacer()
          Button("Cancel", role: .cancel, action: onCancel)
          Button("Download", action: onConfirm)
            .keyboardShortcut(.defaultAction)
        }
      }
      .padding(24)
      .frame(width: 460)
    }
    }
  #endif

#endif
