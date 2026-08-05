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

@Test @MainActor func completedWindowMaximumUsesChromeAwareContentBounds() {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
  )
  let visibleFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
  let coordinator = OnboardingWindowPresenter.Coordinator(
    visibleFrameProvider: { _ in visibleFrame }
  )

  coordinator.apply(
    gateState: .complete,
    completedSize: NSSize(width: 1_200, height: 900),
    onCompletedResize: { _ in },
    to: window
  )

  let expected = window.contentRect(forFrameRect: visibleFrame).size
  #expect(window.contentMaxSize == expected)
  #expect(window.contentView?.bounds.size == expected)
  #expect(visibleFrame.contains(window.frame))
}

@Test @MainActor func screenChangeClampsCompletedWindowAndPersistsOnlyOnce() {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: false
  )
  var visibleFrame = NSRect(x: 0, y: 0, width: 1_200, height: 900)
  var persisted: [NSSize] = []
  let coordinator = OnboardingWindowPresenter.Coordinator(
    visibleFrameProvider: { _ in visibleFrame }
  )
  coordinator.apply(
    gateState: .complete,
    completedSize: NSSize(width: 900, height: 640),
    onCompletedResize: { persisted.append($0) },
    to: window
  )

  visibleFrame = NSRect(x: 0, y: 0, width: 700, height: 500)
  NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
  NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)

  let expected = window.contentRect(forFrameRect: visibleFrame).size
  #expect(window.contentMaxSize == expected)
  #expect(window.contentView?.bounds.size == expected)
  #expect(visibleFrame.contains(window.frame))
  #expect(persisted == [expected])
}

@Test @MainActor func completedResizeObserverReplacesTheObservedWindowAndFiltersOtherStates() {
  let first = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled, .resizable], backing: .buffered, defer: false
  )
  let second = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled, .resizable], backing: .buffered, defer: false
  )
  var persisted: [NSSize] = []
  let coordinator = OnboardingWindowPresenter.Coordinator(
    visibleFrameProvider: { _ in NSRect(x: 0, y: 0, width: 900, height: 700) }
  )
  coordinator.apply(
    gateState: .complete,
    completedSize: NSSize(width: 640, height: 430),
    onCompletedResize: { persisted.append($0) },
    to: first
  )
  coordinator.apply(
    gateState: .required,
    completedSize: NSSize(width: 640, height: 430),
    onCompletedResize: { persisted.append($0) },
    to: second
  )

  NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: first)
  NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: second)

  #expect(persisted.isEmpty)
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
