import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor func NoteLinkEditorInsertionIsOneUndoableRealTextViewEdit() throws {
  let textView = ListAwareTextView(frame: .zero)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  let recorder = NoteLinkEditorChangeRecorder()
  textView.delegate = recorder
  textView.string = "Before [[ after"
  textView.undoManager?.removeAllActions()

  let commands = EditorCommands()
  commands.textView = textView
  let target = UUID()
  let trigger = NSRange(location: 7, length: 2)

  #expect(commands.insertNoteLink(replacing: trigger, label: "Target", targetNoteID: target))
  #expect(
    textView.string == "Before \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) after"
  )
  #expect(recorder.count == 1)
  #expect(textView.undoManager?.canUndo == true)

  textView.undoManager?.undo()
  #expect(textView.string == "Before [[ after")
  textView.undoManager?.redo()
  #expect(textView.string.contains("fleck://note/\(target.uuidString)"))
}

@Test @MainActor func NoteLinkEditorRejectsOutOfBoundsReplacementRanges() {
  let textView = NSTextView()
  textView.string = "body"
  let commands = EditorCommands()
  commands.textView = textView

  #expect(
    !commands.insertNoteLink(
      replacing: NSRange(location: 5, length: 0),
      label: "Target",
      targetNoteID: UUID()
    )
  )
  #expect(textView.string == "body")
}

@Test @MainActor func NoteLinkPresentationUsesOnlyTemporaryAttributes() throws {
  let target = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let text = "Before \(token) after"
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  textView.string = text
  let range = NSRange(location: 0, length: text.utf16.count)
  let font = try #require(NSFont(name: "Helvetica-Bold", size: 18))
  let paragraph = NSMutableParagraphStyle()
  paragraph.firstLineHeadIndent = 14
  textView.textStorage?.addAttributes(
    [
      .font: font,
      .foregroundColor: NSColor.systemRed,
      .backgroundColor: NSColor.systemYellow,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .paragraphStyle: paragraph,
    ],
    range: range
  )
  textView.typingAttributes = [
    .font: font,
    .foregroundColor: NSColor.systemBlue,
    .backgroundColor: NSColor.systemGreen,
  ]
  textView.setSelectedRange(NSRange(location: 2, length: 4))
  textView.undoManager?.registerUndo(withTarget: textView) { _ in }

  let originalString = textView.string
  let originalAttributed = NSAttributedString(attributedString: try #require(textView.textStorage))
  let originalRTFData = try textView.textStorage?.data(
    from: range,
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let originalRTF = try #require(originalRTFData)
  let originalSelection = textView.selectedRange()
  let originalTypingAttributes = NSDictionary(dictionary: textView.typingAttributes)
  let originalCanUndo = try #require(textView.undoManager).canUndo
  let link = try #require(NoteLinkParser.links(in: text).first)

  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  let yellow = try #require(NSColor(hex: "#FFD600"))
  #expect(sRGBColor(textView.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: link.range.location, effectiveRange: nil) as? NSColor) == sRGBColor(yellow))
  #expect((textView.layoutManager?.temporaryAttribute(.underlineStyle, atCharacterIndex: link.range.location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)

  textView.refreshNoteLinks(accentColorHex: "#30D158", liveNoteIDs: [target])
  let green = try #require(NSColor(hex: "#30D158"))
  #expect(sRGBColor(textView.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: link.range.location, effectiveRange: nil) as? NSColor) == sRGBColor(green))
  #expect(textView.string == originalString)
  #expect(NSAttributedString(attributedString: try #require(textView.textStorage)).isEqual(to: originalAttributed))
  let currentRTF = try textView.textStorage?.data(
    from: range,
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  #expect(currentRTF == originalRTF)
  #expect(textView.selectedRange() == originalSelection)
  #expect(NSDictionary(dictionary: textView.typingAttributes).isEqual(to: originalTypingAttributes))
  #expect(textView.undoManager?.canUndo == originalCanUndo)
  #expect(textView.textStorage?.attribute(.link, at: link.range.location, effectiveRange: nil) == nil)
}

@Test @MainActor func NoteLinkPresentationRestoresPreexistingTemporaryAttributesAfterLinkRemoval() throws {
  let target = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 160))
  textView.string = "Before \(token) after"
  let link = try #require(NoteLinkParser.links(in: textView.string).first)
  let firstHalf = NSRange(location: link.range.location, length: link.range.length / 2)
  let secondHalf = NSRange(
    location: NSMaxRange(firstHalf),
    length: link.range.length - firstHalf.length
  )
  let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
  textView.textStorage?.addAttribute(
    .foregroundColor,
    value: NSColor.systemPurple,
    range: fullRange
  )
  textView.layoutManager?.addTemporaryAttribute(
    .foregroundColor,
    value: NSColor.systemBlue,
    forCharacterRange: firstHalf
  )
  textView.layoutManager?.addTemporaryAttribute(
    .foregroundColor,
    value: NSColor.systemGreen,
    forCharacterRange: secondHalf
  )
  textView.layoutManager?.addTemporaryAttribute(
    .underlineStyle,
    value: NSUnderlineStyle.double.rawValue,
    forCharacterRange: secondHalf
  )

  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  textView.clearNoteLinkPresentation()

  #expect(
    sRGBColor(
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: firstHalf.location,
        effectiveRange: nil
      ) as? NSColor
    ) == sRGBColor(.systemBlue)
  )
  #expect(
    sRGBColor(
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: secondHalf.location,
        effectiveRange: nil
      ) as? NSColor
    ) == sRGBColor(.systemGreen)
  )
  #expect(
    textView.layoutManager?.temporaryAttribute(
      .underlineStyle,
      atCharacterIndex: secondHalf.location,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.double.rawValue
  )
}

@Test @MainActor func NoteLinkPresentationRealEditControlMatchesAppKitTemporaryAttributeLifecycle() throws {
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 160))
  textView.string = "Before Target after"
  let targetRange = NSRange(location: 7, length: 6)
  textView.layoutManager?.addTemporaryAttribute(
    .foregroundColor,
    value: NSColor.systemBlue,
    forCharacterRange: targetRange
  )
  textView.layoutManager?.addTemporaryAttribute(
    .underlineStyle,
    value: NSUnderlineStyle.double.rawValue,
    forCharacterRange: targetRange
  )

  textView.setSelectedRange(NSRange(location: 0, length: 0))
  textView.insertText("X", replacementRange: textView.selectedRange())
  textView.setSelectedRange(
    NSRange(location: targetRange.location + 1, length: targetRange.length)
  )
  textView.insertText(
    String(repeating: "x", count: targetRange.length),
    replacementRange: textView.selectedRange()
  )

  #expect(
    sRGBColor(
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: targetRange.location + 1,
        effectiveRange: nil
      ) as? NSColor
    ) == nil
  )
  #expect(
    textView.layoutManager?.temporaryAttribute(
      .underlineStyle,
      atCharacterIndex: targetRange.location + 1,
      effectiveRange: nil
    ) as? Int == nil
  )
}

@Test @MainActor func NoteLinkPresentationTracksRealEditShiftsBeforeRestoringTemporarySlices() throws {
  let target = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 160))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 520, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.string = "Before \(token) after"
  let originalLink = try #require(NoteLinkParser.links(in: textView.string).first)
  let firstHalf = NSRange(location: originalLink.range.location, length: originalLink.range.length / 2)
  let secondHalf = NSRange(
    location: NSMaxRange(firstHalf),
    length: originalLink.range.length - firstHalf.length
  )
  textView.layoutManager?.addTemporaryAttribute(
    .foregroundColor,
    value: NSColor.systemBlue,
    forCharacterRange: firstHalf
  )
  textView.layoutManager?.addTemporaryAttribute(
    .foregroundColor,
    value: NSColor.systemGreen,
    forCharacterRange: secondHalf
  )
  textView.layoutManager?.addTemporaryAttribute(
    .underlineStyle,
    value: NSUnderlineStyle.double.rawValue,
    forCharacterRange: secondHalf
  )
  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])

  textView.setSelectedRange(NSRange(location: 0, length: 0))
  textView.insertText("X", replacementRange: textView.selectedRange())
  let shiftedLink = try #require(NoteLinkParser.links(in: textView.string).first)
  #expect(shiftedLink.range.location == originalLink.range.location + 1)
  #expect(
    sRGBColor(
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: firstHalf.location + 1,
        effectiveRange: nil
      ) as? NSColor
    ) == sRGBColor(.systemBlue)
  )
  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  #expect(
    textView.layoutManager?.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: originalLink.range.location,
      effectiveRange: nil
    ) as? NSColor == nil
  )
  let accent = try #require(NSColor(hex: "#FFD600"))
  #expect(
    sRGBColor(
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: shiftedLink.range.location,
        effectiveRange: nil
      ) as? NSColor
    ) == sRGBColor(accent)
  )
  #expect(
    textView.layoutManager?.temporaryAttribute(
      .underlineStyle,
      atCharacterIndex: shiftedLink.range.location,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.single.rawValue
  )
  textView.clearNoteLinkPresentation()

  #expect(
    sRGBColor(
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: firstHalf.location + 1,
        effectiveRange: nil
      ) as? NSColor
    ) == sRGBColor(.systemBlue)
  )
  #expect(
    sRGBColor(
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: secondHalf.location + 1,
        effectiveRange: nil
      ) as? NSColor
    ) == sRGBColor(.systemGreen)
  )
  #expect(
    textView.layoutManager?.temporaryAttribute(
      .underlineStyle,
      atCharacterIndex: secondHalf.location + 1,
      effectiveRange: nil
    ) as? Int == NSUnderlineStyle.double.rawValue
  )
  #expect(
    textView.layoutManager?.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: originalLink.range.location,
      effectiveRange: nil
    ) as? NSColor == nil
  )
}

@Test @MainActor func NoteLinkPresentationKeepsNewCustomEditorColorAfterLinkRemoval() throws {
  let target = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 160))
  textView.string = "Before \(token) after"
  let link = try #require(NoteLinkParser.links(in: textView.string).first)
  let authoredRange = NSRange(location: 0, length: textView.string.utf16.count)
  let authoredAttributed = NSAttributedString(
    attributedString: try #require(textView.textStorage)
  )
  let authoredRTF = try textView.textStorage?.data(
    from: authoredRange,
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )

  NativeRichTextEditor.applyAppearance(
    to: textView,
    textColorHex: "#FF4245",
    backgroundColorHex: nil
  )
  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  NativeRichTextEditor.applyAppearance(
    to: textView,
    textColorHex: "#30D158",
    backgroundColorHex: nil
  )
  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  textView.clearNoteLinkPresentation()

  #expect(
    sRGBColor(
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: link.range.location,
        effectiveRange: nil
      ) as? NSColor
    ) == sRGBColor(NSColor(hex: "#30D158"))
  )
  #expect(
    NSAttributedString(attributedString: try #require(textView.textStorage))
      .isEqual(to: authoredAttributed)
  )
  let currentRTF = try textView.textStorage?.data(
    from: authoredRange,
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  #expect(currentRTF == authoredRTF)
}

@Test @MainActor func NoteLinkPresentationDistinguishesBrokenLinksWithoutColorAlone() throws {
  let target = UUID()
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
  textView.string = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let link = try #require(NoteLinkParser.links(in: textView.string).first)

  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [])

  #expect(
    sRGBColor(
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: link.range.location,
        effectiveRange: nil
      ) as? NSColor
    ) == sRGBColor(.systemOrange)
  )
  let underline = try #require(
    textView.layoutManager?.temporaryAttribute(
      .underlineStyle,
      atCharacterIndex: link.range.location,
      effectiveRange: nil
    ) as? Int
  )
  #expect(underline & NSUnderlineStyle.patternDot.rawValue == NSUnderlineStyle.patternDot.rawValue)
}

@Test @MainActor func NoteLinkEditorSelectionLookupAndContextActionsUseTheCurrentLink() throws {
  let target = UUID()
  let textView = ListAwareTextView(frame: .zero)
  textView.string = "x \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) y"
  let commands = EditorCommands()
  commands.textView = textView
  let link = try #require(NoteLinkParser.links(in: textView.string).first)
  textView.setSelectedRange(NSRange(location: link.range.location + 2, length: 3))

  #expect(commands.noteLinkAtSelection() == link)
  var requestedRange: NSRange?
  var openedID: UUID?
  textView.onRequestNoteLink = { requestedRange = $0 }
  textView.onOpenNoteLink = { openedID = $0 }
  textView.requestNoteLinkFromMenu(nil)
  textView.openNoteLinkFromMenu(nil)

  #expect(requestedRange == textView.selectedRange())
  #expect(openedID == nil)

  textView.liveNoteIDs = [target]
  textView.openNoteLinkFromMenu(nil)
  #expect(openedID == target)
}

@Test @MainActor func NoteLinkEditorCommandClickOpensOnlyParsedLinks() throws {
  let target = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 160))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 520, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.string = "x \(token) y"
  textView.liveNoteIDs = [target]
  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  let link = try #require(NoteLinkParser.links(in: textView.string).first)
  let container = try #require(textView.textContainer)
  textView.layoutManager?.ensureLayout(for: container)
  let glyphRange = textView.layoutManager?.glyphRange(forCharacterRange: link.range, actualCharacterRange: nil) ?? NSRange(location: 0, length: 0)
  let rect = try #require(textView.layoutManager?.boundingRect(forGlyphRange: glyphRange, in: container))
  let point = textView.convert(NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y), to: nil)
  let event = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: point,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 1,
      pressure: 1
    )
  )
  var openedID: UUID?
  textView.onOpenNoteLink = { openedID = $0 }

  textView.mouseDown(with: event)

  #expect(openedID == target)
  #expect(textView.string == "x \(token) y")
}

@Test @MainActor func NoteLinkEditorCommandClickInTrailingWhitespaceDoesNotOpenTheNearestLink() throws {
  let target = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 160))
  textView.string = "x \(token)     "
  textView.liveNoteIDs = [target]
  textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])
  let link = try #require(NoteLinkParser.links(in: textView.string).first)
  let container = try #require(textView.textContainer)
  textView.layoutManager?.ensureLayout(for: container)
  let glyphRange = textView.layoutManager?.glyphRange(
    forCharacterRange: link.range,
    actualCharacterRange: nil
  ) ?? NSRange(location: 0, length: 0)
  let linkRect = try #require(
    textView.layoutManager?.boundingRect(forGlyphRange: glyphRange, in: container)
  )
  let linkPoint = NSPoint(
    x: linkRect.midX + textView.textContainerOrigin.x,
    y: linkRect.midY + textView.textContainerOrigin.y
  )
  let trailingPoint = NSPoint(
    x: linkRect.maxX + 8 + textView.textContainerOrigin.x,
    y: linkRect.midY + textView.textContainerOrigin.y
  )

  #expect(textView.noteLinkTarget(atViewPoint: linkPoint) == target)
  #expect(textView.noteLinkTarget(atViewPoint: trailingPoint) == nil)
}

@Test @MainActor func NoteLinkEditorContextMenuDeduplicatesItemsAndValidatesLiveSelection() throws {
  let target = UUID()
  let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.string = "x \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)) y"
  let link = try #require(NoteLinkParser.links(in: textView.string).first)
  textView.setSelectedRange(link.range)
  let container = try #require(textView.textContainer)
  textView.layoutManager?.ensureLayout(for: container)
  let glyphRange = textView.layoutManager?.glyphRange(
    forCharacterRange: link.range,
    actualCharacterRange: nil
  ) ?? NSRange(location: 0, length: 0)
  let linkRect = try #require(
    textView.layoutManager?.boundingRect(forGlyphRange: glyphRange, in: container)
  )
  let eventLocation = textView.convert(
    NSPoint(
      x: linkRect.midX + textView.textContainerOrigin.x,
      y: linkRect.midY + textView.textContainerOrigin.y
    ),
    to: nil
  )
  let event = try #require(
    NSEvent.mouseEvent(
      with: .rightMouseDown,
      location: eventLocation,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 3,
      clickCount: 1,
      pressure: 1
    )
  )

  let firstMenu = try #require(textView.menu(for: event))
  let secondMenu = try #require(textView.menu(for: event))
  let firstRequestItems = firstMenu.items.filter {
    $0.action == #selector(ListAwareTextView.requestNoteLinkFromMenu(_:))
  }
  let firstOpenItems = firstMenu.items.filter {
    $0.action == #selector(ListAwareTextView.openNoteLinkFromMenu(_:))
  }
  let requestItems = secondMenu.items.filter {
    $0.action == #selector(ListAwareTextView.requestNoteLinkFromMenu(_:))
  }
  let openItems = secondMenu.items.filter {
    $0.action == #selector(ListAwareTextView.openNoteLinkFromMenu(_:))
  }
  #expect(firstRequestItems.count == 1)
  #expect(firstOpenItems.count == 1)
  #expect(requestItems.count == 1)
  #expect(openItems.count == 1)
  let openItem = try #require(openItems.first)
  #expect(!textView.validateMenuItem(openItem))

  textView.liveNoteIDs = [target]
  #expect(textView.validateMenuItem(openItem))
  textView.setSelectedRange(NSRange(location: 0, length: 0))
  #expect(!textView.validateMenuItem(openItem))
  textView.setSelectedRange(link.range)
  textView.isEditable = false
  #expect(!textView.validateMenuItem(try #require(requestItems.first)))
}

@Test @MainActor func NoteLinkPickerRejectsStaleSourceRevisionBeforeArbitraryReplacement() async {
  let source = Note(id: UUID(), title: "Source", body: "Source body", revision: 7)
  let target = Note(id: UUID(), title: "Target", body: "Target body", revision: 2)
  let controller = NoteLinkPickerController(searchOperation: { _, notes, _ in
    notes.map { note in
      WorkspaceSearchResult(
        noteID: note.id,
        displayTitle: note.displayTitle,
        snippet: note.body,
        match: WorkspaceSearchMatch(field: .title, location: 0, length: 1),
        score: 1
      )
    }
  })
  let replacementRange = NSRange(location: 2, length: 4)
  controller.present(
    sourceNoteID: source.id,
    replacementRange: replacementRange,
    sourceRevision: source.revision
  )
  controller.setQuery(target.title, in: [source, target])
  await settleNoteLinkPicker()

  var activations: [(UUID, NSRange)] = []
  #expect(
    !controller.activateResult(
      target.id,
      currentNoteIDs: Set([source.id, target.id]),
      currentSourceNoteID: source.id,
      currentSourceRevision: source.revision + 1,
      activate: { activations.append(($0, $1)) }
    )
  )
  #expect(activations.isEmpty)
  #expect(!controller.isPresented)

  controller.present(
    sourceNoteID: source.id,
    replacementRange: replacementRange,
    sourceRevision: source.revision + 1
  )
  controller.setQuery(target.title, in: [source, target])
  await settleNoteLinkPicker()
  #expect(
    controller.activateResult(
      target.id,
      currentNoteIDs: Set([source.id, target.id]),
      currentSourceNoteID: source.id,
      currentSourceRevision: source.revision + 1,
      activate: { activations.append(($0, $1)) }
    )
  )
  #expect(activations.count == 1)
  #expect(activations.first?.0 == target.id)
  #expect(activations.first?.1 == replacementRange)
}

@Test @MainActor func NoteLinkEditorReportsDoubleBracketTriggerOnce() {
  var requests: [NSRange] = []
  let commands = EditorCommands()
  let editor = NativeRichTextEditor(
    text: "",
    richTextRTF: nil,
    onChange: { _, _ in },
    fontFamily: "System",
    fontSize: 14,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#FFD600",
    reduceMotion: true,
    automaticLists: false,
    commands: commands,
    onRequestNoteLink: { requests.append($0) }
  )
  let coordinator = editor.makeCoordinator()
  let textView = ListAwareTextView(frame: .zero)
  commands.textView = textView
  textView.delegate = coordinator
  textView.string = "Before [["
  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  let notification = Notification(name: NSText.didChangeNotification, object: textView)

  coordinator.textDidChange(notification)
  coordinator.textDidChange(notification)

  #expect(requests == [NSRange(location: 7, length: 2)])
}

private final class NoteLinkEditorChangeRecorder: NSObject, NSTextViewDelegate {
  var count = 0

  func textDidChange(_ notification: Notification) {
    count += 1
  }
}

private func sRGBColor(_ color: NSColor?) -> [Int]? {
  guard let color = color?.usingColorSpace(.sRGB) else { return nil }
  return [
    Int((color.redComponent * 255).rounded()),
    Int((color.greenComponent * 255).rounded()),
    Int((color.blueComponent * 255).rounded()),
    Int((color.alphaComponent * 255).rounded()),
  ]
}

@MainActor
private func settleNoteLinkPicker() async {
  for _ in 0..<20 {
    await Task.yield()
  }
}
