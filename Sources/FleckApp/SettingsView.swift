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

  struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var runtime: DictationRuntime
    @ObservedObject private var admittedModelSettingsViewModel: AdmittedModelSettingsViewModel
    @ObservedObject private var historyController: DictationHistoryController
    @State private var selectedSection = SettingsSection.appearance
    @State private var showsHistoryClearConfirmation = false
    @State private var recoveryActions: [DictationSystemSettingsAction] = []
    @State private var microphones: [DictationMicrophoneOption] = []
    @State private var recordingSelection = SettingsShortcutRecordingState()
    @Namespace private var selectedSectionHighlight

    init(runtime: DictationRuntime) {
      self.runtime = runtime
      _admittedModelSettingsViewModel = ObservedObject(
        wrappedValue: runtime.admittedModelSettingsViewModel
      )
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
        await admittedModelSettingsViewModel.refresh()
        recoveryActions = runtime.permissionRecoveryActions()
        microphones = DictationMicrophoneOption.available()
        runtime.preferencesDidChange()
        await appState.refreshAgentProfiles()
        appState.refreshAgentActivity()
      }
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
          get: { historyController.errorMessage != nil },
          set: {
            if !$0 {
              historyController.errorMessage = nil
            }
          }
        )
      ) {
        Button("OK") {
          historyController.errorMessage = nil
        }
      } message: {
        Text(historyController.errorMessage ?? "")
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
      }

      Section("Speech Engine") {
        admittedModelCard
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
        Text(
          "Audio stays in memory only and is discarded when capture finishes, is cancelled, is interrupted, or fails. History is local, contains no audio, and expires after 30 days. Turning history off affects future successful captures only."
        )
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }

    private var admittedModelCard: some View {
      let presentation: AdmittedModelSettingsPresentation =
        admittedModelSettingsViewModel.presentation

      return VStack(alignment: .leading, spacing: 8) {
        Label(presentation.title, systemImage: "waveform")
          .font(.headline)
        Text(presentation.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if let identity = presentation.identity {
          LabeledContent("Model", value: identity)
        }
        if let revision = presentation.revision {
          LabeledContent("Revision", value: revision)
        }
        if let license = presentation.license {
          LabeledContent("License", value: license)
        }
        if !presentation.checksums.isEmpty {
          LabeledContent(
            "Checksums",
            value: presentation.checksums.joined(separator: ", ")
          )
        }
        if let downloadBytes = presentation.downloadBytes {
          LabeledContent("Download size", value: "\(downloadBytes) bytes")
        }
        if let installedBytes = presentation.installedBytes {
          LabeledContent("Installed size", value: "\(installedBytes) bytes")
        }
        if !presentation.supportedArchitectures.isEmpty {
          Text("Supported architectures: \(presentation.supportedArchitectures.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if !presentation.supportedLanguages.isEmpty {
          Text("Supported languages: \(presentation.supportedLanguages.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let progress = presentation.progress {
          ProgressView(value: progress)
            .accessibilityLabel("Admitted model installation progress")
            .accessibilityValue(presentation.progressAccessibilityValue ?? "")
        }
        if let action = presentation.primaryAction,
           let label = presentation.primaryActionLabel {
          Button(label) { perform(action) }
            .focusable(presentation.isKeyboardFocusable)
            .buttonStyle(.borderedProminent)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 4)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(presentation.accessibilityLabel)
      .accessibilityValue(presentation.accessibilityValue)
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

    private func perform(_ action: AdmittedModelSettingsAction) {
      admittedModelSettingsViewModel.perform(action)
    }

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

#endif
