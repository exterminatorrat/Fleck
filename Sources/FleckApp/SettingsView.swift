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
        "Manage personal vocabulary and dictation corrections."
      case .agents:
        "Control which local agents can work with your Fleck workspace."
      }
    }
  }

  enum DictationSettingsGroup: String, CaseIterable, Identifiable {
    case readiness = "Status"
    case models = "Models"
    case capture = "Capture"
    case experience = "Experience & history"
    case privacy = "Privacy"

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

  struct SettingsSectionSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
      List(selection: $selection) {
        sectionGroup("Fleck", sections: SettingsSection.fleckCases)
        sectionGroup("Voice & Writing", sections: SettingsSection.voiceAndWritingCases)
        sectionGroup("Connections", sections: SettingsSection.connectionCases)
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
      .accessibilityLabel("Settings sections")
      .accessibilityIdentifier("settings-section-sidebar")
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

  struct SettingsSidebarSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
      self.content = content()
    }

    var body: some View {
      content
        .padding(.horizontal, 12)
        .padding(.top, 52)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
          let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
          if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
              .overlay { shape.fill(Color.primary.opacity(0.06)) }
              .overlay { shape.stroke(Color.primary.opacity(0.12), lineWidth: 1) }
          } else if #available(macOS 26, *) {
            shape.fill(.clear)
              .glassEffect(
                Glass.regular.tint(Color.black.opacity(0.18)),
                in: shape
              )
          } else {
            shape.fill(.ultraThinMaterial)
              .overlay {
                shape.fill(Color.black.opacity(0.10))
              }
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(SettingsSidebarSurfaceProbe())
        .accessibilityIdentifier("settings-sidebar-surface")
    }
  }

  private struct SettingsSidebarSurfaceProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      view.setAccessibilityIdentifier("settings-sidebar-surface")
      return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
  }

  private struct SettingsPageHeaderProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      view.setAccessibilityIdentifier("settings-page-header")
      return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
  }

  private struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowChromeView {
      SettingsWindowChromeView()
    }

    func updateNSView(_ view: SettingsWindowChromeView, context: Context) {
      view.scheduleTrafficLightAdjustment()
    }
  }

  private final class SettingsWindowChromeView: NSView {
    private var adjustmentScheduled = false

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      scheduleTrafficLightAdjustment()
    }

    override func layout() {
      super.layout()
      scheduleTrafficLightAdjustment()
    }

    func scheduleTrafficLightAdjustment() {
      guard let window else { return }
      window.titleVisibility = .hidden
      window.titlebarSeparatorStyle = .none
      window.titlebarAppearsTransparent = true
      guard !adjustmentScheduled else { return }
      adjustmentScheduled = true
      DispatchQueue.main.async { [weak self] in
        self?.adjustmentScheduled = false
        self?.adjustTrafficLights()
      }
    }

    private func adjustTrafficLights() {
      guard let window,
        let contentView = window.contentView,
        let sidebarSurface = settingsSidebarSurface(in: contentView)
      else {
        return
      }

      let buttons = [
        window.standardWindowButton(.closeButton),
        window.standardWindowButton(.miniaturizeButton),
        window.standardWindowButton(.zoomButton),
      ].compactMap { $0 }
      guard !buttons.isEmpty else { return }

      let sidebarFrame = sidebarSurface.convert(sidebarSurface.bounds, to: nil)
      let buttonFrames = buttons.map { $0.convert($0.bounds, to: nil) }
      let targetMinX = sidebarFrame.minX + 14
      let targetMaxY = sidebarFrame.maxY - 14
      guard let currentMinX = buttonFrames.map(\.minX).min() else { return }
      guard let currentMaxY = buttonFrames.map(\.maxY).max() else { return }
      let offsetX = targetMinX - currentMinX
      let offsetY = targetMaxY - currentMaxY
      guard offsetX != 0 || offsetY != 0 else { return }

      for button in buttons {
        button.setFrameOrigin(
          NSPoint(
            x: button.frame.minX + offsetX,
            y: button.frame.minY + offsetY
          )
        )
      }
    }

    private func settingsSidebarSurface(in view: NSView) -> NSView? {
      if view.accessibilityIdentifier() == "settings-sidebar-surface" {
        return view
      }
      for subview in view.subviews {
        if let surface = settingsSidebarSurface(in: subview) {
          return surface
        }
      }
      return nil
    }
  }

  struct SettingsPageHeader: View {
    let section: SettingsSection

    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(section.title)
          .font(.title2.weight(.semibold))
          .background(SettingsPageHeaderProbe())
        Text(section.description)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  struct SettingsSectionCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
      self.title = title
      self.content = content()
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.headline)

        VStack(alignment: .leading, spacing: 12) {
          content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
          if reduceTransparency {
            shape.fill(Color(nsColor: .controlBackgroundColor))
              .overlay { shape.fill(Color.primary.opacity(0.03)) }
              .overlay { shape.stroke(Color.primary.opacity(0.10), lineWidth: 1) }
          } else if #available(macOS 26, *) {
            shape.fill(.clear)
              .glassEffect(
                Glass.regular.tint(Color.black.opacity(0.18)),
                in: shape
              )
          } else {
            shape.fill(.ultraThinMaterial)
              .overlay {
                shape.fill(Color.black.opacity(0.10))
              }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  struct SettingsPreferenceRow<Accessory: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let title: String
    private let detail: String
    private let accessory: Accessory

    init(
      _ title: String,
      detail: String,
      @ViewBuilder accessory: () -> Accessory
    ) {
      self.title = title
      self.detail = detail
      self.accessory = accessory()
    }

    var body: some View {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.body.weight(.semibold))
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        accessory
          .controlSize(.small)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if reduceTransparency {
          shape.fill(Color(nsColor: .controlBackgroundColor))
            .overlay { shape.fill(Color.primary.opacity(0.03)) }
            .overlay { shape.stroke(Color.primary.opacity(0.10), lineWidth: 1) }
        } else if #available(macOS 26, *) {
          shape.fill(.clear)
            .glassEffect(
              Glass.regular.tint(Color.black.opacity(0.18)),
              in: shape
            )
        } else {
          shape.fill(.ultraThinMaterial)
            .overlay { shape.fill(Color.black.opacity(0.10)) }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
  }

  private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
      SettingsPreferenceRow(title, detail: detail) {
        Toggle(isOn: $isOn) { EmptyView() }
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(title)
          .accessibilityHint(detail)
      }
      .accessibilityIdentifier(title)
    }
  }

  struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
      HStack(alignment: .top, spacing: 12) {
        SettingsSidebarSurface {
          SettingsSectionSidebar(selection: $selectedSection)
        }
        .frame(width: 220)
        .padding(.vertical, 8)
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            SettingsPageHeader(section: selectedSection)
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
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 24)
          .padding(.bottom, 20)
        }
        .id(selectedSection)
        .safeAreaPadding(.top, 40)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .padding(.leading, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .ignoresSafeArea(.container, edges: .top)
      .background {
        if reduceTransparency {
          Color(nsColor: .windowBackgroundColor)
            .overlay(Color.primary.opacity(0.02))
        } else {
          Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
              Color.black.opacity(0.10)
            }
        }
      }
      .background(SettingsWindowChromeConfigurator())
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
      VStack(alignment: .leading, spacing: 12) {
        Text("Interface")
          .font(.headline)
        SettingsPreferenceRow(
          "Theme",
          detail: "Choose the overall look for Fleck."
        ) {
          Picker("Theme", selection: preferenceBinding(\.theme)) {
            ForEach(AppTheme.allCases, id: \.self) { theme in
              Text(theme.rawValue.capitalized).tag(theme)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
        SettingsPreferenceRow(
          "Accent color",
          detail: "Choose the color used for selections and actions."
        ) {
          SettingsColorButton(
            title: "Accent color",
            currentHex: appState.preferences.accentHex,
            fallbackColor: .controlAccentColor
          ) { hex in
            guard let hex else { return }
            appState.updatePreferences { $0.accentHex = hex }
            runtime.preferencesDidChange()
          }
        }

        Text("Editor canvas")
          .font(.headline)
          .padding(.top, 4)
        SettingsPreferenceRow(
          "Editor text color",
          detail: "Choose the color used for note text."
        ) {
          SettingsColorButton(
            title: "Editor text color",
            currentHex: appState.preferences.editorTextHex,
            resetTitle: "Use System",
            fallbackColor: .labelColor
          ) { hex in
            appState.updatePreferences { $0.editorTextHex = hex }
          }
        }
        SettingsPreferenceRow(
          "Editor background",
          detail: "Choose the canvas color behind your notes."
        ) {
          SettingsColorButton(
            title: "Editor background",
            currentHex: appState.preferences.editorBackgroundHex,
            resetTitle: "Use System",
            fallbackColor: .textBackgroundColor
          ) { hex in
            appState.updatePreferences { $0.editorBackgroundHex = hex }
          }
        }
        SettingsPreferenceRow(
          "Glass opacity",
          detail: "Adjust how much of the window shows through Fleck surfaces."
        ) {
          Slider(value: preferenceBinding(\.panelOpacity), in: 0.55...1) {
            Text("Glass opacity")
          }
          .labelsHidden()
          .frame(width: 150)
        }

        Text("Menu size")
          .font(.headline)
          .padding(.top, 4)
        SettingsPreferenceRow(
          "Width",
          detail: "Set the width of the menu bar notes panel."
        ) {
          Stepper(
            value: preferenceBinding(\.panelWidth), in: 380...800, step: 20
          ) {
            Text("\(Int(appState.preferences.panelWidth)) pt")
          }
        }
        SettingsPreferenceRow(
          "Height",
          detail: "Set the height of the menu bar notes panel."
        ) {
          Stepper(
            value: preferenceBinding(\.panelHeight), in: 300...800, step: 20
          ) {
            Text("\(Int(appState.preferences.panelHeight)) pt")
          }
        }
      }
    }

    private var editing: some View {
      VStack(alignment: .leading, spacing: 12) {
        SettingsToggleRow(
          title: "Create lists automatically",
          detail: "Recognize list-shaped lines while you edit.",
          isOn: preferenceBinding(\.automaticLists)
        )
        SettingsToggleRow(
          title: "Confirm before moving notes to Trash",
          detail: "Ask before a note is moved to the Trash folder.",
          isOn: preferenceBinding(\.confirmBeforeMovingNotesToTrash)
        )
        SettingsToggleRow(
          title: "Launch at login",
          detail: "Start Fleck automatically when you sign in.",
          isOn: Binding(
            get: { appState.preferences.launchAtLogin },
            set: { appState.setLaunchAtLogin($0) }
          ))
      }
    }

    private var shortcuts: some View {
      VStack(alignment: .leading, spacing: 12) {
        let conflicts = Shortcut.conflicts(in: appState.preferences.shortcuts)
        ForEach(Shortcut.Action.allCases, id: \.self) { action in
          let shortcut = appState.preferences.shortcuts.first(where: { $0.action == action })
          SettingsPreferenceRow(
            action.title,
            detail: shortcutDescription(for: action)
          ) {
            VStack(alignment: .trailing, spacing: 4) {
              HStack(spacing: 8) {
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
                .multilineTextAlignment(.trailing)
              }
              if conflicts.contains(action) {
                Label("Conflicts with another shortcut", systemImage: "exclamationmark.triangle.fill")
                  .font(.caption)
                  .foregroundStyle(.orange)
              }
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

    private var dictation: some View {
      VStack(alignment: .leading, spacing: 12) {
        readiness
        models
        capture
        experienceAndHistory
        DisclosureGroup(DictationSettingsGroup.privacy.rawValue) {
          Text(
            "Audio stays in memory only and is discarded when capture finishes, is cancelled, is interrupted, or fails. History is local, contains no audio, and expires after 30 days. Turning history off affects future successful captures only."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
        }
      }
    }

    private var readiness: some View {
      let isReady = availabilityIssues.isEmpty && recoveryActions.isEmpty
      return SettingsPreferenceRow(
        DictationSettingsGroup.readiness.rawValue,
        detail: isReady
          ? "Dictation is ready to capture and process your voice locally."
          : "Review the items below before starting a capture."
      ) {
        VStack(alignment: .trailing, spacing: 5) {
          Label(
            isReady ? "Ready" : "Needs attention",
            systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .font(.body.weight(.medium))
          if !isReady {
            ForEach(availabilityIssues, id: \.title) { row in
              Text("\(row.title) — \(row.detail)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }
            ForEach(recoveryActions, id: \.pane) { action in
              Button(action.title) {
                NSWorkspace.shared.open(action.url)
              }
            }
          }
        }
      }
    }

    private var capture: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(DictationSettingsGroup.capture.rawValue)
          .font(.headline)
        SettingsPreferenceRow(
          "Modifier key",
          detail: dictationModifierPresentation.statusCopy
        ) {
          VStack(alignment: .trailing, spacing: 4) {
            Picker("Modifier key", selection: dictationModifierBinding) {
              ForEach(DictationModifierKey.allCases, id: \.self) { key in
                Text(
                  key == .rightOption
                    ? "\(key.displayName) — Recommended"
                    : key.displayName
                ).tag(key)
              }
            }
            .labelsHidden()
            .disabled(!dictationModifierPresentation.isPickerEnabled)
            if let guidance = dictationModifierPresentation.guidanceCopy {
              Text(guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
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
          }
        }
        SettingsPreferenceRow(
          "Microphone",
          detail: "Choose which microphone Fleck uses for dictation."
        ) {
          Picker("Microphone", selection: dictationMicrophoneBinding) {
            Text("Automatic").tag(String?.none)
            ForEach(microphones) { microphone in
              Text(microphone.name).tag(Optional(microphone.id))
            }
          }
          .labelsHidden()
        }
        SettingsPreferenceRow(
          "Recognition language",
          detail: "Choose the language used to recognize your dictation."
        ) {
          Text("English")
            .foregroundStyle(.secondary)
        }
      }
    }

    private var experienceAndHistory: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text(DictationSettingsGroup.experience.rawValue)
          .font(.headline)
        SettingsToggleRow(
          title: "Show status capsule",
          detail: "Show a compact status surface while Fleck is listening.",
          isOn: dictationPreferenceBinding(\.dictationCapsuleEnabled)
        )
        SettingsToggleRow(
          title: "Keep local history for 30 days",
          detail: "Keep successful transcripts on this Mac for up to 30 days.",
          isOn: dictationPreferenceBinding(\.dictationHistoryEnabled)
        )
        SettingsPreferenceRow(
          "Clear History",
          detail: "Remove all local transcript records from this Mac."
        ) {
          Button("Clear History", role: .destructive) {
            showsHistoryClearConfirmation = true
          }
        }
      }
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
      VStack(alignment: .leading, spacing: 12) {
        Text(DictationSettingsGroup.models.rawValue)
          .font(.headline)
        SettingsPreferenceRow(
          "Dictation model",
          detail: "Use the local model that turns your voice into text."
        ) {
          modelRow(
            presentation: admittedModelSettingsViewModel.presentation,
            viewModel: admittedModelSettingsViewModel,
            progressAccessibilityLabel: "Enhanced local dictation installation progress"
          )
        }
        SettingsPreferenceRow(
          "Cleanup model",
          detail: "Use the local model that polishes captured text."
        ) {
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

    private func shortcutDescription(for action: Shortcut.Action) -> String {
      switch action {
      case .togglePanel:
        "Set the keyboard shortcut for showing or hiding notes."
      case .newNote:
        "Set the keyboard shortcut for creating a new note."
      case .closeNote:
        "Set the keyboard shortcut for closing the current note."
      case .nextNote:
        "Set the keyboard shortcut for moving to the next note."
      case .previousNote:
        "Set the keyboard shortcut for moving to the previous note."
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

  enum SettingsVocabularySortOrder: String, CaseIterable, Identifiable {
    case aToZ = "A–Z"
    case zToA = "Z–A"

    var id: Self { self }

    func sorted<Element>(
      _ values: [Element],
      by key: (Element) -> String,
      id: (Element) -> UUID
    ) -> [Element] {
      values.sorted { lhs, rhs in
        let lhsKey = key(lhs).folding(
          options: [.caseInsensitive, .diacriticInsensitive],
          locale: Locale(identifier: "en_US_POSIX")
        )
        let rhsKey = key(rhs).folding(
          options: [.caseInsensitive, .diacriticInsensitive],
          locale: Locale(identifier: "en_US_POSIX")
        )
        if lhsKey != rhsKey {
          return self == .aToZ ? lhsKey < rhsKey : lhsKey > rhsKey
        }
        if key(lhs) != key(rhs) {
          return self == .aToZ ? key(lhs) < key(rhs) : key(lhs) > key(rhs)
        }
        let lhsID = id(lhs).uuidString
        let rhsID = id(rhs).uuidString
        return self == .aToZ ? lhsID < rhsID : lhsID > rhsID
      }
    }
  }

  private struct PersonalDictionarySettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var viewModel: PersonalDictionarySettingsViewModel
    @State private var showsImporter = false
    @State private var showsDictionaryExporter = false
    @State private var showsCSVExporter = false
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchExpanded = false
    @State private var sortOrder = SettingsVocabularySortOrder.aToZ
    @State private var isReloading = false

    private let maximumTransferBytes = 64 * 1024 + 256

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Teach Fleck the words and phrases that matter to you")
              .font(.body.weight(.medium))
            Text("Add a correction when Fleck consistently hears something else.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 8)
          Button("Add New") { viewModel.beginAddingEntry() }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Add a new vocabulary word or phrase")
            .accessibilityHint("Opens the vocabulary word editor")
        }

        dictionaryPanel
        transfer
      }
      .frame(maxWidth: .infinity, alignment: .leading)
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

    private var toolbar: some View {
      HStack(spacing: 8) {
        filterTabs
        Spacer(minLength: 8)
        ZStack(alignment: .trailing) {
          toolbarTrailingContent
            .opacity(isSearchExpanded ? 0 : 1)
            .accessibilityHidden(isSearchExpanded)
            .allowsHitTesting(!isSearchExpanded)
          if isSearchExpanded {
            searchSurface
              .transition(.opacity)
          }
        }
        .frame(width: 236, height: 30, alignment: .trailing)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 30)
      .onExitCommand {
        guard isSearchExpanded else { return }
        closeSearch(source: .keyboard)
      }
    }

    private var toolbarTrailingContent: some View {
      HStack(spacing: 8) {
        summaryLabel
        searchTrigger
        sortControl
        reloadControl
      }
    }

    private var summaryLabel: some View {
      Text(entrySummary)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var filterTabs: some View {
      HStack(spacing: 2) {
        ForEach(PersonalDictionarySettingsViewModel.Filter.allCases) { filter in
          Button(filter.rawValue) {
            viewModel.filter = filter
          }
          .buttonStyle(.plain)
          .font(.caption.weight(filter == viewModel.filter ? .semibold : .regular))
          .foregroundStyle(filter == viewModel.filter ? .primary : .secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 5)
          .overlay(alignment: .bottom) {
            if filter == viewModel.filter {
              Capsule()
                .fill(Color.accentColor)
                .frame(height: 2)
            }
          }
          .accessibilityLabel(filter.rawValue)
          .accessibilityValue(filter == viewModel.filter ? "Selected" : "Available")
          .accessibilityHint("Shows \(filter.rawValue.lowercased()) vocabulary")
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Personal dictionary filter")
      .accessibilityValue(viewModel.filter.rawValue)
      .accessibilityHint("Filters entries or shows pending suggestions")
    }

    private var sortControl: some View {
      Picker("Sort", selection: $sortOrder) {
        ForEach(SettingsVocabularySortOrder.allCases) { order in
          Text(order.rawValue).tag(order)
        }
      }
      .pickerStyle(.menu)
      .accessibilityLabel("Sort vocabulary")
      .accessibilityValue(sortOrder.rawValue)
      .accessibilityHint("Sorts vocabulary alphabetically")
    }

    private var reloadControl: some View {
      Button(action: reloadVocabulary) {
        if isReloading {
          ProgressView()
            .controlSize(.small)
        } else {
          Label("Reload", systemImage: "arrow.clockwise")
        }
      }
      .buttonStyle(.borderless)
      .disabled(isReloading)
      .accessibilityLabel("Reload vocabulary")
      .accessibilityValue(isReloading ? "Reloading" : "Ready")
      .accessibilityHint("Loads the latest local vocabulary entries")
    }

    private var entrySummary: String {
      if viewModel.filter == .suggestions {
        let count = viewModel.visibleSuggestions.count
        return count == 1 ? "1 pending suggestion" : "\(count) pending suggestions"
      }
      let count = viewModel.visibleEntries.count
      let total = viewModel.entries.count
      if viewModel.query.isEmpty, viewModel.filter == .all {
        return total == 1 ? "1 saved word" : "\(total) saved words"
      }
      return "\(count) of \(total) saved words"
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
    private var dictionaryPanel: some View {
      VStack(alignment: .leading, spacing: 0) {
        toolbar
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 10)
        messages
          .padding(.horizontal, 12)
          .padding(.bottom, 8)
        Divider()
        listSurface
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if reduceTransparency {
          shape.fill(Color(nsColor: .controlBackgroundColor))
            .overlay { shape.fill(Color.primary.opacity(0.03)) }
            .overlay { shape.stroke(Color.primary.opacity(0.10), lineWidth: 1) }
        } else if #available(macOS 26, *) {
          shape.fill(.clear)
            .glassEffect(
              Glass.regular.tint(Color.black.opacity(0.18)),
              in: shape
            )
        } else {
          shape.fill(.ultraThinMaterial)
            .overlay {
              shape.fill(Color.black.opacity(0.10))
            }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(.separator.opacity(0.5), lineWidth: 1)
      }
    }

    @ViewBuilder
    private var listSurface: some View {
      VStack(alignment: .leading, spacing: 0) {
        if viewModel.filter == .suggestions {
          if sortedSuggestions.isEmpty {
            emptyState
          } else {
            ForEach(Array(sortedSuggestions.enumerated()), id: \.element.id) { index, suggestion in
              suggestionRow(suggestion, expectedRevision: viewModel.revision)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
              if index < sortedSuggestions.count - 1 {
                Divider().padding(.leading, 12)
              }
            }
          }
        } else if sortedEntries.isEmpty {
          emptyState
        } else {
          ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
            entryRow(entry)
              .padding(.horizontal, 12)
              .padding(.vertical, 10)
            if index < sortedEntries.count - 1 {
              Divider().padding(.leading, 12)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
      .padding(.bottom, 12)
    }

    private var sortedEntries: [PersonalDictionaryEntry] {
      sortOrder.sorted(viewModel.visibleEntries, by: \.preferredForm, id: \.id)
    }

    private var sortedSuggestions: [PersonalDictionarySuggestion] {
      sortOrder.sorted(viewModel.visibleSuggestions, by: \.preferredForm, id: \.id)
    }

    @ViewBuilder
    private var emptyState: some View {
      Group {
        if viewModel.filter == .suggestions {
          Text("No pending suggestions. Fleck will show new forms here when it finds them.")
            .foregroundStyle(.secondary)
        } else if !viewModel.query.isEmpty {
          Text("No matching entries. Clear search or choose another filter.")
            .foregroundStyle(.secondary)
        } else if viewModel.filter != .all {
          Text("No entries match this filter. Choose All or use Add New.")
            .foregroundStyle(.secondary)
        } else {
          Text("No entries yet. Use Add New to teach Fleck a word or phrase.")
            .foregroundStyle(.secondary)
        }
      }
      .font(.callout)
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
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
        .toggleStyle(.switch)
        .controlSize(.small)
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

    private var searchTrigger: some View {
      Button {
        openSearch(source: .pointer)
      } label: {
        Image(systemName: "magnifyingglass")
      }
      .buttonStyle(.plain)
      .keyboardShortcut("f", modifiers: .command)
      .help("Search vocabulary (⌘F)")
      .accessibilityLabel("Search vocabulary")
      .accessibilityHint("Focuses the vocabulary search field")
    }

    private var searchSurface: some View {
      HStack(spacing: 7) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        TextField("Search vocabulary", text: $viewModel.query)
          .textFieldStyle(.plain)
          .focused($isSearchFocused)
          .accessibilityLabel("Search vocabulary")
          .accessibilityValue(viewModel.query.isEmpty ? "No search" : viewModel.query)
          .accessibilityHint("Searches saved words and corrections")
        Button {
          closeSearch(source: .pointer)
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .help("Close search (Esc)")
        .accessibilityLabel("Clear vocabulary search")
        .accessibilityHint("Clears search and closes vocabulary search")
      }
      .padding(.horizontal, 10)
      .frame(width: 236, height: 30)
      .background {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if reduceTransparency {
          shape.fill(Color(nsColor: .controlBackgroundColor))
            .overlay { shape.fill(Color.primary.opacity(0.03)) }
            .overlay { shape.stroke(Color.primary.opacity(0.10), lineWidth: 1) }
        } else if #available(macOS 26, *) {
          shape.fill(.clear)
            .glassEffect(
              Glass.regular.tint(Color.black.opacity(0.18)),
              in: shape
            )
        } else {
          shape.fill(.ultraThinMaterial)
            .overlay { shape.fill(Color.black.opacity(0.10)) }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(.separator.opacity(0.5), lineWidth: 1)
      }
    }

    private func openSearch(source: AppInteractionSource) {
      withAnimation(motion.presentationAnimation(for: source)) {
        isSearchExpanded = true
        isSearchFocused = true
      }
    }

    private func closeSearch(source: AppInteractionSource) {
      withAnimation(motion.presentationAnimation(for: source)) {
        isSearchExpanded = false
        isSearchFocused = false
      }
      clearSearchQueryAfterTeardown()
    }

    private func clearSearchQueryAfterTeardown() {
      let viewModel = viewModel
      Task { @MainActor in
        await Task.yield()
        viewModel.query = ""
      }
    }

    private func reloadVocabulary() {
      guard !isReloading else { return }
      isReloading = true
      Task { @MainActor in
        await viewModel.load()
        isReloading = false
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
        Section(isNew ? "Add New" : "Edit Word") {
          TextField("Word or phrase", text: $preferredForm)
            .accessibilityLabel("Word or phrase")
            .accessibilityHint("The spelling Fleck should use")

          Toggle("Correct a misspelling", isOn: $usesCorrection)
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityHint("Shows a field for the spelling Fleck should replace")
          if usesCorrection {
            TextField("Correct from", text: $aliases)
              .accessibilityLabel("Correct from")
              .accessibilityHint("The spelling or phrase Fleck should replace")
            Text("For multiple corrections, separate each one with a comma or new line.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Toggle("Use this word in dictation", isOn: $isEnabled)
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityHint("Keeps this vocabulary entry active for dictation")
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
            Button(isNew ? "Add" : "Save", action: onSave)
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
              .accessibilityLabel(isNew ? "Add vocabulary word" : "Save vocabulary word")
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
