import AppKit
import Testing

@testable import FleckApp

@Suite(.serialized) struct TextDragTests {
  @MainActor
  private func dragEditor(
    _ text: String,
    store: InlineNoteImageStore? = nil
  ) -> (ListAwareTextView, NSWindow) {
    let frame = NSRect(x: 0, y: 0, width: 360, height: 180)
    let textView = ListAwareTextView(frame: frame)
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = textView
    textView.isRichText = true
    textView.importsGraphics = false
    textView.inlineImageStore = store
    textView.allowsUndo = true
    textView.string = text
    return (textView, window)
  }

  @Test @MainActor func dragPasteboardCarriesNativeSelectionAsRichText() throws {
    let (source, window) = dragEditor("• note")
    defer { window.contentView = nil }
    let selection = NSRange(location: 2, length: 4)
    source.setSelectedRange(selection)
    source.textStorage?.addAttribute(
      .underlineStyle,
      value: NSUnderlineStyle.single.rawValue,
      range: selection
    )

    let dragPasteboard = NSPasteboard(name: .drag)
    _ = dragPasteboard.clearContents()
    defer { _ = dragPasteboard.clearContents() }
    #expect(source.writeSelection(to: dragPasteboard, types: source.writablePasteboardTypes))

    #expect(dragPasteboard.string(forType: .string) == "note")
    let draggedText = try NSAttributedString(
      data: #require(dragPasteboard.data(forType: .rtf)),
      options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: nil
    )
    #expect(draggedText.string == "note")
    let underline = draggedText.attribute(
      .underlineStyle,
      at: 0,
      effectiveRange: nil
    ) as? Int
    #expect(underline == NSUnderlineStyle.single.rawValue)
    #expect(source.selectedRange() == selection)
  }

  @Test @MainActor func clipboardStillExpandsWholeBulletSelection() {
    let (source, window) = dragEditor("• note")
    defer { window.contentView = nil }
    source.setSelectedRange(NSRange(location: 2, length: 4))

    let clipboard = NSPasteboard.withUniqueName()
    defer { clipboard.releaseGlobally() }
    #expect(source.writeSelection(to: clipboard, types: source.writablePasteboardTypes))
    #expect(clipboard.string(forType: .string) == "• note")
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["FLECK_NATIVE_CAPTURE_QA"] == "1"))
  @MainActor func selectedTextMovesThroughNativePointerDragWhenRequested() async throws {
    let original = "alpha bravo charlie\nsecond line"
    let (editor, window) = dragEditor(original)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    window.title = "FLEC-165 Synthetic Text Drag"
    window.setContentSize(NSSize(width: 620, height: 240))
    editor.autoresizingMask = [.width, .height]
    editor.font = .monospacedSystemFont(ofSize: 22, weight: .regular)
    editor.textContainerInset = NSSize(width: 24, height: 24)
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location: 6, length: 6))
    editor.undoManager?.removeAllActions()
    let deadline = Date().addingTimeInterval(90)
    while editor.string == original, Date() < deadline {
      try await Task.sleep(for: .milliseconds(200))
    }
    #expect(editor.string != original)
    #expect(editor.string == "alpha charlie\nsecond linebravo ")
    #expect(editor.undoManager?.canUndo == true)
    try await Task.sleep(for: .seconds(8))
    editor.undoManager?.undo()
    #expect(editor.string == original)
  }

  @Test @MainActor func dragPasteboardDropInsertsPlainTextAndUndoes() {
    let (destination, window) = dragEditor("one two")
    defer { window.contentView = nil }
    destination.setSelectedRange(NSRange(location: 4, length: 0))
    destination.undoManager?.removeAllActions()

    let dragPasteboard = NSPasteboard(name: .drag)
    _ = dragPasteboard.clearContents()
    defer { _ = dragPasteboard.clearContents() }
    _ = dragPasteboard.declareTypes([.string], owner: nil)
    #expect(dragPasteboard.setString("dragged ", forType: .string))

    #expect(destination.readSelection(from: dragPasteboard))
    #expect(destination.string == "one dragged two")
    #expect(destination.undoManager?.canUndo == true)
    destination.undoManager?.undo()
    #expect(destination.string == "one two")
  }

  @Test @MainActor func droppedPlainTextInsertsAtSelectionAndUndoes() {
    let (destination, window) = dragEditor("one two")
    defer { window.contentView = nil }
    destination.setSelectedRange(NSRange(location: 4, length: 0))
    destination.undoManager?.removeAllActions()

    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    _ = pasteboard.clearContents()
    _ = pasteboard.declareTypes([.string], owner: nil)
    #expect(pasteboard.setString("dragged ", forType: .string))

    #expect(destination.readSelection(from: pasteboard))
    #expect(destination.string == "one dragged two")
    #expect(NSMaxRange(destination.selectedRange()) == 12)
    #expect(destination.undoManager?.canUndo == true)
    destination.undoManager?.undo()
    #expect(destination.string == "one two")
  }

  @Test @MainActor func dragPasteboardCarriesManagedImageReferencesAndRestoresAttachments() throws {
    let fixture = try DragImageFixture()
    defer { fixture.remove() }
    let reference = try fixture.makeReference()
    let displayed = fixture.store.projectedContent(
      from: NSAttributedString(string: "• \(reference)")
    )
    let imageLocation = (displayed.string as NSString).range(of: "\u{fffc}").location
    try #require(imageLocation != NSNotFound)

    let (source, sourceWindow) = dragEditor("", store: fixture.store)
    defer { sourceWindow.contentView = nil }
    source.textStorage?.setAttributedString(displayed)
    let selection = NSRange(location: imageLocation, length: 1)
    source.setSelectedRange(selection)

    let dragPasteboard = NSPasteboard(name: .drag)
    _ = dragPasteboard.clearContents()
    defer { _ = dragPasteboard.clearContents() }
    #expect(source.writeSelection(to: dragPasteboard, types: source.writablePasteboardTypes))
    let payload = try #require(dragPasteboard.string(forType: .string))
    #expect(payload == reference)
    #expect(source.selectedRange() == selection)
    #expect(!payload.contains("\u{fffc}"))
    #expect(dragPasteboard.data(forType: .rtf) != nil)

    _ = dragPasteboard.clearContents()
    _ = dragPasteboard.declareTypes([.rtf, .string], owner: nil)
    #expect(source.writeSelection(to: dragPasteboard, type: .string))
    #expect(source.writeSelection(to: dragPasteboard, type: .rtf))
    #expect(dragPasteboard.string(forType: .string) == reference)
    #expect(dragPasteboard.data(forType: .rtf) != nil)
    #expect(source.selectedRange() == selection)

    let (destination, destinationWindow) = dragEditor("", store: fixture.store)
    defer { destinationWindow.contentView = nil }
    destination.setSelectedRange(NSRange(location: 0, length: 0))
    #expect(destination.readSelection(from: dragPasteboard))

    var insertedAttachment: InlineNoteImageAttachment?
    destination.textStorage?.enumerateAttribute(
      .attachment,
      in: NSRange(location: 0, length: destination.textStorage?.length ?? 0)
    ) { value, _, stop in
      guard let attachment = value as? InlineNoteImageAttachment else { return }
      insertedAttachment = attachment
      stop.pointee = true
    }
    #expect(insertedAttachment?.sourceReference == reference)
  }
}

@MainActor
private final class DragImageFixture {
  let root: URL
  let store: InlineNoteImageStore

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("FleckTextDrag-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = InlineNoteImageStore(
      rootURL: root.appendingPathComponent("managed", isDirectory: true)
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  func makeReference() throws -> String {
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 2,
      pixelsHigh: 2,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ))
    bitmap.setColor(.systemRed, atX: 0, y: 0)
    let imageURL = root.appendingPathComponent("synthetic.png")
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: imageURL)
    return try store.importImage(at: imageURL).reference
  }
}
