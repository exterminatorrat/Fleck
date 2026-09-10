#if os(macOS)
  import AppKit
  import Testing

  @testable import FleckApp

  @Test @MainActor func DictationCapsulePanelSurvivesRepeatedDefaultMotionLifecycle() async throws {
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel, markLoader: { nil })
    defer {
      controller.dismiss()
      panel.close()
    }

    #expect(panel.animationBehavior == .default)

    for _ in 0..<20 {
      controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
      controller.render(.listening)
      controller.render(.saved(destination: "Inbox"), action: .undo)
      controller.setDock(.left)
      #expect(panel.isVisible)

      controller.dismiss()
      #expect(!panel.isVisible)
      await Task.yield()
    }
    try await Task.sleep(for: .milliseconds(250))
  }
#endif
