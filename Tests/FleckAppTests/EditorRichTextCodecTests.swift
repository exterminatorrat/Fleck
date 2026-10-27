import AppKit
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor func hostedEditorLoadsAndSavesRelativeTailIndentThroughCodec() async throws {
  let body = "👩🏽‍💻 Cafe\u{301} inline"
  let source = NSMutableAttributedString(string: body)
  let style = NSMutableParagraphStyle()
  style.tailIndent = -24
  source.addAttribute(
    .paragraphStyle,
    value: style,
    range: NSRange(location: 0, length: source.length)
  )
  let inlineRange = (body as NSString).range(of: "inline")
  source.addAttribute(
    .underlineStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: inlineRange
  )
  let richTextRTF = try NoteRichTextCodec.encode(source)
  let commands = EditorCommands()
  var savedBody: String?
  var savedRTF: Data?
  let editor = NativeRichTextEditor(
    text: body,
    richTextRTF: richTextRTF,
    onChange: { savedBody = $0; savedRTF = $1 },
    fontFamily: "Helvetica",
    fontSize: 17,
    reduceMotion: true,
    automaticLists: false,
    commands: commands
  )
  let host = NSHostingView(rootView: editor)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  defer { window.orderOut(nil) }
  await settleEditorHost(host)

  let textView = try #require(hostedEditorTextView(in: host))
  let storage = try #require(textView.textStorage)
  let loadedParagraph = try #require(
    storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(commands.textView === textView)
  #expect(textView.string.utf16.elementsEqual(body.utf16))
  #expect(loadedParagraph.tailIndent == -24)
  #expect(
    storage.attribute(.underlineStyle, at: inlineRange.location, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )

  let insertedText = "\nSaved 👨‍🚀"
  storage.append(
    NSAttributedString(string: insertedText, attributes: textView.typingAttributes)
  )
  let coordinator = try #require(textView.delegate as? NativeRichTextEditor.Coordinator)
  coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

  let expectedBody = body + insertedText
  #expect(savedBody?.utf16.elementsEqual(expectedBody.utf16) == true)
  let saved = try NoteRichTextCodec.decode(try #require(savedRTF))
  let savedParagraph = try #require(
    saved.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(saved.string.utf16.elementsEqual(expectedBody.utf16))
  #expect(savedParagraph.tailIndent == -24)
  #expect(
    saved.attribute(.underlineStyle, at: inlineRange.location, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
}

@Test @MainActor func hostedEditorFallsBackToPlainBodyForMalformedRTF() async throws {
  let body = "Synthetic fallback"
  let commands = EditorCommands()
  let editor = NativeRichTextEditor(
    text: body,
    richTextRTF: Data("malformed RTF".utf8),
    onChange: { _, _ in },
    fontFamily: "Helvetica",
    fontSize: 17,
    reduceMotion: true,
    automaticLists: false,
    commands: commands
  )
  let host = NSHostingView(rootView: editor)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  defer { window.orderOut(nil) }
  await settleEditorHost(host)

  let textView = try #require(hostedEditorTextView(in: host))
  #expect(commands.textView === textView)
  #expect(textView.string.utf16.elementsEqual(body.utf16))
}

@MainActor
private func hostedEditorTextView(in view: NSView) -> ListAwareTextView? {
  if let textView = view as? ListAwareTextView { return textView }
  for subview in view.subviews {
    if let textView = hostedEditorTextView(in: subview) { return textView }
  }
  return nil
}

@MainActor
private func settleEditorHost(_ view: NSView) async {
  for _ in 0..<5 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
