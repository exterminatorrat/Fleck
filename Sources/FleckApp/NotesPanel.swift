#if os(macOS)
  import AppKit
  import SwiftUI
  import FleckCore
  import UniformTypeIdentifiers

  enum FolderDragPayload {
    static let noteType = UTType(exportedAs: "com.harryjin.fleck.local-note")
    static let folderType = UTType(exportedAs: "com.harryjin.fleck.local-folder")

    private struct NoteValue: Codable {
      let noteID: UUID
      let sourceFolderID: UUID?
    }

    private struct FolderValue: Codable {
      let folderID: UUID
    }

    static func noteProvider(noteID: UUID, sourceFolderID: UUID?) -> NSItemProvider {
      provider(
        type: noteType,
        value: NoteValue(noteID: noteID, sourceFolderID: sourceFolderID)
      )
    }

    static func folderProvider(folderID: UUID) -> NSItemProvider {
      provider(type: folderType, value: FolderValue(folderID: folderID))
    }

    static func noteValue(from data: Data) -> (noteID: UUID, sourceFolderID: UUID?)? {
      guard let value = try? JSONDecoder().decode(NoteValue.self, from: data) else {
        return nil
      }
      return (value.noteID, value.sourceFolderID)
    }

    static func folderID(from data: Data) -> UUID? {
      try? JSONDecoder().decode(FolderValue.self, from: data).folderID
    }

    private static func provider<Value: Encodable>(
      type: UTType,
      value: Value
    ) -> NSItemProvider {
      let data = try! JSONEncoder().encode(value)
      let provider = NSItemProvider()
      provider.registerDataRepresentation(
        forTypeIdentifier: type.identifier,
        visibility: .ownProcess
      ) { completion in
        completion(data, nil)
        return nil
      }
      return provider
    }
  }

  enum FolderNavigatorFocus {
    static func nextIndex(
      currentIndex: Int,
      direction: MoveCommandDirection,
      count: Int
    ) -> Int {
      guard count > 0 else { return 0 }
      let offset: Int
      switch direction {
      case .up: offset = -1
      case .down: offset = 1
      default: return currentIndex
      }
      return min(max(currentIndex + offset, 0), count - 1)
    }
  }

  enum TabDragReorder {
    struct Destination: Equatable {
      let id: UUID
      let index: Int
    }

    struct LiveMoveResult: Equatable {
      let didMove: Bool
      let destinationID: UUID?
    }

    static func destination(
      draggedID: UUID?,
      locationX: CGFloat,
      currentNoteIDs: [UUID],
      currentFrames: [UUID: CGRect]
    ) -> Destination? {
      guard let draggedID,
        let sourceIndex = currentNoteIDs.firstIndex(of: draggedID),
        let draggedFrame = currentFrames[draggedID]
      else { return nil }

      let destinationID: UUID?
      if locationX > draggedFrame.midX {
        destinationID = currentNoteIDs.dropFirst(sourceIndex + 1).last { id in
          guard let midpoint = currentFrames[id]?.midX else { return false }
          return midpoint <= locationX
        }
      } else if locationX < draggedFrame.midX {
        destinationID = currentNoteIDs.prefix(sourceIndex).first { id in
          guard let midpoint = currentFrames[id]?.midX else { return false }
          return midpoint >= locationX
        }
      } else {
        destinationID = nil
      }

      guard let destinationID,
        let destinationIndex = currentNoteIDs.firstIndex(of: destinationID)
      else { return nil }
      return Destination(id: destinationID, index: destinationIndex)
    }

    static func performLiveMove(
      draggedID: UUID?,
      locationX: CGFloat,
      currentNoteIDs: () -> [UUID],
      currentFrames: () -> [UUID: CGRect],
      lastDestinationID: UUID?,
      move: (UUID, Int) -> Void
    ) -> LiveMoveResult {
      guard let draggedID,
        let destination = destination(
          draggedID: draggedID,
          locationX: locationX,
          currentNoteIDs: currentNoteIDs(),
          currentFrames: currentFrames()
        )
      else {
        return LiveMoveResult(didMove: false, destinationID: nil)
      }
      guard destination.id != lastDestinationID else {
        return LiveMoveResult(didMove: false, destinationID: destination.id)
      }
      move(draggedID, destination.index)
      return LiveMoveResult(didMove: true, destinationID: destination.id)
    }
  }

  enum TabOverflowPresentation {
    static func tabViewportWidth(totalStripWidth: CGFloat) -> CGFloat {
      max(0, totalStripWidth - 28)
    }

    static func hasHiddenTrailingContent(
      contentTrailingEdge: CGFloat,
      visibleTrailingEdge: CGFloat
    ) -> Bool {
      contentTrailingEdge > visibleTrailingEdge + 0.5
    }
  }

  enum FontSizeSubmission {
    static func requestedSize(
      for text: String,
      currentSize: CGFloat?,
      isMixed: Bool
    ) -> CGFloat? {
      guard let size = Double(text), size.isFinite, (1...512).contains(size) else { return nil }
      let requestedSize = CGFloat(size)
      guard isMixed || requestedSize != currentSize else { return nil }
      return requestedSize
    }
  }

  private struct TabContentTrailingEdgePreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
      value = nextValue()
    }
  }

  private struct TabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
      value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
  }

  enum NotesPanelSizing: Equatable {
    case storedPreferences
    case container
  }

  struct NotesPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var dictationRuntime: DictationRuntime
    let isPinned: Bool
    let sizing: NotesPanelSizing
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
    @State private var tabDragDestinationID: UUID?
    @State private var tabColorPickerNoteID: UUID?
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var tabContentTrailingEdge: CGFloat = 0
    @State private var activeFolderID: UUID?

    init(
      dictationRuntime: DictationRuntime,
      isPinned: Bool = false,
      sizing: NotesPanelSizing = .storedPreferences,
      editorCommands: EditorCommands? = nil
    ) {
      self.dictationRuntime = dictationRuntime
      self.isPinned = isPinned
      self.sizing = sizing
      _editorCommands = StateObject(wrappedValue: editorCommands ?? EditorCommands())
    }

    var body: some View {
      VStack(spacing: 0) {
        if let migrationError = appState.startupMigrationError {
          migrationFailure(migrationError)
        } else {
          header
          folderNavigator
          tabStrip
          Divider().opacity(0.35)
          if let title = modifierRecoveryPresentation.recoveryButtonTitle {
            HStack(spacing: 8) {
              Label(modifierRecoveryPresentation.statusCopy, systemImage: "keyboard.badge.ellipsis")
                .font(.caption)
              Spacer()
              Button(title) {
                Task { @MainActor in
                  guard let settings = await dictationRuntime.recoverModifierMonitoring() else {
                    return
                  }
                  dictationRuntime.openSystemSettings(settings)
                }
              }
              .accessibilityLabel(title)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.35))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dictation shortcut unavailable")
          }
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
          scopedEditor
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
        width: sizing == .storedPreferences ? appState.preferences.panelWidth : nil,
        height: sizing == .storedPreferences ? appState.preferences.panelHeight : nil
      )
      .frame(
        maxWidth: sizing == .container ? .infinity : nil,
        maxHeight: sizing == .container ? .infinity : nil
      )
      .background {
        Rectangle()
          .fill(.ultraThinMaterial)
          .opacity(appState.preferences.panelOpacity)
      }
      .tint(Color(hex: appState.preferences.accentHex) ?? .accentColor)
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
      .task {
        await appState.waitUntilInitialLoad()
        guard !Task.isCancelled else { return }
        activeFolderID = appState.folderScopeForSelectedNote()
      }
      .onChange(of: appState.workspace.folders) { _, folders in
        guard let activeFolderID,
          !folders.contains(where: { $0.id == activeFolderID })
        else { return }
        self.activeFolderID = nil
      }
    }

    private var modifierRecoveryPresentation: DictationModifierSettingsPresentation {
      .init(
        selected: appState.preferences.dictationModifierKey,
        monitorStatus: dictationRuntime.modifierMonitorState,
        canChange: dictationRuntime.canChangeModifier
      )
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
        HStack(spacing: 6) {
          switch FleckMark.load(template: true) {
          case .image(let mark):
            Image(nsImage: mark)
              .resizable()
              .frame(width: 18, height: 18)
              .accessibilityHidden(true)
          case .missingPackagedResource:
            Text("!")
              .foregroundStyle(.red)
              .accessibilityLabel("Fleck mark missing")
          }
          Text("Fleck")
            .accessibilityLabel("Fleck")
        }
          .font(.headline)
        Spacer()
        SaveFeedbackView(status: appState.saveStatus, motion: motion)
        Button {
          appState.addNote(inFolderID: activeFolderID)
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

        Button {
          appState.updatePreferences { $0.showFormattingBar.toggle() }
        } label: {
          Image(
            systemName: appState.preferences.showFormattingBar
              ? "chevron.up"
              : "chevron.down"
          )
        }
        .accessibilityLabel(
          appState.preferences.showFormattingBar
            ? "Hide Editor toolbar"
            : "Show Editor toolbar"
        )
        .help(
          appState.preferences.showFormattingBar
            ? "Hide Editor toolbar"
            : "Show Editor toolbar"
        )

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

    private var folderNavigator: some View {
      FolderNavigator(
        activeFolderID: activeFolderID,
        onSelect: selectFolder,
        onDelete: deleteFolder,
        onOpenTrash: { isShowingTrash = true }
      )
      .environmentObject(appState)
    }

    private func selectFolder(_ folderID: UUID?) {
      guard folderID == nil || appState.workspace.folders.contains(where: { $0.id == folderID })
      else { return }
      activeFolderID = folderID
      let visible = appState.visibleNotes(in: folderID)
      guard !visible.contains(where: { $0.id == appState.workspace.selectedNoteID }),
        let first = visible.first
      else { return }
      appState.select(first.id)
    }

    private func deleteFolder(_ folderID: UUID) {
      let currentFolderID = activeFolderID
      if currentFolderID == folderID {
        activeFolderID = nil
      }
      do {
        try appState.deleteFolder(id: folderID, activeFolderID: currentFolderID)
      } catch {
        if currentFolderID == folderID {
          activeFolderID = folderID
        }
        appState.saveError = "Could not update folder: \(String(describing: error))"
      }
    }

    private var tabStrip: some View {
      ScrollViewReader { scrollProxy in
        GeometryReader { proxy in
          let tabViewportWidth = TabOverflowPresentation.tabViewportWidth(totalStripWidth: proxy.size.width)
          let hasHiddenTrailingTabs = TabOverflowPresentation.hasHiddenTrailingContent(
            contentTrailingEdge: tabContentTrailingEdge,
            visibleTrailingEdge: tabViewportWidth
          )
        HStack(spacing: 0) {
          ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 6) {
                ForEach(visibleNotes) { note in
            Button {
              guard draggedNoteID == nil else { return }
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
              .background {
                GeometryReader { proxy in
                  Color.clear.preference(
                    key: TabFramePreferenceKey.self,
                    value: [note.id: proxy.frame(in: .named("tab-strip"))]
                  )
                }
              }
            }
            .buttonStyle(.plain)
            .onDrag {
              FolderDragPayload.noteProvider(
                noteID: note.id,
                sourceFolderID: note.folderID
              )
            }
            .transition(
              .opacity.combined(
                with: .offset(x: motion.offset)
              )
            )
            .simultaneousGesture(
              DragGesture(minimumDistance: 2, coordinateSpace: .named("tab-strip"))
                .onChanged { value in
                  guard abs(value.translation.width) >= 2 else { return }
                  if draggedNoteID == nil {
                    draggedNoteID = note.id
                    tabDragDestinationID = nil
                    appState.select(note.id)
                  }
                  guard draggedNoteID == note.id else { return }
                  let result = TabDragReorder.performLiveMove(
                    draggedID: draggedNoteID,
                    locationX: value.location.x,
                    currentNoteIDs: { visibleNotes.map(\.id) },
                    currentFrames: { tabFrames },
                    lastDestinationID: tabDragDestinationID,
                    move: { id, destination in
                      _ = appState.moveNote(
                        id,
                        inFolderID: activeFolderID,
                        toVisibleIndex: destination
                      )
                    }
                  )
                  tabDragDestinationID = result.destinationID
                }
                .onEnded { _ in
                  draggedNoteID = nil
                  tabDragDestinationID = nil
                }
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
              Button("Tab Color...", systemImage: "paintpalette") {
                tabColorPickerNoteID = note.id
              }
              .accessibilityValue(tabColorAccessibilityValue(for: note.tabColorHex))
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
            .popover(
              isPresented: Binding(
                get: { tabColorPickerNoteID == note.id },
                set: { if !$0 { tabColorPickerNoteID = nil } }
              ),
              arrowEdge: .bottom
            ) {
              tabColorPicker(noteID: note.id)
            }
                }
                Color.clear
                  .frame(width: 0, height: 0)
                  .background {
                GeometryReader { proxy in
                  Color.clear.preference(
                    key: TabContentTrailingEdgePreferenceKey.self,
                    value: proxy.frame(in: .named("tab-scroll-viewport")).minX - 6
                  )
                }
              }
              }
              .padding(.horizontal, 12)
              .padding(.bottom, 9)
              .animation(motion.spatial, value: appState.workspace.selectedNoteID)
              .animation(motion.spatial, value: visibleNotes.map(\.id))
            }
            .coordinateSpace(name: "tab-scroll-viewport")
            .coordinateSpace(name: "tab-strip")

            if hasHiddenTrailingTabs {
              LinearGradient(
                colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                startPoint: .leading,
                endPoint: .trailing
              )
              .frame(width: 18)
              .allowsHitTesting(false)
            }
          }
          .frame(width: tabViewportWidth, alignment: .leading)

          Button {
            if let lastNoteID = visibleNotes.last?.id {
              scrollProxy.scrollTo(lastNoteID, anchor: .trailing)
            }
          } label: {
            Image(systemName: "chevron.right")
              .font(.caption)
              .frame(width: 28, height: 28)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Reveal hidden tabs")
          .accessibilityHidden(!hasHiddenTrailingTabs)
          .disabled(!hasHiddenTrailingTabs)
          .opacity(hasHiddenTrailingTabs ? 1 : 0)
        }
        .onPreferenceChange(TabContentTrailingEdgePreferenceKey.self) { trailingEdge in
          guard tabContentTrailingEdge != trailingEdge else { return }
          tabContentTrailingEdge = trailingEdge
        }
        .onPreferenceChange(TabFramePreferenceKey.self) { frames in
          tabFrames = frames
        }
        }
        .frame(height: 37)
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
      return (Color(hex: hex) ?? .accentColor).opacity(opacity)
    }

    @ViewBuilder
    private func tabColorPicker(noteID: UUID) -> some View {
      if let note = appState.workspace.notes.first(where: { $0.id == noteID }) {
        FleckColorPicker(
          currentHex: note.tabColorHex,
          currentLabel: tabColorAccessibilityValue(for: note.tabColorHex),
          resetTitle: "None",
          onCommit: { hex in commitTabColor(hex, for: noteID) },
          onCancel: { tabColorPickerNoteID = nil }
        )
      } else {
        EmptyView()
      }
    }

    private func commitTabColor(_ hex: String?, for noteID: UUID) {
      guard appState.workspace.notes.contains(where: { $0.id == noteID }) else {
        tabColorPickerNoteID = nil
        return
      }
      appState.select(noteID)
      appState.setSelectedTabColor(hex)
      tabColorPickerNoteID = nil
    }

    private func tabColorAccessibilityValue(for hex: String?) -> String {
      guard let hex else { return "None" }
      return FleckPaletteOption.paletteName(for: NSColor(hex: hex)) ?? "Custom"
    }

    private func performShortcut(_ action: Shortcut.Action) {
      switch action {
      case .togglePanel:
        NSApp.keyWindow?.orderOut(nil)
      case .newNote:
        appState.addNote(inFolderID: activeFolderID)
      case .closeNote:
        if let note = appState.selectedNote {
          requestDeletion(note)
        }
      case .nextNote:
        appState.selectAdjacentNote(forward: true, inFolderID: activeFolderID)
      case .previousNote:
        appState.selectAdjacentNote(forward: false, inFolderID: activeFolderID)
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
      guard let index = visibleNotes.firstIndex(where: { $0.id == note.id }) else {
        return
      }
      _ = appState.moveNote(
        note.id,
        inFolderID: activeFolderID,
        toVisibleIndex: index + offset
      )
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
          appState.importNote(note, intoFolderID: activeFolderID)
        }
        appState.saveError = nil
      } catch {
        appState.saveError = "Import failed: \(error.localizedDescription)"
      }
    }

    private var visibleNotes: [Note] {
      appState.visibleNotes(in: activeFolderID)
    }

    private var isEditorVisible: Bool {
      guard let selectedID = appState.workspace.selectedNoteID else { return false }
      return visibleNotes.contains(where: { $0.id == selectedID })
    }

    @ViewBuilder
    private var scopedEditor: some View {
      ZStack {
        editor
          .opacity(isEditorVisible ? 1 : 0)
          .allowsHitTesting(isEditorVisible)
          .accessibilityHidden(!isEditorVisible)

        if visibleNotes.isEmpty {
          VStack(spacing: 10) {
            ContentUnavailableView(
              activeFolderID == nil ? "Unfiled is Empty" : "Folder is Empty",
              systemImage: activeFolderID == nil ? "tray" : "folder",
              description: Text("Create a note here to get started.")
            )
            Button("New note") {
              appState.addNote(inFolderID: activeFolderID)
            }
            .keyboardShortcut("t", modifiers: .command)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityElement(children: .contain)
          .accessibilityLabel(
            activeFolderID == nil ? "Unfiled is empty" : "Folder is empty"
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .transition(.opacity)
            .animation(reduceMotion ? nil : motion.quick, value: appState.preferences.showFormattingBar)
          }
          TextField(
            "Note title",
            text: Binding(
              get: { note.title },
              set: { appState.updateSelected(title: $0) }
            )
          )
          .textFieldStyle(.plain)
          .font(EditorTypography.titleFont(family: appState.preferences.fontFamily))
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

  private struct FolderNavigator: View {
    private enum FocusedRow: Hashable {
      case unfiled
      case folder(UUID)
      case trash
      case newFolder
    }

    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedRow: FocusedRow?
    @State private var editingFolderID: UUID?
    @State private var isCreatingFolder = false
    @State private var folderNameDraft = ""
    @State private var folderPendingDeletion: Folder?

    let activeFolderID: UUID?
    let onSelect: (UUID?) -> Void
    let onDelete: (UUID) -> Void
    let onOpenTrash: () -> Void

    var body: some View {
      VStack(spacing: 3) {
        if isCreatingFolder {
          folderEditor(label: "New folder", focus: .newFolder)
        }

        rootRow

        ForEach(appState.workspace.folders, id: \.id) { folder in
          folderRow(folder)
        }

        Button {
          beginNewFolder()
        } label: {
          Label("New Folder", systemImage: "folder.badge.plus")
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityLabel("New folder")
        .onDrop(of: [FolderDragPayload.folderType], isTargeted: nil) { providers, _ in
          handleFolderDrop(providers, beforeFolderID: nil)
        }

        Divider()
          .padding(.vertical, 2)

        Button {
          onOpenTrash()
        } label: {
          rowLabel(
            name: "Trash",
            systemImage: "trash",
            count: appState.trashedNotes.count,
            isSelected: false,
            isEmpty: appState.trashedNotes.isEmpty
          )
        }
        .buttonStyle(.plain)
        .focused($focusedRow, equals: .trash)
        .focusable()
        .accessibilityLabel("Trash")
        .accessibilityValue(
          appState.trashedNotes.isEmpty
            ? "Empty"
            : "\(appState.trashedNotes.count) notes"
        )
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 5)
      .onMoveCommand { direction in
        moveFocus(direction)
      }
      .onDeleteCommand {
        guard case .folder(let id) = focusedRow,
          let folder = appState.workspace.folders.first(where: { $0.id == id })
        else { return }
        folderPendingDeletion = folder
      }
      .onExitCommand {
        cancelFolderEditing()
      }
      .onKeyPress(phases: .down) { press in
        guard isF2(press), beginRename() else { return .ignored }
        return .handled
      }
      .onKeyPress(keys: [.return, .space], phases: .down) { _ in
        activateFocusedRow()
        return .handled
      }
      .confirmationDialog(
        "Delete folder?",
        isPresented: Binding(
          get: { folderPendingDeletion != nil },
          set: { if !$0 { folderPendingDeletion = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Delete Folder", role: .destructive) {
          guard let folderPendingDeletion else { return }
          self.folderPendingDeletion = nil
          onDelete(folderPendingDeletion.id)
        }
        Button("Cancel", role: .cancel) {
          folderPendingDeletion = nil
        }
      } message: {
        Text("Notes in this folder move to Unfiled. No notes are deleted.")
      }
    }

    private var rootRow: some View {
      Button {
        onSelect(nil)
      } label: {
        rowLabel(
          name: "Unfiled",
          systemImage: "tray",
          count: appState.visibleNotes(in: nil).count,
          isSelected: activeFolderID == nil,
          isEmpty: appState.visibleNotes(in: nil).isEmpty
        )
      }
      .buttonStyle(.plain)
      .focused($focusedRow, equals: .unfiled)
      .focusable()
      .onDrop(of: [FolderDragPayload.noteType], isTargeted: nil) { providers, _ in
        handleNoteDrop(providers, targetFolderID: nil)
      }
      .accessibilityLabel("Unfiled")
      .accessibilityValue(
        "\(appState.visibleNotes(in: nil).count) notes"
          + (activeFolderID == nil ? ", Selected" : "")
          + (appState.visibleNotes(in: nil).isEmpty ? ", Empty" : "")
      )
      .accessibilityAddTraits(activeFolderID == nil ? .isSelected : [])
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
      if editingFolderID == folder.id {
        folderEditor(label: "Folder name", focus: .folder(folder.id))
      } else {
        Button {
          onSelect(folder.id)
        } label: {
          rowLabel(
            name: folder.name,
            systemImage: "folder",
            count: appState.visibleNotes(in: folder.id).count,
            isSelected: activeFolderID == folder.id,
            isEmpty: appState.visibleNotes(in: folder.id).isEmpty
          )
        }
        .buttonStyle(.plain)
        .focused($focusedRow, equals: .folder(folder.id))
        .focusable()
        .onDrag { FolderDragPayload.folderProvider(folderID: folder.id) }
        .onDrop(
          of: [FolderDragPayload.noteType, FolderDragPayload.folderType],
          isTargeted: nil
        ) { providers, _ in
          handleDrop(
            providers,
            noteTargetFolderID: folder.id,
            folderBeforeID: folder.id
          )
        }
        .contextMenu {
          Button("Rename", systemImage: "pencil") {
            _ = beginRename(folderID: folder.id)
          }
          Button("Delete", systemImage: "trash", role: .destructive) {
            folderPendingDeletion = folder
          }
        }
        .accessibilityLabel(folder.name)
        .accessibilityValue(
          "\(appState.visibleNotes(in: folder.id).count) notes"
            + (activeFolderID == folder.id ? ", Selected" : "")
            + (appState.visibleNotes(in: folder.id).isEmpty ? ", Empty" : "")
        )
        .accessibilityAddTraits(activeFolderID == folder.id ? .isSelected : [])
      }
    }

    @ViewBuilder
    private func folderEditor(label: String, focus: FocusedRow) -> some View {
      HStack(spacing: 5) {
        TextField(label, text: $folderNameDraft)
          .textFieldStyle(.roundedBorder)
          .focused($focusedRow, equals: focus)
          .onSubmit { commitFolderEditing() }
          .onExitCommand { cancelFolderEditing() }
        Button("Save") { commitFolderEditing() }
          .buttonStyle(.plain)
          .accessibilityLabel("Save folder name")
        Button("Cancel", role: .cancel) { cancelFolderEditing() }
          .buttonStyle(.plain)
          .accessibilityLabel("Cancel folder name")
      }
      .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func rowLabel(
      name: String,
      systemImage: String,
      count: Int,
      isSelected: Bool,
      isEmpty: Bool
    ) -> some View {
      HStack(spacing: 7) {
        Image(systemName: systemImage)
          .frame(width: 18)
        Text(name)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text(count, format: .number)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        isSelected ? Color.accentColor.opacity(0.18) : .clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .contentShape(RoundedRectangle(cornerRadius: 6))
      .accessibilityHint(isEmpty ? "Empty folder" : "")
    }

    private func beginNewFolder() {
      editingFolderID = nil
      isCreatingFolder = true
      folderNameDraft = ""
      focusedRow = .newFolder
    }

    private func beginRename(folderID: UUID? = nil) -> Bool {
      let id: UUID?
      if let folderID {
        id = folderID
      } else if case .folder(let focusedID) = focusedRow {
        id = focusedID
      } else {
        id = nil
      }
      guard let id,
        let folder = appState.workspace.folders.first(where: { $0.id == id })
      else { return false }
      isCreatingFolder = false
      editingFolderID = id
      folderNameDraft = folder.name
      focusedRow = .folder(id)
      return true
    }

    private func commitFolderEditing() {
      do {
        if isCreatingFolder {
          _ = try appState.createFolder(named: folderNameDraft)
        } else if let editingFolderID {
          try appState.renameFolder(id: editingFolderID, name: folderNameDraft)
        }
        cancelFolderEditing()
      } catch {
        appState.saveError = "Could not update folder: \(String(describing: error))"
      }
    }

    private func cancelFolderEditing() {
      editingFolderID = nil
      isCreatingFolder = false
      folderNameDraft = ""
      focusedRow = nil
    }

    private func activateFocusedRow() {
      switch focusedRow {
      case .unfiled:
        onSelect(nil)
      case .folder(let id):
        onSelect(id)
      case .trash:
        onOpenTrash()
      case .newFolder, nil:
        break
      }
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
      let rows: [FocusedRow] = [.unfiled]
        + appState.workspace.folders.map { .folder($0.id) }
        + [.trash]
      guard !rows.isEmpty else { return }
      let currentIndex = focusedRow.flatMap { rows.firstIndex(of: $0) } ?? 0
      focusedRow = rows[
        FolderNavigatorFocus.nextIndex(
          currentIndex: currentIndex,
          direction: direction,
          count: rows.count
        )
      ]
    }

    private func isF2(_ press: KeyPress) -> Bool {
      press.characters.unicodeScalars.contains { $0.value == UInt32(NSF2FunctionKey) }
    }

    private func handleDrop(
      _ providers: [NSItemProvider],
      noteTargetFolderID: UUID?,
      folderBeforeID: UUID?
    ) -> Bool {
      if let provider = providers.first(where: {
        $0.registeredTypeIdentifiers.contains(FolderDragPayload.noteType.identifier)
      }) {
        return handleNoteDrop([provider], targetFolderID: noteTargetFolderID)
      }
      if let provider = providers.first(where: {
        $0.registeredTypeIdentifiers.contains(FolderDragPayload.folderType.identifier)
      }) {
        return handleFolderDrop([provider], beforeFolderID: folderBeforeID)
      }
      return false
    }

    private func handleNoteDrop(
      _ providers: [NSItemProvider],
      targetFolderID: UUID?
    ) -> Bool {
      guard let provider = providers.first(where: {
        $0.registeredTypeIdentifiers.contains(FolderDragPayload.noteType.identifier)
      }) else { return false }
      provider.loadDataRepresentation(forTypeIdentifier: FolderDragPayload.noteType.identifier) {
        data, _ in
        guard let data, let payload = FolderDragPayload.noteValue(from: data) else { return }
        Task { @MainActor in
          guard let note = appState.workspace.notes.first(where: { $0.id == payload.noteID }),
            note.folderID == payload.sourceFolderID
          else { return }
          _ = appState.moveNote(
            payload.noteID,
            fromFolderID: payload.sourceFolderID,
            toFolderID: targetFolderID,
            activeFolderID: activeFolderID
          )
        }
      }
      return true
    }

    private func handleFolderDrop(
      _ providers: [NSItemProvider],
      beforeFolderID targetFolderID: UUID?
    ) -> Bool {
      guard let provider = providers.first(where: {
        $0.registeredTypeIdentifiers.contains(FolderDragPayload.folderType.identifier)
      }) else { return false }
      provider.loadDataRepresentation(forTypeIdentifier: FolderDragPayload.folderType.identifier) {
        data, _ in
        guard let data, let sourceFolderID = FolderDragPayload.folderID(from: data) else {
          return
        }
        Task { @MainActor in
          guard let sourceIndex = appState.workspace.folders.firstIndex(where: { $0.id == sourceFolderID })
          else { return }
          let destination: Int
          if let targetFolderID,
            let targetIndex = appState.workspace.folders.firstIndex(where: { $0.id == targetFolderID })
          {
            destination = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
          } else if targetFolderID == nil {
            destination = appState.workspace.folders.count - 1
          } else {
            return
          }
          try? appState.reorderFolder(id: sourceFolderID, to: destination)
        }
      }
      return true
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var commands: EditorCommands
    @ObservedObject var dictationRuntime: DictationRuntime
    let onDelete: () -> Void
    @State private var fontSizeText = ""
    @FocusState private var isFontSizeFocused: Bool
    @State private var isForegroundColorPickerPresented = false
    @State private var isBackgroundColorPickerPresented = false

    var body: some View {
      ScrollView(.horizontal, showsIndicators: false) {
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
            Button {
              commands.applyFontFamily(family)
            } label: {
              HStack {
                Text(family)
                if !commands.isFontFamilyMixed, commands.currentFontFamily == family {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          ToolbarIconLabel(systemImage: "textformat")
        }
        .help("Font")
        .accessibilityLabel("Font")
        .accessibilityValue(
          commands.isFontFamilyMixed ? "Mixed" : commands.currentFontFamily ?? "Automatic"
        )
        TextField("Font size", text: $fontSizeText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 48)
          .focused($isFontSizeFocused)
          .onAppear(perform: syncFontSizeText)
          .onChange(of: commands.currentFontSize) { _, _ in syncFontSizeText() }
          .onChange(of: commands.isFontSizeMixed) { _, _ in syncFontSizeText() }
          .onChange(of: isFontSizeFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused { applyFontSizeText() }
          }
          .onSubmit { applyFontSizeText() }
          .accessibilityLabel("Font size")
          .accessibilityValue(commands.isFontSizeMixed ? "Mixed" : fontSizeDisplay)
          .accessibilityHint("Enter a size from 1 through 512 points.")
        Button {
          isForegroundColorPickerPresented = true
        } label: {
          ToolbarIconLabel(systemImage: "paintpalette")
        }
        .accessibilityLabel("Font Color")
        .accessibilityValue(
          colorAccessibilityValue(
            color: commands.currentForegroundColor,
            isMixed: commands.isForegroundColorMixed,
            emptyName: "Automatic"
          )
        )
        .popover(isPresented: $isForegroundColorPickerPresented, arrowEdge: .bottom) {
          FleckColorPicker(
            currentHex: commands.isForegroundColorMixed
              ? nil
              : FleckColorHex.hex(from: commands.currentForegroundColor),
            currentLabel: colorAccessibilityValue(
              color: commands.currentForegroundColor,
              isMixed: commands.isForegroundColorMixed,
              emptyName: "Automatic"
            ),
            resetTitle: "Automatic",
            onCommit: { hex in
              commands.applyForegroundColor(hex.flatMap { NSColor(hex: $0) })
              isForegroundColorPickerPresented = false
            },
            onCancel: { isForegroundColorPickerPresented = false }
          )
        }
        Button {
          isBackgroundColorPickerPresented = true
        } label: {
          ToolbarIconLabel(systemImage: "highlighter")
        }
        .accessibilityLabel("Highlight")
        .accessibilityValue(
          colorAccessibilityValue(
            color: commands.currentBackgroundColor,
            isMixed: commands.isBackgroundColorMixed,
            emptyName: "No Highlight"
          )
        )
        .popover(isPresented: $isBackgroundColorPickerPresented, arrowEdge: .bottom) {
          FleckColorPicker(
            currentHex: commands.isBackgroundColorMixed
              ? nil
              : FleckColorHex.hex(from: commands.currentBackgroundColor),
            currentLabel: colorAccessibilityValue(
              color: commands.currentBackgroundColor,
              isMixed: commands.isBackgroundColorMixed,
              emptyName: "No Highlight"
            ),
            resetTitle: "No Highlight",
            fallbackHex: "#FFD600",
            onCommit: { hex in
              commands.applyBackgroundColor(hex.flatMap { NSColor(hex: $0) })
              isBackgroundColorPickerPresented = false
            },
            onCancel: { isBackgroundColorPickerPresented = false }
          )
        }
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
      }
      .frame(maxWidth: .infinity)
      .background(.thinMaterial)
      .accessibilityLabel("Editor toolbar")
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private var fontSizeDisplay: String {
      guard !commands.isFontSizeMixed, let size = commands.currentFontSize else { return "" }
      return String(format: "%.2f", size).replacingOccurrences(of: #"\.00$"#, with: "", options: .regularExpression)
    }

    private func syncFontSizeText() {
      guard !isFontSizeFocused else { return }
      fontSizeText = fontSizeDisplay
    }

    private func applyFontSizeText() {
      if let size = FontSizeSubmission.requestedSize(
        for: fontSizeText,
        currentSize: commands.currentFontSize,
        isMixed: commands.isFontSizeMixed
      ) {
        _ = commands.applyFontSize(size)
      }
      fontSizeText = fontSizeDisplay
    }

    private func colorAccessibilityValue(
      color: NSColor?,
      isMixed: Bool,
      emptyName: String
    ) -> String {
      guard !isMixed else { return "Mixed" }
      guard let color else { return emptyName }
      return FleckPaletteOption.paletteName(for: color) ?? "Custom"
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

#endif
