import AppKit
import CoreGraphics
import Foundation
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Suite(.serialized)
struct WorkspaceSearchHostingTests {

@Test @MainActor
func WorkspaceSearchPresentationSelectsPointerAndKeyboardMotionKinds() {
  #expect(
    WorkspaceSearchPresentationKind.resolve(
      activation: .pointer,
      reduceMotion: false
    ) == .inline
  )
  #expect(
    WorkspaceSearchPresentationKind.resolve(
      activation: .pointer,
      reduceMotion: true
    ) == .crossfade
  )
  #expect(
    WorkspaceSearchPresentationKind.resolve(
      activation: .keyboard,
      reduceMotion: false
    ) == .instant
  )
  #expect(
    WorkspaceSearchPresentationKind.resolve(
      activation: .keyboard,
      reduceMotion: true
    ) == .instant
  )
  #expect(WorkspaceSearchPresentationKind.inline.interactionSource == .pointer)
  #expect(WorkspaceSearchPresentationKind.crossfade.interactionSource == .pointer)
  #expect(WorkspaceSearchPresentationKind.instant.interactionSource == .keyboard)
  #expect(WorkspaceSearchPresentationKind.inline.usesAnimatedDismissal)
  #expect(WorkspaceSearchPresentationKind.crossfade.usesAnimatedDismissal)
  #expect(!WorkspaceSearchPresentationKind.instant.usesAnimatedDismissal)

  let controller = WorkspaceSearchController()
  controller.present(presentation: .inline)
  #expect(controller.presentationKind == .inline)
  controller.dismiss()
  controller.present(presentation: .crossfade)
  #expect(controller.presentationKind == .crossfade)
}

@Test
func WorkspaceSearchHostingUsesNoMatchedGeometryWiring() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let notesPanel = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let searchView = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/WorkspaceSearchView.swift"),
    encoding: .utf8
  )

  #expect(!notesPanel.contains("WorkspaceSearchTransition"))
  #expect(!searchView.contains("WorkspaceSearchTransition"))
  #expect(!searchView.contains("matchedGeometryEffect"))
}

@Test
func WorkspaceSearchFieldUsesNeutralKeyboardFocusStyling() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let searchView = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/WorkspaceSearchView.swift"),
    encoding: .utf8
  )

  #expect(searchView.contains(".textFieldStyle(.plain)"))
  #expect(searchView.contains(".focusEffectDisabled()"))
  #expect(searchView.contains(".focused($isQueryFocused)"))
  #expect(searchView.contains("isQueryFocused = true"))
  #expect(!searchView.contains(".textFieldStyle(.roundedBorder)"))
}

@Test @MainActor
func WorkspaceSearchSelectedResultUsesPalettePairedTextAcrossThemes() async throws {
  let application = NSApplication.shared
  let previousApplicationAppearance = application.appearance
  defer { application.appearance = previousApplicationAppearance }

  for palette in [FleckColorTheme.capy, .absolutely] {
    for (mode, appearance, windowAppearance) in [
      (AppTheme.light, FleckThemeAppearance.light, NSAppearance.Name.aqua),
      (AppTheme.dark, FleckThemeAppearance.dark, NSAppearance.Name.darkAqua),
    ] {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("workspace-search-selection-" + UUID().uuidString, isDirectory: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
      await state.waitUntilInitialLoad()
      state.updatePreferences {
        $0.colorTheme = palette
        $0.theme = mode
      }
      let note = Note(
        title: "Selected result",
        body: "Selected snippet with a matching result."
      )
      let results = [
        WorkspaceSearchResult(
          noteID: note.id,
          displayTitle: note.displayTitle,
          snippet: note.body,
          match: WorkspaceSearchMatch(field: .title, location: 0, length: 8),
          score: 1
        )
      ]
      let controller = WorkspaceSearchController(searchOperation: { _, _, _ in results })
      controller.present()
      controller.setQuery("Selected", in: [note])
      for _ in 0..<40 { await Task.yield() }
      #expect(controller.results.map(\.noteID) == [note.id])
      #expect(controller.highlightedNoteID == note.id)
      #expect(controller.isHighlighted(note.id))
      #expect(controller.resultsAreCurrent)

      let theme = state.themeSnapshot
      #expect(theme.appearance == appearance)
      let search = WorkspaceSearchView(
        controller: controller,
        notes: [note],
        accent: theme.color(.accent),
        presentationID: controller.presentationID,
        reduceMotion: false,
        currentNoteIDs: { [note.id] },
        onActivate: { _ in },
        onDismiss: {}
      )
      let host = NSHostingView(
        rootView: FleckThemeTestRoot(state: state) {
          search
            .frame(width: 420, height: 360)
            .background(theme.color(.window))
        }
      )
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      window.appearance = NSAppearance(named: windowAppearance)
      window.backgroundColor = mode == .light ? .black : .white
      window.contentView = host
      window.makeKeyAndOrderFront(nil)
      await settleWorkspaceSearchHost(host)
      try await Task.sleep(for: .milliseconds(20))
      await settleWorkspaceSearchHost(host)
      #expect(controller.resultsAreCurrent)
      let queryField = try #require(
        hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
          .first { $0.placeholderString == "Search notes" }
      )
      #expect(queryField.stringValue == "Selected")
      let queryFrame = queryField.convert(queryField.bounds, to: host)
      #expect(queryFrame.width > 100)
      #expect(queryFrame.height >= 16)
      #expect(queryFrame.maxX <= host.bounds.maxX - 10)
      #expect(window.makeFirstResponder(queryField))
      let queryFieldEditor = try #require(window.firstResponder as? NSTextView)
      #expect(queryField.currentEditor() === queryFieldEditor)
      let image = try workspaceSearchHostedCapture(in: host)
      if let captureDirectory = ProcessInfo.processInfo.environment["FLECK_SEARCH_TEST_CAPTURE_DIR"],
        palette == .capy
      {
        let suffix = mode == .light ? "light" : "dark"
        let directory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true
        )
        let captureURL = directory.appendingPathComponent("workspace-search-\(suffix).png")
        try #require(image.representation(using: .png, properties: [:])).write(to: captureURL)
      }

      #expect(
        FleckColorContrast.contrastRatio(
          theme.nsColor(.selectionText),
          against: theme.nsColor(.selectionFill)
        ) >= 4.5
      )
      #expect(
        workspaceSearchThemePixelCount(in: image, matching: theme.nsColor(.selectionFill)) > 40
      )
      #expect(
        workspaceSearchThemePixelCount(in: image, matching: theme.nsColor(.selectionText)) > 0
      )

      window.contentView = nil
      window.orderOut(nil)
    }
  }
}

@Test @MainActor
func WorkspaceSearchHostingUsesACompactTrailingSurfaceAt640Points() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-compact-640-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  searchController.present(presentation: .inline)
  await settleWorkspaceSearchHost(host)
  let queryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  let queryFrame = queryField.convert(queryField.bounds, to: host)

  #expect(queryFrame.width <= 320)
  #expect(queryFrame.minX >= host.bounds.maxX - 370)
  #expect(queryFrame.maxX <= host.bounds.maxX - 10)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingKeepsCompactSurfaceInsideMinimumWidth() async throws {
  _ = try await runWorkspaceSearchCompactCloseFixture()
}

@Test
func WorkspaceSearchDismissalsUseNotesPanelAnimationContract() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let notesPanel = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let searchView = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/WorkspaceSearchView.swift"),
    encoding: .utf8
  )

  #expect(notesPanel.contains("onDismiss: dismissWorkspaceSearch"))
  #expect(notesPanel.contains("searchController.presentationKind.usesAnimatedDismissal"))
  #expect(notesPanel.contains("motion.presentationAnimation(for: presentation.interactionSource)"))
  #expect(!notesPanel.contains("value: searchController.isPresented"))
  #expect(searchView.contains("let onDismiss: () -> Void"))
  #expect(searchView.contains("onDismiss: onDismiss"))
  #expect(searchView.contains("onDismiss()"))
}

@Test @MainActor
func WorkspaceSearchHostingPointerDismissRestoresEditorFocus() async throws {
  _ = try await runWorkspaceSearchPointerOpenFixture(includeDismissalChecks: true)
}

@Test("Workspace search paired input delivery experiment [anchor: paired-search-delivery]")
@MainActor
func WorkspaceSearchHostingPairedInputDeliveryExperimentAnchor() async throws {
  let originalPointer = CGEvent(source: nil)?.location
  defer {
    if let originalPointer {
      _ = CGWarpMouseCursorPosition(originalPointer)
    }
  }

  let cgEventControl = CGPreflightPostEventAccess()
    ? "available-not-used"
    : "unavailable-access"
  print("WORKSPACE_SEARCH_DELIVERY_EXPERIMENT cgEventControl=\(cgEventControl)")

  var ordinal = 0
  for round in 0..<4 {
    for scenario in WorkspaceSearchDeliveryScenario.allCases {
      for pointer in WorkspaceSearchDeliveryPointerCondition.allCases {
        let paths = round.isMultiple(of: 2)
          ? WorkspaceSearchDeliveryPath.allCases
          : Array(WorkspaceSearchDeliveryPath.allCases.reversed())
        for path in paths {
          ordinal += 1
          let trial = WorkspaceSearchDeliveryTrial(
            scenario: scenario,
            path: path,
            pointer: pointer,
            round: round + 1,
            ordinal: ordinal
          )
          WorkspaceSearchDeliveryExperiment.current = trial
          var result: WorkspaceSearchFixtureResult?
          do {
            switch scenario {
            case .compactClose:
              result = try await runWorkspaceSearchCompactCloseFixture()
            case .pointerOpen:
              result = try await runWorkspaceSearchPointerOpenFixture(
                includeDismissalChecks: false
              )
            }
          } catch {
            trial.setOutcome("fixture-error")
          }
          trial.finish()
          WorkspaceSearchDeliveryExperiment.current = nil

          let presentation = result?.presentationKind.experimentLabel ?? "none"
          let behavior: String
          switch scenario {
          case .compactClose:
            behavior = "dismissed=\(result?.dismissed ?? false)"
          case .pointerOpen:
            behavior = "presented=\(result?.isPresented ?? false) presentation=\(presentation)"
          }
          let witness = trial.pointerWitness?.summary ?? "unavailable"
          let events = trial.eventPairSummary ?? "unavailable"
          let routes = trial.routes.isEmpty ? "none" : trial.routes.joined(separator: ",")
          let callbacks = trial.callbacks.isEmpty ? "none" : trial.callbacks.joined(separator: ",")
          let outcome = trial.outcome ?? behavior
          print(
            "WORKSPACE_SEARCH_DELIVERY_EXPERIMENT round=\(trial.round) "
              + "scenario=\(scenario.rawValue) path=\(path.rawValue) "
              + "pointer=\(pointer.rawValue) witness={\(witness)} "
              + "events={\(events)} routes={\(routes)} "
              + "callbacks={\(callbacks)} completionWait=\(trial.completionWaitCompleted) "
              + "\(behavior) outcome=\(outcome)"
          )

          #expect(result != nil, "Search delivery fixture did not complete")
          #expect(trial.pointerWitness?.matches == true, "Global pointer witness did not match the requested condition")
          #expect(trial.completionWaitCompleted, "Timed out waiting for the fixture's required delivery and behavior")
          #expect(trial.receivedOwnedMouseUp, "Timed out waiting for the owned mouse-up delivery witness")
          switch scenario {
          case .compactClose:
            #expect(result?.dismissed == true, "Compact search close did not dismiss search")
          case .pointerOpen:
            #expect(
              result?.isPresented == true && result?.presentationKind == .inline,
              "Pointer-open fixture did not present inline"
            )
          }
        }
      }
    }
  }
}

@Test @MainActor
func WorkspaceSearchHostingImmediateReopenSurvivesOldDisappearance() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-reopen-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  searchController.present(presentation: .inline)
  let firstPresentationID = searchController.presentationID
  await settleWorkspaceSearchHost(host)
  searchController.dismiss()
  searchController.present(presentation: .instant)
  let reopenedPresentationID = searchController.presentationID
  #expect(reopenedPresentationID != firstPresentationID)
  searchController.dismiss(ifPresentationID: firstPresentationID)
  #expect(searchController.isPresented)
  searchController.setQuery("still open", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  try await Task.sleep(for: .milliseconds(400))
  await settleWorkspaceSearchHost(host)

  #expect(searchController.isPresented)
  #expect(searchController.presentationKind == .instant)
  #expect(searchController.query == "still open")

  searchController.dismiss()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingImmediateReopenKeepsQueryFocusAfterOldRestoreRetry()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-focus-reopen-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let note = Note(title: "Focus title", body: "Keep this body")
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  let editor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == note.body }
  )
  #expect(window.makeFirstResponder(editor))

  searchController.present(for: note.id)
  await settleWorkspaceSearchHost(host)
  let firstQueryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  #expect(window.makeFirstResponder(firstQueryField))

  searchController.dismiss()
  searchController.present(for: note.id)
  var reopenedField: NSTextField?
  for _ in 0..<8 {
    host.layoutSubtreeIfNeeded()
    reopenedField = hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
    if reopenedField != nil { break }
    await Task.yield()
  }
  let reopenedQueryField = try #require(reopenedField)
  #expect(window.makeFirstResponder(reopenedQueryField))
  let reopenedQueryEditor = try #require(
    reopenedQueryField.currentEditor() as? NSTextView
  )
  #expect(window.firstResponder === reopenedQueryEditor)

  try await Task.sleep(for: .milliseconds(400))
  await settleWorkspaceSearchHost(host)

  #expect(searchController.isPresented)
  #expect(window.firstResponder === reopenedQueryEditor)
  #expect(reopenedQueryField.currentEditor() === reopenedQueryEditor)

  searchController.dismiss()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingPreservesSearchResultsAndNoteStateAcrossAccentUpdates()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-highlight-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let accentHex = "#E64A19"
  state.updatePreferences { $0.accentHex = accentHex }
  state.updateSelected(title: "Café cafe CAFE — untouched", body: "No body match")
  let titleNoteID = try #require(state.selectedNote?.id)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("cafe", in: state.workspace.notes)
  let searchDeadline = ContinuousClock.now + .seconds(5)
  while
    (!searchController.resultsAreCurrent
      || searchController.results.map(\.noteID) != [titleNoteID]),
    ContinuousClock.now < searchDeadline
  {
    await Task.yield()
  }
  #expect(
    searchController.resultsAreCurrent
      && searchController.results.map(\.noteID) == [titleNoteID],
    "Timed out waiting for the current workspace search result"
  )

  #expect(searchController.results.map(\.noteID) == [titleNoteID])
  let initialResult = try #require(searchController.results.first)
  #expect(initialResult.displayTitle == "Café cafe CAFE — untouched")
  #expect(initialResult.snippet == initialResult.displayTitle)

  state.updatePreferences { $0.accentHex = "#007AFF" }
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.first?.displayTitle == initialResult.displayTitle)
  #expect(searchController.results.first?.snippet == initialResult.snippet)
  #expect(state.selectedNote?.title == "Café cafe CAFE — untouched")
  #expect(state.selectedNote?.body == "No body match")

  searchController.setQuery("   \n", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.isEmpty)

  searchController.dismiss()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingLinkPickerIsIndependentAndBlocksTheOtherOverlay() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-link-picker-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let sourceID = try #require(state.workspace.selectedNoteID)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let picker = NoteLinkPickerController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController,
      noteLinkPickerController: picker
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  let sourceRevision = try #require(state.workspace.notes.first { $0.id == sourceID }?.revision)
  picker.present(
    sourceNoteID: sourceID,
    replacementRange: NSRange(location: 0, length: 0),
    sourceRevision: sourceRevision
  )
  await settleWorkspaceSearchHost(host)
  #expect(picker.isPresented)
  searchController.present(for: sourceID)
  await settleWorkspaceSearchHost(host)
  #expect(picker.isPresented)
  #expect(!searchController.isPresented)

  picker.dismiss()
  await settleWorkspaceSearchHost(host)
  searchController.present(for: sourceID)
  await settleWorkspaceSearchHost(host)
  #expect(searchController.isPresented)
  picker.present(
    sourceNoteID: sourceID,
    replacementRange: NSRange(location: 0, length: 0),
    sourceRevision: sourceRevision
  )
  await settleWorkspaceSearchHost(host)
  #expect(searchController.isPresented)
  #expect(!picker.isPresented)

  searchController.dismiss()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingRestoresTheRealEditorStateAfterEscape() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()

  let text = "Keep this rich text"
  let selectedRange = NSRange(location: 5, length: 4)
  let font = try #require(NSFont(name: "Helvetica-Bold", size: 18))
  let attributed = NSMutableAttributedString(string: text)
  attributed.addAttributes(
    [.font: font, .foregroundColor: NSColor.systemRed],
    range: NSRange(location: 0, length: text.utf16.count)
  )
  let rtfAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
    .documentType: NSAttributedString.DocumentType.rtf
  ]
  let rtf = try attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: rtfAttributes
  )
  state.updateSelected(body: text, richTextRTF: rtf)

  let commands = EditorCommands()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      editorCommands: commands,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  let textView = try #require(hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self))
  #expect(window.makeFirstResponder(textView))
  #expect(window.firstResponder === textView)
  textView.setSelectedRange(selectedRange)
  textView.typingAttributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
  commands.refreshFormattingState()
  commands.applyBackgroundColor(.systemYellow)
  #expect(commands.beginFocusedDictation())

  let expectedRTF = try #require(
    try textView.textStorage?.data(
      from: NSRange(location: 0, length: textView.textStorage?.length ?? 0),
      documentAttributes: rtfAttributes
    )
  )
  let expectedTypingAttributes = textView.typingAttributes
  let expectedSelectedNoteID = state.workspace.selectedNoteID
  let expectedUndoAvailability = textView.undoManager?.canUndo
  let expectedActiveState = commands.isFocusedDictationActive
  #expect(expectedUndoAvailability == true)
  #expect(expectedActiveState)

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("rich", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  searchController.moveHighlight(.down)
  #expect(searchController.handleKey(.escape))
  await settleWorkspaceSearchHost(host)

  #expect(!searchController.isPresented)
  #expect(commands.textView === textView)
  #expect(textView.string == text)
  #expect(textView.selectedRange() == selectedRange)
  #expect(
    NSDictionary(dictionary: textView.typingAttributes)
      .isEqual(to: expectedTypingAttributes)
  )
  let actualRTF = try #require(
    try textView.textStorage?.data(
      from: NSRange(location: 0, length: textView.textStorage?.length ?? 0),
      documentAttributes: rtfAttributes
    )
  )
  #expect(actualRTF == expectedRTF)
  #expect(textView.undoManager?.canUndo == expectedUndoAvailability)
  #expect(commands.isFocusedDictationActive == expectedActiveState)
  #expect(state.workspace.selectedNoteID == expectedSelectedNoteID)
  #expect(window.firstResponder === textView)

  commands.cancelFocusedDictation()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingRestoresTheTargetEditorAfterCrossNoteActivation()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-cross-note-editor-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  state.updateSelected(title: "Original title", body: "Original body")
  let originalID = try #require(state.selectedNote?.id)
  let target = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!,
    title: "Target title",
    body: "Target body"
  )
  state.importNote(target)
  state.select(originalID)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  let originalEditor = try #require(
    hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self)
  )
  #expect(originalEditor.string == "Original body")
  #expect(window.makeFirstResponder(originalEditor))
  searchController.present(for: originalID)
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Target", in: state.workspace.notes)
  try #require(
    await waitForWorkspaceSearchHostState(host) {
      searchController.resultsAreCurrent
        && searchController.results.map(\.noteID) == [target.id]
    },
    "Timed out waiting for the target search result to publish"
  )
  #expect(searchController.results.map(\.noteID) == [target.id])

  var activations: [UUID] = []
  #expect(
    searchController.activateResult(
      target.id,
      currentNoteIDs: Set(state.workspace.notes.map(\.id)),
      activate: { noteID in
        activations.append(noteID)
        state.select(noteID)
      }
    )
  )
  try #require(
    await waitForWorkspaceSearchHostState(host) {
      guard state.workspace.selectedNoteID == target.id,
        !searchController.isPresented,
        let targetEditor = hostedWorkspaceSearchDescendants(
          in: host,
          as: ListAwareTextView.self
        ).first(where: { $0.string == target.body })
      else {
        return false
      }
      return window.firstResponder === targetEditor
    },
    "Timed out waiting for the activated note's editor to regain focus"
  )

  #expect(activations == [target.id])
  #expect(state.workspace.selectedNoteID == target.id)
  #expect(!searchController.isPresented)
  let targetEditor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == target.body }
  )
  #expect(targetEditor !== originalEditor)
  #expect(window.firstResponder === targetEditor)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingRestoresTheTargetTitleFieldAfterCrossNoteActivation()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-cross-note-title-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  state.updateSelected(title: "Original title", body: "Original body")
  let originalID = try #require(state.selectedNote?.id)
  let target = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")!,
    title: "Goal",
    body: "Target body"
  )
  state.importNote(target)
  state.select(originalID)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  let originalTitleField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.stringValue == "Original title" && $0.frame.width > 200 }
  )
  #expect(window.makeFirstResponder(originalTitleField))
  let originalFieldEditor = try #require(window.firstResponder as? NSTextView)
  let originalSelection = NSRange(location: 2, length: 5)
  originalFieldEditor.setSelectedRange(originalSelection)
  #expect(originalTitleField.currentEditor() === originalFieldEditor)

  searchController.present(for: originalID)
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Goal", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  try #require(
    await waitForWorkspaceSearchHostState(host) {
      searchController.resultsAreCurrent
        && searchController.results.map(\.noteID) == [target.id]
    },
    "Timed out waiting for the target search result to publish"
  )
  #expect(searchController.results.map(\.noteID) == [target.id])

  var activations: [UUID] = []
  #expect(
    searchController.activateResult(
      target.id,
      currentNoteIDs: Set(state.workspace.notes.map(\.id)),
      activate: { noteID in
        activations.append(noteID)
        state.select(noteID)
      }
    )
  )
  await settleWorkspaceSearchHost(host)

  #expect(activations == [target.id])
  #expect(state.workspace.selectedNoteID == target.id)
  #expect(!searchController.isPresented)
  let targetTitleField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.stringValue == target.title && $0.frame.width > 200 }
  )
  let targetFieldEditor = try #require(targetTitleField.currentEditor() as? NSTextView)
  #expect(window.firstResponder === targetFieldEditor)
  #expect(targetFieldEditor.selectedRange() != originalSelection)
  #expect(NSMaxRange(targetFieldEditor.selectedRange()) <= target.title.utf16.count)
  #expect(targetTitleField.stringValue == target.title)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingRestoresTitleFieldEditorAndIsolatesUnderlyingControls()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-title-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  state.updateSelected(title: "Editable title")

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  let editor = try #require(hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self))
  let titleField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.stringValue == "Editable title" && $0.frame.width > 200 }
  )
  #expect(window.makeFirstResponder(titleField))
  let originalFieldEditor = try #require(window.firstResponder as? NSTextView)
  let selectedRange = NSRange(location: 2, length: 6)
  originalFieldEditor.setSelectedRange(selectedRange)
  #expect(titleField.currentEditor() === originalFieldEditor)

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Editable", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)

  let queryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  #expect(hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self) === editor)
  #expect(!titleField.isEnabled)
  #expect(!titleField.isAccessibilityElement())
  #expect(window.makeFirstResponder(queryField))
  for _ in 0..<12 {
    window.selectNextKeyView(nil)
    #expect(window.firstResponder !== titleField)
    #expect(window.firstResponder !== editor)
    #expect((window.firstResponder as? NSTextView)?.delegate !== titleField)
  }
  #expect(searchController.isPresented)

  searchController.dismiss()
  await settleWorkspaceSearchHost(host)
  let restoredFieldEditor = try #require(window.firstResponder as? NSTextView)
  #expect(restoredFieldEditor === originalFieldEditor)
  #expect(titleField.currentEditor() === originalFieldEditor)
  #expect(restoredFieldEditor.selectedRange() == selectedRange)
  #expect(titleField.stringValue == "Editable title")
  #expect(window.firstResponder !== editor)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingReturnSelectsOnlyTheCurrentUUID() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-return-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let originalID = try #require(state.selectedNote?.id)
  let target = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
    title: "Target note",
    body: "A body-only match"
  )
  state.importNote(target)
  state.select(originalID)
  #expect(state.workspace.notes.contains(where: { $0.id == target.id }))

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Target", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  try #require(
    await waitForWorkspaceSearchHostState(host) {
      searchController.resultsAreCurrent
        && searchController.results.map(\.noteID) == [target.id]
    },
    "Timed out waiting for the target search result to publish"
  )
  #expect(searchController.results.map(\.noteID) == [target.id])

  var activations: [UUID] = []
  #expect(
    searchController.handleKey(
      .return,
      currentNoteIDs: Set(state.workspace.notes.map(\.id)),
      activate: { noteID in
        activations.append(noteID)
        state.select(noteID)
      }
    )
  )
  #expect(activations == [target.id])
  #expect(state.workspace.selectedNoteID == target.id)
  #expect(!searchController.isPresented)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingKeepsResultsScrollableInProductionOverlay()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-palette-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let originalID = try #require(state.selectedNote?.id)
  for index in 0..<80 {
    state.importNote(
      Note(
        title: "Result " + String(index),
        body: "Scrollable result body " + String(index)
      )
    )
  }
  state.select(originalID)
  #expect(state.workspace.notes.count == 81)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController(searchOperation: { _, notes, limit in
    notes.dropFirst().prefix(limit).map { note in
      WorkspaceSearchResult(
        noteID: note.id,
        displayTitle: note.displayTitle,
        snippet: note.body,
        match: WorkspaceSearchMatch(field: .title, location: 0, length: 1),
        score: 1
      )
    }
  })
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)
  let editor = try #require(hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self))
  #expect(window.makeFirstResponder(editor))
  #expect(window.firstResponder === editor)
  let initialScrollViews = hostedWorkspaceSearchScrollViews(in: host)
  let initialScrollViewIDs = Set(initialScrollViews.map { ObjectIdentifier($0) })

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Result", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  try await Task.sleep(for: .milliseconds(20))
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.count == 50)

  let scrollViews = hostedWorkspaceSearchScrollViews(in: host)
  #expect(scrollViews.count == initialScrollViews.count + 1)
  let newPaletteScrollViews = scrollViews.filter {
    !initialScrollViewIDs.contains(ObjectIdentifier($0))
  }
  #expect(newPaletteScrollViews.count == 1)
  let resultScrollView = try #require(newPaletteScrollViews.first)

  let firstBounds = resultScrollView.contentView.bounds
  for _ in 0..<12 {
    searchController.moveHighlight(.down)
    await settleWorkspaceSearchHost(host)
  }
  await settleWorkspaceSearchHost(host)
  #expect(searchController.highlightedNoteID == searchController.results[12].noteID)
  #expect(resultScrollView.contentView.bounds.origin.y > firstBounds.origin.y)

  searchController.dismiss()
  await settleWorkspaceSearchHost(host)
  #expect(!searchController.isPresented)
  #expect(window.firstResponder === editor)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingActivatesNamedFolderResultThroughProductionScope()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-folder-activation-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let work = try Folder(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!,
    name: "Work"
  )
  let unfiled = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000b2")!,
    title: "Unfiled note",
    body: "Unfiled body"
  )
  var target = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000b3")!,
    title: "Named folder target",
    body: "Folder body"
  )
  target.folderID = work.id

  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(
    notes: [unfiled, target],
    selectedNoteID: unfiled.id,
    folders: [work]
  )

  let commands = EditorCommands()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      editorCommands: commands,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  let unfiledEditor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == unfiled.body }
  )
  #expect(window.makeFirstResponder(unfiledEditor))
  commands.textView?.setSelectedRange(NSRange(location: 0, length: 0))
  commands.refreshFormattingState()

  searchController.present(for: unfiled.id)
  await settleWorkspaceSearchHost(host)
  searchController.setQuery(target.title, in: state.workspace.notes)
  try #require(
    await waitForWorkspaceSearchHostState(host) {
      searchController.resultsAreCurrent
        && searchController.results.map(\.noteID) == [target.id]
    },
    "Timed out waiting for the named-folder search result to publish"
  )
  #expect(searchController.results.map(\.noteID) == [target.id])
  let queryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  #expect(window.makeFirstResponder(queryField))
  let returnEvent = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "\r",
      charactersIgnoringModifiers: "\r",
      isARepeat: false,
      keyCode: 36
    )
  )
  window.sendEvent(returnEvent)
  let activated = try await waitForWorkspaceSearchHostState(host) {
    guard state.workspace.selectedNoteID == target.id,
      !searchController.isPresented,
      let targetEditor = hostedWorkspaceSearchDescendants(
        in: host,
        as: ListAwareTextView.self
      ).first(where: { $0.string == target.body })
    else {
      return false
    }
    return commands.textView === targetEditor
      && window.firstResponder === targetEditor
  }
  if !activated {
    let targetEditor = hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == target.body }
    print(
      "FLECK_SEARCH_RETURN_DIAGNOSTIC"
        + " selected=\(state.workspace.selectedNoteID == target.id)"
        + " presented=\(searchController.isPresented)"
        + " targetEditor=\(targetEditor != nil)"
        + " commandsTarget=\(targetEditor != nil && commands.textView === targetEditor)"
        + " responderTarget=\(targetEditor != nil && window.firstResponder === targetEditor)"
        + " queryOwnsEditor=\(queryField.currentEditor() === window.firstResponder)"
        + " active=\(NSApp.isActive) key=\(window.isKeyWindow)"
        + " responder=\(String(describing: window.firstResponder.map { type(of: $0) }))"
    )
  }
  try #require(
    activated,
    "Timed out waiting for Return activation to restore the target editor"
  )

  #expect(state.workspace.selectedNoteID == target.id)
  #expect(state.folderID(for: target.id) == work.id)
  #expect(!searchController.isPresented)
  let targetEditor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == target.body }
  )
  #expect(commands.textView === targetEditor)
  #expect(window.firstResponder === targetEditor)

  let newNoteEvent = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "t",
      charactersIgnoringModifiers: "t",
      isARepeat: false,
      keyCode: 17
    )
  )
  NSApp.sendEvent(newNoteEvent)
  await settleWorkspaceSearchHost(host)
  let createdNoteID = try #require(state.workspace.selectedNoteID)
  let createdNote = try #require(
    state.workspace.notes.first { $0.id == createdNoteID }
  )
  #expect(createdNote.id != target.id)
  #expect(createdNote.folderID == work.id)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingBlocksEveryShortcutWhilePresented() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-shortcuts-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let work = try Folder(id: UUID(), name: "Work")
  let first = Note(title: "First", body: "First body")
  let second = Note(title: "Second", body: "Second body")
  let hidden = Note(title: "Hidden", body: "Hidden body", folderID: work.id)
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(
    notes: [first, second, hidden],
    selectedNoteID: first.id,
    folders: [work]
  )
  state.updatePreferences {
    $0.shortcuts = [
      Shortcut(action: .togglePanel, key: "p", modifiers: ["command", "shift"]),
      Shortcut(action: .newNote, key: "n", modifiers: ["command"]),
      Shortcut(action: .closeNote, key: "w", modifiers: ["command"]),
      Shortcut(action: .nextNote, key: "tab", modifiers: ["control"]),
      Shortcut(action: .previousNote, key: "tab", modifiers: ["control", "shift"]),
    ]
  }

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  let expectedWorkspace = state.workspace
  let expectedSelectedNoteID = state.workspace.selectedNoteID
  let expectedScope = state.folderScopeForSelectedNote()
  let expectedGeneration = state.persistenceGeneration
  searchController.present(for: first.id)
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("First", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  let queryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  #expect(window.makeFirstResponder(queryField))
  let queryFieldEditor = try #require(window.firstResponder as? NSTextView)
  #expect(queryField.currentEditor() === queryFieldEditor)

  let shortcuts: [(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags)] = [
    (45, "n", [.command]),
    (13, "w", [.command]),
    (48, "\t", [.control]),
    (48, "\t", [.control, .shift]),
    (35, "p", [.command, .shift]),
  ]
  for shortcut in shortcuts {
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: shortcut.modifiers,
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: shortcut.characters,
        charactersIgnoringModifiers: shortcut.characters,
        isARepeat: false,
        keyCode: shortcut.keyCode
      )
    )
    NSApp.sendEvent(event)
    await settleWorkspaceSearchHost(host)
  }

  #expect(searchController.isPresented)
  #expect(searchController.query == "First")
  #expect(window.firstResponder === queryFieldEditor)
  #expect(queryField.currentEditor() === queryFieldEditor)
  #expect(state.workspace == expectedWorkspace)
  #expect(state.workspace.selectedNoteID == expectedSelectedNoteID)
  #expect(state.folderScopeForSelectedNote() == expectedScope)
  #expect(state.persistenceGeneration == expectedGeneration)
  #expect(window.isVisible)
  #expect(
    !hostedWorkspaceSearchDescendants(in: host, as: NSButton.self)
      .contains { $0.title == "Confirm" }
  )

  searchController.dismiss()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingDismissPreservesFocusScopeWorkspaceAndSaveGeneration()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-dismiss-state-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let work = try Folder(id: UUID(), name: "Work")
  let note = Note(title: "Focus note", body: "Keep this body", folderID: work.id)
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [work])

  let commands = EditorCommands()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      editorCommands: commands,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  var originalError: (any Error)? = nil
  do {
    await settleWorkspaceSearchHost(host)

    let editor = try #require(
      hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
        .first { $0.string == note.body }
    )
    #expect(window.makeFirstResponder(editor))
    let bodySelection = NSRange(location: 2, length: 4)
    editor.setSelectedRange(bodySelection)
    editor.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
    commands.refreshFormattingState()
    let expectedTypingAttributes = NSDictionary(dictionary: editor.typingAttributes)
    let expectedWorkspace = state.workspace
    let expectedGeneration = state.persistenceGeneration
    let expectedScope = state.folderScopeForSelectedNote()

    searchController.present(for: note.id)
    await settleWorkspaceSearchHost(host)
    searchController.dismiss()
    await settleWorkspaceSearchHost(host)

    #expect(state.workspace == expectedWorkspace)
    #expect(state.persistenceGeneration == expectedGeneration)
    #expect(state.folderScopeForSelectedNote() == expectedScope)
    #expect(state.workspace.selectedNoteID == note.id)
    #expect(commands.textView === editor)
    #expect(editor.selectedRange() == bodySelection)
    #expect(NSDictionary(dictionary: editor.typingAttributes).isEqual(to: expectedTypingAttributes))
    #expect(window.firstResponder === editor)

    let titleField = try #require(
      hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
        .first { $0.stringValue == note.title && $0.frame.width > 200 }
    )
    #expect(window.makeFirstResponder(titleField))
    let titleEditor = try #require(window.firstResponder as? NSTextView)
    let titleSelection = NSRange(location: 1, length: 3)
    titleEditor.setSelectedRange(titleSelection)
    let expectedTitle = titleField.stringValue

    searchController.present(for: note.id)
    await settleWorkspaceSearchHost(host)
    searchController.dismiss()
    await settleWorkspaceSearchHost(host)

    #expect(state.workspace == expectedWorkspace)
    #expect(state.persistenceGeneration == expectedGeneration)
    #expect(state.folderScopeForSelectedNote() == expectedScope)
    #expect(titleField.stringValue == expectedTitle)
    let restoredTitleEditor = try #require(window.firstResponder as? NSTextView)
    #expect(restoredTitleEditor === titleEditor)
    #expect(restoredTitleEditor.selectedRange() == titleSelection)

  } catch {
    originalError = error
  }
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
  if let originalError {
    throw originalError
  }
}

}

@MainActor
private func runWorkspaceSearchCompactCloseFixture() async throws
  -> WorkspaceSearchFixtureResult
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-compact-380-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let trial = WorkspaceSearchDeliveryExperiment.current
#if DEBUG
  if let trial {
    searchController.searchDeliveryExperimentObserver = {
      trial.recordCallback($0)
    }
  }
#endif
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
    )
    .environmentObject(state)
  )
  let window = workspaceSearchFixtureWindow(
    contentRect: NSRect(x: 137, y: 211, width: 380, height: 430)
  )

  do {
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    await settleWorkspaceSearchHost(host)

    searchController.present(presentation: .inline)
    await settleWorkspaceSearchHost(host)
    let queryField = try #require(
      hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
        .first { $0.placeholderString == "Search notes" }
    )
    let queryFrame = queryField.convert(queryField.bounds, to: host)

    #expect(queryFrame.width <= 320)
    #expect(queryFrame.minX >= 10)
    #expect(queryFrame.maxX <= host.bounds.maxX - 10)

    let hStackSpacing: CGFloat = 8
    let closeGlyphWidth: CGFloat = 15
    let dismissPoint = NSPoint(
      x: queryFrame.maxX + hStackSpacing + closeGlyphWidth / 2,
      y: queryFrame.midY
    )
    #expect(dismissPoint.x >= host.bounds.maxX - 40)
    #expect(dismissPoint.x <= host.bounds.maxX - 10)
    try clickWorkspaceSearchControl(host.convert(dismissPoint, to: nil), in: window)
    let dismissed: Bool
    if let trial {
      let completionWait = try await waitForWorkspaceSearchHostState(host) {
        trial.inputDeliveryComplete && !searchController.isPresented
      }
      trial.recordCompletionWait(completionWait)
      dismissed = !searchController.isPresented
    } else {
      dismissed = try await waitForWorkspaceSearchHostState(host) {
        !searchController.isPresented
      }
    }
    if !dismissed {
      printCompactSearchDismissDiagnostic(
        host: host,
        window: window,
        queryFrame: queryFrame,
        dismissPoint: dismissPoint
      )
    }
    #expect(dismissed, "Timed out waiting for the compact search close control to dismiss search")

    let result = WorkspaceSearchFixtureResult(
      isPresented: searchController.isPresented,
      presentationKind: searchController.presentationKind,
      dismissed: dismissed
    )
    trial?.finish()
    searchController.dismiss()
    window.contentView = nil
    window.orderOut(nil)
    await runtime.shutdown()
    return result
  } catch {
    trial?.finish()
    searchController.dismiss()
    window.contentView = nil
    window.orderOut(nil)
    await runtime.shutdown()
    throw error
  }
}

@MainActor
private func runWorkspaceSearchPointerOpenFixture(
  includeDismissalChecks: Bool
) async throws -> WorkspaceSearchFixtureResult {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-pointer-focus-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let note = Note(title: "Focus title", body: "Keep this body")
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id)

  let commands = EditorCommands()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let trial = WorkspaceSearchDeliveryExperiment.current
#if DEBUG
  if let trial {
    searchController.searchDeliveryExperimentObserver = {
      trial.recordCallback($0)
    }
  }
#endif
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      editorCommands: commands,
      searchController: searchController
    )
    .environmentObject(state)
    .environment(\._accessibilityReduceMotion, false)
  )
  let window = workspaceSearchFixtureWindow(
    contentRect: NSRect(x: 137, y: 211, width: 640, height: 430)
  )

  do {
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    await settleWorkspaceSearchHost(host)

    let editor = try #require(
      hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
        .first { $0.string == note.body }
    )
    #expect(window.makeFirstResponder(editor))
    let bodySelection = NSRange(location: 2, length: 4)
    editor.setSelectedRange(bodySelection)

    let searchButton = try #require(workspaceSearchTrigger(in: host))
    try clickWorkspaceSearchControl(searchButton, in: window)
    if let trial {
      let completionWait = try await waitForWorkspaceSearchHostState(host) {
        trial.inputDeliveryComplete && searchController.isPresented
      }
      trial.recordCompletionWait(completionWait)
    } else {
      await settleWorkspaceSearchHost(host)
    }

    let isPresented = searchController.isPresented
    let presentationKind = searchController.presentationKind
    #expect(searchController.isPresented)
    #expect(searchController.presentationKind == .inline)
    if includeDismissalChecks && searchController.isPresented
      && searchController.presentationKind == .inline
    {
      sendWorkspaceSearchEscape(to: window)
      await settleWorkspaceSearchHost(host)

      #expect(!searchController.isPresented)
      #expect(commands.textView === editor)
      #expect(editor.selectedRange() == bodySelection)
      #expect(window.firstResponder === editor)
    }

    let result = WorkspaceSearchFixtureResult(
      isPresented: isPresented,
      presentationKind: presentationKind,
      dismissed: includeDismissalChecks ? !searchController.isPresented : nil
    )
    trial?.finish()
    searchController.dismiss()
    window.contentView = nil
    window.orderOut(nil)
    await runtime.shutdown()
    return result
  } catch {
    trial?.finish()
    searchController.dismiss()
    window.contentView = nil
    window.orderOut(nil)
    await runtime.shutdown()
    throw error
  }
}

@MainActor
private func workspaceSearchFixtureWindow(contentRect: NSRect) -> NSWindow {
  if WorkspaceSearchDeliveryExperiment.current != nil {
    return WorkspaceSearchDeliveryProbeWindow(
      contentRect: contentRect,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
  }
  return NSWindow(
    contentRect: contentRect,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
}

private struct WorkspaceSearchFixtureResult {
  let isPresented: Bool
  let presentationKind: WorkspaceSearchPresentationKind
  let dismissed: Bool?
}

private enum WorkspaceSearchDeliveryScenario: String, CaseIterable {
  case compactClose = "compact-close"
  case pointerOpen = "pointer-open"
}

private enum WorkspaceSearchDeliveryPath: String, CaseIterable {
  case splitWindowDown = "A-split-up-window-down"
  case queuedPair = "B-queued-down-up"
}

private enum WorkspaceSearchDeliveryPointerCondition: String, CaseIterable {
  case atTarget = "pointer-at-target"
  case outsideWindow = "pointer-outside-window"
}

private extension WorkspaceSearchPresentationKind {
  var experimentLabel: String {
    switch self {
    case .inline: "inline"
    case .crossfade: "crossfade"
    case .instant: "instant"
    }
  }
}

@MainActor
private enum WorkspaceSearchDeliveryExperiment {
  static var current: WorkspaceSearchDeliveryTrial?
}

@MainActor
private final class WorkspaceSearchDeliveryTrial {
  let scenario: WorkspaceSearchDeliveryScenario
  let path: WorkspaceSearchDeliveryPath
  let pointer: WorkspaceSearchDeliveryPointerCondition
  let round: Int
  let ordinal: Int
  private(set) var callbacks: [String] = []
  private(set) var routes: [String] = []
  private(set) var pointerWitness: WorkspaceSearchPointerWitness?
  private(set) var eventPairSummary: String?
  private(set) var outcome: String?
  private(set) var completionWaitCompleted = false
  private(set) var receivedOwnedMouseUp = false
  private var keyboardFallbackPending = false
  private var receiptObserver: WorkspaceSearchDeliveryReceiptObserver?
  private var localMonitor: Any?
  private weak var probeWindow: WorkspaceSearchDeliveryProbeWindow?
  private var isFinished = false

  init(
    scenario: WorkspaceSearchDeliveryScenario,
    path: WorkspaceSearchDeliveryPath,
    pointer: WorkspaceSearchDeliveryPointerCondition,
    round: Int,
    ordinal: Int
  ) {
    self.scenario = scenario
    self.path = path
    self.pointer = pointer
    self.round = round
    self.ordinal = ordinal
  }

  var inputDeliveryComplete: Bool {
    receivedOwnedMouseUp && !keyboardFallbackPending
  }

  func recordCallback(_ event: String) {
    callbacks.append(event)
    switch event {
    case "keyboard-fallback-scheduled":
      keyboardFallbackPending = true
    case "keyboard-fallback-execution", "keyboard-fallback-skipped":
      keyboardFallbackPending = false
    default:
      break
    }
  }

  func recordRoute(_ route: String) {
    routes.append(route)
  }

  func recordPointerWitness(_ witness: WorkspaceSearchPointerWitness) {
    pointerWitness = witness
  }

  func recordEventPair(_ summary: String) {
    eventPairSummary = summary
  }

  func recordMouseUpReceipt(_ route: String) {
    routes.append("mouse-up-receipt:\(route)")
    if route == "qualifiedTrackingReceipt" {
      receivedOwnedMouseUp = true
    }
  }

  func recordMouseUpWindowReturn() {
    receivedOwnedMouseUp = true
    routes.append("window-super-return:leftMouseUp")
  }

  func recordCompletionWait(_ completed: Bool) {
    completionWaitCompleted = completed
  }

  func setOutcome(_ outcome: String) {
    self.outcome = outcome
  }

  func arm(
    _ click: WorkspaceSearchDeliveryClick,
    in window: WorkspaceSearchDeliveryProbeWindow
  ) throws {
    probeWindow = window
    let receiptObserver = WorkspaceSearchDeliveryReceiptObserver(
      window: window,
      generation: click.generation,
      mouseUp: click.up
    ) { [weak self] route in
      self?.recordMouseUpReceipt(route)
    }
    self.receiptObserver = receiptObserver

    guard let monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseUp],
      handler: { [self, window] event in
        MainActor.assumeIsolated {
          if let identity = click.identity(for: event, in: window) {
            recordRoute(
              "app-monitor:\(identity.label):pointer=\(WorkspaceSearchDeliveryPointerCondition.label(NSEvent.mouseLocation))"
            )
            if identity.type == .leftMouseUp {
              NotificationCenter.default.post(
                name: WorkspaceSearchDeliveryProbeNotification.localMouseUpReceipt,
                object: event,
                userInfo: ["generation": click.generation.uuidString]
              )
            }
          }
        }
        return event
      }
    ) else {
      receiptObserver.removeObserver()
      self.receiptObserver = nil
      throw WorkspaceSearchDeliveryError.localMonitorUnavailable
    }
    localMonitor = monitor
    window.arm(click, trial: self)
  }

  func finish() {
    guard !isFinished else { return }
    isFinished = true
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
    receiptObserver?.removeObserver()
    receiptObserver = nil
    probeWindow?.disarm()
    probeWindow = nil
  }
}

private enum WorkspaceSearchDeliveryError: Error {
  case localMonitorUnavailable
  case probeWindowUnavailable
}

private enum WorkspaceSearchDeliveryProbeNotification {
  static let arm = Notification.Name("org.fleck.appkit-test-host.models-click.arm")
  static let windowEvent = Notification.Name(
    "org.fleck.appkit-test-host.models-click.window-event"
  )
  static let disarm = Notification.Name("org.fleck.appkit-test-host.models-click.disarm")
  static let localMouseUpReceipt = Notification.Name(
    "org.fleck.appkit-test-host.models-click.local-mouse-up-receipt"
  )
  static let trackingMouseUpReceipt = Notification.Name(
    "org.fleck.appkit-test-host.models-click.tracking-mouse-up-receipt"
  )
}

@MainActor
private struct WorkspaceSearchDeliveryEventIdentity {
  let type: NSEvent.EventType
  let windowNumber: Int
  let eventNumber: Int
  let timestamp: TimeInterval
  let x: Double
  let y: Double
  let modifierFlags: NSEvent.ModifierFlags.RawValue
  let clickCount: Int

  init?(event: NSEvent, window: NSWindow) {
    guard (event.type == .leftMouseDown || event.type == .leftMouseUp),
      event.window === window,
      event.windowNumber == window.windowNumber
    else {
      return nil
    }
    type = event.type
    windowNumber = event.windowNumber
    eventNumber = event.eventNumber
    timestamp = event.timestamp
    x = Double(event.locationInWindow.x)
    y = Double(event.locationInWindow.y)
    modifierFlags = event.modifierFlags.rawValue
    clickCount = event.clickCount
  }

  func matches(_ other: Self) -> Bool {
    type == other.type
      && windowNumber == other.windowNumber
      && eventNumber == other.eventNumber
      && timestamp == other.timestamp
      && x == other.x
      && y == other.y
      && modifierFlags == other.modifierFlags
      && clickCount == other.clickCount
  }

  func matches(_ event: NSEvent, in window: NSWindow) -> Bool {
    guard let identity = Self(event: event, window: window) else { return false }
    return matches(identity)
  }

  var typeName: String {
    type == .leftMouseDown ? "leftMouseDown" : "leftMouseUp"
  }

  var label: String {
    "\(typeName)#\(eventNumber)"
  }

  func notificationFields(prefix: String) -> [AnyHashable: Any] {
    [
      "\(prefix).type": Int(type.rawValue),
      "\(prefix).eventNumber": eventNumber,
      "\(prefix).timestamp": timestamp,
      "\(prefix).x": x,
      "\(prefix).y": y,
      "\(prefix).flags": modifierFlags,
      "\(prefix).clickCount": clickCount,
    ]
  }
}

@MainActor
private struct WorkspaceSearchDeliveryClick {
  let generation: UUID
  let scenario: String
  let ordinal: Int
  let targetKind: String
  let windowNumber: Int
  let down: WorkspaceSearchDeliveryEventIdentity
  let up: WorkspaceSearchDeliveryEventIdentity

  var armFields: [AnyHashable: Any] {
    var fields: [AnyHashable: Any] = [
      "generation": generation.uuidString,
      "scenario": scenario,
      "ordinal": ordinal,
      "targetKind": targetKind,
      "windowNumber": windowNumber,
    ]
    fields.merge(down.notificationFields(prefix: "down")) { _, new in new }
    fields.merge(up.notificationFields(prefix: "up")) { _, new in new }
    return fields
  }

  func identity(
    for event: NSEvent,
    in window: NSWindow
  ) -> WorkspaceSearchDeliveryEventIdentity? {
    guard let identity = WorkspaceSearchDeliveryEventIdentity(event: event, window: window),
      identity.matches(down) || identity.matches(up)
    else {
      return nil
    }
    return identity
  }

  func eventFields(
    _ event: WorkspaceSearchDeliveryEventIdentity,
    phase: String
  ) -> [AnyHashable: Any] {
    var fields = armFields
    fields["phase"] = phase
    fields.merge(event.notificationFields(prefix: "event")) { _, new in new }
    return fields
  }
}

@MainActor
private final class WorkspaceSearchDeliveryProbeWindow: NSWindow {
  private var armedClick: WorkspaceSearchDeliveryClick?
  private weak var trial: WorkspaceSearchDeliveryTrial?

  func arm(_ click: WorkspaceSearchDeliveryClick, trial: WorkspaceSearchDeliveryTrial) {
    armedClick = click
    self.trial = trial
    NotificationCenter.default.post(
      name: WorkspaceSearchDeliveryProbeNotification.arm,
      object: self,
      userInfo: click.armFields
    )
  }

  func disarm() {
    guard let armedClick else { return }
    NotificationCenter.default.post(
      name: WorkspaceSearchDeliveryProbeNotification.disarm,
      object: self,
      userInfo: armedClick.armFields
    )
    self.armedClick = nil
    trial = nil
  }

  override func sendEvent(_ event: NSEvent) {
    let click = armedClick
    let identity = click?.identity(for: event, in: self)
    if let click, let identity {
      trial?.recordRoute("window-entry:\(identity.label)")
      NotificationCenter.default.post(
        name: WorkspaceSearchDeliveryProbeNotification.windowEvent,
        object: self,
        userInfo: click.eventFields(identity, phase: "entry")
      )
    }
    super.sendEvent(event)
    if let click, let identity {
      trial?.recordRoute("window-return:\(identity.label)")
      if identity.type == .leftMouseUp {
        trial?.recordMouseUpWindowReturn()
      }
      NotificationCenter.default.post(
        name: WorkspaceSearchDeliveryProbeNotification.windowEvent,
        object: self,
        userInfo: click.eventFields(identity, phase: "return")
      )
    }
  }
}

@MainActor
private final class WorkspaceSearchDeliveryReceiptObserver: NSObject {
  private let window: NSWindow
  private let windowNumber: Int
  private let generation: UUID
  private let mouseUp: WorkspaceSearchDeliveryEventIdentity
  private let onReceipt: @MainActor (String) -> Void

  init(
    window: NSWindow,
    generation: UUID,
    mouseUp: WorkspaceSearchDeliveryEventIdentity,
    onReceipt: @escaping @MainActor (String) -> Void
  ) {
    self.window = window
    windowNumber = window.windowNumber
    self.generation = generation
    self.mouseUp = mouseUp
    self.onReceipt = onReceipt
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(receiveMouseUpReceipt(_:)),
      name: WorkspaceSearchDeliveryProbeNotification.localMouseUpReceipt,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(receiveMouseUpReceipt(_:)),
      name: WorkspaceSearchDeliveryProbeNotification.trackingMouseUpReceipt,
      object: nil
    )
  }

  func removeObserver() {
    NotificationCenter.default.removeObserver(
      self,
      name: WorkspaceSearchDeliveryProbeNotification.localMouseUpReceipt,
      object: nil
    )
    NotificationCenter.default.removeObserver(
      self,
      name: WorkspaceSearchDeliveryProbeNotification.trackingMouseUpReceipt,
      object: nil
    )
  }

  @objc private func receiveMouseUpReceipt(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
      let generationValue = userInfo["generation"] as? String,
      UUID(uuidString: generationValue) == generation,
      let event = notification.object as? NSEvent,
      mouseUp.matches(event, in: window)
    else {
      return
    }

    if notification.name == WorkspaceSearchDeliveryProbeNotification.localMouseUpReceipt {
      onReceipt("localMouseUpReceipt")
      return
    }
    guard notification.name == WorkspaceSearchDeliveryProbeNotification.trackingMouseUpReceipt,
      let receiptWindowNumber = (userInfo["windowNumber"] as? NSNumber)?.intValue,
      receiptWindowNumber == windowNumber,
      userInfo["dequeue"] as? Bool == true,
      userInfo["mode"] as? String == RunLoop.Mode.eventTracking.rawValue,
      userInfo["dequeuedDuringOwnedWindowSynchronousDown"] as? Bool == true,
      userInfo["downSuperDispatchReturned"] as? Bool == true
    else {
      return
    }
    onReceipt("qualifiedTrackingReceipt")
  }
}

private struct WorkspaceSearchPointerWitness {
  let condition: WorkspaceSearchDeliveryPointerCondition
  let requested: NSPoint?
  let actual: NSPoint
  let warpSucceeded: Bool
  let matches: Bool

  var summary: String {
    "requested=\(requested.map(NSStringFromPoint) ?? "unavailable") "
      + "actual=\(NSStringFromPoint(actual)) warpSucceeded=\(warpSucceeded) matches=\(matches)"
  }
}

@MainActor
private extension WorkspaceSearchDeliveryPointerCondition {
  static func label(_ point: NSPoint) -> String {
    "\(Int(point.x)):\(Int(point.y))"
  }
}

@MainActor
private func positionWorkspaceSearchPointer(
  for trial: WorkspaceSearchDeliveryTrial,
  window: NSWindow,
  windowPoint: NSPoint
) -> WorkspaceSearchPointerWitness {
  let screen = window.screen ?? NSScreen.main
  let target = window.convertPoint(toScreen: windowPoint)
  let requested: NSPoint?
  switch trial.pointer {
  case .atTarget:
    requested = target
  case .outsideWindow:
    requested = screen.flatMap { screen in
      let inset: CGFloat = 32
      let candidates = [
        NSPoint(x: screen.frame.minX + inset, y: screen.frame.minY + inset),
        NSPoint(x: screen.frame.minX + inset, y: screen.frame.maxY - inset),
        NSPoint(x: screen.frame.maxX - inset, y: screen.frame.minY + inset),
        NSPoint(x: screen.frame.maxX - inset, y: screen.frame.maxY - inset),
      ]
      return candidates.first {
        screen.frame.contains($0) && !window.frame.contains($0)
      }
    }
  }

  var warpSucceeded = false
  if let screen, let requested,
    let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
  {
    let displayBounds = CGDisplayBounds(CGDirectDisplayID(displayNumber.uint32Value))
    guard screen.frame.width > 0, screen.frame.height > 0,
      displayBounds.width > 0, displayBounds.height > 0
    else {
      let actual = NSEvent.mouseLocation
      return WorkspaceSearchPointerWitness(
        condition: trial.pointer,
        requested: requested,
        actual: actual,
        warpSucceeded: false,
        matches: false
      )
    }
    let pointInDisplay = CGPoint(
      x: (requested.x - screen.frame.minX) * displayBounds.width / screen.frame.width,
      y: (screen.frame.maxY - requested.y) * displayBounds.height / screen.frame.height
    )
    let warpPoint = CGPoint(
      x: displayBounds.minX + pointInDisplay.x,
      y: displayBounds.minY + pointInDisplay.y
    )
    warpSucceeded = CGWarpMouseCursorPosition(warpPoint) == .success
  }

  let actual = NSEvent.mouseLocation
  let matches: Bool
  switch trial.pointer {
  case .atTarget:
    matches = warpSucceeded && requested.map {
      abs(actual.x - $0.x) <= 1 && abs(actual.y - $0.y) <= 1
    } == true
  case .outsideWindow:
    matches = warpSucceeded && !window.frame.contains(actual)
  }
  return WorkspaceSearchPointerWitness(
    condition: trial.pointer,
    requested: requested,
    actual: actual,
    warpSucceeded: warpSucceeded,
    matches: matches
  )
}

@MainActor
private func hostedWorkspaceSearchDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for subview in view.subviews {
    if let match = hostedWorkspaceSearchDescendant(in: subview, as: type) { return match }
  }
  return nil
}

@MainActor
private func hostedWorkspaceSearchDescendants<T: NSView>(in view: NSView, as type: T.Type) -> [T] {
  var matches: [T] = []
  if let match = view as? T { matches.append(match) }
  for subview in view.subviews {
    matches.append(contentsOf: hostedWorkspaceSearchDescendants(in: subview, as: type))
  }
  return matches
}

@MainActor
private func hostedWorkspaceSearchScrollViews(in view: NSView) -> [NSScrollView] {
  var scrollViews: [NSScrollView] = []
  if let scrollView = view as? NSScrollView {
    scrollViews.append(scrollView)
  }
  for subview in view.subviews {
    scrollViews.append(contentsOf: hostedWorkspaceSearchScrollViews(in: subview))
  }
  return scrollViews
}

@MainActor
private func workspaceSearchTrigger(in view: NSView) -> NSView? {
  let headerControls = hostedWorkspaceSearchDescendants(in: view, as: NSView.self)
    .filter { control in
      guard String(describing: type(of: control)) == "KeyViewProxy" else { return false }
      let frame = control.convert(control.bounds, to: view)
      return frame.minY < 40 && frame.minX > view.bounds.midX
    }
    .sorted {
      $0.convert($0.bounds, to: view).minX < $1.convert($1.bounds, to: view).minX
    }
  return headerControls.dropFirst().first
}

@MainActor
private func printCompactSearchDismissDiagnostic(
  host: NSView,
  window: NSWindow,
  queryFrame: NSRect,
  dismissPoint: NSPoint
) {
  let windowPoint = host.convert(dismissPoint, to: nil)
  var hitChain: [String] = []
  var hit = window.contentView?.hitTest(
    window.contentView?.superview?.convert(windowPoint, from: nil) ?? windowPoint
  )
  while let view = hit, hitChain.count < 12 {
    hitChain.append(
      "\(type(of: view))@\(NSStringFromRect(view.convert(view.bounds, to: host)))"
    )
    hit = view.superview
  }
  let containing = hostedWorkspaceSearchDescendants(in: host, as: NSView.self)
    .filter { $0 !== host && $0.convert($0.bounds, to: host).contains(dismissPoint) }
    .map { "\(type(of: $0))@\(NSStringFromRect($0.convert($0.bounds, to: host)))" }
  var pendingAccessibilityElements: [Any] = [host]
  var visitedAccessibilityElements: Set<ObjectIdentifier> = []
  var dismissAccessibilityFrames: [String] = []
  while let value = pendingAccessibilityElements.popLast(), visitedAccessibilityElements.count < 512 {
    guard let element = value as? NSObject,
      visitedAccessibilityElements.insert(ObjectIdentifier(element)).inserted
    else { continue }
    let labels = ["accessibilityLabel", "accessibilityTitle"].compactMap { name -> String? in
      let selector = NSSelectorFromString(name)
      guard element.responds(to: selector) else { return nil }
      let value = element.perform(selector)?.takeUnretainedValue()
      return (value as? String) ?? (value as? NSAttributedString)?.string
    }
    if labels.contains("Dismiss search"),
      element.responds(to: NSSelectorFromString("accessibilityFrame")),
      let frame = element.value(forKey: "accessibilityFrame") as? NSValue
    {
      let hostFrame = host.convert(window.convertFromScreen(frame.rectValue), from: nil)
      dismissAccessibilityFrames.append(
        "\(NSStringFromRect(hostFrame)):containsClick=\(hostFrame.contains(dismissPoint))"
      )
    }
    let childrenSelector = NSSelectorFromString("accessibilityChildren")
    if element.responds(to: childrenSelector),
      let children = element.perform(childrenSelector)?.takeUnretainedValue() as? [Any]
    {
      pendingAccessibilityElements.append(contentsOf: children)
    }
  }
  print(
    "FLECK_COMPACT_SEARCH_DISMISS_DIAGNOSTIC"
      + " active=\(NSApp.isActive) key=\(window.isKeyWindow)"
      + " responder=\(String(describing: window.firstResponder.map { type(of: $0) }))"
      + " host=\(NSStringFromRect(host.bounds))"
      + " fitting=\(NSStringFromSize(host.fittingSize))"
      + " query=\(NSStringFromRect(queryFrame))"
      + " point=\(NSStringFromPoint(dismissPoint))"
      + " hit=[\(hitChain.joined(separator: " < "))]"
      + " containing=[\(containing.joined(separator: ", "))]"
      + " dismissAX=[\(dismissAccessibilityFrames.joined(separator: ", "))]"
  )
}

@MainActor
private func clickWorkspaceSearchControl(_ control: NSView, in window: NSWindow) throws {
  let point = control.convert(
    NSPoint(x: control.bounds.midX, y: control.bounds.midY),
    to: nil
  )
  try clickWorkspaceSearchControl(point, in: window)
}

@MainActor
private enum WorkspaceSearchPointerEventSequence {
  static var nextEventNumber = 1
}

@MainActor
private func clickWorkspaceSearchControl(_ windowPoint: NSPoint, in window: NSWindow) throws {
  if let trial = WorkspaceSearchDeliveryExperiment.current {
    let pointerWitness = positionWorkspaceSearchPointer(
      for: trial,
      window: window,
      windowPoint: windowPoint
    )
    trial.recordPointerWitness(pointerWitness)
    guard let probeWindow = window as? WorkspaceSearchDeliveryProbeWindow else {
      throw WorkspaceSearchDeliveryError.probeWindowUnavailable
    }

    let timestamp = ProcessInfo.processInfo.systemUptime
    let mouseDownEventNumber = WorkspaceSearchPointerEventSequence.nextEventNumber
    WorkspaceSearchPointerEventSequence.nextEventNumber += 1
    let mouseUpEventNumber = WorkspaceSearchPointerEventSequence.nextEventNumber
    WorkspaceSearchPointerEventSequence.nextEventNumber += 1
    let mouseDown = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: windowPoint,
        modifierFlags: [],
        timestamp: timestamp,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: mouseDownEventNumber,
        clickCount: 1,
        pressure: 1
      )
    )
    let mouseUp = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: windowPoint,
        modifierFlags: [],
        timestamp: timestamp,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: mouseUpEventNumber,
        clickCount: 1,
        pressure: 0
      )
    )
    let down = try #require(
      WorkspaceSearchDeliveryEventIdentity(event: mouseDown, window: probeWindow)
    )
    let up = try #require(
      WorkspaceSearchDeliveryEventIdentity(event: mouseUp, window: probeWindow)
    )
    let click = WorkspaceSearchDeliveryClick(
      generation: UUID(),
      scenario: "workspace-search-delivery-experiment",
      ordinal: trial.ordinal,
      targetKind: "\(trial.scenario.rawValue).\(trial.pointer.rawValue)",
      windowNumber: probeWindow.windowNumber,
      down: down,
      up: up
    )
    trial.recordEventPair("down=\(down.label) up=\(up.label)")
    try trial.arm(click, in: probeWindow)

    switch trial.path {
    case .splitWindowDown:
      window.postEvent(mouseUp, atStart: true)
      window.sendEvent(mouseDown)
    case .queuedPair:
      NSApp.postEvent(mouseUp, atStart: true)
      NSApp.postEvent(mouseDown, atStart: true)
    }
    return
  }

  let timestamp = ProcessInfo.processInfo.systemUptime
  let mouseDownEventNumber = WorkspaceSearchPointerEventSequence.nextEventNumber
  WorkspaceSearchPointerEventSequence.nextEventNumber += 1
  let mouseUpEventNumber = WorkspaceSearchPointerEventSequence.nextEventNumber
  WorkspaceSearchPointerEventSequence.nextEventNumber += 1
  let mouseDown = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: windowPoint,
      modifierFlags: [],
      timestamp: timestamp,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: mouseDownEventNumber,
      clickCount: 1,
      pressure: 1
    ))
  let mouseUp = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseUp,
      location: windowPoint,
      modifierFlags: [],
      timestamp: timestamp,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: mouseUpEventNumber,
      clickCount: 1,
      pressure: 0
    ))
  window.postEvent(mouseUp, atStart: true)
  window.sendEvent(mouseDown)
}

@MainActor
private func sendWorkspaceSearchEscape(to window: NSWindow) {
  guard let event = NSEvent.keyEvent(
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
  ) else { return }
  window.sendEvent(event)
}

@MainActor
private func settleWorkspaceSearchHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@MainActor
private func waitForWorkspaceSearchHostState(
  _ view: NSView,
  until condition: @MainActor () -> Bool
) async throws -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(2))
  while true {
    try Task.checkCancellation()
    view.layoutSubtreeIfNeeded()
    if condition() { return true }
    let now = clock.now
    guard now < deadline else { return false }
    try await Task.sleep(for: min(.milliseconds(10), now.duration(to: deadline)))
  }
}

@MainActor
private func workspaceSearchThemePixelCount(
  in image: NSBitmapImageRep,
  matching targetColor: NSColor
) -> Int {
  guard let target = targetColor.usingColorSpace(image.colorSpace) else { return 0 }
  var matches = 0
  for y in 0..<image.pixelsHigh {
    for x in 0..<image.pixelsWide {
      guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(image.colorSpace),
        color.alphaComponent > 0.5
      else { continue }
      let distance = max(
        abs(color.redComponent - target.redComponent),
        max(
          abs(color.greenComponent - target.greenComponent),
          abs(color.blueComponent - target.blueComponent)
        )
      )
      if distance < 0.04 { matches += 1 }
    }
  }
  return matches
}

@MainActor
private func workspaceSearchHostedCapture(in view: NSView) throws -> NSBitmapImageRep {
  let scale = view.window?.backingScaleFactor ?? 2
  let image = try #require(
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(view.bounds.width * scale),
      pixelsHigh: Int(view.bounds.height * scale),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .calibratedRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  )
  image.size = view.bounds.size
  view.cacheDisplay(in: view.bounds, to: image)
  return image
}
