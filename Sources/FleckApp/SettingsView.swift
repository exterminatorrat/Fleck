#if os(macOS)
  import AppKit
  import AVFoundation
  import Carbon
  import SwiftUI
  import FleckCore
  import UniformTypeIdentifiers

  enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case editing = "Editing"
    case shortcuts = "Shortcuts"
    case dictation = "Dictation"
    case vocabulary = "Vocabulary"
    case agents = "Agents"

    static let fleckCases: [SettingsSection] = [.editing, .appearance, .shortcuts]
    static let voiceAndWritingCases: [SettingsSection] = [.dictation, .vocabulary]
    static let connectionCases: [SettingsSection] = [.agents]
    static let allCases: [SettingsSection] =
      fleckCases + voiceAndWritingCases + connectionCases

    var id: Self { self }

    var title: String {
      switch self {
      case .editing:
        "General"
      default:
        rawValue
      }
    }

    var systemImage: String {
      switch self {
      case .editing:
        "note.text"
      case .appearance:
        "paintbrush"
      case .shortcuts:
        "keyboard"
      case .dictation:
        "waveform"
      case .vocabulary:
        "character.book.closed"
      case .agents:
        "person.2"
      }
    }

    var description: String {
      switch self {
      case .editing:
        "Choose how Fleck edits and organizes your notes."
      case .appearance:
        "Adjust Fleck’s editor theme, type, and accent."
      case .shortcuts:
        "Set the keyboard shortcuts you use across Fleck."
      case .dictation:
        "Configure voice capture, models, microphones, and history."
      case .vocabulary:
        "Teach Fleck the words and spellings that matter to you."
      case .agents:
        "Control which local agents can work with your Fleck workspace."
      }
    }
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

  struct SettingsSectionSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
      List(selection: $selection) {
        sectionGroup("Fleck", sections: SettingsSection.fleckCases)
        sectionGroup("Voice & Writing", sections: SettingsSection.voiceAndWritingCases)
        sectionGroup("Connections", sections: SettingsSection.connectionCases)
      }
      .listStyle(.sidebar)
      .accessibilityLabel("Settings sections")
      .accessibilityIdentifier("settings-section-sidebar")
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
    }

    @ViewBuilder
    private func sectionGroup(
      _ title: LocalizedStringKey,
      sections: [SettingsSection]
    ) -> some View {
      Section(title) {
        ForEach(sections) { section in
          Label(section.title, systemImage: section.systemImage)
            .tag(section)
        }
      }
    }
  }

  struct SettingsPageHeader: View {
    let section: SettingsSection

    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(section.title)
          .font(.title2.weight(.semibold))
        Text(section.description)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.vertical, 18)
    }
  }

  struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var runtime: DictationRuntime
    @ObservedObject private var admittedModelSettingsViewModel: AdmittedModelSettingsViewModel
    @ObservedObject private var cleanupAdmittedModelSettingsViewModel: AdmittedModelSettingsViewModel
    @ObservedObject private var personalDictionarySettingsViewModel:
      PersonalDictionarySettingsViewModel
    @ObservedObject private var historyController: DictationHistoryController
    @State private var selectedSection = SettingsSection.appearance
    @State private var showsHistoryClearConfirmation = false
    @State private var recoveryActions: [DictationSystemSettingsAction] = []
    @State private var microphones: [DictationMicrophoneOption] = []
    @State private var recordingSelection = SettingsShortcutRecordingState()

    init(runtime: DictationRuntime) {
      self.runtime = runtime
      _admittedModelSettingsViewModel = ObservedObject(
        wrappedValue: runtime.admittedModelSettingsViewModel
      )
      _cleanupAdmittedModelSettingsViewModel = ObservedObject(
        wrappedValue: runtime.cleanupAdmittedModelSettingsViewModel
      )
      _personalDictionarySettingsViewModel = ObservedObject(
        wrappedValue: runtime.personalDictionarySettingsViewModel
      )
      _historyController = ObservedObject(wrappedValue: runtime.historyController)
    }

    var body: some View {
      NavigationSplitView {
        SettingsSectionSidebar(selection: $selectedSection)
      } detail: {
        VStack(alignment: .leading, spacing: 0) {
          SettingsPageHeader(section: selectedSection)
          Divider()

          Form {
            switch selectedSection {
            case .appearance:
              appearance
            case .editing:
              editing
            case .shortcuts:
              shortcuts
            case .dictation:
              dictation
            case .vocabulary:
              vocabulary
            case .agents:
              AgentSettingsView()
            }
          }
          .formStyle(.grouped)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .navigationSplitViewStyle(.balanced)
      .onChange(of: selectedSection) { _, newSection in
        recordingSelection.transition(to: newSection)
      }
      .onAppear {
        consumePendingSettingsRoute()
      }
      .onChange(of: runtime.pendingSettingsSection) { _, _ in
        consumePendingSettingsRoute()
      }
      .onDisappear { recordingSelection.cancel() }
      .task {
        await runtime.awaitStartupAssessment()
        await admittedModelSettingsViewModel.refresh()
        await cleanupAdmittedModelSettingsViewModel.refresh()
        await personalDictionarySettingsViewModel.load()
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

    private func consumePendingSettingsRoute() {
      guard let section = runtime.consumePendingSettingsSection() else { return }
      selectedSection = section
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
          runtime.preferencesDidChange()
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

    @ViewBuilder
    private var dictation: some View {
      if !availabilityIssues.isEmpty || !recoveryActions.isEmpty {
        Section("Needs attention") {
          ForEach(availabilityIssues, id: \.title) { row in
            Label(
              "\(row.title) — \(row.detail)",
              systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
          }
          ForEach(recoveryActions, id: \.pane) { action in
            Button(action.title) {
              NSWorkspace.shared.open(action.url)
            }
          }
        }
      }

      models

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

    private var vocabulary: some View {
      PersonalDictionarySettingsSection(
        viewModel: personalDictionarySettingsViewModel
      )
    }

    private var availabilityIssues: [DictationCompatibilityRow] {
      let compatibility = DictationCompatibilityPresentation(
        availability: runtime.availability
      )
      return [compatibility.appleSpeech, compatibility.cleanup, compatibility.smartCapture]
        .filter { !$0.available }
    }

    private var models: some View {
      Section("Models") {
        LabeledContent("Dictation") {
          modelRow(
            presentation: admittedModelSettingsViewModel.presentation,
            viewModel: admittedModelSettingsViewModel,
            progressAccessibilityLabel: "Enhanced local dictation installation progress"
          )
        }

        LabeledContent("Cleanup") {
          modelRow(
            presentation: cleanupAdmittedModelSettingsViewModel.presentation,
            viewModel: cleanupAdmittedModelSettingsViewModel,
            progressAccessibilityLabel: "Enhanced local cleanup installation progress"
          )
        }
      }
    }

    private func modelRow(
      presentation: AdmittedModelSettingsPresentation,
      viewModel: AdmittedModelSettingsViewModel,
      progressAccessibilityLabel: String
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text("Model: \(presentation.modelLabel)")
          .font(.caption.weight(.medium))
        if presentation.showsStatus {
          Text(presentation.compactStatus)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if presentation.showsDetail {
          Text(presentation.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let progress = presentation.progress {
          ProgressView(value: progress)
            .accessibilityLabel(progressAccessibilityLabel)
            .accessibilityValue(presentation.progressAccessibilityValue ?? "")
        }
        if let action = presentation.primaryAction,
           let label = presentation.primaryActionLabel {
          Button(label) { viewModel.perform(action) }
            .focusable(presentation.isKeyboardFocusable)
            .buttonStyle(.borderedProminent)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
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

  private struct PersonalDictionarySettingsSection: View {
    @ObservedObject var viewModel: PersonalDictionarySettingsViewModel
    @State private var showsImporter = false
    @State private var showsDictionaryExporter = false
    @State private var showsCSVExporter = false
    @FocusState private var isSearchFocused: Bool

    private let maximumTransferBytes = 64 * 1024 + 256

    var body: some View {
      Section("Vocabulary") {
        VStack(alignment: .leading, spacing: 4) {
          Text("Help Fleck recognize the words and phrases you use.")
          Text("Add a correction only when Fleck consistently hears something else.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        HStack {
          Text(entrySummary)
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Picker("Show", selection: $viewModel.filter) {
            ForEach(PersonalDictionarySettingsViewModel.Filter.allCases) { filter in
              Text(filter.rawValue).tag(filter)
            }
          }
          .pickerStyle(.menu)
          .frame(width: 110)
          .accessibilityLabel("Personal dictionary filter")
          .accessibilityValue(viewModel.filter.rawValue)
          .accessibilityHint("Filters entries or shows pending suggestions")

          Button("Add Word") { viewModel.beginAddingEntry() }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Add a word to Fleck vocabulary")
            .accessibilityHint("Opens the vocabulary word editor")
        }

        messages
        rows
        transfer
        searchUtility
      }
      .sheet(
        isPresented: Binding(
          get: { viewModel.entryEdit != nil },
          set: { if !$0 { viewModel.cancelEntryEdit() } }
        )
      ) {
        if let edit = viewModel.entryEdit {
          PersonalDictionaryEntryEditSheet(
            isNew: edit.isNew,
            preferredForm: Binding(
              get: { viewModel.entryEditPreferredForm },
              set: { viewModel.entryEditPreferredForm = $0 }
            ),
            aliases: Binding(
              get: { viewModel.entryEditAliases },
              set: { viewModel.entryEditAliases = $0 }
            ),
            usesCorrection: Binding(
              get: { viewModel.entryEditUsesCorrection },
              set: { viewModel.entryEditUsesCorrection = $0 }
            ),
            isEnabled: Binding(
              get: { viewModel.entryEditIsEnabled },
              set: { viewModel.entryEditIsEnabled = $0 }
            ),
            isMutationInFlight: viewModel.isEntryEditMutationInFlight,
            errorMessage: viewModel.errorMessage,
            onCancel: { viewModel.cancelEntryEdit() },
            onSave: {
              Task { @MainActor in await viewModel.submitEntryEdit() }
            },
            onDelete: {
              Task { @MainActor in await viewModel.deleteEntryEdit() }
            }
          )
        }
      }
      .sheet(
        isPresented: Binding(
          get: { viewModel.suggestionEdit != nil },
          set: { if !$0 { viewModel.cancelSuggestionEdit() } }
        )
      ) {
        PersonalDictionarySuggestionEditSheet(
          preferredForm: $viewModel.suggestionEditPreferredForm,
          aliases: $viewModel.suggestionEditAliases,
          errorMessage: viewModel.errorMessage,
          statusMessage: viewModel.statusMessage,
          onCancel: { viewModel.cancelSuggestionEdit() },
          onSubmit: {
            Task { @MainActor in
              await viewModel.submitSuggestionEdit()
            }
          }
        )
      }
      .sheet(
        isPresented: Binding(
          get: { viewModel.isImportPreviewPresented },
          set: { if !$0 { viewModel.cancelImportPreview() } }
        )
      ) {
        PersonalDictionaryImportPreviewSheet(viewModel: viewModel)
      }
      .fileImporter(
        isPresented: $showsImporter,
        allowedContentTypes: [.fleckDictionary, .json],
        allowsMultipleSelection: false,
        onCompletion: handleImport
      )
      .fileExporter(
        isPresented: $showsDictionaryExporter,
        document: PersonalDictionaryTransferDocument(data: viewModel.canonicalExportData ?? Data()),
        contentType: .fleckDictionary,
        defaultFilename: "Fleck Personal Dictionary.fleckdict",
        onCompletion: handleFileCompletion
      )
      .fileExporter(
        isPresented: $showsCSVExporter,
        document: PersonalDictionaryTransferDocument(data: viewModel.csvExportData ?? Data()),
        contentType: .commaSeparatedText,
        defaultFilename: "Fleck Personal Dictionary Entries.csv",
        onCompletion: handleFileCompletion
      )
    }

    private var entrySummary: String {
      let count = viewModel.entries.count
      return count == 1 ? "1 saved word" : "\(count) saved words"
    }

    @ViewBuilder
    private var messages: some View {
      if let errorMessage = viewModel.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .font(.caption)
          .accessibilityLabel("Personal dictionary error")
          .accessibilityValue(errorMessage)
      } else if let statusMessage = viewModel.statusMessage {
        Label(statusMessage, systemImage: "checkmark.circle")
          .foregroundStyle(.secondary)
          .font(.caption)
          .accessibilityLabel("Personal dictionary status")
          .accessibilityValue(statusMessage)
      }
    }

    @ViewBuilder
    private var rows: some View {
      if viewModel.filter == .suggestions {
        if viewModel.visibleSuggestions.isEmpty {
          Text("No pending suggestions.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(viewModel.visibleSuggestions) { suggestion in
            suggestionRow(suggestion, expectedRevision: viewModel.revision)
          }
        }
      } else if viewModel.visibleEntries.isEmpty {
        Text(viewModel.query.isEmpty ? "No entries yet." : "No matching entries.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.visibleEntries) { entry in
          entryRow(entry)
        }
      }
    }

    private func entryRow(_ entry: PersonalDictionaryEntry) -> some View {
      HStack(spacing: 12) {
        Button {
          viewModel.beginEditingEntry(entry)
        } label: {
          HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
              HStack(spacing: 5) {
                Text(entry.preferredForm)
                  .fontWeight(.medium)
                if entry.isPriority {
                  Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Prioritized")
                }
              }
              if !entry.aliases.isEmpty {
                Text("Corrects: \(entry.aliases.joined(separator: ", "))")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(entry.preferredForm)")
        .accessibilityValue(
          entry.aliases.isEmpty
            ? "Saved word"
            : "Corrects \(entry.aliases.joined(separator: ", "))"
        )
        .accessibilityHint("Opens this vocabulary word for editing")

        Toggle("Use \(entry.preferredForm)", isOn: Binding(
          get: { entry.isEnabled },
          set: { enabled in
            let expectedRevision = viewModel.revision
            Task { @MainActor in
              await viewModel.setEnabled(
                enabled,
                id: entry.id,
                expectedRevision: expectedRevision
              )
            }
          }
        ))
        .labelsHidden()
        .accessibilityLabel("Enable \(entry.preferredForm)")
        .accessibilityValue(entry.isEnabled ? "Enabled" : "Disabled")
        .accessibilityHint("Toggles whether this entry is used for dictation")
      }
      .accessibilityElement(children: .contain)
    }

    private func suggestionRow(
      _ suggestion: PersonalDictionarySuggestion,
      expectedRevision: UInt64
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(suggestion.preferredForm)
        if !suggestion.observedForms.isEmpty {
          Text(suggestion.observedForms.joined(separator: ", "))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        HStack {
          Button("Approve") {
            Task { @MainActor in
              await viewModel.approveSuggestion(
                id: suggestion.id,
                expectedRevision: expectedRevision
              )
            }
          }
          .accessibilityLabel("Approve \(suggestion.preferredForm)")
          .accessibilityHint("Adds this suggestion to the dictionary")

          Button("Edit and Approve") {
            viewModel.beginEditingSuggestion(suggestion)
          }
          .accessibilityLabel("Edit and approve \(suggestion.preferredForm)")
          .accessibilityHint("Reviews the preferred form and aliases before adding")

          Button("Dismiss", role: .destructive) {
            Task { @MainActor in
              await viewModel.dismissSuggestion(
                id: suggestion.id,
                expectedRevision: expectedRevision
              )
            }
          }
          .accessibilityLabel("Dismiss \(suggestion.preferredForm)")
          .accessibilityHint("Removes this pending suggestion")
        }
      }
      .accessibilityElement(children: .contain)
    }

    private var transfer: some View {
      DisclosureGroup("Transfer") {
        VStack(alignment: .leading, spacing: 8) {
          Button("Export Dictionary") {
            Task { @MainActor in
              await viewModel.prepareCanonicalExport()
              showsDictionaryExporter = viewModel.canonicalExportData != nil
            }
          }
          .accessibilityLabel("Export complete personal dictionary")
          .accessibilityHint("Exports entries and pending suggestions in a restorable format")

          Button("Export Entries (CSV)") {
            Task { @MainActor in
              await viewModel.prepareCSVExport()
              showsCSVExporter = viewModel.csvExportData != nil
            }
          }
          .accessibilityLabel("Export visible entries as CSV")
          .accessibilityHint("Exports only the currently visible entries")

          Text(
            "CSV excludes pending suggestions and cannot restore a complete personal dictionary."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          Button("Import Dictionary") { showsImporter = true }
            .accessibilityLabel("Import personal dictionary")
            .accessibilityHint("Selects a Fleck dictionary or compatible JSON file to preview")
        }
        .padding(.vertical, 4)
      }
    }

    private var searchUtility: some View {
      HStack {
        Spacer()
        HStack(spacing: 6) {
          Button {
            isSearchFocused = true
          } label: {
            Image(systemName: "magnifyingglass")
          }
          .buttonStyle(.plain)
          .keyboardShortcut("f", modifiers: .command)
          .help("Search vocabulary (⌘F)")
          .accessibilityLabel("Search vocabulary")
          .accessibilityHint("Focuses the vocabulary search field")

          TextField("Search", text: $viewModel.query)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .accessibilityLabel("Search vocabulary")
            .accessibilityValue(viewModel.query.isEmpty ? "No search" : viewModel.query)
            .accessibilityHint("Searches saved words and corrections")

          if !viewModel.query.isEmpty {
            Button {
              viewModel.query = ""
              isSearchFocused = true
            } label: {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear vocabulary search")
            .accessibilityHint("Clears the current vocabulary search")
          }
        }
        .frame(width: 200)
      }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else {
          viewModel.handleFileOperationFailure(CocoaError(.fileReadNoPermission))
          return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
          let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
          guard let fileSize, fileSize <= maximumTransferBytes else {
            throw PersonalDictionaryStoreError.fileTooLarge
          }
          let data = try Data(contentsOf: url, options: .mappedIfSafe)
          guard data.count <= maximumTransferBytes else {
            throw PersonalDictionaryStoreError.fileTooLarge
          }
          Task { @MainActor in await viewModel.previewCanonicalImport(data) }
        } catch {
          viewModel.handleFileOperationFailure(error)
        }
      case .failure(let error):
        viewModel.handleFileOperationFailure(error)
      }
    }

    private func handleFileCompletion(_ result: Result<URL, Error>) {
      if case .failure(let error) = result {
        viewModel.handleFileOperationFailure(error)
      }
    }
  }

  private struct PersonalDictionaryEntryEditSheet: View {
    let isNew: Bool
    @Binding var preferredForm: String
    @Binding var aliases: String
    @Binding var usesCorrection: Bool
    @Binding var isEnabled: Bool
    let isMutationInFlight: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    @State private var showsDeleteConfirmation = false

    var body: some View {
      Form {
        Section(isNew ? "Add Word" : "Edit Word") {
          TextField("Word or phrase", text: $preferredForm)
            .accessibilityLabel("Word or phrase")
            .accessibilityHint("The spelling Fleck should use")

          Toggle("Correct a misspelling or shorthand", isOn: $usesCorrection)
          if usesCorrection {
            TextField("Correct from", text: $aliases)
              .accessibilityLabel("Correct from")
              .accessibilityHint("The spelling or phrase Fleck should replace")
            Text("For multiple corrections, separate each one with a comma or new line.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Toggle("Use this word in dictation", isOn: $isEnabled)
        }
        .disabled(isMutationInFlight)

        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityLabel("Vocabulary editor error")
            .accessibilityValue(errorMessage)
        }

        Section {
          HStack {
            if !isNew {
              Button("Delete Word", role: .destructive) {
                showsDeleteConfirmation = true
              }
              .disabled(isMutationInFlight)
              .accessibilityLabel("Delete vocabulary word")
              .accessibilityHint("Asks for confirmation before deleting this word")
            }
            Spacer()
            if isMutationInFlight {
              ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Saving vocabulary word")
            }
            Button("Cancel", action: onCancel)
              .disabled(isMutationInFlight)
            Button("Save", action: onSave)
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
              .disabled(
                isMutationInFlight
                  || preferredForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              )
          }
        }
      }
      .formStyle(.grouped)
      .frame(width: 420, height: usesCorrection ? 330 : 280)
      .interactiveDismissDisabled(isMutationInFlight)
      .confirmationDialog(
        "Delete this word?",
        isPresented: $showsDeleteConfirmation
      ) {
        Button("Delete Word", role: .destructive, action: onDelete)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Fleck will stop applying this vocabulary entry.")
      }
    }
  }

  private struct PersonalDictionarySuggestionEditSheet: View {
    @Binding var preferredForm: String
    @Binding var aliases: String
    let errorMessage: String?
    let statusMessage: String?
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
      Form {
        TextField("Preferred form", text: $preferredForm)
        TextField("Aliases", text: $aliases)
        Text("Separate aliases with commas or new lines.")
          .font(.caption)
          .foregroundStyle(.secondary)
        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .font(.caption)
            .accessibilityLabel("Suggestion edit error")
            .accessibilityValue(errorMessage)
        } else if let statusMessage {
          Label(statusMessage, systemImage: "info.circle")
            .foregroundStyle(.secondary)
            .font(.caption)
            .accessibilityLabel("Suggestion edit status")
            .accessibilityValue(statusMessage)
        }
        HStack {
          Spacer()
          Button("Cancel", action: onCancel)
            .accessibilityLabel("Cancel suggestion edit")
          Button("Approve", action: onSubmit)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(preferredForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Approve edited suggestion")
        }
      }
      .formStyle(.grouped)
      .frame(width: 440)
      .padding()
    }
  }

  private struct PersonalDictionaryImportPreviewSheet: View {
    @ObservedObject var viewModel: PersonalDictionarySettingsViewModel
    @State private var omissionPreview: PersonalDictionaryImportPreview?

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Review Dictionary Import")
          .font(.title2.weight(.semibold))
        if let errorMessage = viewModel.errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .font(.caption)
            .accessibilityLabel("Dictionary import error")
            .accessibilityValue(errorMessage)
        } else if let statusMessage = viewModel.statusMessage {
          Label(statusMessage, systemImage: "info.circle")
            .foregroundStyle(.secondary)
            .font(.caption)
            .accessibilityLabel("Dictionary import status")
            .accessibilityValue(statusMessage)
        }
        if let preview = viewModel.importPreview {
          HStack {
            LabeledContent("Source", value: String(preview.sourceRevision))
            LabeledContent("Local", value: String(preview.expectedLocalRevision))
            LabeledContent("Target", value: String(preview.checkedTargetRevision))
          }
          .accessibilityElement(children: .contain)

          List {
            if viewModel.importPreviewRows.isEmpty {
              Text("No dictionary changes.")
                .foregroundStyle(.secondary)
            } else {
              ForEach(viewModel.importPreviewRows) { row in
                LabeledContent {
                  VStack(alignment: .trailing, spacing: 2) {
                    Text(row.title)
                    if let detail = row.detail {
                      Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                  }
                } label: {
                  Text("\(row.action.rawValue) \(row.kind.rawValue)")
                }
                .accessibilityLabel(row.accessibilityImportLabel)
                .accessibilityValue(row.detail ?? "No alternate forms")
                .accessibilityHint("Dictionary import preview row")
              }
            }
            ForEach(viewModel.importConflictRows) { conflict in
              LabeledContent(conflict.code, value: String(conflict.count))
                .accessibilityLabel("Compiler conflict \(conflict.code)")
                .accessibilityValue("\(conflict.count)")
                .accessibilityHint("Existing conflict code and count")
            }
          }
        }

        HStack {
          Spacer()
          Button("Cancel") { viewModel.cancelImportPreview() }
            .focusable()
            .accessibilityLabel("Cancel dictionary import")
            .accessibilityHint("Closes the preview without changing the dictionary")
          Button("Confirm Import") {
            guard let preview = viewModel.importPreview else { return }
            if viewModel.importRequiresOmissionConfirmation {
              omissionPreview = preview
            } else {
              Task { @MainActor in await viewModel.confirmCanonicalImport(preview) }
            }
          }
          .focusable()
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(!viewModel.canConfirmImport)
          .accessibilityLabel("Confirm dictionary import")
          .accessibilityValue(viewModel.canConfirmImport ? "Available" : "No changes")
          .accessibilityHint("Applies the reviewed dictionary changes")
        }
      }
      .frame(minWidth: 620, minHeight: 420)
      .padding()
      .confirmationDialog(
        "Import omits local dictionary content",
        isPresented: Binding(
          get: { omissionPreview != nil },
          set: { if !$0 { omissionPreview = nil } }
        ),
        presenting: omissionPreview
      ) { preview in
        Button("Import and Omit", role: .destructive) {
          Task { @MainActor in await viewModel.confirmCanonicalImport(preview) }
        }
        Button("Cancel", role: .cancel) {}
      } message: { _ in
        Text("The reviewed omitted entries and suggestions will be removed.")
      }
    }
  }

  private struct PersonalDictionaryTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.fleckDictionary, .commaSeparatedText] }
    let data: Data

    init(data: Data) {
      self.data = data
    }

    init(configuration: ReadConfiguration) throws {
      data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
      FileWrapper(regularFileWithContents: data)
    }
  }

  private extension UTType {
    static let fleckDictionary =
      UTType(filenameExtension: "fleckdict", conformingTo: .json)
      ?? UTType(
        exportedAs: "com.harryjin.fleck.personal-dictionary",
        conformingTo: .json
      )
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
