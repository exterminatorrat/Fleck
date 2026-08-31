import AppKit
import FleckCore
import Testing

@testable import FleckApp

@Test func DictationAccessibilityMapsEveryStatusToVisibleAndVoiceOverText() {
  let cases: [(DictationCapsuleStatus, String?, String)] = [
    (.idle, nil, "Fleck dictation ready"),
    (.listening, nil, "Dictation listening"),
    (.finalizing, "Finishing", "Finishing dictation"),
    (.cleaning, "Cleaning up", "Cleaning up dictation"),
    (.routing, "Finding note", "Finding a note for dictation"),
    (.saved(destination: "Inbox"), "Saved to Inbox", "Dictation saved to Inbox"),
    (
      .savedWithoutCleanup(destination: "Inbox"),
      "Saved to Inbox without cleanup",
      "Dictation saved to Inbox without cleanup"
    ),
    (
      .repairingModel,
      "Repairing enhanced model",
      "Repairing enhanced dictation model"
    ),
    (
      .failed("Microphone unavailable"),
      "Dictation failed",
      "Dictation failed: Microphone unavailable"
    ),
  ]

  for (status, visibleText, voiceOverText) in cases {
    let presentation = status.presentation
    #expect(presentation.visibleText == visibleText)
    #expect(presentation.voiceOverText == voiceOverText)
    #expect(!presentation.symbolName.isEmpty)
  }
}

@Test func DictationAccessibilityReduceMotionUsesOpacityOnly() {
  #expect(DictationCapsuleTransition.forReduceMotion(true) == .opacity)
  #expect(DictationCapsuleTransition.forReduceMotion(false) == .scaleAndOpacity)
}

@Test @MainActor func DictationAccessibilityPanelNeverActivatesTheApp() {
  let panel = DictationCapsulePanel()

  #expect(panel.styleMask.contains(.nonactivatingPanel))
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
  #expect(panel.level == .floating)
  #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
  #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
  #expect(panel.collectionBehavior.contains(.stationary))

  panel.allowsActions = true
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
}

@Test @MainActor func DictationAccessibilityChooserRemainsCaptureBoundAndNonactivating() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  let firstCaptureID = UUID()
  let secondCaptureID = UUID()
  let noteID = UUID()
  var selections: [(UUID, UUID?)] = []
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(
      captureID: firstCaptureID,
      choices: [
        .init(
          destination: .init(noteID: noteID, title: "Projects"),
          contextHint: "Roadmap"
        )
      ]
    )
  )

  controller.render(
    .saved(destination: "Inbox"),
    chooser: chooser,
    onChoice: { selections.append(($0, $1)) }
  )

  #expect(panel.allowsActions)
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
  controller.selectRoutingChoice(captureID: firstCaptureID, noteID: noteID)
  controller.selectRoutingChoice(captureID: firstCaptureID, noteID: nil)
  #expect(selections.count == 2)
  #expect(selections[0].0 == firstCaptureID)
  #expect(selections[0].1 == noteID)
  #expect(selections[1].0 == firstCaptureID)
  #expect(selections[1].1 == nil)

  controller.render(
    .saved(destination: "Inbox"),
    chooser: .init(
      ambiguity: .init(captureID: secondCaptureID, choices: chooser.choices.map {
        .init(
          destination: .init(noteID: $0.id, title: $0.title),
          contextHint: $0.contextHint
        )
      })
    ),
    onChoice: { selections.append(($0, $1)) }
  )
  controller.selectRoutingChoice(captureID: firstCaptureID, noteID: noteID)
  #expect(selections.count == 2)
  controller.selectRoutingChoice(captureID: secondCaptureID, noteID: noteID)
  #expect(selections.last?.0 == secondCaptureID)

  controller.render(
    .saved(destination: "Projects"),
    chooser: .init(
      ambiguity: .init(
        captureID: secondCaptureID,
        choices: [
          .init(
            destination: .init(noteID: noteID, title: "Projects"),
            contextHint: "Roadmap"
          )
        ]
      ),
      currentDestinationID: noteID,
      currentDestinationTitle: "Projects",
      allowsKeepInInbox: false
    ),
    onChoice: { selections.append(($0, $1)) }
  )
  let movedSelectionCount = selections.count
  controller.selectRoutingChoice(captureID: secondCaptureID, noteID: nil)
  #expect(selections.count == movedSelectionCount)
}

@Test @MainActor func DictationAccessibilityChooserSurvivesDockReinstallationWithUndo() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  let captureID = UUID()
  let noteID = UUID()
  var selectedCaptureID: UUID?
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(
      captureID: captureID,
      choices: [
        .init(
          destination: .init(noteID: noteID, title: "Projects"),
          contextHint: "Roadmap"
        )
      ]
    )
  )

  controller.render(
    .saved(destination: "Inbox"),
    action: .undo,
    chooser: chooser,
    onChoice: { captureID, _ in selectedCaptureID = captureID }
  )
  controller.setDock(.left)
  controller.selectRoutingChoice(captureID: captureID, noteID: noteID)

  #expect(panel.allowsActions)
  #expect(selectedCaptureID == captureID)
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
}

@Test func DictationAccessibilityRecoveryActionsHaveKeyboardAndVoiceOverLabels() {
  let actions: [(DictationCapsuleAction, String)] = [
    (.undo, "Undo"),
    (.copy, "Copy"),
    (.openHistory, "Open Dictation History"),
    (.openDestination, "Open Destination"),
  ]

  for (action, title) in actions {
    #expect(action.title == title)
    #expect(action.accessibilityLabel == title)
  }
}

@Test @MainActor func DictationAccessibilityUsesCompactDockAwareGeometry() {
  let visibleFrame = CGRect(x: 100, y: 200, width: 1_000, height: 800)

  let bottom = DictationCapsuleController.frame(for: .bottom, in: visibleFrame)
  let left = DictationCapsuleController.frame(for: .left, in: visibleFrame)
  let right = DictationCapsuleController.frame(for: .right, in: visibleFrame)

  #expect(DictationCapsuleController.idleSize == CGSize(width: 40, height: 26))
  #expect(DictationCapsuleController.listeningSize == CGSize(width: 196, height: 32))
  #expect(DictationCapsuleController.activeSize.height == 32)
  #expect(bottom.size == CGSize(width: 40, height: 26))
  #expect(bottom.midX == visibleFrame.midX)
  #expect(bottom.minY > visibleFrame.minY)
  #expect(left.minX > visibleFrame.minX)
  #expect(left.midY == visibleFrame.midY)
  #expect(right.maxX < visibleFrame.maxX)
  #expect(right.midY == visibleFrame.midY)
}

@Test @MainActor func DictationAccessibilityKeepsEveryActiveStatusAtCompactThickness() {
  #expect(DictationCapsuleController.size(for: .listening) == CGSize(width: 196, height: 32))
  for status in [
    DictationCapsuleStatus.finalizing,
    .cleaning,
    .routing,
    .saved(destination: "Inbox"),
    .savedWithoutCleanup(destination: "Inbox"),
    .repairingModel,
    .failed("Unavailable"),
  ] {
    #expect(DictationCapsuleController.size(for: status).height == 32)
  }
}

@Test @MainActor func DictationAccessibilitySelectsTheNearestSupportedDock() {
  let visibleFrame = CGRect(x: 100, y: 200, width: 1_000, height: 800)

  #expect(DictationCapsuleController.nearestDock(
    to: CGPoint(x: visibleFrame.minX, y: visibleFrame.midY),
    in: visibleFrame
  ) == .left)
  #expect(DictationCapsuleController.nearestDock(
    to: CGPoint(x: visibleFrame.maxX, y: visibleFrame.midY),
    in: visibleFrame
  ) == .right)
  #expect(DictationCapsuleController.nearestDock(
    to: CGPoint(x: visibleFrame.midX, y: visibleFrame.minY),
    in: visibleFrame
  ) == .bottom)
}

@Test @MainActor func DictationAccessibilityKeepsOnePanelAndOffersDockMenuFallback() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  var dockChanges: [DictationCapsuleDock] = []
  controller.presentIdle(
    dock: .bottom,
    onOpenFleck: {},
    onDockChanged: { dockChanges.append($0) }
  )

  #expect(controller.panel === panel)
  #expect(panel.contentView?.menu?.items.map(\.title) == [
    "Dock Bottom",
    "Dock Left",
    "Dock Right",
  ])
  panel.contentView?.menu?.performActionForItem(at: 1)
  #expect(controller.currentDock == .left)
  #expect(dockChanges == [.left])

  controller.render(.failed("Unavailable"), action: .copy, onAction: {})
  #expect(controller.panel === panel)
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityPrefersKeyboardFocusDisplayOverPointerAndPrimary() {
  let selected = DictationCapsuleController.preferredDisplay(
    keyboardFocus: "keyboard",
    pointer: "pointer",
    primary: "primary"
  )

  #expect(selected == "keyboard")
  #expect(DictationCapsuleController.preferredDisplay(
    keyboardFocus: nil,
    pointer: "pointer",
    primary: "primary"
  ) == "pointer")
}

@Test func DictationAccessibilityPersonalDictionaryExposesSearchRowsTransfersAndPreviewActions()
  throws
{
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  for label in [
    "Personal dictionary filter",
    "Enable \\(entry.preferredForm)",
    "Delete \\(entry.preferredForm)",
    "Approve \\(suggestion.preferredForm)",
    "Edit and approve \\(suggestion.preferredForm)",
    "Dismiss \\(suggestion.preferredForm)",
    "Export complete personal dictionary",
    "Export visible entries as CSV",
    "Import personal dictionary",
    "Confirm dictionary import",
    "Cancel dictionary import",
  ] {
    #expect(settingsSource.contains("accessibilityLabel(\"\(label)\")"))
  }
  #expect(settingsSource.contains(
    ".searchable(text: $viewModel.query, prompt: \"Search personal dictionary\")"
  ))
  #expect(settingsSource.contains(".accessibilityValue("))
  #expect(settingsSource.contains(".accessibilityHint("))
  #expect(settingsSource.contains(".focusable()"))
  #expect(settingsSource.contains(".keyboardShortcut(.defaultAction)"))
  #expect(settingsSource.contains("accessibilityImportLabel"))
}

@Test func DictationAccessibilityImportPreviewExposesStatusAndErrorInsideTheSheet() throws {
  let previewSource = try personalDictionaryImportPreviewSource()

  #expect(previewSource.contains("if let errorMessage = viewModel.errorMessage"))
  #expect(previewSource.contains("else if let statusMessage = viewModel.statusMessage"))
  #expect(previewSource.contains("accessibilityLabel(\"Dictionary import error\")"))
  #expect(previewSource.contains("accessibilityLabel(\"Dictionary import status\")"))
}

@Test func DictationAccessibilitySuggestionEditExposesStatusAndErrorInsideTheSheet() throws {
  let settingsSource = try settingsViewSource()
  let editSource = try personalDictionarySuggestionEditSource(settingsSource)

  #expect(settingsSource.contains("errorMessage: viewModel.errorMessage"))
  #expect(settingsSource.contains("statusMessage: viewModel.statusMessage"))
  #expect(editSource.contains("if let errorMessage"))
  #expect(editSource.contains("else if let statusMessage"))
  #expect(editSource.contains("accessibilityLabel(\"Suggestion edit error\")"))
  #expect(editSource.contains("accessibilityLabel(\"Suggestion edit status\")"))
  #expect(editSource.contains("accessibilityValue(errorMessage)"))
  #expect(editSource.contains("accessibilityValue(statusMessage)"))
}

@Test func DictationAccessibilityImportPreviewRendersConflictsOutsideTheChangeBranch() throws {
  let previewLines = try personalDictionaryImportPreviewSource().split(
    separator: "\n",
    omittingEmptySubsequences: false
  )
  let changesCondition = try #require(previewLines.first {
    $0.contains("if viewModel.importPreviewRows.isEmpty")
  })
  let conflictsLoop = try #require(previewLines.first {
    $0.contains("ForEach(viewModel.importConflictRows)")
  })

  #expect(
    changesCondition.prefix { $0 == " " }.count
      == conflictsLoop.prefix { $0 == " " }.count
  )
}

private func personalDictionaryImportPreviewSource() throws -> String {
  let settingsSource = try settingsViewSource()
  let start = try #require(settingsSource.range(
    of: "private struct PersonalDictionaryImportPreviewSheet"
  ))
  let end = try #require(settingsSource.range(
    of: "private struct PersonalDictionaryTransferDocument",
    range: start.upperBound..<settingsSource.endIndex
  ))
  return String(settingsSource[start.lowerBound..<end.lowerBound])
}

private func personalDictionarySuggestionEditSource(_ settingsSource: String) throws -> String {
  let start = try #require(settingsSource.range(
    of: "private struct PersonalDictionarySuggestionEditSheet"
  ))
  let end = try #require(settingsSource.range(
    of: "private struct PersonalDictionaryImportPreviewSheet",
    range: start.upperBound..<settingsSource.endIndex
  ))
  return String(settingsSource[start.lowerBound..<end.lowerBound])
}

private func settingsViewSource() throws -> String {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
}
