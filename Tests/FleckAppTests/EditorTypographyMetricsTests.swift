import AppKit
import Testing

@testable import FleckApp

@MainActor
private func metricsEditor(_ body: String) -> (NSWindow, ListAwareTextView, EditorCommands) {
  let frame = NSRect(x: 0, y: 0, width: 520, height: 260)
  let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  let textView = ListAwareTextView(frame: frame)
  window.contentView = textView
  textView.isEditable = true
  textView.isSelectable = true
  textView.allowsUndo = true
  textView.textStorage?.setAttributedString(
    NSAttributedString(
      string: body,
      attributes: EditorTypography.defaultAttributes(
        family: ".AppleSystemUIFont",
        size: 17
      )
    )
  )
  let commands = EditorCommands()
  commands.configureBodyDefaults(family: ".AppleSystemUIFont", size: 17)
  commands.textView = textView
  window.makeFirstResponder(textView)
  return (window, textView, commands)
}

@Test @MainActor func editorTabGridMatchesTheSourceIndentUnit() throws {
  let bodyFont = EditorTypography.bodyFont(family: ".AppleSystemUIFont", size: 17)
  let unit = EditorTypography.indentWidth(font: bodyFont)
  let style = EditorTypography.systemDefaultParagraphStyle(fontSize: 17)

  #expect(EditorTypography.indentSpaces == EditorListEngine.indentation.count)
  let fourSpaces = (" " as NSString).size(withAttributes: [.font: bodyFont]).width * 4
  #expect(abs(unit - fourSpaces) < 0.01)
  #expect(abs(style.defaultTabInterval - unit) < 0.01)
  #expect(EditorTypography.hasOnlyDefaultTabStops(style))
  #expect(abs(style.minimumLineHeight - 27) < 0.01)
  #expect(abs(style.maximumLineHeight - 27) < 0.01)
}

@Test @MainActor func editorBodyDefaultsCarryParagraphSpacing() throws {
  let attributes = EditorTypography.defaultAttributes(family: ".AppleSystemUIFont", size: 17)
  let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)

  #expect(abs(paragraph.paragraphSpacing - EditorTypography.bodyParagraphSpacing) < 0.01)
  #expect(abs(paragraph.paragraphSpacingBefore) < 0.01)
  #expect(abs(paragraph.minimumLineHeight - 27) < 0.01)
}

@Test @MainActor func headingStylesKeepHierarchyAndSpacing() throws {
  let body = "heading under test"
  let (window, textView, commands) = metricsEditor(body)
  defer { closeEditorTestWindow(window) }
  let storage = try #require(textView.textStorage)
  let fullRange = NSRange(location: 0, length: (body as NSString).length)
  textView.setSelectedRange(fullRange)

  var sizes: [CGFloat] = []
  for style in [EditorTextStyle.heading1, .heading2, .heading3] {
    textView.setSelectedRange(fullRange)
    #expect(commands.applyTextStyle(style))
    let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    let paragraph = try #require(
      storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    )
    sizes.append(font.pointSize)
    #expect(
      NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    )
    #expect(abs(paragraph.minimumLineHeight - EditorTypography.lineHeight(fontSize: font.pointSize)) < 0.01)
    #expect(paragraph.paragraphSpacingBefore > paragraph.paragraphSpacing)
  }

  #expect(sizes[0] > sizes[1])
  #expect(sizes[1] > sizes[2])
  #expect(sizes[2] > 17)
  #expect(abs(sizes[0] - 17 * 1.6) < 0.01)
  #expect(abs(sizes[1] - 17 * 1.35) < 0.01)
  #expect(abs(sizes[2] - 17 * 1.15) < 0.01)
}

@Test @MainActor func everyPresetPinsItsExactSpacing() throws {
  let expectations: [(EditorTextStyle, CGFloat, CGFloat)] = [
    (.normal, 0, 8),
    (.heading1, 16, 8),
    (.heading2, 12, 6),
    (.heading3, 8, 4),
    (.quote, 8, 8),
    (.code, 4, 4),
  ]
  for (style, before, after) in expectations {
    let (window, textView, commands) = metricsEditor("spacing preset")
    defer { closeEditorTestWindow(window) }
    let storage = try #require(textView.textStorage)
    let neutral = NSMutableParagraphStyle()
    neutral.paragraphSpacingBefore = 1
    neutral.paragraphSpacing = 1
    storage.addAttribute(
      .paragraphStyle,
      value: neutral,
      range: NSRange(location: 0, length: storage.length)
    )
    textView.setSelectedRange(NSRange(location: 0, length: storage.length))
    #expect(commands.applyTextStyle(style))
    let paragraph = try #require(
      storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    )
    #expect(paragraph.paragraphSpacingBefore == before, "\(style.rawValue) before")
    #expect(paragraph.paragraphSpacing == after, "\(style.rawValue) after")
  }
}

@Test @MainActor func toolbarRecognizesPresetsWithoutChangingParagraphGeometry() throws {
  let (window, textView, commands) = metricsEditor("First paragraph\nSecond paragraph")
  defer { closeEditorTestWindow(window) }
  let storage = try #require(textView.textStorage)
  let fullRange = NSRange(location: 0, length: storage.length)
  textView.setSelectedRange(fullRange)

  for style in EditorTextStyle.allCases {
    _ = commands.applyTextStyle(style)
    let paragraph = try #require(
      (storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
        as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
    )
    paragraph.alignment = .right
    paragraph.headIndent = 19
    paragraph.firstLineHeadIndent = 7
    paragraph.lineSpacing = 3
    paragraph.defaultTabInterval = 72
    paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 90, options: [:])]
    storage.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
    let before = NSAttributedString(attributedString: storage)

    commands.refreshFormattingState()

    #expect(commands.currentTextStyle == style)
    #expect(!commands.isTextStyleMixed)
    #expect(storage.isEqual(to: before))
  }
}

@Test @MainActor func toolbarRecognizesTypingPresetsWithoutChangingTypingAttributes() throws {
  let (window, textView, commands) = metricsEditor("")
  defer { closeEditorTestWindow(window) }

  for style in EditorTextStyle.allCases {
    #expect(commands.applyTextStyle(style))
    let before = NSDictionary(dictionary: textView.typingAttributes)

    commands.refreshFormattingState()

    #expect(commands.currentTextStyle == style)
    #expect(!commands.isTextStyleMixed)
    #expect(NSDictionary(dictionary: textView.typingAttributes).isEqual(before))
  }
}

@Test @MainActor func toolbarRejectsAMixedParagraphPreset() throws {
  let body = "First paragraph\nSecond paragraph"
  let (window, textView, commands) = metricsEditor(body)
  defer { closeEditorTestWindow(window) }
  let storage = try #require(textView.textStorage)
  let fullRange = NSRange(location: 0, length: storage.length)
  let secondRange = (body as NSString).paragraphRange(
    for: NSRange(location: ("First paragraph\n" as NSString).length, length: 0)
  )
  textView.setSelectedRange(fullRange)
  #expect(commands.applyTextStyle(.heading2))
  let paragraph = try #require(
    (storage.attribute(.paragraphStyle, at: secondRange.location, effectiveRange: nil)
      as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
  )
  paragraph.paragraphSpacing += 2
  storage.addAttribute(.paragraphStyle, value: paragraph, range: secondRange)

  commands.refreshFormattingState()

  #expect(commands.currentTextStyle == nil)
  #expect(commands.isTextStyleMixed)
  textView.setSelectedRange(NSRange(location: 0, length: 0))
  commands.refreshFormattingState()
  #expect(commands.currentTextStyle == .heading2)
}

@Test @MainActor func codeParagraphKeepsMonospacedBodySizedText() throws {
  let body = "let value = 42"
  let (window, textView, commands) = metricsEditor(body)
  defer { closeEditorTestWindow(window) }
  let storage = try #require(textView.textStorage)
  textView.setSelectedRange(NSRange(location: 0, length: (body as NSString).length))

  #expect(commands.applyTextStyle(.code))
  let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  let paragraph = try #require(
    storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )

  #expect(NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask))
  #expect(abs(font.pointSize - 17) < 0.01)
  #expect(abs(paragraph.minimumLineHeight - 27) < 0.01)
}

@Test @MainActor func multiLineBlockIndentMovesExactlyOneGridStep() throws {
  let body = "first line\nsecond line"
  let (window, textView, commands) = metricsEditor(body)
  defer { closeEditorTestWindow(window) }
  let storage = try #require(textView.textStorage)
  let unit = EditorTypography.indentWidth(
    font: EditorTypography.bodyFont(family: ".AppleSystemUIFont", size: 17)
  )
  textView.setSelectedRange(NSRange(location: 0, length: (body as NSString).length))

  #expect(commands.increaseIndent())
  let first = try #require(
    storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  let second = try #require(
    storage.attribute(.paragraphStyle, at: (body as NSString).range(of: "second").location,
      effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(first.headIndent - unit) < 0.01)
  #expect(abs(second.headIndent - unit) < 0.01)
  #expect(textView.string == body)

  #expect(commands.increaseIndent())
  let doubled = try #require(
    storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(doubled.headIndent - unit * 2) < 0.01)

  #expect(commands.decreaseIndent())
  #expect(commands.decreaseIndent())
  let cleared = try #require(
    storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(cleared.headIndent) < 0.01)
  #expect(textView.string == body)
}

@Test @MainActor func blockIndentStepsByTheBodyGridInsideHeadingParagraphs() throws {
  let body = "A heading that gets indented"
  let (window, textView, commands) = metricsEditor(body)
  defer { closeEditorTestWindow(window) }
  let storage = try #require(textView.textStorage)
  let unit = EditorTypography.indentWidth(
    font: EditorTypography.bodyFont(family: ".AppleSystemUIFont", size: 17)
  )
  textView.setSelectedRange(NSRange(location: 0, length: storage.length))
  #expect(commands.applyTextStyle(.heading1))

  textView.setSelectedRange(NSRange(location: 0, length: (body as NSString).length))
  #expect(commands.increaseIndent())

  let paragraph = try #require(
    storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(paragraph.headIndent - unit) < 0.01)
  #expect(abs(paragraph.firstLineHeadIndent - unit) < 0.01)
}

@Test @MainActor func resizedRunIndentsByTheBodyGrid() throws {
  let body = "Text enlarged past the body size"
  let (window, textView, commands) = metricsEditor(body)
  defer { closeEditorTestWindow(window) }
  let storage = try #require(textView.textStorage)
  let unit = EditorTypography.indentWidth(
    font: EditorTypography.bodyFont(family: ".AppleSystemUIFont", size: 17)
  )
  let resized = NSFont.systemFont(ofSize: 24)
  storage.addAttribute(.font, value: resized, range: NSRange(location: 0, length: storage.length))
  textView.typingAttributes[.font] = resized

  textView.setSelectedRange(NSRange(location: 0, length: (body as NSString).length))
  #expect(commands.increaseIndent())

  let paragraph = try #require(
    storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(paragraph.headIndent - unit) < 0.01)
}

@Test @MainActor func resizedRunKeepsListTabsOnTheBodyGrid() throws {
  let (window, textView, _) = metricsEditor("• item")
  defer { closeEditorTestWindow(window) }
  let storage = try #require(textView.textStorage)
  let unit = EditorTypography.indentWidth(
    font: EditorTypography.bodyFont(family: ".AppleSystemUIFont", size: 17)
  )
  let resized = NSFont.systemFont(ofSize: 24)
  storage.addAttribute(.font, value: resized, range: NSRange(location: 0, length: storage.length))
  textView.typingAttributes[.font] = resized

  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.insertTab(nil)

  #expect(textView.string == "• \titem")
  let paragraph = try #require(
    storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(paragraph.defaultTabInterval - unit) < 0.05)
  #expect(paragraph.tabStops.isEmpty)
}

@Test @MainActor func resizedRunKeepsBlockIndentTabsOnTheBodyGrid() throws {
  let body = "A selected line of enlarged text"
  let (window, textView, commands) = metricsEditor(body)
  defer { closeEditorTestWindow(window) }
  let storage = try #require(textView.textStorage)
  let unit = EditorTypography.indentWidth(
    font: EditorTypography.bodyFont(family: ".AppleSystemUIFont", size: 17)
  )
  let resized = NSFont.systemFont(ofSize: 24)
  storage.addAttribute(.font, value: resized, range: NSRange(location: 0, length: storage.length))

  textView.setSelectedRange(NSRange(location: 2, length: 6))
  #expect(commands.increaseIndent())

  let paragraph = try #require(
    storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(paragraph.headIndent - unit) < 0.01)
  #expect(abs(paragraph.firstLineHeadIndent - unit) < 0.01)
}
