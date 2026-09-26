#if os(macOS)
  import AppKit
  import FleckCore
  import Foundation
  import SwiftUI

  enum SettingsSearchTarget: Hashable {
    case section(SettingsSection)

    case generalLaunchAtLogin
    case generalAutomaticLists
    case generalConfirmTrash

    case appearanceTheme
    case appearanceColorTheme
    case appearanceChromeAppearance
    case appearanceGlassOpacity
    case appearanceWidth
    case appearanceHeight

    case shortcut(Shortcut.Action)

    case dictationStatus
    case dictationModel
    case dictationCleanupModel
    case dictationModifier
    case dictationMicrophone
    case dictationRecognitionLanguage
    case dictationStatusCapsule
    case dictationShortcutGuide
    case dictationLocalHistory
    case dictationClearHistory
    case dictationPrivacy

    case vocabularyAdd
    case vocabularySearch
    case vocabularySort
    case vocabularyReload
    case vocabularyTransfer
    case vocabularyTransferFooter
    case vocabularyExportDictionary
    case vocabularyExportCSV
    case vocabularyImportDictionary

    case agentsConnector
    case agentIntegration(AgentIntegrationKind)
    case agentsConnectedProfiles
    case agentsSetup
    case agentsActivity
    case agentsUpdateBanners
    case agentsOpenActivity
    case agentsClearActivity
    case agentsAccess

    case aboutProductVersion
    case aboutBuild
    case aboutSource
    case aboutCandidateStatus
    case aboutMetadata
    case aboutCopyBuildInfo

    var identifier: String {
      switch self {
      case .section(let section): "section-\(section.rawValue)"
      case .generalLaunchAtLogin: "general-launch-at-login"
      case .generalAutomaticLists: "general-automatic-lists"
      case .generalConfirmTrash: "general-confirm-trash"
      case .appearanceTheme: "appearance-theme"
      case .appearanceColorTheme: "appearance-color-theme"
      case .appearanceChromeAppearance: "appearance-chrome-appearance"
      case .appearanceGlassOpacity: "appearance-glass-opacity"
      case .appearanceWidth: "appearance-width"
      case .appearanceHeight: "appearance-height"
      case .shortcut(let action): "shortcut-\(action.rawValue)"
      case .dictationStatus: "dictation-status"
      case .dictationModel: "dictation-model"
      case .dictationCleanupModel: "dictation-cleanup-model"
      case .dictationModifier: "dictation-modifier"
      case .dictationMicrophone: "dictation-microphone"
      case .dictationRecognitionLanguage: "dictation-recognition-language"
      case .dictationStatusCapsule: "dictation-status-capsule"
      case .dictationShortcutGuide: "dictation-shortcut-guide"
      case .dictationLocalHistory: "dictation-local-history"
      case .dictationClearHistory: "dictation-clear-history"
      case .dictationPrivacy: "dictation-privacy"
      case .vocabularyAdd: "vocabulary-add"
      case .vocabularySearch: "vocabulary-search"
      case .vocabularySort: "vocabulary-sort"
      case .vocabularyReload: "vocabulary-reload"
      case .vocabularyTransfer: "vocabulary-transfer"
      case .vocabularyTransferFooter: "vocabulary-transfer-footer"
      case .vocabularyExportDictionary: "vocabulary-export-dictionary"
      case .vocabularyExportCSV: "vocabulary-export-csv"
      case .vocabularyImportDictionary: "vocabulary-import-dictionary"
      case .agentsConnector: "agents-connector"
      case .agentIntegration(let integration): "agents-integration-\(integration.rawValue)"
      case .agentsConnectedProfiles: "agents-connected-profiles"
      case .agentsSetup: "agents-setup"
      case .agentsActivity: "agents-activity"
      case .agentsUpdateBanners: "agents-update-banners"
      case .agentsOpenActivity: "agents-open-activity"
      case .agentsClearActivity: "agents-clear-activity"
      case .agentsAccess: "agents-access"
      case .aboutProductVersion: "about-product-version"
      case .aboutBuild: "about-build"
      case .aboutSource: "about-source"
      case .aboutCandidateStatus: "about-candidate-status"
      case .aboutMetadata: "about-metadata"
      case .aboutCopyBuildInfo: "about-copy-build-info"
      }
    }

    var accessibilityIdentifier: String {
      "settings-search-target-\(identifier)"
    }

    var pageScrollAnchor: Self {
      switch self {
      case .vocabularyTransfer, .vocabularyExportDictionary, .vocabularyExportCSV,
        .vocabularyImportDictionary:
        .vocabularyTransferFooter
      case .vocabularyAdd, .vocabularySearch, .vocabularySort, .vocabularyReload:
        .section(.vocabulary)
      default:
        self
      }
    }

    var usesVocabularyFocusLifecycle: Bool {
      switch self {
      case .section(.vocabulary), .vocabularyAdd, .vocabularySearch, .vocabularySort,
        .vocabularyReload, .vocabularyTransfer,
        .vocabularyExportDictionary, .vocabularyExportCSV, .vocabularyImportDictionary:
        true
      default:
        false
      }
    }

    var focusLabel: String {
      SettingsSearchIndex.catalog.first { $0.target == self }?.title ?? identifier
    }

    func revealAnchor(isPackaged: Bool) -> Self {
      guard !isPackaged else { return self }
      switch self {
      case .aboutProductVersion, .aboutSource, .aboutCandidateStatus:
        return .aboutMetadata
      default:
        return self
      }
    }
  }

  struct SettingsSearchResult: Equatable, Identifiable {
    let target: SettingsSearchTarget
    let title: String
    let destination: SettingsSection
    let aliases: [String]
    let anchor: SettingsSearchTarget

    var id: SettingsSearchTarget { target }
    var accessibilityLabel: String { "\(title), \(destination.title)" }
  }

  struct SettingsSearchRequest: Equatable, Identifiable {
    let id: UUID
    let target: SettingsSearchTarget
    let anchor: SettingsSearchTarget

    init(
      target: SettingsSearchTarget,
      anchor: SettingsSearchTarget? = nil,
      id: UUID = UUID()
    ) {
      self.id = id
      self.target = target
      self.anchor = anchor ?? target
    }
  }

  private struct SettingsSearchRequestEnvironmentKey: EnvironmentKey {
    static let defaultValue: SettingsSearchRequest? = nil
  }

  extension EnvironmentValues {
    var settingsSearchRequest: SettingsSearchRequest? {
      get { self[SettingsSearchRequestEnvironmentKey.self] }
      set { self[SettingsSearchRequestEnvironmentKey.self] = newValue }
    }
  }

  enum SettingsSearchMove {
    case up
    case down
  }

  struct SettingsAccentPresentation {
    let color: Color
    let selectionColor: Color
    let contrastingColor: Color
    let primaryTextColor: Color
    let secondaryTextColor: Color

    init(theme: FleckThemeSnapshot) {
      color = theme.color(.accent)
      selectionColor = theme.color(.selectionFill)
      contrastingColor = theme.color(.selectionText)
      primaryTextColor = theme.color(.textPrimary)
      secondaryTextColor = theme.color(.caption)
    }
  }

  enum SettingsSearchIndex {
    static let catalog: [SettingsSearchResult] = {
      var results: [SettingsSearchResult] = []

      func add(
        _ target: SettingsSearchTarget,
        _ title: String,
        to destination: SettingsSection,
        aliases: [String] = [],
        anchor: SettingsSearchTarget? = nil
      ) {
        results.append(
          SettingsSearchResult(
            target: target,
            title: title,
            destination: destination,
            aliases: aliases,
            anchor: anchor ?? target
          )
        )
      }

      func addSection(_ section: SettingsSection, aliases: [String] = []) {
        add(
          .section(section),
          section.title,
          to: section,
          aliases: [section.rawValue, section.description] + aliases
        )
      }

      addSection(.editing)
      add(
        .generalLaunchAtLogin,
        "Launch at login",
        to: .editing,
        aliases: ["startup", "start automatically", "sign in", "login item"]
      )
      add(
        .generalAutomaticLists,
        "Create lists automatically",
        to: .editing,
        aliases: ["automatic lists", "format bullets", "list-shaped lines"]
      )
      add(
        .generalConfirmTrash,
        "Confirm before moving notes to Trash",
        to: .editing,
        aliases: ["delete confirmation", "confirm trash", "move note to trash"]
      )

      addSection(.appearance)
      add(.appearanceTheme, "Appearance", to: .appearance, aliases: ["light dark system"])
      add(
        .appearanceColorTheme,
        "Color theme",
        to: .appearance,
        aliases: ["palette", "color palette", "colour theme"]
      )
      add(
        .appearanceChromeAppearance,
        "Glass appearance",
        to: .appearance,
        aliases: ["window appearance", "solid", "surface", "translucency", "material"]
      )
      add(
        .appearanceGlassOpacity,
        "Glass opacity",
        to: .appearance,
        aliases: ["transparency"]
      )
      add(.appearanceWidth, "Width", to: .appearance, aliases: ["menu panel size"])
      add(.appearanceHeight, "Height", to: .appearance, aliases: ["menu panel size"])

      addSection(.shortcuts)
      for action in Shortcut.Action.allCases {
        add(.shortcut(action), action.title, to: .shortcuts, aliases: ["keyboard shortcut"])
      }

      addSection(.dictation)
      add(
        .dictationStatus,
        DictationSettingsGroup.readiness.rawValue,
        to: .dictation,
        aliases: ["readiness", "permission recovery", "microphone speech permission"]
      )
      add(.dictationModel, "Dictation model", to: .dictation, aliases: ["speech model"])
      add(.dictationCleanupModel, "Cleanup model", to: .dictation)
      add(.dictationModifier, "Modifier key", to: .dictation)
      add(.dictationMicrophone, "Microphone", to: .dictation, aliases: ["audio input"])
      add(.dictationRecognitionLanguage, "Recognition language", to: .dictation)
      add(.dictationStatusCapsule, "Show status capsule", to: .dictation)
      add(.dictationShortcutGuide, "Show shortcut guide in editor", to: .dictation)
      add(.dictationLocalHistory, "Keep local history for 30 days", to: .dictation)
      add(.dictationClearHistory, "Clear History", to: .dictation, aliases: ["delete history"])
      add(.dictationPrivacy, DictationSettingsGroup.privacy.rawValue, to: .dictation)

      addSection(.vocabulary, aliases: ["suggestions"])
      add(.vocabularyAdd, "Add New", to: .vocabulary, aliases: ["new word phrase correction"])
      add(.vocabularySearch, "Search vocabulary", to: .vocabulary)
      add(
        .vocabularySort,
        "Sort",
        to: .vocabulary,
        aliases: ["alphabetical A to Z Z to A", "recently used", "most used"]
      )
      add(.vocabularyReload, "Reload", to: .vocabulary, aliases: ["refresh"])
      add(.vocabularyTransfer, "Transfer", to: .vocabulary)
      add(.vocabularyExportDictionary, "Export Dictionary", to: .vocabulary)
      add(.vocabularyExportCSV, "Export Entries (CSV)", to: .vocabulary)
      add(.vocabularyImportDictionary, "Import Dictionary", to: .vocabulary)

      addSection(.agents)
      add(
        .agentsConnector,
        "Local connector",
        to: .agents,
        aliases: [AgentConnectorPresentation.sectionTitle, "install refresh status"]
      )
      for integration in AgentIntegrationKind.allCases {
        add(
          .agentIntegration(integration),
          integration.displayName,
          to: .agents,
          aliases: [integration.description]
        )
      }
      add(
        .agentsConnectedProfiles,
        "Connected Profiles",
        to: .agents,
        aliases: ["capabilities revoke snippets route"]
      )
      add(.agentsSetup, "Set up a local integration", to: .agents)
      add(.agentsActivity, "Activity", to: .agents)
      add(.agentsUpdateBanners, "Show agent update banners", to: .agents)
      add(.agentsOpenActivity, "Open Agent Activity", to: .agents)
      add(.agentsClearActivity, "Clear Activity", to: .agents)
      add(.agentsAccess, "Access", to: .agents, aliases: ["capability grants permissions"])

      addSection(.about)
      add(.aboutProductVersion, "Product version", to: .about)
      add(.aboutBuild, "Build", to: .about, aliases: ["build number date"])
      add(.aboutSource, "Source", to: .about, aliases: ["revision commit"])
      add(.aboutCandidateStatus, "Candidate status", to: .about, aliases: ["acceptance"])
      add(.aboutMetadata, "Full build metadata", to: .about)
      add(.aboutCopyBuildInfo, "Copy Build Info", to: .about)

      return results
    }()

    static func results(for query: String) -> [SettingsSearchResult] {
      let normalizedQuery = normalize(query)
      guard !normalizedQuery.isEmpty else { return [] }
      let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
      let matches: [(rank: Int, index: Int, result: SettingsSearchResult)] =
        catalog.enumerated().compactMap { index, result in
          guard let rank = matchRank(for: result, query: normalizedQuery, tokens: tokens) else {
            return nil
          }
          return (rank: rank, index: index, result: result)
        }
      return matches.sorted {
        $0.rank == $1.rank ? $0.index < $1.index : $0.rank < $1.rank
      }
      .map(\.result)
    }

    static func movingHighlight(
      _ move: SettingsSearchMove,
      from current: SettingsSearchTarget?,
      in results: [SettingsSearchResult]
    ) -> SettingsSearchTarget? {
      guard !results.isEmpty else { return nil }
      guard let current,
        let currentIndex = results.firstIndex(where: { $0.target == current })
      else {
        return move == .down ? results.first?.target : results.last?.target
      }
      let nextIndex: Int
      switch move {
      case .up: nextIndex = max(results.startIndex, currentIndex - 1)
      case .down: nextIndex = min(results.index(before: results.endIndex), currentIndex + 1)
      }
      return results[nextIndex].target
    }

    private static func matchRank(
      for result: SettingsSearchResult,
      query: String,
      tokens: [String]
    ) -> Int? {
      let title = normalize(result.title)
      if title == query { return 0 }
      if title.hasPrefix(query) { return 1 }
      if tokens.allSatisfy(title.contains) { return 2 }

      let terms = [title, normalize(result.destination.title)] + result.aliases.map(normalize)
      return tokens.allSatisfy { token in terms.contains(where: { $0.contains(token) }) }
        ? 3
        : nil
    }

    private static func normalize(_ value: String) -> String {
      value
        .folding(
          options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
          locale: Locale(identifier: "en_US_POSIX")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  struct SettingsSearchField: NSViewRepresentable {
    @Binding var query: String
    var focusRequest: UUID? = nil
    let onMove: (SettingsSearchMove) -> Void
    let onSubmit: () -> Void
    let onBeginEditing: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
      let field = NSSearchField()
      field.delegate = context.coordinator
      field.placeholderString = "Search settings"
      field.sendsSearchStringImmediately = true
      field.sendsWholeSearchString = false
      Self.applyNativeMetrics(to: field)
      field.setAccessibilityLabel("Search settings")
      field.setAccessibilityIdentifier("settings-search-field")
      return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
      context.coordinator.parent = self
      Self.applyNativeMetrics(to: field)
      if field.stringValue != query {
        field.stringValue = query
      }
      guard let focusRequest, context.coordinator.focusRequest != focusRequest else { return }
      context.coordinator.focusRequest = focusRequest
      let coordinator = context.coordinator
      Task { @MainActor [weak field, weak coordinator] in
        await Task.yield()
        guard let field, coordinator?.focusRequest == focusRequest, field.window != nil else {
          return
        }
        field.window?.makeFirstResponder(field)
      }
    }

    private static func applyNativeMetrics(to field: NSSearchField) {
      field.controlSize = .large
      field.cell?.controlSize = .large
      field.font = .systemFont(ofSize: 13)
      field.focusRingType = .none
    }

    static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
      let onFocusChange = coordinator.parent.onFocusChange
      field.delegate = nil
      Task { @MainActor in
        await Task.yield()
        onFocusChange(false)
      }
    }

    func sizeThatFits(
      _ proposal: ProposedViewSize,
      nsView: NSSearchField,
      context: Context
    ) -> CGSize? {
      CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: 28)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
      var parent: SettingsSearchField
      var focusRequest: UUID?

      init(parent: SettingsSearchField) {
        self.parent = parent
      }

      func controlTextDidBeginEditing(_ notification: Notification) {
        parent.onFocusChange(true)
        parent.onBeginEditing()
      }

      func controlTextDidEndEditing(_ notification: Notification) {
        parent.onFocusChange(false)
      }

      func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        parent.query = field.stringValue
      }

      func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
      ) -> Bool {
        if textView.hasMarkedText(),
          commandSelector == #selector(NSResponder.moveUp(_:))
            || commandSelector == #selector(NSResponder.moveDown(_:))
            || commandSelector == #selector(NSResponder.insertNewline(_:))
        {
          return false
        }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
          parent.onMove(.up)
        case #selector(NSResponder.moveDown(_:)):
          parent.onMove(.down)
        case #selector(NSResponder.insertNewline(_:)):
          parent.onSubmit()
        case #selector(NSResponder.cancelOperation(_:)):
          if parent.query.isEmpty {
            control.window?.makeFirstResponder(nil)
          } else {
            parent.query = ""
            (control as? NSSearchField)?.stringValue = ""
          }
        default:
          return false
        }
        return true
      }
    }

  }

  struct SettingsSearchResultsView: View {
    let results: [SettingsSearchResult]
    let highlightedTarget: SettingsSearchTarget?
    let accentPresentation: SettingsAccentPresentation
    let onHighlight: (SettingsSearchTarget) -> Void
    let onActivate: (SettingsSearchResult) -> Void
    let onCancel: () -> Void

    var body: some View {
      if results.isEmpty {
        ContentUnavailableView(
          "No Settings Found",
          systemImage: "magnifyingglass",
          description: Text("Try another setting or section name.")
        )
        .accessibilityIdentifier("settings-search-empty")
        .background(SettingsSearchProbe(identifier: "settings-search-empty"))
      } else {
        ScrollViewReader { proxy in
          List(results, selection: selection) { result in
            resultRow(result)
          }
          .listStyle(.sidebar)
          .scrollContentBackground(.hidden)
          .accessibilityLabel("Settings search results")
          .background {
            SettingsSearchResultsKeyHandler(
              onSubmit: {
                guard let highlightedTarget,
                  let result = results.first(where: { $0.target == highlightedTarget })
                else { return }
                onActivate(result)
              },
              onCancel: onCancel
            )
            SettingsListSelectionStyleAdapter(
              accessibilityLabel: "Settings search results"
            )
          }
          .onKeyPress(keys: [.return], phases: .down) { press in
            handleReturn(press)
          }
          .onKeyPress(keys: [.escape], phases: .down) { press in
            handleCancel(press)
          }
          .onChange(of: highlightedTarget, initial: true) { _, target in
            guard let target else { return }
            proxy.scrollTo(target, anchor: .center)
          }
        }
      }
    }

    private var selection: Binding<SettingsSearchTarget?> {
      Binding(
        get: { highlightedTarget },
        set: { target in
          guard let target,
            let result = results.first(where: { $0.target == target })
          else { return }
          onHighlight(result.target)
        }
      )
    }

    private func resultRow(_ result: SettingsSearchResult) -> some View {
      Button {
        onActivate(result)
      } label: {
        HStack(spacing: 8) {
          Image(systemName: result.destination.systemImage)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
              .lineLimit(2)
            Text(result.destination.title)
              .font(.caption)
              .foregroundStyle(
                result.target == highlightedTarget
                  ? accentPresentation.contrastingColor
                  : accentPresentation.secondaryTextColor
              )
          }
          Spacer(minLength: 0)
          if result.target == highlightedTarget {
            Image(systemName: "chevron.right")
              .accessibilityHidden(true)
          }
        }
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 28)
      .contentShape(Rectangle())
      .frame(minHeight: 44)
      .foregroundStyle(
        result.target == highlightedTarget
          ? accentPresentation.contrastingColor
          : accentPresentation.primaryTextColor
      )
      .background(
        result.target == highlightedTarget
          ? accentPresentation.selectionColor
          : Color.clear,
        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
      )
      .tag(result.target)
      .id(result.target)
      .listRowInsets(EdgeInsets(top: 0, leading: -16, bottom: 0, trailing: -16))
      .listRowBackground(Color.clear)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(result.accessibilityLabel)
      .accessibilityValue(result.target == highlightedTarget ? "Selected" : "Result")
      .accessibilityHint("Opens this setting without changing it")
      .accessibilityAction { onActivate(result) }
      .accessibilityIdentifier("settings-search-result-\(result.target.identifier)")
      .background(
        SettingsSearchProbe(
          identifier: "settings-search-result-\(result.target.identifier)"
        )
      )
      .background {
        if result.target == highlightedTarget {
          SettingsSearchProbe(
            identifier: "settings-search-highlight-\(result.target.identifier)"
          )
        }
      }
    }

    private func handleReturn(_ press: KeyPress) -> KeyPress.Result {
      guard
        press.modifiers.intersection([.command, .option, .control, .shift]).isEmpty,
        let highlightedTarget,
        let result = results.first(where: { $0.target == highlightedTarget })
      else { return .ignored }
      onActivate(result)
      return .handled
    }

    private func handleCancel(_ press: KeyPress) -> KeyPress.Result {
      guard press.modifiers.intersection([.command, .option, .control, .shift]).isEmpty
      else { return .ignored }
      onCancel()
      return .handled
    }
  }

  private struct SettingsSearchResultsKeyHandler: NSViewRepresentable {
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyHandlerView {
      let view = KeyHandlerView()
      view.onSubmit = onSubmit
      view.onCancel = onCancel
      view.setAccessibilityElement(false)
      return view
    }

    func updateNSView(_ view: KeyHandlerView, context: Context) {
      view.onSubmit = onSubmit
      view.onCancel = onCancel
    }

    static func dismantleNSView(_ view: KeyHandlerView, coordinator: ()) {
      view.removeMonitor()
    }

    final class KeyHandlerView: NSView {
      var onSubmit: (() -> Void)?
      var onCancel: (() -> Void)?
      private var monitor: Any?

      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
          guard let self,
            event.window === window,
            event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
            let table = resultsTable(in: window?.contentView),
            window?.firstResponder === table
          else { return event }
          switch event.keyCode {
          case 36, 76:
            onSubmit?()
          case 53:
            onCancel?()
          default:
            return event
          }
          return nil
        }
      }

      func removeMonitor() {
        if let monitor {
          NSEvent.removeMonitor(monitor)
          self.monitor = nil
        }
      }

      private func resultsTable(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let table = view as? NSTableView,
          table.accessibilityLabel() == "Settings search results"
        {
          return table
        }
        for subview in view.subviews {
          if let table = resultsTable(in: subview) {
            return table
          }
        }
        return nil
      }
    }
  }

  struct SettingsListSelectionStyleAdapter: NSViewRepresentable {
    let accessibilityLabel: String

    func makeNSView(context: Context) -> SelectionStyleView {
      let view = SelectionStyleView()
      view.targetAccessibilityLabel = accessibilityLabel
      view.setAccessibilityElement(false)
      return view
    }

    func updateNSView(_ view: SelectionStyleView, context: Context) {
      view.targetAccessibilityLabel = accessibilityLabel
      view.applySelectionStyle()
    }

    final class SelectionStyleView: NSView {
      var targetAccessibilityLabel = ""

      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applySelectionStyle()
        DispatchQueue.main.async { [weak self] in
          self?.applySelectionStyle()
        }
      }

      override func layout() {
        super.layout()
        applySelectionStyle()
      }

      func applySelectionStyle() {
        guard let table = nearestTable() else { return }
        table.selectionHighlightStyle = .none
      }

      private func nearestTable() -> NSTableView? {
        var ancestor = superview
        while let candidate = ancestor {
          let tables = descendantTables(in: candidate)
          if tables.count == 1 {
            return tables[0]
          }
          ancestor = candidate.superview
        }
        guard let contentView = window?.contentView else { return nil }
        return matchingTable(in: contentView)
      }

      private func descendantTables(in view: NSView) -> [NSTableView] {
        var tables = view.subviews.compactMap { $0 as? NSTableView }
        for subview in view.subviews {
          tables.append(contentsOf: descendantTables(in: subview))
        }
        return tables
      }

      private func matchingTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView,
          table.accessibilityLabel() == targetAccessibilityLabel
        {
          return table
        }
        for subview in view.subviews {
          if let table = matchingTable(in: subview) {
            return table
          }
        }
        return nil
      }
    }
  }

  private struct SettingsSearchAnchorModifier: ViewModifier {
    let target: SettingsSearchTarget
    let request: SettingsSearchRequest?
    @FocusState private var isKeyboardFocused: Bool
    @AccessibilityFocusState private var isFocused: Bool

    private var isRevealed: Bool {
      request?.anchor == target
    }

    private var usesNeutralKeyboardFocus: Bool {
      switch target {
      case .vocabularySearch, .vocabularySort, .vocabularyReload,
        .vocabularyTransfer, .vocabularyExportDictionary, .vocabularyExportCSV,
        .vocabularyImportDictionary:
        true
      default:
        false
      }
    }

    func body(content: Content) -> some View {
      content
        .id(target)
        .accessibilityIdentifier(target.accessibilityIdentifier)
        .accessibilityLabel(target.focusLabel)
        .focusable()
        .focusEffectDisabled(usesNeutralKeyboardFocus)
        .focused($isKeyboardFocused)
        .accessibilityFocused($isFocused)
        .background {
          SettingsSearchProbe(identifier: target.accessibilityIdentifier)
          if isKeyboardFocused {
            SettingsSearchProbe(identifier: "settings-keyboard-focus-\(target.identifier)")
          }
        }
        .overlay(alignment: .bottom) {
          if isRevealed {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(
                Color.primary.opacity(0.72),
                style: StrokeStyle(lineWidth: 2, dash: [4, 3])
              )
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          } else if usesNeutralKeyboardFocus && isKeyboardFocused {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(Color.primary.opacity(0.72), lineWidth: 1.5)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .overlay(alignment: .topTrailing) {
          if isRevealed {
            Image(systemName: "scope")
              .padding(4)
              .background(.regularMaterial, in: Circle())
              .padding(4)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .onChange(of: request?.id, initial: true) { _, _ in
          if target.usesVocabularyFocusLifecycle {
            if !isRevealed {
              isKeyboardFocused = false
              isFocused = false
            }
            return
          }
          guard isRevealed else {
            isFocused = false
            return
          }
          Task { @MainActor in
            await Task.yield()
            isKeyboardFocused = true
            isFocused = true
          }
        }
        .task(id: target.usesVocabularyFocusLifecycle ? request?.id : nil) {
          guard target.usesVocabularyFocusLifecycle, isRevealed else { return }
          await Task.yield()
          guard !Task.isCancelled, isRevealed else { return }
          isKeyboardFocused = true
          isFocused = true
        }
        .onDisappear {
          guard target.usesVocabularyFocusLifecycle else { return }
          isKeyboardFocused = false
          isFocused = false
        }
    }
  }

  struct SettingsSearchProbe: NSViewRepresentable {
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

  extension View {
    func settingsSearchAnchor(
      _ target: SettingsSearchTarget,
      request: SettingsSearchRequest?
    ) -> some View {
      modifier(SettingsSearchAnchorModifier(target: target, request: request))
    }
  }

#endif
