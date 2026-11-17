#if os(macOS)
  import AppKit
  import FleckCore
  import Testing

  @testable import FleckApp

  @MainActor
  private func composingEditor(
    _ text: String,
    palette: FleckThemePalette
  ) -> (ListAwareTextView, NSWindow) {
    let frame = NSRect(x: 0, y: 0, width: 520, height: 240)
    let view = ListAwareTextView(frame: frame)
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = view
    view.textStorage?.setAttributedString(
      NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: 17),
        .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 17),
      ])
    )
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    NativeRichTextEditor.applyAppearance(to: view, palette: palette)
    view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
    return (view, window)
  }

  @MainActor
  private func presentedInk(
    _ view: ListAwareTextView,
    at location: Int
  ) -> NSColor? {
    view.layoutManager?.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: location,
      effectiveRange: nil
    ) as? NSColor
  }

  private func sRGB(_ color: NSColor) -> [Int] {
    let converted = color.usingColorSpace(.sRGB) ?? color
    return [
      Int((converted.redComponent * 255).rounded()),
      Int((converted.greenComponent * 255).rounded()),
      Int((converted.blueComponent * 255).rounded()),
      Int((converted.alphaComponent * 255).rounded()),
    ]
  }

  @Test(arguments: [FleckThemeAppearance.dark, FleckThemeAppearance.light])
  @MainActor func composingRunWearsTheNotesInk(appearance: FleckThemeAppearance) throws {
    let palette = FleckThemePalette.resolve(family: .monochrome, appearance: appearance)
    let expected = try #require(NSColor(hex: palette[.textPrimary]))
    let (view, window) = composingEditor("Notebook ", palette: palette)
    defer { window.contentView = nil }

    view.setMarkedText(
      "nihao",
      selectedRange: NSRange(location: 5, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0)
    )

    let marked = view.markedRange()
    #expect(marked.location != NSNotFound)
    #expect(view.hasMarkedText())
    #expect(view.textStorage?.attribute(.foregroundColor, at: marked.location, effectiveRange: nil) == nil)
    let composingInk = try #require(presentedInk(view, at: marked.location))
    #expect(sRGB(composingInk) == sRGB(expected))
    #expect(sRGB(composingInk) != sRGB(.black))

    view.unmarkText()

    #expect(!view.hasMarkedText())
    #expect(view.string == "Notebook nihao")
    let committedInk = try #require(presentedInk(view, at: marked.location))
    #expect(sRGB(committedInk) == sRGB(expected))
  }

  @Test @MainActor func composingRunFollowsANewThemeMidComposition() throws {
    let dark = FleckThemePalette.resolve(family: .monochrome, appearance: .dark)
    let light = FleckThemePalette.resolve(family: .monochrome, appearance: .light)
    let (view, window) = composingEditor("Notebook ", palette: dark)
    defer { window.contentView = nil }

    view.setMarkedText(
      "zhong",
      selectedRange: NSRange(location: 5, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    let marked = view.markedRange()
    #expect(
      presentedInk(view, at: marked.location).map(sRGB)
        == NSColor(hex: dark[.textPrimary]).map(sRGB)
    )

    NativeRichTextEditor.applyAppearance(to: view, palette: light)

    let relitInk = try #require(presentedInk(view, at: marked.location))
    let expectedLight = try #require(NSColor(hex: light[.textPrimary]))
    #expect(sRGB(relitInk) == sRGB(expectedLight))
    #expect(view.hasMarkedText())
  }
#endif
