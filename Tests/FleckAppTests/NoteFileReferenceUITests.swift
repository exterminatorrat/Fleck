import AppKit
import FleckCore
import Foundation
import SwiftUI
import Testing

@testable import FleckApp

@Suite(.serialized)
@MainActor
struct NoteFileReferenceUITests {
  @Test func widthAwareLayoutUsesOneRowAndExposesEveryOverflowedFile() async {
    let references = (0..<8).map { index in
      referencePresentation(
        filename: "very-long-reference-name-\(index)-for-layout.pdf"
      )
    }

    let wide = NoteFileReferenceLayout.plan(
      references: references,
      availableWidth: 900
    )
    #expect(wide.rows.count == 1)
    #expect(!wide.overflow.isEmpty)
    #expect(
      wide.rows.flatMap { $0 }.map(\.reference.id) + wide.overflow.map(\.id)
        == references.map(\.id)
    )

    let roomyReferences = Array(references.prefix(3))
    let roomy = NoteFileReferenceLayout.plan(
      references: roomyReferences,
      availableWidth: 900
    )
    #expect(roomy.rows.count == 1)
    #expect(roomy.overflow.isEmpty)
    #expect(roomy.rows.flatMap { $0 }.map(\.reference.id) == roomyReferences.map(\.id))

    let narrow = NoteFileReferenceLayout.plan(
      references: references,
      availableWidth: 280
    )
    #expect(narrow.rows.count == 1)
    #expect(!narrow.overflow.isEmpty)
    let visibleIDs = narrow.rows.flatMap { $0 }.map(\.reference.id)
    let overflowIDs = narrow.overflow.map(\.id)
    #expect(Set(visibleIDs + overflowIDs) == Set(references.map(\.id)))
    let rowsFit = narrow.rows.allSatisfy { row in
      let itemWidths = row.map(\.width).reduce(0, +)
      let gaps = CGFloat(max(0, row.count - 1)) * NoteFileReferenceLayout.spacing
      return itemWidths + gaps <= narrow.chipAreaWidth
    }
    #expect(rowsFit)

    NSApplication.shared.accessibilitySetValue(
      true,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
    let horizontalInsets: CGFloat = 28
    let narrowHost = referenceViewHost(
      references: references,
      width: 280 + horizontalInsets
    )
    let wideHost = referenceViewHost(
      references: references,
      width: 900 + horizontalInsets
    )
    let roomyHost = referenceViewHost(
      references: roomyReferences,
      width: 900 + horizontalInsets
    )
    await settleReferenceHost(narrowHost)
    await settleReferenceHost(wideHost)
    await settleReferenceHost(roomyHost)
    let narrowLabels = referenceAccessibilityStrings(in: narrowHost)
    let wideLabels = referenceAccessibilityStrings(in: wideHost)
    let roomyLabels = referenceAccessibilityStrings(in: roomyHost)
    #expect(narrowLabels.contains { $0.contains("more file shortcuts") })
    #expect(wideLabels.contains { $0.contains("more file shortcuts") })
    #expect(!roomyLabels.contains { $0.contains("more file shortcuts") })
  }

  @Test func compactLayoutConservesZeroOneManyMixedAndMissingReferences() {
    let sets = [
      [],
      [referencePresentation(filename: "one.txt")],
      [
        referencePresentation(filename: "日本語の設計資料.pdf"),
        referencePresentation(filename: "résumé-notes.txt"),
        referencePresentation(filename: "missing.txt", isAvailable: false),
        referencePresentation(filename: "family-👨‍👩‍👧‍👦-archive.pages"),
      ],
    ]

    for references in sets {
      for width in [180.0, 320.0, 900.0] {
        let plan = NoteFileReferenceLayout.plan(
          references: references,
          availableWidth: width
        )
        #expect(plan.rows.count <= 1)
        let visibleIDs = plan.rows.flatMap { $0 }.map(\.reference.id)
        #expect(visibleIDs + plan.overflow.map(\.id) == references.map(\.id))
        #expect(plan.rows.allSatisfy { row in
          row.map(\.width).reduce(0, +)
            + CGFloat(max(0, row.count - 1)) * NoteFileReferenceLayout.spacing
            <= plan.chipAreaWidth
        })
      }
    }
  }

  @Test func availableFileMenuIncludesLocateAlongsideOpenAndReveal() {
    let reference = referencePresentation(filename: "available.pdf")
    #expect(
      NoteFileReferenceView.actions(for: reference)
        == [.open, .reveal, .locate, .remove]
    )
  }

  @Test func unavailableChipExposesFilenameAndNonColorStatus() async throws {
    NSApplication.shared.accessibilitySetValue(
      true,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
    let reference = referencePresentation(
      filename: "missing-reference.txt",
      isAvailable: false
    )
    let host = NSHostingView(
      rootView: NoteFileReferenceView(
        references: [reference],
        canAdd: true,
        onAdd: {},
        onOpen: { _ in },
        onReveal: { _ in },
        onLocate: { _ in },
        onRemove: { _ in }
      )
      .frame(width: 280)
    )
    await settleReferenceHost(host)
    let labels = referenceAccessibilityStrings(in: host)

    #expect(labels.contains { $0.contains("missing-reference.txt") })
    #expect(labels.contains { $0.contains("File unavailable") })
  }

  @Test func disabledAddDoesNotInvokeItsAction() async throws {
    var addCount = 0
    let host = referenceViewHost(
      references: [referencePresentation(filename: "locked.txt")],
      width: 320,
      canAdd: false,
      onAdd: { addCount += 1 }
    )
    await settleReferenceHost(host)
    let add = try #require(
      referenceAccessibilityElement(in: host, label: "Add file shortcut")
    )

    _ = add.perform(NSSelectorFromString("accessibilityPerformPress"))
    #expect(addCount == 0)
  }

  @Test func compactStripRendersOneRowAcrossWidthsAndAppearances() async throws {
    let references = [
      referencePresentation(filename: "missing-reference.txt", isAvailable: false),
      referencePresentation(filename: "Quarterly-planning-notes-with-a-long-name.pages"),
      referencePresentation(filename: "日本語の設計資料.pdf"),
    ]
    let configurations: [(String, ColorScheme, ColorSchemeContrast, Bool, Bool)] = [
      ("light", .light, .standard, false, false),
      ("dark", .dark, .standard, false, false),
      ("disabled", .light, .standard, false, false),
      ("high-contrast", .light, .increased, false, false),
      ("reduced-settings", .light, .increased, true, true),
    ]
    let evidencePath = ProcessInfo.processInfo.environment[
      "FLECK_FILE_REFERENCE_EVIDENCE_DIR"
    ]
    var isDirectory: ObjCBool = false
    let shouldExport = evidencePath.map {
      FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory)
        && isDirectory.boolValue
    } ?? false

    for width in [320, 640] {
      for (name, scheme, contrast, reduceTransparency, reduceMotion) in configurations {
        let host = NSHostingView(
          rootView: AnyView(
            NoteFileReferenceView(
              references: references,
              canAdd: name != "disabled",
              onAdd: {},
              onOpen: { _ in },
              onReveal: { _ in },
              onLocate: { _ in },
              onRemove: { _ in }
            )
            .environment(\.colorScheme, scheme)
            .environment(\._colorSchemeContrast, contrast)
            .environment(\._accessibilityReduceTransparency, reduceTransparency)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .frame(width: CGFloat(width))
            .background(Color(nsColor: .windowBackgroundColor))
          )
        )
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 40)
        await settleReferenceHost(host)
        #expect(host.fittingSize.height == 40)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        let bytesPerPixel = max(1, bitmap.bitsPerPixel / 8)
        let firstPixel = (0..<bytesPerPixel).map { bytes[$0] }
        var hasDistinctPixel = false
        for y in 0..<bitmap.pixelsHigh {
          for x in 0..<bitmap.pixelsWide {
            let offset = y * bitmap.bytesPerRow + x * bytesPerPixel
            if firstPixel.indices.contains(where: { bytes[offset + $0] != firstPixel[$0] }) {
              hasDistinctPixel = true
              break
            }
          }
          if hasDistinctPixel { break }
        }
        #expect(hasDistinctPixel)
        if shouldExport, let evidencePath {
          let data = try #require(bitmap.representation(using: .png, properties: [:]))
          try data.write(
            to: URL(fileURLWithPath: evidencePath)
              .appendingPathComponent("file-strip-\(width)-\(name).png")
          )
        }
      }
    }
  }

  @Test func appStateUsesDedicatedSidecarAndKeepsNoteContentUnchanged() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Source", body: "Keep this body")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let fileURL = try fixture.makeFile(named: "outline.pdf")
    let exportBefore = NoteExport(note: note, format: .markdown).data

    #expect(state.addFileReference(noteID: note.id, url: fileURL))
    #expect(state.selectedNoteFileReferences.map(\.filename) == ["outline.pdf"])
    #expect(state.selectedNoteFileReferences.allSatisfy { $0.isAvailable })
    #expect(state.selectedNote?.title == "Source")
    #expect(state.selectedNote?.body == "Keep this body")
    #expect(
      NoteExport(
        note: try #require(state.selectedNote),
        format: .markdown
      ).data == exportBefore
    )
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.rootURL
          .appendingPathComponent("FileReferences/references.json").path
      )
    )
  }

  @Test func movingToTrashAndRestoringTheNoteRetainsItsShortcuts() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Restore")
    let state = AppState(store: LocalStore(rootURL: fixture.rootURL))
    await state.waitUntilInitialLoad()
    state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    let fileURL = try fixture.makeFile(named: "retained.txt")
    #expect(state.addFileReference(noteID: note.id, url: fileURL))

    #expect(state.moveToTrash(note.id))
    try await state.saveNow().value
    await state.refreshTrash()
    #expect(state.fileReferences(noteID: note.id).count == 1)
    let trashed = try #require(state.trashedNotes.first(where: { $0.id == note.id }))
    let restore = try #require(state.restore(trashed))
    await restore.value
    state.refreshSelectedNoteFileReferences()

    #expect(state.selectedNote?.id == note.id)
    #expect(state.selectedNoteFileReferences.map(\.filename) == ["retained.txt"])
  }

  @Test func pickerResultKeepsCapturedNoteIdentityAfterSelectionChanges() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let first = Note(title: "First")
    let second = Note(title: "Second")
    let state = await fixture.state(
      workspace: Workspace(
        notes: [first, second],
        selectedNoteID: first.id,
        folders: []
      )
    )
    let fileURL = try fixture.makeFile(named: "first.txt")

    state.workspace.selectedNoteID = second.id
    #expect(state.addFileReference(noteID: first.id, url: fileURL))
    #expect(state.fileReferences(noteID: first.id).count == 1)
    #expect(state.fileReferences(noteID: second.id).isEmpty)

    NotesPanel.completeFileReferenceSelection(
      nil,
      noteID: first.id,
      appState: state
    )
    #expect(state.fileReferences(noteID: first.id).count == 1)

    state.workspace.deleteNote(id: first.id)
    NotesPanel.completeFileReferenceSelection(
      fileURL,
      noteID: first.id,
      appState: state
    )
    #expect(state.fileReferences(noteID: first.id).count == 1)
  }

  @Test func unavailableFilesRemainVisibleAndCanBeRelinked() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Reference")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let originalURL = try fixture.makeFile(named: "missing.txt")
    #expect(state.addFileReference(noteID: note.id, url: originalURL))
    let referenceID = try #require(state.selectedNoteFileReferences.first?.id)
    try FileManager.default.removeItem(at: originalURL)

    state.refreshSelectedNoteFileReferences()
    #expect(state.selectedNoteFileReferences.first?.isAvailable == false)
    #expect(state.selectedNoteFileReferences.first?.filename == "missing.txt")

    let replacementURL = try fixture.makeFile(named: "replacement.txt")
    let other = Note(title: "Other")
    state.workspace.notes.append(other)
    state.workspace.selectedNoteID = other.id
    #expect(state.relinkFileReference(referenceID: referenceID, url: replacementURL))
    state.workspace.selectedNoteID = note.id
    state.refreshSelectedNoteFileReferences()
    #expect(state.selectedNoteFileReferences.first?.isAvailable == true)
    #expect(state.selectedNoteFileReferences.first?.filename == "replacement.txt")

    NotesPanel.completeFileReferenceRelink(
      nil,
      referenceID: referenceID,
      appState: state
    )
    #expect(state.selectedNoteFileReferences.first?.filename == "replacement.txt")
  }

  @Test func noteLockedBeforePickerCompletionRejectsTheResult() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Locked")
    let gate = NoteFileReferenceAsyncGate()
    let state = AppState(
      store: LocalStore(rootURL: fixture.rootURL),
      replaceAgentCapabilities: { _, _ in
        await gate.waitForRelease()
        return AgentCapabilityState(profiles: [:], unassignedLegacyNoteIDs: [])
      }
    )
    await state.waitUntilInitialLoad()
    state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    let context = AgentCapabilityPresentation.noteAccessContext(
      for: note.id,
      in: state.workspace
    )
    let transaction = Task {
      await state.updateAgentCapabilitiesForNote(
        noteID: note.id,
        capturedContext: context,
        replacements: [],
        expectedGrantRevisions: [:]
      )
    }
    await gate.waitUntilStarted()
    let fileURL = try fixture.makeFile(named: "locked.txt")

    NotesPanel.completeFileReferenceSelection(
      fileURL,
      noteID: note.id,
      appState: state
    )
    #expect(state.fileReferences(noteID: note.id).isEmpty)
    await gate.release()
    _ = await transaction.value
  }

  @Test func removeRegistersUndoAndRedoWithoutChangingTheNote() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Undo", body: "Unchanged")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let fileURL = try fixture.makeFile(named: "undo.txt")
    #expect(state.addFileReference(noteID: note.id, url: fileURL))
    let referenceID = try #require(state.selectedNoteFileReferences.first?.id)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false

    undoManager.beginUndoGrouping()
    #expect(state.removeFileReference(referenceID: referenceID, undoManager: undoManager))
    undoManager.endUndoGrouping()
    #expect(state.selectedNoteFileReferences.isEmpty)
    #expect(undoManager.canUndo)
    undoManager.undo()
    #expect(state.selectedNoteFileReferences.count == 1)
    #expect(undoManager.canRedo)
    undoManager.redo()
    #expect(state.selectedNoteFileReferences.isEmpty)
    #expect(state.selectedNote?.body == "Unchanged")
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test func corruptSidecarIsPreservedAndBlocksShortcutWrites() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let sidecarURL = fixture.rootURL
      .appendingPathComponent("FileReferences", isDirectory: true)
      .appendingPathComponent("references.json")
    try FileManager.default.createDirectory(
      at: sidecarURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let corrupt = Data("not-json\n".utf8)
    try corrupt.write(to: sidecarURL)
    let note = Note(title: "Corrupt")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let fileURL = try fixture.makeFile(named: "blocked.txt")

    #expect(state.noteFileReferenceError != nil)
    #expect(!state.addFileReference(noteID: note.id, url: fileURL))
    #expect(try Data(contentsOf: sidecarURL) == corrupt)
  }

  @Test func sidecarSaveFailureKeepsVisibleAssociationsUnchanged() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Write failure")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let firstURL = try fixture.makeFile(named: "first.txt")
    let secondURL = try fixture.makeFile(named: "second.txt")
    #expect(state.addFileReference(noteID: note.id, url: firstURL))
    let sidecarURL = fixture.rootURL.appendingPathComponent("FileReferences/references.json")
    let originalBytes = try Data(contentsOf: sidecarURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o444],
      ofItemAtPath: sidecarURL.path
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555],
      ofItemAtPath: sidecarURL.deletingLastPathComponent().path
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: sidecarURL.deletingLastPathComponent().path
      )
    }

    let renamedURL = fixture.rootURL.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: firstURL, to: renamedURL)
    state.refreshSelectedNoteFileReferences()
    #expect(state.selectedNoteFileReferences.first?.isAvailable == true)
    #expect(state.noteFileReferenceError == "File shortcuts could not be saved.")

    #expect(!state.addFileReference(noteID: note.id, url: secondURL))
    #expect(state.selectedNoteFileReferences.map(\.filename) == ["first.txt"])
    #expect(try Data(contentsOf: sidecarURL) == originalBytes)
    #expect(state.noteFileReferenceError == "File shortcuts could not be saved.")

  }

  @Test func pickerEntryPointsPreserveCapturedIDsAndMapTerminalOutcomes() async throws {
    NSApplication.shared.accessibilitySetValue(
      true,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let first = Note(title: "First")
    let second = Note(title: "Second")
    let state = await fixture.state(
      workspace: Workspace(
        notes: [first, second],
        selectedNoteID: first.id,
        folders: []
      )
    )
    let missingURL = try fixture.makeFile(named: "missing.txt")
    #expect(state.addFileReference(noteID: first.id, url: missingURL))
    let referenceID = try #require(state.selectedNoteFileReferences.first?.id)
    try FileManager.default.removeItem(at: missingURL)
    state.refreshSelectedNoteFileReferences()

    var completions: [(NoteFilePicker.Result) -> Void] = []
    let picker = NoteFilePicker { completion in
      completions.append(completion)
      return true
    }
    let runtime = DictationRuntime(appState: state, applicationSupportURL: fixture.rootURL)
    let host = NSHostingView(
      rootView: NotesPanel(dictationRuntime: runtime, filePicker: picker)
        .environmentObject(state)
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
      styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    await settleReferenceHost(host)

    let add = try #require(referenceAccessibilityElement(in: host, label: "Add file shortcut"))
    _ = add.perform(NSSelectorFromString("accessibilityPerformPress"))
    await settleReferenceHost(host)
    completions.removeFirst()(.cancelled)
    #expect(state.fileReferences(noteID: first.id).count == 1)

    _ = add.perform(NSSelectorFromString("accessibilityPerformPress"))
    await settleReferenceHost(host)
    completions.removeFirst()(.aborted)
    #expect(state.fileReferences(noteID: first.id).count == 1)
    #expect(state.noteFileReferenceError == "The file chooser could not be opened.")

    let addedURL = try fixture.makeFile(named: "captured-add.txt")
    _ = add.perform(NSSelectorFromString("accessibilityPerformPress"))
    await settleReferenceHost(host)
    state.workspace.selectedNoteID = second.id
    completions.removeFirst()(.accepted(addedURL))
    #expect(state.fileReferences(noteID: first.id).count == 2)
    #expect(state.fileReferences(noteID: second.id).isEmpty)

    state.workspace.selectedNoteID = first.id
    state.refreshSelectedNoteFileReferences()
    await settleReferenceHost(host)
    let locate = try #require(
      referenceAccessibilityElement(
        in: host,
        label: "Locate unavailable file missing.txt"
      )
    )
    _ = locate.perform(NSSelectorFromString("accessibilityPerformPress"))
    await settleReferenceHost(host)
    let replacementURL = try fixture.makeFile(named: "replacement.txt")
    state.workspace.selectedNoteID = second.id
    completions.removeFirst()(.accepted(replacementURL))
    #expect(
      state.fileReferences(noteID: first.id)
        .first(where: { $0.id == referenceID })?.cachedFilename == "replacement.txt"
    )

    state.workspace.selectedNoteID = first.id
    state.refreshSelectedNoteFileReferences()
    await settleReferenceHost(host)
    let staleAdd = try #require(
      referenceAccessibilityElement(in: host, label: "Add file shortcut")
    )
    state.workspace.deleteNote(id: first.id)
    _ = staleAdd.perform(NSSelectorFromString("accessibilityPerformPress"))
    #expect(completions.isEmpty)

    await runtime.shutdown()
  }

  @Test func hostedBodyAndTitleRemoveThenUndoTheExactReference() async throws {
    let fixture = try NoteFileReferenceUIFixture()
    defer { fixture.remove() }
    let note = Note(title: "Native undo", body: "Body")
    let state = await fixture.state(
      workspace: Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    )
    let commands = EditorCommands()
    let runtime = DictationRuntime(appState: state, applicationSupportURL: fixture.rootURL)
    let fileURL = try fixture.makeFile(named: "native-undo.txt")
    #expect(state.addFileReference(noteID: note.id, url: fileURL))
    let referenceID = try #require(state.selectedNoteFileReferences.first?.id)
    let host = NSHostingView(
      rootView: NotesPanel(dictationRuntime: runtime, editorCommands: commands)
        .environmentObject(state)
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
      styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    await settleReferenceHost(host)
    var caughtError: Error?
    do {
      let body = try #require(referenceDescendant(in: host, as: ListAwareTextView.self))
      let title = try #require(referenceTitleField(in: host, value: note.title))
      let originalBody = body.string
      let originalTitle = title.stringValue

      for focus in [body as NSResponder, title as NSResponder] {
        #expect(window.makeFirstResponder(focus))
        let manager = try #require(
          NotesPanel.fileReferenceUndoManager(commands: commands)
        )
        #expect(
          state.removeFileReference(
            referenceID: referenceID,
            undoManager: manager
          )
        )
        await settleReferenceHost(host)
        #expect(state.selectedNoteFileReferences.isEmpty)
        #expect(manager.canUndo)
        commands.undo()
        await settleReferenceHost(host)
        #expect(state.selectedNoteFileReferences.map(\.id) == [referenceID])
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        commands.redo()
        await settleReferenceHost(host)
        #expect(state.selectedNoteFileReferences.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        commands.undo()
        await settleReferenceHost(host)
        #expect(state.selectedNoteFileReferences.map(\.id) == [referenceID])
        #expect(body.string == originalBody)
        #expect(title.stringValue == originalTitle)
      }
    } catch {
      caughtError = error
    }
    window.contentView = nil
    host.removeFromSuperview()
    window.orderOut(nil)
    await runtime.shutdown()
    if let caughtError {
      throw caughtError
    }
  }
}

@MainActor
private func referencePresentation(
  filename: String,
  isAvailable: Bool = true
) -> NoteFileReferencePresentation {
  NoteFileReferencePresentation(
    reference: NoteFileReference(
      id: UUID(),
      noteID: UUID(),
      bookmarkData: Data([1]),
      cachedFilename: filename
    ),
    url: isAvailable
      ? URL(fileURLWithPath: "/tmp/\(filename)")
      : nil,
    isAvailable: isAvailable
  )
}

@MainActor
private func referenceViewHost(
  references: [NoteFileReferencePresentation],
  width: CGFloat,
  canAdd: Bool = true,
  onAdd: @escaping () -> Void = {}
) -> NSHostingView<AnyView> {
  let host = NSHostingView(
    rootView: AnyView(
      NoteFileReferenceView(
        references: references,
        canAdd: canAdd,
        onAdd: onAdd,
        onOpen: { _ in },
        onReveal: { _ in },
        onLocate: { _ in },
        onRemove: { _ in }
      )
      .frame(width: width)
      .background(Color(nsColor: .windowBackgroundColor))
    )
  )
  host.frame = NSRect(x: 0, y: 0, width: width, height: host.fittingSize.height)
  return host
}

private actor NoteFileReferenceAsyncGate {
  private var started = false
  private var released = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func waitForRelease() async {
    started = true
    for waiter in startWaiters {
      waiter.resume()
    }
    startWaiters.removeAll()
    guard !released else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func release() {
    released = true
    for waiter in releaseWaiters {
      waiter.resume()
    }
    releaseWaiters.removeAll()
  }
}

@MainActor
private struct NoteFileReferenceUIFixture {
  let rootURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("note-file-reference-ui-\(UUID().uuidString)")

  init() throws {
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  }

  func state(workspace: Workspace) async -> AppState {
    let state = AppState(
      store: LocalStore(rootURL: rootURL),
      saveOperation: { _, _, _, _ in .committed }
    )
    await state.waitUntilInitialLoad()
    state.workspace = workspace
    state.refreshSelectedNoteFileReferences()
    return state
  }

  func makeFile(named name: String) throws -> URL {
    let url = rootURL.appendingPathComponent(name)
    try Data("contents".utf8).write(to: url)
    return url
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

@MainActor
private func settleReferenceHost(_ host: NSView) async {
  for _ in 0..<8 {
    try? await Task.sleep(for: .milliseconds(10))
    await Task.yield()
    host.layoutSubtreeIfNeeded()
  }
}

@MainActor
private func referenceDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for subview in view.subviews {
    if let match = referenceDescendant(in: subview, as: type) { return match }
  }
  return nil
}

@MainActor
private func referenceTitleField(in view: NSView, value: String) -> NSTextField? {
  if let field = view as? NSTextField,
    field.stringValue == value,
    field.placeholderString == "Note title"
  {
    return field
  }
  for subview in view.subviews {
    if let match = referenceTitleField(in: subview, value: value) { return match }
  }
  return nil
}

@MainActor
private func referenceAccessibilityStrings(in value: Any) -> [String] {
  guard let object = value as? NSObject else { return [] }
  var values: [String] = []
  for name in ["accessibilityLabel", "accessibilityValue", "accessibilityHelp"] {
    let selector = NSSelectorFromString(name)
    if object.responds(to: selector),
      let value = object.perform(selector)?.takeUnretainedValue() as? String,
      !value.isEmpty
    {
      values.append(value)
    }
  }
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let children = object.responds(to: childrenSelector)
    ? object.perform(childrenSelector)?.takeUnretainedValue() as? [Any]
    : nil
  for child in children ?? [] {
    values.append(contentsOf: referenceAccessibilityStrings(in: child))
  }
  return values
}

@MainActor
private func referenceAccessibilityElement(in value: Any, label: String) -> NSObject? {
  guard let object = value as? NSObject else { return nil }
  let labelSelector = NSSelectorFromString("accessibilityLabel")
  if object.responds(to: labelSelector),
    object.perform(labelSelector)?.takeUnretainedValue() as? String == label
  {
    return object
  }
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let children = object.responds(to: childrenSelector)
    ? object.perform(childrenSelector)?.takeUnretainedValue() as? [Any]
    : nil
  for child in children ?? [] {
    if let found = referenceAccessibilityElement(in: child, label: label) {
      return found
    }
  }
  return nil
}
