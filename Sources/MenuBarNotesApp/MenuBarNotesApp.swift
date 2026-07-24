#if os(macOS)
  import AppKit
  import SwiftUI
  import MenuBarNotesCore

  @main
  struct MenuBarNotesApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
      MenuBarExtra("Menu Bar Notes", systemImage: "note.text") {
        NotesPanel()
          .environmentObject(appState)
          .preferredColorScheme(colorScheme)
      }
      .menuBarExtraStyle(.window)

      Window("Menu Bar Notes", id: "pinned-notes") {
        NotesPanel()
          .environmentObject(appState)
          .preferredColorScheme(colorScheme)
          .background(PinnedWindowConfigurator())
      }
      .windowResizability(.contentSize)

      Settings {
        SettingsView()
          .environmentObject(appState)
          .frame(width: 520, height: 440)
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

  private struct PinnedWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      DispatchQueue.main.async { configure(view.window) }
      return view
    }

    func updateNSView(_ view: NSView, context: Context) {
      DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
      guard let window else { return }
      window.level = .floating
      window.collectionBehavior.insert(.canJoinAllSpaces)
      window.isMovableByWindowBackground = true
    }
  }
#else
  import Foundation

  @main
  enum MenuBarNotesApp {
    static func main() {
      print("MenuBarNotes is a native macOS application. Build this package on macOS 14 or later.")
    }
  }
#endif
