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
    @ObservedObject private var cleanupAdmittedModelSettingsViewModel: AdmittedModelSettingsViewModel
    @ObservedObject private var personalDictionarySettingsViewModel:
      PersonalDictionarySettingsViewModel
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
      _cleanupAdmittedModelSettingsViewModel = ObservedObject(
        wrappedValue: runtime.cleanupAdmittedModelSettingsViewModel
      )
      _personalDictionarySettingsViewModel = ObservedObject(
        wrappedValue: runtime.personalDictionarySettingsViewModel
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

      personalDictionary

      Section("Privacy") {
        Text(
          "Audio stays in memory only and is discarded when capture finishes, is cancelled, is interrupted, or fails. History is local, contains no audio, and expires after 30 days. Turning history off affects future successful captures only."
        )
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }

    private var personalDictionary: some View {
      PersonalDictionarySettingsSection(
        viewModel: personalDictionarySettingsViewModel
      )
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
    @State private var preferredForm = ""
    @State private var aliases = ""
    @State private var suggestionDraft: PersonalDictionarySuggestionDraft?
    @State private var showsImporter = false
    @State private var showsDictionaryExporter = false
    @State private var showsCSVExporter = false

    private let maximumTransferBytes = 64 * 1024 + 256

    var body: some View {
      Section("Personal Dictionary") {
        Picker("Show", selection: $viewModel.filter) {
          ForEach(PersonalDictionarySettingsViewModel.Filter.allCases) { filter in
            Text(filter.rawValue).tag(filter)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Personal dictionary filter")
        .accessibilityValue(viewModel.filter.rawValue)
        .accessibilityHint("Filters entries or shows pending suggestions")

        TextField("Preferred form", text: $preferredForm)
          .accessibilityLabel("Preferred form")
          .onSubmit(addEntry)
        TextField("Aliases", text: $aliases)
          .accessibilityLabel("Aliases")
          .accessibilityHint("Separate aliases with commas or new lines")
          .onSubmit(addEntry)

        Button("Add Entry", action: addEntry)
          .buttonStyle(.borderedProminent)
          .disabled(preferredForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityHint("Adds the preferred form and its aliases to the dictionary")

        messages
        rows
        transfer
      }
      .searchable(text: $viewModel.query, prompt: "Search personal dictionary")
      .sheet(item: $suggestionDraft) { draft in
        PersonalDictionarySuggestionEditSheet(
          draft: draft,
          onCancel: { suggestionDraft = nil },
          onSubmit: { preferredForm, aliases in
            Task { @MainActor in
              await viewModel.editAndApproveSuggestion(
                id: draft.id,
                preferredForm: preferredForm,
                aliases: aliases,
                expectedRevision: draft.expectedRevision
              )
              guard viewModel.errorMessage == nil else { return }
              suggestionDraft = nil
            }
          }
        )
      }
      .sheet(
        isPresented: Binding(
          get: { viewModel.importPreview != nil },
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
          entryRow(entry, expectedRevision: viewModel.revision)
        }
      }
    }

    private func entryRow(
      _ entry: PersonalDictionaryEntry,
      expectedRevision: UInt64
    ) -> some View {
      HStack(alignment: .firstTextBaseline) {
        Toggle(isOn: Binding(
          get: { entry.isEnabled },
          set: { enabled in
            Task { @MainActor in
              await viewModel.setEnabled(
                enabled,
                id: entry.id,
                expectedRevision: expectedRevision
              )
            }
          }
        )) {
          VStack(alignment: .leading, spacing: 2) {
            Text(entry.preferredForm)
            if !entry.aliases.isEmpty {
              Text(entry.aliases.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        .accessibilityLabel("Enable \(entry.preferredForm)")
        .accessibilityValue(entry.isEnabled ? "Enabled" : "Disabled")
        .accessibilityHint("Toggles whether this entry is used for dictation")

        Button("Delete", role: .destructive) {
          Task { @MainActor in
            await viewModel.delete(id: entry.id, expectedRevision: expectedRevision)
          }
        }
        .accessibilityLabel("Delete \(entry.preferredForm)")
        .accessibilityHint("Permanently removes this dictionary entry")
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
            suggestionDraft = PersonalDictionarySuggestionDraft(
              suggestion: suggestion,
              expectedRevision: expectedRevision
            )
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

    private func addEntry() {
      let submittedPreferredForm = preferredForm
      let submittedAliases = aliases
      Task { @MainActor in
        await viewModel.add(
          preferredForm: submittedPreferredForm,
          aliases: submittedAliases
        )
        guard viewModel.errorMessage == nil else { return }
        preferredForm = ""
        aliases = ""
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

  private struct PersonalDictionarySuggestionDraft: Identifiable {
    let id: UUID
    let expectedRevision: UInt64
    let preferredForm: String
    let aliases: String

    init(suggestion: PersonalDictionarySuggestion, expectedRevision: UInt64) {
      id = suggestion.id
      self.expectedRevision = expectedRevision
      preferredForm = suggestion.preferredForm
      aliases = suggestion.observedForms.joined(separator: ", ")
    }
  }

  private struct PersonalDictionarySuggestionEditSheet: View {
    let draft: PersonalDictionarySuggestionDraft
    let onCancel: () -> Void
    let onSubmit: (String, String) -> Void
    @State private var preferredForm: String
    @State private var aliases: String

    init(
      draft: PersonalDictionarySuggestionDraft,
      onCancel: @escaping () -> Void,
      onSubmit: @escaping (String, String) -> Void
    ) {
      self.draft = draft
      self.onCancel = onCancel
      self.onSubmit = onSubmit
      _preferredForm = State(initialValue: draft.preferredForm)
      _aliases = State(initialValue: draft.aliases)
    }

    var body: some View {
      Form {
        TextField("Preferred form", text: $preferredForm)
        TextField("Aliases", text: $aliases)
        Text("Separate aliases with commas or new lines.")
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack {
          Spacer()
          Button("Cancel", action: onCancel)
            .accessibilityLabel("Cancel suggestion edit")
          Button("Approve") { onSubmit(preferredForm, aliases) }
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
    @State private var showsOmissionConfirmation = false

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
            if viewModel.importRequiresOmissionConfirmation {
              showsOmissionConfirmation = true
            } else {
              Task { @MainActor in await viewModel.confirmCanonicalImport() }
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
        isPresented: $showsOmissionConfirmation
      ) {
        Button("Import and Omit", role: .destructive) {
          Task { @MainActor in await viewModel.confirmCanonicalImport() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
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
