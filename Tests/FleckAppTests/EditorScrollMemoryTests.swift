import AppKit
import SwiftUI
import Testing

@testable import FleckApp

private struct ScrollMemoryNote: Equatable {
  let id: UUID
  var text: String
}

private struct ScrollMemoryHarness: View {
  let note: ScrollMemoryNote
  let commands: EditorCommands

  var body: some View {
    NativeRichTextEditor(
      text: note.text,
      richTextRTF: nil,
      noteID: note.id,
      onChange: { _, _ in },
      fontFamily: "Helvetica",
      fontSize: 16,
      reduceMotion: true,
      automaticLists: false,
      commands: commands
    )
    .id(note.id)
  }
}

private func longScrollMemoryBody() -> String {
  (1...120)
    .map { "Paragraph \($0) makes the note taller than the editor viewport." }
    .joined(separator: "\n")
}

@MainActor
private func hostedEditorScrollView(in view: NSView) -> NativeEditorScrollView? {
  if let scrollView = view as? NativeEditorScrollView { return scrollView }
  for subview in view.subviews {
    if let scrollView = hostedEditorScrollView(in: subview) { return scrollView }
  }
  return nil
}

@MainActor
private func settleScrollMemoryHost(_ view: NSView) async {
  for _ in 0..<8 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@MainActor
private func makeScrollMemoryWindow(host: NSView) -> NSWindow {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  return window
}

@MainActor
private func scrollEditor(_ scrollView: NSScrollView, to offset: CGFloat) {
  scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
  scrollView.reflectScrolledClipView(scrollView.contentView)
}

@Test @MainActor func scrollMemoryKeepsOneOffsetPerNote() {
  let memory = EditorScrollMemory()
  let first = UUID()
  let second = UUID()

  #expect(memory.offset(forNote: first) == nil)
  memory.remember(184, forNote: first)
  memory.remember(-40, forNote: second)
  memory.remember(72, forNote: nil)

  #expect(memory.offset(forNote: first) == 184)
  #expect(memory.offset(forNote: second) == 0)
  #expect(memory.offset(forNote: nil) == 72)
}

@Test @MainActor func scrolledLongNoteHoldsItsOffsetAcrossAnExternalTextChange() async throws {
  let commands = EditorCommands()
  let noteID = UUID()
  let body = longScrollMemoryBody()
  let host = NSHostingView(
    rootView: ScrollMemoryHarness(
      note: ScrollMemoryNote(id: noteID, text: body),
      commands: commands
    )
  )
  let window = makeScrollMemoryWindow(host: host)
  defer { window.orderOut(nil) }
  await settleScrollMemoryHost(host)

  let scrollView = try #require(hostedEditorScrollView(in: host))
  let documentHeight = try #require(scrollView.documentView?.bounds.height)
  #expect(documentHeight > scrollView.contentView.bounds.height * 3)

  scrollEditor(scrollView, to: 900)
  await settleScrollMemoryHost(host)
  let offsetBeforeReload = scrollView.contentView.bounds.origin.y
  #expect(abs(offsetBeforeReload - 900) < 1)

  host.rootView = ScrollMemoryHarness(
    note: ScrollMemoryNote(id: noteID, text: body + "\nAppended by the model."),
    commands: commands
  )
  await settleScrollMemoryHost(host)

  let offsetAfterReload = try #require(hostedEditorScrollView(in: host)).contentView.bounds.origin.y
  #expect(abs(offsetAfterReload - offsetBeforeReload) <= 16 * 1.6)
}

@Test @MainActor func switchingNotesAndBackRestoresTheNoteOffset() async throws {
  let commands = EditorCommands()
  let firstID = UUID()
  let secondID = UUID()
  let firstBody = longScrollMemoryBody()
  let secondBody = "Second note with one short paragraph."

  let host = NSHostingView(
    rootView: ScrollMemoryHarness(
      note: ScrollMemoryNote(id: firstID, text: firstBody),
      commands: commands
    )
  )
  let window = makeScrollMemoryWindow(host: host)
  defer { window.orderOut(nil) }
  await settleScrollMemoryHost(host)

  let firstScrollView = try #require(hostedEditorScrollView(in: host))
  scrollEditor(firstScrollView, to: 1200)
  await settleScrollMemoryHost(host)
  let rememberedOffset = firstScrollView.contentView.bounds.origin.y
  #expect(rememberedOffset > 100)

  host.rootView = ScrollMemoryHarness(
    note: ScrollMemoryNote(id: secondID, text: secondBody),
    commands: commands
  )
  await settleScrollMemoryHost(host)

  let secondScrollView = try #require(hostedEditorScrollView(in: host))
  #expect(secondScrollView !== firstScrollView)
  #expect(secondScrollView.contentView.bounds.origin.y < 1)

  host.rootView = ScrollMemoryHarness(
    note: ScrollMemoryNote(id: firstID, text: firstBody),
    commands: commands
  )
  await settleScrollMemoryHost(host)

  let restoredScrollView = try #require(hostedEditorScrollView(in: host))
  #expect(restoredScrollView !== secondScrollView)
  #expect(abs(restoredScrollView.contentView.bounds.origin.y - rememberedOffset) <= 16 * 1.6)
}

@Test @MainActor func shorterNoteClampsTheRememberedOffsetToItsContent() async throws {
  let commands = EditorCommands()
  let noteID = UUID()
  let host = NSHostingView(
    rootView: ScrollMemoryHarness(
      note: ScrollMemoryNote(id: noteID, text: longScrollMemoryBody()),
      commands: commands
    )
  )
  let window = makeScrollMemoryWindow(host: host)
  defer { window.orderOut(nil) }
  await settleScrollMemoryHost(host)

  let scrollView = try #require(hostedEditorScrollView(in: host))
  scrollEditor(scrollView, to: 1400)
  await settleScrollMemoryHost(host)
  #expect(abs(scrollView.contentView.bounds.origin.y - 1400) < 1)

  host.rootView = ScrollMemoryHarness(
    note: ScrollMemoryNote(id: noteID, text: "Short."),
    commands: commands
  )
  await settleScrollMemoryHost(host)

  let documentHeight = try #require(scrollView.documentView?.bounds.height)
  let visibleHeight = scrollView.contentView.bounds.height
  let offsetAfterReload = scrollView.contentView.bounds.origin.y
  #expect(offsetAfterReload >= 0)
  #expect(offsetAfterReload <= max(0, documentHeight - visibleHeight) + 0.5)
  #expect(offsetAfterReload < 1)
}

@Test @MainActor func reloadKeepsTheCaretVisibleWhenItWasOnScreen() async throws {
  let commands = EditorCommands()
  let noteID = UUID()
  let body = longScrollMemoryBody()
  let host = NSHostingView(
    rootView: ScrollMemoryHarness(
      note: ScrollMemoryNote(id: noteID, text: body),
      commands: commands
    )
  )
  let window = makeScrollMemoryWindow(host: host)
  defer { window.orderOut(nil) }
  await settleScrollMemoryHost(host)

  let scrollView = try #require(hostedEditorScrollView(in: host))
  let textView = try #require(scrollView.documentView.flatMap { $0 as? NativeEditorDocumentView })
    .textView
  scrollEditor(scrollView, to: 900)
  await settleScrollMemoryHost(host)

  let caretOffset = textView.layoutManager.flatMap { layoutManager -> Int? in
    guard let textContainer = textView.textContainer else { return nil }
    let point = NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y + 40)
    let containerPoint = NSPoint(
      x: point.x - textView.textContainerOrigin.x,
      y: point.y - textView.textContainerOrigin.y
    )
    return layoutManager.characterIndex(
      for: containerPoint,
      in: textContainer,
      fractionOfDistanceBetweenInsertionPoints: nil
    )
  }
  let caretLocation = try #require(caretOffset)
  textView.setSelectedRange(NSRange(location: caretLocation, length: 0))
  await settleScrollMemoryHost(host)
  let offsetBeforeReload = scrollView.contentView.bounds.origin.y

  let insertedAbove = (1...40)
    .map { "Inserted \($0)" }
    .joined(separator: "\n")
  host.rootView = ScrollMemoryHarness(
    note: ScrollMemoryNote(id: noteID, text: insertedAbove + "\n" + body),
    commands: commands
  )
  await settleScrollMemoryHost(host)

  let offsetAfterReload = scrollView.contentView.bounds.origin.y
  #expect(abs(offsetAfterReload - offsetBeforeReload) > 1)
  #expect(scrollView.isCaretVisible(in: textView))
}
