#if os(macOS)
  import AppKit
  import SwiftUI
  import MenuBarNotesCore
  import UniformTypeIdentifiers

  struct NotesPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @StateObject private var editorCommands = EditorCommands()
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: NoteFileDocument?
    @State private var exportType: UTType = .markdownText
    @State private var exportFilename = "Untitled.md"

    var body: some View {
      VStack(spacing: 0) {
        header
        tabStrip
        Divider().opacity(0.35)
        editor
        if let error = appState.saveError {
          Text("Could not save: \(error)")
            .font(.caption)
            .foregroundStyle(.red)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .frame(
        width: appState.preferences.panelWidth,
        height: appState.preferences.panelHeight
      )
      .background {
        Rectangle()
          .fill(.ultraThinMaterial)
          .opacity(appState.preferences.panelOpacity)
      }
      .tint(Color(hex: appState.preferences.accentHex))
      .background(
        ShortcutMonitor(shortcuts: appState.preferences.shortcuts, action: performShortcut)
          .frame(width: 0, height: 0)
      )
      .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: [.plainText, .markdownText],
        allowsMultipleSelection: true,
        onCompletion: importFiles
      )
      .fileExporter(
        isPresented: $isExporting,
        document: exportDocument,
        contentType: exportType,
        defaultFilename: exportFilename
      ) { result in
        if case .failure(let error) = result {
          appState.saveError = "Export failed: \(error.localizedDescription)"
        }
      }
    }

    private var header: some View {
      HStack(spacing: 10) {
        Label("Notes", systemImage: "note.text")
          .font(.headline)
        Spacer()
        Button {
          appState.addNote()
        } label: {
          Image(systemName: "plus")
        }
        .keyboardShortcut("t", modifiers: .command)
        .help("New note")

        Button {
          openWindow(id: "pinned-notes")
        } label: {
          Image(systemName: "pin")
        }
        .help("Open as a floating window")

        Menu {
          Button("Import…", systemImage: "square.and.arrow.down") {
            isImporting = true
          }
          Divider()
          Button("Export Markdown…") { startExport(.markdown) }
          Button("Export Plain Text…") { startExport(.plainText) }
          Button("Export Rich Text…") { startExport(.richText) }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .help("Import or export")

        Button {
          openSettings()
        } label: {
          Image(systemName: "slider.horizontal.3")
        }
        .help("Customize")
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
    }

    private var tabStrip: some View {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(appState.workspace.notes) { note in
            Button {
              appState.select(note.id)
            } label: {
              HStack(spacing: 4) {
                if note.isPinned {
                  Image(systemName: "pin.fill")
                    .font(.caption2)
                }
                Text(note.displayTitle).lineLimit(1)
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(
                note.id == appState.workspace.selectedNoteID
                  ? Color.accentColor.opacity(0.18)
                  : Color.clear,
                in: Capsule()
              )
            }
            .buttonStyle(.plain)
            .draggable(note.id.uuidString)
            .dropDestination(for: String.self) { identifiers, _ in
              guard let identifier = identifiers.first,
                let id = UUID(uuidString: identifier),
                let destination = appState.workspace.notes.firstIndex(where: { $0.id == note.id })
              else { return false }
              appState.moveNote(id, to: destination)
              return true
            }
            .contextMenu {
              Button(
                note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin"
              ) {
                appState.togglePinned(note.id)
              }
              Button("Move Left", systemImage: "arrow.left") {
                move(note, offset: -1)
              }
              Button("Move Right", systemImage: "arrow.right") {
                move(note, offset: 1)
              }
              Divider()
              Button("Close Note", systemImage: "xmark", role: .destructive) {
                appState.select(note.id)
                appState.deleteSelectedNote()
              }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
      }
    }

    private func performShortcut(_ action: Shortcut.Action) {
      switch action {
      case .togglePanel:
        NSApp.keyWindow?.orderOut(nil)
      case .newNote:
        appState.addNote()
      case .closeNote:
        appState.deleteSelectedNote()
      case .nextNote:
        appState.selectAdjacentNote(forward: true)
      case .previousNote:
        appState.selectAdjacentNote(forward: false)
      }
    }

    private func move(_ note: Note, offset: Int) {
      guard let index = appState.workspace.notes.firstIndex(where: { $0.id == note.id }) else {
        return
      }
      appState.moveNote(note.id, to: index + offset)
    }

    private func startExport(_ format: NoteExportFormat) {
      guard let note = appState.selectedNote else { return }
      let export = NoteExport(note: note, format: format)
      exportDocument = NoteFileDocument(data: export.data)
      exportFilename = export.suggestedFilename
      switch format {
      case .plainText: exportType = .plainText
      case .markdown: exportType = .markdownText
      case .richText: exportType = .rtf
      }
      isExporting = true
    }

    private func importFiles(_ result: Result<[URL], Error>) {
      do {
        for url in try result.get() {
          let accessing = url.startAccessingSecurityScopedResource()
          defer { if accessing { url.stopAccessingSecurityScopedResource() } }
          let note = try NoteImport.note(
            from: Data(contentsOf: url),
            filename: url.lastPathComponent
          )
          appState.importNote(note)
        }
        appState.saveError = nil
      } catch {
        appState.saveError = "Import failed: \(error.localizedDescription)"
      }
    }

    @ViewBuilder
    private var editor: some View {
      if let note = appState.selectedNote {
        VStack(spacing: 0) {
          if appState.preferences.showFormattingBar {
            FormattingBar(commands: editorCommands)
          }
          TextField(
            "Note title",
            text: Binding(
              get: { note.title },
              set: { appState.updateSelected(title: $0) }
            )
          )
          .textFieldStyle(.plain)
          .font(.title3.weight(.semibold))
          .padding(.horizontal, 16)
          .padding(.top, 12)

          NativeRichTextEditor(
            text: Binding(
              get: { note.body },
              set: { appState.updateSelected(body: $0) }
            ),
            richTextRTF: Binding(
              get: { note.richTextRTF },
              set: { appState.updateSelectedRichTextRTF($0) }
            ),
            fontFamily: appState.preferences.fontFamily,
            fontSize: appState.preferences.fontSize,
            textColorHex: appState.preferences.editorTextHex,
            backgroundColorHex: appState.preferences.editorBackgroundHex,
            automaticLists: appState.preferences.automaticLists,
            commands: editorCommands
          )
          .id(note.id)
          .padding(10)
        }
      }
    }
  }

  private struct FormattingBar: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var commands: EditorCommands

    var body: some View {
      HStack(spacing: 13) {
        Button("Undo", systemImage: "arrow.uturn.backward") { commands.undo() }
          .keyboardShortcut("z", modifiers: .command)
        Button("Redo", systemImage: "arrow.uturn.forward") { commands.redo() }
          .keyboardShortcut("z", modifiers: [.command, .shift])
        Divider().frame(height: 15)
        Button("Bold", systemImage: "bold") { commands.toggleBold() }
          .keyboardShortcut("b", modifiers: .command)
        Button("Italic", systemImage: "italic") { commands.toggleItalic() }
          .keyboardShortcut("i", modifiers: .command)
        Button("Underline", systemImage: "underline") { commands.toggleUnderline() }
          .keyboardShortcut("u", modifiers: .command)
        Button("Strikethrough", systemImage: "strikethrough") { commands.toggleStrikethrough() }
        Menu {
          ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
            Button(family) { commands.applyFontFamily(family) }
          }
        } label: {
          Image(systemName: "textformat")
        }
        .help("Font")
        Button("Bullets", systemImage: "list.bullet") {
          commands.applyList(.bullets)
        }
        Button("Numbers", systemImage: "list.number") {
          commands.applyList(.numbers)
        }
        Spacer()
        Button("Delete", systemImage: "trash", role: .destructive) {
          appState.deleteSelectedNote()
        }
        .keyboardShortcut("w", modifiers: .command)
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.plain)
      .padding(.horizontal, 16)
      .padding(.vertical, 9)
      .background(.thinMaterial)
    }
  }

  extension Color {
    fileprivate init(hex: String) {
      let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
      let value = UInt64(cleaned, radix: 16) ?? 0x7C6CF2
      self.init(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
      )
    }
  }
#endif
