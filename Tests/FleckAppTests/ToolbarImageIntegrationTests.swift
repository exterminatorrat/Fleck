import AppKit
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor
func toolbarUnicodeCaseAcrossProjectedImagePreservesReferenceAndSelection() throws {
  let fixture = try ToolbarImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.importImage(named: "unicode-case.png")
  let canonical = "straße \(reference) e\u{301}lan"
  let editor = fixture.editor(canonical: NSAttributedString(string: canonical))
  let commands = fixture.commands(for: editor)
  editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))

  #expect(commands.transformCase(.uppercase))

  let canonicalExpanded = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  #expect(canonicalExpanded.string == "STRASSE \(reference) E\u{301}LAN")
  #expect(editor.selectedRange() == NSRange(location: 0, length: editor.string.utf16.count))
  try expectOneProjectedImage(
    in: editor,
    canonical: "STRASSE \(reference) E\u{301}LAN",
    canonicalReference: reference
  )
  let expanded = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  let data = try expanded.data(
    from: NSRange(location: 0, length: expanded.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let restored = try NSAttributedString(
    data: data,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(restored.string == "STRASSE \(reference) E\u{301}LAN")
  let reprojected = fixture.store.projectedContent(from: restored)
  #expect(InlineNoteImageProjection.expanded(reprojected).string == restored.string)
  #expect(reprojected.attribute(.attachment, at: 8, effectiveRange: nil) is InlineNoteImageAttachment)
}

@Test @MainActor
func toolbarClearAndFormatPainterPreserveProjectedAttachmentReferenceAndLink() throws {
  let fixture = try ToolbarImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.importImage(named: "format-painter.png")
  let canonical = "Source \(reference) target"
  let source = NSMutableAttributedString(string: canonical)
  let sourceRange = (canonical as NSString).range(of: "Source")
  let targetRange = (canonical as NSString).range(of: "target")
  let sourceFont = try #require(NSFont(name: "Courier-Bold", size: 23))
  let targetURL = try #require(URL(string: "https://example.com/target"))
  source.addAttributes(
    [.font: sourceFont, .backgroundColor: NSColor.systemYellow],
    range: sourceRange
  )
  source.addAttribute(.link, value: targetURL, range: targetRange)
  let editor = fixture.editor(canonical: source)
  let commands = fixture.commands(for: editor)

  let displaySourceRange = (editor.string as NSString).range(of: "Source")
  editor.setSelectedRange(displaySourceRange)
  #expect(commands.copyFormatting())
  let attachmentLocation = (editor.string as NSString).range(of: "\u{fffc}").location
  let displayTargetRange = (editor.string as NSString).range(of: "target")
  editor.setSelectedRange(NSRange(
    location: attachmentLocation,
    length: NSMaxRange(displayTargetRange) - attachmentLocation
  ))
  #expect(commands.pasteFormatting())
  #expect(
    editor.textStorage?.attribute(.attachment, at: attachmentLocation, effectiveRange: nil)
      is InlineNoteImageAttachment
  )
  #expect(editor.textStorage?.attribute(.link, at: displayTargetRange.location, effectiveRange: nil) as? URL == targetURL)
  #expect(
    (editor.textStorage?.attribute(.font, at: attachmentLocation, effectiveRange: nil) as? NSFont)?
      .fontName == sourceFont.fontName
  )

  #expect(commands.clearTextFormatting())
  #expect(editor.textStorage?.attribute(.link, at: displayTargetRange.location, effectiveRange: nil) as? URL == targetURL)
  try expectOneProjectedImage(
    in: editor,
    canonical: canonical,
    canonicalReference: reference
  )
}

@Test @MainActor
func toolbarParagraphStyleWithProjectedImagePreservesChecklistLayoutDelegate() throws {
  let fixture = try ToolbarImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.importImage(named: "checklist-paragraph.png")
  let canonical = "○ Review \(reference) inline\nFollowing paragraph"
  let editor = fixture.editor(canonical: NSAttributedString(string: canonical))
  let commands = fixture.commands(for: editor)
  let firstParagraph = (editor.string as NSString).paragraphRange(
    for: NSRange(location: 0, length: 0)
  )
  editor.setSelectedRange(firstParagraph)

  #expect(commands.applyAlignment(.right))
  #expect(commands.applyLineSpacing(.oneAndHalf))
  #expect(commands.applyParagraphSpacingAfter(12))

  let attachmentLocation = (editor.string as NSString).range(of: "\u{fffc}").location
  let style = try #require(
    editor.textStorage?.attribute(.paragraphStyle, at: attachmentLocation, effectiveRange: nil)
      as? NSParagraphStyle
  )
  #expect(style.alignment == .right)
  #expect(abs(style.lineHeightMultiple - 1.5) < 0.01)
  #expect(style.paragraphSpacing == 12)
  #expect(EditorListEngine.parse("○ Review \u{fffc} inline")?.style == .checklist)
  #expect(editor.layoutManager?.delegate === editor)
  try expectOneProjectedImage(
    in: editor,
    canonical: canonical,
    canonicalReference: reference
  )
}

@Test @MainActor
func toolbarLinksNearProjectedImagePreserveReferenceAndRejectStaleTargets() throws {
  let fixture = try ToolbarImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.importImage(named: "link-targets.png")
  let canonical = "Before \(reference) after"
  let editor = fixture.editor(canonical: NSAttributedString(string: canonical))
  let commands = fixture.commands(for: editor)
  let note = Note(title: "Image links", body: canonical, revision: 4)

  let afterRange = (editor.string as NSString).range(of: "after")
  editor.setSelectedRange(afterRange)
  let webTarget = try #require(EditorWebLinkTarget(note: note, commands: commands))
  #expect(
    webTarget.apply(
      urlText: "https://example.com/after",
      displayText: nil,
      note: note,
      isEditorVisible: true,
      commands: commands
    )
  )
  #expect(
    editor.textStorage?.attribute(.link, at: afterRange.location, effectiveRange: nil) as? URL
      == URL(string: "https://example.com/after")
  )

  let beforeRange = (editor.string as NSString).range(of: "Before")
  editor.setSelectedRange(beforeRange)
  let staleWebTarget = try #require(EditorWebLinkTarget(note: note, commands: commands))
  var revisedNote = note
  revisedNote.revision += 1
  #expect(
    !staleWebTarget.apply(
      urlText: "https://example.com/stale",
      displayText: nil,
      note: revisedNote,
      isEditorVisible: true,
      commands: commands
    )
  )
  #expect(editor.textStorage?.attribute(.link, at: beforeRange.location, effectiveRange: nil) == nil)

  let noteTarget = try #require(
    EditorNoteLinkTarget(note: note, range: beforeRange, commands: commands)
  )
  commands.areBodyCommandsBlocked = true
  editor.isEditable = false
  editor.isSelectable = false
  #expect(noteTarget.capturePickerBlock(commands: commands))
  #expect(
    noteTarget.isValidAfterPickerDismissal(
      note: note,
      isEditorVisible: true,
      commands: commands
    )
  )
  #expect(
    noteTarget.isValidAfterPickerDismissal(
      note: note,
      isEditorVisible: true,
      commands: commands
    )
  )
  commands.areBodyCommandsBlocked = false
  editor.isEditable = true
  editor.isSelectable = true
  let targetID = UUID()
  #expect(
    noteTarget.apply(
      label: "Destination",
      targetNoteID: targetID,
      commands: commands
    )
  )
  let insertedLink = NoteLinkFormatter.markdown(label: "Destination", targetNoteID: targetID)
  let linkedCanonical = canonical.replacingOccurrences(of: "Before", with: insertedLink)
  #expect(InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string == linkedCanonical)

  let afterDisplayRange = (editor.string as NSString).range(of: "after")
  editor.setSelectedRange(afterDisplayRange)
  let staleTarget = try #require(
    EditorNoteLinkTarget(note: note, range: afterDisplayRange, commands: commands)
  )
  commands.areBodyCommandsBlocked = true
  editor.isEditable = false
  editor.isSelectable = false
  #expect(staleTarget.capturePickerBlock(commands: commands))
  #expect(
    !staleTarget.isValidAfterPickerDismissal(
      note: revisedNote,
      isEditorVisible: true,
      commands: commands
    )
  )
  commands.areBodyCommandsBlocked = false
  editor.isEditable = true
  editor.isSelectable = true
  #expect(
    !staleTarget.apply(
      label: "Stale",
      targetNoteID: UUID(),
      commands: commands
    )
  )
  #expect(InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string == linkedCanonical)
  try expectOneProjectedImage(
    in: editor,
    canonical: linkedCanonical,
    canonicalReference: reference
  )
}

@Test @MainActor
func webLinksRefuseEveryImageBearingSelectionWithoutUndoOrCanonicalCorruption() throws {
  let fixture = try ToolbarImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.importImage(named: "web-link-refusal.png")
  let canonical = "Before \(reference) after"
  let replacementURL = try #require(URL(string: "https://example.com/replacement"))
  let oldURL = try #require(URL(string: "https://example.com/old"))

  for imagePosition in ["leading", "middle"] {
    for changedLabel in [false, true] {
      for editingExistingLink in [false, true] {
        let editor = fixture.editor(canonical: NSAttributedString(string: canonical))
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
          styleMask: [.titled],
          backing: .buffered,
          defer: false
        )
        window.contentView = editor
        defer { window.orderOut(nil) }
        let commands = fixture.commands(for: editor)
        let attachmentLocation = (editor.string as NSString).range(of: "\u{fffc}").location
        let selection: NSRange
        if imagePosition == "leading" {
          selection = NSRange(
            location: attachmentLocation,
            length: editor.string.utf16.count - attachmentLocation
          )
        } else {
          selection = NSRange(location: 0, length: editor.string.utf16.count)
        }
        if editingExistingLink {
          editor.textStorage?.addAttribute(.link, value: oldURL, range: selection)
        }
        editor.setSelectedRange(selection)
        let note = Note(title: "Image", body: canonical, revision: 2)
        let before = NSAttributedString(attributedString: try #require(editor.textStorage))
        let beforeSelection = editor.selectedRange()
        let undoManager = try #require(editor.undoManager)
        undoManager.removeAllActions()

        #expect(EditorWebLinkTarget(note: note, commands: commands) == nil)
        #expect(!commands.applyWebLink(
          url: replacementURL,
          range: selection,
          displayText: changedLabel ? "Changed label" : nil,
          expectedTextView: editor,
          expectedStorage: try #require(editor.textStorage)
        ))
        #expect(try #require(editor.textStorage).isEqual(to: before))
        #expect(editor.selectedRange() == beforeSelection)
        #expect(!undoManager.canUndo)
        #expect(InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string == canonical)

        let expanded = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
        let data = try expanded.data(
          from: NSRange(location: 0, length: expanded.length),
          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let restored = try NSAttributedString(
          data: data,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
        )
        #expect(restored.string == canonical)
        let reprojected = fixture.store.projectedContent(from: restored)
        #expect(InlineNoteImageProjection.expanded(reprojected).string == canonical)
        #expect(reprojected.attribute(
          .attachment,
          at: attachmentLocation,
          effectiveRange: nil
        ) is InlineNoteImageAttachment)
      }
    }
  }
}

@Test @MainActor
func caretWebLinkDropsAttachmentTypingAttributeAndPreservesCanonicalImage() throws {
  let fixture = try ToolbarImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.importImage(named: "caret-link.png")
  let projectedReference = fixture.store.projectedContent(
    from: NSAttributedString(string: reference)
  )
  let attachment = try #require(
    projectedReference.attribute(.attachment, at: 0, effectiveRange: nil)
      as? InlineNoteImageAttachment
  )
  let editor = fixture.editor(canonical: NSAttributedString(string: ""))
  let commands = fixture.commands(for: editor)
  editor.typingAttributes[.attachment] = attachment
  editor.setSelectedRange(NSRange(location: 0, length: 0))
  let url = try #require(URL(string: "https://example.com/caret"))

  #expect(commands.applyWebLink(
    url: url,
    range: editor.selectedRange(),
    displayText: "Caret link",
    expectedTextView: editor,
    expectedStorage: try #require(editor.textStorage)
  ))
  #expect(editor.string == "Caret link")
  #expect(editor.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
  #expect(editor.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == url)
  #expect(InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string == "Caret link")
}

@Test @MainActor
func toolbarCanonicalRTFSaveReloadAndUndoRedoPreserveProjectedImage() throws {
  let fixture = try ToolbarImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.importImage(named: "canonical-save.png")
  let canonical = "Before \(reference) after"
  let editor = fixture.editor(canonical: NSAttributedString(string: canonical))
  let commands = fixture.commands(for: editor)
  var savedBody: String?
  var savedRTF: Data?
  let bridge = fixture.nativeEditor(
    text: canonical,
    commands: commands,
    onChange: { savedBody = $0; savedRTF = $1 }
  )
  let coordinator = bridge.makeCoordinator()
  editor.delegate = coordinator
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = editor
  defer { window.orderOut(nil) }
  #expect(window.makeFirstResponder(editor))
  editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
  editor.undoManager?.removeAllActions()
  let before = NSAttributedString(attributedString: try #require(editor.textStorage))
  let beforeSelection = editor.selectedRange()

  #expect(commands.applyTextStyle(.heading2))
  let after = NSAttributedString(attributedString: try #require(editor.textStorage))
  let afterSelection = editor.selectedRange()
  #expect(!after.isEqual(to: before))
  #expect(afterSelection == beforeSelection)
  #expect(editor.undoManager?.canUndo == true)
  #expect(savedBody == canonical)
  let appliedRTF = try #require(savedRTF)
  let decoded = try NSAttributedString(
    data: appliedRTF,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(decoded.string == canonical)
  let reloaded = fixture.store.projectedContent(from: decoded)
  #expect(reloaded.attribute(.attachment, at: 7, effectiveRange: nil) is InlineNoteImageAttachment)
  #expect(InlineNoteImageProjection.expanded(reloaded).string == canonical)

  commands.undo()
  #expect(try #require(editor.textStorage).isEqual(to: before))
  #expect(editor.selectedRange() == beforeSelection)
  #expect(editor.undoManager?.canRedo == true)
  try expectOneProjectedImage(
    in: editor,
    canonical: canonical,
    canonicalReference: reference
  )
  commands.redo()
  #expect(try #require(editor.textStorage).isEqual(to: after))
  #expect(editor.selectedRange() == afterSelection)
  try expectOneProjectedImage(
    in: editor,
    canonical: canonical,
    canonicalReference: reference
  )
  #expect(savedBody == canonical)
  let redoneRTF = try #require(savedRTF)
  let redoneDecoded = try NSAttributedString(
    data: redoneRTF,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(redoneDecoded.isEqual(to: decoded))
  #expect(redoneRTF == appliedRTF)
}

@MainActor
private func expectOneProjectedImage(
  in editor: ListAwareTextView,
  canonical: String,
  canonicalReference: String
) throws {
  let storage = try #require(editor.textStorage)
  let expectedDisplay = canonical.replacingOccurrences(of: canonicalReference, with: "\u{fffc}")
  #expect(canonical.components(separatedBy: canonicalReference).count - 1 == 1)
  #expect(expectedDisplay.components(separatedBy: "\u{fffc}").count - 1 == 1)
  #expect(storage.string == expectedDisplay)

  var attachments: [(NSRange, InlineNoteImageAttachment)] = []
  storage.enumerateAttribute(
    .attachment,
    in: NSRange(location: 0, length: storage.length)
  ) { value, range, _ in
    if let attachment = value as? InlineNoteImageAttachment {
      attachments.append((range, attachment))
    } else if value != nil {
      Issue.record("Unexpected attachment type in projected editor content")
    }
  }
  let projectedImage = try #require(attachments.first)
  #expect(attachments.count == 1)
  #expect(projectedImage.0.length == 1)
  #expect((storage.string as NSString).substring(with: projectedImage.0) == "\u{fffc}")
  #expect(projectedImage.1.sourceReference == canonicalReference)

  let expanded = InlineNoteImageProjection.expanded(storage)
  #expect(expanded.string == canonical)
  #expect(expanded.string.components(separatedBy: canonicalReference).count - 1 == 1)
  #expect(!expanded.string.contains("\u{fffc}"))
  let canonicalRange = (expanded.string as NSString).range(of: canonicalReference)
  #expect(canonicalRange.location != NSNotFound)
  var projectedAttributes = storage.attributes(
    at: projectedImage.0.location,
    effectiveRange: nil
  )
  projectedAttributes.removeValue(forKey: .attachment)
  projectedAttributes.removeValue(forKey: .link)
  let canonicalAttributes = expanded.attributes(at: canonicalRange.location, effectiveRange: nil)
  #expect(
    NSDictionary(dictionary: canonicalAttributes).isEqual(
      NSDictionary(dictionary: projectedAttributes)
    )
  )
}

@MainActor
private final class ToolbarImageFixture {
  let root: URL
  let store: InlineNoteImageStore

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("FleckToolbarImage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = InlineNoteImageStore(
      rootURL: root.appendingPathComponent("managed", isDirectory: true)
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  func importImage(named name: String) throws -> String {
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 4,
      pixelsHigh: 3,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ))
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        bitmap.setColor(
          NSColor(calibratedRed: Double(x) / 4, green: Double(y) / 3, blue: 0.6, alpha: 1),
          atX: x,
          y: y
        )
      }
    }
    let url = root.appendingPathComponent(name)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    return try store.importImage(at: url).reference
  }

  func editor(canonical: NSAttributedString) -> ListAwareTextView {
    let editor = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
    editor.isRichText = true
    editor.isEditable = true
    editor.isSelectable = true
    editor.importsGraphics = false
    editor.inlineImageStore = store
    editor.allowsUndo = true
    editor.textStorage?.setAttributedString(store.projectedContent(from: canonical))
    return editor
  }

  func commands(for editor: ListAwareTextView) -> EditorCommands {
    let commands = EditorCommands()
    commands.configureBodyDefaults(family: "Helvetica", size: 14)
    commands.textView = editor
    return commands
  }

  func nativeEditor(
    text: String,
    commands: EditorCommands,
    onChange: @escaping (String, Data?) -> Void
  ) -> NativeRichTextEditor {
    NativeRichTextEditor(
      text: text,
      richTextRTF: nil,
      onChange: onChange,
      fontFamily: "Helvetica",
      fontSize: 14,
      textColorHex: nil,
      backgroundColorHex: nil,
      accentColorHex: "#007AFF",
      reduceMotion: true,
      automaticLists: true,
      commands: commands,
      inlineImageStore: store
    )
  }
}
