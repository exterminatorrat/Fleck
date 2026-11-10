import Foundation
import Testing

@testable import FleckApp

private func fleckProductSource(_ relativePath: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(
    contentsOf: root.appendingPathComponent(relativePath),
    encoding: .utf8
  )
}

private func focusSection(
  of source: String,
  from start: String,
  to end: String
) throws -> Substring {
  let startIndex = try #require(source.range(of: start))
  let remainder = source[startIndex.upperBound...]
  let endIndex = try #require(remainder.range(of: end))
  return remainder[..<endIndex.lowerBound]
}

@Test
func FocusEffectSuppressionDisablesProductHostingRoots() throws {
  let app = try fleckProductSource("Sources/FleckApp/FleckApp.swift")

  let menuBarRoot = try focusSection(
    of: app,
    from: "MenuBarExtra {",
    to: "label: {"
  )
  #expect(menuBarRoot.contains("FleckMenuBarRoot("))
  #expect(menuBarRoot.contains(".focusEffectDisabled()"))

  let pinnedNotesRoot = try focusSection(
    of: app,
    from: "Window(\"Fleck\", id: \"pinned-notes\") {",
    to: ".windowResizability(.contentSize)"
  )
  #expect(pinnedNotesRoot.contains("FleckPinnedNotesRoot("))
  #expect(pinnedNotesRoot.contains(".focusEffectDisabled()"))

  let settingsRoot = try focusSection(
    of: app,
    from: "Settings {",
    to: ".defaultSize(width: 840, height: 600)"
  )
  #expect(settingsRoot.contains("SettingsView(runtime: dictationRuntime,"))
  #expect(settingsRoot.contains(".focusEffectDisabled()"))

  let historyRoot = try focusSection(
    of: app,
    from: "let view = DictationHistoryView(",
    to: "NSHostingController(rootView: view)"
  )
  #expect(historyRoot.contains(".focusEffectDisabled()"))
}

@Test
func FocusEffectSuppressionCoversDetachedSurfacesAndAppKitControls() throws {
  let capsule = try fleckProductSource("Sources/FleckApp/DictationCapsule.swift")
  let capsuleBody = try focusSection(
    of: capsule,
    from: "    var body: some View {\n      accessibilityContent",
    to: "@ViewBuilder"
  )
  #expect(capsuleBody.contains(".focusEffectDisabled()"))

  let roots = try fleckProductSource("Sources/FleckApp/OnboardingWindowPresenter.swift")
  let menuBarRoot = try focusSection(
    of: roots,
    from: "struct FleckMenuBarRoot: View {",
    to: "struct FleckPinnedNotesRoot: View {"
  )
  #expect(menuBarRoot.contains("NotesPanel(dictationRuntime: dictationRuntime)"))
  let pinnedNotesRoot = try focusSection(
    of: roots,
    from: "struct FleckPinnedNotesRoot: View {",
    to: "struct OnboardingResumePanel: View {"
  )
  #expect(pinnedNotesRoot.contains("NotesPanel("))

  let notesPanel = try fleckProductSource("Sources/FleckApp/NotesPanel.swift")
  #expect(notesPanel.contains("WorkspaceSearchView("))
  #expect(notesPanel.contains("NoteLinkPickerView("))

  let editor = try fleckProductSource("Sources/FleckApp/NativeRichTextEditor.swift")
  #expect(editor.contains("scrollView.focusRingType = .none"))
  #expect(editor.contains("textView.focusRingType = .none"))
  #expect(editor.contains("button.focusRingType = .none"))
  #expect(editor.components(separatedBy: ".focusRingType = .none").count - 1 >= 3)

  let fontPicker = try fleckProductSource("Sources/FleckApp/FontFamilyPicker.swift")
  #expect(fontPicker.contains("searchField.focusRingType = .none"))
  #expect(fontPicker.contains("table.focusRingType = .none"))
  #expect(fontPicker.contains("scroll.focusRingType = .none"))
  #expect(fontPicker.contains("clearButton.focusRingType = .none"))
}

@Test
func FocusEffectSuppressionKeepsKeyboardFocusAndTheFolderFocusCue() throws {
  let notesPanel = try fleckProductSource("Sources/FleckApp/NotesPanel.swift")

  let folderRows = try focusSection(
    of: notesPanel,
    from: "private func folderRow(_ folder: Folder) -> some View {",
    to: "private func folderEditor("
  )
  #expect(
    folderRows.contains(
      ".focusable()\n        .focused($focusedRow, equals: .folder(folder.id))\n        .focusEffectDisabled()"
    )
  )

  let rowLabel = try focusSection(
    of: notesPanel,
    from: "private func rowLabel(",
    to: "private func noteDropDelegate("
  )
  #expect(rowLabel.contains(".fleckNeutralControlOutline("))
  #expect(rowLabel.contains("isFocused: isFocused && !isSelected"))
}

@Test
func FocusEffectSuppressionCoversTheAppKitFindBar() throws {
  let editor = try fleckProductSource("Sources/FleckApp/NativeRichTextEditor.swift")
  let formatting = try fleckProductSource("Sources/FleckApp/EditorFormattingCommands.swift")

  #expect(editor.contains("textView.usesFindBar = true"))

  let scrollView = try focusSection(
    of: editor,
    from: "final class NativeEditorScrollView: NSScrollView {",
    to: "final class ListAwareTextView: NSTextView"
  )
  #expect(
    scrollView.contains(
      "override func tile() {\n      super.tile()\n      suppressFocusRingsInFindBar()\n    }"
    )
  )
  #expect(
    scrollView.contains(
      "override func layout() {\n      super.layout()\n      suppressFocusRingsInFindBar()"
    )
  )
  #expect(
    scrollView.contains(
      "private func suppressFocusRingsInFindBar() {\n      guard let findBarView else { return }\n      suppressFocusRing(in: findBarView)\n    }"
    )
  )
  #expect(
    scrollView.contains(
      "private func suppressFocusRing(in view: NSView) {\n      view.focusRingType = .none\n      for subview in view.subviews {"
    )
  )

  for forbidden in [
    "method_exchangeImplementations",
    "class_replaceMethod",
    "method_setImplementation",
    "NSApp.windows",
    "NSApplication.shared.windows",
  ] {
    #expect(!editor.contains(forbidden), Comment(rawValue: forbidden))
  }

  #expect(editor.contains("performTextFinderAction(sender)"))
  #expect(formatting.contains("performTextFinderAction(sender)"))
}
