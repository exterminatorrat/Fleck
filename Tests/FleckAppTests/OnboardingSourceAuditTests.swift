import Foundation
import Testing

@Test func OnboardingSourceAuditUsesRealFleckSurfaces() throws {
  let source = try String(
    contentsOf: onboardingSourceURL(),
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
    "NativeRichTextEditor(",
    "DictationCoordinator(",
    "DictationCapsulePanel(",
  ] {
    #expect(!source.contains(forbidden), Comment(rawValue: forbidden))
  }
}

private func onboardingSourceURL() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/FleckApp/OnboardingView.swift")
}
