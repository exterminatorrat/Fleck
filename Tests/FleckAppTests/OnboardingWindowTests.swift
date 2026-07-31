import AppKit
import Testing

@testable import FleckApp

@Test func OnboardingWindowContentFollowsTheGate() {
  #expect(FleckRootPresentation.menuBar(for: .loading) == .loading)
  #expect(FleckRootPresentation.menuBar(for: .required) == .resumeOnboarding)
  #expect(FleckRootPresentation.menuBar(for: .complete) == .notes)
  #expect(FleckRootPresentation.pinned(for: .required) == .onboarding)
  #expect(FleckRootPresentation.pinned(for: .complete) == .notes)
}

@Test func OnboardingWindowReusesThePinnedIdentifier() {
  #expect(OnboardingWindowPresenter.windowIdentifier == "pinned-notes")
  #expect(OnboardingWindowPresenter.onboardingTitle == "Welcome to Fleck")
  #expect(OnboardingWindowPresenter.completedTitle == "Fleck")
}

@Test func OnboardingWindowDeclaresDefaultAndMinimumResponsiveSizes() {
  #expect(OnboardingWindowPresenter.defaultSize == NSSize(width: 1_080, height: 700))
  #expect(OnboardingWindowPresenter.minimumSize == NSSize(width: 760, height: 520))
}

@Test func OnboardingWindowSourceHasOneExistingScene() throws {
  let source = try String(
    contentsOf: appSourceURL(),
    encoding: .utf8
  )
  #expect(
    source.components(separatedBy: #"Window("Fleck", id: "pinned-notes")"#).count - 1
      == 1
  )
  #expect(!source.contains(#"Window("Onboarding""#))
}

private func appSourceURL() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/FleckApp/FleckApp.swift")
}
