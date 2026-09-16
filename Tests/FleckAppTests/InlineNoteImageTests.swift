import AppKit
import FleckCore
import ImageIO
import Testing

@testable import FleckApp

@Test @MainActor func managedReferencesRoundTripWhenStoreRootContainsParentheses() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let source = try fixture.makeImage(name: "parentheses.png", width: 12, height: 8)
  let originalBytes = try Data(contentsOf: source)
  let store = InlineNoteImageStore(
    rootURL: fixture.root.appendingPathComponent("managed (synthetic)", isDirectory: true)
  )

  let imported = try store.importImage(at: source)
  let managedURL = try #require(managedReferenceURLs(in: imported.reference).first)
  #expect(managedURL.deletingLastPathComponent().standardizedFileURL == store.rootURL)
  #expect(try Data(contentsOf: managedURL) == originalBytes)

  let projected = store.projectedContent(from: NSAttributedString(string: imported.reference))
  #expect(projected.string == "\u{fffc}")
  #expect(projected.attribute(.attachment, at: 0, effectiveRange: nil) is InlineNoteImageAttachment)
  let expanded = InlineNoteImageProjection.expanded(projected)
  #expect(expanded.string == imported.reference)
  let reprojected = store.projectedContent(from: expanded)
  #expect(reprojected.string == "\u{fffc}")
  #expect(
    reprojected.attribute(.attachment, at: 0, effectiveRange: nil)
      is InlineNoteImageAttachment
  )
}

@Test @MainActor func nativeFileURLDragImportsAtDropLocationAndRoundTripsUndo() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let imageURL = try fixture.makeImage(name: "native-drag.png", width: 32, height: 24)
  let initial = "Before\n\nAfter"
  let editor = fixture.editor()
  editor.font = .systemFont(ofSize: 17)
  editor.string = initial
  let window = offscreenWindow(containing: editor)
  defer { window.close() }
  let commands = EditorCommands()
  commands.textView = editor
  var savedBody = ""
  var savedRTF: Data?
  let bridge = fixture.nativeEditor(
    text: initial,
    commands: commands,
    onChange: { savedBody = $0; savedRTF = $1 }
  )
  let coordinator = bridge.makeCoordinator()
  editor.delegate = coordinator
  editor.setSelectedRange(NSRange(location: initial.utf16.count, length: 0))
  editor.undoManager?.removeAllActions()

  let result = performNativeDestinationDrag(
    urls: [imageURL],
    on: editor,
    in: window
  )

  #expect(editor.acceptableDragTypes.first == .fileURL)
  #expect(result.entered == .copy)
  #expect(result.updated == .copy)
  #expect(result.prepared)
  #expect(result.performed)
  #expect(result.types.first == .fileURL)
  #expect(result.types.contains(.fileURL))
  #expect(result.types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")))
  let expanded = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  let references = try managedReferenceURLs(in: expanded.string)
  let managedURL = try #require(references.first)
  #expect(references.count == 1)
  #expect(expanded.string == "Before\n![Image](\(managedURL.absoluteString))\nAfter")
  #expect(editor.string == "Before\n\u{fffc}\nAfter")
  #expect(editor.selectedRange() == NSRange(location: 7, length: 1))
  #expect(managedURL.standardizedFileURL != imageURL.standardizedFileURL)
  #expect(managedURL.path.hasPrefix(fixture.store.rootURL.path + "/"))
  #expect(savedBody.utf16.elementsEqual(expanded.string.utf16))
  let decodedRTF = try NSAttributedString(
    data: #require(savedRTF),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(decodedRTF.string.utf16.elementsEqual(savedBody.utf16))
  var containsAttachment = false
  decodedRTF.enumerateAttribute(
    .attachment,
    in: NSRange(location: 0, length: decodedRTF.length)
  ) { value, _, _ in
    containsAttachment = containsAttachment || value != nil
  }
  #expect(!containsAttachment)

  editor.undoManager?.undo()
  #expect(editor.string == initial)
  editor.undoManager?.redo()
  #expect(
    InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string
      == expanded.string
  )
}

@Test @MainActor func nativeFileURLDragImportsMultipleImagesInFinderOrder() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let first = try fixture.makeImage(name: "native-first.png", width: 7, height: 5)
  let second = try fixture.makeImage(name: "native-second.png", width: 5, height: 7)
  let initial = "Start\n\nEnd"
  let editor = fixture.editor()
  editor.font = .systemFont(ofSize: 17)
  editor.string = initial
  let window = offscreenWindow(containing: editor)
  defer { window.close() }
  editor.setSelectedRange(NSRange(location: initial.utf16.count, length: 0))
  editor.undoManager?.removeAllActions()

  let result = performNativeDestinationDrag(
    urls: [first, second],
    on: editor,
    in: window
  )

  #expect(result.performed)
  let expanded = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  let references = try managedReferenceURLs(in: expanded.string)
  #expect(references.count == 2)
  #expect(try references.map(imagePixelSize) == [
    NSSize(width: 7, height: 5),
    NSSize(width: 5, height: 7),
  ])
  #expect(expanded.string.hasPrefix("Start\n![Image]("))
  #expect(expanded.string.contains(")\n![Image]("))
  #expect(expanded.string.hasSuffix(")\nEnd"))
  #expect(editor.string == "Start\n\u{fffc}\n\u{fffc}\nEnd")
  #expect(editor.undoManager?.canUndo == true)
  editor.undoManager?.undo()
  #expect(editor.string == initial)
  editor.undoManager?.redo()
  #expect(
    InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string
      == expanded.string
  )
}

@Test @MainActor func nativeFileURLDragPreservesNativeFallbackForUnsupportedFiles() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "mixed.png", width: 7, height: 5)
  let textFile = fixture.root.appendingPathComponent("notes.txt")
  try Data("plain".utf8).write(to: textFile)
  let corruptImage = fixture.root.appendingPathComponent("corrupt.png")
  try Data("not an image".utf8).write(to: corruptImage)

  let cases: [([URL], Bool)] = [
    ([textFile], true),
    ([corruptImage], true),
    ([image, textFile], true),
    ([image], false),
  ]
  for (urls, hasImageStore) in cases {
    let initial = "Keep\n\nHere"
    let editor = fixture.editor()
    editor.font = .systemFont(ofSize: 17)
    editor.string = initial
    if !hasImageStore { editor.inlineImageStore = nil }
    var errors: [String] = []
    editor.onInlineImageError = { errors.append($0) }
    let control = NSTextView(frame: editor.frame)
    control.isRichText = true
    control.importsGraphics = false
    control.allowsUndo = true
    control.font = editor.font
    control.string = initial
    let editorWindow = offscreenWindow(containing: editor)
    let controlWindow = offscreenWindow(containing: control)
    defer {
      editorWindow.close()
      controlWindow.close()
    }
    let selection = NSRange(location: initial.utf16.count, length: 0)
    editor.setSelectedRange(selection)
    control.setSelectedRange(selection)

    let actual = performNativeDestinationDrag(
      urls: urls,
      on: editor,
      in: editorWindow
    )
    let baseline = performNativeDestinationDrag(
      urls: urls,
      on: control,
      in: controlWindow
    )

    #expect(actual == baseline)
    #expect(editor.string == control.string)
    #expect(editor.selectedRange() == control.selectedRange())
    #expect(editor.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
    for url in urls {
      #expect(editor.string.contains(url.path))
    }
    #expect(errors.isEmpty == !(hasImageStore && urls == [corruptImage]))
  }
  let importedFiles = (try? FileManager.default.contentsOfDirectory(
    at: fixture.store.rootURL,
    includingPropertiesForKeys: nil
  )) ?? []
  #expect(importedFiles.isEmpty)
}

@Test @MainActor func fileURLPasteboardDropDisplaysInlineImageThroughNativeEntries() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let imageURL = try fixture.makeImage(name: "drop.png", width: 4, height: 3)

  for typed in [false, true] {
    let editor = fixture.editor()
    editor.isRichText = true
    editor.importsGraphics = false
    editor.inlineImageStore = fixture.store
    #expect(editor.readablePasteboardTypes.first == .fileURL)
    editor.string = "Before after"
    editor.setSelectedRange(NSRange(location: 7, length: 0))
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.writeObjects([imageURL as NSURL])

    let accepted = typed
      ? editor.readSelection(from: pasteboard, type: .fileURL)
      : editor.readSelection(from: pasteboard)
    #expect(accepted)
    #expect(editor.textStorage?.attribute(.attachment, at: 7, effectiveRange: nil) != nil)
    let source = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
    #expect(source.string.hasPrefix("Before ![Image](file://"))
    #expect(source.string.hasSuffix(".png)after"))
  }
}

@Test @MainActor func multipleImageDropIsOneUndoableCanonicalEditInFileOrder() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let first = try fixture.makeImage(name: "first.png", width: 7, height: 5)
  let second = try fixture.makeImage(name: "second.png", width: 5, height: 7)
  let editor = fixture.editor(text: "🐈replace me")
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = editor
  defer { window.orderOut(nil) }
  editor.setSelectedRange(NSRange(location: 2, length: 7))
  editor.undoManager?.removeAllActions()
  let pasteboard = fixture.pasteboard(urls: [first, second])
  defer { pasteboard.releaseGlobally() }

  #expect(editor.readSelection(from: pasteboard))
  let inserted = InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string
  let references = inserted.components(separatedBy: "\n")
  #expect(references.count == 2)
  #expect(references[0].hasPrefix("🐈![Image](file://"))
  #expect(references[1].hasSuffix(") me"))
  let copiedSizes = try managedReferenceURLs(in: inserted).map(imagePixelSize)
  #expect(copiedSizes == [NSSize(width: 7, height: 5), NSSize(width: 5, height: 7)])
  #expect(editor.undoManager?.canUndo == true)
  editor.undoManager?.undo()
  #expect(editor.string == "🐈replace me")
  editor.undoManager?.redo()
  #expect(InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string == inserted)
}

@Test @MainActor func failedAndMixedFileDropsPreserveNativeFallbackWithoutConsumingSelection() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let validImage = try fixture.makeImage(name: "valid.png", width: 7, height: 5)
  let corruptImage = fixture.root.appendingPathComponent("corrupt.png")
  try Data("not an image".utf8).write(to: corruptImage)
  let textFile = fixture.root.appendingPathComponent("notes.txt")
  try Data("plain".utf8).write(to: textFile)

  for urls in [[corruptImage], [validImage, textFile]] {
    let editor = fixture.editor(text: "Keep selection")
    let control = NSTextView(frame: editor.frame)
    control.isRichText = true
    control.importsGraphics = false
    control.string = editor.string
    let selection = NSRange(location: 5, length: 4)
    editor.setSelectedRange(selection)
    control.setSelectedRange(selection)
    var errors: [String] = []
    editor.onInlineImageError = { errors.append($0) }
    let actualPasteboard = fixture.pasteboard(urls: urls)
    let controlPasteboard = fixture.pasteboard(urls: urls)
    defer {
      actualPasteboard.releaseGlobally()
      controlPasteboard.releaseGlobally()
    }

    let accepted = editor.readSelection(from: actualPasteboard, type: .fileURL)
    let controlAccepted = control.readSelection(from: controlPasteboard, type: .fileURL)
    #expect(accepted == controlAccepted)
    #expect(editor.string == control.string)
    #expect(editor.selectedRange() == control.selectedRange())
    #expect(errors.isEmpty == (urls.count > 1))
  }
  let importedFiles = (try? FileManager.default.contentsOfDirectory(
    at: fixture.store.rootURL,
    includingPropertiesForKeys: nil
  )) ?? []
  #expect(importedFiles.isEmpty)
}

@Test @MainActor func editsListsAndPlainPasteNeverInheritImageAttachmentAttributes() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "editing.png", width: 20, height: 10)
  let reference = try fixture.store.importImage(at: image).reference
  let editor = fixture.editor()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = editor
  defer { window.orderOut(nil) }

  editor.textStorage?.setAttributedString(
    fixture.store.projectedContent(from: NSAttributedString(string: reference))
  )
  editor.setSelectedRange(NSRange(location: 1, length: 0))
  editor.insertText(" after", replacementRange: editor.selectedRange())
  #expect(InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string == reference + " after")
  #expect(editor.textStorage?.attribute(.attachment, at: 1, effectiveRange: nil) == nil)

  editor.selectAll(nil)
  editor.toggleList(.bullet(.disc))
  let listed = try #require(editor.textStorage)
  #expect(InlineNoteImageProjection.expanded(listed).string == "• \(reference) after")
  #expect(listed.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
  #expect(listed.attribute(.attachment, at: 2, effectiveRange: nil) is InlineNoteImageAttachment)

  editor.undoManager?.removeAllActions()
  editor.setSelectedRange(NSRange(location: 2, length: 1))
  editor.insertText("replacement", replacementRange: editor.selectedRange())
  #expect(editor.string == "• replacement after")
  #expect(editor.undoManager?.canUndo == true)
  editor.undoManager?.undo()
  #expect(InlineNoteImageProjection.expanded(try #require(editor.textStorage)).string == "• \(reference) after")
  editor.undoManager?.redo()
  #expect(editor.string == "• replacement after")

  editor.textStorage?.setAttributedString(
    fixture.store.projectedContent(from: NSAttributedString(string: reference))
  )
  editor.setSelectedRange(NSRange(location: 0, length: 1))
  editor.insertPastedTextForTesting(
    NSAttributedString(string: "plain"),
    plainText: "plain",
    hasRichFormatting: false
  )
  #expect(editor.string == "plain")
  #expect(editor.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
}

@Test @MainActor func bindingSnapshotPersistsReferenceOnlyWithMatchingRTFText() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "binding.png", width: 40, height: 20)
  let imported = try fixture.store.importImage(at: image)
  let canonical = "Before 🐈 \(imported.reference) after"
  let display = fixture.store.projectedContent(from: NSAttributedString(string: canonical))
  let editor = fixture.editor()
  editor.textStorage?.setAttributedString(display)
  let commands = EditorCommands()
  commands.textView = editor
  var body: String?
  var rtf: Data?
  let bridge = fixture.nativeEditor(
    text: canonical,
    commands: commands,
    onChange: { body = $0; rtf = $1 }
  )

  bridge.makeCoordinator().textDidChange(
    Notification(name: NSText.didChangeNotification, object: editor)
  )

  #expect(body == canonical)
  let decoded = try NSAttributedString(
    data: #require(rtf),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(decoded.string == canonical)
  var hasAttachment = false
  decoded.enumerateAttribute(.attachment, in: NSRange(location: 0, length: decoded.length)) {
    value, _, _ in hasAttachment = hasAttachment || value != nil
  }
  #expect(!hasAttachment)
}

@Test @MainActor func savedCanonicalNoteReopensWithInlineProjection() async throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let localStore = LocalStore(rootURL: fixture.root)
  let imageStore = InlineNoteImageStore(
    rootURL: fixture.root.appendingPathComponent(
      InlineNoteImageStore.directoryName,
      isDirectory: true
    )
  )
  let sourceImage = try fixture.makeImage(name: "reopen.png", width: 32, height: 24)
  let reference = try imageStore.importImage(at: sourceImage).reference
  let body = "Saved \(reference)"
  let rich = NSAttributedString(
    string: body,
    attributes: [.font: NSFont.boldSystemFont(ofSize: 15)]
  )
  let rtf = try #require(rich.rtf(from: NSRange(location: 0, length: rich.length)))
  let note = Note(title: "Photo", body: body, richTextRTF: rtf)
  try await localStore.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init()
  )

  let reopenedWorkspace = try await localStore.loadWorkspace()
  let reopened = try #require(reopenedWorkspace.notes.first)
  #expect(reopened.body == body)
  let reopenedRich = try NSAttributedString(
    data: #require(reopened.richTextRTF),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(reopenedRich.string == body)
  let display = InlineNoteImageStore(rootURL: imageStore.rootURL)
    .projectedContent(from: reopenedRich)
  #expect(display.string == "Saved \u{fffc}")
  #expect(display.attribute(.attachment, at: 6, effectiveRange: nil) is InlineNoteImageAttachment)
}

@Test @MainActor func unicodeRangeConversionsRoundTripAcrossMultipleImages() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "ranges.png", width: 8, height: 6)
  let first = try fixture.store.importImage(at: image).reference
  let second = try fixture.store.importImage(at: image).reference
  let source = "🐈A\(first)é\(second)Z"
  let display = fixture.store.projectedContent(from: NSAttributedString(string: source))
  #expect(display.string == "🐈A\u{fffc}é\u{fffc}Z")

  let spanningDisplay = NSRange(location: 2, length: 4)
  let spanningSource = InlineNoteImageProjection.sourceRange(
    forDisplayRange: spanningDisplay,
    in: display
  )
  #expect(
    spanningSource
      == NSRange(location: 2, length: 1 + first.utf16.count + 1 + second.utf16.count)
  )
  #expect(
    InlineNoteImageProjection.displayRange(forSourceRange: spanningSource, in: display)
      == spanningDisplay
  )
  for pair in [
    (NSRange(location: 3, length: 0), NSRange(location: 3, length: 0)),
    (
      NSRange(location: 4, length: 0),
      NSRange(location: 3 + first.utf16.count, length: 0)
    ),
  ] {
    #expect(
      InlineNoteImageProjection.sourceRange(forDisplayRange: pair.0, in: display) == pair.1
    )
  }
  #expect(
    InlineNoteImageProjection.displayRange(
      forSourceRange: NSRange(location: 4, length: 0),
      in: display
    ) == NSRange(location: 3, length: 0)
  )
}

@Test @MainActor func externalReloadPreservesDisplaySelectionAndProjectsAgentAppend() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "reload.png", width: 20, height: 10)
  let reference = try fixture.store.importImage(at: image).reference
  let original = "🐈\(reference) tail"
  let updated = original + "\nAgent append"
  let commands = EditorCommands()
  let textView = fixture.editor()
  textView.textStorage?.setAttributedString(
    fixture.store.projectedContent(from: NSAttributedString(string: original))
  )
  commands.textView = textView
  textView.setSelectedRange(NSRange(location: 3, length: 5))
  let initial = fixture.nativeEditor(text: original, commands: commands)
  let coordinator = initial.makeCoordinator()
  let external = fixture.nativeEditor(text: updated, commands: commands)

  #expect(external.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
  #expect(InlineNoteImageProjection.expanded(try #require(textView.textStorage)).string == updated)
  #expect(textView.string == "🐈\u{fffc} tail\nAgent append")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 5))
}

@Test @MainActor func externalReloadUsesExactUTF16CanonicalTextWithoutResettingCaret() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let decomposed = "e\u{301} tail"
  let composed = "\u{e9} tail"
  let composedRTF = try #require(
    NSAttributedString(string: composed).rtf(
      from: NSRange(location: 0, length: composed.utf16.count)
    )
  )
  let commands = EditorCommands()
  let textView = fixture.editor(text: decomposed)
  commands.textView = textView
  textView.setSelectedRange(NSRange(location: decomposed.utf16.count, length: 0))
  let initial = NativeRichTextEditor(
    text: decomposed,
    richTextRTF: composedRTF,
    onChange: { _, _ in },
    fontFamily: "Helvetica",
    fontSize: 14,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#007AFF",
    reduceMotion: true,
    automaticLists: true,
    commands: commands,
    inlineImageStore: fixture.store
  )
  let coordinator = initial.makeCoordinator()

  let composedUpdate = NativeRichTextEditor(
    text: composed,
    richTextRTF: composedRTF,
    onChange: { _, _ in },
    fontFamily: "Helvetica",
    fontSize: 14,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#007AFF",
    reduceMotion: true,
    automaticLists: true,
    commands: commands,
    inlineImageStore: fixture.store
  )
  #expect(composedUpdate.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
  #expect(textView.string.utf16.elementsEqual(composed.utf16))
  #expect(textView.selectedRange() == NSRange(location: composed.utf16.count, length: 0))

  let decomposedUpdate = NativeRichTextEditor(
    text: decomposed,
    richTextRTF: composedRTF,
    onChange: { _, _ in },
    fontFamily: "Helvetica",
    fontSize: 14,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#007AFF",
    reduceMotion: true,
    automaticLists: true,
    commands: commands,
    inlineImageStore: fixture.store
  )
  #expect(decomposedUpdate.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
  #expect(textView.string.utf16.elementsEqual(decomposed.utf16))
  #expect(textView.selectedRange() == NSRange(location: decomposed.utf16.count, length: 0))
}

@Test @MainActor func canonicalEquivalentReloadRemapsInteriorSelectionsAndTyping() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let decomposed = "e\u{301} tail"
  let composed = "\u{e9} tail"
  let cases: [(String, String, NSRange, NSRange, String)] = [
    (
      decomposed, composed,
      NSRange(location: 3, length: 0), NSRange(location: 2, length: 0),
      "\u{e9} Xtail"
    ),
    (
      composed, decomposed,
      NSRange(location: 2, length: 0), NSRange(location: 3, length: 0),
      "e\u{301} Xtail"
    ),
    (
      decomposed, composed,
      NSRange(location: 3, length: 2), NSRange(location: 2, length: 2),
      "\u{e9} Xil"
    ),
    (
      composed, decomposed,
      NSRange(location: 2, length: 2), NSRange(location: 3, length: 2),
      "e\u{301} Xil"
    ),
    (
      decomposed, composed,
      NSRange(location: 1, length: 0), NSRange(location: 0, length: 0),
      "X\u{e9} tail"
    ),
    (
      decomposed, composed,
      NSRange(location: 1, length: 1), NSRange(location: 0, length: 1),
      "X tail"
    ),
    (
      composed, decomposed,
      NSRange(location: 0, length: 1), NSRange(location: 0, length: 2),
      "X tail"
    ),
  ]

  for (original, updated, originalSelection, updatedSelection, expectedAfterTyping) in cases {
    let commands = EditorCommands()
    let textView = fixture.editor(text: original)
    commands.textView = textView
    textView.setSelectedRange(originalSelection)
    let coordinator = fixture.nativeEditor(text: original, commands: commands).makeCoordinator()
    let external = fixture.nativeEditor(text: updated, commands: commands)

    #expect(external.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
    #expect(textView.string.utf16.elementsEqual(updated.utf16))
    #expect(textView.selectedRange() == updatedSelection)
    textView.insertText("X", replacementRange: textView.selectedRange())
    #expect(textView.string.utf16.elementsEqual(expectedAfterTyping.utf16))
  }
}

@Test @MainActor func canonicalEquivalentReloadRemapsSelectionsThroughProjectedImage() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "canonical-selection.png", width: 24, height: 16)
  let reference = try fixture.store.importImage(at: image).reference
  let original = "e\u{301} \(reference) 👩‍💻 a\u{300} tail"
  let updated = "\u{e9} \(reference) 👩‍💻 \u{e0} tail"
  let originalAttributed = fixture.store.projectedContent(
    from: NSAttributedString(string: original)
  )
  let updatedAttributed = fixture.store.projectedContent(
    from: NSAttributedString(string: updated)
  )
  let originalNSString = original as NSString
  let updatedNSString = updated as NSString
  let originalEmoji = originalNSString.range(of: "👩‍💻")
  let updatedEmoji = updatedNSString.range(of: "👩‍💻")
  let originalReference = originalNSString.range(of: reference)
  let updatedReference = updatedNSString.range(of: reference)
  let originalTail = originalNSString.range(of: "tail")
  let updatedTail = updatedNSString.range(of: "tail")
  let cases: [(NSRange, NSRange, Bool)] = [
    (
      NSRange(location: originalTail.location, length: 0),
      NSRange(location: updatedTail.location, length: 0),
      true
    ),
    (
      NSRange(location: originalTail.location, length: 2),
      NSRange(location: updatedTail.location, length: 2),
      true
    ),
    (originalReference, updatedReference, true),
    (
      NSRange(location: originalNSString.length, length: 0),
      NSRange(location: updatedNSString.length, length: 0),
      false
    ),
  ]

  for (originalSourceSelection, updatedSourceSelection, verifyTyping) in cases {
    let commands = EditorCommands()
    let textView = fixture.editor()
    textView.textStorage?.setAttributedString(originalAttributed)
    commands.textView = textView
    textView.setSelectedRange(
      InlineNoteImageProjection.displayRange(
        forSourceRange: originalSourceSelection,
        in: originalAttributed
      )
    )
    let coordinator = fixture.nativeEditor(text: original, commands: commands).makeCoordinator()
    let external = fixture.nativeEditor(text: updated, commands: commands)

    #expect(external.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
    #expect(
      textView.selectedRange()
        == InlineNoteImageProjection.displayRange(
          forSourceRange: updatedSourceSelection,
          in: updatedAttributed
        )
    )
    if verifyTyping {
      textView.insertText("X", replacementRange: textView.selectedRange())
      let expected = NSMutableString(string: updated)
      expected.replaceCharacters(in: updatedSourceSelection, with: "X")
      let expanded = InlineNoteImageProjection.expanded(try #require(textView.textStorage))
      #expect(expanded.string.utf16.elementsEqual((expected as String).utf16))
    }
  }

  let exactSelectionTextView = ExactSelectionTextView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 180)
  )
  exactSelectionTextView.textStorage?.setAttributedString(originalAttributed)
  let originalEmojiSelection = InlineNoteImageProjection.displayRange(
    forSourceRange: NSRange(location: originalEmoji.location + 2, length: 0),
    in: originalAttributed
  )
  exactSelectionTextView.exactSelectedRange = originalEmojiSelection
  let commands = EditorCommands()
  commands.textView = exactSelectionTextView
  let coordinator = fixture.nativeEditor(text: original, commands: commands).makeCoordinator()
  let external = fixture.nativeEditor(text: updated, commands: commands)

  #expect(
    external.applyExternalContentIfNeeded(
      to: exactSelectionTextView,
      coordinator: coordinator
    )
  )
  #expect(
    exactSelectionTextView.exactSelectedRange
      == InlineNoteImageProjection.displayRange(
        forSourceRange: NSRange(location: updatedEmoji.location + 2, length: 0),
        in: updatedAttributed
      )
  )
}

@Test @MainActor func canonicalEquivalentRichTextLoadsExactBodyWithoutLosingFormatting() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let decomposed = "e\u{301} tail"
  let composed = "\u{e9} tail"
  let composedRich = styledCanonicalText(composed)
  let composedRTF = try #require(
    composedRich.rtf(from: NSRange(location: 0, length: composedRich.length))
  )
  let composedRTFText = try #require(String(data: composedRTF, encoding: .utf8))
  let decomposedRTFText = composedRTFText
    .replacingOccurrences(of: #"\'e9"#, with: #"\u101?\u769?"#)
    .replacingOccurrences(of: #"\u233?"#, with: #"\u101?\u769?"#)
  #expect(decomposedRTFText != composedRTFText)
  let decomposedRTF = Data(decomposedRTFText.utf8)
  let parsedDecomposed = try NSAttributedString(
    data: decomposedRTF,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(parsedDecomposed.string.utf16.elementsEqual(decomposed.utf16))

  for (body, rtf) in [(decomposed, composedRTF), (composed, decomposedRTF)] {
    let commands = EditorCommands()
    let textView = fixture.editor(text: body)
    commands.textView = textView
    textView.setSelectedRange(NSRange(location: body.utf16.count, length: 0))
    var savedBody = ""
    var savedRTF: Data?
    let initial = fixture.nativeEditor(text: "", commands: commands)
    let coordinator = initial.makeCoordinator()
    let loaded = fixture.nativeEditor(
      text: body,
      richTextRTF: rtf,
      commands: commands,
      onChange: { savedBody = $0; savedRTF = $1 }
    )
    coordinator.parent = loaded

    #expect(loaded.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
    let storage = try #require(textView.textStorage)
    assertCanonicalFormatting(storage, exactBody: body)
    #expect(textView.selectedRange() == NSRange(location: body.utf16.count, length: 0))

    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    #expect(savedBody.utf16.elementsEqual(body.utf16))
    let reopenedCommands = EditorCommands()
    let reopened = fixture.editor(text: body)
    reopenedCommands.textView = reopened
    reopened.setSelectedRange(NSRange(location: body.utf16.count, length: 0))
    let reopenedCoordinator = fixture.nativeEditor(
      text: "",
      commands: reopenedCommands
    ).makeCoordinator()
    guard let savedRTF else {
      Issue.record("Expected the native editor snapshot to include RTF")
      continue
    }
    let reopenedBridge = fixture.nativeEditor(
      text: body,
      richTextRTF: savedRTF,
      commands: reopenedCommands
    )
    #expect(
      reopenedBridge.applyExternalContentIfNeeded(
        to: reopened,
        coordinator: reopenedCoordinator
      )
    )
    assertCanonicalFormatting(try #require(reopened.textStorage), exactBody: body)
    #expect(reopened.selectedRange() == NSRange(location: body.utf16.count, length: 0))
  }
}

@Test @MainActor func canonicalRemapPreservesMultipleRunsAroundImageAndMultiscalarGrapheme() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "canonical-runs.png", width: 24, height: 16)
  let reference = try fixture.store.importImage(at: image).reference
  let sourceText = "\u{ac00} 👩‍💻 \(reference) \u{e9}"
  let body = "\u{1100}\u{1161} 👩‍💻 \(reference) e\u{301}"
  let rich = NSMutableAttributedString(
    string: sourceText,
    attributes: [.font: NSFont.systemFont(ofSize: 14)]
  )
  let firstFont = try #require(NSFont(name: "Courier-Bold", size: 22))
  let emojiFirstFont = try #require(NSFont(name: "Menlo", size: 18))
  let emojiSecondFont = NSFont.systemFont(ofSize: 24)
  let imageFont = try #require(NSFont(name: "Avenir Next", size: 20))
  let tailFont = try #require(NSFont(name: "Menlo", size: 17))
  rich.addAttribute(.font, value: firstFont, range: NSRange(location: 0, length: 1))
  let emojiRange = (sourceText as NSString).range(of: "👩‍💻")
  rich.addAttribute(
    .font,
    value: emojiFirstFont,
    range: NSRange(location: emojiRange.location, length: 2)
  )
  rich.addAttribute(
    .font,
    value: emojiSecondFont,
    range: NSRange(location: emojiRange.location + 2, length: emojiRange.length - 2)
  )
  rich.addAttribute(
    .font,
    value: imageFont,
    range: (sourceText as NSString).range(of: reference)
  )
  rich.addAttribute(
    .font,
    value: tailFont,
    range: (sourceText as NSString).range(of: "\u{e9}")
  )
  let rtf = try #require(rich.rtf(from: NSRange(location: 0, length: rich.length)))
  let commands = EditorCommands()
  let textView = fixture.editor(text: body)
  commands.textView = textView
  textView.setSelectedRange(NSRange(location: body.utf16.count, length: 0))
  let coordinator = fixture.nativeEditor(text: "", commands: commands).makeCoordinator()
  let loaded = fixture.nativeEditor(
    text: body,
    richTextRTF: rtf,
    commands: commands
  )

  #expect(loaded.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
  let expanded = InlineNoteImageProjection.expanded(try #require(textView.textStorage))
  #expect(expanded.string.utf16.elementsEqual(body.utf16))
  let remappedFirstFont = try #require(expanded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(remappedFirstFont.pointSize == firstFont.pointSize)
  #expect(NSFontManager.shared.traits(of: remappedFirstFont).contains(.boldFontMask))
  let bodyEmojiRange = (body as NSString).range(of: "👩‍💻")
  #expect((expanded.attribute(.font, at: bodyEmojiRange.location, effectiveRange: nil) as? NSFont)?.pointSize == emojiFirstFont.pointSize)
  #expect((expanded.attribute(.font, at: bodyEmojiRange.location + 2, effectiveRange: nil) as? NSFont)?.pointSize == emojiSecondFont.pointSize)
  let bodyReferenceRange = (body as NSString).range(of: reference)
  #expect(expanded.attribute(.font, at: bodyReferenceRange.location, effectiveRange: nil) as? NSFont == imageFont)
  let bodyTail = (body as NSString).range(of: "e\u{301}")
  #expect(expanded.attribute(.font, at: bodyTail.location, effectiveRange: nil) as? NSFont == tailFont)
  #expect(textView.selectedRange() == NSRange(location: textView.string.utf16.count, length: 0))
}

@Test @MainActor func externalAgentAppendPreservesAbsoluteEndCaretPosition() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let commands = EditorCommands()
  let textView = fixture.editor(text: "hello")
  commands.textView = textView
  textView.setSelectedRange(NSRange(location: 5, length: 0))
  let initial = fixture.nativeEditor(text: "hello", commands: commands)
  let coordinator = initial.makeCoordinator()
  let external = fixture.nativeEditor(
    text: "hello\nAgent append",
    commands: commands
  )

  #expect(external.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
  #expect(textView.string == "hello\nAgent append")
  #expect(textView.selectedRange() == NSRange(location: 5, length: 0))
}

@Test @MainActor func focusedDictationSnapshotExpandsAfterRestoringOriginalImageSelection() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "dictation.png", width: 20, height: 10)
  let reference = try fixture.store.importImage(at: image).reference
  let canonical = "Before \(reference) after"
  let textView = fixture.editor()
  textView.textStorage?.setAttributedString(
    fixture.store.projectedContent(from: NSAttributedString(string: canonical))
  )
  let commands = EditorCommands()
  commands.textView = textView
  var persistedBody: String?
  let bridge = fixture.nativeEditor(
    text: canonical,
    commands: commands,
    onChange: { body, _ in persistedBody = body }
  )
  let coordinator = bridge.makeCoordinator()
  textView.setSelectedRange(NSRange(location: 7, length: 1))
  #expect(commands.beginFocusedDictation())
  commands.updateFocusedDictation(provisionalText: "draft")

  coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
  #expect(persistedBody == canonical)
  #expect(textView.string == "Before draft after")
}

@Test @MainActor func copyingProjectedImageWritesUsableReferenceWithoutImagePayload() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "copy.png", width: 20, height: 10)
  let reference = try fixture.store.importImage(at: image).reference
  let editor = fixture.editor()
  editor.textStorage?.setAttributedString(
    fixture.store.projectedContent(from: NSAttributedString(string: reference))
  )
  editor.setSelectedRange(NSRange(location: 0, length: 1))
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }

  #expect(editor.writablePasteboardTypes == [.rtf, .string])
  #expect(editor.writeSelection(to: pasteboard, types: editor.writablePasteboardTypes))
  #expect(pasteboard.string(forType: .string) == reference)
  let decoded = try NSAttributedString(
    data: #require(pasteboard.data(forType: .rtf)),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(decoded.string == reference)
  #expect(pasteboard.data(forType: .tiff) == nil)

  let pasted = fixture.editor(text: "Replace")
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = pasted
  defer { window.orderOut(nil) }
  pasted.selectAll(nil)
  pasted.undoManager?.removeAllActions()
  #expect(pasted.readSelection(from: pasteboard))
  #expect(pasted.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) is InlineNoteImageAttachment)
  #expect(InlineNoteImageProjection.expanded(try #require(pasted.textStorage)).string == reference)
  pasted.undoManager?.undo()
  #expect(pasted.string == "Replace")
  pasted.undoManager?.redo()
  #expect(pasted.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) is InlineNoteImageAttachment)

  let commands = EditorCommands()
  commands.textView = pasted
  var body = ""
  var modelRTF: Data?
  let initial = fixture.nativeEditor(
    text: "Replace",
    commands: commands,
    onChange: { body = $0; modelRTF = $1 }
  )
  let coordinator = initial.makeCoordinator()
  coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: pasted))
  let echo = NativeRichTextEditor(
    text: body,
    richTextRTF: modelRTF,
    onChange: { _, _ in },
    fontFamily: "Helvetica",
    fontSize: 14,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#007AFF",
    reduceMotion: true,
    automaticLists: true,
    commands: commands,
    inlineImageStore: fixture.store
  )
  #expect(!echo.applyExternalContentIfNeeded(to: pasted, coordinator: coordinator))
  #expect(pasted.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) is InlineNoteImageAttachment)

  for type: NSPasteboard.PasteboardType in [.rtf, .string] {
    let typedPaste = fixture.editor()
    #expect(typedPaste.readSelection(from: pasteboard, type: type))
    #expect(
      typedPaste.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil)
        is InlineNoteImageAttachment
    )
  }
}

@Test @MainActor func droppedAndReloadedAttachmentsCarrySanitizedSourceFormatting() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "styled.png", width: 20, height: 10)
  let expectedFont = try #require(NSFont(name: "Courier-Bold", size: 22))
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .right
  let editor = fixture.editor()
  editor.textStorage?.setAttributedString(
    NSAttributedString(
      string: "Before ",
      attributes: [.font: expectedFont, .paragraphStyle: paragraph]
    )
  )
  editor.setSelectedRange(NSRange(location: 7, length: 0))
  editor.typingAttributes = [.font: expectedFont, .paragraphStyle: paragraph]
  let pasteboard = fixture.pasteboard(urls: [image])
  defer { pasteboard.releaseGlobally() }

  #expect(editor.readSelection(from: pasteboard))
  let droppedAttributes = try #require(editor.textStorage?.attributes(at: 7, effectiveRange: nil))
  #expect((droppedAttributes[.font] as? NSFont) == expectedFont)
  #expect((droppedAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .right)
  #expect(droppedAttributes[.link] == nil)
  editor.insertText(" after", replacementRange: editor.selectedRange())
  #expect(editor.textStorage?.attribute(.font, at: 8, effectiveRange: nil) as? NSFont == expectedFont)
  #expect(editor.textStorage?.attribute(.attachment, at: 8, effectiveRange: nil) == nil)

  let canonical = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  let canonicalRTF = try #require(
    canonical.rtf(from: NSRange(location: 0, length: canonical.length))
  )
  let decoded = try NSAttributedString(
    data: canonicalRTF,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let reloaded = fixture.store.projectedContent(from: decoded)
  let attachmentLocation = (reloaded.string as NSString).range(of: "\u{fffc}").location
  let reloadedAttributes = reloaded.attributes(at: attachmentLocation, effectiveRange: nil)
  #expect((reloadedAttributes[.font] as? NSFont) == expectedFont)
  #expect((reloadedAttributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .right)
  #expect(reloadedAttributes[.link] == nil)
}

@Test @MainActor func plainBodyDefaultFormattingSurvivesSnapshotReopenAndTyping() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "plain-default.png", width: 20, height: 10)
  let reference = try fixture.store.importImage(at: image).reference
  let expectedFont = try #require(NSFont(name: "Courier", size: 22))
  let commands = EditorCommands()
  let textView = fixture.editor()
  commands.textView = textView
  let initial = fixture.nativeEditor(text: "", commands: commands)
  let coordinator = initial.makeCoordinator()
  var body = ""
  var rtf: Data?
  let loaded = NativeRichTextEditor(
    text: reference,
    richTextRTF: nil,
    onChange: { body = $0; rtf = $1 },
    fontFamily: "Courier",
    fontSize: 22,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#007AFF",
    reduceMotion: true,
    automaticLists: true,
    commands: commands,
    inlineImageStore: fixture.store
  )
  coordinator.parent = loaded
  #expect(loaded.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
  #expect(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == expectedFont)

  coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
  #expect(body == reference)
  let decoded = try NSAttributedString(
    data: #require(rtf),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == expectedFont)
  let reopened = fixture.editor()
  reopened.textStorage?.setAttributedString(fixture.store.projectedContent(from: decoded))
  reopened.setSelectedRange(NSRange(location: 1, length: 0))
  reopened.insertText("after", replacementRange: reopened.selectedRange())
  #expect(reopened.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont == expectedFont)
}

@Test @MainActor func currentAttachmentFormattingExpandsExactlyAndUndoRestoresRemoval() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "current-format.png", width: 20, height: 10)
  let reference = try fixture.store.importImage(at: image).reference
  let originalFont = try #require(NSFont(name: "Courier", size: 22))
  let source = NSAttributedString(
    string: reference,
    attributes: [
      .font: originalFont,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .backgroundColor: NSColor.systemYellow,
      .link: URL(string: "https://example.invalid/frozen")!,
    ]
  )
  let textView = fixture.editor()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  defer { window.orderOut(nil) }
  #expect(window.makeFirstResponder(textView))
  textView.textStorage?.setAttributedString(fixture.store.projectedContent(from: source))
  let commands = EditorCommands()
  commands.textView = textView
  textView.selectAll(nil)
  #expect(commands.applyFontSize(30))
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .right
  textView.textStorage?.addAttribute(
    .paragraphStyle,
    value: paragraph,
    range: NSRange(location: 0, length: 1)
  )

  let styled = InlineNoteImageProjection.expanded(try #require(textView.textStorage))
  #expect((styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 30)
  #expect((styled.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .right)
  #expect(styled.attribute(.link, at: 0, effectiveRange: nil) == nil)
  let styledRTF = try #require(styled.rtf(from: NSRange(location: 0, length: styled.length)))
  let decoded = try NSAttributedString(
    data: styledRTF,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let reopened = fixture.store.projectedContent(from: decoded)
  #expect((reopened.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 30)
  #expect((reopened.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .right)

  commands.toggleUnderline()
  textView.undoManager?.removeAllActions()
  commands.applyBackgroundColor(nil)
  let removed = InlineNoteImageProjection.expanded(try #require(textView.textStorage))
  #expect((removed.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
  #expect(removed.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
  #expect(removed.attribute(.link, at: 0, effectiveRange: nil) == nil)
  commands.undo()
  let undone = InlineNoteImageProjection.expanded(try #require(textView.textStorage))
  #expect(undone.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemYellow)
  #expect((undone.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
  #expect((undone.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 30)
}

@Test @MainActor func missingCorruptRemoteAndUnmanagedReferencesStayAsText() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let missing = fixture.store.rootURL.appendingPathComponent("\(UUID().uuidString).png")
  try FileManager.default.createDirectory(
    at: fixture.store.rootURL,
    withIntermediateDirectories: true
  )
  let corrupt = fixture.store.rootURL.appendingPathComponent("\(UUID().uuidString).png")
  try Data("not an image".utf8).write(to: corrupt)
  let unmanaged = fixture.root.appendingPathComponent("\(UUID().uuidString).png")
  try Data("not an image".utf8).write(to: unmanaged)
  let source = [
    "![Missing](\(missing.absoluteString))",
    "![Corrupt](\(corrupt.absoluteString))",
    "![Remote](https://example.invalid/image.png)",
    "![Unmanaged](\(unmanaged.absoluteString))",
  ].joined(separator: "\n")

  let display = fixture.store.projectedContent(from: NSAttributedString(string: source))
  #expect(display.string == source)
  #expect(InlineNoteImageProjection.expanded(display).string == source)
}

@Test @MainActor func oversizedDeclaredImageIsRejectedBeforeDecodeOrCopy() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let oversized = fixture.root.appendingPathComponent("oversized.png")
  FileManager.default.createFile(atPath: oversized.path, contents: Data([0x89, 0x50, 0x4e, 0x47]))
  let handle = try FileHandle(forWritingTo: oversized)
  try handle.truncate(atOffset: UInt64(InlineNoteImageStore.maximumFileSize + 1))
  try handle.close()

  #expect(throws: InlineNoteImageError.fileTooLarge) {
    try fixture.store.importImage(at: oversized)
  }
  #expect(!FileManager.default.fileExists(atPath: fixture.store.rootURL.path))
}

@Test @MainActor func oversizedManagedImageReferenceRemainsCanonicalText() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let source = try fixture.makeImage(name: "managed-large.png", width: 4, height: 3)
  let reference = try fixture.store.importImage(at: source).reference
  let managedURL = try #require(managedReferenceURLs(in: reference).first)
  let handle = try FileHandle(forWritingTo: managedURL)
  try handle.truncate(atOffset: UInt64(InlineNoteImageStore.maximumFileSize + 1))
  try handle.close()

  let projected = fixture.store.projectedContent(from: NSAttributedString(string: reference))
  #expect(projected.string == reference)
  #expect(projected.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
}

@Test @MainActor func mismatchedRTFUsesCanonicalBodyAndDoesNotResurrectImageReference() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "rtf.png", width: 20, height: 10)
  let reference = try fixture.store.importImage(at: image).reference
  let richReference = NSAttributedString(
    string: reference,
    attributes: [.font: NSFont.boldSystemFont(ofSize: 18)]
  )
  let mismatchedRTF = try #require(
    richReference.rtf(from: NSRange(location: 0, length: richReference.length))
  )
  let commands = EditorCommands()
  let textView = fixture.editor()
  commands.textView = textView
  let initial = fixture.nativeEditor(text: "", commands: commands)
  let coordinator = initial.makeCoordinator()
  let external = NativeRichTextEditor(
    text: "Body wins",
    richTextRTF: mismatchedRTF,
    onChange: { _, _ in },
    fontFamily: NSFont.systemFont(ofSize: 14).familyName ?? "Helvetica",
    fontSize: 14,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#007AFF",
    reduceMotion: true,
    automaticLists: true,
    commands: commands,
    inlineImageStore: fixture.store
  )

  #expect(external.applyExternalContentIfNeeded(to: textView, coordinator: coordinator))
  #expect(textView.string == "Body wins")
  #expect(textView.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
}

@Test @MainActor func appStateInjectsManagedImageRootAndReportsImportErrors() {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckInlineImageState-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })

  #expect(
    state.inlineNoteImageStore.rootURL
      == root.appendingPathComponent(InlineNoteImageStore.directoryName, isDirectory: true)
        .standardizedFileURL
  )
  state.inlineNoteImageImportFailed("Import failed")
  #expect(state.saveError == "Import failed")
}

@Test @MainActor func imageBoundsFitContainerWithoutUpscalingAndRenderEvidence() throws {
  let fixture = try InlineImageFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "bounds.png", width: 640, height: 480)
  let reference = try fixture.store.importImage(at: image).reference
  let projected = fixture.store.projectedContent(from: NSAttributedString(string: reference))
  let attachment = try #require(
    projected.attribute(.attachment, at: 0, effectiveRange: nil)
      as? InlineNoteImageAttachment
  )
  #expect(attachment.image?.accessibilityDescription == "Image file \(try #require(managedReferenceURLs(in: reference).first).lastPathComponent)")
  #expect(
    attachment.attachmentBounds(
      for: nil,
      proposedLineFragment: NSRect(x: 0, y: 0, width: 200, height: 20),
      glyphPosition: .zero,
      characterIndex: 0
    ).size == NSSize(width: 200, height: 150)
  )
  #expect(
    attachment.attachmentBounds(
      for: nil,
      proposedLineFragment: NSRect(x: 0, y: 0, width: 1_000, height: 20),
      glyphPosition: .zero,
      characterIndex: 0
    ).size == NSSize(width: 426, height: 320)
  )

  guard let evidenceDirectory = ProcessInfo.processInfo.environment["FLECK_EDITOR_EVIDENCE_DIR"]
  else { return }
  let appearances: [(String, NSAppearance.Name)] = [
    ("light", .aqua),
    ("dark", .darkAqua),
    ("high-contrast", .accessibilityHighContrastAqua),
  ]
  let widths: [(String, CGFloat)] = [("narrow", 240), ("normal", 480)]
  for (appearanceName, appearanceIdentifier) in appearances {
    for (widthName, width) in widths {
      let editor = fixture.editor()
      editor.appearance = NSAppearance(named: appearanceIdentifier)
      editor.setFrameSize(NSSize(width: width, height: 420))
      editor.drawsBackground = true
      editor.backgroundColor = .textBackgroundColor
      editor.textContainerInset = NSSize(width: 16, height: 10)
      editor.textContainer?.lineFragmentPadding = 0
      editor.textContainer?.widthTracksTextView = true
      editor.textContainer?.containerSize = NSSize(
        width: width,
        height: .greatestFiniteMagnitude
      )
      editor.textStorage?.setAttributedString(
        fixture.store.projectedContent(
          from: NSAttributedString(
            string: "Photo before\n\(reference)\nPhoto after",
            attributes: [
              .font: NSFont.systemFont(ofSize: 14),
              .foregroundColor: NSColor.textColor,
            ]
          )
        )
      )
      let textContainer = try #require(editor.textContainer)
      let layoutManager = try #require(editor.layoutManager)
      layoutManager.ensureLayout(for: textContainer)
      let attachmentLocation = (editor.string as NSString).range(of: "\u{fffc}").location
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: attachmentLocation, length: 1),
        actualCharacterRange: nil
      )
      let attachmentRect = layoutManager.boundingRect(
        forGlyphRange: glyphRange,
        in: textContainer
      ).offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
      #expect(attachmentRect.width > 0)
      #expect(attachmentRect.width <= width - 32 + 0.5)
      #expect(attachmentRect.height > 0 && attachmentRect.height <= 320.5)
      #expect(editor.bounds.insetBy(dx: 15.5, dy: 0).contains(attachmentRect))

      let bitmap = try #require(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
      editor.cacheDisplay(in: editor.bounds, to: bitmap)
      var bluePixels = 0
      var yellowPixels = 0
      var greenPixels = 0
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
            color.alphaComponent > 0.9
          else { continue }
          if color.blueComponent > 0.65
            && color.blueComponent > color.redComponent + 0.2
          {
            bluePixels += 1
          }
          if color.redComponent > 0.8
            && color.greenComponent > 0.55
            && color.blueComponent < 0.35
          {
            yellowPixels += 1
          }
          if color.greenComponent > color.redComponent + 0.15
            && color.greenComponent > color.blueComponent
          {
            greenPixels += 1
          }
        }
      }
      #expect(bluePixels > 100)
      #expect(yellowPixels > 20)
      #expect(greenPixels > 20)
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: evidenceDirectory)
          .appendingPathComponent("inline-image-\(appearanceName)-\(widthName).png")
      )
    }
  }
}

private func managedReferenceURLs(in source: String) throws -> [URL] {
  let expression = try NSRegularExpression(pattern: #"!\[[^\]]*\]\((file://[^)]+)\)"#)
  return expression.matches(
    in: source,
    range: NSRange(location: 0, length: (source as NSString).length)
  ).map { match in
    URL(string: (source as NSString).substring(with: match.range(at: 1)))!
  }
}

private func imagePixelSize(at url: URL) throws -> NSSize {
  let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
  let properties = try #require(
    CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
  )
  return NSSize(
    width: try #require(properties[kCGImagePropertyPixelWidth] as? NSNumber).doubleValue,
    height: try #require(properties[kCGImagePropertyPixelHeight] as? NSNumber).doubleValue
  )
}

private final class ExactSelectionTextView: NSTextView {
  var exactSelectedRange = NSRange(location: 0, length: 0)

  override func selectedRange() -> NSRange {
    exactSelectedRange
  }

  override func setSelectedRange(_ range: NSRange) {
    exactSelectedRange = range
  }
}

private struct NativeDragResult: Equatable {
  let entered: NSDragOperation
  let updated: NSDragOperation
  let prepared: Bool
  let performed: Bool
  let types: [NSPasteboard.PasteboardType]
}

@MainActor
private final class InlineImageDraggingInfo: NSObject, NSDraggingInfo {
  let draggingDestinationWindow: NSWindow?
  let draggingSourceOperationMask: NSDragOperation = .copy
  var draggingLocation: NSPoint
  let draggedImageLocation: NSPoint = .zero
  let draggedImage: NSImage? = nil
  let draggingPasteboard: NSPasteboard
  let draggingSource: Any? = nil
  let draggingSequenceNumber = 1
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = false
  var numberOfValidItemsForDrop: Int
  let springLoadingHighlight: NSSpringLoadingHighlight = .none

  init(
    window: NSWindow,
    location: NSPoint,
    pasteboard: NSPasteboard,
    itemCount: Int
  ) {
    draggingDestinationWindow = window
    draggingLocation = location
    draggingPasteboard = pasteboard
    numberOfValidItemsForDrop = itemCount
  }

  func slideDraggedImage(to screenPoint: NSPoint) {}

  override func namesOfPromisedFilesDropped(
    atDestination dropDestination: URL
  ) -> [String]? { nil }

  func enumerateDraggingItems(
    options enumOpts: NSDraggingItemEnumerationOptions,
    for view: NSView?,
    classes classArray: [AnyClass],
    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
    using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {}

  func resetSpringLoading() {}
}

@MainActor
private func offscreenWindow(containing textView: NSTextView) -> NSWindow {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  window.isReleasedWhenClosed = false
  window.contentView = textView
  if let textContainer = textView.textContainer {
    textView.layoutManager?.ensureLayout(for: textContainer)
  }
  return window
}

@MainActor
private func performNativeDestinationDrag(
  urls: [URL],
  on textView: NSTextView,
  in window: NSWindow
) -> NativeDragResult {
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  pasteboard.writeObjects(urls.map { $0 as NSURL })
  let info = InlineImageDraggingInfo(
    window: window,
    location: textView.convert(NSPoint(x: 20, y: 28), to: nil),
    pasteboard: pasteboard,
    itemCount: urls.count
  )
  let entered = textView.draggingEntered(info)
  let updated = textView.draggingUpdated(info)
  let prepared = textView.prepareForDragOperation(info)
  let performed = textView.performDragOperation(info)
  textView.concludeDragOperation(info)
  return NativeDragResult(
    entered: entered,
    updated: updated,
    prepared: prepared,
    performed: performed,
    types: pasteboard.types ?? []
  )
}

private func styledCanonicalText(_ text: String) -> NSAttributedString {
  let result = NSMutableAttributedString(
    string: text,
    attributes: [.font: NSFont(name: "Courier-Bold", size: 22)!]
  )
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .right
  let firstCharacterLength = String(text.first!).utf16.count
  result.addAttributes(
    [
      .paragraphStyle: paragraph,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .backgroundColor: NSColor.systemYellow,
    ],
    range: NSRange(location: 0, length: firstCharacterLength)
  )
  let tail = (text as NSString).range(of: "tail")
  result.addAttributes(
    [
      .font: NSFont(name: "Menlo", size: 18)!,
      .foregroundColor: NSColor.systemRed,
    ],
    range: tail
  )
  return result
}

private func assertCanonicalFormatting(
  _ text: NSAttributedString,
  exactBody: String
) {
  #expect(text.string.utf16.elementsEqual(exactBody.utf16))
  #expect((text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "Courier-Bold")
  #expect((text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 22)
  #expect((text.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 1)
  #expect((text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .right)
  #expect(text.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
  let tail = (text.string as NSString).range(of: "tail").location
  #expect((text.attribute(.font, at: tail, effectiveRange: nil) as? NSFont)?.familyName == "Menlo")
  #expect((text.attribute(.font, at: tail, effectiveRange: nil) as? NSFont)?.pointSize == 18)
}

@MainActor
private final class InlineImageFixture {
  let root: URL
  let store: InlineNoteImageStore

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("FleckInlineImage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = InlineNoteImageStore(
      rootURL: root.appendingPathComponent("managed", isDirectory: true)
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  func makeImage(name: String, width: Int, height: Int) throws -> URL {
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ))
    for y in 0..<height {
      for x in 0..<width {
        let horizontal = Double(x) / Double(max(1, width - 1))
        let vertical = Double(y) / Double(max(1, height - 1))
        let sun = hypot(horizontal - 0.78, vertical - 0.22) < 0.105
        let mountain = vertical > 0.48 + abs(horizontal - 0.55) * 0.75
        let treeCrown = hypot(horizontal - 0.20, vertical - 0.58) < 0.13
        let treeTrunk = (0.17...0.23).contains(horizontal) && (0.58...0.84).contains(vertical)
        let color: NSColor
        if treeCrown {
          color = NSColor(calibratedRed: 0.05, green: 0.42, blue: 0.16, alpha: 1)
        } else if treeTrunk {
          color = NSColor(calibratedRed: 0.38, green: 0.18, blue: 0.06, alpha: 1)
        } else if vertical > 0.78 {
          color = NSColor(calibratedRed: 0.18, green: 0.58, blue: 0.20, alpha: 1)
        } else if mountain {
          color = horizontal < 0.55
            ? NSColor(calibratedRed: 0.30, green: 0.34, blue: 0.42, alpha: 1)
            : NSColor(calibratedRed: 0.46, green: 0.40, blue: 0.36, alpha: 1)
        } else if sun {
          color = NSColor(calibratedRed: 1, green: 0.76, blue: 0.08, alpha: 1)
        } else {
          color = NSColor(
            calibratedRed: 0.12 + vertical * 0.18,
            green: 0.46 + vertical * 0.22,
            blue: 0.90,
            alpha: 1
          )
        }
        bitmap.setColor(color, atX: x, y: y)
      }
    }
    let url = root.appendingPathComponent(name)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    return url
  }

  func editor(text: String = "") -> ListAwareTextView {
    let editor = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
    editor.isRichText = true
    editor.importsGraphics = false
    editor.inlineImageStore = store
    editor.allowsUndo = true
    editor.string = text
    return editor
  }

  func pasteboard(urls: [URL]) -> NSPasteboard {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.writeObjects(urls.map { $0 as NSURL })
    return pasteboard
  }

  func nativeEditor(
    text: String,
    richTextRTF: Data? = nil,
    fontFamily: String? = nil,
    fontSize: Double = 14,
    commands: EditorCommands,
    onChange: @escaping (String, Data?) -> Void = { _, _ in }
  ) -> NativeRichTextEditor {
    NativeRichTextEditor(
      text: text,
      richTextRTF: richTextRTF,
      onChange: onChange,
      fontFamily: fontFamily ?? NSFont.systemFont(ofSize: 14).familyName ?? "Helvetica",
      fontSize: fontSize,
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
