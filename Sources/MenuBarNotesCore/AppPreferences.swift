import Foundation

public struct AppPreferences: Codable, Equatable, Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public var accentHex: String
    public var panelOpacity: Double
    public var showFormattingBar: Bool
    public var automaticLists: Bool
    public var shortcuts: [Shortcut]

    public init(
        fontFamily: String = ".AppleSystemUIFont",
        fontSize: Double = 15,
        accentHex: String = "#7C6CF2",
        panelOpacity: Double = 0.82,
        showFormattingBar: Bool = true,
        automaticLists: Bool = true,
        shortcuts: [Shortcut] = Shortcut.defaults
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.accentHex = accentHex
        self.panelOpacity = panelOpacity
        self.showFormattingBar = showFormattingBar
        self.automaticLists = automaticLists
        self.shortcuts = shortcuts
    }
}

public struct Shortcut: Identifiable, Codable, Equatable, Sendable {
    public enum Action: String, Codable, CaseIterable, Sendable {
        case togglePanel
        case newNote
        case closeNote
        case nextNote
        case previousNote

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

    public var id: Action { action }
    public var action: Action
    public var key: String?
    public var modifiers: [String]

    public init(action: Action, key: String?, modifiers: [String]) {
        self.action = action
        self.key = key
        self.modifiers = modifiers
    }

    public static let defaults: [Shortcut] = [
        Shortcut(action: .togglePanel, key: "n", modifiers: ["command", "shift"]),
        Shortcut(action: .newNote, key: "t", modifiers: ["command"]),
        Shortcut(action: .closeNote, key: "w", modifiers: ["command"]),
        Shortcut(action: .nextNote, key: "tab", modifiers: ["control"]),
        Shortcut(action: .previousNote, key: "tab", modifiers: ["control", "shift"]),
    ]
}
