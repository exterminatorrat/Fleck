#if os(macOS)
  import AppKit
  import FleckCore
  import Testing

  @testable import FleckApp

  /// Records the stored text after every editing pass, so a test can prove that
  /// no intermediate state of the text storage ever exposes a note link's
  /// Markdown. It listens to the text storage rather than a delegate, so the
  /// editor keeps its own delegate and notifications.
  @MainActor
  private final class StoredTextRecorder: NSObject {
    private(set) var snapshots: [String] = []

    func reset() {
      snapshots = []
    }

    @objc func record(_ notification: Notification) {
      guard let storage = notification.object as? NSTextStorage else { return }
      snapshots.append(storage.string)
    }
  }

  @MainActor
  private func noteLinkEditor(
    _ text: String,
    liveNoteIDs: Set<UUID>
  ) -> (ListAwareTextView, NSWindow, StoredTextRecorder) {
    let frame = NSRect(x: 0, y: 0, width: 520, height: 240)
    let view = ListAwareTextView(frame: frame)
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = view
    view.allowsUndo = true
    view.textStorage?.setAttributedString(
      NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: 17),
        .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 17),
      ])
    )
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    view.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: liveNoteIDs)
    let recorder = StoredTextRecorder()
    if let storage = view.textStorage {
      NotificationCenter.default.addObserver(
        recorder,
        selector: #selector(StoredTextRecorder.record(_:)),
        name: NSTextStorage.didProcessEditingNotification,
        object: storage
      )
    }
    return (view, window, recorder)
  }

  @MainActor
  private func stopRecording(_ recorder: StoredTextRecorder) {
    NotificationCenter.default.removeObserver(recorder)
  }

  @MainActor
  private func nullGlyphCount(_ layoutManager: NSLayoutManager) -> Int {
    (0..<layoutManager.numberOfGlyphs).reduce(into: 0) { count, glyphIndex in
      if layoutManager.propertyForGlyph(at: glyphIndex) == .null {
        count += 1
      }
    }
  }

  @MainActor
  private func expectNoStoredMarkdownOrDebris(
    _ snapshots: [String],
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(!snapshots.isEmpty, sourceLocation: sourceLocation)
    for snapshot in snapshots {
      #expect(!snapshot.contains("fleck://note/"), sourceLocation: sourceLocation)
      #expect(!snapshot.contains("["), sourceLocation: sourceLocation)
      #expect(!snapshot.contains("]"), sourceLocation: sourceLocation)
      #expect(!snapshot.contains("("), sourceLocation: sourceLocation)
      #expect(!snapshot.contains(")"), sourceLocation: sourceLocation)
    }
  }

  @Test @MainActor func backspaceAtRenderedLinkTailRemovesTheWholeLink() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let (view, window, recorder) = noteLinkEditor(text, liveNoteIDs: [target])
    defer { window.contentView = nil }
    defer { stopRecording(recorder) }
    let link = try #require(NoteLinkParser.links(in: text).first)

    view.setSelectedRange(NSRange(location: NSMaxRange(link.range), length: 0))
    view.deleteBackward(nil)

    #expect(view.string == "Ship it.  covers signing.")
    #expect(view.selectedRange() == NSRange(location: link.range.location, length: 0))
    expectNoStoredMarkdownOrDebris(recorder.snapshots)
    #expect(recorder.snapshots.contains("Ship it.  covers signing."))
  }

  @Test @MainActor func backspaceWithTheRenderedLinkSelectedRemovesTheWholeLink() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let (view, window, recorder) = noteLinkEditor(text, liveNoteIDs: [target])
    defer { window.contentView = nil }
    defer { stopRecording(recorder) }
    let link = try #require(NoteLinkParser.links(in: text).first)

    view.setSelectedRange(link.range)
    view.deleteBackward(nil)

    #expect(view.string == "Ship it.  covers signing.")
    #expect(view.selectedRange() == NSRange(location: link.range.location, length: 0))
    expectNoStoredMarkdownOrDebris(recorder.snapshots)
  }

  @Test @MainActor func optionBackspaceAtRenderedLinkTailRemovesTheWholeLink() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let (view, window, recorder) = noteLinkEditor(text, liveNoteIDs: [target])
    defer { window.contentView = nil }
    defer { stopRecording(recorder) }
    let link = try #require(NoteLinkParser.links(in: text).first)

    view.setSelectedRange(NSRange(location: NSMaxRange(link.range), length: 0))
    view.deleteWordBackward(nil)

    #expect(view.string == "Ship it.  covers signing.")
    expectNoStoredMarkdownOrDebris(recorder.snapshots)
  }

  @Test @MainActor func backspaceBesideARenderedLinkKeepsItRendered() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let (view, window, recorder) = noteLinkEditor(text, liveNoteIDs: [target])
    defer { window.contentView = nil }
    defer { stopRecording(recorder) }
    let layoutManager = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    layoutManager.ensureLayout(for: container)
    let collapsedNulls = nullGlyphCount(layoutManager)
    #expect(collapsedNulls > 0)

    view.setSelectedRange(NSRange(location: 4, length: 0))
    view.deleteBackward(nil)
    layoutManager.ensureLayout(for: container)

    #expect(view.string == "Shi it. \(token) covers signing.")
    #expect(nullGlyphCount(layoutManager) == collapsedNulls)
    #expect(recorder.snapshots.contains(view.string))
  }

  @Test @MainActor func backspaceOverASelectionWiderThanTheLinkRemovesTheWholeSelection() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let (view, window, recorder) = noteLinkEditor(text, liveNoteIDs: [target])
    defer { window.contentView = nil }
    defer { stopRecording(recorder) }
    let link = try #require(NoteLinkParser.links(in: text).first)
    let selection = NSRange(location: 5, length: NSMaxRange(link.range) + 7 - 5)
    #expect((text as NSString).substring(with: selection).hasSuffix("covers"))

    view.setSelectedRange(selection)
    view.deleteBackward(nil)

    #expect(view.string == "Ship  signing.")
    #expect(view.selectedRange() == NSRange(location: 5, length: 0))
    expectNoStoredMarkdownOrDebris(recorder.snapshots)
    #expect(recorder.snapshots.contains("Ship  signing."))
  }

  @Test @MainActor func backspaceOverTheLinkTailAndFollowingTextRemovesBoth() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let (view, window, recorder) = noteLinkEditor(text, liveNoteIDs: [target])
    defer { window.contentView = nil }
    defer { stopRecording(recorder) }
    let link = try #require(NoteLinkParser.links(in: text).first)
    let selection = NSRange(
      location: NSMaxRange(link.range) - 3,
      length: 6
    )
    #expect(NoteLinkParser.link(atUTF16Location: selection.location, in: text) != nil)

    view.setSelectedRange(selection)
    view.deleteBackward(nil)

    #expect(view.string == "Ship it. vers signing.")
    #expect(view.selectedRange() == NSRange(location: link.range.location, length: 0))
    expectNoStoredMarkdownOrDebris(recorder.snapshots)
  }

  @Test @MainActor func backspaceOverASelectionSpanningTwoLinksRemovesBoth() throws {
    let first = UUID()
    let second = UUID()
    let firstToken = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: first)
    let secondToken = NoteLinkFormatter.markdown(label: "Signing notes", targetNoteID: second)
    let text = "Ship it. \(firstToken) and \(secondToken) covers signing."
    let (view, window, recorder) = noteLinkEditor(text, liveNoteIDs: [first, second])
    defer { window.contentView = nil }
    defer { stopRecording(recorder) }
    let links = NoteLinkParser.links(in: text)
    #expect(links.count == 2)
    let firstLink = try #require(links.first)
    let secondLink = try #require(links.last)
    let selection = NSRange(
      location: firstLink.range.location + 3,
      length: NSMaxRange(secondLink.range) - 2 - (firstLink.range.location + 3)
    )

    view.setSelectedRange(selection)
    view.deleteBackward(nil)

    #expect(view.string == "Ship it.  covers signing.")
    #expect(view.selectedRange() == NSRange(location: firstLink.range.location, length: 0))
    expectNoStoredMarkdownOrDebris(recorder.snapshots)
    #expect(recorder.snapshots.contains("Ship it.  covers signing."))
  }

  @Test @MainActor func undoRestoresTheWholeLinkAfterBackspace() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let (view, window, recorder) = noteLinkEditor(text, liveNoteIDs: [target])
    defer { window.contentView = nil }
    defer { stopRecording(recorder) }
    let link = try #require(NoteLinkParser.links(in: text).first)

    view.setSelectedRange(NSRange(location: NSMaxRange(link.range), length: 0))
    view.deleteBackward(nil)
    #expect(view.string == "Ship it.  covers signing.")

    view.undoManager?.undo()

    #expect(view.string == text)
    #expect(NoteLinkParser.links(in: view.string).count == 1)
    expectNoStoredMarkdownOrDebris(recorder.snapshots.filter { $0 != text })
  }
#endif
