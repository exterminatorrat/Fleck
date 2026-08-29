import Foundation
import Testing

@testable import FleckApp

@Test func DictationAmbiguityPresentationCapsModelChoicesAndAddsKeepInbox() throws {
  let captureID = UUID()
  let choices = (1...6).map { index in
    DictationRoutingChoice(
      destination: .init(noteID: UUID(), title: "Note \(index)"),
      contextHint: "Context \(index)"
    )
  }

  let chooser = DictationCapsuleChooser(
    ambiguity: .init(captureID: captureID, choices: choices)
  )

  #expect(chooser.captureID == captureID)
  #expect(chooser.choices.count == 4)
  #expect(chooser.choices.map(\.title) == ["Note 1", "Note 2", "Note 3", "Note 4"])
  #expect(chooser.keepInboxTitle == "Keep in Inbox")
  #expect(chooser.keepInboxAccessibilityLabel == "Keep dictation in Inbox")
}

@Test func DictationAmbiguityPresentationDisambiguatesDuplicateTitlesAccessibly() throws {
  let firstContext = String(repeating: "Alpha context ", count: 10)
  let secondContext = "Beta context"
  let choices = [
    DictationRoutingChoice(
      destination: .init(noteID: UUID(), title: "Projects"),
      contextHint: firstContext
    ),
    DictationRoutingChoice(
      destination: .init(noteID: UUID(), title: " projects "),
      contextHint: secondContext
    ),
    DictationRoutingChoice(
      destination: .init(noteID: UUID(), title: "Ideas"),
      contextHint: "Unique context"
    ),
  ]

  let chooser = DictationCapsuleChooser(
    ambiguity: .init(captureID: UUID(), choices: choices)
  )
  let first = try #require(chooser.choices.first)
  let second = chooser.choices[1]
  let unique = chooser.choices[2]

  #expect(first.menuTitle.hasPrefix("Projects — Alpha context"))
  #expect(first.menuTitle.count < first.accessibilityLabel.count)
  #expect(first.accessibilityLabel.contains(firstContext))
  #expect(first.accessibilityHint == "Moves this saved dictation from Inbox to Projects.")
  #expect(second.menuTitle == "projects — Beta context")
  #expect(unique.menuTitle == "Ideas")
  #expect(unique.accessibilityLabel.contains("Unique context"))
}
