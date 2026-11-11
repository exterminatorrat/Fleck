import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor
func collapsedCaretFormattingPreservesNoteLinkPresentationAcrossAnUnchangedUpdate() async throws {
  let liveNoteID = UUID()
  let missingNoteID = UUID()
  let liveToken = NoteLinkFormatter.markdown(label: "Live", targetNoteID: liveNoteID)
  let missingToken = NoteLinkFormatter.markdown(label: "Missing", targetNoteID: missingNoteID)
  let text = "Lead \(liveToken) mid \(missingToken) tail"

  let fixture = try await makeNoteLinkCaretFixture(text: text, liveNoteIDs: [liveNoteID])
  defer { fixture.close() }

  let textView = fixture.textView
  let layoutManager = try #require(textView.layoutManager)
  let links = NoteLinkParser.links(in: text)
  try #require(links.count == 2)
  let liveLink = try #require(links.first { $0.targetNoteID == liveNoteID })
  let missingLink = try #require(links.first { $0.targetNoteID == missingNoteID })
  try #require(textView.string == text)

  try #require(fixture.window.makeFirstResponder(textView))
  let caret = NSRange(location: 2, length: 0)
  textView.setSelectedRange(caret)
  #expect(textView.selectedRange() == caret)

  let livePresentation = noteLinkCaretPresentation(layoutManager, in: liveLink.range)
  let missingPresentation = noteLinkCaretPresentation(layoutManager, in: missingLink.range)
  #expect(livePresentation.allSatisfy { $0.underline == NSUnderlineStyle.single.rawValue })
  #expect(
    missingPresentation.allSatisfy {
      $0.underline == NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
    }
  )
  #expect(livePresentation.allSatisfy { $0.foreground != nil })
  #expect(missingPresentation.allSatisfy { $0.foreground != nil })
  #expect(livePresentation.first?.foreground != missingPresentation.first?.foreground)
  #expect(
    (textView.textStorage?.attribute(
      .underlineStyle,
      at: liveLink.range.location,
      effectiveRange: nil
    ) as? Int) == nil
  )

  let storageBefore = NSAttributedString(
    attributedString: textView.textStorage ?? NSTextStorage()
  )
  let typingFontBefore = textView.typingAttributes[.font] as? NSFont
  #expect(
    typingFontBefore.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == false
  )
  let undoManager = try #require(textView.undoManager)
  undoManager.removeAllActions()

  fixture.commands.toggleBold()
  fixture.commands.applyForegroundColor(.systemRed)
  fixture.commands.applyBackgroundColor(.systemYellow)
  fixture.commands.toggleUnderline()
  fixture.commands.toggleStrikethrough()

  expectCollapsedCaretFormattingState(in: textView)
  expectUnchangedEditorContent(
    textView: textView,
    storageBefore: storageBefore,
    caret: caret,
    undoManager: undoManager,
    text: text,
    changeRecorder: fixture.changeRecorder
  )

  fixture.driver.reduceMotion = true
  try await waitForCachedPresentationUpdate(fixture.host) { textView.reduceMotion }
  #expect(textView.reduceMotion)
  #expect(noteLinkCaretEditor(in: fixture.host) === textView)

  #expect(noteLinkCaretPresentation(layoutManager, in: liveLink.range) == livePresentation)
  #expect(noteLinkCaretPresentation(layoutManager, in: missingLink.range) == missingPresentation)
  expectCollapsedCaretFormattingState(in: textView)
  expectUnchangedEditorContent(
    textView: textView,
    storageBefore: storageBefore,
    caret: caret,
    undoManager: undoManager,
    text: text,
    changeRecorder: fixture.changeRecorder
  )
}

@MainActor
private func expectUnchangedEditorContent(
  textView: ListAwareTextView,
  storageBefore: NSAttributedString,
  caret: NSRange,
  undoManager: UndoManager,
  text: String,
  changeRecorder: NoteLinkCaretChangeRecorder
) {
  #expect(textView.selectedRange() == caret)
  #expect(textView.string == text)
  #expect(storageBefore.isEqual(to: textView.textStorage ?? NSTextStorage()))
  #expect(!undoManager.canUndo)
  #expect(!undoManager.canRedo)
  #expect(changeRecorder.changeCount == 0)
}

@MainActor
private func expectCollapsedCaretFormattingState(in textView: ListAwareTextView) {
  let font = textView.typingAttributes[.font] as? NSFont
  #expect(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)
  #expect(
    noteLinkSRGB(textView.typingAttributes[.foregroundColor] as? NSColor)
      == noteLinkSRGB(NSColor.systemRed)
  )
  #expect(
    noteLinkSRGB(textView.typingAttributes[.backgroundColor] as? NSColor)
      == noteLinkSRGB(NSColor.systemYellow)
  )
  #expect(
    (textView.typingAttributes[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
  )
  #expect(
    (textView.typingAttributes[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue
  )
}

private struct NoteLinkCaretPresentation: Equatable {
  let foreground: [Int]?
  let underline: Int?
}

private func noteLinkSRGB(_ color: NSColor?) -> [Int]? {
  guard let color = color?.usingColorSpace(.sRGB) else { return nil }
  return [
    Int((color.redComponent * 255).rounded()),
    Int((color.greenComponent * 255).rounded()),
    Int((color.blueComponent * 255).rounded()),
    Int((color.alphaComponent * 255).rounded()),
  ]
}

@MainActor
private func noteLinkCaretPresentation(
  _ layoutManager: NSLayoutManager,
  in range: NSRange
) -> [NoteLinkCaretPresentation] {
  (0..<range.length).map { offset in
    let index = range.location + offset
    return NoteLinkCaretPresentation(
      foreground: noteLinkSRGB(
        layoutManager.temporaryAttribute(
          .foregroundColor,
          atCharacterIndex: index,
          effectiveRange: nil
        ) as? NSColor
      ),
      underline: layoutManager.temporaryAttribute(
        .underlineStyle,
        atCharacterIndex: index,
        effectiveRange: nil
      ) as? Int
    )
  }
}

@MainActor
private final class NoteLinkCaretChangeRecorder {
  private(set) var changeCount = 0

  func recordChange() {
    changeCount += 1
  }
}

@MainActor
private final class NoteLinkCaretPresentationDriver: ObservableObject {
  @Published var reduceMotion = false
}

@MainActor
private struct NoteLinkCaretEditorHost: View {
  @ObservedObject var driver: NoteLinkCaretPresentationDriver
  let text: String
  let commands: EditorCommands
  let liveNoteIDs: Set<UUID>
  let changeRecorder: NoteLinkCaretChangeRecorder

  var body: some View {
    NativeRichTextEditor(
      text: text,
      richTextRTF: nil,
      onChange: { _, _ in changeRecorder.recordChange() },
      fontFamily: NSFont.systemFont(ofSize: 14).familyName ?? "Helvetica",
      fontSize: 14,
      reduceMotion: driver.reduceMotion,
      automaticLists: false,
      commands: commands,
      liveNoteIDs: liveNoteIDs
    )
  }
}

@MainActor
private struct NoteLinkCaretFixture {
  let window: NSWindow
  let host: NSHostingView<AnyView>
  let textView: ListAwareTextView
  let commands: EditorCommands
  let driver: NoteLinkCaretPresentationDriver
  let changeRecorder: NoteLinkCaretChangeRecorder

  func close() {
    window.makeFirstResponder(nil)
    window.orderOut(nil)
    window.contentView = nil
    window.close()
  }
}

private enum NoteLinkCaretFixtureError: Error {
  case editorNotReady
  case cachedPresentationUpdateNotDelivered
}

@MainActor
private func makeNoteLinkCaretFixture(
  text: String,
  liveNoteIDs: Set<UUID>
) async throws -> NoteLinkCaretFixture {
  let commands = EditorCommands()
  let driver = NoteLinkCaretPresentationDriver()
  let changeRecorder = NoteLinkCaretChangeRecorder()
  let host = NSHostingView(
    rootView: AnyView(
      NoteLinkCaretEditorHost(
        driver: driver,
        text: text,
        commands: commands,
        liveNoteIDs: liveNoteIDs,
        changeRecorder: changeRecorder
      )
    )
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.isReleasedWhenClosed = false
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  do {
    let textView = try await waitForNoteLinkCaretEditor(host, text: text)
    return NoteLinkCaretFixture(
      window: window,
      host: host,
      textView: textView,
      commands: commands,
      driver: driver,
      changeRecorder: changeRecorder
    )
  } catch {
    window.orderOut(nil)
    window.contentView = nil
    window.close()
    throw error
  }
}

@MainActor
private func waitForNoteLinkCaretEditor(
  _ host: NSHostingView<AnyView>,
  text: String
) async throws -> ListAwareTextView {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(5))
  while clock.now < deadline {
    host.layoutSubtreeIfNeeded()
    if let textView = noteLinkCaretEditor(in: host),
      textView.string == text,
      let layoutManager = textView.layoutManager,
      NoteLinkParser.links(in: text).allSatisfy({
        layoutManager.temporaryAttribute(
          .underlineStyle,
          atCharacterIndex: $0.range.location,
          effectiveRange: nil
        ) != nil
      })
    {
      return textView
    }
    await Task.yield()
    try await Task.sleep(for: .milliseconds(10))
  }
  throw NoteLinkCaretFixtureError.editorNotReady
}

@MainActor
private func waitForCachedPresentationUpdate(
  _ host: NSHostingView<AnyView>,
  until condition: @MainActor () -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(5))
  while clock.now < deadline {
    host.layoutSubtreeIfNeeded()
    if condition() { return }
    await Task.yield()
    try await Task.sleep(for: .milliseconds(10))
  }
  throw NoteLinkCaretFixtureError.cachedPresentationUpdateNotDelivered
}

@MainActor
private func noteLinkCaretEditor(in view: NSView) -> ListAwareTextView? {
  if let textView = view as? ListAwareTextView { return textView }
  for subview in view.subviews {
    if let textView = noteLinkCaretEditor(in: subview) { return textView }
  }
  return nil
}
