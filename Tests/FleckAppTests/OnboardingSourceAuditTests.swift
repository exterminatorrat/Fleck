import Foundation
import Testing

@Test func OnboardingSourceAuditUsesRealFleckSurfaces() throws {
  let source = try String(
    contentsOf: onboardingSourceURL(),
    encoding: .utf8
  )
  let allSources = onboardingSources()
  let notesPanelSource = try String(
    contentsOf: onboardingSourceURL()
      .deletingLastPathComponent()
      .appendingPathComponent("NotesPanel.swift"),
    encoding: .utf8
  )
  for required in [
    "NotesPanel(",
    "DictationModifierKey",
    "displayName",
    "DictationCompatibilityPresentation",
  ] {
    #expect(source.contains(required), Comment(rawValue: required))
  }
  for forbidden in [
    "$2.99",
    "$4.99",
    "USD",
    "SKTestSession",
    "--onboarding-complete",
    "hasFullAccess = true",
    "UserDefaults.standard.set(true",
    "NativeRichTextEditor(",
    "DictationCoordinator(",
    "DictationCapsulePanel(",
  ] {
    #expect(!allSources.contains(forbidden), Comment(rawValue: forbidden))
  }
  for required in [
    "UnavailableFleckAccessActions",
    "localizedLifetimePrice",
    "No credit card",
    "No Apple purchase sheet",
    "not be charged automatically",
    "Settings → Dictation",
  ] {
    #expect(allSources.contains(required), Comment(rawValue: required))
  }
  #expect(source.contains("sizing: .container"))
  #expect(notesPanelSource.contains("enum NotesPanelSizing"))
  #expect(notesPanelSource.contains("sizing: NotesPanelSizing = .storedPreferences"))
}

private func onboardingSourceURL() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/FleckApp/OnboardingView.swift")
}

private func onboardingSources() -> String {
  let directory = onboardingSourceURL().deletingLastPathComponent()
  return [
    "OnboardingView.swift",
    "OnboardingCoordinator.swift",
    "FleckAccessActions.swift",
    "OnboardingWindowPresenter.swift",
  ]
  .compactMap {
    try? String(
      contentsOf: directory.appendingPathComponent($0),
      encoding: .utf8
    )
  }
  .joined(separator: "\n")
}
