import AppKit
import CoreGraphics
import Foundation
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor
func personalDictionarySettingsLoadsAllEntriesAndSuggestionsInStableOrder() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  try await store.upsert(settingsEntry(3, "zeta", aliases: ["Last term"]))
  try await store.upsert(settingsEntry(2, "Alpha", enabled: false))
  try await store.upsert(settingsEntry(1, "alpha", aliases: ["First term"]))
  try await store.recordSuggestion(settingsSuggestion(5, "Beta", observed: ["B term"]))
  let viewModel = PersonalDictionarySettingsViewModel(store: store)

  await viewModel.load()

  #expect(viewModel.revision == 4)
  #expect(viewModel.entries.map(\.id) == [settingsUUID(2), settingsUUID(1), settingsUUID(3)])
  #expect(viewModel.suggestions.map(\.preferredForm) == ["Beta"])
  #expect(
    viewModel.visibleEntries.map(\.id) == [settingsUUID(2), settingsUUID(1), settingsUUID(3)]
  )
  #expect(viewModel.visibleEntries.map(\.isEnabled) == [false, true, true])
  #expect(viewModel.visibleSuggestions.isEmpty)

  viewModel.query = "FIRST TERM"
  #expect(viewModel.visibleEntries.map(\.preferredForm) == ["alpha"])

  viewModel.filter = .suggestions
  viewModel.query = "b TERM"
  #expect(viewModel.visibleEntries.isEmpty)
  #expect(viewModel.visibleSuggestions.map(\.preferredForm) == ["Beta"])
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySuggestionHeaderActionTracksQueueAndKeepsAnExitAfterDismissal() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let firstSuggestion = settingsSuggestion(1, "First suggestion")
  let lastSuggestion = settingsSuggestion(2, "Last suggestion")
  try await store.recordSuggestion(firstSuggestion)
  try await store.recordSuggestion(lastSuggestion)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)

  #expect(viewModel.suggestionsHeaderActionTitle == nil)
  await viewModel.load()
  #expect(viewModel.suggestionsHeaderActionTitle == "Review suggestions (2)")

  await viewModel.dismissSuggestion(
    id: firstSuggestion.id,
    expectedRevision: viewModel.revision
  )
  #expect(viewModel.suggestionsHeaderActionTitle == "Review suggestions (1)")

  viewModel.filter = .suggestions
  #expect(viewModel.suggestionsHeaderActionTitle == "Back to words")
  await viewModel.dismissSuggestion(
    id: lastSuggestion.id,
    expectedRevision: viewModel.revision
  )
  #expect(viewModel.suggestions.isEmpty)
  #expect(viewModel.suggestionsHeaderActionTitle == "Back to words")

  viewModel.filter = .all
  #expect(viewModel.suggestionsHeaderActionTitle == nil)
}

@Test @MainActor
func personalDictionarySettingsBindsAddEnableAndDeleteToDisplayedRevision() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.add(
    preferredForm: "  FleckApp \n",
    aliases: " fleck app, Fleck application\n fleck app ",
    expectedRevision: viewModel.revision
  )
  #expect(viewModel.revision == 1)
  #expect(viewModel.entries[0].preferredForm == "FleckApp")
  #expect(viewModel.entries[0].aliases == ["fleck app", "Fleck application"])

  let id = viewModel.entries[0].id
  let enabledRevision = viewModel.revision
  await viewModel.setEnabled(false, id: id, expectedRevision: enabledRevision)
  #expect(viewModel.revision == 2)
  #expect(viewModel.entries[0].isEnabled == false)

  await viewModel.delete(id: id, expectedRevision: viewModel.revision)
  #expect(viewModel.revision == 3)
  #expect(viewModel.entries.isEmpty)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsPriorityUsesDisplayedRevisionAndPersists() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(11, "Fleck")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.setPriority(true, id: entry.id, expectedRevision: viewModel.revision)

  #expect(viewModel.entries.first?.isPriority == true)
  #expect(viewModel.errorMessage == nil)

  let reloadedViewModel = PersonalDictionarySettingsViewModel(store: store)
  await reloadedViewModel.load()
  #expect(reloadedViewModel.entries.first?.isPriority == true)
}

@Test @MainActor
func personalDictionarySettingsDoesNotRebaseConcurrentPriorityChanges() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(12, "Dictionary")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let displayedRevision = viewModel.revision

  _ = try await store.mutate(
    expectedRevision: displayedRevision,
    .setPriority(true, id: entry.id)
  )
  await viewModel.setPriority(false, id: entry.id, expectedRevision: displayedRevision)

  #expect(viewModel.revision == displayedRevision + 1)
  #expect(viewModel.entries.first?.isPriority == true)
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")
}

@Test @MainActor
func personalDictionaryRowDeletionWaitsForConfirmationBeforeMutating() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(13, "Remove only after confirmation")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let displayedRevision = viewModel.revision

  viewModel.requestEntryDeletion(entry, expectedRevision: displayedRevision)

  #expect(viewModel.pendingEntryDeletion?.id == entry.id)
  #expect(viewModel.pendingEntryDeletion?.expectedRevision == displayedRevision)
  #expect(viewModel.entries.map(\.id) == [entry.id])
  #expect(viewModel.revision == displayedRevision)

  viewModel.cancelEntryDeletion()
  #expect(viewModel.pendingEntryDeletion == nil)
  #expect(viewModel.entries.map(\.id) == [entry.id])
  #expect(viewModel.revision == displayedRevision)

  viewModel.requestEntryDeletion(entry, expectedRevision: displayedRevision)
  await viewModel.confirmEntryDeletion()

  #expect(viewModel.pendingEntryDeletion == nil)
  #expect(!viewModel.isEntryDeletionInFlight)
  #expect(viewModel.entries.isEmpty)
  #expect(viewModel.revision == displayedRevision + 1)
}

@Test @MainActor
func personalDictionaryRowDeletionRejectsAStaleDisplayedRevision() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(14, "Concurrent delete")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let displayedRevision = viewModel.revision
  viewModel.requestEntryDeletion(entry, expectedRevision: displayedRevision)

  _ = try await store.mutate(
    expectedRevision: displayedRevision,
    .upsert(settingsEntry(15, "Newer entry"))
  )
  await viewModel.confirmEntryDeletion()

  #expect(viewModel.entries.map(\.id) == [entry.id, settingsUUID(15)])
  #expect(viewModel.revision == displayedRevision + 1)
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")
}

@Test @MainActor
func personalDictionaryNativeConfirmationClaimsDeletionBeforeDismissal() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let deletedEntry = settingsEntry(87, "Delete after native confirmation")
  let retainedEntry = settingsEntry(88, "Keep after native confirmation")
  try await store.upsert(deletedEntry)
  try await store.upsert(retainedEntry)
  let gate = PersonalDictionaryEntryMutationGate(store: store)
  let viewModel = PersonalDictionarySettingsViewModel(
    store: store,
    entryMutation: { revision, mutation in
      try await gate.perform(expectedRevision: revision, mutation: mutation)
    }
  )
  var mutationGateCleanupCompleted = false
  defer {
    if !mutationGateCleanupCompleted {
      Task { @MainActor in
        _ = await releaseAndWaitForPersonalDictionaryDeletion(gate, viewModel: viewModel)
      }
    }
  }
  await viewModel.load()
  let displayedRevision = viewModel.revision

  let (window, host) = await hostedPersonalDictionarySettingsSection(
    viewModel: viewModel,
    size: NSSize(width: 540, height: 500)
  )
  defer {
    window.contentView = nil
    window.orderOut(nil)
  }

  let rowIdentifier = "settings-vocabulary-entry-frame-\(deletedEntry.id.uuidString)"
  let row = try #require(
    personalDictionarySettingsView(
      withAccessibilityIdentifier: rowIdentifier,
      in: host
    )
  )
  let deleteID = "settings-vocabulary-entry-delete-\(deletedEntry.id.uuidString)"

  let screenCandidate = window.screen ?? NSScreen.screens.first
  if screenCandidate == nil {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: deletedEntry.id,
        deleteIdentifier: deleteID,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
  }
  let screen = try #require(screenCandidate)
  boundPersonalDictionaryDeleteAdmissionViewport(
    window: window,
    host: host,
    screen: screen,
    contentSize: NSSize(width: 540, height: 620)
  )
  await settlePersonalDictionarySettingsHost(host)

  let application = NSApplication.shared
  application.activate(ignoringOtherApps: true)
  window.makeKeyAndOrderFront(nil)
  await settlePersonalDictionarySettingsHost(host)
  window.displayIfNeeded()
  host.displayIfNeeded()
  let geometryBeforePointer = personalDictionaryDeletePointerState(
    row: row,
    in: host,
    window: window
  )
  let windowIsActiveAndKey =
    application.isActive && window.isKeyWindow && application.keyWindow === window
      && window.isVisible
  let initialGeometryIsVisible = geometryBeforePointer.windowWithinVisibleFrame
    && geometryBeforePointer.rowFullyVisible
  if !windowIsActiveAndKey || !initialGeometryIsVisible {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: deletedEntry.id,
        deleteIdentifier: deleteID,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
  }
  try #require(windowIsActiveAndKey && initialGeometryIsVisible)

  let pointerOutsideRows = NSPoint(
    x: host.visibleRect.minX + 8,
    y: host.isFlipped ? host.visibleRect.minY + 8 : host.visibleRect.maxY - 8
  )
  let outsideRowsScreenPoint = personalDictionaryScreenPoint(
    fromHostPoint: pointerOutsideRows,
    host: host,
    window: window
  )
  let offRowPointIsVisible = host.visibleRect.contains(pointerOutsideRows)
    && screen.visibleFrame.contains(outsideRowsScreenPoint)
    && window.frame.contains(outsideRowsScreenPoint)
  if !offRowPointIsVisible || geometryBeforePointer.rowFrame.contains(pointerOutsideRows) {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: deletedEntry.id,
        deleteIdentifier: deleteID,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
  }
  try #require(
    offRowPointIsVisible && !geometryBeforePointer.rowFrame.contains(pointerOutsideRows)
  )
  try movePersonalDictionaryDeleteAdmissionPointer(
    to: pointerOutsideRows,
    in: host,
    window: window,
    screen: screen,
    row: row,
    entryID: deletedEntry.id,
    deleteIdentifier: deleteID,
    viewModel: viewModel
  )
  await settlePersonalDictionarySettingsHost(host)
  let geometryAfterExit = personalDictionaryDeletePointerState(
    row: row,
    in: host,
    window: window
  )
  let pointerReachedOffRowPoint = personalDictionaryScreenPointsAreNear(
    geometryAfterExit.pointerOnScreen,
    outsideRowsScreenPoint
  )
  let pointerActuallyExitedRow = !geometryAfterExit.rowFrame.contains(geometryAfterExit.pointerInHost)
    && geometryAfterExit.pointerWithinVisibleFrame
    && geometryAfterExit.pointerInsideWindow
    && geometryAfterExit.pointerInsideHost
  if !pointerReachedOffRowPoint || !pointerActuallyExitedRow {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: deletedEntry.id,
        deleteIdentifier: deleteID,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
  }
  try #require(pointerReachedOffRowPoint && pointerActuallyExitedRow)

  let rowCenter = NSPoint(
    x: geometryAfterExit.rowFrame.midX,
    y: geometryAfterExit.rowFrame.midY
  )
  let rowCenterScreenPoint = personalDictionaryScreenPoint(
    fromHostPoint: rowCenter,
    host: host,
    window: window
  )
  if !geometryAfterExit.rowFullyVisible || !screen.visibleFrame.contains(rowCenterScreenPoint) {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: deletedEntry.id,
        deleteIdentifier: deleteID,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
  }
  try #require(
    geometryAfterExit.rowFullyVisible && screen.visibleFrame.contains(rowCenterScreenPoint)
  )
  try movePersonalDictionaryDeleteAdmissionPointer(
    to: rowCenter,
    in: host,
    window: window,
    screen: screen,
    row: row,
    entryID: deletedEntry.id,
    deleteIdentifier: deleteID,
    viewModel: viewModel
  )
  await settlePersonalDictionarySettingsHost(host)
  window.displayIfNeeded()
  host.displayIfNeeded()
  let geometryAfterEntry = personalDictionaryDeletePointerState(
    row: row,
    in: host,
    window: window
  )
  let pointerReachedRowCenter = personalDictionaryScreenPointsAreNear(
    geometryAfterEntry.pointerOnScreen,
    rowCenterScreenPoint
  )
  let pointerEnteredRow = geometryAfterEntry.rowFrame.contains(geometryAfterEntry.pointerInHost)
  let windowRemainsActiveAndKey =
    application.isActive && window.isKeyWindow && application.keyWindow === window
      && window.isVisible
  let entryGeometryIsValid = pointerReachedRowCenter && pointerEnteredRow
    && geometryAfterEntry.pointerHitsOwnedContentSubtree
    && geometryAfterEntry.pointerWithinVisibleFrame
    && geometryAfterEntry.pointerInsideWindow
    && geometryAfterEntry.pointerInsideHost
    && geometryAfterEntry.windowWithinVisibleFrame
    && geometryAfterEntry.rowFullyVisible
  if !entryGeometryIsValid || !windowRemainsActiveAndKey {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: deletedEntry.id,
        deleteIdentifier: deleteID,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
  }
  try #require(entryGeometryIsValid && windowRemainsActiveAndKey)
  try await requirePersonalDictionaryDeleteAccessibilityElement(
    deleteID,
    row: row,
    entryID: deletedEntry.id,
    in: host,
    window: window,
    viewModel: viewModel
  )
  try requirePersonalDictionaryDeletePointerAdmission(
    row: row,
    entryID: deletedEntry.id,
    deleteIdentifier: deleteID,
    in: host,
    window: window,
    viewModel: viewModel
  )
  try clickPersonalDictionaryControlAtPaddedEdge(deleteID, in: host, window: window)
  await settlePersonalDictionarySettingsHost(host)
  #expect(viewModel.pendingEntryDeletion?.id == deletedEntry.id)

  let cancelID = "settings-vocabulary-delete-cancellation"
  let (cancelWindow, cancelHost) = try #require(
    personalDictionarySettingsSheet(
      attachedTo: window,
      containingAccessibilityIdentifier: cancelID
    )
  )
  let cancelFrame = try personalDictionarySettingsAccessibilityFrame(cancelID, in: cancelHost)
  let cancelBounds = personalDictionaryHostFrame(fromScreenFrame: cancelFrame, in: cancelHost)
  try sendPersonalDictionaryMouseClick(
    at: NSPoint(x: cancelBounds.midX, y: cancelBounds.midY),
    in: cancelHost,
    window: cancelWindow
  )

  #expect(viewModel.pendingEntryDeletion == nil)
  #expect(!viewModel.isEntryDeletionInFlight)
  #expect(viewModel.entries.map(\.id) == [deletedEntry.id, retainedEntry.id])
  #expect(viewModel.revision == displayedRevision)
  #expect(await gate.requestCount == 0)
  await settlePersonalDictionarySettingsHost(host)

  let geometryAfterCancellation = personalDictionaryDeletePointerState(
    row: row,
    in: host,
    window: window
  )
  let pointerRemainsOnVisibleRow = geometryAfterCancellation.rowFrame.contains(
    geometryAfterCancellation.pointerInHost
  ) && geometryAfterCancellation.pointerHitsOwnedContentSubtree
    && geometryAfterCancellation.pointerWithinVisibleFrame
    && geometryAfterCancellation.pointerInsideWindow
    && geometryAfterCancellation.pointerInsideHost
    && geometryAfterCancellation.windowWithinVisibleFrame
    && geometryAfterCancellation.rowFullyVisible
  if !pointerRemainsOnVisibleRow {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: deletedEntry.id,
        deleteIdentifier: deleteID,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
  }
  try #require(pointerRemainsOnVisibleRow)
  try await requirePersonalDictionaryDeleteAccessibilityElement(
    deleteID,
    row: row,
    entryID: deletedEntry.id,
    in: host,
    window: window,
    viewModel: viewModel
  )
  try requirePersonalDictionaryDeletePointerAdmission(
    row: row,
    entryID: deletedEntry.id,
    deleteIdentifier: deleteID,
    in: host,
    window: window,
    viewModel: viewModel
  )
  try clickPersonalDictionaryControlAtPaddedEdge(deleteID, in: host, window: window)
  await settlePersonalDictionarySettingsHost(host)

  let confirmID = "settings-vocabulary-delete-confirmation"
  let (confirmWindow, confirmHost) = try #require(
    personalDictionarySettingsSheet(
      attachedTo: window,
      containingAccessibilityIdentifier: confirmID
    )
  )
  #expect(window.attachedSheet === confirmWindow)
  #expect(confirmWindow.sheetParent === window)
  #expect(cancelWindow !== window.attachedSheet)
  #expect(cancelWindow.sheetParent == nil)
  #expect(cancelWindow.parent == nil)
  let confirmFrame = try personalDictionarySettingsAccessibilityFrame(confirmID, in: confirmHost)
  let confirmBounds = personalDictionaryHostFrame(fromScreenFrame: confirmFrame, in: confirmHost)
  do {
    try sendPersonalDictionaryMouseClick(
      at: NSPoint(x: confirmBounds.midX, y: confirmBounds.midY),
      in: confirmHost,
      window: confirmWindow
    )

    let gateClock = ContinuousClock()
    let gateDeadline = gateClock.now.advanced(by: .seconds(2))
    while gateClock.now < gateDeadline {
      if await gate.requestCount > 0 { break }
      try await gateClock.sleep(
        until: min(gateDeadline, gateClock.now.advanced(by: .milliseconds(10)))
      )
    }
    let mutationRequestCount = await gate.requestCount
    try #require(mutationRequestCount == 1)
    #expect(viewModel.pendingEntryDeletion == nil)
    #expect(viewModel.isEntryDeletionInFlight)
    #expect(viewModel.entries.map(\.id) == [deletedEntry.id, retainedEntry.id])
    #expect(viewModel.revision == displayedRevision)
    #expect(viewModel.claimEntryDeletionConfirmation() == nil)
    viewModel.requestEntryDeletion(retainedEntry, expectedRevision: displayedRevision)
    viewModel.cancelEntryDeletion()
    #expect(viewModel.pendingEntryDeletion == nil)
    #expect(viewModel.isEntryDeletionInFlight)
    #expect(await gate.requestCount == 1)

    let completed = await releaseAndWaitForPersonalDictionaryDeletion(gate, viewModel: viewModel)
    mutationGateCleanupCompleted = true
    #expect(completed)
  } catch {
    let completed = await releaseAndWaitForPersonalDictionaryDeletion(gate, viewModel: viewModel)
    mutationGateCleanupCompleted = true
    #expect(completed)
    throw error
  }

  #expect(await gate.requestCount == 1)
  #expect(!viewModel.isEntryDeletionInFlight)
  #expect(viewModel.entries.map(\.id) == [retainedEntry.id])
  #expect(viewModel.revision == displayedRevision + 1)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionaryEntryEditorPreservesIdentityAndMetadataWhenSavingCorrections() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let original = PersonalDictionaryEntry(
    id: settingsUUID(9),
    preferredForm: "Fleck",
    aliases: ["flick"],
    localeIdentifier: "en-GB",
    isPriority: true,
    isEnabled: false,
    origin: .suggested,
    usage: .init(useCount: 12, lastUsedAt: Date(timeIntervalSince1970: 4_200))
  )
  try await store.upsert(original)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  viewModel.beginEditingEntry(original)
  #expect(viewModel.entryEdit?.id == original.id)
  #expect(viewModel.entryEdit?.isNew == false)
  #expect(viewModel.entryEditUsesCorrection == true)
  viewModel.entryEditPreferredForm = "Fleck App"
  viewModel.entryEditAliases = "flick app, fleck application\nflick app"
  await viewModel.submitEntryEdit()

  let saved = try #require(viewModel.entries.first)
  #expect(saved.id == original.id)
  #expect(saved.preferredForm == "Fleck App")
  #expect(saved.aliases == ["flick app", "fleck application"])
  #expect(saved.localeIdentifier == original.localeIdentifier)
  #expect(saved.isPriority == original.isPriority)
  #expect(saved.isEnabled == original.isEnabled)
  #expect(saved.origin == original.origin)
  #expect(saved.usage == original.usage)
  #expect(viewModel.entryEdit == nil)
}

@Test @MainActor
func personalDictionaryEntryEditorMapsCorrectionToggleAndDeletesFromTheEditor() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let original = settingsEntry(7, "Parakeet", aliases: ["parrot key"])
  try await store.upsert(original)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  viewModel.beginEditingEntry(original)
  viewModel.entryEditUsesCorrection = false
  await viewModel.submitEntryEdit()
  #expect(viewModel.entries.first?.aliases == [])

  viewModel.beginEditingEntry(try #require(viewModel.entries.first))
  await viewModel.deleteEntryEdit()
  #expect(viewModel.entries.isEmpty)
  #expect(viewModel.entryEdit == nil)
}

@Test @MainActor
func personalDictionaryEntryEditorAddsOneWordThroughTheSharedFlow() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )
  await viewModel.load()

  viewModel.beginAddingEntry()
  #expect(viewModel.entryEdit?.isNew == true)
  viewModel.entryEditPreferredForm = "Gemma"
  viewModel.entryEditUsesCorrection = true
  viewModel.entryEditAliases = "Jemma"
  await viewModel.submitEntryEdit()

  #expect(viewModel.entries.map(\.preferredForm) == ["Gemma"])
  #expect(viewModel.entries.first?.aliases == ["Jemma"])
  #expect(viewModel.entries.first?.origin == .manual)
  #expect(viewModel.entries.first?.isEnabled == true)
}

@Test @MainActor
func personalDictionaryEntryEditorAllowsOnlyOneSaveAndKeepsTheActiveEditStable() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let gate = PersonalDictionaryEntryMutationGate(store: store)
  let original = settingsEntry(8, "Original")
  try await store.upsert(original)
  let viewModel = PersonalDictionarySettingsViewModel(
    store: store,
    entryMutation: { revision, mutation in
      try await gate.perform(expectedRevision: revision, mutation: mutation)
    }
  )
  await viewModel.load()
  viewModel.beginEditingEntry(original)
  let sessionID = try #require(viewModel.entryEdit?.sessionID)
  viewModel.entryEditPreferredForm = "Saved once"

  let firstSave = Task { await viewModel.submitEntryEdit() }
  await gate.waitUntilStarted()
  #expect(viewModel.isEntryEditMutationInFlight)

  viewModel.cancelEntryEdit()
  viewModel.beginAddingEntry()
  await viewModel.submitEntryEdit()

  #expect(viewModel.entryEdit?.sessionID == sessionID)
  #expect(await gate.requestCount == 1)
  await gate.release()
  await firstSave.value

  #expect(viewModel.entries.map(\.preferredForm) == ["Saved once"])
  #expect(viewModel.entryEdit == nil)
  #expect(!viewModel.isEntryEditMutationInFlight)
}

@Test @MainActor
func personalDictionaryEntryEditorAllowsOnlyOneDeleteWhileMutationIsInFlight() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let gate = PersonalDictionaryEntryMutationGate(store: store)
  let original = settingsEntry(6, "Delete once")
  try await store.upsert(original)
  let viewModel = PersonalDictionarySettingsViewModel(
    store: store,
    entryMutation: { revision, mutation in
      try await gate.perform(expectedRevision: revision, mutation: mutation)
    }
  )
  await viewModel.load()
  viewModel.beginEditingEntry(original)

  let firstDelete = Task { await viewModel.deleteEntryEdit() }
  await gate.waitUntilStarted()
  await viewModel.deleteEntryEdit()

  #expect(viewModel.isEntryEditMutationInFlight)
  #expect(await gate.requestCount == 1)
  await gate.release()
  await firstDelete.value

  #expect(viewModel.entries.isEmpty)
  #expect(viewModel.entryEdit == nil)
  #expect(!viewModel.isEntryEditMutationInFlight)
}

@Test @MainActor
func personalDictionarySettingsDoesNotRebaseConcurrentAddsOntoAnUndisplayedRevision() async {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )
  await viewModel.load()

  let displayedRevision = viewModel.revision
  await viewModel.add(
    preferredForm: "First",
    aliases: "",
    expectedRevision: displayedRevision
  )
  await viewModel.add(
    preferredForm: "Second",
    aliases: "",
    expectedRevision: displayedRevision
  )

  #expect(viewModel.entries.count == 1)
  #expect(viewModel.revision == 1)
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")
}

@Test @MainActor
func personalDictionarySettingsRecoversLatestRevisionWithoutRetryingConflictedMutation() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let entry = settingsEntry(1, "Visible term")
  try await store.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let displayedRevision = viewModel.revision

  _ = try await store.mutate(
    expectedRevision: displayedRevision,
    .upsert(settingsEntry(2, "Concurrent term"))
  )
  await viewModel.setEnabled(false, id: entry.id, expectedRevision: displayedRevision)

  #expect(viewModel.revision == displayedRevision + 1)
  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent term", "Visible term"])
  #expect(viewModel.entries.first(where: { $0.id == entry.id })?.isEnabled == true)
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")
}

@Test @MainActor
func personalDictionarySettingsApprovesAndDismissesSuggestionsExplicitly() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let approved = settingsSuggestion(1, "Approved", observed: ["aproved"], count: 8)
  let dismissed = settingsSuggestion(2, "Dismissed", observed: ["dismised"])
  try await store.recordSuggestion(approved)
  try await store.recordSuggestion(dismissed)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.approveSuggestion(id: approved.id, expectedRevision: viewModel.revision)
  #expect(viewModel.entries.first?.id == approved.id)
  #expect(viewModel.entries.first?.origin == .suggested)
  #expect(viewModel.entries.first?.usage.useCount == 8)
  #expect(viewModel.suggestions.map(\.id) == [dismissed.id])

  await viewModel.dismissSuggestion(id: dismissed.id, expectedRevision: viewModel.revision)
  #expect(viewModel.suggestions.isEmpty)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsEditAndApproveIsAtomicAndPreservesSuggestionOnFailure() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let suggestion = settingsSuggestion(
    2,
    "Suggested",
    observed: ["sugested"],
    count: 4,
    observedAt: Date(timeIntervalSince1970: 4_000)
  )
  try await store.upsert(settingsEntry(1, "Existing", aliases: ["collision"]))
  try await store.recordSuggestion(suggestion)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.editAndApproveSuggestion(
    id: suggestion.id,
    preferredForm: "Collision",
    aliases: "edited, EDITED\nsecond",
    expectedRevision: viewModel.revision
  )

  let failed = try await store.publishedSnapshot()
  #expect(failed.snapshot.entries.map(\.preferredForm) == ["Existing"])
  #expect(failed.snapshot.suggestions.map(\.id) == [suggestion.id])
  #expect(viewModel.errorMessage == "This change would introduce a dictionary conflict.")

  await viewModel.editAndApproveSuggestion(
    id: suggestion.id,
    preferredForm: "Edited suggestion",
    aliases: "edited, EDITED\nsecond",
    expectedRevision: viewModel.revision
  )
  let entry = viewModel.entries.first(where: { $0.id == suggestion.id })
  #expect(entry?.preferredForm == "Edited suggestion")
  #expect(entry?.aliases == ["edited", "second"])
  #expect(entry?.isEnabled == true)
  #expect(entry?.isPriority == false)
  #expect(entry?.origin == .suggested)
  #expect(entry?.usage == .init(useCount: 4, lastUsedAt: suggestion.lastObservedAt))
  #expect(viewModel.suggestions.isEmpty)
}

@Test @MainActor
func personalDictionarySettingsEditAndApproveRetainsDraftForExplicitConflictRetry() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let suggestion = settingsSuggestion(2, "Suggested", observed: ["sugested"], count: 3)
  try await store.recordSuggestion(suggestion)
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  viewModel.beginEditingSuggestion(suggestion)
  viewModel.suggestionEditPreferredForm = "Edited suggestion"
  viewModel.suggestionEditAliases = "edited, EDITED\nsecond"
  let displayedRevision = viewModel.revision

  _ = try await store.mutate(
    expectedRevision: displayedRevision,
    .upsert(settingsEntry(1, "Concurrent entry"))
  )
  await viewModel.submitSuggestionEdit()

  #expect(viewModel.revision == displayedRevision + 1)
  #expect(viewModel.suggestionEdit?.preferredForm == "Edited suggestion")
  #expect(viewModel.suggestionEdit?.aliases == "edited, EDITED\nsecond")
  #expect(viewModel.suggestions.map(\.id) == [suggestion.id])
  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent entry"])
  #expect(viewModel.errorMessage == "Dictionary changed; try again.")

  await viewModel.submitSuggestionEdit()

  #expect(viewModel.revision == displayedRevision + 2)
  #expect(viewModel.suggestionEdit == nil)
  #expect(viewModel.suggestions.isEmpty)
  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent entry", "Edited suggestion"])
  let approved = try #require(viewModel.entries.first { $0.id == suggestion.id })
  #expect(approved.aliases == ["edited", "second"])
  #expect(approved.origin == .suggested)
  #expect(approved.usage.useCount == 3)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsEditAndApproveRejectsIdentifierCollisionAtomically() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  let sharedID = settingsUUID(1)
  try await store.upsert(settingsEntry(1, "Existing"))
  try await store.recordSuggestion(settingsSuggestion(1, "Suggested"))
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()

  await viewModel.editAndApproveSuggestion(
    id: sharedID,
    preferredForm: "Edited",
    aliases: "alias",
    expectedRevision: viewModel.revision
  )

  let published = try await store.publishedSnapshot()
  #expect(published.snapshot.entries.map(\.preferredForm) == ["Existing"])
  #expect(published.snapshot.suggestions.map(\.preferredForm) == ["Suggested"])
  #expect(viewModel.errorMessage == "Could not apply that dictionary change.")
}

@Test @MainActor
func personalDictionarySettingsExportsCanonicalDictionaryAndVisibleEntriesOnlyCSV() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PersonalDictionaryStore(rootURL: root)
  try await store.upsert(settingsEntry(1, "Included"))
  try await store.upsert(settingsEntry(2, "Excluded"))
  try await store.recordSuggestion(settingsSuggestion(3, "Pending suggestion"))
  let viewModel = PersonalDictionarySettingsViewModel(store: store)
  await viewModel.load()
  let exportedAt = Date(timeIntervalSince1970: 10_000)

  await viewModel.prepareCanonicalExport(exportedAt: exportedAt)
  #expect(viewModel.canonicalExportData == (try await store.exportCanonicalTransfer(
    exportedAt: exportedAt
  )))

  viewModel.query = "included"
  await viewModel.prepareCSVExport()
  let csv = String(decoding: viewModel.csvExportData ?? Data(), as: UTF8.self)
  #expect(csv.hasPrefix(PersonalDictionaryCodec.csvHeader.joined(separator: ",")))
  #expect(csv.contains("Included"))
  #expect(!csv.contains("Excluded"))
  #expect(!csv.contains("Pending suggestion"))
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsCanonicalPreviewHasDeterministicTypedRowsAndOmissionGate() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  try await source.upsert(settingsEntry(1, "Imported update"))
  try await source.upsert(settingsEntry(3, "Imported add"))
  try await source.recordSuggestion(settingsSuggestion(4, "Imported suggestion"))
  try await target.upsert(settingsEntry(1, "Local update"))
  try await target.upsert(settingsEntry(2, "Local omission"))
  try await target.recordSuggestion(settingsSuggestion(5, "Local suggestion omission"))
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()

  let bytes = try await source.exportCanonicalTransfer(exportedAt: Date(timeIntervalSince1970: 1))
  await viewModel.previewCanonicalImport(bytes)

  #expect(viewModel.importPreviewData == bytes)
  #expect(viewModel.importPreviewRows.map(\.action) == [.update, .omit, .add, .add, .omit])
  #expect(viewModel.importPreviewRows.map(\.kind) == [
    .entry, .entry, .entry, .suggestion, .suggestion,
  ])
  #expect(viewModel.importPreviewRows.map(\.title) == [
    "Imported update", "Local omission", "Imported add", "Imported suggestion",
    "Local suggestion omission",
  ])
  #expect(viewModel.importRequiresOmissionConfirmation)
  #expect(viewModel.canConfirmImport)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsZeroChangePreviewCannotBeConfirmed() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  let entry = settingsEntry(1, "Same")
  try await source.upsert(entry)
  try await target.upsert(entry)
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()

  await viewModel.previewCanonicalImport(
    try await source.exportCanonicalTransfer(exportedAt: Date(timeIntervalSince1970: 2))
  )

  #expect(viewModel.importPreviewRows.isEmpty)
  #expect(!viewModel.canConfirmImport)
  #expect(!viewModel.importRequiresOmissionConfirmation)
}

@Test @MainActor
func personalDictionarySettingsStaleConfirmationRepreviewsAndRequiresAnotherConfirmation() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  try await source.upsert(settingsEntry(1, "Imported"))
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()
  let bytes = try await source.exportCanonicalTransfer(
    exportedAt: Date(timeIntervalSince1970: 3)
  )
  await viewModel.previewCanonicalImport(bytes)
  let displayedPreview = try #require(viewModel.importPreview)
  let staleRevision = displayedPreview.expectedLocalRevision
  #expect(viewModel.isImportPreviewPresented)

  _ = try await target.mutate(
    expectedRevision: viewModel.revision,
    .upsert(settingsEntry(2, "Concurrent local"))
  )
  await viewModel.confirmCanonicalImport(displayedPreview)

  #expect(viewModel.importPreview != nil)
  #expect(viewModel.isImportPreviewPresented)
  #expect(viewModel.importPreviewData == bytes)
  #expect(viewModel.importPreview?.expectedLocalRevision != staleRevision)
  #expect(viewModel.importRequiresOmissionConfirmation)
  #expect(viewModel.statusMessage == "Dictionary changed; review the updated preview.")
  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent local"])

  let updatedPreview = try #require(viewModel.importPreview)
  await viewModel.confirmCanonicalImport(updatedPreview)
  #expect(viewModel.entries.map(\.preferredForm) == ["Imported"])
  #expect(!viewModel.isImportPreviewPresented)
  #expect(viewModel.importPreview == nil)
  #expect(viewModel.importPreviewData == nil)
  #expect(viewModel.statusMessage == "Dictionary imported.")
}

@Test @MainActor
func personalDictionarySettingsQueuedConfirmationsUseExactDisplayedPreview() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  try await source.upsert(settingsEntry(1, "Imported"))
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()
  let bytes = try await source.exportCanonicalTransfer(
    exportedAt: Date(timeIntervalSince1970: 3)
  )
  await viewModel.previewCanonicalImport(bytes)
  let displayedPreview = try #require(viewModel.importPreview)
  #expect(!viewModel.importRequiresOmissionConfirmation)

  _ = try await target.mutate(
    expectedRevision: viewModel.revision,
    .upsert(settingsEntry(2, "Concurrent local"))
  )
  await viewModel.confirmCanonicalImport(displayedPreview)
  await viewModel.confirmCanonicalImport(displayedPreview)

  #expect(viewModel.entries.map(\.preferredForm) == ["Concurrent local"])
  #expect(viewModel.importPreviewData == bytes)
  #expect(viewModel.isImportPreviewPresented)
  #expect(viewModel.importPreview != displayedPreview)
  #expect(viewModel.importRequiresOmissionConfirmation)
  #expect(viewModel.statusMessage == "Dictionary changed; review the updated preview.")

  let updatedPreview = try #require(viewModel.importPreview)
  await viewModel.confirmCanonicalImport(updatedPreview)
  #expect(viewModel.entries.map(\.preferredForm) == ["Imported"])
  #expect(!viewModel.isImportPreviewPresented)
  #expect(viewModel.importPreview == nil)
  #expect(viewModel.importPreviewData == nil)
}

@Test @MainActor
func personalDictionarySettingsRejectsIntroducedImportConflictAndRetainsPreview() async throws {
  let sourceRoot = temporarySettingsDictionaryRoot()
  let targetRoot = temporarySettingsDictionaryRoot()
  defer {
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: targetRoot)
  }
  let source = PersonalDictionaryStore(rootURL: sourceRoot)
  let conflicting = PersonalDictionarySnapshotV2(
    revision: 7,
    entries: [settingsEntry(1, "Conflict"), settingsEntry(2, "conflict")]
  )
  let sourceURL = source.fileURL
  try FileManager.default.createDirectory(
    at: sourceURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try PersonalDictionaryCodec.encodeCanonicalJSON(conflicting).write(to: sourceURL)
  let target = PersonalDictionaryStore(rootURL: targetRoot)
  let viewModel = PersonalDictionarySettingsViewModel(store: target)
  await viewModel.load()
  let bytes = try await source.exportCanonicalTransfer(exportedAt: Date(timeIntervalSince1970: 4))
  await viewModel.previewCanonicalImport(bytes)

  #expect(viewModel.importConflictRows.map(\.code) == ["duplicatePreferredOwner"])
  #expect(viewModel.importConflictRows.map(\.count) == [1])
  let preview = try #require(viewModel.importPreview)
  await viewModel.confirmCanonicalImport(preview)

  #expect(viewModel.errorMessage == "This import would introduce a dictionary conflict.")
  #expect(viewModel.importPreview != nil)
  #expect(viewModel.importPreviewData == bytes)
  #expect(viewModel.entries.isEmpty)
}

@Test @MainActor
func personalDictionarySettingsCancellationIsSilentAndErrorsNeverExposeContent() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )
  await viewModel.load()
  await viewModel.previewCanonicalImport(Data("/private/path/SecretTerm".utf8))

  #expect(viewModel.errorMessage == "That file is not a valid Fleck dictionary.")
  #expect(!viewModel.errorMessage!.contains("/private/path"))
  #expect(!viewModel.errorMessage!.contains("SecretTerm"))
  let before = viewModel.state

  viewModel.handleFileOperationFailure(CocoaError(.userCancelled))
  #expect(viewModel.state == before)
  #expect(viewModel.errorMessage == "That file is not a valid Fleck dictionary.")

  viewModel.cancelImportPreview()
  #expect(viewModel.importPreview == nil)
  #expect(viewModel.importPreviewData == nil)
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsMapsRequiredErrorCategoriesToDistinctContentFreeMessages() {
  let cases: [(PersonalDictionaryStoreError, PersonalDictionarySettingsViewModel.Action, String)] = [
    (.invalidTransfer, .previewImport, "That file is not a valid Fleck dictionary."),
    (.revisionConflict, .entry, "Dictionary changed; try again."),
    (.revisionOverflow, .entry, "Personal dictionary cannot accept another change."),
    (.conflictIntroduced, .entry, "This change would introduce a dictionary conflict."),
    (.corruptData, .previewImport, "Dictionary data is corrupted."),
    (.fileTooLarge, .previewImport, "That dictionary file is too large."),
    (.publicationFailed, .entry, "Could not save personal dictionary. Try again."),
    (.invalidEntry, .entry, "Check the preferred form and aliases."),
    (.invalidSuggestion, .suggestion, "Could not update that suggestion."),
  ]

  let messages = cases.map { error, action, expected in
    let message = PersonalDictionarySettingsViewModel.message(for: error, action: action)
    #expect(message == expected)
    #expect(!message.contains("SecretTerm"))
    #expect(!message.contains("/private/path"))
    return message
  }

  #expect(Set(messages).count == messages.count)
}

@Test
func personalDictionaryRuntimeAndSettingsUseOneStoreAndNativeFormSurface() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let runtimeSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let viewModelSource = try String(
    contentsOf: repository.appendingPathComponent(
      "Sources/FleckApp/PersonalDictionarySettingsViewModel.swift"
    ),
    encoding: .utf8
  )

  #expect(runtimeSource.contains(
    "let personalDictionaryStore = PersonalDictionaryStore(rootURL: applicationSupportURL)"
  ))
  #expect(runtimeSource.contains(
    "try await personalDictionaryStore.snapshot().entries"
  ))
  #expect(runtimeSource.contains(
    "let personalDictionarySettingsViewModel = PersonalDictionarySettingsViewModel("
  ))
  #expect(runtimeSource.contains("store: personalDictionaryStore"))
  #expect(settingsSource.contains("suggestionRow(suggestion, expectedRevision: viewModel.revision)"))
  #expect(settingsSource.contains("expectedRevision: expectedRevision"))
  #expect(settingsSource.contains("case vocabulary = \"Vocabulary\""))
  #expect(settingsSource.contains("SettingsPageHeader("))
  #expect(settingsSource.contains("section: .vocabulary,\n          title: \"Dictionary\""))
  #expect(settingsSource.contains("Text(title ?? section.title)"))
  #expect(settingsSource.contains("Button(\"Import / Export…\")"))
  #expect(settingsSource.contains("Button(\"Add new\")"))
  #expect(settingsSource.contains("private func entryTitle("))
  #expect(settingsSource.contains("viewModel.beginEditingEntry(entry)"))
  #expect(settingsSource.contains("viewModel.requestEntryDeletion("))
  #expect(viewModelSource.contains("func setPriority("))
  #expect(viewModelSource.contains("mutation: .setPriority(priority, id: id)"))
  #expect(viewModelSource.contains("func requestEntryDeletion("))
  #expect(viewModelSource.contains("func confirmEntryDeletion() async"))
  #expect(viewModelSource.contains("expectedRevision: request.expectedRevision"))
  #expect(settingsSource.contains("PersonalDictionaryEntryEditSheet("))
  #expect(settingsSource.contains("Toggle(\"Correct a misspelling\""))
  #expect(settingsSource.contains("TextField(\"Correct from\""))
  #expect(settingsSource.contains("Button(\"Delete Word\", role: .destructive)"))
  #expect(settingsSource.contains("Image(systemName: \"xmark\")"))
  #expect(!settingsSource.contains(".searchable("))
  #expect(settingsSource.contains("private var optionsPopover: some View"))
  #expect(settingsSource.contains("viewModel.suggestionsHeaderActionTitle"))
  #expect(settingsSource.contains("private var transferFooter: some View"))
  #expect(settingsSource.contains("Button(\"Approve\""))
  #expect(settingsSource.contains("Button(\"Edit and Approve\""))
  #expect(settingsSource.contains("Button(\"Dismiss\""))
  #expect(settingsSource.contains("Button(\"Export Dictionary\""))
  #expect(settingsSource.contains("Button(\"Export Entries (CSV)\""))
  #expect(settingsSource.contains("Button(\"Import Dictionary\""))
  #expect(settingsSource.contains(".fileImporter("))
  #expect(settingsSource.contains(".fileExporter("))
  #expect(settingsSource.contains("filenameExtension: \"fleckdict\""))
  #expect(settingsSource.contains(".confirmationDialog("))
  #expect(settingsSource.contains(".sheet("))
  #expect(settingsSource.contains("get: { viewModel.isImportPreviewPresented }"))
  #expect(settingsSource.contains("presenting: omissionPreview"))
  #expect(settingsSource.contains("viewModel.confirmCanonicalImport(preview)"))
}

@Test
func personalDictionaryBooleanControlsUseCompactNativeSwitches() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(settingsSource.contains("Text(\"Disabled\")"))
  #expect(settingsSource.contains("Toggle(\"Correct a misspelling\""))
  #expect(settingsSource.contains("Toggle(\"Use this word in dictation\""))
  #expect(settingsSource.contains(".toggleStyle(.switch)"))
  #expect(settingsSource.contains(".controlSize(.small)"))
}

@Test
func personalDictionaryVocabularyUsesTheTaskFlowAndLocalSortControls() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(settingsSource.contains("title: \"Dictionary\""))
  #expect(settingsSource.contains("SettingsPageHeader("))
  #expect(settingsSource.contains("Button(\"Import / Export…\")"))
  #expect(settingsSource.contains("Button(\"Add new\")"))
  #expect(!settingsSource.contains("Teach Fleck the words and phrases that matter to you"))
  #expect(settingsSource.contains("@AppStorage(\"settings.vocabularySortOrder\")"))
  #expect(settingsSource.contains("Image(systemName: \"arrow.up.arrow.down\")"))
  #expect(settingsSource.contains("SettingsVocabularySortOrder"))
  #expect(settingsSource.contains("case aToZ"))
  #expect(settingsSource.contains("case zToA"))
  #expect(settingsSource.contains(".settingsSearchAnchor(.vocabularySort, request: visibleSearchRequest)"))
  #expect(settingsSource.contains(".settingsSearchAnchor(.vocabularyReload, request: visibleSearchRequest)"))
  #expect(settingsSource.contains("viewModel.load()"))
  #expect(settingsSource.contains("isReloading"))
  #expect(settingsSource.contains("isSearchExpanded"))
  #expect(settingsSource.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
  #expect(settingsSource.contains("!hasModalPresentation"))
  #expect(settingsSource.contains("isSettingsSearchFieldFocused"))
  #expect(settingsSource.contains(".focusable()"))
  #expect(settingsSource.contains(".focused($isSearchTriggerFocused)"))
  #expect(settingsSource.contains("settings-keyboard-focus-vocabulary-search-trigger"))
  #expect(!settingsSource.contains(".onKeyPress(phases: .down)"))
  #expect(settingsSource.contains("Section(isNew ? \"Add New\" : \"Edit Word\")"))
  #expect(settingsSource.contains("Use this word in dictation"))
  #expect(!settingsSource.contains("Sync"))
  #expect(!settingsSource.contains("Synced"))
}

@Test
func personalDictionaryVocabularySearchUsesResponsiveInlineFieldAndAccessibleDismissal() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(settingsSource.contains("ViewThatFits(in: .horizontal)"))
  #expect(settingsSource.contains("private var dictionaryToolbar: some View"))
  #expect(settingsSource.contains("private var searchControl: some View"))
  #expect(settingsSource.contains(".textFieldStyle(.plain)"))
  #expect(settingsSource.contains("private var searchSurface: some View"))
  #expect(settingsSource.contains(".frame(minWidth: 64, maxWidth: 164"))
  let searchSurfaceStart = try #require(
    settingsSource.range(of: "private var searchSurface: some View")
  )
  let searchSurfaceEnd = try #require(
    settingsSource.range(
      of: "private var hasModalPresentation: Bool",
      range: searchSurfaceStart.upperBound..<settingsSource.endIndex
    )
  )
  let searchSurfaceSource = settingsSource[searchSurfaceStart.lowerBound..<searchSurfaceEnd.lowerBound]
  #expect(!searchSurfaceSource.contains("magnifyingglass"))
  #expect(searchSurfaceSource.contains("TextField(\"Search vocabulary\""))
  #expect(searchSurfaceSource.contains("settings-vocabulary-local-search-field"))
  #expect(settingsSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
  #expect(settingsSource.contains("AppMotion(reduceMotion: reduceMotion)"))
  #expect(settingsSource.contains("motion.allowsSpatialMotion(for: searchPresentationSource)"))
  #expect(settingsSource.contains("openSearch(source: isCommandF ? .keyboard : .pointer)"))
  #expect(settingsSource.contains("withAnimation(motion.presentationAnimation(for: source))"))
  #expect(settingsSource.contains(".onExitCommand"))
  #expect(settingsSource.contains("closeSearch(source: .keyboard)"))
  #expect(settingsSource.contains("viewModel.query = \"\""))
  #expect(settingsSource.contains("Clear vocabulary search"))
  #expect(settingsSource.contains("xmark"))

  let optionsStart = try #require(settingsSource.range(of: "private var optionsPopover: some View"))
  let sortStart = try #require(settingsSource.range(
    of: "private var sortControl: some View",
    range: optionsStart.upperBound..<settingsSource.endIndex
  ))
  let optionsSource = settingsSource[optionsStart.lowerBound..<sortStart.lowerBound]
  #expect(optionsSource.contains("Text(\"Transfer\")"))
  #expect(!optionsSource.contains("ForEach(PersonalDictionarySettingsViewModel.Filter.allCases)"))
  #expect(!optionsSource.contains("Button(\"Find in Dictionary\")"))
  #expect(!optionsSource.contains("sortControl"))
  #expect(!optionsSource.contains("reloadControl"))
  #expect(optionsSource.contains("settingsSearchAnchor(.vocabularyTransfer"))
  #expect(optionsSource.contains("presentAfterClosingOptions"))
  #expect(!settingsSource.contains("vocabularyFilter"))
  #expect(settingsSource.contains("private var optionsPresentation: Binding<Bool>"))
  #expect(settingsSource.contains("private func optionsPopoverDidDisappear()"))
}

@Test
func personalDictionaryVocabularySearchDefersQueryClearUntilFieldTeardown() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(settingsSource.contains("private func clearSearchQueryAfterTeardown()"))
  #expect(settingsSource.contains("Task { @MainActor in"))
  #expect(settingsSource.contains("await Task.yield()"))
  #expect(settingsSource.contains("clearSearchQueryAfterTeardown()"))
  #expect(settingsSource.contains("closeSearch(source: .pointer)"))
  #expect(settingsSource.contains("closeSearch(source: .keyboard)"))
}

@Test
func personalDictionaryFocusIsNeutralAndKeepsControlsKeyboardAccessible() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let searchSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsSearch.swift"),
    encoding: .utf8
  )

  #expect(searchSource.contains("field.focusRingType = .none"))
  #expect(searchSource.contains("onFocusChange(true)"))
  #expect(searchSource.contains(".focusEffectDisabled()"))
  #expect(!searchSource.contains("usesNeutralKeyboardFocus"))
  #expect(searchSource.contains("Color.primary.opacity(0.72)"))
  #expect(searchSource.contains(".overlay(alignment: .bottom)"))
  #expect(!searchSource.contains("vocabularyFilter"))
  #expect(!searchSource.contains("usesFilterUnderlineFocusStyle"))
  #expect(settingsSource.contains(".focused($focusedAction"))
  #expect(
    settingsSource.contains(
      ".underline(focusedAction == .edit || accessibilityFocusedAction == .edit)"
    )
  )
  #expect(
    settingsSource.contains(
      ".padding(.horizontal, 12)\n      .frame(maxWidth: .infinity"
    )
  )
  #expect(settingsSource.contains(": \"Star \\(entry.preferredForm)\""))
  #expect(settingsSource.contains(".accessibilityHidden(true)"))
  #expect(settingsSource.contains(".accessibilityLabel(\"Edit \\(entry.preferredForm)\")"))
  #expect(settingsSource.contains("suggestionsHeaderActionTitle"))
  #expect(!settingsSource.contains("Personal dictionary filter"))
  #expect(!settingsSource.contains("Color.accentColor.opacity(0.12)"))
}

@Test @MainActor
func personalDictionaryCommandFRoutesFromSidebarAndContentWithoutBreakingSearchOrSheets()
  async throws
{
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appState = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await appState.waitUntilInitialLoad()
  appState.preferences.dictationCapsuleEnabled = false
  let runtime = DictationRuntime(appState: appState, applicationSupportURL: root)
  runtime.requestSettings(.vocabulary)

  let host = NSHostingView(
    rootView: SettingsView(runtime: runtime)
      .environmentObject(appState)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 840, height: 600),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settlePersonalDictionarySettingsHost(host)

  let settingsSearchField = try #require(
    personalDictionarySettingsView(
      withAccessibilityIdentifier: "settings-search-field",
      in: host
    ) as? NSSearchField
  )
  let sidebarList = try #require(personalDictionarySettingsTableView(in: host))
  #expect(runtime.pendingSettingsSection == nil)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)

  #expect(window.makeFirstResponder(sidebarList))
  #expect(window.firstResponder === sidebarList)
  window.sendEvent(try #require(personalDictionaryCommandFEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) != nil)

  window.sendEvent(try #require(personalDictionaryEscapeEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)

  #expect(window.makeFirstResponder(settingsSearchField))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsFieldIsFocused(settingsSearchField, in: window))
  window.sendEvent(try #require(personalDictionaryCommandFEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsFieldIsFocused(settingsSearchField, in: window))
  #expect(settingsSearchField.stringValue.isEmpty)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)

  #expect(window.makeFirstResponder(host))
  #expect(window.firstResponder === host)
  window.sendEvent(try #require(personalDictionaryCommandFEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) != nil)

  window.sendEvent(try #require(personalDictionaryEscapeEvent(for: window)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)
  runtime.personalDictionarySettingsViewModel.beginAddingEntry()
  await settlePersonalDictionarySettingsHost(host)
  let sheet = try #require(window.attachedSheet)
  sheet.sendEvent(try #require(personalDictionaryCommandFEvent(for: sheet)))
  await settlePersonalDictionarySettingsHost(host)
  #expect(personalDictionarySettingsView(
    withAccessibilityIdentifier: "settings-vocabulary-local-search-field",
    in: host
  ) == nil)

  runtime.personalDictionarySettingsViewModel.cancelEntryEdit()
  await settlePersonalDictionarySettingsHost(host)
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func personalDictionaryToolbarUsesPaddedTargetsInlineSearchAndKeyboardDismissal() async throws {
  let layouts: [(
    name: String,
    width: CGFloat,
    height: CGFloat,
    dynamicTypeSize: DynamicTypeSize,
    appearance: FleckThemeAppearance,
    reduceMotion: Bool
  )] = [
    ("wide-light", 620, 420, .large, .light, false),
    ("narrow-dark", 360, 440, .large, .dark, false),
    ("narrow-accessibility", 360, 500, .accessibility1, .light, true),
  ]

  for layout in layouts {
    let root = temporarySettingsDictionaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PersonalDictionaryStore(rootURL: root)
    try await store.upsert(settingsEntry(75, "Synthetic phrase"))
    let viewModel = PersonalDictionarySettingsViewModel(store: store)
    await viewModel.load()

    let (window, host) = await hostedPersonalDictionarySettingsSection(
      viewModel: viewModel,
      size: NSSize(width: layout.width, height: layout.height),
      dynamicTypeSize: layout.dynamicTypeSize,
      appearance: layout.appearance,
      reduceMotion: layout.reduceMotion
    )
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    await settlePersonalDictionarySettingsHost(host)

    let actionIdentifiers = [
      "settings-vocabulary-search-trigger",
      "settings-search-target-vocabulary-sort",
      "settings-search-target-vocabulary-reload",
    ]
    let accessibilityFrames = try actionIdentifiers.map {
      try personalDictionarySettingsAccessibilityFrame($0, in: host)
    }
    for frame in accessibilityFrames {
      #expect(abs(frame.width - 40) < 1)
      #expect(abs(frame.height - 40) < 1)
    }
    for firstIndex in accessibilityFrames.indices {
      for secondIndex in accessibilityFrames.indices where secondIndex > firstIndex {
        #expect(!accessibilityFrames[firstIndex].intersects(accessibilityFrames[secondIndex]))
      }
    }

    let divider = try #require(
      personalDictionarySettingsView(
        withAccessibilityIdentifier: "settings-vocabulary-toolbar-divider",
        in: host
      )
    )
    let dividerFrame = host.convert(divider.bounds, from: divider)
    for identifier in actionIdentifiers {
      let controlAccessibilityFrame = try personalDictionarySettingsAccessibilityFrame(
        identifier,
        in: host
      )
      let controlFrame = personalDictionaryHostFrame(
        fromScreenFrame: controlAccessibilityFrame,
        in: host
      )
      let clearance = host.isFlipped
        ? dividerFrame.minY - controlFrame.maxY
        : controlFrame.minY - dividerFrame.maxY
      #expect(clearance >= 12)
    }

    _ = try capturePersonalDictionaryHost(host, name: "dictionary-toolbar-\(layout.name)")

    let collapsedSearchFrame = try personalDictionarySettingsAccessibilityFrame(
      "settings-vocabulary-search-trigger",
      in: host
    )
    let localSearchFields = {
      personalDictionarySettingsViews(in: host)
        .compactMap { $0 as? NSTextField }
        .filter { field in
          !(field is NSSearchField) && field.placeholderString == "Search vocabulary"
        }
    }
    try clickPersonalDictionaryControlAtPaddedEdge(
      "settings-vocabulary-search-trigger",
      in: host,
      window: window
    )
    try await Task.sleep(for: .milliseconds(250))
    await settlePersonalDictionarySettingsHost(host)

    #expect(localSearchFields().count == 1)
    let searchField = try #require(
      personalDictionaryLocalSearchTextField(in: host)
    )
    #expect(!(searchField is NSSearchField))
    #expect(searchField.placeholderString == "Search vocabulary")
    let editor = try #require(searchField.currentEditor() as? NSTextView)
    #expect(window.firstResponder === editor)
    #expect(editor.selectedRange().length == 0)
    let expandedSearchFrame = try personalDictionarySettingsAccessibilityFrame(
      "settings-vocabulary-search-trigger",
      in: host
    )
    #expect(expandedSearchFrame.midX < collapsedSearchFrame.midX - 12)

    viewModel.query = "Direct"
    #expect(viewModel.query == "Direct")
    window.sendEvent(try #require(personalDictionaryEscapeEvent(for: window)))
    await settlePersonalDictionarySettingsHost(host)
    try await Task.sleep(for: .milliseconds(250))
    await settlePersonalDictionarySettingsHost(host)
    #expect(localSearchFields().isEmpty)
    #expect(viewModel.query.isEmpty)

    let searchTrigger = try #require(
      personalDictionarySettingsAccessibilityElement(
        withAccessibilityIdentifier: "settings-vocabulary-search-trigger",
        in: host
      )
    )
    #expect(
      personalDictionaryAccessibilityString(searchTrigger, attribute: "accessibilityLabel")
        == "Search vocabulary"
    )
    let closedSearchFrame = try personalDictionarySettingsAccessibilityFrame(
      "settings-vocabulary-search-trigger",
      in: host
    )
    #expect(abs(closedSearchFrame.width - 40) < 1)
    #expect(abs(closedSearchFrame.height - 40) < 1)
    let closedSearchHostFrame = personalDictionaryHostFrame(
      fromScreenFrame: closedSearchFrame,
      in: host
    )
    let closedSearchImage = try capturePersonalDictionaryHost(
      host,
      name: "dictionary-search-after-direct-escape-\(layout.name)"
    )
    #expect(
      personalDictionaryAccentPixelCount(
        in: closedSearchImage,
        host: host,
        frame: closedSearchHostFrame.insetBy(dx: -3, dy: -3),
        accent: .keyboardFocusIndicatorColor,
        matchingTolerance: 0.18
      ) == 0
    )

    try clickPersonalDictionaryControlAtPaddedEdge(
      "settings-vocabulary-search-trigger",
      in: host,
      window: window
    )
    try await Task.sleep(for: .milliseconds(250))
    await settlePersonalDictionarySettingsHost(host)
    #expect(localSearchFields().count == 1)
    let reopenedSearchField = try #require(
      personalDictionaryLocalSearchTextField(in: host)
    )
    #expect(!(reopenedSearchField is NSSearchField))
    #expect(reopenedSearchField.placeholderString == "Search vocabulary")
    let reopenedEditor = try #require(reopenedSearchField.currentEditor() as? NSTextView)
    #expect(window.firstResponder === reopenedEditor)

    viewModel.query = "Synthetic"
    try clickPersonalDictionaryControlAtPaddedEdge(
      "settings-search-target-vocabulary-sort",
      in: host,
      window: window
    )
    await settlePersonalDictionarySettingsHost(host)
    #expect(!(window.childWindows ?? []).isEmpty)

    let sortWindow = NSApp.keyWindow ?? window
    sortWindow.sendEvent(try #require(personalDictionaryEscapeEvent(for: sortWindow)))
    await settlePersonalDictionarySettingsHost(host)
    #expect((window.childWindows ?? []).isEmpty)
    #expect(localSearchFields().count == 1)
    #expect(viewModel.query == "Synthetic")

    window.sendEvent(try #require(personalDictionaryEscapeEvent(for: window)))
    await settlePersonalDictionarySettingsHost(host)
    try await Task.sleep(for: .milliseconds(80))
    #expect(localSearchFields().isEmpty)
    #expect(viewModel.query.isEmpty)

    #expect(window.makeFirstResponder(host))
    #expect(window.firstResponder === host)
    window.sendEvent(try #require(personalDictionaryCommandFEvent(for: window)))
    try await Task.sleep(for: .milliseconds(250))
    await settlePersonalDictionarySettingsHost(host)
    #expect(localSearchFields().count == 1)
    let commandFSearchField = try #require(
      personalDictionaryLocalSearchTextField(in: host)
    )
    #expect(!(commandFSearchField is NSSearchField))
    let commandFEditor = try #require(commandFSearchField.currentEditor() as? NSTextView)
    #expect(window.firstResponder === commandFEditor)

    window.sendEvent(try #require(personalDictionaryEscapeEvent(for: window)))
    await settlePersonalDictionarySettingsHost(host)
    try await Task.sleep(for: .milliseconds(80))
    #expect(localSearchFields().isEmpty)
    #expect(viewModel.query.isEmpty)

    let revisionBeforeExternalUpdate = viewModel.revision
    try await store.upsert(settingsEntry(76, "Refresh edge target"))
    #expect(viewModel.revision == revisionBeforeExternalUpdate)
    try clickPersonalDictionaryControlAtPaddedEdge(
      "settings-search-target-vocabulary-reload",
      in: host,
      window: window
    )
    await settlePersonalDictionarySettingsHost(host)
    let reloadClock = ContinuousClock()
    let reloadDeadline = reloadClock.now.advanced(by: .seconds(2))
    let didReload = {
      viewModel.revision == revisionBeforeExternalUpdate + 1
        && viewModel.entries.contains { $0.id == settingsUUID(76) }
    }
    while !didReload(), reloadClock.now < reloadDeadline {
      try await reloadClock.sleep(
        until: min(reloadDeadline, reloadClock.now.advanced(by: .milliseconds(10)))
      )
    }
    try #require(
      didReload(),
      "Dictionary reload did not complete; error: \(viewModel.errorMessage ?? "none")"
    )
    #expect(viewModel.revision == revisionBeforeExternalUpdate + 1)
    #expect(viewModel.entries.contains { $0.id == settingsUUID(76) })
  }
}

@Test @MainActor
func personalDictionaryPriorityStarStaysVisibleWithoutHoverAndDeleteRemainsHidden() async throws {
  for appearance in [FleckThemeAppearance.light, .dark] {
    let root = temporarySettingsDictionaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PersonalDictionaryStore(rootURL: root)
    let starredEntry = PersonalDictionaryEntry(
      id: settingsUUID(81),
      preferredForm: "Persistent star",
      isPriority: true
    )
    let unstarredEntry = settingsEntry(82, "Hover target")
    try await store.upsert(starredEntry)
    try await store.upsert(unstarredEntry)
    let viewModel = PersonalDictionarySettingsViewModel(store: store)
    await viewModel.load()

    let (window, host) = await hostedPersonalDictionarySettingsSection(
      viewModel: viewModel,
      size: NSSize(width: 540, height: 500),
      appearance: appearance
    )
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    await settlePersonalDictionarySettingsHost(host)

    let starredPriorityID = "settings-vocabulary-entry-priority-\(starredEntry.id.uuidString)"
    let starredDeleteID = "settings-vocabulary-entry-delete-\(starredEntry.id.uuidString)"
    let starredRow = try #require(
      personalDictionarySettingsView(
        withAccessibilityIdentifier: "settings-vocabulary-entry-frame-\(starredEntry.id.uuidString)",
        in: host
      )
    )
    let starredRowFrame = host.convert(starredRow.bounds, from: starredRow)
    let pointerOutsideRows = NSPoint(
      x: host.bounds.minX + 8,
      y: host.isFlipped ? host.bounds.minY + 8 : host.bounds.maxY - 8
    )
    try movePersonalDictionaryPointer(to: pointerOutsideRows, in: host, window: window)
    await settlePersonalDictionarySettingsHost(host)
    try await Task.sleep(for: .milliseconds(120))

    let priorityFrame = try personalDictionarySettingsAccessibilityFrame(
      starredPriorityID,
      in: host
    )
    let priorityElement = try #require(
      personalDictionarySettingsAccessibilityElement(
        withAccessibilityIdentifier: starredPriorityID,
        in: host
      )
    )
    #expect(
      personalDictionaryAccessibilityString(priorityElement, attribute: "accessibilityLabel")
        == "Unstar \(starredEntry.preferredForm)"
    )
    #expect(
      personalDictionaryAccessibilityString(priorityElement, attribute: "accessibilityValue")
        == "Starred"
    )
    #expect(abs(priorityFrame.width - 32) < 1)
    #expect(abs(priorityFrame.height - 32) < 1)
    #expect(
      personalDictionarySettingsAccessibilityElement(
        withAccessibilityIdentifier: starredDeleteID,
        in: host
      ) == nil
    )

    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .capy,
      mode: appearance == .dark ? .dark : .light,
      systemAppearance: appearance,
      reduceTransparency: false,
      increasedContrast: false
    )
    let screenshot = try capturePersonalDictionaryHost(
      host,
      name: "dictionary-priority-star-\(appearance == .dark ? "dark" : "light")"
    )
    let goldFrame = CGRect(
      x: host.bounds.maxX - 64,
      y: host.bounds.minY,
      width: 64,
      height: host.bounds.height
    )
    #expect(
      personalDictionaryAccentPixelCount(
        in: screenshot,
        host: host,
        frame: goldFrame,
        accent: personalDictionaryPriorityStarColor(
          appearance: appearance,
          windowAppearance: window.appearance
        ),
        matchingTolerance: 0.18
      ) > 0
    )
    #expect(
      personalDictionaryColorContrast(
        personalDictionaryPriorityStarColor(
          appearance: appearance,
          windowAppearance: window.appearance
        ),
        theme.nsColor(.window)
      ) > 3
    )

    try clickPersonalDictionaryTrailingStarAtPaddedEdge(
      in: host,
      rowFrame: starredRowFrame,
      window: window
    )
    await settlePersonalDictionarySettingsHost(host)
    try await Task.sleep(for: .milliseconds(120))
    await settlePersonalDictionarySettingsHost(host)
    #expect(viewModel.entries.first(where: { $0.id == starredEntry.id })?.isPriority == false)
    #expect(viewModel.pendingEntryDeletion == nil)

    let unstarredPriorityID = "settings-vocabulary-entry-priority-\(unstarredEntry.id.uuidString)"
    let unstarredDeleteID = "settings-vocabulary-entry-delete-\(unstarredEntry.id.uuidString)"
    #expect(
      personalDictionarySettingsAccessibilityElement(
        withAccessibilityIdentifier: unstarredPriorityID,
        in: host
      ) == nil
    )
    #expect(
      personalDictionarySettingsAccessibilityElement(
        withAccessibilityIdentifier: unstarredDeleteID,
        in: host
      ) == nil
    )
  }
}

@Test
func personalDictionaryUsesSharedHeaderAndResponsiveToolbarAndRetainsSuggestionReviewSurfaces()
  throws
{
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  let toolbarStart = try #require(
    settingsSource.range(of: "private var dictionaryToolbar: some View")
  )
  let searchControlStart = try #require(
    settingsSource.range(
      of: "private var searchTrigger: some View",
      range: toolbarStart.upperBound..<settingsSource.endIndex
    )
  )
  let toolbarSource = settingsSource[toolbarStart.lowerBound..<searchControlStart.lowerBound]

  #expect(settingsSource.contains(
    "SettingsPageHeader(\n          section: .vocabulary,\n          title: \"Dictionary\",\n          searchRequest: visibleSearchRequest"
  ))
  #expect(settingsSource.contains("SettingsSearchProbe(identifier: \"settings-vocabulary-toolbar-divider\")"))
  #expect(!toolbarSource.contains("Text(\"Dictionary\")"))
  #expect(!settingsSource.contains("ForEach(PersonalDictionarySettingsViewModel.Filter.allCases)"))
  #expect(toolbarSource.contains("private var suggestionsHeaderAction: some View"))
  #expect(toolbarSource.contains("Button(title)"))
  #expect(toolbarSource.contains(".controlSize(.small)"))
  #expect(toolbarSource.contains(".accessibilityLabel(title)"))
  #expect(toolbarSource.contains(".accessibilityHint("))
  #expect(toolbarSource.contains("searchActions"))
  #expect(toolbarSource.contains("searchControl"))
  #expect(toolbarSource.contains("sortControl"))
  #expect(toolbarSource.contains("reloadControl"))
  #expect(toolbarSource.contains("Button(\"Add new\")"))
  #expect(!settingsSource.contains("vocabularyFilter"))
  #expect(settingsSource.contains(".popover(isPresented: optionsPresentation"))
  #expect(settingsSource.contains("Color(nsColor: .controlBackgroundColor)"))
  #expect(settingsSource.contains("RoundedRectangle(cornerRadius: 12, style: .continuous)"))
  #expect(settingsSource.contains(".frame(maxWidth: .infinity, minHeight: 48"))
  #expect(settingsSource.contains("Divider().padding(.leading, 12)"))
  #expect(!settingsSource.contains(".frame(maxWidth: .infinity, minHeight: 280"))
  #expect(!settingsSource.contains("private var dictionaryPanel: some View"))
  #expect(settingsSource.contains("private var transferFooter: some View"))
  #expect(settingsSource.contains(".id(SettingsSearchTarget.vocabularyTransferFooter)"))
  #expect(settingsSource.contains("private struct PersonalDictionaryEntryRow: View"))
  #expect(settingsSource.contains("focusedAction"))
  #expect(settingsSource.contains("onHover"))
  #expect(settingsSource.contains("Button(\"Delete\", role: .destructive)"))
  #expect(settingsSource.contains("viewModel.claimEntryDeletionConfirmation()"))
  #expect(settingsSource.contains("viewModel.confirmEntryDeletion(request)"))
  #expect(settingsSource.contains("accessibilityLabel: entry.isPriority\n"))
  #expect(settingsSource.contains(": \"Star \\(entry.preferredForm)\""))
  #expect(settingsSource.contains(".opacity(showsActions || entry.isPriority ? 1 : 0)"))
  #expect(settingsSource.contains(".allowsHitTesting(showsActions || entry.isPriority)"))
  let rowStart = try #require(
    settingsSource.range(of: "private struct PersonalDictionaryEntryRow: View")
  )
  let editStart = try #require(
    settingsSource.range(
      of: "Button(action: onEdit)",
      range: rowStart.upperBound..<settingsSource.endIndex
    )
  )
  let actionStart = try #require(
    settingsSource.range(
      of: "HStack(spacing: 4)",
      range: editStart.upperBound..<settingsSource.endIndex
    )
  )
  let editSource = settingsSource[editStart.lowerBound..<actionStart.lowerBound]
  let rowActionsSource = settingsSource[actionStart.lowerBound...]
  #expect(!editSource.contains("star.fill"))
  #expect(rowActionsSource.contains("systemImage: entry.isPriority ? \"star.fill\" : \"star\""))
  #expect(settingsSource.contains("isHovered || isFocused"))
  #expect(rowActionsSource.contains(".opacity(showsActions ? 1 : 0)"))
  #expect(rowActionsSource.contains(".allowsHitTesting(showsActions)"))
  #expect(rowActionsSource.contains(".frame(width: 32, height: 32)"))
  #expect(rowActionsSource.contains(".contentShape(Rectangle())"))
  #expect(rowActionsSource.contains(".focused($focusedAction, equals: action)"))
  #expect(
    rowActionsSource.contains(".accessibilityFocused($accessibilityFocusedAction, equals: action)")
  )
  #expect(
    rowActionsSource.contains("isPriority ? priorityStarColor : theme.color(.textSecondary)")
  )
  #expect(settingsSource.contains("NSColor.systemYellow"))
  #expect(settingsSource.contains("theme.appearance == .light"))
  #expect(settingsSource.contains("blended(withFraction: 0.35, of: .black)"))
  #expect(settingsSource.contains("Text(\"Transfer\")"))
  #expect(!settingsSource.contains("DisclosureGroup(\"Transfer\""))
}

@Test
func personalDictionaryVocabularySortOrdersEntriesInBothDirections() {
  let entries = [
    settingsEntry(1, "zulu"),
    settingsEntry(2, "Alpha"),
    settingsEntry(3, "bravo"),
    PersonalDictionaryEntry(
      id: settingsUUID(4),
      preferredForm: "Beta",
      isPriority: true
    ),
  ]

  #expect(
    SettingsVocabularySortOrder.aToZ
      .sorted(entries, by: \.preferredForm, id: \.id, priority: \.isPriority)
      .map(\.preferredForm) == ["Beta", "Alpha", "bravo", "zulu"]
  )
  #expect(
    SettingsVocabularySortOrder.zToA
      .sorted(entries, by: \.preferredForm, id: \.id, priority: \.isPriority)
      .map(\.preferredForm) == ["Beta", "zulu", "bravo", "Alpha"]
  )

  let ties = [settingsEntry(5, "same"), settingsEntry(6, "Same")]
  let ascendingTies = SettingsVocabularySortOrder.aToZ
    .sorted(ties, by: \.preferredForm, id: \.id)
    .map(\.id)
  let descendingTies = SettingsVocabularySortOrder.zToA
    .sorted(ties, by: \.preferredForm, id: \.id)
    .map(\.id)
  #expect(ascendingTies == [settingsUUID(6), settingsUUID(5)])
  #expect(descendingTies == ascendingTies)
}

@Test
func personalDictionaryVocabularyUsageSortOrdersPinEntriesAndBreakTiesDeterministically() {
  let latestUse = Date(timeIntervalSince1970: 300)
  let earlierUse = Date(timeIntervalSince1970: 200)
  let entries = [
    PersonalDictionaryEntry(
      id: settingsUUID(1),
      preferredForm: "Zulu",
      usage: .init(useCount: 5, lastUsedAt: earlierUse)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(2),
      preferredForm: "Alpha",
      usage: .init(useCount: 8, lastUsedAt: latestUse)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(3),
      preferredForm: "alpha",
      usage: .init(useCount: 8, lastUsedAt: latestUse)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(4),
      preferredForm: "Beta",
      usage: .init(useCount: 12)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(5),
      preferredForm: "Pinned",
      isPriority: true,
      usage: .init(useCount: 0)
    ),
    PersonalDictionaryEntry(
      id: settingsUUID(6),
      preferredForm: "Bravo",
      usage: .init(useCount: 8, lastUsedAt: latestUse)
    ),
  ]

  let recentlyUsed = SettingsVocabularySortOrder.recentlyUsed
    .sorted(entries, by: \.preferredForm, id: \.id, priority: \.isPriority, usage: \.usage)
    .map(\.id)
  let mostUsed = SettingsVocabularySortOrder.mostUsed
    .sorted(entries, by: \.preferredForm, id: \.id, priority: \.isPriority, usage: \.usage)
    .map(\.id)

  #expect(
    recentlyUsed == [
      settingsUUID(5), settingsUUID(2), settingsUUID(3), settingsUUID(6), settingsUUID(1),
      settingsUUID(4),
    ]
  )
  #expect(
    mostUsed == [
      settingsUUID(5), settingsUUID(4), settingsUUID(2), settingsUUID(3), settingsUUID(6),
      settingsUUID(1),
    ]
  )
  #expect(SettingsVocabularySortOrder.recentlyUsed.suggestionSortOrder == .aToZ)
  #expect(SettingsVocabularySortOrder.mostUsed.suggestionSortOrder == .aToZ)
  #expect(SettingsVocabularySortOrder.zToA.suggestionSortOrder == .zToA)
  #expect(SettingsVocabularySortOrder(rawValue: "A–Z") == .aToZ)
  #expect(SettingsVocabularySortOrder(rawValue: "Z–A") == .zToA)
}

@Test
func personalDictionaryEntryListSortPassesUsageMetadata() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let sortStart = try #require(
    settingsSource.range(of: "private var sortedEntries: [PersonalDictionaryEntry]")
  )
  let suggestionsStart = try #require(
    settingsSource.range(
      of: "private var sortedSuggestions: [PersonalDictionarySuggestion]",
      range: sortStart.upperBound..<settingsSource.endIndex
    )
  )
  let sortedEntriesSource = settingsSource[sortStart.lowerBound..<suggestionsStart.lowerBound]

  #expect(sortedEntriesSource.contains("sortOrder.sorted("))
  #expect(sortedEntriesSource.contains("priority: \\.isPriority"))
  #expect(sortedEntriesSource.contains("usage: \\.usage"))
}

@Test
func personalDictionarySortSettingsSearchAliasesFindSortByUsage() {
  for query in ["recently used", "most used"] {
    #expect(
      SettingsSearchIndex.results(for: query).contains { $0.target == .vocabularySort }
    )
  }
}

@Test
func personalDictionarySortPopoverKeepsSearchAndKeyboardInteractionsAccessible() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let sortStart = try #require(settingsSource.range(of: "private var sortPopover: some View"))
  let reloadStart = try #require(
    settingsSource.range(
      of: "private var reloadControl: some View",
      range: sortStart.upperBound..<settingsSource.endIndex
    )
  )
  let sortSource = settingsSource[sortStart.lowerBound..<reloadStart.lowerBound]

  #expect(sortSource.contains("Text(\"SORT BY\")"))
  #expect(sortSource.contains(".background(.regularMaterial"))
  #expect(sortSource.contains("sortOrdersForCurrentFilter"))
  #expect(sortSource.contains("SettingsVocabularySortOrder.allCases"))
  #expect(sortSource.contains("viewModel.filter == .suggestions"))
  #expect(sortSource.contains("sortOrder.suggestionSortOrder"))
  #expect(sortSource.contains("if viewModel.filter != .suggestions"))
  #expect(sortSource.contains("Text(\"Usage reflects saved data, not live dictation.\")"))
  #expect(sortSource.contains("sortOrder = order"))
  #expect(sortSource.contains("Image(systemName: \"checkmark\")"))
  #expect(sortSource.contains("isHovered || isFocused"))
  #expect(sortSource.contains(".onHover"))
  #expect(sortSource.contains(".focused($focusedSortOrder, equals: order)"))
  #expect(sortSource.contains(".accessibilityLabel(\"Sort by \\(order.rawValue)\")"))
  #expect(
    sortSource.contains(".accessibilityValue(isSelected ? \"Selected\" : \"Not selected\")")
  )
  #expect(sortSource.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
  #expect(sortSource.contains(".popover(isPresented: $isSortPresented, arrowEdge: .bottom)"))
  #expect(sortSource.contains(".onExitCommand"))
  #expect(sortSource.contains("isSortPresented = false"))
  #expect(!sortSource.contains("Picker("))
  #expect(!sortSource.contains(".animation("))
  #expect(
    settingsSource.contains(
      ".settingsSearchAnchor(.vocabularySort, request: visibleSearchRequest)"
    )
  )
  #expect(
    settingsSource.contains(
      "if isSortPresented {\n          isSortPresented = false\n          return\n        }"
    )
  )
  #expect(settingsSource.contains(".onChange(of: searchRequest?.id, initial: true)"))
  #expect(settingsSource.contains(".onChange(of: hasModalPresentation)"))
  guard let sortEscapeStart = settingsSource.range(
    of: ".onExitCommand {\n        if isSortPresented {"
  ) else {
    Issue.record("The parent Escape handler must dismiss Sort by before search.")
    return
  }
  guard let sortEscapeEnd = settingsSource.range(
    of: "      .onAppear {",
    range: sortEscapeStart.upperBound..<settingsSource.endIndex
  ) else {
    Issue.record("The parent Escape handler must remain within the settings body.")
    return
  }
  let sortEscapeSource = settingsSource[sortEscapeStart.lowerBound..<sortEscapeEnd.lowerBound]
  let sortDismissal = try #require(sortEscapeSource.range(of: "if isSortPresented"))
  let searchDismissal = try #require(sortEscapeSource.range(of: "guard isSearchExpanded"))

  #expect(sortDismissal.lowerBound < searchDismissal.lowerBound)
  #expect(sortEscapeSource.contains("closeSearch(source: .keyboard)"))

  let optionsStart = try #require(
    settingsSource.range(of: "private var optionsPopover: some View")
  )
  let sortPopoverStart = try #require(
    settingsSource.range(
      of: "private var sortPopover: some View",
      range: optionsStart.upperBound..<settingsSource.endIndex
    )
  )
  let optionsSource = settingsSource[optionsStart.lowerBound..<sortPopoverStart.lowerBound]
  let optionsEscapeStart = try #require(optionsSource.range(of: ".onExitCommand {"))
  let optionsEscapeDismissal = try #require(
    optionsSource.range(
      of: "beginOptionsDismissal(returnFocus: true)",
      range: optionsEscapeStart.upperBound..<optionsSource.endIndex
    )
  )
  let optionsEscapeSource = optionsSource[
    optionsEscapeStart.lowerBound..<optionsEscapeDismissal.upperBound
  ]
  #expect(optionsEscapeSource.contains("guard isOptionsPresented, !hasModalPresentation"))
}

private func settingsEntry(
  _ number: UInt8,
  _ preferredForm: String,
  aliases: [String] = [],
  enabled: Bool = true
) -> PersonalDictionaryEntry {
  PersonalDictionaryEntry(
    id: settingsUUID(number),
    preferredForm: preferredForm,
    aliases: aliases,
    isEnabled: enabled
  )
}

private func settingsSuggestion(
  _ number: UInt8,
  _ preferredForm: String,
  observed: [String] = [],
  count: Int = 1,
  observedAt: Date = Date(timeIntervalSince1970: 1_000)
) -> PersonalDictionarySuggestion {
  PersonalDictionarySuggestion(
    id: settingsUUID(number),
    preferredForm: preferredForm,
    observedForms: observed,
    observationCount: count,
    lastObservedAt: observedAt
  )
}

private actor PersonalDictionaryEntryMutationGate {
  let store: PersonalDictionaryStore
  private(set) var requestCount = 0
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
  private var isReleased = false

  init(store: PersonalDictionaryStore) {
    self.store = store
  }

  func perform(
    expectedRevision: UInt64,
    mutation: PersonalDictionaryMutation
  ) async throws -> PersonalDictionaryPublishedSnapshot {
    requestCount += 1
    startedWaiters.forEach { $0.resume() }
    startedWaiters.removeAll()
    if !isReleased {
      await withCheckedContinuation { releaseContinuations.append($0) }
    }
    return try await store.mutate(expectedRevision: expectedRevision, mutation)
  }

  func waitUntilStarted() async {
    guard requestCount == 0 else { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }

  func release() {
    isReleased = true
    releaseContinuations.forEach { $0.resume() }
    releaseContinuations.removeAll()
  }
}

@MainActor
private func releaseAndWaitForPersonalDictionaryDeletion(
  _ gate: PersonalDictionaryEntryMutationGate,
  viewModel: PersonalDictionarySettingsViewModel
) async -> Bool {
  await Task { @MainActor in
    await gate.release()
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while viewModel.isEntryDeletionInFlight, clock.now < deadline {
      try? await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(10))))
    }
    return !viewModel.isEntryDeletionInFlight
  }.value
}

private func settingsUUID(_ number: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
}

private func temporarySettingsDictionaryRoot() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckSettingsTests-\(UUID().uuidString)", isDirectory: true)
}

@MainActor
private func personalDictionarySettingsView(
  withAccessibilityIdentifier identifier: String,
  in view: NSView
) -> NSView? {
  if view.accessibilityIdentifier() == identifier {
    return view
  }
  for subview in view.subviews {
    if let match = personalDictionarySettingsView(
      withAccessibilityIdentifier: identifier,
      in: subview
    ) {
      return match
    }
  }
  return nil
}

@MainActor
private func personalDictionarySettingsSheet(
  attachedTo fixtureWindow: NSWindow,
  containingAccessibilityIdentifier identifier: String
) -> (NSWindow, NSView)? {
  guard let sheetWindow = fixtureWindow.attachedSheet,
    sheetWindow.sheetParent === fixtureWindow,
    let contentView = sheetWindow.contentView,
    personalDictionarySettingsAccessibilityElement(
      withAccessibilityIdentifier: identifier,
      in: contentView
    ) != nil
  else {
    return nil
  }
  return (sheetWindow, contentView)
}

@MainActor
private func requirePersonalDictionaryDeleteAccessibilityElement(
  _ identifier: String,
  row: NSView,
  entryID: UUID,
  in host: NSView,
  window: NSWindow,
  viewModel: PersonalDictionarySettingsViewModel
) async throws {
  let application = NSApplication.shared
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(2))
  do {
    while clock.now < deadline {
      try Task.checkCancellation()
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
      window.displayIfNeeded()
      try Task.checkCancellation()
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async {
          continuation.resume()
        }
      }
      try Task.checkCancellation()
      guard clock.now < deadline else { break }
      let deleteElementIsReady = application.isActive
        && window.isKeyWindow
        && application.keyWindow === window
        && window.isVisible
        && personalDictionarySettingsAccessibilityElement(
          withAccessibilityIdentifier: identifier,
          in: host
        ) != nil
      try Task.checkCancellation()
      guard clock.now < deadline else { break }
      if deleteElementIsReady {
        return
      }
      try Task.checkCancellation()
      try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(10))))
      try Task.checkCancellation()
    }
    try #require(clock.now < deadline)
  } catch {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: entryID,
        deleteIdentifier: identifier,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
    throw error
  }
}

@MainActor
private func requirePersonalDictionaryDeletePointerAdmission(
  row: NSView,
  entryID: UUID,
  deleteIdentifier: String,
  in host: NSView,
  window: NSWindow,
  viewModel: PersonalDictionarySettingsViewModel
) throws {
  let pointerState = personalDictionaryDeletePointerState(row: row, in: host, window: window)
  let application = NSApplication.shared
  let pointerRemainsAdmitted = pointerState.rowFrame.contains(pointerState.pointerInHost)
    && pointerState.pointerHitsOwnedContentSubtree
    && pointerState.pointerWithinVisibleFrame
    && pointerState.pointerInsideWindow
    && pointerState.pointerInsideHost
    && pointerState.windowWithinVisibleFrame
    && pointerState.rowFullyVisible
    && application.isActive
    && window.isKeyWindow
    && application.keyWindow === window
    && window.isVisible
  if !pointerRemainsAdmitted {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: entryID,
        deleteIdentifier: deleteIdentifier,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
  }
  try #require(pointerRemainsAdmitted)
}

@MainActor
private struct PersonalDictionaryDeletePointerState {
  let pointerOnScreen: NSPoint
  let pointerInWindow: NSPoint
  let pointerInHost: NSPoint
  let rowFrame: NSRect
  let rowVisibleFrame: NSRect
  let rowFrameOnScreen: NSRect
  let screenVisibleFrame: NSRect
  let windowWithinVisibleFrame: Bool
  let pointerWithinVisibleFrame: Bool
  let pointerInsideWindow: Bool
  let pointerInsideHost: Bool
  let rowFullyVisible: Bool
  let pointerHitsOwnedContentSubtree: Bool
}

@MainActor
private func boundPersonalDictionaryDeleteAdmissionViewport(
  window: NSWindow,
  host: NSHostingView<AnyView>,
  screen: NSScreen,
  contentSize: NSSize
) {
  let availableFrame = screen.visibleFrame.insetBy(dx: 12, dy: 12)
  host.sizingOptions = []
  window.setContentSize(contentSize)
  let windowInsets = NSSize(
    width: max(window.frame.width - host.frame.width, 0),
    height: max(window.frame.height - host.frame.height, 0)
  )
  let maximumContentSize = NSSize(
    width: max(1, availableFrame.width - windowInsets.width),
    height: max(1, availableFrame.height - windowInsets.height)
  )
  let viewportSize = NSSize(
    width: min(contentSize.width, maximumContentSize.width),
    height: min(contentSize.height, maximumContentSize.height)
  )
  window.setContentSize(viewportSize)
  host.autoresizingMask = [.width, .height]
  host.setFrameOrigin(.zero)
  host.setFrameSize(viewportSize)
  host.layoutSubtreeIfNeeded()
  window.displayIfNeeded()
  let frame = window.frame
  window.setFrameOrigin(
    NSPoint(
      x: availableFrame.midX - frame.width / 2,
      y: availableFrame.midY - frame.height / 2
    )
  )
  window.displayIfNeeded()
  host.layoutSubtreeIfNeeded()
}

@MainActor
private func personalDictionaryScreenPoint(
  fromHostPoint point: NSPoint,
  host: NSView,
  window: NSWindow
) -> NSPoint {
  window.convertToScreen(NSRect(origin: host.convert(point, to: nil), size: .zero)).origin
}

private func personalDictionaryScreenPointsAreNear(_ lhs: NSPoint, _ rhs: NSPoint) -> Bool {
  abs(lhs.x - rhs.x) <= 1 && abs(lhs.y - rhs.y) <= 1
}

@MainActor
private func personalDictionaryDeletePointerState(
  row: NSView,
  in host: NSView,
  window: NSWindow
) -> PersonalDictionaryDeletePointerState {
  let pointerOnScreen = NSEvent.mouseLocation
  let pointerInWindow = window.convertFromScreen(NSRect(origin: pointerOnScreen, size: .zero)).origin
  let pointerInHost = host.convert(pointerInWindow, from: nil)
  let rowFrame = host.convert(row.bounds, from: row)
  let rowVisibleFrame = host.convert(row.visibleRect, from: row)
  let rowFrameOnScreen = window.convertToScreen(host.convert(rowFrame, to: nil))
  let visibleRowFrameOnScreen = window.convertToScreen(host.convert(rowVisibleFrame, to: nil))
  let screenVisibleFrame = window.screen?.visibleFrame ?? .zero
  var hitView: NSView?
  if let contentView = window.contentView,
    contentView === host,
    let hitTestSuperview = contentView.superview
  {
    let pointInSuperview = hitTestSuperview.convert(pointerInWindow, from: nil)
    hitView = contentView.hitTest(pointInSuperview)
  }
  var pointerHitsOwnedContentSubtree = false
  while let view = hitView {
    if view === host {
      pointerHitsOwnedContentSubtree = true
      break
    }
    hitView = view.superview
  }
  return PersonalDictionaryDeletePointerState(
    pointerOnScreen: pointerOnScreen,
    pointerInWindow: pointerInWindow,
    pointerInHost: pointerInHost,
    rowFrame: rowFrame,
    rowVisibleFrame: rowVisibleFrame,
    rowFrameOnScreen: rowFrameOnScreen,
    screenVisibleFrame: screenVisibleFrame,
    windowWithinVisibleFrame: screenVisibleFrame.contains(window.frame),
    pointerWithinVisibleFrame: screenVisibleFrame.contains(pointerOnScreen),
    pointerInsideWindow: window.frame.contains(pointerOnScreen),
    pointerInsideHost: host.visibleRect.contains(pointerInHost),
    rowFullyVisible: host.visibleRect.contains(rowFrame)
      && rowVisibleFrame.contains(rowFrame)
      && screenVisibleFrame.contains(rowFrameOnScreen)
      && screenVisibleFrame.contains(visibleRowFrameOnScreen),
    pointerHitsOwnedContentSubtree: pointerHitsOwnedContentSubtree
  )
}

@MainActor
private func movePersonalDictionaryDeleteAdmissionPointer(
  to point: NSPoint,
  in host: NSView,
  window: NSWindow,
  screen: NSScreen,
  row: NSView,
  entryID: UUID,
  deleteIdentifier: String,
  viewModel: PersonalDictionarySettingsViewModel
) throws {
  do {
    let pointOnScreen = personalDictionaryScreenPoint(
      fromHostPoint: point,
      host: host,
      window: window
    )
    let screenFrame = screen.frame
    let displayNumber = try #require(
      screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    )
    let displayID = CGDirectDisplayID(displayNumber.uint32Value)
    let displayBounds = CGDisplayBounds(displayID)
    try #require(screen.visibleFrame.contains(pointOnScreen))
    try #require(
      screenFrame.width > 0 && screenFrame.height > 0
        && displayBounds.width > 0 && displayBounds.height > 0
    )
    let pointInDisplay = CGPoint(
      x: (pointOnScreen.x - screenFrame.minX) * displayBounds.width / screenFrame.width,
      y: (screenFrame.maxY - pointOnScreen.y) * displayBounds.height / screenFrame.height
    )
    try #require(CGDisplayMoveCursorToPoint(displayID, pointInDisplay) == .success)
    let pointerOnScreen = NSEvent.mouseLocation
    let pointerInWindow = window.convertFromScreen(
      NSRect(origin: pointerOnScreen, size: .zero)
    ).origin
    let event = try #require(
      NSEvent.mouseEvent(
        with: .mouseMoved,
        location: pointerInWindow,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 0,
        pressure: 0
      )
    )
    window.sendEvent(event)
  } catch {
    print(
      personalDictionaryDeleteAdmissionDiagnostic(
        row: row,
        entryID: entryID,
        deleteIdentifier: deleteIdentifier,
        in: host,
        window: window,
        viewModel: viewModel
      )
    )
    throw error
  }
}

@MainActor
private func personalDictionaryDeleteAdmissionDiagnostic(
  row: NSView,
  entryID: UUID,
  deleteIdentifier: String,
  in host: NSView,
  window: NSWindow,
  viewModel: PersonalDictionarySettingsViewModel
) -> String {
  let pointerState = personalDictionaryDeletePointerState(row: row, in: host, window: window)
  let expectedIdentifiers = [
    "settings-vocabulary-entry-frame-\(entryID.uuidString)",
    "settings-vocabulary-entry-\(entryID.uuidString)",
    deleteIdentifier,
    "settings-vocabulary-entry-priority-\(entryID.uuidString)",
    "settings-vocabulary-delete-cancellation",
    "settings-vocabulary-delete-confirmation",
  ]
  let actualIdentifiers = expectedIdentifiers.filter {
    personalDictionarySettingsAccessibilityElement(
      withAccessibilityIdentifier: $0,
      in: host
    ) != nil
  }
  return """
  [passive synthetic failure-only Dictionary Delete admission diagnostic]
  rowID=settings-vocabulary-entry-frame-\(entryID.uuidString)
  pointerScreen=\(pointerState.pointerOnScreen) pointerWindow=\(pointerState.pointerInWindow)
  pointerLocal=\(pointerState.pointerInHost)
  hostBounds=\(host.bounds) hostVisibleRect=\(host.visibleRect)
  rowBounds=\(row.bounds) rowFrame=\(pointerState.rowFrame)
  rowVisibleRect=\(row.visibleRect) rowVisibleFrame=\(pointerState.rowVisibleFrame)
  rowScreenFrame=\(pointerState.rowFrameOnScreen)
  screenVisibleFrame=\(pointerState.screenVisibleFrame)
  windowWithinVisibleFrame=\(pointerState.windowWithinVisibleFrame)
  rowFullyVisible=\(pointerState.rowFullyVisible)
  pointerWithinVisibleFrame=\(pointerState.pointerWithinVisibleFrame)
  pointerInsideWindow=\(pointerState.pointerInsideWindow)
  pointerInsideHost=\(pointerState.pointerInsideHost)
  pointerHitsOwnedContentSubtree=\(pointerState.pointerHitsOwnedContentSubtree)
  rowHidden=\(row.isHiddenOrHasHiddenAncestor) rowAlpha=\(row.alphaValue)
  windowFrame=\(window.frame) windowVisible=\(window.isVisible) windowIsKey=\(window.isKeyWindow)
  appActive=\(NSApplication.shared.isActive) appKeyWindowMatches=\(NSApplication.shared.keyWindow === window)
  actualAXIdentifiers=\(actualIdentifiers)
  pendingRequest=\(String(describing: viewModel.pendingEntryDeletion))
  """
}

@MainActor
private func personalDictionarySettingsTableView(in view: NSView) -> NSTableView? {
  if let tableView = view as? NSTableView {
    return tableView
  }
  for subview in view.subviews {
    if let tableView = personalDictionarySettingsTableView(in: subview) {
      return tableView
    }
  }
  return nil
}

@MainActor
private func personalDictionarySettingsFieldIsFocused(
  _ field: NSTextField,
  in window: NSWindow
) -> Bool {
  if window.firstResponder === field { return true }
  guard let fieldEditor = field.currentEditor() else { return false }
  return window.firstResponder === fieldEditor
}

@MainActor
private func hostedPersonalDictionarySettingsSection(
  viewModel: PersonalDictionarySettingsViewModel,
  size: NSSize,
  dynamicTypeSize: DynamicTypeSize = .large,
  appearance: FleckThemeAppearance = .light,
  reduceMotion: Bool = false
) async -> (NSWindow, NSHostingView<AnyView>) {
  NSApplication.shared.accessibilitySetValue(
    true,
    forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
  )
  let theme = FleckThemeSnapshot.resolve(
    colorTheme: .capy,
    mode: appearance == .dark ? .dark : .light,
    systemAppearance: appearance,
    reduceTransparency: false,
    increasedContrast: false
  )
  let rootView = AnyView(
    PersonalDictionarySettingsSection(
      viewModel: viewModel,
      searchRequest: .constant(nil),
      pageScrollReadyRequestID: nil,
      selectedSection: .constant(.vocabulary)
    )
    .environment(\.fleckThemeSnapshot, theme)
    .environment(\.colorScheme, theme.colorScheme)
    .environment(\.dynamicTypeSize, dynamicTypeSize)
    .environment(\._accessibilityReduceMotion, reduceMotion)
    .padding(12)
  )
  let host = NSHostingView(rootView: rootView)
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settlePersonalDictionarySettingsHost(host)
  return (window, host)
}

@MainActor
private func personalDictionarySettingsViews(in view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap(personalDictionarySettingsViews(in:))
}

@MainActor
private func personalDictionaryLocalSearchTextField(in view: NSView) -> NSTextField? {
  personalDictionarySettingsViews(in: view)
    .compactMap { $0 as? NSTextField }
    .first { field in
      !(field is NSSearchField)
        && (field.placeholderString == "Search vocabulary"
          || field.accessibilityIdentifier() == "settings-search-target-vocabulary-search")
    }
}

@MainActor
private func personalDictionarySettingsAccessibilityFrame(
  _ identifier: String,
  in host: NSView
) throws -> CGRect {
  let element = try #require(
    personalDictionarySettingsAccessibilityElement(
      withAccessibilityIdentifier: identifier,
      in: host
    )
  )
  let frame = try #require(element.value(forKey: "accessibilityFrame") as? NSValue)
  return frame.rectValue
}

@MainActor
private func personalDictionarySettingsAccessibilityElement(
  withAccessibilityIdentifier identifier: String,
  in view: NSView
) -> NSObject? {
  var visited: Set<ObjectIdentifier> = []
  return personalDictionaryAccessibilityElement(
    withAccessibilityIdentifier: identifier,
    in: view,
    visited: &visited,
    depth: 0
  )
}

@MainActor
private func personalDictionaryAccessibilityElement(
  withAccessibilityIdentifier identifier: String,
  in value: Any,
  visited: inout Set<ObjectIdentifier>,
  depth: Int
) -> NSObject? {
  guard depth < 48, let element = value as? NSObject,
    visited.insert(ObjectIdentifier(element)).inserted
  else {
    return nil
  }

  let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
  let currentIdentifier = element.responds(to: identifierSelector)
    ? element.perform(identifierSelector)?.takeUnretainedValue() as? String
    : nil
  if currentIdentifier == identifier { return element }

  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let children = element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any]
    : nil
  for child in children ?? [] {
    if let match = personalDictionaryAccessibilityElement(
      withAccessibilityIdentifier: identifier,
      in: child,
      visited: &visited,
      depth: depth + 1
    ) {
      return match
    }
  }
  return nil
}

@MainActor
private func personalDictionaryAccessibilityString(
  _ element: NSObject,
  attribute: String
) -> String? {
  let selector = NSSelectorFromString(attribute)
  guard element.responds(to: selector) else { return nil }
  return element.perform(selector)?.takeUnretainedValue() as? String
}

@MainActor
private func personalDictionaryHostFrame(
  fromScreenFrame frame: CGRect,
  in host: NSView
) -> CGRect {
  guard let window = host.window else { return .zero }
  return host.convert(window.convertFromScreen(frame), from: nil)
}

@MainActor
private func clickPersonalDictionaryTrailingStarAtPaddedEdge(
  in host: NSView,
  rowFrame: CGRect,
  window: NSWindow
) throws {
  try sendPersonalDictionaryMouseClick(
    at: NSPoint(x: rowFrame.maxX - 13, y: rowFrame.midY),
    in: host,
    window: window
  )
}

@MainActor
private func clickPersonalDictionaryControlAtPaddedEdge(
  _ identifier: String,
  in host: NSView,
  window: NSWindow
) throws {
  let frame = personalDictionaryHostFrame(
    fromScreenFrame: try personalDictionarySettingsAccessibilityFrame(identifier, in: host),
    in: host
  )
  let point = NSPoint(
    x: frame.minX + 1,
    y: host.isFlipped ? frame.minY + 1 : frame.maxY - 1
  )
  try sendPersonalDictionaryMouseClick(at: point, in: host, window: window)
}

@MainActor
private func sendPersonalDictionaryMouseClick(
  at point: NSPoint,
  in host: NSView,
  window: NSWindow
) throws {
  let location = host.convert(point, to: nil)
  for (eventType, eventNumber, pressure) in [
    (NSEvent.EventType.leftMouseDown, 1, 1.0),
    (NSEvent.EventType.leftMouseUp, 2, 0.0),
  ] {
    let event = try #require(
      NSEvent.mouseEvent(
        with: eventType,
        location: location,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: Float(pressure)
      )
    )
    window.sendEvent(event)
  }
}

@MainActor
private func movePersonalDictionaryPointer(
  to point: NSPoint,
  in host: NSView,
  window: NSWindow
) throws {
  let pointInWindow = host.convert(point, to: nil)
  let pointOnScreen = window.convertToScreen(NSRect(origin: pointInWindow, size: .zero)).origin
  let pointer = NSEvent.mouseLocation
  window.setFrameOrigin(
    NSPoint(
      x: pointer.x - (pointOnScreen.x - window.frame.minX),
      y: pointer.y - (pointOnScreen.y - window.frame.minY)
    )
  )
  host.updateTrackingAreas()
  window.displayIfNeeded()
  let event = try #require(
    NSEvent.mouseEvent(
      with: .mouseMoved,
      location: window.convertFromScreen(NSRect(origin: pointer, size: .zero)).origin,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 0,
      pressure: 0
    )
  )
  window.sendEvent(event)
}

@MainActor
private func capturePersonalDictionaryHost(
  _ host: NSView,
  name: String
) throws -> NSBitmapImageRep {
  host.layoutSubtreeIfNeeded()
  host.displayIfNeeded()
  host.window?.displayIfNeeded()
  let scale = host.window?.backingScaleFactor ?? 1
  let image = try #require(
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: max(Int((host.bounds.width * scale).rounded(.up)), 1),
      pixelsHigh: max(Int((host.bounds.height * scale).rounded(.up)), 1),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  )
  host.cacheDisplay(in: host.bounds, to: image)

  if let directory = ProcessInfo.processInfo.environment[
    "FLECK_DICTIONARY_SETTINGS_CAPTURE_DIR"
  ] {
    let captureDirectory = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(
      at: captureDirectory,
      withIntermediateDirectories: true
    )
    let data = try #require(image.representation(using: .png, properties: [:]))
    try data.write(
      to: captureDirectory.appendingPathComponent("\(name).png"),
      options: .atomic
    )
  }

  return image
}

@MainActor
private func personalDictionaryAccentPixelCount(
  in image: NSBitmapImageRep,
  host: NSView,
  frame: CGRect,
  accent: NSColor,
  matchingTolerance: CGFloat = 0.45
) -> Int {
  guard
    let target = accent.usingColorSpace(.deviceRGB),
    host.bounds.width > 0,
    host.bounds.height > 0
  else {
    return 0
  }

  let scaleX = CGFloat(image.pixelsWide) / host.bounds.width
  let scaleY = CGFloat(image.pixelsHigh) / host.bounds.height
  let minX = max(Int(((frame.minX - host.bounds.minX) * scaleX).rounded(.down)), 0)
  let maxX = min(Int(((frame.maxX - host.bounds.minX) * scaleX).rounded(.up)), image.pixelsWide)
  let originY = host.isFlipped ? host.bounds.maxY - frame.maxY : frame.minY - host.bounds.minY
  let minY = max(Int((originY * scaleY).rounded(.down)), 0)
  let maxY = min(Int(((originY + frame.height) * scaleY).rounded(.up)), image.pixelsHigh)
  var matchingPixels = 0

  for y in minY..<maxY {
    for x in minX..<maxX {
      guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
      let distance = abs(color.redComponent - target.redComponent)
        + abs(color.greenComponent - target.greenComponent)
        + abs(color.blueComponent - target.blueComponent)
      if color.alphaComponent > 0.5 && distance < matchingTolerance {
        matchingPixels += 1
      }
    }
  }
  return matchingPixels
}

@MainActor
private func personalDictionaryPriorityStarColor(
  appearance: FleckThemeAppearance,
  windowAppearance: NSAppearance?
) -> NSColor {
  var color = NSColor.systemYellow.usingColorSpace(.deviceRGB) ?? .yellow
  windowAppearance?.performAsCurrentDrawingAppearance {
    let yellow = NSColor.systemYellow
    let visibleYellow = appearance == .light
      ? yellow.blended(withFraction: 0.35, of: .black) ?? yellow
      : yellow
    color = visibleYellow.usingColorSpace(.deviceRGB) ?? color
  }
  return color
}

@MainActor
private func personalDictionaryColorContrast(_ first: NSColor, _ second: NSColor) -> CGFloat {
  func luminance(_ source: NSColor) -> CGFloat {
    guard let color = source.usingColorSpace(.deviceRGB) else { return 0 }
    func linearized(_ component: CGFloat) -> CGFloat {
      component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearized(color.redComponent)
      + 0.7152 * linearized(color.greenComponent)
      + 0.0722 * linearized(color.blueComponent)
  }

  let firstLuminance = luminance(first)
  let secondLuminance = luminance(second)
  return (max(firstLuminance, secondLuminance) + 0.05)
    / (min(firstLuminance, secondLuminance) + 0.05)
}

@MainActor
private func personalDictionaryCommandFEvent(for window: NSWindow) -> NSEvent? {
  NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [.command],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: window.windowNumber,
    context: nil,
    characters: "f",
    charactersIgnoringModifiers: "f",
    isARepeat: false,
    keyCode: 3
  )
}

@MainActor
private func personalDictionaryEscapeEvent(for window: NSWindow) -> NSEvent? {
  NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: window.windowNumber,
    context: nil,
    characters: "\u{1b}",
    charactersIgnoringModifiers: "\u{1b}",
    isARepeat: false,
    keyCode: 53
  )
}

@MainActor
private func settlePersonalDictionarySettingsHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
