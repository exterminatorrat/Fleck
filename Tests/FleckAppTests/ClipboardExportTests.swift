import AppKit
import Testing

@testable import FleckApp

@Suite struct ClipboardExportTests {
  @MainActor
  private func clipboardEditor(_ text: String, selection: NSRange) -> ListAwareTextView {
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
    textView.isRichText = true
    textView.string = text
    textView.setSelectedRange(selection)
    return textView
  }

  @MainActor
  private func clipboardItem(_ text: String) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    let attributed = NSAttributedString(
      string: text,
      attributes: [.font: NSFont.systemFont(ofSize: 13)]
    )
    if let data = try? attributed.data(
      from: NSRange(location: 0, length: attributed.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    ) {
      _ = item.setData(data, forType: .rtf)
    }
    _ = item.setString(text, forType: .string)
    return item
  }

  @Test @MainActor func copyReplacesExistingClipboardWithSelectedPhrase() throws {
    let textView = clipboardEditor(
      "Previous paragraph\nselected phrase\nnext paragraph",
      selection: NSRange(location: 19, length: 15)
    )
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    _ = pasteboard.clearContents()
    #expect(pasteboard.writeObjects([clipboardItem("previous clipboard")]))

    #expect(textView.writeSelection(to: pasteboard, types: [.rtf, .string]))

    #expect(pasteboard.pasteboardItems?.count == 1)
    #expect(pasteboard.string(forType: .string) == "selected phrase")
    #expect(pasteboard.data(forType: .rtf) != nil)
  }

  @Test @MainActor func copyReplacesExistingClipboardForBulletSelection() throws {
    let textView = clipboardEditor("• note", selection: NSRange(location: 2, length: 4))
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    _ = pasteboard.clearContents()
    #expect(pasteboard.writeObjects([clipboardItem("previous clipboard")]))

    #expect(textView.writeSelection(to: pasteboard, types: [.rtf, .string]))

    #expect(pasteboard.pasteboardItems?.count == 1)
    #expect(pasteboard.string(forType: .string) == "• note")
    #expect(pasteboard.data(forType: .rtf) != nil)
  }

  @Test @MainActor func sequentialTypeWritesPreserveEveryFormat() throws {
    let textView = clipboardEditor("copy me", selection: NSRange(location: 0, length: 4))
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    _ = pasteboard.clearContents()
    _ = pasteboard.declareTypes([.rtf, .string], owner: nil)

    #expect(textView.writeSelection(to: pasteboard, type: .rtf))
    #expect(textView.writeSelection(to: pasteboard, type: .string))

    #expect(pasteboard.pasteboardItems?.count == 1)
    #expect(pasteboard.string(forType: .string) == "copy")
    #expect(pasteboard.data(forType: .rtf) != nil)
  }

  @Test @MainActor func declaredTextPasteboardTypesStillCopyTheSelection() throws {
    let textView = clipboardEditor("• note", selection: NSRange(location: 2, length: 4))
    let legacyTypes = textView.writablePasteboardTypes
    #expect(!legacyTypes.isEmpty)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    _ = pasteboard.clearContents()

    #expect(textView.writeSelection(to: pasteboard, types: legacyTypes))

    #expect(pasteboard.pasteboardItems?.count == 1)
    #expect(pasteboard.string(forType: .string) == "• note")
    #expect(pasteboard.data(forType: .rtf) != nil)
  }
}
