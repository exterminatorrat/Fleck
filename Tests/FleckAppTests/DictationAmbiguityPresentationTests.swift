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
  #expect(chooser.menuAccessibilityLabel == "Choose note")
  #expect(chooser.menuAccessibilityHint == "Choose a note for this saved dictation or keep it in Inbox.")
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

@Test func DictationAmbiguityPresentationUsesMovedReceiptAsTruthfulOrigin() throws {
  let inboxID = UUID()
  let projectsID = UUID()
  let personalID = UUID()
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(
      captureID: UUID(),
      choices: [
        .init(
          destination: .init(noteID: projectsID, title: "Projects"),
          contextHint: "Roadmap"
        ),
        .init(
          destination: .init(noteID: personalID, title: "Personal"),
          contextHint: "Weekend"
        ),
      ]
    ),
    currentDestinationID: projectsID,
    currentDestinationTitle: "Projects",
    allowsKeepInInbox: projectsID == inboxID
  )

  #expect(!chooser.allowsKeepInInbox)
  #expect(!chooser.menuAccessibilityHint.contains("Inbox"))
  #expect(chooser.choices.allSatisfy { !$0.accessibilityHint.contains("from Inbox") })
  let current = try #require(chooser.choices.first(where: { $0.id == projectsID }))
  let alternative = try #require(chooser.choices.first(where: { $0.id == personalID }))
  #expect(current.accessibilityLabel.hasPrefix("Retry saving dictation in Projects"))
  #expect(current.accessibilityHint == "Retries completion for this saved dictation in Projects.")
  #expect(alternative.accessibilityHint == "Moves this saved dictation from Projects to Personal.")
}

@Test func DictationAmbiguityPresentationAnnouncesKeepWhenNoNoteChoicesRemain() {
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(captureID: UUID(), choices: []),
    allowsKeepInInbox: true
  )

  #expect(chooser.menuAccessibilityLabel == "Keep dictation in Inbox")
  #expect(chooser.menuAccessibilityHint == "Keeps this saved dictation in Inbox.")
}
