#if os(macOS)
  import AppKit
  import SwiftUI
  import FleckCore
  import UniformTypeIdentifiers

  enum TabDragReorder {
    static let dropOperation: DropOperation = .move

    static func makeContentType(id: UUID = UUID()) -> UTType {
      let token = id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
      return UTType(exportedAs: "com.menubarnotes.tabdrag.session\(token)")
    }

    static func destinationIndex(
      draggedID: UUID?,
      over destinationID: UUID,
      in noteIDs: [UUID]
    ) -> Int? {
      guard let draggedID,
        draggedID != destinationID,
        noteIDs.contains(draggedID),
        let destination = noteIDs.firstIndex(of: destinationID)
      else { return nil }
      return destination
    }

    static func itemProvider(for noteID: UUID, contentType: UTType) -> NSItemProvider {
      let provider = NSItemProvider()
      let data = Data(noteID.uuidString.utf8)
      provider.registerDataRepresentation(
        forTypeIdentifier: contentType.identifier,
        visibility: .ownProcess
      ) { completion in
        completion(data, nil)
        return nil
      }
      return provider
    }

    @discardableResult
    static func performLiveMove(
      draggedID: UUID?,
      over destinationID: UUID,
      currentNoteIDs: () -> [UUID],
      move: (UUID, Int) -> Void
    ) -> Bool {
      guard let draggedID,
        let destination = destinationIndex(
          draggedID: draggedID,
          over: destinationID,
          in: currentNoteIDs()
        )
      else { return false }
      move(draggedID, destination)
      return true
    }
  }

  struct NotesPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var dictationRuntime: DictationRuntime
    let isPinned: Bool
    @StateObject private var editorCommands = EditorCommands()
    @Namespace private var selectedTabHighlight
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var isShowingTrash = false
    @State private var isShowingDictationHistory = false
    @State private var isShowingAgentActivity = false
    @State private var notePendingDeletion: Note?
    @State private var notePendingAgentShare: Note?
    @State private var exportDocument: NoteFileDocument?
    @State private var exportType = NoteFileDocument.markdownContentType
    @State private var exportFilename = "Untitled.md"
    @State private var draggedNoteID: UUID?
    @State private var tabDragContentType = TabDragReorder.makeContentType()

    init(dictationRuntime: DictationRuntime, isPinned: Bool = false) {
      self.dictationRuntime = dictationRuntime
      self.isPinned = isPinned
    }

    var body: some View {
      VStack(spacing: 0) {
        if let migrationError = appState.startupMigrationError {
          migrationFailure(migrationError)
        } else {
          header
          tabStrip
          Divider().opacity(0.35)
          if let failure = dictationRuntime.captureFailure {
            HStack(spacing: 8) {
              Label(failure.message, systemImage: "exclamationmark.triangle")
                .font(.caption)
              Spacer()
              ForEach(failure.actions, id: \.pane) { action in
                Button(action.title) {
                  dictationRuntime.openSystemSettings(action)
                }
                .accessibilityLabel(action.title)
              }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.35))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dictation unavailable")
          }
          if let recoveryAction = dictationRuntime.recoveryAction {
            HStack(spacing: 8) {
              Label("Dictation recovery", systemImage: "waveform.badge.exclamationmark")
                .font(.caption)
              Spacer()
              Button(recoveryAction.title) {
                Task { await dictationRuntime.performRecoveryAction() }
              }
              .keyboardShortcut("r", modifiers: [.command, .shift])
              .disabled(!dictationRuntime.recoveryCommand.isEnabled)
              .accessibilityLabel(recoveryAction.accessibilityLabel)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.35))
          }
          if let banner = appState.agentBannerPresentation {
            AgentChangeBanner(
              presentation: banner,
              motion: motion,
              onUndo: { Task { await appState.undoLatestAgentChange() } }
            )
            .animation(motion.quick, value: banner)
          }
          editor
          if let error = appState.saveError {
            Text("Could not save: \(error)")
              .font(.caption)
              .foregroundStyle(.red)
              .padding(8)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
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
        TrashView(onDone: { isShowingTrash = false })
          .environmentObject(appState)
      }
      .sheet(isPresented: $isShowingDictationHistory) {
        DictationHistoryView(
          history: dictationRuntime.historyController,
          onOpenDestination: openHistoryDestination
        )
      }
      .sheet(isPresented: $isShowingAgentActivity) {
        AgentActivityView { noteID in
          appState.select(noteID)
          isShowingAgentActivity = false
        }
        .environmentObject(appState)
      }
      .confirmationDialog(
        "Allow authorized agents to read and edit this note?",
        isPresented: Binding(
          get: { notePendingAgentShare != nil },
          set: { if !$0 { notePendingAgentShare = nil } }
        )
      ) {
        Button("Allow Agent Access") {
          guard let note = notePendingAgentShare else { return }
          notePendingAgentShare = nil
          appState.confirmFirstAgentShare(noteID: note.id)
        }
        Button("Cancel", role: .cancel) {
          notePendingAgentShare = nil
        }
      } message: {
        Text("Every authorized local integration will be able to read and edit this note.")
      }
      .onAppear {
        dictationRuntime.registerEditor(editorCommands)
      }
      .onDisappear {
        dictationRuntime.unregisterEditor(editorCommands)
      }
      .overlay {
        ZStack {
          if let notePendingDeletion {
            DeleteConfirmationOverlay(
              note: notePendingDeletion,
              onCancel: { self.notePendingDeletion = nil },
              onConfirm: { confirmDeletion(notePendingDeletion) }
            )
            .transition(
              .opacity.combined(
                with: .scale(scale: reduceMotion ? 1 : 0.985)
              )
            )
          }
        }
        .animation(motion.standard, value: notePendingDeletion?.id)
      }
    }

    private func migrationFailure(
      _ error: FleckProductMigrationError
    ) -> some View {
      VStack(spacing: 12) {
        Image(systemName: "externaldrive.badge.exclamationmark")
          .font(.system(size: 28))
          .foregroundStyle(.orange)
        Text("Fleck needs your help")
          .font(.headline)
        Text(
          "Fleck found both legacy and current note data. Nothing was changed. "
            + "Close Fleck and resolve the two Application Support folders "
            + "before reopening it."
        )
        .font(.callout)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        Text(String(describing: error))
          .font(.caption2.monospaced())
          .foregroundStyle(.tertiary)
          .textSelection(.enabled)
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Fleck data migration requires attention")
    }

    private var header: some View {
      HStack(spacing: 10) {
        Label("Motes", systemImage: "note.text")
          .font(.headline)
        Spacer()
        SaveFeedbackView(status: appState.saveStatus, motion: motion)
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
          Button("Dictation History", systemImage: "waveform") {
            isShowingDictationHistory = true
          }
          Button("Agent Activity", systemImage: "clock.arrow.circlepath") {
            isShowingAgentActivity = true
          }
          if let note = appState.selectedNote {
            Toggle(
              "Allow Agent Access",
              isOn: Binding(
                get: { note.agentAccess },
                set: { requestAgentAccess(note, enabled: $0) }
              )
            )
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
                if note.agentAccess {
                  Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption2)
                    .accessibilityLabel(AgentSharingPresentation.sharedBadgeAccessibilityLabel)
                }
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background {
                if note.id == appState.workspace.selectedNoteID {
                  Capsule()
                    .fill(tabColor(for: note, opacity: 0.22))
                    .matchedGeometryEffect(id: "selected-tab", in: selectedTabHighlight)
                } else if note.tabColorHex != nil {
                  Capsule()
                    .fill(tabColor(for: note, opacity: 0.10))
                }
              }
            }
            .buttonStyle(.plain)
            .transition(
              .opacity.combined(
                with: .offset(x: motion.offset)
              )
            )
            .onDrag {
              draggedNoteID = note.id
              return TabDragReorder.itemProvider(for: note.id, contentType: tabDragContentType)
            }
            .onDrop(
              of: [tabDragContentType],
              delegate: TabDropDelegate(
                destinationID: note.id,
                currentNoteIDs: { appState.workspace.notes.map(\.id) },
                draggedNoteID: $draggedNoteID,
                move: appState.moveNote
              )
            )
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
              Menu("Tab Color", systemImage: "paintpalette") {
                ForEach(TabColorOption.all) { option in
                  Button {
                    appState.select(note.id)
                    appState.setSelectedTabColor(option.hex)
                  } label: {
                    HStack {
                      Label {
                        Text(option.name)
                      } icon: {
                        if let swatchImage = option.swatchImage {
                          Image(nsImage: swatchImage)
                        } else {
                          Image(systemName: "circle.slash")
                        }
                      }
                      if note.tabColorHex == option.hex {
                        Image(systemName: "checkmark")
                      }
                    }
                  }
                }
              }
              Toggle(
                "Allow Agent Access",
                isOn: Binding(
                  get: { note.agentAccess },
                  set: { requestAgentAccess(note, enabled: $0) }
                )
              )
              Divider()
              Button("Move to Trash", systemImage: "trash", role: .destructive) {
                requestDeletion(note)
              }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
        .animation(motion.spatial, value: appState.workspace.selectedNoteID)
        .animation(motion.spatial, value: appState.workspace.notes.map(\.id))
      }
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private func tabColor(for note: Note, opacity: Double) -> Color {
      guard let hex = note.tabColorHex else {
        return Color.accentColor.opacity(opacity)
      }
      let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
      guard cleaned.count == 6, UInt64(cleaned, radix: 16) != nil else {
        return Color.accentColor.opacity(opacity)
      }
      return Color(hex: hex).opacity(opacity)
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

    private func requestAgentAccess(_ note: Note, enabled: Bool) {
      guard enabled else {
        appState.setAgentAccess(noteID: note.id, enabled: false)
        return
      }
      if AgentSharingPresentation(
        note: note,
        hasConfirmedFirstShare: appState.hasConfirmedFirstAgentShare
      ).requiresEnableConfirmation {
        notePendingAgentShare = note
      } else {
        appState.setAgentAccess(noteID: note.id, enabled: true)
      }
    }

    private func confirmDeletion(_ note: Note) {
      notePendingDeletion = nil
      appState.moveToTrash(note.id)
    }

    private func openHistoryDestination(_ noteID: UUID) {
      guard appState.workspace.notes.contains(where: { $0.id == noteID }) else { return }
      appState.select(noteID)
      isShowingDictationHistory = false
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
              dictationRuntime: dictationRuntime,
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
            text: note.body,
            richTextRTF: note.richTextRTF,
            onChange: { body, richTextRTF in
              appState.updateSelected(body: body, richTextRTF: richTextRTF)
            },
            fontFamily: appState.preferences.fontFamily,
            fontSize: appState.preferences.fontSize,
            textColorHex: appState.preferences.editorTextHex,
            backgroundColorHex: appState.preferences.editorBackgroundHex,
            accentColorHex: appState.preferences.accentHex,
            reduceMotion: reduceMotion,
            automaticLists: appState.preferences.automaticLists,
            commands: editorCommands
          )
          .id(note.id)
          .padding(.vertical, 10)
        }
      }
    }
  }

  struct TabColorOption: Identifiable {
    let name: String
    let hex: String?

    var id: String { hex ?? "none" }

    var swatchImage: NSImage? {
      guard let hex else { return nil }
      let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
        NSColor(Color(hex: hex)).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        return true
      }
      image.isTemplate = false
      return image
    }

    static let all = [
      TabColorOption(name: "None", hex: nil),
      TabColorOption(name: "Red", hex: "#FF4245"),
      TabColorOption(name: "Orange", hex: "#FF9230"),
      TabColorOption(name: "Yellow", hex: "#FFD600"),
      TabColorOption(name: "Green", hex: "#30D158"),
      TabColorOption(name: "Blue", hex: "#0091FF"),
      TabColorOption(name: "Purple", hex: "#DB34F2"),
      TabColorOption(name: "Pink", hex: "#FF375F"),
      TabColorOption(name: "Gray", hex: "#98989D"),
    ]
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var commands: EditorCommands
    @ObservedObject var dictationRuntime: DictationRuntime
    let onDelete: () -> Void

    var body: some View {
      HStack(spacing: 8) {
        Menu {
          Button("Cancel Dictation", role: .destructive) {
            Task { await dictationRuntime.cancel() }
          }
          .disabled(!dictationRuntime.canCancel)
        } label: {
          ToolbarIconLabel(
            systemImage: dictationRuntime.microphoneSymbol,
            isActive: dictationRuntime.isListening
          )
        } primaryAction: {
          guard dictationRuntime.toolbarPresentation.primaryAction != nil else { return }
          Task { await dictationRuntime.toggle() }
        }
        .accessibilityLabel(dictationRuntime.microphoneHelp)
        .accessibilityAction(named: Text("Cancel Dictation")) {
          Task { await dictationRuntime.cancel() }
        }
        .help(dictationRuntime.microphoneHelp)
        Divider().frame(height: 15)
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
        Menu {
          Button("Disc (•)") { commands.applyList(.bullet(.disc)) }
          Button("Circle (◦)") { commands.applyList(.bullet(.circle)) }
          Button("Square (▪)") { commands.applyList(.bullet(.square)) }
          Button("Dash (–)") { commands.applyList(.bullet(.dash)) }
        } label: {
          ToolbarIconLabel(systemImage: "list.bullet")
        } primaryAction: {
          commands.applyAutomaticList(.bullets)
        }
        .accessibilityLabel("Bullets")
        Menu {
          Button("Decimal (1.)") { commands.applyList(.number(.decimal)) }
          Button("Alphabetic (a.)") { commands.applyList(.number(.alphabetic)) }
          Button("Roman (i.)") { commands.applyList(.number(.roman)) }
        } label: {
          ToolbarIconLabel(systemImage: "list.number")
        } primaryAction: {
          commands.applyAutomaticList(.numbers)
        }
        .accessibilityLabel("Numbers")
        Button {
          commands.applyList(.checklist)
        } label: {
          ToolbarIconLabel(systemImage: "checklist")
        }
        .accessibilityLabel("Checklist")
        Spacer()
        Button(role: .destructive) {
          onDelete()
        } label: {
          ToolbarIconLabel(systemImage: "trash")
        }
        .accessibilityLabel("Delete")
        .keyboardShortcut("w", modifiers: .command)
      }
      .buttonStyle(CrispToolbarButtonStyle(motion: motion))
      .animation(motion.quick, value: commands.isBold)
      .animation(motion.quick, value: commands.isItalic)
      .animation(motion.quick, value: commands.isUnderlined)
      .padding(.horizontal, 16)
      .padding(.vertical, 9)
      .background(.thinMaterial)
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }
  }

  private struct CrispToolbarButtonStyle: ButtonStyle {
    let motion: AppMotion

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .scaleEffect(configuration.isPressed ? motion.pressScale : 1)
        .animation(motion.quick, value: configuration.isPressed)
    }
  }

  private struct SaveFeedbackView: View {
    let status: AppState.SaveStatus
    let motion: AppMotion

    var body: some View {
      ZStack(alignment: .trailing) {
        switch status {
        case .idle:
          Color.clear
        case .saving:
          HStack(spacing: 5) {
            ProgressView()
              .controlSize(.mini)
            Text("Saving")
          }
          .id(status)
          .transition(.opacity)
        case .saved:
          Label("Saved", systemImage: "checkmark")
            .id(status)
            .transition(.opacity)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(width: 62, height: 22, alignment: .trailing)
      .animation(motion.quick, value: status)
      .accessibilityElement(children: .combine)
    }
  }

  private struct TabDropDelegate: DropDelegate {
    let destinationID: UUID
    let currentNoteIDs: () -> [UUID]
    @Binding var draggedNoteID: UUID?
    let move: (UUID, Int) -> Void

    func dropEntered(info: DropInfo) {
      TabDragReorder.performLiveMove(
        draggedID: draggedNoteID,
        over: destinationID,
        currentNoteIDs: currentNoteIDs,
        move: move
      )
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
      DropProposal(operation: TabDragReorder.dropOperation)
    }

    func performDrop(info: DropInfo) -> Bool {
      draggedNoteID = nil
      return true
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
