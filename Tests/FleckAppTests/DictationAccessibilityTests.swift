import AppKit
import Testing

@testable import FleckApp

@Test func DictationAccessibilityMapsEveryStatusToVisibleAndVoiceOverText() {
  let cases: [(DictationCapsuleStatus, String, String)] = [
    (.listening, "Listening", "Dictation listening"),
    (.cleaning, "Cleaning up", "Cleaning up dictation"),
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

  panel.allowsActions = true
  #expect(panel.canBecomeKey)
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

@Test @MainActor func DictationAccessibilityPositionsCapsuleAtActiveDisplayLowerCenter() {
  let visibleFrame = CGRect(x: 100, y: 200, width: 1_000, height: 800)

  let frame = DictationCapsuleController.frame(in: visibleFrame)

  #expect(frame.midX == visibleFrame.midX)
  #expect(frame.minY == visibleFrame.minY + DictationCapsuleController.bottomMargin)
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
