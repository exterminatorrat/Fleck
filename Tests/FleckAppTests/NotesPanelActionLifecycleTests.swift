import AppKit
import FleckCore
import Foundation
import SwiftUI
import Testing

@testable import FleckApp

@Suite("NotesPanelActionLifecycleTests")
@MainActor
struct NotesPanelActionLifecycleTests {
  @Test func folderAndTrashActionsUsePanelOwnedPresentation() throws {
    let source = try notesPanelSource()

    #expect(!source.contains(".confirmationDialog("))
    #expect(!source.contains(".sheet(isPresented: $isShowingTrash)"))
    #expect(source.contains("onConfirm: { confirmFolderDeletion(folderPendingDeletion) }"))
    #expect(source.contains("onDone: { isShowingTrash = false }"))
    #expect(
      source.contains(
        "|| notePendingDeletion != nil || folderPendingDeletion != nil || isShowingTrash"
      )
    )
  }

  @Test(arguments: [false, true])
  func folderDeleteAndCancelStayInsideOwningPanel(isPinned: Bool) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("notes-panel-folder-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try Folder(id: UUID(), name: "Work")
    let note = Note(title: "Filed", folderID: folder.id)
    let state = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _, _ in .committed }
    )
    await state.waitUntilInitialLoad()
    state.workspace = Workspace(
      notes: [note],
      selectedNoteID: note.id,
      folders: [folder]
    )

    var cancelCount = 0
    let (cancelWindow, cancelHost) = hostOverlay(
      AnyView(
        FolderDeleteConfirmationOverlay(
          folder: folder,
          onCancel: { cancelCount += 1 },
          onConfirm: { Issue.record("Cancel invoked Delete Folder") }
        )
      ),
      isPinned: isPinned
    )
    await settle(cancelHost)
    sendKey(.escape, to: cancelWindow)
    await settle(cancelHost)

    #expect(cancelCount == 1)
    #expect(state.workspace.folders == [folder])
    #expect(state.workspace.notes.first?.folderID == folder.id)
    #expect(cancelWindow.isVisible)
    cancelWindow.contentView = nil
    cancelWindow.orderOut(nil)

    var deleteCount = 0
    var deletionError: Error?
    let (deleteWindow, deleteHost) = hostOverlay(
      AnyView(
        FolderDeleteConfirmationOverlay(
          folder: folder,
          onCancel: { Issue.record("Delete Folder invoked Cancel") },
          onConfirm: {
            deleteCount += 1
            do {
              try state.deleteFolder(id: folder.id, activeFolderID: folder.id)
            } catch {
              deletionError = error
            }
          }
        )
      ),
      isPinned: isPinned
    )
    await settle(deleteHost)
    sendKey(.return, to: deleteWindow)
    await settle(deleteHost)

    #expect(deletionError == nil)
    #expect(deleteCount == 1)
    #expect(state.workspace.folders.isEmpty)
    #expect(state.workspace.notes.first?.folderID == nil)
    #expect(deleteWindow.isVisible)
    deleteWindow.contentView = nil
    deleteWindow.orderOut(nil)
  }

  @Test(arguments: [false, true])
  func trashRestoreAndDoneStayInsideOwningPanel(isPinned: Bool) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("notes-panel-trash-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let existing = Note(title: "Existing")
    let trashed = Note(title: "Restore once")
    let store = LocalStore(rootURL: root)
    try await store.save(
      workspace: Workspace(notes: [existing], selectedNoteID: existing.id),
      preferences: .init(),
      trashedNotes: [trashed]
    )
    let restoreCounter = InvocationCounter()
    let state = AppState(
      store: store,
      restoreOperation: { row, workspace, preferences, generation in
        await restoreCounter.record()
        return try await store.restore(
          row,
          into: workspace,
          preferences: preferences,
          generation: generation
        )
      }
    )
    await state.waitUntilInitialLoad()
    var doneCount = 0
    let (window, host) = hostOverlay(
      AnyView(
        TrashPanelOverlay(onDone: { doneCount += 1 })
          .environmentObject(state)
      ),
      isPinned: isPinned
    )
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    await settle(host)

    // SwiftUI does not publish button AX children in the SwiftPM host. The
    // button's native focus ring still gives us its real hit target.
    let restoreFocusRing = try #require(
      physicalDescendants(of: host).first(where: { view in
        String(describing: type(of: view)) == "_FocusRingView"
          && view.ancestorTypeName == "ListTableCellView"
      })
    )
    click(restoreFocusRing, in: window, root: host)
    await settle(host)

    #expect(window.isVisible)
    #expect(state.trashedNotes.isEmpty)
    #expect(state.workspace.notes.filter { $0.id == trashed.id }.count == 1)
    #expect(state.workspace.selectedNoteID == trashed.id)
    let restoreCount = await restoreCounter.value
    #expect(restoreCount == 1)
    let doneProxy = try #require(
      physicalDescendants(of: host).first {
        String(describing: type(of: $0)) == "KeyViewProxy"
      }
    )
    click(doneProxy, in: window, root: host)
    await settle(host)

    #expect(window.isVisible)
    #expect(doneCount == 1)
  }
}

private actor InvocationCounter {
  private var count = 0

  func record() {
    count += 1
  }

  var value: Int { count }
}

private func notesPanelSource() throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
}

@MainActor
private func hostOverlay(
  _ rootView: AnyView,
  isPinned: Bool
) -> (NSWindow, NSHostingView<AnyView>) {
  let host = NSHostingView(rootView: rootView)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: isPinned ? [.titled] : [.borderless],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  return (window, host)
}

@MainActor
private func physicalDescendants(of view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap(physicalDescendants)
}

private extension NSView {
  var ancestorTypeName: String? {
    var ancestor = superview
    while let current = ancestor {
      let name = String(describing: type(of: current))
      if name == "ListTableCellView" { return name }
      ancestor = current.superview
    }
    return nil
  }
}

@MainActor
private func click(_ view: NSView, in window: NSWindow, root: NSView) {
  guard let superview = view.superview else { return }
  let frame = superview.convert(view.frame, to: root)
  let location = root.convert(
    NSPoint(x: frame.midX, y: frame.midY),
    to: nil
  )
  for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    guard let event = NSEvent.mouseEvent(
      with: type,
      location: location,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: type == .leftMouseDown ? 1 : 0
    ) else { continue }
    window.sendEvent(event)
  }
}

@MainActor
private func sendKey(_ key: KeyboardKey, to window: NSWindow) {
  let characters: String
  let keyCode: UInt16
  switch key {
  case .escape:
    characters = "\u{1b}"
    keyCode = 53
  case .return:
    characters = "\r"
    keyCode = 36
  }
  guard let event = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: window.windowNumber,
    context: nil,
    characters: characters,
    charactersIgnoringModifiers: characters,
    isARepeat: false,
    keyCode: keyCode
  ) else { return }
  window.sendEvent(event)
}

private enum KeyboardKey {
  case escape
  case `return`
}

@MainActor
private func settle(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
