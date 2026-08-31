#if os(macOS)
  import AppKit
  import SwiftUI
  import FleckCore
  import UniformTypeIdentifiers

  enum FolderDragPayload {
    static let noteType = UTType(exportedAs: "com.harryjin.fleck.local-note")
    static let folderType = UTType(exportedAs: "com.harryjin.fleck.local-folder")

    private final class LocalNoteItemProvider: NSItemProvider {
      let source: NoteDropSource

      init(source: NoteDropSource) {
        self.source = source
        super.init()
      }

      required init?(coder: NSCoder) {
        return nil
      }
    }

    private struct FolderValue: Codable {
      let folderID: UUID
    }

    static func noteProvider(source: NoteDropSource) -> NSItemProvider {
      let data = try! JSONEncoder().encode(source)
      let provider = LocalNoteItemProvider(source: source)
      provider.registerDataRepresentation(
        forTypeIdentifier: noteType.identifier,
        visibility: .ownProcess
      ) { completion in
        completion(data, nil)
        return nil
      }
      return provider
    }

    static func noteSource(from providers: [NSItemProvider]) -> NoteDropSource? {
      providers.first(where: {
        $0.registeredTypeIdentifiers.contains(noteType.identifier)
      }).flatMap {
        ($0 as? LocalNoteItemProvider)?.source
      }
    }

    static func noteValue(from data: Data) -> NoteDropSource? {
      try? JSONDecoder().decode(NoteDropSource.self, from: data)
    }

    static func folderProvider(folderID: UUID) -> NSItemProvider {
      provider(type: folderType, value: FolderValue(folderID: folderID))
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

  struct NoteDropSource: Codable, Equatable {
    let noteID: UUID
    let sourceFolderID: UUID?
    let dragSessionID: UUID

    init(noteID: UUID, sourceFolderID: UUID?, dragSessionID: UUID = UUID()) {
      self.noteID = noteID
      self.sourceFolderID = sourceFolderID
      self.dragSessionID = dragSessionID
    }
  }

  enum NoteDropPresentation {
    static func isValidTarget(
      draggedSource: NoteDropSource?,
      targetFolderID: UUID?,
      notes: [Note],
      validTargetFolderIDs: Set<UUID>
    ) -> Bool {
      guard let draggedSource,
        let note = notes.first(where: { $0.id == draggedSource.noteID }),
        note.folderID == draggedSource.sourceFolderID
      else { return false }
      if let targetFolderID, !validTargetFolderIDs.contains(targetFolderID) {
        return false
      }
      return draggedSource.sourceFolderID != targetFolderID
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
    static func isValidLocalDrag(
      draggedSource: NoteDropSource?,
      providerSource: NoteDropSource?,
      destinationID: UUID,
      activeFolderID: UUID?,
      currentNotes: [Note]
    ) -> Bool {
      guard let draggedSource,
        draggedSource == providerSource,
        draggedSource.sourceFolderID == activeFolderID,
        draggedSource.noteID != destinationID,
        let draggedNote = currentNotes.first(where: { $0.id == draggedSource.noteID }),
        draggedNote.folderID == draggedSource.sourceFolderID,
        let destinationNote = currentNotes.first(where: { $0.id == destinationID }),
        destinationNote.folderID == activeFolderID
      else { return false }
      return true
    }

    static func partitionLocalDestination(
      draggedID: UUID,
      absoluteDestination: Int,
      visibleNotes: [Note]
    ) -> Int? {
      guard let draggedNote = visibleNotes.first(where: { $0.id == draggedID }) else {
        return nil
      }
      let notesAfterRemoval = visibleNotes.filter { $0.id != draggedID }
      let insertion = min(max(absoluteDestination, 0), notesAfterRemoval.count)
      return notesAfterRemoval.prefix(insertion).reduce(into: 0) { count, note in
        if note.isPinned == draggedNote.isPinned {
          count += 1
        }
      }
    }

    struct LiveMoveResult: Equatable {
      let didMove: Bool
      let destinationID: UUID?
    }

    static func performLiveMove(
      draggedSource: NoteDropSource?,
      providerSource: NoteDropSource?,
      over destinationID: UUID,
      activeFolderID: UUID?,
      currentNotes: () -> [Note],
      lastDestinationID: UUID?,
      move: (UUID, Int) -> Void
    ) -> LiveMoveResult {
      let visibleNotes = currentNotes()
      guard isValidLocalDrag(
        draggedSource: draggedSource,
        providerSource: providerSource,
        destinationID: destinationID,
        activeFolderID: activeFolderID,
        currentNotes: visibleNotes
      ), let draggedSource
      else {
        return LiveMoveResult(didMove: false, destinationID: nil)
      }
      guard destinationID != lastDestinationID else {
        return LiveMoveResult(didMove: false, destinationID: destinationID)
      }
      guard let absoluteDestination = visibleNotes.firstIndex(where: { $0.id == destinationID }),
        let localDestination = partitionLocalDestination(
          draggedID: draggedSource.noteID,
          absoluteDestination: absoluteDestination,
          visibleNotes: visibleNotes
        )
      else {
        return LiveMoveResult(didMove: false, destinationID: nil)
      }
      move(draggedSource.noteID, localDestination)
      return LiveMoveResult(didMove: true, destinationID: destinationID)
    }
  }

  enum TabOverflowPresentation {
    static let tabOverflowRailWidth: CGFloat = 56

    static func tabViewportWidth(totalStripWidth: CGFloat) -> CGFloat {
      max(0, totalStripWidth - tabOverflowRailWidth)
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

  enum NotesPanelSizing: Equatable {
    case storedPreferences
    case container
  }

  enum NotesPanelBannerCategory: Hashable {
    case modifierRecovery
    case captureFailure
    case agentChange
  }

  enum NotesPanelBannerOccurrence: Hashable {
    case modifierRecovery(statusCopy: String, recoveryButtonTitle: String)
    case captureFailure(message: String, actionPanes: [DictationPrivacyPane])
    case agentChange(changeID: UUID, count: Int)

    var category: NotesPanelBannerCategory {
      switch self {
      case .modifierRecovery: .modifierRecovery
      case .captureFailure: .captureFailure
      case .agentChange: .agentChange
      }
    }
  }

  enum NotesPanelBannerPolicy {
    static func activeOccurrences(
      modifierRecovery: NotesPanelBannerOccurrence?,
      captureFailure: NotesPanelBannerOccurrence?,
      routineRecoveryAction _: DictationCapsuleAction?,
      agentChange: NotesPanelBannerOccurrence?
    ) -> Set<NotesPanelBannerOccurrence> {
      Set([modifierRecovery, captureFailure, agentChange].compactMap { $0 })
    }
  }

  struct NotesPanelBannerDismissalState: Equatable {
    private var dismissedOccurrences = Set<NotesPanelBannerOccurrence>()

    mutating func reconcile(
      activeOccurrences: Set<NotesPanelBannerOccurrence>
    ) {
      dismissedOccurrences.formIntersection(activeOccurrences)
    }

    mutating func forgetDismissedOccurrences(
      in category: NotesPanelBannerCategory
    ) {
      dismissedOccurrences = dismissedOccurrences.filter {
        $0.category != category
      }
    }

    mutating func dictationPhaseDidEmit(_ phase: DictationPhase) {
      guard phase == .arming else { return }
      forgetDismissedOccurrences(in: .modifierRecovery)
    }

    mutating func dismiss(_ occurrence: NotesPanelBannerOccurrence) {
      dismissedOccurrences.insert(occurrence)
    }

    func isPresented(_ occurrence: NotesPanelBannerOccurrence) -> Bool {
      !dismissedOccurrences.contains(occurrence)
    }
  }

  struct NotesPanelBannerCloseButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .semibold))
          .frame(width: 22, height: 22)
      }
      .buttonStyle(.borderless)
      .help("Dismiss \(label)")
      .accessibilityLabel("Dismiss \(label)")
    }
  }

  struct NotesPanel: View {
    private enum EditorFocus: Hashable {
      case title
      case body
    }

    private enum TabScrollTarget: Hashable {
      case leading
      case trailing
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var dictationRuntime: DictationRuntime
    let isPinned: Bool
    let sizing: NotesPanelSizing
    @StateObject private var editorCommands = EditorCommands()
    @StateObject private var searchController: WorkspaceSearchController
    @StateObject private var noteLinkPickerController: NoteLinkPickerController
    @StateObject private var backlinkController: BacklinkController
    @Namespace private var selectedTabHighlight
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var isShowingTrash = false
    @State private var isShowingDictationHistory = false
    @State private var isShowingAgentActivity = false
    @State private var notePendingDeletion: Note?
    @State private var folderPendingDeletion: Folder?
    @State private var dontAskAgainForDeletion = false
    @State private var notePendingAgentShare: Note?
    @State private var exportDocument: NoteFileDocument?
    @State private var exportType = NoteFileDocument.markdownContentType
    @State private var exportFilename = "Untitled.md"
    @State private var noteDropSource: NoteDropSource?
    @State private var tabDragDestinationID: UUID?
    @State private var tabColorPickerNoteID: UUID?
    @State private var activeFolderID: UUID?
    @State private var bannerDismissalState = NotesPanelBannerDismissalState()
    @State private var restoreEditorFocusAfterHide = false
    @State private var searchPointerActivationPending = false
    @FocusState private var editorFocus: EditorFocus?

    init(
      dictationRuntime: DictationRuntime,
      isPinned: Bool = false,
      sizing: NotesPanelSizing = .storedPreferences,
      editorCommands: EditorCommands? = nil,
      searchController: WorkspaceSearchController? = nil,
      noteLinkPickerController: NoteLinkPickerController? = nil,
      backlinkController: BacklinkController? = nil
    ) {
      let searchController = searchController ?? WorkspaceSearchController()
      let noteLinkPickerController = noteLinkPickerController ?? NoteLinkPickerController()
      self.dictationRuntime = dictationRuntime
      self.isPinned = isPinned
      self.sizing = sizing
      _editorCommands = StateObject(wrappedValue: editorCommands ?? EditorCommands())
      _searchController = StateObject(wrappedValue: searchController)
      _noteLinkPickerController = StateObject(wrappedValue: noteLinkPickerController)
      _backlinkController = StateObject(wrappedValue: backlinkController ?? BacklinkController())
      noteLinkPickerController.setPresentationGuard { !searchController.isPresented }
    }

    var body: some View {
      ZStack {
        VStack(spacing: 0) {
          if let migrationError = appState.startupMigrationError {
            migrationFailure(migrationError)
          } else {
            header
            folderNavigator
            tabStrip
            Divider().opacity(0.35)
            if let title = modifierRecoveryPresentation.recoveryButtonTitle {
              let occurrence = NotesPanelBannerOccurrence.modifierRecovery(
                statusCopy: modifierRecoveryPresentation.statusCopy,
                recoveryButtonTitle: title
              )
              if bannerDismissalState.isPresented(occurrence) {
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
                  NotesPanelBannerCloseButton(
                    label: "modifier monitoring recovery",
                    action: { dismissBanner(occurrence) }
                  )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.35))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Dictation shortcut unavailable")
              }
            }
            if let failure = dictationRuntime.captureFailure {
              let occurrence = NotesPanelBannerOccurrence.captureFailure(
                message: failure.message,
                actionPanes: failure.actions.map(\.pane)
              )
              if bannerDismissalState.isPresented(occurrence) {
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
                  NotesPanelBannerCloseButton(
                    label: "dictation capture failure",
                    action: { dismissBanner(occurrence) }
                  )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.35))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Dictation unavailable")
              }
            }
            if let banner = appState.agentBannerPresentation {
              let occurrence = NotesPanelBannerOccurrence.agentChange(
                changeID: banner.feedback.changeID,
                count: banner.count
              )
              if bannerDismissalState.isPresented(occurrence) {
                AgentChangeBanner(
                  presentation: banner,
                  motion: motion,
                  onUndo: { Task { await appState.undoLatestAgentChange() } },
                  onDismiss: { dismissBanner(occurrence) }
                )
                .animation(motion.quick, value: banner)
              }
            }
            scopedEditor
              .frame(minHeight: 80)
              .layoutPriority(1)
            if let error = appState.saveError {
              Text("Could not save: \(error)")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .allowsHitTesting(!searchController.isPresented)
        .allowsHitTesting(!isBlockingOverlayPresented)
        .disabled(searchController.isPresented)
        .disabled(isBlockingOverlayPresented)
        .accessibilityHidden(searchController.isPresented)
        .accessibilityHidden(isBlockingOverlayPresented)
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
      .background(
        WorkspaceSearchWindowReader(controller: searchController)
          .frame(width: 0, height: 0)
      )
      .background(
        NoteLinkPickerWindowReader(controller: noteLinkPickerController)
          .frame(width: 0, height: 0)
      )
      .onChange(of: activeBannerOccurrences, initial: true) { _, occurrences in
        bannerDismissalState.reconcile(activeOccurrences: occurrences)
      }
      .onReceive(dictationRuntime.$phase) { phase in
        bannerDismissalState.dictationPhaseDidEmit(phase)
      }
      .onReceive(dictationRuntime.$captureFailure) { failure in
        guard failure == nil else { return }
        bannerDismissalState.forgetDismissedOccurrences(in: .captureFailure)
      }
      .onReceive(dictationRuntime.$modifierMonitorState) { monitorState in
        guard monitorState == .stopped || monitorState == .running else {
          return
        }
        bannerDismissalState.forgetDismissedOccurrences(in: .modifierRecovery)
      }
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
      .sheet(isPresented: $isShowingDictationHistory) {
        DictationHistoryView(
          history: dictationRuntime.historyController,
          onOpenDestination: openHistoryDestination
        )
      }
      .sheet(isPresented: $isShowingAgentActivity) {
        AgentActivityView { noteID in
          if activateNoteAndScope(noteID) {
            isShowingAgentActivity = false
          }
        }
        .environmentObject(appState)
      }
      .sheet(item: $notePendingAgentShare) { note in
        AgentNoteAccessEditorView(
          note: note,
          onDismiss: { notePendingAgentShare = nil }
        )
          .environmentObject(appState)
      }
      .onAppear {
        dictationRuntime.registerEditor(editorCommands)
      }
      .onDisappear {
        dictationRuntime.unregisterEditor(editorCommands)
      }
      .overlay {
        ZStack {
          if isShowingTrash {
            TrashPanelOverlay(
              onDone: { isShowingTrash = false }
            )
            .transition(
              .opacity.combined(
                with: .scale(scale: reduceMotion ? 1 : 0.985)
              )
            )
          }

          if let folderPendingDeletion {
            FolderDeleteConfirmationOverlay(
              folder: folderPendingDeletion,
              onCancel: { self.folderPendingDeletion = nil },
              onConfirm: { confirmFolderDeletion(folderPendingDeletion) }
            )
            .transition(
              .opacity.combined(
                with: .scale(scale: reduceMotion ? 1 : 0.985)
              )
            )
          }

          if let notePendingDeletion {
            DeleteConfirmationOverlay(
              note: notePendingDeletion,
              dontAskAgain: $dontAskAgainForDeletion,
              onCancel: {
                self.notePendingDeletion = nil
                self.dontAskAgainForDeletion = false
              },
              onConfirm: { confirmDeletion(notePendingDeletion) }
            )
            .transition(
              .opacity.combined(
                with: .scale(scale: reduceMotion ? 1 : 0.985)
              )
            )
          }
        }
        .animation(motion.standard, value: isShowingTrash)
        .animation(motion.standard, value: folderPendingDeletion?.id)
        .animation(motion.standard, value: notePendingDeletion?.id)
      }
      .overlay {
        ZStack {
          if searchController.isPresented && !noteLinkPickerController.isPresented {
            WorkspaceSearchView(
              controller: searchController,
              notes: appState.workspace.notes,
              accent: Color(hex: appState.preferences.accentHex) ?? .accentColor,
              presentationID: searchController.presentationID,
              reduceMotion: reduceMotion,
              currentNoteIDs: {
                Set(appState.workspace.notes.map(\.id))
              },
              onActivate: { noteID in
                guard activateNoteAndScope(noteID) else { return }
              },
              onDismiss: dismissWorkspaceSearch
            )
            .id(searchController.presentationID)
            .zIndex(2)
            .transition(workspaceSearchPresentationTransition)
          }
        }
      }
      .overlay {
        if noteLinkPickerController.isPresented {
          NoteLinkPickerView(
            controller: noteLinkPickerController,
            notes: appState.workspace.notes,
            foldersByID: folderNamesByID,
            accent: Color(hex: appState.preferences.accentHex) ?? .accentColor,
            currentNoteIDs: { Set(appState.workspace.notes.map(\.id)) },
            currentSource: {
              guard let source = visibleSelectedNote else { return nil }
              return (source.id, source.revision)
            },
            onChoose: insertNoteLink
          )
          .zIndex(3)
        }
      }
      .task {
        await appState.waitUntilInitialLoad()
        guard !Task.isCancelled else { return }
        activeFolderID = appState.folderScopeForSelectedNote()
        backlinkController.refresh(liveNotes: appState.workspace.notes)
      }
      .onChange(of: appState.workspace.notes) { _, notes in
        backlinkController.refresh(liveNotes: notes)
      }
      .onChange(of: searchController.isPresented) { _, isPresented in
        if !isPresented {
          searchPointerActivationPending = false
        }
        if isPresented, noteLinkPickerController.isPresented {
          dismissWorkspaceSearch()
        }
      }
      .onChange(of: noteLinkPickerController.isPresented) { _, isPresented in
        if isPresented, searchController.isPresented {
          dismissWorkspaceSearch()
        }
      }
      .onChange(of: appState.workspace.folders) { _, folders in
        guard let activeFolderID,
          !folders.contains(where: { $0.id == activeFolderID })
        else { return }
        self.activeFolderID = nil
      }
      .onChange(of: appState.workspace.selectedNoteID) { oldID, newID in
        guard isShowingTrash, oldID != newID else { return }
        if let newID {
          activeFolderID = appState.folderID(for: newID)
        } else {
          activeFolderID = nil
        }
      }
    }

    private var modifierRecoveryPresentation: DictationModifierSettingsPresentation {
      .init(
        selected: appState.preferences.dictationModifierKey,
        monitorStatus: dictationRuntime.modifierMonitorState,
        canChange: dictationRuntime.canChangeModifier
      )
    }

    private var activeBannerOccurrences: Set<NotesPanelBannerOccurrence> {
      let modifierRecovery = modifierRecoveryPresentation.recoveryButtonTitle.map {
        NotesPanelBannerOccurrence.modifierRecovery(
          statusCopy: modifierRecoveryPresentation.statusCopy,
          recoveryButtonTitle: $0
        )
      }
      let captureFailure = dictationRuntime.captureFailure.map {
        NotesPanelBannerOccurrence.captureFailure(
          message: $0.message,
          actionPanes: $0.actions.map(\.pane)
        )
      }
      let agentChange = appState.agentBannerPresentation.map {
        NotesPanelBannerOccurrence.agentChange(
          changeID: $0.feedback.changeID,
          count: $0.count
        )
      }
      return NotesPanelBannerPolicy.activeOccurrences(
        modifierRecovery: modifierRecovery,
        captureFailure: captureFailure,
        routineRecoveryAction: dictationRuntime.recoveryAction,
        agentChange: agentChange
      )
    }

    private func dismissBanner(_ occurrence: NotesPanelBannerOccurrence) {
      withTransaction(Transaction(animation: nil)) {
        bannerDismissalState.dismiss(occurrence)
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
      let backlinkEntries = backlinkController.incoming(to: appState.workspace.selectedNoteID)
      return HStack(spacing: 10) {
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
        }
          .font(.headline)
        Spacer()
        SaveFeedbackView(status: appState.saveStatus, motion: motion)
        Button {
          backlinkController.toggleDisclosure()
        } label: {
          Image(systemName: "link")
            .frame(width: 22, height: 22)
        }
        .accessibilityIdentifier("backlinks-toolbar-button")
        .accessibilityLabel("Backlinks")
        .accessibilityValue(
          backlinkEntries.count == 1
            ? "1 backlink"
            : "\(backlinkEntries.count) backlinks"
        )
        .accessibilityHint("Show notes linking here")
        .help("Backlinks")
        .popover(isPresented: backlinksPopoverPresentation, arrowEdge: .top) {
          BacklinksView(
            entries: backlinkEntries,
            foldersByID: folderNamesByID,
            onOpen: { noteID in
              if backlinkController.isExpanded {
                backlinkController.toggleDisclosure()
              }
              openNoteLink(noteID)
            }
          )
          .frame(width: 320)
        }
        Button {
          let pointerActivation = searchPointerActivationPending
          searchPointerActivationPending = false
          guard !pointerActivation else { return }
          Task { @MainActor in
            await Task.yield()
            guard !searchController.isPresented else { return }
            presentWorkspaceSearch(activation: .keyboard)
          }
        } label: {
          Image(systemName: "magnifyingglass")
            .opacity(searchController.isPresented ? 0 : 1)
            .accessibilityHidden(true)
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel("Search notes")
        .accessibilityHint("Search note titles and bodies")
        .help("Search notes (⌘F)")
        .simultaneousGesture(
          TapGesture().onEnded {
            guard !noteLinkPickerController.isPresented else { return }
            searchPointerActivationPending = true
            presentWorkspaceSearch(activation: .pointer)
          }
        )
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
          if reduceMotion {
            appState.updatePreferences { $0.showFormattingBar.toggle() }
          } else {
            withAnimation(motion.quick) {
              appState.updatePreferences { $0.showFormattingBar.toggle() }
            }
          }
        } label: {
          Image(systemName: "chevron.up")
            .rotationEffect(
              .degrees(appState.preferences.showFormattingBar ? 0 : 180)
            )
            .animation(
              reduceMotion ? nil : motion.quick,
              value: appState.preferences.showFormattingBar
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
          if let note = visibleSelectedNote {
            Button(AgentCapabilityPresentation.manageAgentAccessTitle) {
              notePendingAgentShare = note
            }
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
        draggedSource: $noteDropSource,
        activeFolderID: activeFolderID,
        onSelect: selectFolder,
        onDelete: { folderPendingDeletion = $0 },
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
      _ = activateNoteAndScope(first.id)
    }

    private func activateNoteAndScope(_ noteID: UUID) -> Bool {
      guard appState.workspace.notes.contains(where: { $0.id == noteID }) else {
        return false
      }
      activeFolderID = appState.folderID(for: noteID)
      if appState.workspace.selectedNoteID != noteID {
        appState.select(noteID)
      }
      return true
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

    private func confirmFolderDeletion(_ folder: Folder) {
      folderPendingDeletion = nil
      deleteFolder(folder.id)
    }

    private var tabStrip: some View {
      ScrollViewReader { scrollProxy in
        GeometryReader { proxy in
          let tabViewportWidth = TabOverflowPresentation.tabViewportWidth(totalStripWidth: proxy.size.width)
        HStack(spacing: 0) {
          ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 0) {
                Color.clear
                  .frame(width: 0, height: 0)
                  .id(TabScrollTarget.leading)
                HStack(spacing: 6) {
                ForEach(visibleNotes) { note in
            Button {
              _ = activateNoteAndScope(note.id)
            } label: {
              HStack(spacing: 4) {
                if note.isPinned {
                  Image(systemName: "pin.fill")
                    .font(.caption2)
                }
                Text(note.displayTitle).lineLimit(1)
                if appState.isSharedWithAnyActiveProfile(note.id) {
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
            .accessibilityIdentifier("note-tab-\(note.id.uuidString)")
            .onDrag {
              let source = NoteDropSource(
                noteID: note.id,
                sourceFolderID: note.folderID,
                dragSessionID: UUID()
              )
              noteDropSource = source
              tabDragDestinationID = nil
              _ = activateNoteAndScope(note.id)
              return FolderDragPayload.noteProvider(source: source)
            }
            .onDrop(
              of: [FolderDragPayload.noteType],
              delegate: TabDropDelegate(
                destinationID: note.id,
                activeFolderID: activeFolderID,
                currentNotes: { visibleNotes },
                draggedSource: $noteDropSource,
                lastDestinationID: $tabDragDestinationID,
                move: { id, localDestination in
                  _ = appState.moveNote(
                    id,
                    inFolderID: activeFolderID,
                    toVisibleIndex: localDestination
                  )
                }
              )
            )
            .transition(
              .opacity.combined(
                with: .offset(x: motion.offset)
              )
            )
            .contextMenu {
              Button(
                note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin"
              ) {
                guard isNoteVisible(note.id) else { return }
                appState.togglePinned(note.id)
              }
              Button("Move Left", systemImage: "arrow.left") {
                move(note, offset: -1)
              }
              Button("Move Right", systemImage: "arrow.right") {
                move(note, offset: 1)
              }
              let moveToFolder: (UUID?) -> Void = { destinationFolderID in
                guard isNoteVisible(note.id),
                  let currentNote = appState.workspace.notes.first(where: { $0.id == note.id })
                else { return }
                _ = appState.moveNote(
                  note.id,
                  fromFolderID: currentNote.folderID,
                  toFolderID: destinationFolderID,
                  activeFolderID: activeFolderID
                )
              }
              Menu("Move to Folder", systemImage: "folder") {
                Button {
                  moveToFolder(nil)
                } label: {
                  HStack {
                    Text("Unfiled")
                    if note.folderID == nil {
                      Spacer()
                      Image(systemName: "checkmark")
                    }
                  }
                }
                .disabled(note.folderID == nil)
                ForEach(appState.workspace.folders, id: \.id) { folder in
                  Button {
                    moveToFolder(folder.id)
                  } label: {
                    HStack {
                      Text(folder.name)
                      if note.folderID == folder.id {
                        Spacer()
                        Image(systemName: "checkmark")
                      }
                    }
                  }
                  .disabled(note.folderID == folder.id)
                }
              }
              Button("Tab Color...", systemImage: "paintpalette") {
                guard isNoteVisible(note.id) else { return }
                tabColorPickerNoteID = note.id
              }
              .accessibilityValue(tabColorAccessibilityValue(for: note.tabColorHex))
              Button(AgentCapabilityPresentation.manageAgentAccessTitle) {
                guard isNoteVisible(note.id) else { return }
                notePendingAgentShare = note
              }
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
              }
              .padding(.horizontal, 12)
              .frame(height: 37, alignment: .center)
              .animation(motion.spatial, value: appState.workspace.selectedNoteID)
              .animation(motion.spatial, value: visibleNotes.map(\.id))
                Color.clear
                  .frame(width: 0, height: 0)
                  .id(TabScrollTarget.trailing)
              }
            }
          }
          .frame(width: tabViewportWidth, alignment: .leading)

          HStack(spacing: 0) {
            Button {
              scrollProxy.scrollTo(TabScrollTarget.leading, anchor: .leading)
            } label: {
              Image(systemName: "chevron.left")
                .font(.caption)
                .frame(width: 28, height: 28)
                .frame(width: 28, height: 37)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reveal earlier tabs")
            .help("Show earlier tabs")
            .disabled(visibleNotes.isEmpty)

            Button {
              scrollProxy.scrollTo(TabScrollTarget.trailing, anchor: .trailing)
            } label: {
              Image(systemName: "chevron.right")
                .font(.caption)
                .frame(width: 28, height: 28)
                .frame(width: 28, height: 37)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reveal later tabs")
            .help("Show later tabs")
            .disabled(visibleNotes.isEmpty)
          }
          .frame(width: 56, height: 37, alignment: .center)
        }
        }
        .frame(height: 37)
      }
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private var workspaceSearchPresentationTransition: AnyTransition {
      switch searchController.presentationKind {
      case .inline:
        return .opacity.combined(
          with: .scale(scale: 0.98, anchor: .topTrailing)
        )
      case .crossfade:
        return .opacity
      case .instant:
        return .identity
      }
    }

    private func presentWorkspaceSearch(activation: WorkspaceSearchActivation) {
      guard !noteLinkPickerController.isPresented else { return }
      let presentation = WorkspaceSearchPresentationKind.resolve(
        activation: activation,
        reduceMotion: reduceMotion
      )
      withAnimation(
        motion.presentationAnimation(for: presentation.interactionSource)
      ) {
        if presentation == .instant {
          searchController.present(for: appState.workspace.selectedNoteID)
        } else {
          searchController.present(
            for: appState.workspace.selectedNoteID,
            presentation: presentation
          )
        }
      }
    }

    private func dismissWorkspaceSearch() {
      guard searchController.isPresented else { return }
      withAnimation(
        searchController.presentationKind.usesAnimatedDismissal ? motion.quick : nil
      ) {
        searchController.dismiss()
      }
    }

    private var backlinksPopoverPresentation: Binding<Bool> {
      Binding(
        get: { backlinkController.isExpanded },
        set: { isPresented in
          guard backlinkController.isExpanded != isPresented else { return }
          backlinkController.toggleDisclosure()
        }
      )
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
      guard isNoteVisible(noteID), activateNoteAndScope(noteID) else {
        tabColorPickerNoteID = nil
        return
      }
      appState.setSelectedTabColor(hex)
      tabColorPickerNoteID = nil
    }

    private func tabColorAccessibilityValue(for hex: String?) -> String {
      guard let hex else { return "None" }
      return FleckPaletteOption.paletteName(for: NSColor(hex: hex)) ?? "Custom"
    }

    private func performShortcut(_ action: Shortcut.Action) {
      guard !isBlockingOverlayPresented else { return }
      switch action {
      case .togglePanel:
        NSApp.keyWindow?.orderOut(nil)
      case .newNote:
        appState.addNote(inFolderID: activeFolderID)
      case .closeNote:
        if let note = visibleSelectedNote {
          requestDeletion(note)
        }
      case .nextNote:
        appState.selectAdjacentNote(forward: true, inFolderID: activeFolderID)
      case .previousNote:
        appState.selectAdjacentNote(forward: false, inFolderID: activeFolderID)
      }
    }

    private func requestDeletion(_ note: Note) {
      guard isNoteVisible(note.id) else { return }
      if appState.preferences.confirmBeforeMovingNotesToTrash {
        dontAskAgainForDeletion = false
        notePendingDeletion = note
      } else {
        appState.moveToTrash(note.id, activeFolderID: activeFolderID)
      }
    }

    private func confirmDeletion(_ note: Note) {
      guard isNoteVisible(note.id) else {
        notePendingDeletion = nil
        dontAskAgainForDeletion = false
        return
      }
      let shouldSuppressConfirmation = dontAskAgainForDeletion
      _ = appState.moveToTrash(
        note.id,
        activeFolderID: activeFolderID,
        suppressConfirmation: shouldSuppressConfirmation
      )
      notePendingDeletion = nil
      dontAskAgainForDeletion = false
    }

    private func openHistoryDestination(_ noteID: UUID) {
      if activateNoteAndScope(noteID) {
        isShowingDictationHistory = false
      }
    }

    private func presentPersistentWindow(_ present: () -> Void) {
      NSApp.activate()
      present()
      DispatchQueue.main.async {
        NSApp.activate()
      }
    }

    private func move(_ note: Note, offset: Int) {
      guard isNoteVisible(note.id) else { return }
      guard let index = visibleNotes.firstIndex(where: { $0.id == note.id }) else {
        return
      }
      guard let localDestination = TabDragReorder.partitionLocalDestination(
        draggedID: note.id,
        absoluteDestination: index + offset,
        visibleNotes: visibleNotes
      ) else { return }
      _ = appState.moveNote(
        note.id,
        inFolderID: activeFolderID,
        toVisibleIndex: localDestination
      )
    }

    private func startExport(_ format: NoteExportFormat) {
      guard let note = visibleSelectedNote else { return }
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

    private var isBlockingOverlayPresented: Bool {
      searchController.isPresented || noteLinkPickerController.isPresented
        || notePendingDeletion != nil || folderPendingDeletion != nil || isShowingTrash
    }

    private var folderNamesByID: [UUID: String] {
      Dictionary(uniqueKeysWithValues: appState.workspace.folders.map { ($0.id, $0.name) })
    }

    private func insertNoteLink(targetID: UUID, replacing range: NSRange) {
      guard !searchController.isPresented,
        let sourceID = noteLinkPickerController.presentedSourceNoteID,
        let sourceRevision = noteLinkPickerController.presentedSourceRevision,
        let selectedNote = visibleSelectedNote,
        selectedNote.id == sourceID,
        selectedNote.revision == sourceRevision,
        let target = appState.workspace.notes.first(where: { $0.id == targetID }),
        let textView = editorCommands.textView,
        range.location >= 0,
        NSMaxRange(range) <= (textView.string as NSString).length
      else {
        noteLinkPickerController.dismiss()
        return
      }

      guard editorCommands.insertNoteLink(
        replacing: range,
        label: target.displayTitle,
        targetNoteID: target.id
      ) else {
        noteLinkPickerController.dismiss()
        return
      }
    }

    private func openNoteLink(_ noteID: UUID) {
      guard appState.workspace.notes.contains(where: { $0.id == noteID }) else {
        appState.saveError = "Note unavailable"
        return
      }
      guard activateNoteAndScope(noteID) else {
        appState.saveError = "Note unavailable"
        return
      }
      DispatchQueue.main.async {
        guard self.visibleSelectedNote?.id == noteID,
          let textView = self.editorCommands.textView,
          let window = textView.window
        else { return }
        _ = window.makeFirstResponder(textView)
      }
    }

    private var visibleNotes: [Note] {
      appState.visibleNotes(in: activeFolderID)
    }

    private var visibleSelectedNote: Note? {
      guard let selectedID = appState.workspace.selectedNoteID else { return nil }
      return visibleNotes.first(where: { $0.id == selectedID })
    }

    private func isNoteVisible(_ noteID: UUID) -> Bool {
      visibleNotes.contains(where: { $0.id == noteID })
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
      .onChange(of: isEditorVisible) { _, isVisible in
        if isVisible {
          let restoreBodyFocus = restoreEditorFocusAfterHide
          restoreEditorFocusAfterHide = false
          DispatchQueue.main.async {
            guard self.isEditorVisible,
              let textView = self.editorCommands.textView,
              let window = textView.window
            else { return }
            self.editorCommands.refreshFormattingState()
            if restoreBodyFocus {
              _ = window.makeFirstResponder(textView)
            }
          }
        } else {
          let textView = editorCommands.textView
          restoreEditorFocusAfterHide = textView?.window?.firstResponder === textView
          neutralizeHiddenEditor()
        }
      }
    }

    private func neutralizeHiddenEditor() {
      let textView = editorCommands.textView
      editorCommands.cancelFocusedDictation()
      if let window = textView?.window {
        _ = window.makeFirstResponder(nil)
      }
      editorCommands.textView = nil
    }

    @ViewBuilder
    private var editor: some View {
      if let note = appState.selectedNote {
        VStack(spacing: 0) {
          if appState.preferences.showFormattingBar {
            FormattingBar(
              appState: appState,
              commands: editorCommands,
              dictationRuntime: dictationRuntime,
              isEditorVisible: isEditorVisible,
              isTitleFocused: editorFocus == .title,
              onDelete: {
                if let note = visibleSelectedNote {
                  requestDeletion(note)
                }
              }
            )
            .transition(
              .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
              )
            )
            .animation(reduceMotion ? nil : motion.quick, value: appState.preferences.showFormattingBar)
          }
          NativeRichTextEditor(
            text: note.body,
            richTextRTF: note.richTextRTF,
            title: note.title,
            titleFontFamily: note.titleFontFamily ?? appState.preferences.fontFamily,
            onTitleChange: { title in
              guard visibleSelectedNote?.id == note.id else { return }
              appState.updateSelected(title: title)
            },
            onTitleFocusChange: { isFocused in
              if isFocused {
                editorFocus = .title
              } else if editorFocus == .title {
                editorFocus = nil
              }
            },
            onChange: { body, richTextRTF in
              guard visibleSelectedNote?.id == note.id else { return }
              appState.updateSelected(body: body, richTextRTF: richTextRTF)
            },
            fontFamily: appState.preferences.fontFamily,
            fontSize: appState.preferences.fontSize,
            textColorHex: appState.preferences.editorTextHex,
            backgroundColorHex: appState.preferences.editorBackgroundHex,
            accentColorHex: appState.preferences.accentHex,
            reduceMotion: reduceMotion,
            automaticLists: appState.preferences.automaticLists,
            commands: editorCommands,
            isVisible: isEditorVisible,
            liveNoteIDs: Set(appState.workspace.notes.map(\.id)),
            onRequestNoteLink: { range in
              guard !isBlockingOverlayPresented,
                let source = visibleSelectedNote,
                source.id == note.id
              else { return }
              noteLinkPickerController.present(
                sourceNoteID: source.id,
                replacementRange: range,
                sourceRevision: source.revision
              )
            },
            onOpenNoteLink: openNoteLink,
            onUnavailableNoteLink: { appState.saveError = "Note unavailable" }
          )
          .focused($editorFocus, equals: .body)
          .background(
            EditorCommandVisibilityBoundary(
              appState: appState,
              dictationRuntime: dictationRuntime,
              commands: editorCommands,
              isVisible: isEditorVisible
            )
            .frame(width: 0, height: 0)
          )
          .id(note.id)
          .padding(.vertical, 10)
        }
      }
    }
  }

  private struct EditorCommandVisibilityBoundary: NSViewRepresentable {
    @ObservedObject var appState: AppState
    @ObservedObject var dictationRuntime: DictationRuntime
    let commands: EditorCommands
    let isVisible: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
      context.coordinator.isActive = true
      return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
      let generation = context.coordinator.beginUpdate(isVisible: isVisible)
      guard !isVisible else { return }
      DispatchQueue.main.async {
        guard context.coordinator.isActive,
          context.coordinator.generation == generation,
          !context.coordinator.isVisible
        else { return }
        let textView = commands.textView
        commands.cancelFocusedDictation()
        if let window = textView?.window {
          _ = window.makeFirstResponder(nil)
        }
        commands.textView = nil
      }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
      coordinator.isActive = false
      coordinator.generation &+= 1
    }

    final class Coordinator {
      var isVisible = true
      var isActive = true
      var generation: UInt64 = 0

      func beginUpdate(isVisible: Bool) -> UInt64 {
        generation &+= 1
        self.isVisible = isVisible
        return generation
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

    private enum NoteDropTarget: Equatable {
      case unfiled
      case folder(UUID)

      var folderID: UUID? {
        switch self {
        case .unfiled: return nil
        case .folder(let id): return id
        }
      }
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedRow: FocusedRow?
    @Binding private var draggedSource: NoteDropSource?
    @State private var editingFolderID: UUID?
    @State private var isCreatingFolder = false
    @State private var folderNameDraft = ""
    @State private var noteDropTarget: NoteDropTarget?
    @State private var isUnfiledHovered = false
    private let folderNavigatorMaxHeight: CGFloat = 32

    let activeFolderID: UUID?
    let onSelect: (UUID?) -> Void
    let onDelete: (Folder) -> Void
    let onOpenTrash: () -> Void

    init(
      draggedSource: Binding<NoteDropSource?>,
      activeFolderID: UUID?,
      onSelect: @escaping (UUID?) -> Void,
      onDelete: @escaping (Folder) -> Void,
      onOpenTrash: @escaping () -> Void
    ) {
      self._draggedSource = draggedSource
      self.activeFolderID = activeFolderID
      self.onSelect = onSelect
      self.onDelete = onDelete
      self.onOpenTrash = onOpenTrash
    }

    var body: some View {
      VStack(spacing: 3) {
        if isCreatingFolder {
          folderEditor(label: "New folder", focus: .newFolder)
        }

        HStack(spacing: 4) {
          rootRow

          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 3) {
              ForEach(appState.workspace.folders, id: \.id) { folder in
                folderRow(folder)
              }
            }
          }
          .frame(maxWidth: .infinity)
          .frame(maxHeight: folderNavigatorMaxHeight)
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Folders")

          Button {
            beginNewFolder()
          } label: {
            Image(systemName: "folder.badge.plus")
              .frame(width: 24, height: 24)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("New folder")
          .onDrop(of: [FolderDragPayload.folderType], isTargeted: nil) { providers, _ in
            handleFolderDrop(providers, beforeFolderID: nil)
          }

          Divider()
            .frame(height: 20)

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
          .fixedSize(horizontal: true, vertical: false)
          .buttonStyle(.plain)
          .focused($focusedRow, equals: .trash)
          .focusable()
          .accessibilityLabel("Trash")
          .accessibilityIdentifier("folder-trash")
          .accessibilityValue(
            appState.trashedNotes.isEmpty
              ? "Empty"
              : "\(appState.trashedNotes.count) notes"
          )
        }
      }
      .animation(folderMorphAnimation, value: isCreatingFolder)
      .onChange(of: draggedSource) { oldValue, newValue in
        if oldValue != newValue {
          noteDropTarget = nil
        }
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
        onDelete(folder)
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
    }

    private var rootRow: some View {
      let unfiledNotes = appState.visibleNotes(in: nil)
      return HStack(spacing: 0) {
        Button {
          onSelect(nil)
        } label: {
          rowLabel(
            name: "Unfiled",
            systemImage: "tray",
            count: unfiledNotes.count,
            isSelected: activeFolderID == nil,
            isEmpty: unfiledNotes.isEmpty,
            isDropTarget: isNoteDropTarget(.unfiled),
            isFocused: focusedRow == .unfiled,
            showsName: !isUnfiledCompact
          )
        }
        .buttonStyle(.plain)
        .modifier(
          FolderRowFocusPublisher(onFocusChange: { isFocused in
            updateFocusedRow(.unfiled, isFocused: isFocused)
          })
        )
        .focusable()
        .focused($focusedRow, equals: .unfiled)
        .focusEffectDisabled()
        .accessibilityLabel("Unfiled")
        .accessibilityIdentifier("folder-unfiled")
        .accessibilityValue(unfiledAccessibilityValue)
        .accessibilityAddTraits(activeFolderID == nil ? .isSelected : [])
        .accessibilityAction(named: Text("Toggle Unfiled compact mode")) {
          setUnfiledCompact(!isUnfiledCompact)
        }

        if showsUnfiledDisclosure {
          Button {
            setUnfiledCompact(!isUnfiledCompact)
          } label: {
            Image(systemName: isUnfiledCompact ? "chevron.right" : "chevron.left")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(width: 28, height: 28)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            isUnfiledCompact ? "Expand Unfiled" : "Collapse Unfiled"
          )
        }
      }
      .fixedSize(horizontal: true, vertical: false)
      .onHover { isUnfiledHovered = $0 }
      .contentShape(Rectangle())
      .onDrop(
        of: [FolderDragPayload.noteType],
        delegate: noteDropDelegate(.unfiled)
      )
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
            isEmpty: appState.visibleNotes(in: folder.id).isEmpty,
            isDropTarget: isNoteDropTarget(.folder(folder.id)),
            isFocused: focusedRow == .folder(folder.id)
          )
        }
        .buttonStyle(.plain)
        .modifier(
          FolderRowFocusPublisher(onFocusChange: { isFocused in
            updateFocusedRow(.folder(folder.id), isFocused: isFocused)
          })
        )
        .focusable()
        .focused($focusedRow, equals: .folder(folder.id))
        .focusEffectDisabled()
        .onDrag { FolderDragPayload.folderProvider(folderID: folder.id) }
        .onDrop(
          of: [FolderDragPayload.noteType],
          delegate: noteDropDelegate(.folder(folder.id))
        )
        .onDrop(of: [FolderDragPayload.folderType], isTargeted: nil) { providers, _ in
          handleFolderDrop(providers, beforeFolderID: folder.id)
        }
        .contextMenu {
          Button("Rename", systemImage: "pencil") {
            _ = beginRename(folderID: folder.id)
          }
          Button("Delete", systemImage: "trash", role: .destructive) {
            onDelete(folder)
          }
        }
        .accessibilityLabel(folder.name)
        .accessibilityIdentifier("folder-\(folder.id.uuidString)")
        .accessibilityValue(
          "\(appState.visibleNotes(in: folder.id).count) notes"
            + (activeFolderID == folder.id ? ", Selected" : "")
            + (appState.visibleNotes(in: folder.id).isEmpty ? ", Empty" : "")
            + (isNoteDropTarget(.folder(folder.id)) ? ", Drop target" : "")
        )
        .accessibilityAddTraits(activeFolderID == folder.id ? .isSelected : [])
      }
    }

    private struct FolderActionButtonStyle: ButtonStyle {
      enum Role: Equatable {
        case save
        case cancel
      }

      let role: Role
      let accent: Color
      let motion: AppMotion
      @Environment(\.isEnabled) private var isEnabled

      func makeBody(configuration: Configuration) -> some View {
        let isSave = role == .save
        return configuration.label
          .font(.caption.weight(isSave ? .semibold : .medium))
          .foregroundStyle(isSave ? accent : Color.secondary)
          .frame(height: 22)
          .padding(.horizontal, 8)
          .background(
            isSave
              ? accent.opacity(configuration.isPressed ? 0.24 : 0.16)
              : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )
          .scaleEffect(isEnabled && configuration.isPressed ? motion.pressScale : 1)
          .opacity(isEnabled ? 1 : 0.48)
          .animation(motion.quick, value: configuration.isPressed)
      }
    }

    @ViewBuilder
    private func folderEditor(label: String, focus: FocusedRow) -> some View {
      let accent = Color(hex: appState.preferences.accentHex) ?? .accentColor
      HStack(spacing: 5) {
        TextField(label, text: $folderNameDraft)
          .textFieldStyle(.roundedBorder)
          .focused($focusedRow, equals: focus)
          .onSubmit { commitFolderEditing() }
          .onExitCommand { cancelFolderEditing() }
        Button("Save") { commitFolderEditing() }
          .buttonStyle(FolderActionButtonStyle(role: .save, accent: accent, motion: motion))
          .disabled(
            folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          .accessibilityLabel("Save folder name")
        Button("Cancel", role: .cancel) { cancelFolderEditing() }
          .buttonStyle(FolderActionButtonStyle(role: .cancel, accent: accent, motion: motion))
          .accessibilityLabel("Cancel folder name")
      }
      .accessibilityElement(children: .contain)
    }

    private struct FolderRowFocusPublisher: ViewModifier {
      @Environment(\.isFocused) private var isNativeFocused
      let onFocusChange: (Bool) -> Void

      init(onFocusChange: @escaping (Bool) -> Void) {
        self.onFocusChange = onFocusChange
      }

      func body(content: Content) -> some View {
        content.onChange(of: isNativeFocused) { _, isFocused in
          onFocusChange(isFocused)
        }
      }
    }

    @ViewBuilder
    private func rowLabel(
      name: String,
      systemImage: String,
      count: Int,
      isSelected: Bool,
      isEmpty: Bool,
      isDropTarget: Bool = false,
      isFocused: Bool = false,
      showsName: Bool = true
    ) -> some View {
      HStack(spacing: 7) {
        Image(systemName: systemImage)
          .frame(width: 18)
        if showsName {
          Text(name)
            .lineLimit(1)
          Spacer(minLength: 4)
        } else {
          Spacer(minLength: 2)
        }
        Text(count, format: .number)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(minHeight: 24)
      .background(
        isDropTarget
          ? Color.accentColor.opacity(0.28)
          : (isSelected ? Color.accentColor.opacity(0.18) : .clear),
        in: RoundedRectangle(cornerRadius: 6)
      )
      .contentShape(RoundedRectangle(cornerRadius: 6))
      .overlay {
        if isFocused && !isSelected {
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
        }
      }
      .accessibilityHint(isEmpty ? "Empty folder" : "")
    }

    private func noteDropDelegate(_ target: NoteDropTarget) -> NoteDropDelegate {
      NoteDropDelegate(
        target: target,
        draggedSource: $draggedSource,
        dropTarget: $noteDropTarget,
        canAccept: { expectedSource, targetFolderID in
          canHighlightNoteDrop(
            expectedSource: expectedSource,
            targetFolderID: targetFolderID
          )
        },
        perform: { providers, targetFolderID, expectedSource in
          handleNoteDrop(
            providers,
            targetFolderID: targetFolderID,
            expectedSource: expectedSource
          )
        }
      )
    }

    private func isNoteDropTarget(_ target: NoteDropTarget) -> Bool {
      guard let draggedSource else { return false }
      return noteDropTarget == target
        && canHighlightNoteDrop(
          expectedSource: draggedSource,
          targetFolderID: target.folderID
        )
    }

    private func canHighlightNoteDrop(
      expectedSource: NoteDropSource,
      targetFolderID: UUID?
    ) -> Bool {
      guard draggedSource == expectedSource else { return false }
      return NoteDropPresentation.isValidTarget(
        draggedSource: expectedSource,
        targetFolderID: targetFolderID,
        notes: appState.workspace.notes,
        validTargetFolderIDs: Set(appState.workspace.folders.map(\.id))
      )
    }

    private var isUnfiledCompact: Bool {
      appState.preferences.isUnfiledCompact
    }

    private var unfiledAccessibilityValue: String {
      let notes = appState.visibleNotes(in: nil)
      var parts = ["\(notes.count) notes"]
      if activeFolderID == nil { parts.append("Selected") }
      if notes.isEmpty { parts.append("Empty") }
      if isUnfiledCompact { parts.append("Compact") }
      if isNoteDropTarget(.unfiled) { parts.append("Drop target") }
      return parts.joined(separator: ", ")
    }

    private var showsUnfiledDisclosure: Bool {
      !isUnfiledCompact || isUnfiledHovered || focusedRow == .unfiled
    }

    private func setUnfiledCompact(_ compact: Bool) {
      if reduceMotion {
        appState.updatePreferences { $0.isUnfiledCompact = compact }
      } else {
        withAnimation(motion.quick) {
          appState.updatePreferences { $0.isUnfiledCompact = compact }
        }
      }
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private var folderMorphAnimation: Animation? {
      reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0)
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

    private func updateFocusedRow(_ row: FocusedRow, isFocused: Bool) {
      if isFocused {
        focusedRow = row
      } else if focusedRow == row {
        focusedRow = nil
      }
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

    private func handleNoteDrop(
      _ providers: [NSItemProvider],
      targetFolderID: UUID?,
      expectedSource: NoteDropSource
    ) -> Bool {
      noteDropTarget = nil
      guard draggedSource == expectedSource,
        FolderDragPayload.noteSource(from: providers) == expectedSource,
        let provider = providers.first(where: {
          $0.registeredTypeIdentifiers.contains(FolderDragPayload.noteType.identifier)
        })
      else {
        if draggedSource == expectedSource { draggedSource = nil }
        return false
      }
      provider.loadDataRepresentation(forTypeIdentifier: FolderDragPayload.noteType.identifier) {
        data, _ in
        Task { @MainActor in
          defer {
            if self.draggedSource == expectedSource { self.draggedSource = nil }
            self.noteDropTarget = nil
          }
          guard self.draggedSource == expectedSource else { return }
          guard let data, let payload = FolderDragPayload.noteValue(from: data) else { return }
          guard payload == expectedSource else { return }
          guard targetFolderID == nil || appState.workspace.folders.contains(where: {
            $0.id == targetFolderID
          }) else { return }
          guard let note = appState.workspace.notes.first(where: { $0.id == payload.noteID }),
            note.folderID == payload.sourceFolderID,
            note.folderID != targetFolderID
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

    private struct NoteDropDelegate: DropDelegate {
      let target: NoteDropTarget
      @Binding var draggedSource: NoteDropSource?
      @Binding var dropTarget: NoteDropTarget?
      let canAccept: (NoteDropSource, UUID?) -> Bool
      let perform: ([NSItemProvider], UUID?, NoteDropSource) -> Bool

      private func matchingSource(_ info: DropInfo) -> NoteDropSource? {
        guard let expectedSource = draggedSource,
          let providerSource = FolderDragPayload.noteSource(
            from: info.itemProviders(for: [FolderDragPayload.noteType])
          ),
          providerSource == expectedSource,
          canAccept(expectedSource, target.folderID)
        else { return nil }
        return expectedSource
      }

      func validateDrop(info: DropInfo) -> Bool {
        matchingSource(info) != nil
      }

      func dropEntered(info: DropInfo) {
        if matchingSource(info) != nil {
          dropTarget = target
        } else if dropTarget == target {
          dropTarget = nil
        }
      }

      func dropUpdated(info: DropInfo) -> DropProposal? {
        guard matchingSource(info) != nil else { return nil }
        return DropProposal(operation: .move)
      }

      func dropExited(info: DropInfo) {
        if dropTarget == target { dropTarget = nil }
      }

      func performDrop(info: DropInfo) -> Bool {
        let providerSource = FolderDragPayload.noteSource(
          from: info.itemProviders(for: [FolderDragPayload.noteType])
        )
        guard let expectedSource = draggedSource,
          providerSource == expectedSource
        else {
          if dropTarget == target { dropTarget = nil }
          return false
        }
        guard canAccept(expectedSource, target.folderID) else {
          if draggedSource == expectedSource { draggedSource = nil }
          if dropTarget == target { dropTarget = nil }
          return false
        }
        dropTarget = nil
        let accepted = perform(
          info.itemProviders(for: [FolderDragPayload.noteType]),
          target.folderID,
          expectedSource
        )
        if !accepted && draggedSource == expectedSource { draggedSource = nil }
        return accepted
      }
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

  struct TrashPanelOverlay: View {
    let onDone: () -> Void

    var body: some View {
      ZStack {
        Color.black.opacity(0.28)
          .ignoresSafeArea()
          .accessibilityHidden(true)

        TrashView(onDone: onDone)
          .frame(maxWidth: 520, maxHeight: 400)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
          .clipShape(RoundedRectangle(cornerRadius: 14))
          .shadow(radius: 20, y: 8)
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Trash")
          .padding(8)

        Button("Close Trash", action: onDone)
          .keyboardShortcut(.cancelAction)
          .frame(width: 0, height: 0)
          .opacity(0)
          .accessibilityHidden(true)
      }
    }
  }

  struct FolderDeleteConfirmationOverlay: View {
    let folder: Folder
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
      ZStack {
        Color.black.opacity(0.28)
          .ignoresSafeArea()
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Delete \(folder.name)?")
              .font(.headline)
            Text("Notes in this folder move to Unfiled. No notes are deleted.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }

          HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
              .keyboardShortcut(.cancelAction)
            Button("Delete Folder", role: .destructive, action: onConfirm)
              .keyboardShortcut(.defaultAction)
          }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Delete folder confirmation")
      }
    }
  }

  private struct DeleteConfirmationOverlay: View {
    let note: Note
    @Binding var dontAskAgain: Bool
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

          Toggle("Don't ask me again", isOn: $dontAskAgain)
            .toggleStyle(.checkbox)

          HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
              .keyboardShortcut(.cancelAction)
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

  func routeFontFamilyAction(
    family: String,
    isTitleFocused: Bool,
    titleMutation: (String) -> Void,
    bodyMutation: (String) -> Void
  ) {
    if isTitleFocused {
      titleMutation(family)
    } else {
      bodyMutation(family)
    }
  }

  private struct FormattingBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var appState: AppState
    @ObservedObject var commands: EditorCommands
    @ObservedObject var dictationRuntime: DictationRuntime
    let isEditorVisible: Bool
    let isTitleFocused: Bool
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
            guard isEditorVisible else { return }
            Task { await dictationRuntime.cancel() }
          }
          .disabled(!dictationRuntime.canCancel)
        } label: {
          ToolbarIconLabel(
            systemImage: dictationRuntime.microphoneSymbol,
            isActive: dictationRuntime.isListening
          )
        } primaryAction: {
          guard isEditorVisible,
            dictationRuntime.toolbarPresentation.primaryAction != nil
          else { return }
          Task { await dictationRuntime.toggle() }
        }
        .accessibilityLabel(dictationRuntime.microphoneHelp)
        .accessibilityAction(named: Text("Cancel Dictation")) {
          guard isEditorVisible else { return }
          Task { await dictationRuntime.cancel() }
        }
        .help(dictationRuntime.microphoneHelp)
        Divider().frame(height: 15)
        Button {
          guard isEditorVisible else { return }
          commands.undo()
        } label: {
          ToolbarIconLabel(systemImage: "arrow.uturn.backward")
        }
        .accessibilityLabel("Undo")
          .keyboardShortcut("z", modifiers: .command)
        Button {
          guard isEditorVisible else { return }
          commands.redo()
        } label: {
          ToolbarIconLabel(systemImage: "arrow.uturn.forward")
        }
        .accessibilityLabel("Redo")
          .keyboardShortcut("z", modifiers: [.command, .shift])
        Divider().frame(height: 15)
        Button {
          guard isEditorVisible else { return }
          commands.toggleBold()
        } label: {
          ToolbarIconLabel(systemImage: "bold", isActive: commands.isBold)
        }
        .accessibilityLabel("Bold")
          .keyboardShortcut("b", modifiers: .command)
          .accessibilityValue(commands.isBold ? "On" : "Off")
        Button {
          guard isEditorVisible else { return }
          commands.toggleItalic()
        } label: {
          ToolbarIconLabel(systemImage: "italic", isActive: commands.isItalic)
        }
        .accessibilityLabel("Italic")
          .keyboardShortcut("i", modifiers: .command)
          .accessibilityValue(commands.isItalic ? "On" : "Off")
        Button {
          guard isEditorVisible else { return }
          commands.toggleUnderline()
        } label: {
          ToolbarIconLabel(systemImage: "underline", isActive: commands.isUnderlined)
        }
        .accessibilityLabel("Underline")
          .keyboardShortcut("u", modifiers: .command)
          .accessibilityValue(commands.isUnderlined ? "On" : "Off")
        Button {
          guard isEditorVisible else { return }
          commands.toggleStrikethrough()
        } label: {
          ToolbarIconLabel(systemImage: "strikethrough")
        }
        .accessibilityLabel("Strikethrough")
        Menu {
          ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
            Button {
              guard isEditorVisible else { return }
              applyFontFamily(family)
            } label: {
              HStack {
                Text(family)
                if !isFontFamilyMixed, currentFontFamily == family {
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
          isFontFamilyMixed ? "Mixed" : currentFontFamily ?? "Automatic"
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
          guard isEditorVisible else { return }
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
              guard isEditorVisible else {
                isForegroundColorPickerPresented = false
                return
              }
              commands.applyForegroundColor(hex.flatMap { NSColor(hex: $0) })
              isForegroundColorPickerPresented = false
            },
            onCancel: { isForegroundColorPickerPresented = false }
          )
        }
        Button {
          guard isEditorVisible else { return }
          isBackgroundColorPickerPresented = true
        } label: {
          HighlighterMarkerIcon(
            backgroundColor: commands.currentBackgroundColor,
            isMixed: commands.isBackgroundColorMixed
          )
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
              guard isEditorVisible else {
                isBackgroundColorPickerPresented = false
                return
              }
              commands.applyBackgroundColor(hex.flatMap { NSColor(hex: $0) })
              isBackgroundColorPickerPresented = false
            },
            onCancel: { isBackgroundColorPickerPresented = false }
          )
        }
        Menu {
          Button("Disc (•)") {
            guard isEditorVisible else { return }
            commands.applyList(.bullet(.disc))
          }
          Button("Circle (◦)") {
            guard isEditorVisible else { return }
            commands.applyList(.bullet(.circle))
          }
          Button("Square (▪)") {
            guard isEditorVisible else { return }
            commands.applyList(.bullet(.square))
          }
          Button("Dash (–)") {
            guard isEditorVisible else { return }
            commands.applyList(.bullet(.dash))
          }
        } label: {
          ToolbarIconLabel(systemImage: "list.bullet")
        } primaryAction: {
          guard isEditorVisible else { return }
          commands.applyAutomaticList(.bullets)
        }
        .accessibilityLabel("Bullets")
        Menu {
          Button("Decimal (1.)") {
            guard isEditorVisible else { return }
            commands.applyList(.number(.decimal))
          }
          Button("Alphabetic (a.)") {
            guard isEditorVisible else { return }
            commands.applyList(.number(.alphabetic))
          }
          Button("Roman (i.)") {
            guard isEditorVisible else { return }
            commands.applyList(.number(.roman))
          }
        } label: {
          ToolbarIconLabel(systemImage: "list.number")
        } primaryAction: {
          guard isEditorVisible else { return }
          commands.applyAutomaticList(.numbers)
        }
        .accessibilityLabel("Numbers")
        Button {
          guard isEditorVisible else { return }
          commands.applyList(.checklist)
        } label: {
          ToolbarIconLabel(systemImage: "checklist")
        }
        .accessibilityLabel("Checklist")
        Spacer()
        Button(role: .destructive) {
          guard isEditorVisible else { return }
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
      .modifier(FormattingBarSurface())
      .padding(.horizontal, 10)
      .padding(.top, 8)
      .disabled(!isEditorVisible)
      .accessibilityLabel("Editor toolbar")
      .accessibilityHidden(!isEditorVisible)
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private var fontSizeDisplay: String {
      guard !commands.isFontSizeMixed, let size = commands.currentFontSize else { return "" }
      return String(format: "%.2f", size).replacingOccurrences(of: #"\.00$"#, with: "", options: .regularExpression)
    }

    private var currentFontFamily: String? {
      if isTitleFocused {
        return appState.selectedNote?.titleFontFamily ?? appState.preferences.fontFamily
      }
      return commands.currentFontFamily
    }

    private var isFontFamilyMixed: Bool {
      isTitleFocused ? false : commands.isFontFamilyMixed
    }

    private func applyFontFamily(_ family: String) {
      routeFontFamilyAction(
        family: family,
        isTitleFocused: isTitleFocused,
        titleMutation: { appState.setSelectedTitleFontFamily($0) },
        bodyMutation: { commands.applyFontFamily($0) }
      )
    }

    private func syncFontSizeText() {
      guard !isFontSizeFocused else { return }
      fontSizeText = fontSizeDisplay
    }

    private func applyFontSizeText() {
      guard isEditorVisible else { return }
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

  private struct FormattingBarSurface: ViewModifier {
    func body(content: Content) -> some View {
      if #available(macOS 26, *) {
        content.glassEffect(
          Glass.regular.tint(Color.black.opacity(0.18)),
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
      } else {
        content
          .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(.ultraThinMaterial)
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .fill(Color.black.opacity(0.10))
              }
          }
      }
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
    let activeFolderID: UUID?
    let currentNotes: () -> [Note]
    @Binding var draggedSource: NoteDropSource?
    @Binding var lastDestinationID: UUID?
    let move: (UUID, Int) -> Void

    func dropEntered(info: DropInfo) {
      let providerSource = FolderDragPayload.noteSource(
        from: info.itemProviders(for: [FolderDragPayload.noteType])
      )
      guard draggedSource == providerSource else { return }
      let result = TabDragReorder.performLiveMove(
        draggedSource: draggedSource,
        providerSource: providerSource,
        over: destinationID,
        activeFolderID: activeFolderID,
        currentNotes: currentNotes,
        lastDestinationID: lastDestinationID,
        move: move
      )
      lastDestinationID = result.destinationID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
      let providerSource = FolderDragPayload.noteSource(
        from: info.itemProviders(for: [FolderDragPayload.noteType])
      )
      guard draggedSource == providerSource,
        TabDragReorder.isValidLocalDrag(
          draggedSource: draggedSource,
          providerSource: providerSource,
          destinationID: destinationID,
          activeFolderID: activeFolderID,
          currentNotes: currentNotes()
        )
      else { return nil }
      return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
      let providerSource = FolderDragPayload.noteSource(
        from: info.itemProviders(for: [FolderDragPayload.noteType])
      )
      let accepted = draggedSource == providerSource
        && TabDragReorder.isValidLocalDrag(
          draggedSource: draggedSource,
          providerSource: providerSource,
          destinationID: destinationID,
          activeFolderID: activeFolderID,
          currentNotes: currentNotes()
        )
      if draggedSource == providerSource {
        draggedSource = nil
        lastDestinationID = nil
      }
      return accepted
    }
  }

  struct HighlighterMarkerShape: Shape {
    func path(in rect: CGRect) -> Path {
      let stemMinX = rect.minX + rect.width * 0.20
      let stemMaxX = rect.minX + rect.width * 0.80
      let stemTop = rect.minY + rect.height * 0.08
      let shoulderY = rect.minY + rect.height * 0.43
      let bodyBottom = rect.minY + rect.height * 0.57
      let bodyInset = rect.width * 0.08

      var path = Path()
      path.move(to: CGPoint(x: stemMinX, y: stemTop))
      path.addLine(to: CGPoint(x: stemMinX, y: shoulderY))
      path.addLine(
        to: CGPoint(x: stemMinX + bodyInset, y: bodyBottom)
      )
      path.addLine(
        to: CGPoint(x: stemMaxX - bodyInset, y: bodyBottom)
      )
      path.addLine(to: CGPoint(x: stemMaxX, y: shoulderY))
      path.addLine(to: CGPoint(x: stemMaxX, y: stemTop))
      path.move(to: CGPoint(x: stemMinX, y: shoulderY))
      path.addLine(to: CGPoint(x: stemMaxX, y: shoulderY))
      return path
    }
  }

  struct HighlighterMarkerNibShape: Shape {
    func path(in rect: CGRect) -> Path {
      let inkMinX = rect.minX + rect.width * 0.34
      let inkMaxX = rect.minX + rect.width * 0.70
      let inkTop = rect.minY + rect.height * 0.63
      let inkBottom = rect.minY + rect.height * 0.96
      let taperY = inkTop + (inkBottom - inkTop) * 0.38
      let lowerMinX = inkMinX + rect.width * 0.05

      var path = Path()
      path.move(to: CGPoint(x: inkMinX, y: inkTop))
      path.addLine(to: CGPoint(x: inkMaxX, y: inkTop))
      path.addLine(to: CGPoint(x: inkMaxX, y: taperY))
      path.addLine(to: CGPoint(x: lowerMinX, y: inkBottom))
      path.addLine(to: CGPoint(x: inkMinX, y: inkBottom))
      path.closeSubpath()
      return path
    }
  }

  struct HighlighterMarkerIcon: View {
    let inkColor: NSColor

    init(backgroundColor: NSColor?, isMixed: Bool) {
      self.inkColor = (!isMixed ? backgroundColor : nil)
        ?? FleckColorHex.nsColor(from: "#FFD600")!
    }

    var body: some View {
      ZStack {
        HighlighterMarkerNibShape()
          .fill(Color(nsColor: inkColor))
          .overlay {
            HighlighterMarkerNibShape()
              .stroke(.primary, lineWidth: 1.1)
          }
        HighlighterMarkerShape()
          .stroke(
            .primary,
            style: StrokeStyle(lineWidth: 1.15, lineCap: .butt, lineJoin: .miter)
          )
      }
        .frame(width: 20, height: 18)
        .frame(width: 28, height: 26)
        .background(.clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(RoundedRectangle(cornerRadius: 5))
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
