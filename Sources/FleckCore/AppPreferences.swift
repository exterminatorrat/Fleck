import Foundation

public enum AppTheme: String, Codable, CaseIterable, Sendable {
  case system, light, dark
}

public struct AppPreferences: Codable, Equatable, Sendable {
  public static let currentEditorTypographyVersion = 1
  public static let currentPanelSizingVersion = 1

  public var fontFamily: String
  public var fontSize: Double
  public var editorTypographyVersion: Int
  public var accentHex: String
  public var editorTextHex: String?
  public var editorBackgroundHex: String?
  public var panelOpacity: Double
  public var theme: AppTheme
  public var panelWidth: Double
  public var panelHeight: Double
  public var panelSizingVersion: Int
  public var pinnedPanelWidth: Double
  public var pinnedPanelHeight: Double
  public var showFormattingBar: Bool
  public var automaticLists: Bool
  public var launchAtLogin: Bool
  public var shortcuts: [Shortcut]
  public var dictationSpeechEngine: DictationSpeechEngine
  private var legacyDictationShortcut: DictationShortcut
  @available(*, deprecated, message: "Use dictationModifierKey")
  public var dictationShortcut: DictationShortcut {
    get { legacyDictationShortcut }
    set { legacyDictationShortcut = newValue }
  }
  public var dictationModifierKey: DictationModifierKey
  public var dictationCapsuleDock: DictationCapsuleDock
  public var dictationHistoryEnabled: Bool
  public var dictationCapsuleEnabled: Bool
  public var dictationMicrophoneUID: String?
  public var onboardingProgress: OnboardingProgress?

  public init(
    fontFamily: String = "Avenir Next", fontSize: Double = 17,
    editorTypographyVersion: Int = AppPreferences.currentEditorTypographyVersion,
    accentHex: String = "#7C6CF2", editorTextHex: String? = nil,
    editorBackgroundHex: String? = nil, panelOpacity: Double = 0.82,
    theme: AppTheme = .system, panelWidth: Double = 640, panelHeight: Double = 430,
    panelSizingVersion: Int = AppPreferences.currentPanelSizingVersion,
    pinnedPanelWidth: Double = 640, pinnedPanelHeight: Double = 430,
    showFormattingBar: Bool = true, automaticLists: Bool = true,
    launchAtLogin: Bool = false,
    shortcuts: [Shortcut] = Shortcut.defaults,
    dictationSpeechEngine: DictationSpeechEngine = .standard,
    dictationShortcut: DictationShortcut = DictationShortcut(),
    dictationModifierKey: DictationModifierKey = .rightOption,
    dictationCapsuleDock: DictationCapsuleDock = .bottom,
    dictationHistoryEnabled: Bool = true,
    dictationCapsuleEnabled: Bool = true,
    dictationMicrophoneUID: String? = nil,
    onboardingProgress: OnboardingProgress? = nil
  ) {
    self.fontFamily = fontFamily
    self.fontSize = fontSize
    self.editorTypographyVersion = editorTypographyVersion
    self.accentHex = accentHex
    self.editorTextHex = editorTextHex
    self.editorBackgroundHex = editorBackgroundHex
    self.panelOpacity = panelOpacity
    self.theme = theme
    self.panelWidth = Self.clampedPanelDimension(panelWidth, minimum: 380, maximum: 800)
    self.panelHeight = Self.clampedPanelDimension(panelHeight, minimum: 300, maximum: 800)
    self.panelSizingVersion = panelSizingVersion
    self.pinnedPanelWidth = Self.clampedPanelDimension(pinnedPanelWidth, minimum: 480)
    self.pinnedPanelHeight = Self.clampedPanelDimension(pinnedPanelHeight, minimum: 320)
    self.showFormattingBar = showFormattingBar
    self.automaticLists = automaticLists
    self.launchAtLogin = launchAtLogin
    self.shortcuts = shortcuts
    self.dictationSpeechEngine =
      CleanDictationFeatures.enhancedLocalCandidateEnabled
      ? dictationSpeechEngine
      : .standard
    self.legacyDictationShortcut = dictationShortcut
    self.dictationModifierKey = dictationModifierKey
    self.dictationCapsuleDock = dictationCapsuleDock
    self.dictationHistoryEnabled = dictationHistoryEnabled
    self.dictationCapsuleEnabled = dictationCapsuleEnabled
    self.dictationMicrophoneUID = dictationMicrophoneUID
    self.onboardingProgress = onboardingProgress
  }

  private enum CodingKeys: String, CodingKey {
    case fontFamily, fontSize, editorTypographyVersion, accentHex, editorTextHex,
      editorBackgroundHex, panelOpacity, theme, panelWidth, panelHeight, panelSizingVersion,
      pinnedPanelWidth, pinnedPanelHeight, showFormattingBar,
      automaticLists, launchAtLogin, shortcuts, dictationSpeechEngine,
      legacyDictationShortcut = "dictationShortcut", dictationModifierKey,
      dictationCapsuleDock, dictationHistoryEnabled, dictationCapsuleEnabled,
      dictationMicrophoneUID, onboardingProgress
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let decodedFamily =
      try c.decodeIfPresent(String.self, forKey: .fontFamily)
      ?? "Avenir Next"
    let decodedSize =
      try c.decodeIfPresent(Double.self, forKey: .fontSize)
      ?? 17
    let decodedTypographyVersion =
      try c.decodeIfPresent(Int.self, forKey: .editorTypographyVersion)
    let migratesUntouchedTypography =
      decodedTypographyVersion == nil
      && decodedFamily == ".AppleSystemUIFont"
      && decodedSize == 15
    let decodedPanelWidth = Self.decodedSizingField(
      Double.self,
      from: c,
      forKey: .panelWidth,
      fallback: 520
    )
    let decodedPanelHeight = Self.decodedSizingField(
      Double.self,
      from: c,
      forKey: .panelHeight,
      fallback: 430
    )
    let decodedPanelSizingVersion = Self.decodedSizingField(
      Int?.self,
      from: c,
      forKey: .panelSizingVersion,
      fallback: nil
    )
    let migratesUntouchedPanelSize =
      decodedPanelSizingVersion == nil
      && decodedPanelWidth == 520
      && decodedPanelHeight == 430
    let resolvedPanelWidth = migratesUntouchedPanelSize ? 640 : decodedPanelWidth
    let resolvedPanelHeight = decodedPanelHeight
    self.init(
      fontFamily: migratesUntouchedTypography ? "Avenir Next" : decodedFamily,
      fontSize: migratesUntouchedTypography ? 17 : decodedSize,
      editorTypographyVersion:
        decodedTypographyVersion ?? Self.currentEditorTypographyVersion,
      accentHex: try c.decodeIfPresent(String.self, forKey: .accentHex) ?? "#7C6CF2",
      editorTextHex: try c.decodeIfPresent(String.self, forKey: .editorTextHex),
      editorBackgroundHex: try c.decodeIfPresent(String.self, forKey: .editorBackgroundHex),
      panelOpacity: try c.decodeIfPresent(Double.self, forKey: .panelOpacity) ?? 0.82,
      theme: try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system,
      panelWidth: resolvedPanelWidth,
      panelHeight: resolvedPanelHeight,
      panelSizingVersion: decodedPanelSizingVersion ?? Self.currentPanelSizingVersion,
      pinnedPanelWidth: Self.decodedSizingField(
        Double.self,
        from: c,
        forKey: .pinnedPanelWidth,
        fallback: 640
      ),
      pinnedPanelHeight: Self.decodedSizingField(
        Double.self,
        from: c,
        forKey: .pinnedPanelHeight,
        fallback: 430
      ),
      showFormattingBar: try c.decodeIfPresent(Bool.self, forKey: .showFormattingBar) ?? true,
      automaticLists: try c.decodeIfPresent(Bool.self, forKey: .automaticLists) ?? true,
      launchAtLogin: try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
      shortcuts: try c.decodeIfPresent([Shortcut].self, forKey: .shortcuts) ?? Shortcut.defaults,
      dictationSpeechEngine: try c.decodeIfPresent(DictationSpeechEngine.self, forKey: .dictationSpeechEngine) ?? .standard,
      dictationShortcut: try c.decodeIfPresent(
        DictationShortcut.self,
        forKey: .legacyDictationShortcut
      ) ?? DictationShortcut(),
      dictationModifierKey: try c.decodeIfPresent(
        DictationModifierKey.self,
        forKey: .dictationModifierKey
      ) ?? .rightOption,
      dictationCapsuleDock: try c.decodeIfPresent(
        DictationCapsuleDock.self,
        forKey: .dictationCapsuleDock
      ) ?? .bottom,
      dictationHistoryEnabled: try c.decodeIfPresent(Bool.self, forKey: .dictationHistoryEnabled) ?? true,
      dictationCapsuleEnabled: try c.decodeIfPresent(Bool.self, forKey: .dictationCapsuleEnabled) ?? true,
      dictationMicrophoneUID: try c.decodeIfPresent(String.self, forKey: .dictationMicrophoneUID),
      onboardingProgress: try c.decodeIfPresent(
        OnboardingProgress.self,
        forKey: .onboardingProgress
      ))
  }

  private static func clampedPanelDimension(
    _ value: Double,
    minimum: Double,
    maximum: Double? = nil
  ) -> Double {
    guard value.isFinite else { return minimum }
    let clamped = max(value, minimum)
    return maximum.map { min(clamped, $0) } ?? clamped
  }

  private static func decodedSizingField<T: Decodable>(
    _ type: T.Type,
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys,
    fallback: T
  ) -> T {
    (try? container.decodeIfPresent(type, forKey: key)) ?? fallback
  }
}

public struct Shortcut: Identifiable, Codable, Equatable, Sendable {
  public enum Action: String, Codable, CaseIterable, Sendable {
    case togglePanel, newNote, closeNote, nextNote, previousNote
    public var title: String {
      switch self {
      case .togglePanel: "Show or hide notes"
      case .newNote: "New note"
      case .closeNote: "Close note"
      case .nextNote: "Next note"
      case .previousNote: "Previous note"
      }
    }
  }
  public enum Modifier: String, Codable, CaseIterable, Sendable {
    case command, shift, control, option
  }
  public var id: Action { action }
  public var action: Action
  public var key: String?
  public var modifiers: [String]

  public init(action: Action, key: String?, modifiers: [String]) {
    self.action = action
    let normalized = key?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.key = normalized?.isEmpty == false ? normalized : nil
    self.modifiers = Self.normalizedModifiers(modifiers)
  }
  public var isEnabled: Bool { key != nil }
  public var isValid: Bool {
    guard let key else { return modifiers.isEmpty }
    return !key.isEmpty && !modifiers.isEmpty
  }
  public static func normalizedModifiers(_ values: [String]) -> [String] {
    Modifier.allCases.map(\.rawValue).filter { values.contains($0) }
  }
  public static func conflicts(in shortcuts: [Shortcut]) -> Set<Action> {
    var seen: [String: Action] = [:]
    var result = Set<Action>()
    for shortcut in shortcuts where shortcut.isEnabled {
      let signature = shortcut.modifiers.joined(separator: "+") + ":" + (shortcut.key ?? "")
      if let prior = seen[signature] {
        result.insert(prior)
        result.insert(shortcut.action)
      } else {
        seen[signature] = shortcut.action
      }
    }
    return result
  }
  public static let defaults = [
    Shortcut(action: .togglePanel, key: "n", modifiers: ["command", "shift"]),
    Shortcut(action: .newNote, key: "t", modifiers: ["command"]),
    Shortcut(action: .closeNote, key: "w", modifiers: ["command"]),
    Shortcut(action: .nextNote, key: "tab", modifiers: ["control"]),
    Shortcut(action: .previousNote, key: "tab", modifiers: ["control", "shift"]),
  ]
}
