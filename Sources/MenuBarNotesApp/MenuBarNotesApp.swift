#if os(macOS)
  import AppKit
  import SwiftUI
  import MenuBarNotesCore

  @main
  struct MenuBarNotesApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
      MenuBarExtra("Motes", systemImage: "note.text") {
        NotesPanel()
          .environmentObject(appState)
          .preferredColorScheme(colorScheme)
      }
      .menuBarExtraStyle(.window)

      Window("Motes", id: "pinned-notes") {
        NotesPanel(isPinned: true)
          .environmentObject(appState)
          .preferredColorScheme(colorScheme)
          .background(FloatingWindowConfigurator())
      }
      .windowResizability(.contentSize)

      Settings {
        SettingsView()
          .environmentObject(appState)
          .frame(width: 520, height: 440)
          .background(FloatingWindowConfigurator())
      }
    }

    private var colorScheme: ColorScheme? {
      switch appState.preferences.theme {
      case .system: nil
      case .light: .light
      case .dark: .dark
      }
    }
  }

  private struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      configure(view)
      return view
    }

    func updateNSView(_ view: NSView, context: Context) {
      configure(view)
    }

    private func configure(_ view: NSView) {
      DispatchQueue.main.async {
        view.window?.level = .floating
        view.window?.hidesOnDeactivate = false
      }
    }
  }
#else
  import Foundation

  @main
  enum MenuBarNotesApp {
    static func main() {
      print("Motes is a native macOS application. Build this package on macOS 14 or later.")
    }
  }
#endif
