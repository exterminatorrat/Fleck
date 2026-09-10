import AppKit
import Combine
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
    let trashSource = try trashViewSource()

    #expect(!source.contains(".confirmationDialog("))
    #expect(!source.contains(".sheet(isPresented: $isShowingTrash)"))
    #expect(!trashSource.contains(".frame(minWidth: 440, minHeight: 320)"))
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
      hostCase: PanelHostCase(
        isPinned: isPinned,
        size: NSSize(width: 640, height: 430)
      )
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
      hostCase: PanelHostCase(
        isPinned: isPinned,
        size: NSSize(width: 640, height: 430)
      )
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

  @Test(arguments: PanelHostCase.all)
  func trashRestoreAndDoneStayInsideOwningPanel(hostCase: PanelHostCase) async throws {
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
    let restoreCompletion = AsyncStream<Void>.makeStream()
    defer { restoreCompletion.continuation.finish() }
    let restoreRelease = Gate()
    let state = AppState(
      store: store,
      restoreOperation: { row, workspace, preferences, generation in
        await restoreCounter.record()
        let outcome = try await store.restore(
          row,
          into: workspace,
          preferences: preferences,
          generation: generation
        )
        restoreCompletion.continuation.yield(())
        restoreCompletion.continuation.finish()
        await restoreRelease.wait()
        return outcome
      }
    )
    await state.waitUntilInitialLoad()
    var doneCount = 0
    let initialTrashRefresh = TrashPublicationProbe(state: state)
    let (window, host) = hostOverlay(
      AnyView(
        TrashPanelOverlay(onDone: { doneCount += 1 })
          .environmentObject(state)
      ),
      hostCase: hostCase
    )
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    let refreshedTrash = await initialTrashRefresh.next(timeout: .seconds(1))
    #expect(refreshedTrash?.map(\.id) == [trashed.id])
    await settle(host)

    let cardFrame = try #require(
      descendants(in: host, as: NSVisualEffectView.self)
        .map { material in
          material.superview?.convert(material.frame, to: host) ?? material.frame
        }
        .max { $0.width * $0.height < $1.width * $1.height }
    )
    #expect(host.bounds.contains(cardFrame))
    #expect(host.fittingSize.width <= host.bounds.width + 0.5)
    #expect(host.fittingSize.height <= host.bounds.height + 0.5)

    let trashList = try #require(
      descendants(in: host, as: NSOutlineView.self).first { $0.numberOfRows == 1 }
    )
    let row = try #require(trashList.view(atColumn: 0, row: 0, makeIfNecessary: false))
    click(
      at: row.convert(
        NSPoint(x: row.bounds.maxX - 35, y: row.bounds.midY),
        to: host
      ),
      in: window,
      root: host
    )
    let completedTrashRefresh = TrashPublicationProbe(state: state)
    let restoreReachedCompletion = await firstValue(
      from: restoreCompletion.stream,
      timeout: .seconds(1)
    ) != nil
    #expect(restoreReachedCompletion)
    await restoreRelease.openGate()
    let completedTrash = await completedTrashRefresh.next(timeout: .seconds(1))
    #expect(completedTrash?.isEmpty == true)
    await settle(host)

    #expect(window.isVisible)
    #expect(state.trashedNotes.isEmpty)
    #expect(state.workspace.notes.filter { $0.id == trashed.id }.count == 1)
    #expect(state.workspace.selectedNoteID == trashed.id)
    let restoreCount = await restoreCounter.value
    #expect(restoreCount == 1)
    sendKey(.return, to: window)
    await settle(host)

    #expect(window.isVisible)
    #expect(doneCount == 1)
  }

  @Test(arguments: PanelHostCase.all)
  func trashEscapeClosesOnlyTheOverlay(hostCase: PanelHostCase) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("notes-panel-trash-escape-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(store: LocalStore(rootURL: root))
    await state.waitUntilInitialLoad()
    var doneCount = 0
    let (window, host) = hostOverlay(
      AnyView(
        TrashPanelOverlay(onDone: { doneCount += 1 })
          .environmentObject(state)
      ),
      hostCase: hostCase
    )
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    await settle(host)
    sendKey(.escape, to: window)
    await settle(host)

    #expect(doneCount == 1)
    #expect(window.isVisible)
  }
}

private actor InvocationCounter {
  private var count = 0

  func record() {
    count += 1
  }

  var value: Int { count }
}

@MainActor
private final class TrashPublicationProbe {
  private let stream: AsyncStream<[TrashedNote]>
  private let continuation: AsyncStream<[TrashedNote]>.Continuation
  private var observation: AnyCancellable?

  init(state: AppState) {
    let publications = AsyncStream<[TrashedNote]>.makeStream()
    stream = publications.stream
    continuation = publications.continuation
    var isInitialPublication = true
    observation = state.$trashedNotes.sink { notes in
      if isInitialPublication {
        isInitialPublication = false
      } else {
        publications.continuation.yield(notes)
      }
    }
  }

  func next(timeout: Duration) async -> [TrashedNote]? {
    defer {
      observation?.cancel()
      continuation.finish()
    }
    return await firstValue(from: stream, timeout: timeout)
  }
}

private func firstValue<Element: Sendable>(
  from stream: AsyncStream<Element>,
  timeout: Duration
) async -> Element? {
  await withTaskGroup(of: Element?.self, returning: Element?.self) { group in
    group.addTask {
      var iterator = stream.makeAsyncIterator()
      return await iterator.next()
    }
    group.addTask {
      try? await Task.sleep(for: timeout)
      return nil
    }
    let first = await group.next() ?? nil
    group.cancelAll()
    return first
  }
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

private func trashViewSource() throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/TrashView.swift"),
    encoding: .utf8
  )
}

struct PanelHostCase: Sendable {
  let isPinned: Bool
  let size: NSSize

  static let all = [
    PanelHostCase(isPinned: false, size: NSSize(width: 380, height: 300)),
    PanelHostCase(isPinned: true, size: NSSize(width: 480, height: 320)),
    PanelHostCase(isPinned: false, size: NSSize(width: 640, height: 430)),
    PanelHostCase(isPinned: true, size: NSSize(width: 640, height: 430)),
  ]
}

@MainActor
private func hostOverlay(
  _ rootView: AnyView,
  hostCase: PanelHostCase
) -> (NSWindow, NSHostingView<AnyView>) {
  let host = NSHostingView(rootView: rootView)
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: hostCase.size),
    styleMask: hostCase.isPinned ? [.titled] : [.borderless],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  return (window, host)
}

@MainActor
private func descendants<T: NSView>(in view: NSView, as type: T.Type) -> [T] {
  var result = view as? T == nil ? [] : [view as! T]
  for subview in view.subviews {
    result.append(contentsOf: descendants(in: subview, as: type))
  }
  return result
}

@MainActor
private func click(at point: NSPoint, in window: NSWindow, root: NSView) {
  let location = root.convert(
    point,
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
