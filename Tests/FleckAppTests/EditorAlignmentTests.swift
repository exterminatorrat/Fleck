#if os(macOS)
  import AppKit
  import FleckCore
  import SwiftUI
  import Testing

  @testable import FleckApp

  @Test @MainActor func pinnedTitleUsesOpaqueAdaptiveColorAndMatchesBodyTextOrigin() async throws {
    for (family, bodySize) in [("Avenir Next", 11.0), ("Menlo", 24.0)] {
      let pinned = try await makeEditorAlignmentPanel(
        isPinned: true,
        fontFamily: family,
        fontSize: bodySize,
        bodyText: "Harmonized body\n○ Open checklist\n○ Completed checklist"
      )
      do {
        let body = try #require(
          editorAlignmentDescendant(in: pinned.host, as: ListAwareTextView.self)
        )
        let completedMarkerLocation = "Harmonized body\n○ Open checklist\n".utf16.count
        body.setSelectedRange(NSRange(location: completedMarkerLocation + 2, length: 0))
        #expect(body.toggleSelectedChecklist())
        #expect((body.string as NSString).substring(
          with: NSRange(location: completedMarkerLocation, length: 1)
        ) == "●")
        #expect(body.textStorage?.attribute(
          .strikethroughStyle,
          at: completedMarkerLocation + 2,
          effectiveRange: nil
        ) as? Int == NSUnderlineStyle.single.rawValue)

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
          let appearance = try #require(NSAppearance(named: appearanceName))
          pinned.window.appearance = appearance
          await settleEditorAlignmentView(pinned.host)

          let title = try #require(editorAlignmentDescendant(in: pinned.host, as: NSTextField.self) {
            $0.placeholderString == "Note title"
          })
          let titleFrame = title.convert(title.bounds, to: pinned.host)
          #expect(title.placeholderString == "Note title")
          #expect(resolvedEditorColor(title.textColor, appearance: appearance)?.alpha == 1)
          #expect(
            resolvedEditorColor(title.textColor, appearance: appearance)
              == resolvedEditorColor(.textColor, appearance: appearance)
          )
          let titleInkAlpha = try maximumEditorInkAlpha(in: title)
          title.stringValue = ""
          let placeholderInkAlpha = try maximumEditorInkAlpha(in: title)
          #expect(placeholderInkAlpha < titleInkAlpha)
          title.stringValue = "Harmonized title"

          #expect(pinned.window.makeFirstResponder(title))
          let titleEditor = try #require(title.currentEditor() as? NSTextView)
          let titleOrigin = try nativeTextOrigin(titleEditor, in: pinned.host)
          let bodyOrigin = try nativeTextOrigin(body, in: pinned.host)
          #expect(abs(titleOrigin - bodyOrigin) < 0.01)
          await settleEditorAlignmentView(pinned.host)
          #expect(title.convert(title.bounds, to: pinned.host) == titleFrame)

          #expect(pinned.window.makeFirstResponder(body))
          body.setSelectedRange(NSRange(location: 0, length: 0))
          await settleEditorAlignmentView(pinned.host)
          try captureEditorAlignmentView(
            pinned.host,
            name: "full-editor-\(family)-\(appearanceName.rawValue)"
          )
        }
      } catch {
        await pinned.close()
        throw error
      }
      await pinned.close()
    }
  }

  @Test @MainActor func ordinaryTitleKeepsNativeLabelColorAndLayoutInset() async throws {
    let ordinary = try await makeEditorAlignmentPanel(
      isPinned: false,
      fontFamily: "Avenir Next",
      fontSize: 17
    )
    do {
      let appearance = try #require(NSAppearance(named: .darkAqua))
      ordinary.window.appearance = appearance
      await settleEditorAlignmentView(ordinary.host)

      let title = try #require(editorAlignmentDescendant(in: ordinary.host, as: NSTextField.self) {
        $0.placeholderString == "Note title"
      })
      let body = try #require(editorAlignmentDescendant(in: ordinary.host, as: ListAwareTextView.self))
      #expect(
        resolvedEditorColor(title.textColor, appearance: appearance)
          == resolvedEditorColor(.labelColor, appearance: appearance)
      )
      #expect(try nativeTextOrigin(title, afterFocusingIn: ordinary.window, host: ordinary.host)
        - nativeTextOrigin(body, in: ordinary.host) == 2)
    } catch {
      await ordinary.close()
      throw error
    }
    await ordinary.close()
  }

  @Test @MainActor func checklistPrefixReservesTwentyPointsAcrossContentFontsAndDepths() throws {
    for family in [".AppleSystemUIFont", "Avenir Next", "Menlo"] {
      for size in [CGFloat(11), 14, 17, 24] {
        for marker in ["○", "●"] {
          for content in ["", "Item"] {
            for depth in [0, 1] {
              let indent = String(repeating: "    ", count: depth)
              let text = indent + marker + " " + content
              let editor = makeChecklistAlignmentEditor(text: text, family: family, size: size)
              let markerLocation = indent.utf16.count
              let geometry = try checklistAlignmentGeometry(
                in: editor,
                markerLocation: markerLocation
              )

              #expect(abs(geometry.slot.width - 20) < 0.01)
              #expect(abs(geometry.marker.minX - geometry.slot.minX) < 0.01)
              #expect(abs(geometry.contentOriginX - geometry.marker.maxX - 4) < 0.01)
              #expect(geometry.hit.contains(geometry.marker))
              #expect(abs(geometry.hit.maxX - geometry.marker.maxX) < 0.01)
              if depth == 0 {
                #expect(abs(geometry.marker.minX - editor.textContainerOrigin.x) < 0.01)
              }
            }
          }
        }
      }
    }
  }

  @Test @MainActor func checklistLayoutPreservesTextRichFormattingWrappingAndClickUndo() throws {
    let text = "○ Styled checklist content that wraps across several native text lines"
    let editor = makeChecklistAlignmentEditor(
      text: text,
      family: "Avenir Next",
      size: 17,
      width: 150
    )
    let storage = try #require(editor.textStorage)
    storage.addAttributes(
      [
        .font: try #require(NSFont(name: "Menlo-Bold", size: 24)),
        .foregroundColor: NSColor.systemPurple,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
      ],
      range: NSRange(location: 2, length: 6)
    )
    let original = NSAttributedString(attributedString: storage)
    let originalRTF = try storage.data(
      from: NSRange(location: 0, length: storage.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    let container = try #require(editor.textContainer)
    let layoutManager = try #require(editor.layoutManager)
    layoutManager.ensureLayout(for: container)
    #expect(NSAttributedString(attributedString: storage).isEqual(to: original))
    #expect(layoutManager.usedRect(for: container).height > 54)

    let marker = try #require(editor.checklistMarkerRect(for: NSRange(location: 0, length: 1)))
    let hit = try #require(editor.checklistHitRect(for: NSRange(location: 0, length: 1)))
    #expect(abs(marker.minX - editor.textContainerOrigin.x) < 0.01)
    #expect(hit.contains(NSPoint(x: marker.midX, y: marker.midY)))

    let window = NSWindow(
      contentRect: editor.bounds,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = editor
    editor.allowsUndo = true
    editor.undoManager?.removeAllActions()

    let event = try #require(NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: editor.convert(marker.center, to: nil),
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 1,
      clickCount: 1,
      pressure: 1
    ))
    editor.mouseDown(with: event)
    #expect(editor.string.hasPrefix("● "))
    let completedGeometry = try checklistAlignmentGeometry(in: editor, markerLocation: 0)
    #expect(abs(completedGeometry.slot.width - 20) < 0.01)
    #expect(abs(completedGeometry.marker.minX - editor.textContainerOrigin.x) < 0.01)
    try #require(editor.undoManager).undo()

    #expect(editor.string == text)
    let restoredGeometry = try checklistAlignmentGeometry(in: editor, markerLocation: 0)
    #expect(abs(restoredGeometry.slot.width - 20) < 0.01)
    #expect(abs(restoredGeometry.marker.minX - editor.textContainerOrigin.x) < 0.01)
    #expect(NSAttributedString(attributedString: storage).isEqual(to: original))
    let restoredRTF = try storage.data(
      from: NSRange(location: 0, length: storage.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    #expect(restoredRTF == originalRTF)
    window.contentView = nil
  }

  @Test @MainActor func nonListCircleAndOrdinaryTextKeepNativeGlyphLayout() throws {
    let editor = makeChecklistAlignmentEditor(
      text: "Ordinary ○ symbol\n• Bullet",
      family: ".AppleSystemUIFont",
      size: 14
    )
    let layoutManager = try #require(editor.layoutManager)
    let container = try #require(editor.textContainer)
    layoutManager.ensureLayout(for: container)
    for characterIndex in [9, 10, 18, 19] {
      let glyph = layoutManager.glyphIndexForCharacter(at: characterIndex)
      #expect(!layoutManager.propertyForGlyph(at: glyph).contains(.controlCharacter))
    }
  }

  @Test @MainActor func checklistGlyphClassificationTracksSurroundingTextEditsAndUndo() throws {
    do {
      let fixture = makeChecklistTransitionFixture(text: "Lead ○ Item")
      defer { fixture.window.contentView = nil }
      try expectPlainCircle(in: fixture.editor, markerLocation: 5)

      fixture.editor.insertText("", replacementRange: NSRange(location: 0, length: 5))
      #expect(fixture.editor.string == "○ Item")
      try expectChecklistControl(in: fixture.editor, markerLocation: 0)

      try #require(fixture.editor.undoManager).undo()
      #expect(fixture.editor.string == "Lead ○ Item")
      try expectPlainCircle(in: fixture.editor, markerLocation: 5)
    }

    do {
      let fixture = makeChecklistTransitionFixture(text: "○ Item")
      defer { fixture.window.contentView = nil }
      try expectChecklistControl(in: fixture.editor, markerLocation: 0)

      fixture.editor.insertText("Lead ", replacementRange: NSRange(location: 0, length: 0))
      #expect(fixture.editor.string == "Lead ○ Item")
      try expectPlainCircle(in: fixture.editor, markerLocation: 5)

      try #require(fixture.editor.undoManager).undo()
      #expect(fixture.editor.string == "○ Item")
      try expectChecklistControl(in: fixture.editor, markerLocation: 0)
    }

    do {
      let fixture = makeChecklistTransitionFixture(text: "Lead ○ Item")
      defer { fixture.window.contentView = nil }
      try expectPlainCircle(in: fixture.editor, markerLocation: 5)

      fixture.editor.insertText("\n", replacementRange: NSRange(location: 5, length: 0))
      #expect(fixture.editor.string == "Lead \n○ Item")
      try expectChecklistControl(in: fixture.editor, markerLocation: 6)

      let undoManager = try #require(fixture.editor.undoManager)
      undoManager.undo()
      #expect(fixture.editor.string == "Lead ○ Item")
      try expectPlainCircle(in: fixture.editor, markerLocation: 5)
      undoManager.redo()
      #expect(fixture.editor.string == "Lead \n○ Item")
      try expectChecklistControl(in: fixture.editor, markerLocation: 6)

      fixture.editor.insertText("", replacementRange: NSRange(location: 5, length: 1))
      #expect(fixture.editor.string == "Lead ○ Item")
      try expectPlainCircle(in: fixture.editor, markerLocation: 5)
      undoManager.undo()
      #expect(fixture.editor.string == "Lead \n○ Item")
      try expectChecklistControl(in: fixture.editor, markerLocation: 6)
    }
  }

  @MainActor
  private struct EditorAlignmentPanelFixture {
    let root: URL
    let window: NSWindow
    let host: NSHostingView<AnyView>
    let runtime: DictationRuntime

    func close() async {
      window.contentView = nil
      await runtime.shutdown()
      try? FileManager.default.removeItem(at: root)
    }
  }

  @MainActor
  private func makeEditorAlignmentPanel(
    isPinned: Bool,
    fontFamily: String,
    fontSize: Double,
    bodyText: String = "Harmonized body"
  ) async throws -> EditorAlignmentPanelFixture {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let note = Note(title: "Harmonized title", body: bodyText, folderID: nil)
    let state = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _, _ in .committed }
    )
    await state.waitUntilInitialLoad()
    state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [])
    state.updatePreferences {
      $0.fontFamily = fontFamily
      $0.fontSize = fontSize
      $0.showFormattingBar = false
    }
    let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
    let panel = NotesPanel(
      dictationRuntime: runtime,
      isPinned: isPinned,
      sizing: .container
    )
    let host = NSHostingView(
      rootView: AnyView(panel.environmentObject(state).frame(width: 640, height: 430))
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    await settleEditorAlignmentView(host)
    return EditorAlignmentPanelFixture(root: root, window: window, host: host, runtime: runtime)
  }

  @MainActor
  private func settleEditorAlignmentView(_ view: NSView) async {
    for _ in 0..<5 {
      view.layoutSubtreeIfNeeded()
      await Task.yield()
    }
  }

  @MainActor
  private func editorAlignmentDescendant<T: NSView>(
    in view: NSView,
    as type: T.Type,
    matching predicate: (T) -> Bool = { _ in true }
  ) -> T? {
    if let match = view as? T, predicate(match) { return match }
    for subview in view.subviews {
      if let match = editorAlignmentDescendant(in: subview, as: type, matching: predicate) {
        return match
      }
    }
    return nil
  }

  private struct ResolvedEditorColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
  }

  @MainActor
  private func resolvedEditorColor(
    _ color: NSColor?,
    appearance: NSAppearance
  ) -> ResolvedEditorColor? {
    var result: ResolvedEditorColor?
    appearance.performAsCurrentDrawingAppearance {
      guard let color = color?.usingColorSpace(.sRGB) else { return }
      result = ResolvedEditorColor(
        red: color.redComponent,
        green: color.greenComponent,
        blue: color.blueComponent,
        alpha: color.alphaComponent
      )
    }
    return result
  }

  @MainActor
  private func nativeTextOrigin(_ textView: NSTextView, in host: NSView) throws -> CGFloat {
    let layoutManager = try #require(textView.layoutManager)
    let container = try #require(textView.textContainer)
    layoutManager.ensureLayout(for: container)
    let glyph = layoutManager.glyphIndexForCharacter(at: 0)
    let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    return textView.convert(.zero, to: host).x
      + textView.textContainerOrigin.x
      + line.minX
      + layoutManager.location(forGlyphAt: glyph).x
  }

  @MainActor
  private func nativeTextOrigin(
    _ title: NSTextField,
    afterFocusingIn window: NSWindow,
    host: NSView
  ) throws -> CGFloat {
    #expect(window.makeFirstResponder(title))
    return try nativeTextOrigin(#require(title.currentEditor() as? NSTextView), in: host)
  }

  private struct ChecklistAlignmentGeometry {
    let slot: NSRect
    let marker: NSRect
    let hit: NSRect
    let contentOriginX: CGFloat
  }

  @MainActor
  private struct ChecklistTransitionFixture {
    let editor: ListAwareTextView
    let window: NSWindow
  }

  @MainActor
  private func makeChecklistTransitionFixture(text: String) -> ChecklistTransitionFixture {
    let editor = makeChecklistAlignmentEditor(
      text: text,
      family: "Avenir Next",
      size: 14
    )
    editor.appearance = NSAppearance(named: .aqua)
    editor.drawsBackground = true
    editor.backgroundColor = .white
    editor.textColor = .black
    let window = NSWindow(
      contentRect: editor.bounds,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = editor
    editor.allowsUndo = true
    editor.undoManager?.removeAllActions()
    return ChecklistTransitionFixture(editor: editor, window: window)
  }

  @MainActor
  private func expectChecklistControl(
    in editor: ListAwareTextView,
    markerLocation: Int
  ) throws {
    let layoutManager = try #require(editor.layoutManager)
    let container = try #require(editor.textContainer)
    layoutManager.ensureLayout(for: container)
    for characterIndex in markerLocation...(markerLocation + 1) {
      let glyph = layoutManager.glyphIndexForCharacter(at: characterIndex)
      #expect(layoutManager.propertyForGlyph(at: glyph).contains(.controlCharacter))
    }
    let geometry = try checklistAlignmentGeometry(
      in: editor,
      markerLocation: markerLocation
    )
    #expect(abs(geometry.slot.width - 20) < 0.01)
    #expect(abs(geometry.marker.minX - geometry.slot.minX) < 0.01)
    #expect(abs(geometry.contentOriginX - geometry.marker.maxX - 4) < 0.01)
  }

  @MainActor
  private func expectPlainCircle(
    in editor: ListAwareTextView,
    markerLocation: Int
  ) throws {
    let layoutManager = try #require(editor.layoutManager)
    let container = try #require(editor.textContainer)
    layoutManager.ensureLayout(for: container)
    for characterIndex in markerLocation...(markerLocation + 1) {
      let glyph = layoutManager.glyphIndexForCharacter(at: characterIndex)
      #expect(!layoutManager.propertyForGlyph(at: glyph).contains(.controlCharacter))
    }
    editor.refreshChecklistPresentation()
    let glyphRange = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: markerLocation, length: 1),
      actualCharacterRange: nil
    )
    let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
      .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
      .insetBy(dx: -1, dy: -1)
    let bitmap = try #require(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
    editor.cacheDisplay(in: editor.bounds, to: bitmap)
    let scaleX = CGFloat(bitmap.pixelsWide) / editor.bounds.width
    let scaleY = CGFloat(bitmap.pixelsHigh) / editor.bounds.height
    let firstColumn = max(0, Int(floor(glyphRect.minX * scaleX)))
    let lastColumn = min(bitmap.pixelsWide, Int(ceil(glyphRect.maxX * scaleX)))
    let firstRow = max(0, Int(floor(glyphRect.minY * scaleY)))
    let lastRow = min(bitmap.pixelsHigh, Int(ceil(glyphRect.maxY * scaleY)))
    let columns = firstColumn..<lastColumn
    let rows = firstRow..<lastRow
    let inkCount = rows.reduce(0) { count, y in
      count + columns.filter { x in
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
          return false
        }
        return color.alphaComponent > 0.2
          && max(color.redComponent, color.greenComponent, color.blueComponent) < 0.8
      }.count
    }
    #expect(inkCount > 4)
  }

  @MainActor
  private func makeChecklistAlignmentEditor(
    text: String,
    family: String,
    size: CGFloat,
    width: CGFloat = 320
  ) -> ListAwareTextView {
    let editor = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: width, height: 180))
    editor.reduceMotion = true
    editor.textContainerInset = NSSize(width: 16, height: 8)
    editor.textContainer?.lineFragmentPadding = 0
    editor.textContainer?.containerSize = NSSize(width: width - 32, height: .greatestFiniteMagnitude)
    editor.textContainer?.widthTracksTextView = false
    let attributes = EditorTypography.defaultAttributes(family: family, size: size)
    editor.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
    editor.typingAttributes = attributes
    return editor
  }

  @MainActor
  private func checklistAlignmentGeometry(
    in editor: ListAwareTextView,
    markerLocation: Int
  ) throws -> ChecklistAlignmentGeometry {
    let layoutManager = try #require(editor.layoutManager)
    let container = try #require(editor.textContainer)
    layoutManager.ensureLayout(for: container)
    let prefixGlyphs = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: markerLocation, length: 2),
      actualCharacterRange: nil
    )
    let slot = layoutManager.boundingRect(forGlyphRange: prefixGlyphs, in: container)
      .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
    let contentOriginX: CGFloat
    if markerLocation + 2 < (editor.string as NSString).length {
      let contentGlyph = layoutManager.glyphIndexForCharacter(at: markerLocation + 2)
      let line = layoutManager.lineFragmentRect(forGlyphAt: contentGlyph, effectiveRange: nil)
      contentOriginX = editor.textContainerOrigin.x
        + line.minX
        + layoutManager.location(forGlyphAt: contentGlyph).x
    } else {
      contentOriginX = slot.maxX
    }
    return ChecklistAlignmentGeometry(
      slot: slot,
      marker: try #require(editor.checklistMarkerRect(
        for: NSRange(location: markerLocation, length: 1)
      )),
      hit: try #require(editor.checklistHitRect(
        for: NSRange(location: markerLocation, length: 1)
      )),
      contentOriginX: contentOriginX
    )
  }

  @MainActor
  private func captureEditorAlignmentView(_ view: NSView, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["FLECK_EDITOR_EVIDENCE_DIR"] else {
      return
    }
    try FileManager.default.createDirectory(
      atPath: directory,
      withIntermediateDirectories: true
    )
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
  }

  @MainActor
  private func maximumEditorInkAlpha(in view: NSView) throws -> CGFloat {
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return (0..<bitmap.pixelsHigh).reduce(0) { rowMaximum, y in
      (0..<bitmap.pixelsWide).reduce(rowMaximum) { maximum, x in
        max(maximum, bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
      }
    }
  }

  private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
  }
#endif
