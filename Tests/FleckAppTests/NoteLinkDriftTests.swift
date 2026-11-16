#if os(macOS)
  import AppKit
  import FleckCore
  import Testing

  @testable import FleckApp

  @Test @MainActor func staleNoteLinkUsesADashedUnderlineAndACurrentOneDoesNot() throws {
    let currentID = UUID()
    let staleID = UUID()
    let missingID = UUID()
    let current = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: currentID)
    let stale = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: staleID)
    let missing = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: missingID)
    let text = "A \(current) B \(stale) C \(missing)"
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 200))
    textView.string = text
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.refreshNoteLinks(
      accentColorHex: "#FFD600",
      liveNoteIDs: [currentID, staleID],
      noteLinkTitles: [currentID: "Launch checklist", staleID: "Launch Plan v3"]
    )

    let layoutManager = try #require(textView.layoutManager)
    let links = NoteLinkParser.links(in: text)
    try #require(links.count == 3)

    #expect(underline(layoutManager, at: links[0]) == NSUnderlineStyle.single.rawValue)
    #expect(
      underline(layoutManager, at: links[1])
        == NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDash.rawValue
    )
    #expect(
      underline(layoutManager, at: links[2])
        == NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
    )
    #expect(textView.string == text)
  }

  @Test @MainActor func contextMenuOffersTheCurrentTitleOnlyForAStaleLink() throws {
    let staleID = UUID()
    let currentID = UUID()
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = textView
    let staleToken = NoteLinkFormatter.markdown(label: "Old name", targetNoteID: staleID)
    textView.string = "x \(staleToken) y"
    textView.refreshNoteLinks(
      accentColorHex: "#FFD600",
      liveNoteIDs: [staleID, currentID],
      noteLinkTitles: [staleID: "New name", currentID: "Current"]
    )
    let link = try #require(NoteLinkParser.links(in: textView.string).first)
    textView.setSelectedRange(link.range)

    let relabelItems = try menuItems(
      in: textView,
      at: link,
      in: window,
      action: #selector(ListAwareTextView.useCurrentNoteLinkTitle(_:))
    )

    #expect(relabelItems.count == 1)
    #expect(relabelItems.first?.title == "Use Current Title (“New name”)")

    let currentToken = NoteLinkFormatter.markdown(label: "Current", targetNoteID: currentID)
    textView.string = "x \(currentToken) y"
    textView.refreshNoteLinks(
      accentColorHex: "#FFD600",
      liveNoteIDs: [staleID, currentID],
      noteLinkTitles: [staleID: "New name", currentID: "Current"]
    )
    let currentLink = try #require(NoteLinkParser.links(in: textView.string).first)
    textView.setSelectedRange(currentLink.range)
    let currentRelabelItems = try menuItems(
      in: textView,
      at: currentLink,
      in: window,
      action: #selector(ListAwareTextView.useCurrentNoteLinkTitle(_:))
    )
    #expect(currentRelabelItems.isEmpty)
  }

  @Test @MainActor func updateNoteLinkLabelsRewritesEveryStaleLabelAndUndoesInOneStep() throws {
    let firstID = UUID()
    let secondID = UUID()
    let original = "A \(NoteLinkFormatter.markdown(label: "Old", targetNoteID: firstID)) and "
      + "B \(NoteLinkFormatter.markdown(label: "Older", targetNoteID: secondID)) and plain prose."
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 200))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 200),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = textView
    textView.allowsUndo = true
    textView.string = original
    textView.undoManager?.removeAllActions()
    textView.refreshNoteLinks(
      accentColorHex: "#FFD600",
      liveNoteIDs: [firstID, secondID],
      noteLinkTitles: [firstID: "Launch checklist", secondID: "Plan ] launch"]
    )
    #expect(textView.hasStaleNoteLinks)
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.relabelStaleNoteLinksFromMenu(nil)

    #expect(
      textView.string
        == "A \(NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: firstID)) and "
          + "B \(NoteLinkFormatter.markdown(label: "Plan ] launch", targetNoteID: secondID)) and plain prose."
    )
    #expect(!textView.hasStaleNoteLinks)

    let undoManager = try #require(textView.undoManager)
    undoManager.undo()

    #expect(textView.string == original)
  }

  @Test @MainActor func updateNoteLinkLabelsIsDisabledWhenNothingIsStale() throws {
    let target = UUID()
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
    textView.string = NoteLinkFormatter.markdown(label: "Current", targetNoteID: target)
    textView.refreshNoteLinks(
      accentColorHex: "#FFD600",
      liveNoteIDs: [target],
      noteLinkTitles: [target: "Current"]
    )
    let item = NSMenuItem(
      title: "Update Note Link Labels",
      action: #selector(ListAwareTextView.relabelStaleNoteLinksFromMenu(_:)),
      keyEquivalent: ""
    )

    #expect(!textView.hasStaleNoteLinks)
    #expect(!textView.validateMenuItem(item))
  }

  @MainActor
  private func underline(_ layoutManager: NSLayoutManager, at link: NoteLink) -> Int? {
    layoutManager.temporaryAttribute(
      .underlineStyle,
      atCharacterIndex: link.labelRange.location,
      effectiveRange: nil
    ) as? Int
  }

  @MainActor
  private func menuItems(
    in textView: ListAwareTextView,
    at link: NoteLink,
    in window: NSWindow,
    action: Selector
  ) throws -> [NSMenuItem] {
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
        eventNumber: 5,
        clickCount: 1,
        pressure: 1
      )
    )
    let menu = try #require(textView.menu(for: event))
    return menu.items.filter { $0.action == action }
  }
#endif
