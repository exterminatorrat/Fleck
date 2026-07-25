#if os(macOS)
  import AppKit
  import SwiftUI
  import MenuBarNotesCore
  import UniformTypeIdentifiers

  struct NotesPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    var isPinned = false
    @StateObject private var editorCommands = EditorCommands()
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var isShowingTrash = false
    @State private var notePendingDeletion: Note?
    @State private var exportDocument: NoteFileDocument?
    @State private var exportType = NoteFileDocument.markdownContentType
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
        allowedContentTypes: [.plainText, NoteFileDocument.markdownContentType],
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
      .sheet(isPresented: $isShowingTrash) {
        TrashView()
          .environmentObject(appState)
      }
      .overlay {
        if let notePendingDeletion {
          DeleteConfirmationOverlay(
            note: notePendingDeletion,
            onCancel: { self.notePendingDeletion = nil },
            onConfirm: { confirmDeletion(notePendingDeletion) }
          )
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

        if isPinned {
          Image(systemName: "pin.fill")
            .frame(width: 22, height: 22)
            .foregroundStyle(.tint)
            .accessibilityLabel("Pinned")
            .help("This window stays open until you close it")
        } else {
          Button {
            presentPersistentWindow {
              openWindow(id: "pinned-notes")
            }
          } label: {
            Image(systemName: "pin")
          }
          .help("Pin notes on screen")
        }

        Menu {
          Button("Import…", systemImage: "square.and.arrow.down") {
            isImporting = true
          }
          Divider()
          Button("Export Markdown…") { startExport(.markdown) }
          Button("Export Plain Text…") { startExport(.plainText) }
          Button("Export Rich Text…") { startExport(.richText) }
          Divider()
          Button("Trash…", systemImage: "trash") {
            isShowingTrash = true
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Options")
        .help("Options")

        Button {
          presentPersistentWindow {
            openSettings()
          }
        } label: {
          Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("Customize")
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
              Button("Move to Trash", systemImage: "trash", role: .destructive) {
                requestDeletion(note)
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
        if let note = appState.selectedNote {
          requestDeletion(note)
        }
      case .nextNote:
        appState.selectAdjacentNote(forward: true)
      case .previousNote:
        appState.selectAdjacentNote(forward: false)
      }
    }

    private func requestDeletion(_ note: Note) {
      notePendingDeletion = note
    }

    private func confirmDeletion(_ note: Note) {
      notePendingDeletion = nil
      appState.moveToTrash(note.id)
    }

    private func presentPersistentWindow(_ present: () -> Void) {
      NSApp.activate()
      present()
      DispatchQueue.main.async {
        NSApp.activate()
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
      case .markdown: exportType = NoteFileDocument.markdownContentType
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
            FormattingBar(
              commands: editorCommands,
              onDelete: {
                if let note = appState.selectedNote {
                  requestDeletion(note)
                }
              }
            )
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
          .padding(.vertical, 10)
        }
      }
    }
  }

  private struct DeleteConfirmationOverlay: View {
    let note: Note
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
      ZStack {
        Color.black.opacity(0.28)
          .ignoresSafeArea()

        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Move “\(note.displayTitle)” to Trash?")
              .font(.headline)
            Text("This note can be restored from Trash for 30 days.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }

          HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
            Button("Confirm", role: .destructive, action: onConfirm)
              .keyboardShortcut(.defaultAction)
          }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 20, y: 8)
      }
    }
  }

  private struct FormattingBar: View {
    @ObservedObject var commands: EditorCommands
    let onDelete: () -> Void

    var body: some View {
      HStack(spacing: 8) {
        Button {
          commands.undo()
        } label: {
          ToolbarIconLabel(systemImage: "arrow.uturn.backward")
        }
        .accessibilityLabel("Undo")
          .keyboardShortcut("z", modifiers: .command)
        Button {
          commands.redo()
        } label: {
          ToolbarIconLabel(systemImage: "arrow.uturn.forward")
        }
        .accessibilityLabel("Redo")
          .keyboardShortcut("z", modifiers: [.command, .shift])
        Divider().frame(height: 15)
        Button {
          commands.toggleBold()
        } label: {
          ToolbarIconLabel(systemImage: "bold", isActive: commands.isBold)
        }
        .accessibilityLabel("Bold")
          .keyboardShortcut("b", modifiers: .command)
          .accessibilityValue(commands.isBold ? "On" : "Off")
        Button {
          commands.toggleItalic()
        } label: {
          ToolbarIconLabel(systemImage: "italic", isActive: commands.isItalic)
        }
        .accessibilityLabel("Italic")
          .keyboardShortcut("i", modifiers: .command)
          .accessibilityValue(commands.isItalic ? "On" : "Off")
        Button {
          commands.toggleUnderline()
        } label: {
          ToolbarIconLabel(systemImage: "underline", isActive: commands.isUnderlined)
        }
        .accessibilityLabel("Underline")
          .keyboardShortcut("u", modifiers: .command)
          .accessibilityValue(commands.isUnderlined ? "On" : "Off")
        Button {
          commands.toggleStrikethrough()
        } label: {
          ToolbarIconLabel(systemImage: "strikethrough")
        }
        .accessibilityLabel("Strikethrough")
        Menu {
          ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
            Button(family) { commands.applyFontFamily(family) }
          }
        } label: {
          ToolbarIconLabel(systemImage: "textformat")
        }
        .help("Font")
        .accessibilityLabel("Font")
        Button {
          commands.applyList(.bullets)
        } label: {
          ToolbarIconLabel(systemImage: "list.bullet")
        }
        .accessibilityLabel("Bullets")
        Button {
          commands.applyList(.numbers)
        } label: {
          ToolbarIconLabel(systemImage: "list.number")
        }
        .accessibilityLabel("Numbers")
        Spacer()
        Button(role: .destructive) {
          onDelete()
        } label: {
          ToolbarIconLabel(systemImage: "trash")
        }
        .accessibilityLabel("Delete")
        .keyboardShortcut("w", modifiers: .command)
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 16)
      .padding(.vertical, 9)
      .background(.thinMaterial)
    }
  }

  private struct ToolbarIconLabel: View {
    let systemImage: String
    var isActive = false

    var body: some View {
      Image(systemName: systemImage)
        .frame(width: 28, height: 26)
        .background(
          isActive ? Color.accentColor.opacity(0.24) : .clear,
          in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }
  }

  extension Color {
    init(hex: String) {
      let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
      let value = UInt64(cleaned, radix: 16) ?? 0x7C6CF2
      self.init(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
      )
    }

    var hexString: String? {
      guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
      return String(
        format: "#%02X%02X%02X",
        Int((color.redComponent * 255).rounded()),
        Int((color.greenComponent * 255).rounded()),
        Int((color.blueComponent * 255).rounded())
      )
    }
  }
#endif
