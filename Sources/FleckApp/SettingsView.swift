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
    case about = "About"

    static let fleckCases: [SettingsSection] = [.editing, .appearance, .shortcuts]
    static let voiceAndWritingCases: [SettingsSection] = [.dictation, .vocabulary]
    static let connectionCases: [SettingsSection] = [.agents]
    static let informationCases: [SettingsSection] = [.about]
    static let allCases: [SettingsSection] =
      fleckCases + voiceAndWritingCases + connectionCases + informationCases

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
        "gearshape"
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
      case .about:
        "info.circle"
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
      case .about:
        "View Fleck’s product version, build identity, source, and candidate status."
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
        Section {
          sectionRows(SettingsSection.fleckCases)
        } header: {
          Text("Fleck")
            .padding(.bottom, 4)
            .background(SettingsSearchProbe(identifier: "settings-fleck-sidebar-heading"))
        }
        sectionGroup("Voice & Writing", sections: SettingsSection.voiceAndWritingCases)
        sectionGroup("Connections", sections: SettingsSection.connectionCases)
        sectionGroup("Information", sections: SettingsSection.informationCases)
      }
      .listStyle(.sidebar)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
      .accessibilityLabel("Settings sections")
      .accessibilityIdentifier("settings-section-sidebar")
    }

    private func sectionRows(_ sections: [SettingsSection]) -> some View {
      ForEach(sections) { section in
        Label(section.title, systemImage: section.systemImage)
          .tag(section)
      }
    }

    @ViewBuilder
    private func sectionGroup(
      _ title: LocalizedStringKey,
      sections: [SettingsSection]
    ) -> some View {
      Section {
        sectionRows(sections)
      } header: {
        Text(title)
          .padding(.bottom, 4)
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
        .padding(.top, 44)
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

  private struct SettingsTypographyProbe: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      view.setAccessibilityElement(false)
      view.setAccessibilityIdentifier(identifier)
      return view
    }

    func updateNSView(_ view: NSView, context: Context) {
      view.setAccessibilityIdentifier(identifier)
    }
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
    private var observedButtons: [NSButton] = []

    deinit {
      NotificationCenter.default.removeObserver(self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if newWindow !== window {
        stopObservingTrafficLights()
      }
      super.viewWillMove(toWindow: newWindow)
    }

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
      window.level = .normal
      if !window.styleMask.contains(.miniaturizable) {
        window.styleMask.insert(.miniaturizable)
      }
      var collectionBehavior = window.collectionBehavior
      collectionBehavior.remove(.fullScreenPrimary)
      collectionBehavior.remove(.fullScreenAuxiliary)
      collectionBehavior.insert(.fullScreenNone)
      if collectionBehavior != window.collectionBehavior {
        window.collectionBehavior = collectionBehavior
      }
      if let minimizeButton = window.standardWindowButton(.miniaturizeButton) {
        minimizeButton.isHidden = false
        minimizeButton.isEnabled = true
      }
      window.standardWindowButton(.zoomButton)?.isHidden = true
      guard !adjustmentScheduled else { return }
      adjustmentScheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        adjustmentScheduled = false
        guard let window = self.window else { return }
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        adjustTrafficLights()
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
      ].compactMap { $0 }
      guard !buttons.isEmpty else { return }
      observeTrafficLights(buttons)

      let sidebarFrame = sidebarSurface.convert(sidebarSurface.bounds, to: nil)
      let buttonFrames = buttons.map { $0.convert($0.bounds, to: nil) }
      let targetMinX = sidebarFrame.minX + 14
      let targetMaxY = sidebarFrame.maxY - 14
      guard let currentMinX = buttonFrames.map(\.minX).min() else { return }
      guard let currentMaxY = buttonFrames.map(\.maxY).max() else { return }
      let offsetX = targetMinX - currentMinX
      let offsetY = targetMaxY - currentMaxY
      guard offsetX != 0 || offsetY != 0 else { return }

      for (button, buttonFrame) in zip(buttons, buttonFrames) {
        guard let superview = button.superview else { continue }
        let targetFrame = superview.convert(
          buttonFrame.offsetBy(dx: offsetX, dy: offsetY),
          from: nil
        )
        button.setFrameOrigin(
          targetFrame.origin
        )
      }
    }

    private func observeTrafficLights(_ buttons: [NSButton]) {
      let alreadyObserving = observedButtons.count == buttons.count
        && zip(observedButtons, buttons).allSatisfy { $0.0 === $0.1 }
      guard !alreadyObserving else { return }
      stopObservingTrafficLights()
      observedButtons = buttons
      for button in buttons {
        button.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(trafficLightFrameDidChange),
          name: NSView.frameDidChangeNotification,
          object: button
        )
      }
    }

    private func stopObservingTrafficLights() {
      NotificationCenter.default.removeObserver(
        self,
        name: NSView.frameDidChangeNotification,
        object: nil
      )
      observedButtons = []
    }

    @objc private func trafficLightFrameDidChange() {
      scheduleTrafficLightAdjustment()
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
    @ScaledMetric(relativeTo: .title2) private var generalTitleSize = 20
    let section: SettingsSection
    let searchRequest: SettingsSearchRequest?

    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(section.title)
          .font(
            section == .editing
              ? .system(size: generalTitleSize, weight: .semibold)
              : .title2.weight(.semibold)
          )
          .background(SettingsPageHeaderProbe())
        if section != .editing {
          Text(section.description)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .settingsSearchAnchor(.section(section), request: searchRequest)
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

  private enum SettingsToggleRowStyle {
    case standard
    case general
  }

  private struct SettingsToggleRow: View {
    @ScaledMetric(relativeTo: .body) private var generalTitleSize = 13
    @ScaledMetric(relativeTo: .callout) private var generalDetailSize = 12
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var style = SettingsToggleRowStyle.standard
    var tint: Color? = nil

    @ViewBuilder
    var body: some View {
      Group {
        if style == .general {
          content
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: 64, alignment: .leading)
        } else {
          SettingsPreferenceRow(title, detail: detail) {
            settingsToggle
          }
        }
      }
    }

    private var content: some View {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: generalTitleSize, weight: .regular))
            .background(
              SettingsTypographyProbe(identifier: "settings-general-title-\(title)")
            )
          Text(detail)
            .font(.system(size: generalDetailSize, weight: .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .background(
              SettingsTypographyProbe(identifier: "settings-general-detail-\(title)")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        settingsToggle
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var settingsToggle: some View {
      if let tint {
        baseToggle.tint(tint)
      } else {
        baseToggle
      }
    }

    private var baseToggle: some View {
      Toggle(isOn: $isOn) { EmptyView() }
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityIdentifier(title)
    }
  }

  private struct GeneralSettingsGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .callout) private var titleSize = 12
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
      self.title = title
      self.content = content()
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.system(size: titleSize, weight: .medium))
          .background(
            SettingsTypographyProbe(identifier: "settings-general-section-\(title)")
          )
        VStack(alignment: .leading, spacing: 0) {
          content
        }
        .background {
          let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
          shape.fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
              shape.fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.025))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  enum MenuPanelSettingsSizePolicy {
    static func range(
      minimum: Double,
      storedValue: Double,
      usableDisplayDimensions: [CGFloat]
    ) -> ClosedRange<Double> {
      let displayMaximum = usableDisplayDimensions
        .filter { $0.isFinite && $0 > 0 }
        .map(Double.init)
        .max() ?? minimum
      let storedMaximum = storedValue.isFinite ? storedValue : minimum
      return minimum...max(minimum, max(storedMaximum, displayMaximum))
    }

    static func label(for value: Double) -> String {
      let number = value < 1_000_000
        ? value.formatted(.number.precision(.fractionLength(0...2)))
        : value.formatted(.number.notation(.scientific).precision(.significantDigits(4)))
      return "\(number) pt"
    }
  }

  struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ObservedObject var runtime: DictationRuntime
    @ObservedObject private var admittedModelSettingsViewModel: AdmittedModelSettingsViewModel
    @ObservedObject private var cleanupAdmittedModelSettingsViewModel: AdmittedModelSettingsViewModel
    @ObservedObject private var personalDictionarySettingsViewModel:
      PersonalDictionarySettingsViewModel
    @ObservedObject private var historyController: DictationHistoryController
    private let buildIdentity: BuildIdentity
    @State private var selectedSection = SettingsSection.editing
    @State private var showsHistoryClearConfirmation = false
    @State private var recoveryActions: [DictationSystemSettingsAction] = []
    @State private var microphones: [DictationMicrophoneOption] = []
    @State private var recordingSelection = SettingsShortcutRecordingState()
    @State private var isSettingsSearchFieldFocused = false
    @State private var searchQuery = ""
    @State private var searchFocusRequest: UUID?
    @State private var highlightedSearchTarget: SettingsSearchTarget?
    @State private var searchRequest: SettingsSearchRequest?
    @State private var vocabularyPageScrollRequestID: UUID?
    @State private var isDictationPrivacyExpanded = false

    init(runtime: DictationRuntime, buildIdentity: BuildIdentity = .current()) {
      self.runtime = runtime
      self.buildIdentity = buildIdentity
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
          VStack(alignment: .leading, spacing: 4) {
            SettingsSearchField(
              query: $searchQuery,
              focusRequest: searchFocusRequest,
              onMove: moveSearchHighlight,
              onSubmit: submitHighlightedSearchResult,
              onBeginEditing: { recordingSelection.cancel() },
              onFocusChange: { isSettingsSearchFieldFocused = $0 }
            )
            .frame(height: 28)
            .overlay {
              if isSettingsSearchFieldFocused {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                  .strokeBorder(Color.primary.opacity(0.72), lineWidth: 1.5)
                  .padding(1)
                  .allowsHitTesting(false)
                  .accessibilityHidden(true)
              }
            }
            if isSearching {
              SettingsSearchResultsView(
                results: searchResults,
                highlightedTarget: highlightedSearchTarget,
                accentPresentation: accentPresentation,
                onHighlight: { highlightedSearchTarget = $0 },
                onActivate: activateSearchResult,
                onCancel: cancelSettingsSearch
              )
            } else {
              SettingsSectionSidebar(selection: sectionSelection)
            }
          }
        }
        .frame(width: 220)
        .padding(.vertical, 8)
        ZStack(alignment: .topLeading) {
          ScrollViewReader { proxy in
            ScrollView {
              VStack(alignment: .leading, spacing: 20) {
                if selectedSection != .vocabulary {
                  SettingsPageHeader(section: selectedSection, searchRequest: searchRequest)
                }
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
                case .about:
                  AboutSettingsView(identity: buildIdentity)
                }
              }
              .environment(\.settingsSearchRequest, searchRequest)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 24)
              .padding(.bottom, 20)
            }
            .id(selectedSection)
            .safeAreaPadding(.top, 40)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: searchRequest?.id) { _, _ in
              vocabularyPageScrollRequestID = nil
              guard let searchRequest else { return }
              Task { @MainActor in
                await Task.yield()
                await Task.yield()
                guard self.searchRequest?.id == searchRequest.id else { return }
                let pageScrollAnchor = searchRequest.anchor.pageScrollAnchor
                let isTransferFooter = pageScrollAnchor == .vocabularyTransferFooter
                proxy.scrollTo(pageScrollAnchor, anchor: isTransferFooter ? .bottom : .center)
                if searchRequest.anchor.usesVocabularyFocusLifecycle {
                  await Task.yield()
                  guard self.searchRequest?.id == searchRequest.id else { return }
                  vocabularyPageScrollRequestID = searchRequest.id
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
      .tint(accentPresentation.color)
      .onChange(of: selectedSection) { _, newSection in
        recordingSelection.transition(to: newSection)
      }
      .onChange(of: searchQuery) { _, _ in
        recordingSelection.cancel()
        highlightedSearchTarget = searchResults.first?.target
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
      recordingSelection.cancel()
      searchQuery = ""
      highlightedSearchTarget = nil
      searchRequest = nil
      vocabularyPageScrollRequestID = nil
      selectedSection = section
    }

    private var isSearching: Bool {
      !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var accentPresentation: SettingsAccentPresentation {
      SettingsAccentPresentation(
        hex: appState.preferences.accentHex,
        colorScheme: colorScheme,
        increasedContrast: colorSchemeContrast == .increased
      )
    }

    private func cancelSettingsSearch() {
      searchQuery = ""
      highlightedSearchTarget = nil
      searchFocusRequest = UUID()
    }

    private var searchResults: [SettingsSearchResult] {
      SettingsSearchIndex.results(for: searchQuery)
    }

    private var sectionSelection: Binding<SettingsSection> {
      Binding(
        get: { selectedSection },
        set: { section in
          if selectedSection == section,
            let target = searchRequest?.target,
            SettingsSearchIndex.catalog.first(where: { $0.target == target })?.destination
              == section
          {
            return
          }
          recordingSelection.cancel()
          searchRequest = nil
          vocabularyPageScrollRequestID = nil
          selectedSection = section
        }
      )
    }

    private func moveSearchHighlight(_ move: SettingsSearchMove) {
      highlightedSearchTarget = SettingsSearchIndex.movingHighlight(
        move,
        from: highlightedSearchTarget,
        in: searchResults
      )
    }

    private func submitHighlightedSearchResult() {
      guard let highlightedSearchTarget,
        let result = searchResults.first(where: { $0.target == highlightedSearchTarget })
      else { return }
      activateSearchResult(result)
    }

    private func activateSearchResult(_ result: SettingsSearchResult) {
      recordingSelection.cancel()
      selectedSection = result.destination
      searchQuery = ""
      highlightedSearchTarget = nil
      let anchor = result.anchor.revealAnchor(isPackaged: buildIdentity.isPackaged)
      if anchor == .dictationPrivacy {
        isDictationPrivacyExpanded = true
      }
      vocabularyPageScrollRequestID = nil
      searchRequest = SettingsSearchRequest(target: result.target, anchor: anchor)
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
        .settingsSearchAnchor(.appearanceTheme, request: searchRequest)
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
        .settingsSearchAnchor(.appearanceAccent, request: searchRequest)

        Text("Editor canvas")
          .font(.headline)
          .padding(.top, 12)
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
        .settingsSearchAnchor(.appearanceEditorText, request: searchRequest)
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
        .settingsSearchAnchor(.appearanceEditorBackground, request: searchRequest)
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
        .settingsSearchAnchor(.appearanceGlassOpacity, request: searchRequest)

        Text("Menu size")
          .font(.headline)
          .padding(.top, 12)
        SettingsPreferenceRow(
          "Width",
          detail: "Set the width of the menu bar notes panel."
        ) {
          Stepper(
            value: preferenceBinding(\.panelWidth), in: menuPanelWidthRange, step: 20
          ) {
            Text(MenuPanelSettingsSizePolicy.label(for: appState.preferences.panelWidth))
          }
        }
        .settingsSearchAnchor(.appearanceWidth, request: searchRequest)
        SettingsPreferenceRow(
          "Height",
          detail: "Set the height of the menu bar notes panel."
        ) {
          Stepper(
            value: preferenceBinding(\.panelHeight), in: menuPanelHeightRange, step: 20
          ) {
            Text(MenuPanelSettingsSizePolicy.label(for: appState.preferences.panelHeight))
          }
        }
        .settingsSearchAnchor(.appearanceHeight, request: searchRequest)
      }
    }

    private var menuPanelWidthRange: ClosedRange<Double> {
      MenuPanelSettingsSizePolicy.range(
        minimum: 380,
        storedValue: appState.preferences.panelWidth,
        usableDisplayDimensions: NSScreen.screens.map { $0.visibleFrame.width }
      )
    }

    private var menuPanelHeightRange: ClosedRange<Double> {
      MenuPanelSettingsSizePolicy.range(
        minimum: 300,
        storedValue: appState.preferences.panelHeight,
        usableDisplayDimensions: NSScreen.screens.map { $0.visibleFrame.height }
      )
    }

    private var editing: some View {
      let launchAtLogin = Group {
        SettingsToggleRow(
          title: "Launch at login",
          detail: "Start Fleck automatically when you sign in.",
          isOn: Binding(
            get: { appState.preferences.launchAtLogin },
            set: { appState.setLaunchAtLogin($0) }
          ),
          style: .general,
          tint: accentPresentation.color
        )
      }
      .settingsSearchAnchor(.generalLaunchAtLogin, request: searchRequest)
      let automaticLists = Group {
        SettingsToggleRow(
          title: "Create lists automatically",
          detail: "Recognize list-shaped lines while you edit.",
          isOn: preferenceBinding(\.automaticLists),
          style: .general,
          tint: accentPresentation.color
        )
      }
      .settingsSearchAnchor(.generalAutomaticLists, request: searchRequest)
      let trashConfirmation = Group {
        SettingsToggleRow(
          title: "Confirm before moving notes to Trash",
          detail: "Ask before a note is moved to the Trash folder.",
          isOn: preferenceBinding(\.confirmBeforeMovingNotesToTrash),
          style: .general,
          tint: accentPresentation.color
        )
      }
      .settingsSearchAnchor(.generalConfirmTrash, request: searchRequest)

      return VStack(alignment: .leading, spacing: 12) {
        GeneralSettingsGroup("Startup") {
          launchAtLogin
        }
        Divider()
        GeneralSettingsGroup("Editing") {
          automaticLists
          Divider()
            .padding(.leading, 14)
          trashConfirmation
        }
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
          .settingsSearchAnchor(.shortcut(action), request: searchRequest)
        }
        Text(
          "Click a shortcut, then press the key combination. Conflicts are highlighted. Restore brings back the default shortcut."
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
        DisclosureGroup(isExpanded: $isDictationPrivacyExpanded) {
          Text(
            "Audio stays in memory only and is discarded when capture finishes, is cancelled, is interrupted, or fails. History is local, contains no audio, and expires after 30 days. Turning history off affects future successful captures only."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
          .accessibilityIdentifier("settings-dictation-privacy-content")
          .background(SettingsSearchProbe(identifier: "settings-dictation-privacy-content"))
        } label: {
          Text(DictationSettingsGroup.privacy.rawValue)
        }
        .disclosureGroupStyle(SettingsDisclosureGroupStyle())
        .settingsSearchAnchor(.dictationPrivacy, request: searchRequest)
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
      .settingsSearchAnchor(.dictationStatus, request: searchRequest)
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
        .settingsSearchAnchor(.dictationModifier, request: searchRequest)
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
        .settingsSearchAnchor(.dictationMicrophone, request: searchRequest)
        SettingsPreferenceRow(
          "Recognition language",
          detail: "Choose the language used to recognize your dictation."
        ) {
          Text("English")
            .foregroundStyle(.secondary)
        }
        .settingsSearchAnchor(.dictationRecognitionLanguage, request: searchRequest)
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
        .settingsSearchAnchor(.dictationStatusCapsule, request: searchRequest)
        SettingsToggleRow(
          title: "Show shortcut guide in editor",
          detail: "Show shortcut and Smart Capture guidance above the editor when dictation is ready.",
          isOn: preferenceBinding(\.showDictationShortcutGuide)
        )
        .settingsSearchAnchor(.dictationShortcutGuide, request: searchRequest)
        SettingsToggleRow(
          title: "Keep local history for 30 days",
          detail: "Keep successful transcripts on this Mac for up to 30 days.",
          isOn: dictationPreferenceBinding(\.dictationHistoryEnabled)
        )
        .settingsSearchAnchor(.dictationLocalHistory, request: searchRequest)
        SettingsPreferenceRow(
          "Clear History",
          detail: "Remove all local transcript records from this Mac."
        ) {
          Button("Clear History", role: .destructive) {
            showsHistoryClearConfirmation = true
          }
        }
        .settingsSearchAnchor(.dictationClearHistory, request: searchRequest)
      }
    }

    private var vocabulary: some View {
      PersonalDictionarySettingsSection(
        viewModel: personalDictionarySettingsViewModel,
        searchRequest: $searchRequest,
        pageScrollReadyRequestID: vocabularyPageScrollRequestID,
        selectedSection: $selectedSection
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
        .settingsSearchAnchor(.dictationModel, request: searchRequest)
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
        .settingsSearchAnchor(.dictationCleanupModel, request: searchRequest)
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
      id: (Element) -> UUID,
      priority: ((Element) -> Bool)? = nil
    ) -> [Element] {
      values.sorted { lhs, rhs in
        if let priority, priority(lhs) != priority(rhs) {
          return priority(lhs)
        }
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
          return key(lhs) < key(rhs)
        }
        let lhsID = id(lhs).uuidString
        let rhsID = id(rhs).uuidString
        return lhsID < rhsID
      }
    }
  }

  private struct PersonalDictionarySettingsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var titleSize = 23
    @ObservedObject var viewModel: PersonalDictionarySettingsViewModel
    @Binding var searchRequest: SettingsSearchRequest?
    let pageScrollReadyRequestID: UUID?
    @Binding var selectedSection: SettingsSection
    @State private var showsImporter = false
    @State private var showsDictionaryExporter = false
    @State private var showsCSVExporter = false
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isSearchTriggerFocused: Bool
    @FocusState private var isOptionsTriggerFocused: Bool
    @State private var isViewPresent = false
    @State private var isSearchExpanded = false
    @State private var isOptionsPresented = false
    @State private var activeOptionsRevealID: UUID?
    @State private var focusedOptionsRevealID: UUID?
    @State private var deferredSearchRequest: SettingsSearchRequest?
    @State private var searchPresentationGeneration = 0
    @State private var presentationGeneration = 0
    @State private var pendingOptionsPresentation: (() -> Void)?
    @State private var pendingOptionsPresentationGeneration: Int?
    @State private var pendingOptionsPresentationRequestID: UUID?
    @State private var optionsDismissalGeneration: Int?
    @State private var optionsDismissalRequestID: UUID?
    @State private var returnsFocusAfterOptionsDismissal = false
    @AppStorage("settings.vocabularySortOrder")
    private var sortOrder = SettingsVocabularySortOrder.aToZ
    @State private var isReloading = false

    private let maximumTransferBytes = 64 * 1024 + 256

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        dictionaryHeader
        dictionaryToolbar
        if isSearchExpanded {
          searchSurface
            .transition(.opacity)
        }
        Divider()
        messages
        listSurface
        transferFooter
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .onChange(of: searchRequest?.id, initial: true) { _, _ in
        searchPresentationGeneration += 1
        presentationGeneration += 1
        clearPendingOptionsPresentation()
        optionsDismissalGeneration = nil
        returnsFocusAfterOptionsDismissal = false
        revealSearchTarget()
      }
      .onChange(of: pageScrollReadyRequestID) { _, _ in
        revealSearchTarget()
      }
      .onChange(of: hasModalPresentation) { wasPresented, isPresented in
        presentationGeneration += 1
        if isPresented {
          clearPendingOptionsPresentation()
          optionsDismissalGeneration = nil
          returnsFocusAfterOptionsDismissal = false
        }
        if wasPresented, !isPresented {
          revealDeferredSearchTarget()
        }
      }
      .onChange(of: isOptionsPresented) { _, isPresented in
        guard !isPresented else { return }
        activeOptionsRevealID = nil
        focusedOptionsRevealID = nil
      }
      .onExitCommand {
        guard isSearchExpanded, !isOptionsPresented, !hasModalPresentation else { return }
        closeSearch(source: .keyboard)
      }
      .onAppear {
        isViewPresent = true
        presentationGeneration += 1
        revealSearchTarget()
      }
      .onDisappear {
        isViewPresent = false
        activeOptionsRevealID = nil
        focusedOptionsRevealID = nil
        deferredSearchRequest = nil
        searchPresentationGeneration += 1
        presentationGeneration += 1
        clearPendingOptionsPresentation()
        optionsDismissalGeneration = nil
        returnsFocusAfterOptionsDismissal = false
        isOptionsPresented = false
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
      .confirmationDialog(
        viewModel.pendingEntryDeletion.map { "Delete \($0.preferredForm)?" } ?? "Delete this entry?",
        isPresented: Binding(
          get: { viewModel.pendingEntryDeletion != nil },
          set: { if !$0 { viewModel.cancelEntryDeletion() } }
        ),
        titleVisibility: .visible
      ) {
        Button("Delete", role: .destructive) {
          Task { @MainActor in await viewModel.confirmEntryDeletion() }
        }
        Button("Cancel", role: .cancel) {
          viewModel.cancelEntryDeletion()
        }
      } message: {
        Text("Fleck will stop applying this vocabulary entry.")
      }
    }

    private var dictionaryHeader: some View {
      HStack(spacing: 10) {
        Text("Dictionary")
          .font(.system(size: titleSize, weight: .semibold))
          .background(SettingsPageHeaderProbe())
          .settingsSearchAnchor(.section(.vocabulary), request: visibleSearchRequest)
        Spacer(minLength: 8)
        Button("Add new") {
          presentAfterClosingOptions {
            viewModel.beginAddingEntry()
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel("Add a new vocabulary word or phrase")
        .accessibilityHint("Opens the vocabulary word editor")
        .settingsSearchAnchor(.vocabularyAdd, request: visibleSearchRequest)
      }
      .frame(maxWidth: .infinity, minHeight: 40)
    }

    private var dictionaryToolbar: some View {
      HStack(spacing: 12) {
        HStack(spacing: 4) {
          ForEach(PersonalDictionarySettingsViewModel.Filter.allCases) { filter in
            Button {
              viewModel.filter = filter
            } label: {
              Text(filter.rawValue)
                .font(.subheadline.weight(filter == viewModel.filter ? .semibold : .regular))
                .foregroundStyle(filter == viewModel.filter ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(alignment: .bottom) {
                  if filter == viewModel.filter {
                    Rectangle()
                      .fill(Color.primary.opacity(0.72))
                      .frame(height: 2)
                  }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(filter.rawValue) filter")
            .accessibilityValue(filter == viewModel.filter ? "Selected" : "Available")
            .accessibilityHint("Shows \(filter.rawValue.lowercased()) vocabulary")
            .settingsSearchAnchor(.vocabularyFilter(filter), request: visibleSearchRequest)
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Personal dictionary filter")
        .accessibilityHint("Choose which vocabulary entries are shown")
        Spacer(minLength: 8)
        searchTrigger
        sortControl
        reloadControl
      }
      .frame(maxWidth: .infinity)
    }

    private var searchTrigger: some View {
      Button {
        let isCommandF = NSEvent.modifierFlags.contains(.command)
        guard !hasModalPresentation,
          !isCommandF || !isSettingsSearchFieldFocused
        else { return }
        presentAfterClosingOptions {
          openSearch(source: isCommandF ? .keyboard : .pointer)
        }
      } label: {
        Image(systemName: "magnifyingglass")
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .keyboardShortcut("f", modifiers: .command)
      .focused($isSearchTriggerFocused)
      .background {
        if isSearchTriggerFocused {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
        }
      }
      .overlay {
        if isSearchTriggerFocused {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.72), lineWidth: 1.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .disabled(hasModalPresentation)
      .help("Search vocabulary (⌘F)")
      .accessibilityLabel("Search vocabulary")
      .accessibilityHint("Focuses the vocabulary search field")
      .accessibilityIdentifier("settings-vocabulary-search-trigger")
    }

    private var transferFooter: some View {
      HStack {
        Button("Import / Export…") {
          toggleOptions()
        }
        .font(.footnote)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .focused($isOptionsTriggerFocused)
        .accessibilityIdentifier("settings-vocabulary-options-trigger")
        .accessibilityHint("Imports or exports your personal dictionary")
        .id(SettingsSearchTarget.vocabularyTransferFooter)
        .popover(isPresented: optionsPresentation, arrowEdge: .bottom) {
          optionsPopover
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity)
    }

    private var optionsPopover: some View {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            Text("Transfer")
              .font(.headline)
              .settingsSearchAnchor(.vocabularyTransfer, request: optionsSearchRequest)

            Button("Export Dictionary") {
              presentAfterClosingOptions {
                Task { @MainActor in
                  await viewModel.prepareCanonicalExport()
                  showsDictionaryExporter = viewModel.canonicalExportData != nil
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Export complete personal dictionary")
            .accessibilityHint("Exports entries and pending suggestions in a restorable format")
            .settingsSearchAnchor(.vocabularyExportDictionary, request: optionsSearchRequest)

            Button("Export Entries (CSV)") {
              presentAfterClosingOptions {
                Task { @MainActor in
                  await viewModel.prepareCSVExport()
                  showsCSVExporter = viewModel.csvExportData != nil
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Export visible entries as CSV")
            .accessibilityHint("Exports only the currently visible entries")
            .settingsSearchAnchor(.vocabularyExportCSV, request: optionsSearchRequest)

            Text(
              "CSV excludes pending suggestions and cannot restore a complete personal dictionary."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button("Import Dictionary") {
              presentAfterClosingOptions {
                showsImporter = true
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Import personal dictionary")
            .accessibilityHint("Selects a Fleck dictionary or compatible JSON file to preview")
            .settingsSearchAnchor(.vocabularyImportDictionary, request: optionsSearchRequest)
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: optionsScrollRequest?.id, initial: true) { _, _ in
          guard let request = optionsScrollRequest else { return }
          Task { @MainActor in
            await Task.yield()
            guard optionsScrollRequest?.id == request.id else { return }
            proxy.scrollTo(request.anchor, anchor: .center)
            await Task.yield()
            guard optionsScrollRequest?.id == request.id else { return }
            focusedOptionsRevealID = request.id
          }
        }
      }
      .frame(width: 280, height: 260)
      .accessibilityIdentifier("settings-vocabulary-options-content")
      .background(SettingsSearchProbe(identifier: "settings-vocabulary-options-content"))
      .onExitCommand {
        guard isOptionsPresented, !hasModalPresentation else { return }
        beginOptionsDismissal(returnFocus: true)
      }
      .onDisappear {
        optionsPopoverDidDisappear()
      }
    }

    private var sortControl: some View {
      Button {
        sortOrder = sortOrder == .aToZ ? .zToA : .aToZ
      } label: {
        Image(systemName: "arrow.up.arrow.down")
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .help("Sort \(sortOrder.rawValue)")
      .accessibilityLabel("Sort vocabulary")
      .accessibilityValue(sortOrder.rawValue)
      .accessibilityHint("Switches between A–Z and Z–A")
      .settingsSearchAnchor(.vocabularySort, request: visibleSearchRequest)
    }

    private var reloadControl: some View {
      Button(action: reloadVocabulary) {
        if isReloading {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: "arrow.clockwise")
            .frame(width: 28, height: 28)
        }
      }
      .buttonStyle(.plain)
      .disabled(isReloading)
      .help("Refresh dictionary")
      .accessibilityLabel("Refresh dictionary")
      .accessibilityValue(isReloading ? "Reloading" : "Ready")
      .accessibilityHint("Loads the latest local vocabulary entries")
      .settingsSearchAnchor(.vocabularyReload, request: visibleSearchRequest)
    }

    @ViewBuilder
    private var messages: some View {
      if isReloading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Reloading dictionary…")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reloading dictionary")
      } else if let errorMessage = viewModel.errorMessage {
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

    private var listSurface: some View {
      let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
      return VStack(alignment: .leading, spacing: 0) {
        if viewModel.filter == .suggestions {
          if sortedSuggestions.isEmpty {
            emptyState
          } else {
            ForEach(Array(sortedSuggestions.enumerated()), id: \.element.id) { index, suggestion in
              suggestionRow(suggestion, expectedRevision: viewModel.revision)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
              if index < sortedSuggestions.count - 1 {
                Divider().padding(.leading, 12)
              }
            }
          }
        } else if sortedEntries.isEmpty {
          emptyState
        } else {
          ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
            entryRow(entry, expectedRevision: viewModel.revision)
              .padding(.horizontal, 12)
            if index < sortedEntries.count - 1 {
              Divider().padding(.leading, 12)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(Color(nsColor: .controlBackgroundColor), in: card)
      .overlay {
        card.strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.8)
      }
      .clipShape(card)
    }

    private var sortedEntries: [PersonalDictionaryEntry] {
      sortOrder.sorted(
        viewModel.visibleEntries,
        by: \.preferredForm,
        id: \.id,
        priority: \.isPriority
      )
    }

    private var sortedSuggestions: [PersonalDictionarySuggestion] {
      sortOrder.sorted(viewModel.visibleSuggestions, by: \.preferredForm, id: \.id)
    }

    @ViewBuilder
    private var emptyState: some View {
      Group {
        if viewModel.filter == .suggestions {
          if viewModel.suggestions.isEmpty {
            Text("No pending suggestions.")
              .foregroundStyle(.secondary)
          } else {
            Text("No suggestions match your search. Clear search to review the queue.")
              .foregroundStyle(.secondary)
          }
        } else if viewModel.entries.isEmpty {
          Text("No entries yet. Use Add new to add a word, phrase, or correction.")
            .foregroundStyle(.secondary)
        } else if !viewModel.query.isEmpty {
          Text("No matching entries. Clear search or choose another filter.")
            .foregroundStyle(.secondary)
        } else if viewModel.filter != .all {
          Text("No entries match this filter. Choose All or use Add new.")
            .foregroundStyle(.secondary)
        }
      }
      .font(.callout)
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryRow(
      _ entry: PersonalDictionaryEntry,
      expectedRevision: UInt64
    ) -> some View {
      PersonalDictionaryEntryRow(
        entry: entry,
        title: entryTitle(entry),
        accessibilityValue: entryAccessibilityValue(entry),
        onEdit: { viewModel.beginEditingEntry(entry) },
        onDelete: { viewModel.requestEntryDeletion(entry, expectedRevision: expectedRevision) },
        onPriorityToggle: { priority in
          Task { @MainActor in
            await viewModel.setPriority(
              priority,
              id: entry.id,
              expectedRevision: expectedRevision
            )
          }
        }
      )
    }

    private func entryTitle(_ entry: PersonalDictionaryEntry) -> String {
      entry.aliases.first.map { first in
        let remaining = entry.aliases.count - 1
        let summary = remaining > 0 ? "\(first) +\(remaining) more" : first
        return "\(summary) → \(entry.preferredForm)"
      } ?? entry.preferredForm
    }

    private func entryAccessibilityValue(_ entry: PersonalDictionaryEntry) -> String {
      var values: [String]
      if entry.aliases.isEmpty {
        values = ["Preferred form \(entry.preferredForm)"]
      } else {
        values = [
          "Misheard spellings \(entry.aliases.joined(separator: ", "))",
          "Desired spelling \(entry.preferredForm)",
        ]
      }
      values.append(entry.isEnabled ? "Enabled" : "Disabled")
      if entry.isPriority {
        values.append("Prioritized")
      }
      return values.joined(separator: ", ")
    }

    private func suggestionRow(
      _ suggestion: PersonalDictionarySuggestion,
      expectedRevision: UInt64
    ) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(suggestion.preferredForm)
          .fixedSize(horizontal: false, vertical: true)
        if !suggestion.observedForms.isEmpty {
          Text(suggestion.observedForms.joined(separator: ", "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
      .padding(.vertical, 8)
      .accessibilityElement(children: .contain)
    }

    private var searchSurface: some View {
      let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
      return HStack(spacing: 7) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        TextField("Search vocabulary", text: $viewModel.query)
          .textFieldStyle(.plain)
          .frame(maxWidth: .infinity)
          .focused($isSearchFocused)
          .accessibilityLabel("Search vocabulary")
          .accessibilityValue(viewModel.query.isEmpty ? "No search" : viewModel.query)
          .accessibilityHint("Searches saved words and corrections")
          .settingsSearchAnchor(.vocabularySearch, request: visibleSearchRequest)
          .accessibilityIdentifier("settings-vocabulary-local-search-field")
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
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 8)
      .frame(height: 32)
      .background(Color(nsColor: .controlBackgroundColor), in: shape)
      .overlay {
        shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.8)
      }
      .background(SettingsSearchProbe(identifier: "settings-vocabulary-local-search-field"))
    }

    private var hasModalPresentation: Bool {
      viewModel.entryEdit != nil
        || viewModel.suggestionEdit != nil
        || viewModel.pendingEntryDeletion != nil
        || viewModel.isEntryDeletionInFlight
        || viewModel.isImportPreviewPresented
        || showsImporter
        || showsDictionaryExporter
        || showsCSVExporter
    }

    private var isSettingsSearchFieldFocused: Bool {
      guard let window = NSApp.keyWindow,
        let searchField = settingsSearchField(in: window.contentView)
      else { return false }
      if window.firstResponder === searchField { return true }
      guard let fieldEditor = searchField.currentEditor() else { return false }
      return window.firstResponder === fieldEditor
    }

    private func settingsSearchField(in view: NSView?) -> NSSearchField? {
      guard let view else { return nil }
      if let searchField = view as? NSSearchField,
        searchField.accessibilityIdentifier() == "settings-search-field"
      {
        return searchField
      }
      for subview in view.subviews {
        if let searchField = settingsSearchField(in: subview) {
          return searchField
        }
      }
      return nil
    }

    private var visibleSearchRequest: SettingsSearchRequest? {
      guard isViewPresent,
        selectedSection == .vocabulary,
        !hasModalPresentation,
        searchRequest?.id == pageScrollReadyRequestID
      else { return nil }
      return searchRequest
    }

    private var optionsSearchRequest: SettingsSearchRequest? {
      guard isViewPresent,
        selectedSection == .vocabulary,
        !hasModalPresentation,
        let request = searchRequest,
        request.id == focusedOptionsRevealID
      else { return nil }
      return request
    }

    private var optionsScrollRequest: SettingsSearchRequest? {
      guard isViewPresent,
        selectedSection == .vocabulary,
        !hasModalPresentation,
        let request = searchRequest,
        request.id == activeOptionsRevealID
      else { return nil }
      return request
    }

    private func revealSearchTarget() {
      guard isViewPresent, selectedSection == .vocabulary else { return }
      guard let request = searchRequest else {
        deferredSearchRequest = nil
        activeOptionsRevealID = nil
        return
      }
      guard request.target.usesVocabularyFocusLifecycle else {
        deferredSearchRequest = nil
        activeOptionsRevealID = nil
        return
      }
      guard pageScrollReadyRequestID == request.id else {
        deferredSearchRequest = request
        activeOptionsRevealID = nil
        focusedOptionsRevealID = nil
        return
      }
      guard !hasModalPresentation else {
        deferredSearchRequest = request
        activeOptionsRevealID = nil
        focusedOptionsRevealID = nil
        return
      }

      deferredSearchRequest = nil
      switch request.anchor {
      case .vocabularySearch:
        presentAfterClosingOptions {
          openSearch(source: .keyboard)
        }
      case .section(.vocabulary), .vocabularyAdd:
        dismissOptionsForNewPresentation()
        isSearchFocused = false
      case .vocabularyFilter, .vocabularySort, .vocabularyReload:
        isSearchFocused = false
        dismissOptionsForNewPresentation()
      case .vocabularyTransfer, .vocabularyExportDictionary, .vocabularyExportCSV,
        .vocabularyImportDictionary:
        isSearchFocused = false
        activeOptionsRevealID = request.id
        focusedOptionsRevealID = nil
        isOptionsPresented = true
      default:
        break
      }
    }

    private func revealDeferredSearchTarget() {
      guard let deferredSearchRequest,
        deferredSearchRequest.id == searchRequest?.id
      else {
        deferredSearchRequest = nil
        return
      }
      self.deferredSearchRequest = nil
      revealSearchTarget()
    }

    private func dismissOptionsForNewPresentation() {
      activeOptionsRevealID = nil
      focusedOptionsRevealID = nil
      guard isOptionsPresented else { return }
      beginOptionsDismissal(returnFocus: false)
    }

    private func presentAfterClosingOptions(_ presentation: @escaping () -> Void) {
      guard isOptionsPresented else {
        guard isViewPresent, selectedSection == .vocabulary, !hasModalPresentation else {
          return
        }
        presentation()
        return
      }
      searchPresentationGeneration += 1
      presentationGeneration += 1
      pendingOptionsPresentation = presentation
      pendingOptionsPresentationGeneration = presentationGeneration
      pendingOptionsPresentationRequestID = searchRequest?.id
      beginOptionsDismissal(returnFocus: false)
    }

    private var optionsPresentation: Binding<Bool> {
      Binding(
        get: { isOptionsPresented },
        set: { isPresented in
          guard isPresented != isOptionsPresented else { return }
          if isPresented {
            isOptionsPresented = true
          } else {
            beginOptionsDismissal(returnFocus: false)
          }
        }
      )
    }

    private func toggleOptions() {
      if isOptionsPresented {
        beginOptionsDismissal(returnFocus: true)
        return
      }
      searchPresentationGeneration += 1
      presentationGeneration += 1
      clearPendingOptionsPresentation()
      optionsDismissalGeneration = nil
      activeOptionsRevealID = nil
      focusedOptionsRevealID = nil
      returnsFocusAfterOptionsDismissal = false
      isOptionsPresented = true
    }

    private func beginOptionsDismissal(returnFocus: Bool) {
      optionsDismissalGeneration = presentationGeneration
      optionsDismissalRequestID = searchRequest?.id
      returnsFocusAfterOptionsDismissal = returnFocus
      isOptionsPresented = false
    }

    private func optionsPopoverDidDisappear() {
      let presentation = pendingOptionsPresentation
      let queuedGeneration = pendingOptionsPresentationGeneration
      let queuedRequestID = pendingOptionsPresentationRequestID
      clearPendingOptionsPresentation()

      let dismissalGeneration = optionsDismissalGeneration
      let dismissalRequestID = optionsDismissalRequestID
      let shouldReturnFocus = returnsFocusAfterOptionsDismissal
      optionsDismissalGeneration = nil
      optionsDismissalRequestID = nil
      returnsFocusAfterOptionsDismissal = false

      guard isViewPresent, selectedSection == .vocabulary else { return }
      if let presentation {
        guard queuedGeneration == presentationGeneration,
          queuedRequestID == searchRequest?.id,
          !hasModalPresentation
        else { return }
        presentation()
        return
      }
      guard shouldReturnFocus,
        dismissalGeneration == self.presentationGeneration,
        dismissalRequestID == searchRequest?.id,
        !hasModalPresentation
      else { return }
      isOptionsTriggerFocused = true
    }

    private func clearPendingOptionsPresentation() {
      pendingOptionsPresentation = nil
      pendingOptionsPresentationGeneration = nil
      pendingOptionsPresentationRequestID = nil
    }

    private func openSearch(source: AppInteractionSource) {
      searchPresentationGeneration += 1
      presentationGeneration += 1
      isOptionsTriggerFocused = false
      isSearchTriggerFocused = false
      withAnimation(motion.presentationAnimation(for: source)) {
        isSearchExpanded = true
        isSearchFocused = true
      }
    }

    private func closeSearch(source: AppInteractionSource) {
      searchPresentationGeneration += 1
      withAnimation(motion.presentationAnimation(for: source)) {
        isSearchExpanded = false
        isSearchFocused = false
      }
      isSearchTriggerFocused = true
      clearSearchQueryAfterTeardown()
    }

    private func clearSearchQueryAfterTeardown() {
      let generation = searchPresentationGeneration
      let requestID = searchRequest?.id
      let viewModel = viewModel
      Task { @MainActor in
        await Task.yield()
        guard generation == searchPresentationGeneration,
          requestID == searchRequest?.id,
          isViewPresent,
          selectedSection == .vocabulary,
          !isSearchExpanded
        else { return }
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

  private struct PersonalDictionaryEntryRow: View {
    private enum Action: Hashable {
      case edit
      case delete
      case priority
    }

    let entry: PersonalDictionaryEntry
    let title: String
    let accessibilityValue: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onPriorityToggle: (Bool) -> Void
    @State private var isHovered = false
    @FocusState private var focusedAction: Action?
    @AccessibilityFocusState private var accessibilityFocusedAction: Action?

    private var isFocused: Bool {
      focusedAction != nil || accessibilityFocusedAction != nil
    }

    private var showsActions: Bool {
      isHovered || isFocused
    }

    var body: some View {
      HStack(spacing: 10) {
        Button(action: onEdit) {
          HStack(spacing: 6) {
            Text(title)
              .font(.body)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
            if entry.isPriority {
              Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            }
            if !entry.isEnabled {
              Text("Disabled")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
          }
          .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
          .contentShape(Rectangle())
          .background {
            if focusedAction == .edit || accessibilityFocusedAction == .edit {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            }
          }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focusedAction, equals: .edit)
        .accessibilityFocused($accessibilityFocusedAction, equals: .edit)
        .overlay {
          if focusedAction == .edit || accessibilityFocusedAction == .edit {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(Color.primary.opacity(0.72), lineWidth: 1.5)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .help("Edit \(entry.preferredForm)")
        .accessibilityLabel("Edit \(entry.preferredForm)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens this dictionary entry for editing")
        .accessibilityIdentifier("settings-vocabulary-entry-\(entry.id.uuidString)")
        HStack(spacing: 4) {
          actionButton(
            .delete,
            systemImage: "trash",
            accessibilityLabel: "Delete \(entry.preferredForm)",
            accessibilityHint: "Asks for confirmation before deleting this entry",
            accessibilityIdentifier: "settings-vocabulary-entry-delete-\(entry.id.uuidString)",
            role: .destructive,
            action: onDelete
          )
          actionButton(
            .priority,
            systemImage: entry.isPriority ? "star.fill" : "star",
            accessibilityLabel: entry.isPriority
              ? "Unstar \(entry.preferredForm)"
              : "Star \(entry.preferredForm)",
            accessibilityValue: entry.isPriority ? "Starred" : "Not starred",
            accessibilityHint: "Pins starred entries to the top of the dictionary",
            accessibilityIdentifier: "settings-vocabulary-entry-priority-\(entry.id.uuidString)",
            isPriority: entry.isPriority,
            action: { onPriorityToggle(!entry.isPriority) }
          )
        }
        .opacity(showsActions ? 1 : 0)
      }
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .background {
        if showsActions {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
        }
      }
      .onHover { isHovered = $0 }
      .background(
        SettingsSearchProbe(identifier: "settings-vocabulary-entry-frame-\(entry.id.uuidString)")
      )
      .accessibilityElement(children: .contain)
    }

    private func actionButton(
      _ action: Action,
      systemImage: String,
      accessibilityLabel: String,
      accessibilityValue: String? = nil,
      accessibilityHint: String,
      accessibilityIdentifier: String,
      role: ButtonRole? = nil,
      isPriority: Bool = false,
      action perform: @escaping () -> Void
    ) -> some View {
      Button(role: role, action: perform) {
        Image(systemName: systemImage)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(isPriority ? Color.accentColor : Color.secondary)
          .frame(width: 24, height: 24)
          .background {
            if focusedAction == action || accessibilityFocusedAction == action {
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            }
          }
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .focused($focusedAction, equals: action)
      .accessibilityFocused($accessibilityFocusedAction, equals: action)
      .overlay {
        if focusedAction == action || accessibilityFocusedAction == action {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.72), lineWidth: 1.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .help(accessibilityLabel)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityValue(accessibilityValue ?? "")
      .accessibilityHint(accessibilityHint)
      .accessibilityIdentifier(accessibilityIdentifier)
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
