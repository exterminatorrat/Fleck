import AppKit
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor func unchangedEditorPresentationSkipsRepeatedWork() {
  let inputs = editorPresentationInputs()
  let changes = editorPresentationChanges(from: inputs, to: inputs)

  #expect(!changes.contentReloaded)
  #expect(!changes.titleChanged)
  #expect(!changes.titleFontFamilyChanged)
  #expect(!changes.bodyFontChanged)
  #expect(!changes.paletteChanged)
  #expect(!changes.liveNoteIDsChanged)
  #expect(!changes.isEnabledChanged)
  #expect(!changes.reduceTransparencyChanged)
  #expect(!changes.reduceMotionChanged)
  #expect(!changes.automaticListsChanged)
  #expect(!changes.visibilityChanged)
  #expect(!changes.contentSizeChanged)
  #expect(!changes.shouldRefreshBaseAppearance)
  #expect(!changes.shouldRefreshNoteLinks)
  #expect(!changes.shouldUpdateTypingFont)
  #expect(!changes.shouldRelayoutDocument)
}

@Test @MainActor func editorPresentationInputsInvalidateDependentWork() {
  let inputs = editorPresentationInputs()
  let darkPalette = FleckThemePalette.resolve(family: .monochrome, appearance: .dark)
  let themeChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(palette: darkPalette)
  )
  #expect(themeChanges.paletteChanged)
  #expect(themeChanges.shouldRefreshBaseAppearance)
  #expect(themeChanges.shouldRefreshNoteLinks)
  #expect(!themeChanges.shouldRelayoutDocument)

  let linkChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(liveNoteIDs: [UUID()])
  )
  #expect(linkChanges.liveNoteIDsChanged)
  #expect(linkChanges.shouldRefreshNoteLinks)
  #expect(!linkChanges.shouldRefreshBaseAppearance)

  let contentChanges = editorPresentationChanges(
    from: inputs,
    to: inputs,
    contentReloaded: true
  )
  #expect(contentChanges.shouldRefreshBaseAppearance)
  #expect(contentChanges.shouldRefreshNoteLinks)
  #expect(contentChanges.shouldRelayoutDocument)

  let familyChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(fontFamily: "Serif")
  )
  #expect(familyChanges.bodyFontChanged)
  #expect(familyChanges.shouldUpdateTypingFont)
  #expect(familyChanges.shouldRelayoutDocument)

  let sizeChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(fontSize: 18)
  )
  #expect(sizeChanges.bodyFontChanged)
  #expect(sizeChanges.shouldUpdateTypingFont)
  #expect(sizeChanges.shouldRelayoutDocument)

  let titleChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(title: "Updated title")
  )
  #expect(titleChanges.titleChanged)
  #expect(titleChanges.shouldRelayoutDocument)

  let titleFontChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(titleFontFamily: "Rounded")
  )
  #expect(titleFontChanges.titleFontFamilyChanged)
  #expect(titleFontChanges.shouldRelayoutDocument)

  let geometryChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(contentSize: NSSize(width: 420, height: 240))
  )
  #expect(geometryChanges.contentSizeChanged)
  #expect(geometryChanges.shouldRelayoutDocument)

  let listChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(automaticLists: false)
  )
  #expect(listChanges.automaticListsChanged)
  #expect(listChanges.shouldRelayoutDocument)
}

@Test @MainActor func editorPresentationEnvironmentChangesAreTracked() {
  let inputs = editorPresentationInputs()

  let enabledChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(isEnabled: false)
  )
  #expect(enabledChanges.isEnabledChanged)

  let transparencyChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(reduceTransparency: true)
  )
  #expect(transparencyChanges.reduceTransparencyChanged)

  let motionChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(reduceMotion: true)
  )
  #expect(motionChanges.reduceMotionChanged)

  let visibilityChanges = editorPresentationChanges(
    from: inputs,
    to: editorPresentationInputs(isVisible: false)
  )
  #expect(visibilityChanges.visibilityChanged)
}

@Test @MainActor func externalTextAndAttributeChangesInvalidatePresentation() throws {
  let commands = EditorCommands()
  let original = nativeEditor(text: "Original body", richTextRTF: nil, commands: commands)
  let changed = nativeEditor(text: "Changed body", richTextRTF: nil, commands: commands)
  let coordinator = original.makeCoordinator()
  coordinator.parent = changed
  let textView = ListAwareTextView(frame: .zero)
  let textReloaded = changed.applyExternalContentIfNeeded(to: textView, coordinator: coordinator)

  #expect(textReloaded)
  #expect(textView.string == "Changed body")
  let inputs = editorPresentationInputs()
  let textChanges = editorPresentationChanges(
    from: inputs,
    to: inputs,
    contentReloaded: textReloaded
  )
  #expect(textChanges.shouldRefreshBaseAppearance)
  #expect(textChanges.shouldRefreshNoteLinks)
  #expect(textChanges.shouldRelayoutDocument)

  let originalRTF = try editorRTF(
    color: NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
  )
  let changedRTF = try editorRTF(
    color: NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.9, alpha: 1)
  )
  #expect(originalRTF != changedRTF)
  let originalAttributes = nativeEditor(
    text: "Stable body",
    richTextRTF: originalRTF,
    commands: commands
  )
  let changedAttributes = nativeEditor(
    text: "Stable body",
    richTextRTF: changedRTF,
    commands: commands
  )
  let attributeCoordinator = originalAttributes.makeCoordinator()
  attributeCoordinator.parent = changedAttributes
  let attributeTextView = ListAwareTextView(frame: .zero)
  let attributesReloaded = changedAttributes.applyExternalContentIfNeeded(
    to: attributeTextView,
    coordinator: attributeCoordinator
  )

  #expect(attributesReloaded)
  #expect(attributeTextView.string == "Stable body")
  let attributeChanges = editorPresentationChanges(
    from: inputs,
    to: inputs,
    contentReloaded: attributesReloaded
  )
  #expect(attributeChanges.shouldRefreshBaseAppearance)
  #expect(attributeChanges.shouldRefreshNoteLinks)
  #expect(attributeChanges.shouldRelayoutDocument)
}

@MainActor
private func editorPresentationChanges(
  from previous: NativeRichTextEditor.PresentationInputs,
  to current: NativeRichTextEditor.PresentationInputs,
  contentReloaded: Bool = false
) -> NativeRichTextEditor.PresentationChanges {
  NativeRichTextEditor.PresentationChanges(
    previous: previous,
    current: current,
    contentReloaded: contentReloaded
  )
}

@MainActor
private func editorPresentationInputs(
  title: String = "Synthetic note",
  titleFontFamily: String = "System",
  fontFamily: String = "System",
  fontSize: Double = 14,
  palette: FleckThemePalette = .resolve(family: .monochrome, appearance: .light),
  liveNoteIDs: Set<UUID> = [],
  isEnabled: Bool = true,
  reduceTransparency: Bool = false,
  reduceMotion: Bool = false,
  automaticLists: Bool = true,
  isVisible: Bool = true,
  contentSize: NSSize = NSSize(width: 320, height: 240)
) -> NativeRichTextEditor.PresentationInputs {
  NativeRichTextEditor.PresentationInputs(
    title: title,
    titleFontFamily: titleFontFamily,
    fontFamily: fontFamily,
    fontSize: fontSize,
    palette: palette,
    liveNoteIDs: liveNoteIDs,
    isEnabled: isEnabled,
    reduceTransparency: reduceTransparency,
    reduceMotion: reduceMotion,
    automaticLists: automaticLists,
    isVisible: isVisible,
    contentSize: contentSize
  )
}

@MainActor
private func nativeEditor(
  text: String,
  richTextRTF: Data?,
  commands: EditorCommands
) -> NativeRichTextEditor {
  NativeRichTextEditor(
    text: text,
    richTextRTF: richTextRTF,
    onChange: { _, _ in },
    fontFamily: "System",
    fontSize: 14,
    reduceMotion: false,
    automaticLists: true,
    commands: commands,
    isVisible: false
  )
}

@MainActor
private func editorRTF(color: NSColor) throws -> Data {
  let attributedText = NSAttributedString(
    string: "Stable body",
    attributes: [
      .font: NSFont.systemFont(ofSize: 14),
      .foregroundColor: color,
    ]
  )
  return try attributedText.data(
    from: NSRange(location: 0, length: attributedText.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
}
