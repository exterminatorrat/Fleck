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
        TextField("Editor text color", text: optionalPreferenceBinding(\.editorTextHex))
          .help("Leave empty to follow the system theme")
        TextField("Editor background", text: optionalPreferenceBinding(\.editorBackgroundHex))
          .help("Leave empty for transparent glass")
        Slider(value: preferenceBinding(\.panelOpacity), in: 0.55...1) {
          Text("Glass opacity")
        }
        Picker("Theme", selection: preferenceBinding(\.theme)) {
          ForEach(AppTheme.allCases, id: \.self) { theme in
            Text(theme.rawValue.capitalized).tag(theme)
          }
        }
        HStack {
          Stepper(
            "Width: \(Int(appState.preferences.panelWidth))",
            value: preferenceBinding(\.panelWidth), in: 380...800, step: 20)
          Stepper(
            "Height: \(Int(appState.preferences.panelHeight))",
            value: preferenceBinding(\.panelHeight), in: 300...800, step: 20)
        }
      }
    }

    private var editing: some View {
      Section("Behavior") {
        Toggle("Show formatting bar", isOn: preferenceBinding(\.showFormattingBar))
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
              TextField("Key", text: shortcutKeyBinding(action))
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
              Menu(shortcutLabel(shortcut)) {
                ForEach(Shortcut.Modifier.allCases, id: \.self) { modifier in
                  Toggle(
                    modifier.rawValue.capitalized, isOn: modifierBinding(modifier, action: action))
                }
              }
              Button(shortcut?.key == nil ? "Restore" : "Remove") {
                setShortcutEnabled(action, enabled: shortcut?.key == nil)
              }
            }
            if conflicts.contains(action) {
              Label("Conflicts with another shortcut", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
            }
          }
        }
        Text(
          "Choose a key and one or more modifiers. Conflicting combinations are highlighted and disabled shortcuts can be restored at any time."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
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

    private func optionalPreferenceBinding(_ keyPath: WritableKeyPath<AppPreferences, String?>)
      -> Binding<String>
    {
      Binding(
        get: { appState.preferences[keyPath: keyPath] ?? "" },
        set: { value in
          appState.updatePreferences {
            $0[keyPath: keyPath] =
              value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? nil : value
          }
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

    private func shortcutKeyBinding(_ action: Shortcut.Action) -> Binding<String> {
      Binding(
        get: {
          appState.preferences.shortcuts.first(where: { $0.action == action })?.key ?? ""
        },
        set: { key in
          appState.updatePreferences { preferences in
            guard let index = preferences.shortcuts.firstIndex(where: { $0.action == action })
            else { return }
            let old = preferences.shortcuts[index]
            preferences.shortcuts[index] = Shortcut(
              action: action, key: key, modifiers: old.modifiers)
          }
        })
    }

    private func modifierBinding(_ modifier: Shortcut.Modifier, action: Shortcut.Action) -> Binding<
      Bool
    > {
      Binding(
        get: {
          appState.preferences.shortcuts.first(where: { $0.action == action })?.modifiers.contains(
            modifier.rawValue) == true
        },
        set: { enabled in
          appState.updatePreferences { preferences in
            guard let index = preferences.shortcuts.firstIndex(where: { $0.action == action })
            else { return }
            let old = preferences.shortcuts[index]
            var modifiers = old.modifiers.filter { $0 != modifier.rawValue }
            if enabled { modifiers.append(modifier.rawValue) }
            preferences.shortcuts[index] = Shortcut(
              action: action, key: old.key, modifiers: modifiers)
          }
        })
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
