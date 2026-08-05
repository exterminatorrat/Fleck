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

@Test @MainActor func completedLiveResizeClampsAndPersistsTheContentMinimum() {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: false
  )
  let coordinator = OnboardingWindowPresenter.Coordinator()
  var persistedSizes: [NSSize] = []
  coordinator.apply(
    gateState: .complete,
    completedSize: NSSize(width: 640, height: 430),
    onCompletedResize: { persistedSizes.append($0) },
    to: window
  )

  window.contentView?.setFrameSize(NSSize(width: 300, height: 227))
  NotificationCenter.default.post(
    name: NSWindow.didEndLiveResizeNotification,
    object: window
  )

  #expect(window.contentView?.bounds.size == OnboardingWindowPresenter.completedMinimumSize)
  #expect(persistedSizes == [OnboardingWindowPresenter.completedMinimumSize])
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
