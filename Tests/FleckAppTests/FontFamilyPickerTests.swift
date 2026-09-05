import AppKit
import FleckCore
import Testing
@testable import FleckApp

@Test @MainActor func fontPickerFiltersSystemFirstAndKeepsReadableNames() {
  #expect(FontFamilyPickerController.families(from: ["Menlo", ".AppleSystemUIFont", "Avenir Next", "Menlo"], query: "") == [".AppleSystemUIFont", "Avenir Next", "Menlo"])
  #expect(FontFamilyPickerController.families(from: ["Menlo", "Avenir Next"], query: "NEXT") == ["Avenir Next"])
  #expect(FontFamilyPickerController.families(from: ["Menlo"], query: "missing") == [])
  #expect(FontFamilyPickerController.displayName(".AppleSystemUIFont") == "System")
}

@Test @MainActor func fontPickerTitleTargetSurvivesSearchFocusAndCommitsOnce() throws {
  let note = Note(title: "Title", body: "Body")
  let commands = EditorCommands()
  let target = try #require(FontPickerTarget(note: note, isTitle: true, commands: commands))
  var titles: [String] = []
  let picker = FontFamilyPickerController(currentFamily: "Menlo", isMixed: false, targetLabel: target.label, onCommit: { family in
    _ = target.apply(family, note: note, isEditorVisible: true, commands: commands, titleMutation: { titles.append($0) })
  }, onCancel: {})
  picker.loadViewIfNeeded()
  picker.searchField.stringValue = "Menlo"
  picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  #expect(titles.isEmpty)
  picker.commitSelection()
  #expect(titles == ["Menlo"])
  #expect(!target.apply("Menlo", note: note, isEditorVisible: true, commands: commands, titleMutation: { titles.append($0) }))
}

@Test @MainActor func fontPickerRejectsChangedNoteRevisionAndEligibility() throws {
  let note = Note(body: "Body")
  let commands = EditorCommands()
  for replacement in [Note(body: "Body"), nil] as [Note?] {
    let target = try #require(FontPickerTarget(note: note, isTitle: true, commands: commands))
    #expect(!target.apply("Menlo", note: replacement, isEditorVisible: true, commands: commands, titleMutation: { _ in Issue.record("Stale target applied") }))
  }
  var changed = note
  changed.revision += 1
  for (replacement, visible) in [(changed, true), (note, false)] {
    let target = try #require(FontPickerTarget(note: note, isTitle: true, commands: commands))
    #expect(!target.apply("Menlo", note: replacement, isEditorVisible: visible, commands: commands, titleMutation: { _ in Issue.record("Invalid target applied") }))
  }
}

@Test @MainActor func fontPickerKeyboardNavigationAndEmptyResultDoNotCommit() {
  var commits: [String] = []
  var cancelled = false
  let picker = FontFamilyPickerController(currentFamily: ".AppleSystemUIFont", isMixed: false, targetLabel: "New text", onCommit: { commits.append($0) }, onCancel: { cancelled = true })
  _ = picker.view
  let editor = NSTextView()
  #expect(picker.control(picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
  #expect(commits.isEmpty)
  picker.searchField.stringValue = "nonesuchfont-123"
  picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  #expect(picker.control(picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
  #expect(commits.isEmpty)
  #expect(picker.control(picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
  #expect(cancelled)
}

@Test @MainActor func fontPickerSystemAtCaretChangesFutureTyping() throws {
  let text = NSTextView()
  text.textStorage?.setAttributedString(NSAttributedString(string: "A", attributes: [.font: try #require(NSFont(name: "Courier", size: 23))]))
  text.setSelectedRange(NSRange(location: 1, length: 0))
  let commands = EditorCommands()
  commands.textView = text
  let note = Note(body: "A")
  let target = try #require(FontPickerTarget(note: note, isTitle: false, commands: commands))
  #expect(target.label == "New text")
  #expect(target.apply(".AppleSystemUIFont", note: note, isEditorVisible: true, commands: commands, titleMutation: { _ in }))
  text.insertText("B", replacementRange: text.selectedRange())
  #expect((text.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.familyName == NSFont.systemFont(ofSize: 23).familyName)
  #expect((text.textStorage?.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.pointSize == 23)
}

@Test @MainActor func fontPickerHostedVisualSamples() throws {
  let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/evidence")
  for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    let picker = FontFamilyPickerController(currentFamily: "Avenir Next", isMixed: false, targetLabel: "Selected text", onCommit: { _ in }, onCancel: {})
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 280, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.contentViewController = picker
    _ = picker.view
    picker.searchField.stringValue = "Avenir"
    picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    picker.view.layoutSubtreeIfNeeded()
    let rep = try #require(picker.view.bitmapImageRepForCachingDisplay(in: picker.view.bounds))
    picker.view.cacheDisplay(in: picker.view.bounds, to: rep)
    let image = NSImage(size: picker.view.bounds.size)
    image.lockFocus()
    window.appearance?.performAsCurrentDrawingAppearance {
      NSColor.windowBackgroundColor.setFill()
      picker.view.bounds.fill()
    }
    let foreground = NSImage(size: picker.view.bounds.size)
    foreground.addRepresentation(rep)
    foreground.draw(in: picker.view.bounds, from: .zero, operation: .sourceOver, fraction: 1)
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: evidence.appendingPathComponent("phase2-font-\(appearance.rawValue).png"))
    #expect(picker.searchField.frame.width > 200)
  }
}
