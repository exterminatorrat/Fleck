#if os(macOS)
  import AppKit
  import Combine
  import Foundation
  import FleckCore
  import ServiceManagement

  enum AgentCapabilitySaveResult {
    case succeeded
    case revisionConflict
    case failed
  }

  enum AgentNoteAccessSaveResult: Equatable {
    case succeeded
    case revisionConflict
    case contextChanged
    case failed
  }

  @MainActor
  final class AppState: ObservableObject, DictationSaving, AgentWorkspaceStateAccess {
    typealias SaveOperation =
      @Sendable (
        Workspace,
        AppPreferences,
        [Note],
        UInt64
      ) async throws -> LocalStoreSnapshotWriteResult
    typealias LegacySaveOperation =
      @Sendable (
        Workspace,
        AppPreferences,
        [Note]
      ) async throws -> Void
    typealias LoadTrashOperation = @Sendable () async throws -> [TrashedNote]
    typealias AgentProfileProvisionOperation =
      @Sendable (UUID, Data) async throws -> Void
    typealias AgentProfileDisconnectOperation =
      @Sendable (UUID) async throws -> Void
    typealias RestoreOperation =
      @Sendable (
        TrashedNote,
        Workspace,
        AppPreferences,
        UInt64
      ) async throws -> Workspace
    typealias AgentCapabilityBatchReplaceOperation =
      @Sendable (
        [(profile: AgentProfileCapabilities, expectedGrantRevision: UInt64)],
        [UUID: UInt64]
      ) async throws -> AgentCapabilityState

    enum SaveStatus: Equatable {
      case idle
      case saving
      case saved
    }

    @Published var workspace = Workspace() {
      didSet {
        if workspace != oldValue {
          persistenceGeneration += 1
        }
      }
    }
    @Published var preferences = AppPreferences() {
      didSet {
        if preferences != oldValue {
          persistenceGeneration += 1
        }
      }
    }
    @Published var saveError: String?
    @Published private(set) var startupMigrationError: FleckProductMigrationError?
    @Published private(set) var saveStatus = SaveStatus.idle
    @Published private(set) var initialSnapshotSource: LocalStoreSnapshotSource?
    @Published private(set) var trashedNotes: [TrashedNote] = []
    @Published private(set) var latestAgentFeedback: AgentChangeFeedback?
    @Published private(set) var agentProfiles: [AgentIntegrationProfile] = []
    @Published private(set) var agentActivity: [AgentActivityRecord] = []
    @Published private(set) var agentBannerPresentation: AgentBannerPresentation?
    @Published private(set) var isAgentConnectorInstalled = false
    @Published private(set) var agentCapabilityState = AgentCapabilityState(
      profiles: [:],
      unassignedLegacyNoteIDs: []
    )
    @Published var agentCleanupError: String?
    private(set) var persistenceGeneration: UInt64 = 0
    private(set) var hasFinishedInitialLoad = false
    private(set) var isAgentWorkspaceAvailable = false
    private(set) var agentCommitProofs: [AgentWorkspaceCommitProof] = []
    var isPersistenceBlocked: Bool { startupMigrationError != nil }

    private let store: LocalStore
    private let snapshotWriter: LocalStoreSnapshotWriter
    private let saveOperation: SaveOperation
    private let loadTrashOperation: LoadTrashOperation
    let agentProfileStore: AgentProfileStore
    let agentActivityStore: AgentActivityStore
    let agentCapabilityStore: AgentCapabilityStore
    let agentCapabilityAuthority: any AgentCapabilityAuthorizing
    private let agentProfileProvisionOperation: AgentProfileProvisionOperation
    private let agentProfileDisconnectOperation: AgentProfileDisconnectOperation
    private let restoreOperation: RestoreOperation
    private let replaceAgentCapabilitiesOperation:
      AgentCapabilityBatchReplaceOperation
    private struct NoteAccessTransactionLock {
      let capturedContext: AgentNoteAccessContext
      let folderID: UUID?
    }
    private var noteAccessTransactionLocks: [UUID: NoteAccessTransactionLock] = [:]
    private var pendingRestoreNoteIDs: Set<UUID> = []
    private var debouncedSaveTask: Task<Void, Error>?
    private var awaitedSaveCount = 0
    private var awaitedSaveWaiters: [CheckedContinuation<Void, Never>] = []
    private var initialLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveStatusResetTask: Task<Void, Never>?
    private var agentConnectorStatusGeneration: UInt64 = 0
    private var pendingTrashNotes: [UUID: Note] = [:] {
      didSet {
        if pendingTrashNotes != oldValue {
          persistenceGeneration += 1
        }
      }
    }

    init(
      store: LocalStore? = nil,
      saveOperation: SaveOperation? = nil,
      loadTrashOperation: LoadTrashOperation? = nil,
      restoreOperation: RestoreOperation? = nil,
      agentProfileStore: AgentProfileStore? = nil,
      agentActivityStore: AgentActivityStore? = nil,
      agentCapabilityStore: AgentCapabilityStore? = nil,
      agentCapabilityAuthority: (any AgentCapabilityAuthorizing)? = nil,
      replaceAgentCapabilities: AgentCapabilityBatchReplaceOperation? = nil,
      provisionAgentProfile: AgentProfileProvisionOperation? = nil,
      disconnectAgentProfile: AgentProfileDisconnectOperation? = nil,
      startupMigrationError: FleckProductMigrationError? = nil
    ) {
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      let canonicalRoot = appSupport.appendingPathComponent(
        FleckProductPaths.canonicalDirectoryName,
        isDirectory: true
      )
      let store = store ?? LocalStore(rootURL: canonicalRoot)
      let agentRoot = store.rootURL
      self.store = store
      snapshotWriter = store.snapshotWriter
      self.saveOperation =
        saveOperation ?? { workspace, preferences, trashedNotes, generation in
          try await store.save(
            workspace: workspace,
            preferences: preferences,
            trashedNotes: trashedNotes,
            generation: generation
          )
        }
      self.loadTrashOperation =
        loadTrashOperation ?? {
          try await store.loadTrash()
        }
      self.restoreOperation =
        restoreOperation ?? { trashedNote, workspace, preferences, generation in
          try await store.restore(
            trashedNote,
            into: workspace,
            preferences: preferences,
            generation: generation
          )
        }
      self.agentProfileStore =
        agentProfileStore
        ?? AgentProfileStore(
          profilesURL: agentRoot
            .appendingPathComponent("AgentIntegrations", isDirectory: true)
            .appendingPathComponent("profiles.json")
        )
      self.agentActivityStore =
        agentActivityStore
        ?? AgentActivityStore(rootURL: agentRoot)
      let capabilityStore =
        agentCapabilityStore
        ?? AgentCapabilityStore(
          capabilitiesURL: agentRoot
            .appendingPathComponent("AgentIntegrations", isDirectory: true)
            .appendingPathComponent("capabilities.json"),
          previousCapabilitiesURL: agentRoot
            .appendingPathComponent("AgentIntegrations", isDirectory: true)
            .appendingPathComponent("capabilities.previous.json")
        )
      self.agentCapabilityStore = capabilityStore
      self.agentCapabilityAuthority =
        agentCapabilityAuthority ?? AgentCapabilityAuthority(store: capabilityStore)
      self.replaceAgentCapabilitiesOperation =
        replaceAgentCapabilities ?? { replacements, expectedGrantRevisions in
          try await capabilityStore.replaceProfiles(
            replacements,
            expectedGrantRevisions: expectedGrantRevisions
          )
        }
      self.agentProfileProvisionOperation =
        provisionAgentProfile ?? { profileID, credential in
          try await AgentBridgeInstaller.live().provisionAsync(
            profileID: profileID,
            token: credential
          )
        }
      self.agentProfileDisconnectOperation =
        disconnectAgentProfile ?? { profileID in
          try await AgentBridgeInstaller.live().disconnectAsync(
            profileID: profileID
          )
        }
      self.startupMigrationError = startupMigrationError
      workspace.ensureNoteExists()
      Task {
        if let startupMigrationError {
          isAgentWorkspaceAvailable = false
          saveError = Self.migrationFailureMessage(for: startupMigrationError)
          finishInitialLoad()
          return
        }
        guard await load() else {
          finishInitialLoad()
          return
        }
        guard await refreshAgentProfiles() else {
          finishInitialLoad()
          return
        }
        do {
          agentCapabilityState = try await self.agentCapabilityStore.loadOrMigrate(
            activeProfileIDs: agentProfiles.map(\.id),
            workspace: workspace
          )
          isAgentWorkspaceAvailable = true
          agentCleanupError = nil
        } catch {
          isAgentWorkspaceAvailable = false
          agentCleanupError = Self.agentCapabilityFailureMessage
        }
        refreshAgentActivity()
        finishInitialLoad()
      }
    }

    convenience init(
      store: LocalStore? = nil,
      saveOperation: @escaping LegacySaveOperation,
      loadTrashOperation: LoadTrashOperation? = nil
    ) {
      self.init(
        store: store,
        saveOperation: { workspace, preferences, trashedNotes, _ in
          try await saveOperation(workspace, preferences, trashedNotes)
          return .committed
        },
        loadTrashOperation: loadTrashOperation
      )
    }

    var selectedNote: Note? {
      guard let id = workspace.selectedNoteID else { return nil }
      return workspace.notes.first(where: { $0.id == id })
    }

    func visibleNotes(in folderID: UUID?) -> [Note] {
      workspace.notes(inFolderID: folderID)
    }

    func folderScopeForSelectedNote() -> UUID? {
      guard let selectedID = workspace.selectedNoteID else { return nil }
      return folderID(for: selectedID)
    }

    func folderID(for noteID: UUID) -> UUID? {
      guard let folderID = workspace.notes.first(where: { $0.id == noteID })?.folderID,
        workspace.folders.contains(where: { $0.id == folderID })
      else { return nil }
      return folderID
    }

    private func isLockedNoteMembershipChange(
      noteID: UUID,
      targetFolderID: UUID?
    ) -> Bool {
      guard noteAccessTransactionLocks[noteID] != nil else { return false }
      let currentContext = AgentCapabilityPresentation.noteAccessContext(
        for: noteID,
        in: workspace
      )
      guard currentContext.noteExists else { return true }
      return currentContext.noteFolderID != targetFolderID
    }

    private func isLockedNote(_ noteID: UUID) -> Bool {
      noteAccessTransactionLocks[noteID] != nil
    }

    private func isLockedFolder(_ folderID: UUID) -> Bool {
      noteAccessTransactionLocks.values.contains { $0.folderID == folderID }
    }

    private func isLockedContextUnchanged(in workspace: Workspace) -> Bool {
      noteAccessTransactionLocks.values.allSatisfy { lock in
        AgentCapabilityPresentation.noteAccessContext(
          for: lock.capturedContext.noteID,
          in: workspace
        ) == lock.capturedContext
      }
    }

    func activeDestinations() -> [DictationDestination] {
      workspace.notes.map {
        DictationDestination(noteID: $0.id, title: $0.displayTitle)
      }
    }

    func capabilityProfile(_ profileID: UUID) -> AgentProfileCapabilities? {
      agentCapabilityState.profiles[profileID]
    }

    static func activeCapabilityProfiles(
      profiles: [AgentIntegrationProfile],
      state: AgentCapabilityState
    ) -> [AgentProfileCapabilities] {
      profiles.compactMap { profile in
        guard !profile.isRevoked else { return nil }
        return state.profiles[profile.id]
      }
    }

    var activeAgentCapabilityProfiles: [AgentProfileCapabilities] {
      Self.activeCapabilityProfiles(profiles: agentProfiles, state: agentCapabilityState)
    }

    func profilesWithReadAccess(to noteID: UUID) -> [AgentIntegrationProfile] {
      agentProfiles.filter { profile in
        guard !profile.isRevoked else { return false }
        guard let capabilities = agentCapabilityState.profiles[profile.id] else {
          return false
        }
        return AgentCapabilityPolicy.authorizationSnapshot(
          for: capabilities,
          workspace: workspace
        ).readableNoteIDs.contains(noteID)
      }
    }

    func isSharedWithAnyActiveProfile(_ noteID: UUID) -> Bool {
      !profilesWithReadAccess(to: noteID).isEmpty
    }

    @discardableResult
    func updateAgentCapabilitiesForNote(
      noteID: UUID,
      capturedContext: AgentNoteAccessContext,
      replacements: [
        (profile: AgentProfileCapabilities, expectedGrantRevision: UInt64)
      ],
      expectedGrantRevisions: [UUID: UInt64]
    ) async -> AgentNoteAccessSaveResult {
      guard !pendingRestoreNoteIDs.contains(noteID) else {
        return .contextChanged
      }
      guard
        capturedContext.noteID == noteID,
        capturedContext.noteExists,
        AgentCapabilityPresentation.noteAccessContextIsUnchanged(
          noteID: noteID,
          captured: capturedContext,
          workspace: workspace
        )
      else {
        return .contextChanged
      }
      guard noteAccessTransactionLocks[noteID] == nil else {
        agentCleanupError = "Could not update Agent access. Try again."
        return .failed
      }

      noteAccessTransactionLocks[noteID] = NoteAccessTransactionLock(
        capturedContext: capturedContext,
        folderID: capturedContext.folderExists
          ? capturedContext.noteFolderID
          : nil
      )
      defer { noteAccessTransactionLocks.removeValue(forKey: noteID) }

      do {
        agentCapabilityState = try await replaceAgentCapabilitiesOperation(
          replacements,
          expectedGrantRevisions
        )
        agentCleanupError = nil
        return .succeeded
      } catch let error as AgentWorkspaceError where error.code == .revisionConflict {
        agentCleanupError = AgentCapabilityPresentation.conflictMessage
        return .revisionConflict
      } catch {
        agentCleanupError = "Could not update Agent access. Try again."
        return .failed
      }
    }

    @discardableResult
    func updateAgentCapabilities(
      _ replacement: AgentProfileCapabilities,
      expectedGrantRevision: UInt64
    ) async -> AgentCapabilitySaveResult {
      do {
        agentCapabilityState = try await agentCapabilityStore.replaceProfile(
          replacement,
          expectedGrantRevision: expectedGrantRevision
        )
        agentCleanupError = nil
        return .succeeded
      } catch let error as AgentWorkspaceError where error.code == .revisionConflict {
        agentCleanupError = AgentCapabilityPresentation.conflictMessage
        return .revisionConflict
      } catch {
        agentCleanupError = "Could not update Agent capabilities. Try again."
        return .failed
      }
    }

    @discardableResult
    func updateAgentCapabilities(
      _ replacements: [
        (profile: AgentProfileCapabilities, expectedGrantRevision: UInt64)
      ]
    ) async -> AgentCapabilitySaveResult {
      do {
        agentCapabilityState = try await agentCapabilityStore.replaceProfiles(replacements)
        agentCleanupError = nil
        return .succeeded
      } catch let error as AgentWorkspaceError where error.code == .revisionConflict {
        agentCleanupError = AgentCapabilityPresentation.conflictMessage
        return .revisionConflict
      } catch {
        agentCleanupError = "Could not update Agent access. Try again."
        return .failed
      }
    }

    @discardableResult
    func updateAgentCapabilities(
      _ replacements: [
        (profile: AgentProfileCapabilities, expectedGrantRevision: UInt64)
      ],
      expectedGrantRevisions: [UUID: UInt64]
    ) async -> AgentCapabilitySaveResult {
      do {
        agentCapabilityState = try await agentCapabilityStore.replaceProfiles(
          replacements,
          expectedGrantRevisions: expectedGrantRevisions
        )
        agentCleanupError = nil
        return .succeeded
      } catch let error as AgentWorkspaceError where error.code == .revisionConflict {
        agentCleanupError = AgentCapabilityPresentation.conflictMessage
        return .revisionConflict
      } catch {
        agentCleanupError = "Could not update Agent access. Try again."
        return .failed
      }
    }

    @discardableResult
    func assignUnassignedLegacyNotes(
      _ noteIDs: Set<UUID>,
      to profileID: UUID,
      expectedGrantRevision: UInt64
    ) async -> AgentCapabilitySaveResult {
      do {
        agentCapabilityState = try await agentCapabilityStore.assignUnassignedLegacyNotes(
          noteIDs,
          to: profileID,
          expectedGrantRevision: expectedGrantRevision
        )
        agentCleanupError = nil
        return .succeeded
      } catch let error as AgentWorkspaceError where error.code == .revisionConflict {
        agentCleanupError = AgentCapabilityPresentation.conflictMessage
        return .revisionConflict
      } catch {
        agentCleanupError = "Could not assign legacy Agent shares. Try again."
        return .failed
      }
    }

    func saveSmartCapture(
      text: String,
      captureID: UUID,
      destinationID: UUID?
    ) async throws -> DictationInsertionReceipt {
      beginAwaitedSave()
      defer { endAwaitedSave() }
      let destinationIndex: Int
      let originalNote: Note
      let createdInbox: Bool
      if let destinationID,
        let index = workspace.notes.firstIndex(where: { $0.id == destinationID })
      {
        destinationIndex = index
        originalNote = workspace.notes[index]
        createdInbox = false
      } else if let index = workspace.notes.firstIndex(where: {
        $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
      }) {
        destinationIndex = index
        originalNote = workspace.notes[index]
        createdInbox = false
      } else {
        let inbox = Note(title: "Inbox")
        workspace.notes.append(inbox)
        destinationIndex = workspace.notes.index(before: workspace.notes.endIndex)
        originalNote = inbox
        createdInbox = true
      }

      let appended = NoteTextAppender.appending(
        text,
        to: workspace.notes[destinationIndex],
        defaults: NoteTextAppendDefaults(
          fontFamily: preferences.fontFamily,
          fontSize: preferences.fontSize
        )
      )
      let noteID = workspace.notes[destinationIndex].id
      workspace.updateContent(
        id: noteID,
        body: appended.body,
        rtf: appended.richTextRTF
      )
      let insertedNote = workspace.notes[destinationIndex]
      do {
        try await saveNow(transactionOwned: true).value
      } catch {
        rollbackSmartCapture(
          noteID: noteID,
          insertedNote: insertedNote,
          originalNote: originalNote,
          createdInbox: createdInbox
        )
        throw error
      }
      return DictationInsertionReceipt(
        captureID: captureID,
        noteID: noteID,
        insertedSuffix: appended.insertedSuffix
      )
    }

    func undoSmartCapture(_ receipt: DictationInsertionReceipt) async -> Bool {
      guard let index = workspace.notes.firstIndex(where: { $0.id == receipt.noteID }) else {
        return false
      }
      beginAwaitedSave()
      defer { endAwaitedSave() }
      workspace.selectedNoteID = receipt.noteID
      let note = workspace.notes[index]
      guard
        !receipt.insertedSuffix.isEmpty,
        note.body.hasSuffix(receipt.insertedSuffix),
        let richTextRTF = removingSuffix(receipt.insertedSuffix, from: note.richTextRTF)
      else {
        return false
      }

      workspace.updateContent(
        id: receipt.noteID,
        body: String(note.body.dropLast(receipt.insertedSuffix.count)),
        rtf: richTextRTF
      )
      let attemptedUndoNote = workspace.notes[index]
      do {
        try await saveNow(transactionOwned: true).value
        return true
      } catch {
        if let currentIndex = workspace.notes.firstIndex(where: { $0.id == receipt.noteID }) {
          if workspace.notes[currentIndex] == attemptedUndoNote {
            workspace.notes[currentIndex] = note
          }
          workspace.selectedNoteID = receipt.noteID
        }
        return false
      }
    }

    func flushFocusedDictationSave(
      captureID: UUID
    ) async throws -> FocusedDictationPersistenceReceipt {
      beginAwaitedSave()
      defer { endAwaitedSave() }
      try await saveNow(transactionOwned: true).value
      return FocusedDictationPersistenceReceipt(captureID: captureID)
    }

    func flushFocusedDictationSave() async throws {
      _ = try await flushFocusedDictationSave(captureID: UUID())
    }

    func compensateFocusedDictationSave(
      _ receipt: FocusedDictationPersistenceReceipt
    ) async -> Bool {
      beginAwaitedSave()
      defer { endAwaitedSave() }
      do {
        try await saveNow(transactionOwned: true).value
        return true
      } catch {
        return false
      }
    }

    func select(_ id: UUID) {
      workspace.selectedNoteID = id
      scheduleSave()
    }

    func addNote() {
      _ = addNote(inFolderID: nil)
    }

    @discardableResult
    func addNote(inFolderID targetFolderID: UUID?) -> UUID {
      let folderID = validFolderIDOrUnfiled(targetFolderID)
      let note = Note(folderID: folderID)
      workspace.addNote(note)
      scheduleSave()
      return note.id
    }

    func importNote(_ note: Note) {
      importNote(note, intoFolderID: nil)
    }

    func importNote(_ note: Note, intoFolderID targetFolderID: UUID?) {
      var imported = note
      guard
        !isLockedNote(imported.id)
          || workspace.notes.contains(where: { $0.id == imported.id })
      else { return }
      if workspace.notes.contains(where: { $0.id == imported.id }) {
        imported = Note(
          id: UUID(),
          title: imported.title,
          body: imported.body,
          richTextRTF: imported.richTextRTF,
          tabColorHex: imported.tabColorHex,
          createdAt: imported.createdAt,
          modifiedAt: imported.modifiedAt,
          isPinned: imported.isPinned,
          agentAccess: imported.agentAccess,
          revision: imported.revision,
          folderID: imported.folderID
        )
      }
      imported.folderID = validFolderIDOrUnfiled(targetFolderID)
      workspace.addNote(imported)
      scheduleSave()
    }

    @discardableResult
    func createFolder(named name: String) throws -> Folder {
      var updated = workspace
      let folder = try updated.createFolder(name: name)
      workspace = updated
      scheduleSave()
      return folder
    }

    func renameFolder(id: UUID, name: String) throws {
      var updated = workspace
      try updated.renameFolder(id: id, name: name)
      guard updated != workspace else { return }
      workspace = updated
      scheduleSave()
    }

    func reorderFolder(id: UUID, to postRemovalIndex: Int) throws {
      var updated = workspace
      try updated.reorderFolder(id: id, to: postRemovalIndex)
      guard updated != workspace else { return }
      workspace = updated
      scheduleSave()
    }

    func deleteFolder(id: UUID, activeFolderID: UUID? = nil) throws {
      guard !isLockedFolder(id) else { return }
      let selectedID = workspace.selectedNoteID
      let selectedWasMember = workspace.notes.contains {
        $0.id == selectedID && $0.folderID == id
      }
      var updated = workspace
      try updated.deleteFolder(id: id)

      guard activeFolderID == id else {
        guard updated != workspace else { return }
        workspace = updated
        scheduleSave()
        return
      }

      if selectedWasMember, let selectedID {
        updated.selectedNoteID = selectedID
      } else if let firstUnfiled = updated.notes(inFolderID: nil).first {
        updated.selectedNoteID = firstUnfiled.id
      } else if let selectedID,
        updated.notes.contains(where: { $0.id == selectedID })
      {
        updated.selectedNoteID = selectedID
      } else {
        updated.ensureNoteExists()
      }

      guard updated != workspace else { return }
      workspace = updated
      scheduleSave()
    }

    @discardableResult
    func moveNote(
      _ id: UUID,
      fromFolderID sourceFolderID: UUID?,
      toFolderID targetFolderID: UUID?,
      activeFolderID: UUID? = nil
    ) -> Bool {
      guard let note = workspace.notes.first(where: { $0.id == id }),
        note.folderID == sourceFolderID
      else { return false }
      return moveNote(
        id,
        toFolderID: targetFolderID,
        activeFolderID: activeFolderID
      )
    }

    @discardableResult
    func moveNote(
      _ id: UUID,
      toFolderID targetFolderID: UUID?,
      activeFolderID: UUID? = nil
    ) -> Bool {
      guard let note = workspace.notes.first(where: { $0.id == id }),
        targetFolderID == nil
          || workspace.folders.contains(where: { $0.id == targetFolderID })
      else { return false }
      guard !isLockedNoteMembershipChange(noteID: id, targetFolderID: targetFolderID)
      else { return false }
      guard note.folderID != targetFolderID else { return false }

      let sourceFolderID = note.folderID
      let sourceVisibleNotes = workspace.notes(inFolderID: sourceFolderID)
      var updated = workspace
      guard (try? updated.moveNote(id: id, toFolderID: targetFolderID)) != nil else {
        return false
      }

      if activeFolderID == sourceFolderID, updated.selectedNoteID == id,
        let movingIndex = sourceVisibleNotes.firstIndex(where: { $0.id == id })
      {
        let remaining = sourceVisibleNotes.filter { $0.id != id }
        if let nearest = remaining.dropFirst(movingIndex).first ?? remaining.last {
          updated.selectedNoteID = nearest.id
        }
      }

      workspace = updated
      scheduleSave()
      return true
    }

    @discardableResult
    func moveNote(
      _ id: UUID,
      inFolderID folderID: UUID?,
      toVisibleIndex destination: Int
    ) -> Bool {
      var updated = workspace
      guard (try? updated.reorderNote(
        id: id,
        inFolderID: folderID,
        toVisibleIndex: destination
      )) != nil, updated != workspace else {
        return false
      }
      workspace = updated
      scheduleSave()
      return true
    }

    func moveToTrash(_ id: UUID) {
      guard !isLockedNote(id) else { return }
      guard let note = workspace.notes.first(where: { $0.id == id }) else { return }
      pendingTrashNotes[id] = note
      workspace.deleteNote(id: id)
      saveNow()
    }

    func moveToTrash(_ id: UUID, activeFolderID: UUID?) {
      guard !isLockedNote(id) else { return }
      guard let note = workspace.notes.first(where: { $0.id == id }) else { return }
      let sourceFolderID = note.folderID
      let sourceVisibleNotes = workspace.notes(inFolderID: sourceFolderID)
      let selectedWasDeleted = workspace.selectedNoteID == id
      pendingTrashNotes[id] = note
      var updated = workspace
      updated.deleteNote(id: id)
      if selectedWasDeleted, activeFolderID == sourceFolderID,
        let movingIndex = sourceVisibleNotes.firstIndex(where: { $0.id == id })
      {
        let remaining = sourceVisibleNotes.filter { $0.id != id }
        if let nearest = remaining.dropFirst(movingIndex).first ?? remaining.last {
          updated.selectedNoteID = nearest.id
        }
      }
      workspace = updated
      saveNow()
    }

    func selectAdjacentNote(forward: Bool) {
      workspace.selectAdjacent(forward: forward)
      scheduleSave()
    }

    func selectAdjacentNote(forward: Bool, inFolderID folderID: UUID?) {
      let visible = workspace.notes(inFolderID: folderID)
      guard !visible.isEmpty else { return }
      let currentIndex = visible.firstIndex(where: { $0.id == workspace.selectedNoteID })
      let targetIndex: Int
      if let currentIndex {
        targetIndex = (currentIndex + (forward ? 1 : visible.count - 1)) % visible.count
      } else {
        targetIndex = forward ? 0 : visible.count - 1
      }
      let targetID = visible[targetIndex].id
      guard workspace.selectedNoteID != targetID else { return }
      workspace.selectedNoteID = targetID
      scheduleSave()
    }

    func moveNote(_ id: UUID, to destination: Int) {
      workspace.moveNote(id: id, to: destination)
      scheduleSave()
    }

    func togglePinned(_ id: UUID) {
      workspace.togglePinned(id: id)
      scheduleSave()
    }

    func updateSelected(title: String? = nil, body: String? = nil) {
      guard let id = workspace.selectedNoteID else { return }
      let originalWorkspace = workspace
      if let title {
        workspace.updateNote(id: id, title: title)
      }
      if let body,
        let note = workspace.notes.first(where: { $0.id == id })
      {
        workspace.updateContent(id: id, body: body, rtf: note.richTextRTF)
      }
      guard workspace != originalWorkspace else { return }
      scheduleSave()
    }

    func updateSelected(body: String, richTextRTF: Data?) {
      guard let id = workspace.selectedNoteID else { return }
      let originalWorkspace = workspace
      workspace.updateContent(id: id, body: body, rtf: richTextRTF)
      guard workspace != originalWorkspace else { return }
      scheduleSave()
    }

    func updateSelectedRichTextRTF(_ rtf: Data?) {
      guard let body = selectedNote?.body else { return }
      updateSelected(body: body, richTextRTF: rtf)
    }

    func setSelectedTabColor(_ hex: String?) {
      guard let id = workspace.selectedNoteID else { return }
      workspace.setTabColor(id: id, hex: hex)
      scheduleSave()
    }

    func toggleList(_ style: MarkdownEditing.ListStyle) {
      guard let note = selectedNote else { return }
      updateSelected(body: MarkdownEditing.togglingList(in: note.body, style: style))
    }

    func updatePreferences(_ update: (inout AppPreferences) -> Void) {
      let originalPreferences = preferences
      update(&preferences)
      guard preferences != originalPreferences else { return }
      scheduleSave()
    }

    func persistOnboardingProgress(_ progress: OnboardingProgress) async throws {
      let previous = preferences.onboardingProgress
      preferences.onboardingProgress = progress
      do {
        try await saveNow(transactionOwned: true).value
      } catch {
        if preferences.onboardingProgress == progress {
          preferences.onboardingProgress = previous
        }
        throw error
      }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
        updatePreferences { $0.launchAtLogin = enabled }
        saveError = nil
      } catch {
        saveError = "Could not update launch at login: \(error.localizedDescription)"
      }
    }

    @discardableResult
    func saveNow(transactionOwned: Bool = false) -> Task<Void, Error> {
      if let startupMigrationError {
        return Task { throw startupMigrationError }
      }
      debouncedSaveTask?.cancel()
      markSaveStarted()
      if transactionOwned {
        let snapshot = saveSnapshot()
        return Task {
          try await persist(snapshot)
        }
      }
      return Task {
        await waitForAwaitedSaves()
        try Task.checkCancellation()
        try await persist(saveSnapshot())
      }
    }

    func refreshTrash() async {
      do {
        trashedNotes = try await store.loadTrash()
        saveError = nil
      } catch {
        saveError = error.localizedDescription
      }
    }

    @discardableResult
    func restore(_ trashedNote: TrashedNote) -> Task<Void, Never>? {
      guard !isLockedNote(trashedNote.id) else { return nil }
      guard startupMigrationError == nil else { return nil }
      guard pendingRestoreNoteIDs.insert(trashedNote.id).inserted else {
        return nil
      }
      debouncedSaveTask?.cancel()
      resetSaveStatus()
      pendingTrashNotes.removeValue(forKey: trashedNote.id)
      trashedNotes.removeAll { $0.id == trashedNote.id }
      let originalWorkspace = workspace
      workspace.addRestoredNote(trashedNote.note)
      let optimisticWorkspace = workspace
      let preferences = preferences
      let generation = persistenceGeneration
      let store = store
      let restoreOperation = self.restoreOperation
      return Task { @MainActor in
        defer { pendingRestoreNoteIDs.remove(trashedNote.id) }
        do {
          _ = try await restoreOperation(
            trashedNote,
            optimisticWorkspace,
            preferences,
            generation
          )
          trashedNotes = try await store.loadTrash()
          saveError = nil
        } catch {
          if workspace == optimisticWorkspace {
            workspace = originalWorkspace
          }
          if let refreshedTrash = try? await store.loadTrash() {
            trashedNotes = refreshedTrash
          }
          saveError = error.localizedDescription
        }
      }
    }

    private func load() async -> Bool {
      do {
        let snapshot = try await store.loadSnapshot()
        workspace = snapshot.workspace
        preferences = snapshot.preferences
        initialSnapshotSource = snapshot.source
        persistenceGeneration = max(
          persistenceGeneration,
          snapshot.generation
        )
        agentCommitProofs = snapshot.commitProofs
        trashedNotes = try await store.loadTrash()
        saveError = nil
        return true
      } catch {
        isAgentWorkspaceAvailable = false
        saveError = error.localizedDescription
        return false
      }
    }

    func waitUntilInitialLoad() async {
      guard !hasFinishedInitialLoad else { return }
      await withCheckedContinuation { continuation in
        initialLoadWaiters.append(continuation)
      }
    }

    private func finishInitialLoad() {
      guard !hasFinishedInitialLoad else { return }
      hasFinishedInitialLoad = true
      let waiters = initialLoadWaiters
      initialLoadWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
    }

    private func scheduleSave() {
      guard startupMigrationError == nil else { return }
      debouncedSaveTask?.cancel()
      markSaveStarted()
      let task = Task {
        try await Task.sleep(for: .milliseconds(350))
        await waitForAwaitedSaves()
        try Task.checkCancellation()
        try await persist(saveSnapshot())
      }
      debouncedSaveTask = task
    }

    private static func migrationFailureMessage(
      for error: FleckProductMigrationError
    ) -> String {
      switch error {
      case .conflictingWorkspaces(let legacyPath, let canonicalPath):
        "Fleck found data in both \(legacyPath) and \(canonicalPath). "
          + "Close Fleck and resolve those folders before editing."
      case .unsafeLegacyRoot:
        "Fleck could not safely migrate the legacy data folder because it is "
          + "a symbolic link. Restore a normal local folder, then reopen Fleck."
      case .invalidMigratedWorkspace:
        "Fleck could not validate the migrated notes and restored the legacy "
          + "folder. Check the legacy data, then reopen Fleck."
      case .rollbackFailed(let legacyPath, let canonicalPath):
        "Fleck could not finish or roll back migration. Do not edit "
          + "\(legacyPath) or \(canonicalPath) until the folders are resolved."
      case .filesystemFailure:
        "Fleck could not prepare its Application Support folder. Check disk "
          + "access and available space, then reopen Fleck."
      }
    }

    private static let agentCapabilityFailureMessage =
      "Agent workspace is unavailable. Reopen Fleck after resolving capability storage."

    private typealias SaveSnapshot = (
      workspace: Workspace,
      preferences: AppPreferences,
      trashedNotes: [Note],
      generation: UInt64
    )

    private func saveSnapshot() -> SaveSnapshot {
      (
        workspace,
        preferences,
        Array(pendingTrashNotes.values),
        persistenceGeneration
      )
    }

    private func persist(_ snapshot: SaveSnapshot) async throws {
      do {
        _ = try await saveOperation(
          snapshot.workspace,
          snapshot.preferences,
          snapshot.trashedNotes,
          snapshot.generation
        )
      } catch {
        if Task.isCancelled || error is CancellationError {
          throw CancellationError()
        }
        saveError = error.localizedDescription
        markSaveFailed()
        throw error
      }

      for note in snapshot.trashedNotes {
        pendingTrashNotes.removeValue(forKey: note.id)
      }
      guard !Task.isCancelled else { return }
      var trashRefreshError: Error?
      if !snapshot.trashedNotes.isEmpty {
        do {
          trashedNotes = try await loadTrashOperation()
        } catch {
          guard !Task.isCancelled else { return }
          trashRefreshError = error
        }
      }
      guard !Task.isCancelled else { return }
      saveError = trashRefreshError?.localizedDescription
      markSaveSucceeded()
    }

    func flushPendingPersistenceForAgent() async throws {
      try await withCheckedThrowingContinuation { continuation in
        let resolution = AgentPersistenceDrainResolution(continuation)
        Task { @MainActor [weak self] in
          do {
            guard let self else {
              throw AgentWorkspaceError(code: .fleckUnavailable)
            }
            try await self.drainPersistenceForAgent()
            resolution.resolve(.success(()))
          } catch {
            resolution.resolve(.failure(error))
          }
        }
        Task {
          try? await Task.sleep(for: .seconds(2))
          resolution.resolve(
            .failure(
              AgentWorkspaceError(
                code: .fleckUnavailable,
                recoveryAction: "Wait for Fleck to finish saving, then retry."
              )
            )
          )
        }
      }
    }

    func commitAgentWorkspace(
      _ workspace: Workspace,
      expectedGeneration: UInt64,
      commitProof: AgentWorkspaceCommitProof
    ) throws {
      guard
        isAgentWorkspaceAvailable,
        persistenceGeneration == expectedGeneration
      else {
        throw AgentWorkspaceError(code: .revisionConflict)
      }
      guard pendingTrashNotes.isEmpty else {
        throw AgentWorkspaceError(
          code: .fleckUnavailable,
          recoveryAction: "Wait for Trash to finish saving, then retry."
        )
      }
      guard isLockedContextUnchanged(in: self.workspace),
        isLockedContextUnchanged(in: workspace)
      else {
        throw AgentWorkspaceError(code: .revisionConflict)
      }
      debouncedSaveTask?.cancel()
      let committedGeneration = expectedGeneration + 1
      do {
        let result = try snapshotWriter.save(
          workspace: workspace,
          preferences: preferences,
          generation: committedGeneration,
          commitProof: commitProof
        )
        guard result == .committed else {
          throw AgentWorkspaceError(code: .revisionConflict)
        }
      } catch let error as AgentWorkspaceError {
        throw error
      } catch {
        throw AgentWorkspaceError(code: .internalSaveFailure)
      }

      self.workspace = workspace
      persistenceGeneration = committedGeneration
      agentCommitProofs.removeAll {
        $0.changeID == commitProof.changeID
      }
      agentCommitProofs.append(commitProof)
      saveError = nil
      markSaveSucceeded()
    }

    func publishAgentFeedback(_ feedback: AgentChangeFeedback) {
      latestAgentFeedback = feedback
      if var banner = agentBannerPresentation,
        feedback.createdAt.timeIntervalSince(banner.feedback.createdAt) <= 2
      {
        banner.coalesce(feedback: feedback)
        agentBannerPresentation = banner
      } else {
        agentBannerPresentation = AgentBannerPresentation(feedback: feedback)
      }
      refreshAgentActivity()
    }

    func refreshAgentConnectorStatus() async {
      agentConnectorStatusGeneration &+= 1
      let generation = agentConnectorStatusGeneration
      let installed = await Task.detached(priority: .utility) {
        (try? AgentBridgeInstaller.live().verifiedInstalledHelperURL()) != nil
      }.value
      guard generation == agentConnectorStatusGeneration else { return }
      isAgentConnectorInstalled = installed
    }

    func installAgentBridge() async {
      agentConnectorStatusGeneration &+= 1
      do {
        _ = try await AgentBridgeInstaller.live().installAsync()
        agentConnectorStatusGeneration &+= 1
        isAgentConnectorInstalled = true
        agentCleanupError = nil
      } catch {
        await refreshAgentConnectorStatus()
        agentCleanupError =
          "Could not install the Agent Connector: \(error.localizedDescription)"
      }
    }

    func addAgentProfile(named name: String) async {
      do {
        let provisioning = try await agentProfileStore.create(name: name)
        do {
          try await agentProfileProvisionOperation(
            provisioning.profile.id,
            provisioning.credential
          )
          agentCapabilityState = try await agentCapabilityStore.registerEmptyProfile(
            provisioning.profile.id
          )
        } catch {
          do {
            try await agentProfileStore.revoke(profileID: provisioning.profile.id)
          } catch {
            try? await agentProfileStore.revoke(profileID: provisioning.profile.id)
          }
          do {
            try await agentProfileDisconnectOperation(provisioning.profile.id)
          } catch {
            try? await agentProfileDisconnectOperation(provisioning.profile.id)
          }
          throw error
        }
        await refreshAgentProfiles()
        agentCleanupError = nil
      } catch {
        await refreshAgentConnectorStatus()
        agentCleanupError = "Could not add \(name): \(error.localizedDescription)"
      }
    }

    func revokeAgentProfile(_ profile: AgentIntegrationProfile) async {
      var localCleanupFailed = false
      do {
        try await agentProfileStore.revoke(profileID: profile.id)
      } catch {
        localCleanupFailed = true
        agentCleanupError = "Could not revoke \(profile.displayName): \(error.localizedDescription)"
      }
      await refreshAgentProfiles()
      guard !agentProfiles.contains(where: { $0.id == profile.id }) else { return }
      do {
        try await agentProfileDisconnectOperation(profile.id)
        if !localCleanupFailed {
          agentCleanupError = nil
        }
      } catch {
        await refreshAgentConnectorStatus()
        agentCleanupError =
          "\(profile.displayName) is revoked, but its helper credential could not be removed."
      }
    }

    @discardableResult
    func refreshAgentProfiles() async -> Bool {
      do {
        agentProfiles = try await agentProfileStore.activeProfiles()
        return true
      } catch {
        agentCleanupError = "Could not load agent profiles: \(error.localizedDescription)"
        return false
      }
    }

    func refreshAgentActivity() {
      agentActivity = agentActivityStore.list(
        profileID: nil,
        visibleNoteIDs: Set(workspace.notes.map(\.id))
      )
    }

    func clearAgentActivity() {
      do {
        try agentActivityStore.clearVisibleActivity()
        refreshAgentActivity()
      } catch {
        agentCleanupError = "Could not clear Agent Activity: \(error.localizedDescription)"
      }
    }

    func undoAgentChange(_ record: AgentActivityRecord) async {
      guard let note = workspace.notes.first(where: { $0.id == record.noteID }) else { return }
      select(note.id)
      let service = AgentCommandService(
        state: self,
        profileStore: agentProfileStore,
        activityStore: agentActivityStore,
        capabilityAuthority: agentCapabilityAuthority
      )
      do {
        _ = try await service.executeLocalUndo(
          changeID: record.changeID,
          expectedRevision: note.revision,
          operationID: UUID()
        )
        refreshAgentActivity()
      } catch {
        agentCleanupError = "Undo was not safe: \(error.localizedDescription)"
      }
    }

    func undoLatestAgentChange() async {
      guard let feedback = agentBannerPresentation?.feedback,
        let record = agentActivityStore.record(id: feedback.changeID)
      else { return }
      await undoAgentChange(record)
    }

    func agentSetupSnippet(profileID: UUID) -> String? {
      try? AgentBridgeInstaller.live().setupSnippet(profileID: profileID)
    }

    private func drainPersistenceForAgent() async throws {
      while true {
        await waitForAwaitedSaves()
        debouncedSaveTask?.cancel()
        let generation = persistenceGeneration
        do {
          try await saveNow(transactionOwned: true).value
        } catch is CancellationError {
          continue
        } catch {
          throw AgentWorkspaceError(
            code: .fleckUnavailable,
            recoveryAction: "Resolve the Fleck save error, then retry."
          )
        }
        guard
          generation == persistenceGeneration,
          pendingTrashNotes.isEmpty
        else {
          continue
        }
        return
      }
    }

    private func rollbackSmartCapture(
      noteID: UUID,
      insertedNote: Note,
      originalNote: Note,
      createdInbox: Bool
    ) {
      if let index = workspace.notes.firstIndex(where: { $0.id == noteID }),
        workspace.notes[index] == insertedNote
      {
        if createdInbox, workspace.selectedNoteID != noteID {
          workspace.notes.remove(at: index)
        } else {
          workspace.notes[index] = originalNote
        }
        return
      }
      guard pendingTrashNotes[noteID] == insertedNote else { return }
      if createdInbox {
        pendingTrashNotes.removeValue(forKey: noteID)
      } else {
        pendingTrashNotes[noteID] = originalNote
      }
    }

    private func beginAwaitedSave() {
      awaitedSaveCount += 1
    }

    private func endAwaitedSave() {
      awaitedSaveCount -= 1
      guard awaitedSaveCount == 0 else { return }
      let waiters = awaitedSaveWaiters
      awaitedSaveWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
    }

    private func waitForAwaitedSaves() async {
      guard awaitedSaveCount > 0 else { return }
      await withCheckedContinuation { continuation in
        awaitedSaveWaiters.append(continuation)
      }
    }

    private func removingSuffix(_ suffix: String, from richTextRTF: Data?) -> Data? {
      guard
        let richTextRTF,
        let attributed = try? NSMutableAttributedString(
          data: richTextRTF,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
        ),
        attributed.string.hasSuffix(suffix)
      else { return nil }
      let suffixLength = suffix.utf16.count
      attributed.deleteCharacters(
        in: NSRange(location: attributed.length - suffixLength, length: suffixLength)
      )
      return try? attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
      )
    }

    private func markSaveStarted() {
      saveStatusResetTask?.cancel()
      saveStatus = .saving
    }

    private func markSaveSucceeded() {
      saveStatus = .saved
      saveStatusResetTask?.cancel()
      saveStatusResetTask = Task {
        try? await Task.sleep(for: .seconds(1.2))
        guard !Task.isCancelled else { return }
        saveStatus = .idle
      }
    }

    private func markSaveFailed() {
      resetSaveStatus()
    }

    private func resetSaveStatus() {
      saveStatusResetTask?.cancel()
      saveStatus = .idle
    }

    private func validFolderIDOrUnfiled(_ folderID: UUID?) -> UUID? {
      guard let folderID else { return nil }
      return workspace.folders.contains(where: { $0.id == folderID }) ? folderID : nil
    }
  }

  private final class AgentPersistenceDrainResolution: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
      self.continuation = continuation
    }

    func resolve(_ result: Result<Void, Error>) {
      let continuation = lock.withLock {
        defer { self.continuation = nil }
        return self.continuation
      }
      continuation?.resume(with: result)
    }
  }
#endif
