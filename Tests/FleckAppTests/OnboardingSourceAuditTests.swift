import AppKit
import Foundation
import Testing

@testable import FleckApp

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
  for required in [
    "GeometryReader",
    "OnboardingLayoutPresentation(",
    "liveEditorCanvas(layout:",
    "ViewThatFits(in: .vertical)",
    ".layoutPriority(1)",
  ] {
    #expect(source.contains(required), Comment(rawValue: required))
  }
  #expect(source.components(separatedBy: "private func liveCanvas").count - 1 == 0)
  #expect(
    source.components(separatedBy: ".fixedSize(horizontal: false, vertical: true)").count - 1
      >= 7
  )
}

@Test func pinnedWindowUsesNativeCompletedSizingAndResizePersistence() throws {
  let source = try String(contentsOf: presenterSourceURL(), encoding: .utf8)

  #expect(source.contains("NotesPanel(dictationRuntime: dictationRuntime)"))
  #expect(
    source.contains(
      "NotesPanel(dictationRuntime: dictationRuntime, isPinned: true, sizing: .container)"
    )
  )
  for required in [
    "pinnedPanelWidth",
    "pinnedPanelHeight",
    "completedMinimumSize = NSSize(width: 480, height: 320)",
    "defaultSize = NSSize(width: 1_080, height: 700)",
    "minimumSize = NSSize(width: 760, height: 520)",
    "NSWindow.didEndLiveResizeNotification",
    "appliedState == .complete",
    "contentMinSize",
    "contentMaxSize",
    "styleMask.insert(.resizable)",
  ] {
    #expect(source.contains(required), Comment(rawValue: required))
  }
  #expect(!source.contains("DragGesture"))

  let visibleFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
  #expect(
    OnboardingWindowPresenter.clampedCompletedSize(
      NSSize(width: 1, height: 2),
      visibleFrame: visibleFrame
    ) == NSSize(width: 480, height: 320)
  )
  #expect(
    OnboardingWindowPresenter.clampedCompletedSize(
      NSSize(width: 1_200, height: 900),
      visibleFrame: visibleFrame
    ) == NSSize(width: 800, height: 600)
  )
}

private func onboardingSourceURL() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/FleckApp/OnboardingView.swift")
}

private func presenterSourceURL() -> URL {
  onboardingSourceURL()
    .deletingLastPathComponent()
    .appendingPathComponent("OnboardingWindowPresenter.swift")
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
