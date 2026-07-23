#if os(macOS)
import AppKit
import SwiftUI
import MenuBarNotesCore

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSection = SettingsSection.appearance

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case appearance = "Appearance"
        case editing = "Editing"
        case shortcuts = "Shortcuts"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings section", selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Form {
                switch selectedSection {
                case .appearance:
                    appearance
                case .editing:
                    editing
                case .shortcuts:
                    shortcuts
                }
            }
            .formStyle(.grouped)
        }
    }

    private var appearance: some View {
        Section("Editor") {
            Picker("Font", selection: preferenceBinding(\.fontFamily)) {
                Text("System").tag(".AppleSystemUIFont")
                ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Stepper(
                "Font size: \(Int(appState.preferences.fontSize)) pt",
                value: preferenceBinding(\.fontSize),
                in: 10...36
            )
            TextField("Accent color", text: preferenceBinding(\.accentHex))
                .help("Enter a hexadecimal color such as #7C6CF2")
            Slider(value: preferenceBinding(\.panelOpacity), in: 0.55...1) {
                Text("Glass opacity")
            }
        }
    }

    private var editing: some View {
        Section("Behavior") {
            Toggle("Show formatting bar", isOn: preferenceBinding(\.showFormattingBar))
            Toggle("Create lists automatically", isOn: preferenceBinding(\.automaticLists))
            Text("Notes are stored locally as readable Markdown files with a small JSON workspace manifest.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        Section("Keyboard shortcuts") {
            ForEach(Shortcut.Action.allCases, id: \.self) { action in
                let shortcut = appState.preferences.shortcuts.first(where: { $0.action == action })
                HStack {
                    Text(action.title)
                    Spacer()
                    Text(shortcutLabel(shortcut))
                        .foregroundStyle(.secondary)
                    Button(shortcut?.key == nil ? "Restore" : "Remove") {
                        setShortcutEnabled(action, enabled: shortcut?.key == nil)
                    }
                }
            }
            Text("Shortcut recording and global registration are part of the next implementation milestone. Every shortcut can already be disabled or restored in the saved preferences model.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { appState.preferences[keyPath: keyPath] },
            set: { value in
                appState.updatePreferences { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func setShortcutEnabled(_ action: Shortcut.Action, enabled: Bool) {
        appState.updatePreferences { preferences in
            guard let index = preferences.shortcuts.firstIndex(where: { $0.action == action }) else { return }
            if enabled, let defaultShortcut = Shortcut.defaults.first(where: { $0.action == action }) {
                preferences.shortcuts[index] = defaultShortcut
            } else {
                preferences.shortcuts[index].key = nil
                preferences.shortcuts[index].modifiers = []
            }
        }
    }

    private func shortcutLabel(_ shortcut: Shortcut?) -> String {
        guard let shortcut, let key = shortcut.key else { return "Not set" }
        let symbols = shortcut.modifiers.map { modifier in
            switch modifier {
            case "command": "⌘"
            case "shift": "⇧"
            case "control": "⌃"
            case "option": "⌥"
            default: modifier
            }
        }.joined()
        return symbols + key.uppercased()
    }
}
#endif
