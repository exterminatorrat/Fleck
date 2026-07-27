#if os(macOS)
  import AppKit
  import SwiftUI

  enum DictationCapsuleStatus: Equatable {
    case listening
    case cleaning
    case saved(destination: String)
    case savedWithoutCleanup(destination: String)
    case repairingModel
    case failed(String)

    var presentation: DictationCapsulePresentation {
      switch self {
      case .listening:
        .init(
          visibleText: "Listening",
          voiceOverText: "Dictation listening",
          symbolName: "waveform"
        )
      case .cleaning:
        .init(
          visibleText: "Cleaning up",
          voiceOverText: "Cleaning up dictation",
          symbolName: "sparkles"
        )
      case .saved(let destination):
        .init(
          visibleText: "Saved to \(destination)",
          voiceOverText: "Dictation saved to \(destination)",
          symbolName: "checkmark.circle.fill",
          isSuccess: true
        )
      case .savedWithoutCleanup(let destination):
        .init(
          visibleText: "Saved to \(destination) without cleanup",
          voiceOverText: "Dictation saved to \(destination) without cleanup",
          symbolName: "exclamationmark.triangle.fill",
          isSuccess: true
        )
      case .repairingModel:
        .init(
          visibleText: "Repairing enhanced model",
          voiceOverText: "Repairing enhanced dictation model",
          symbolName: "wrench.and.screwdriver.fill"
        )
      case .failed(let message):
        .init(
          visibleText: "Dictation failed",
          voiceOverText: "Dictation failed: \(message)",
          symbolName: "exclamationmark.circle.fill"
        )
      }
    }
  }

  struct DictationCapsulePresentation: Equatable {
    let visibleText: String
    let voiceOverText: String
    let symbolName: String
    var isSuccess = false
  }

  enum DictationCapsuleTransition: Equatable {
    case opacity
    case scaleAndOpacity

    static func forReduceMotion(_ reduceMotion: Bool) -> Self {
      reduceMotion ? .opacity : .scaleAndOpacity
    }
  }

  final class DictationCapsulePanel: NSPanel {
    init() {
      super.init(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
      )
      level = .floating
      collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      isFloatingPanel = true
      hidesOnDeactivate = false
      isReleasedWhenClosed = false
      isOpaque = false
      backgroundColor = .clear
      hasShadow = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
  }

  @MainActor
  final class DictationCapsuleController {
    static let size = CGSize(width: 280, height: 52)
    static let bottomMargin: CGFloat = 48
    static let successDismissDelay = Duration.seconds(1.2)

    let panel: DictationCapsulePanel
    private var dismissalTask: Task<Void, Never>?

    init(panel: DictationCapsulePanel = DictationCapsulePanel()) {
      self.panel = panel
    }

    func show(
      _ status: DictationCapsuleStatus,
      on screen: NSScreen? = nil,
      reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
      dismissalTask?.cancel()
      let presentation = status.presentation
      panel.contentView = NSHostingView(rootView: DictationCapsuleView(presentation: presentation))

      let finalFrame = Self.frame(in: (screen ?? activeScreen())?.visibleFrame ?? .zero)
      let transition = DictationCapsuleTransition.forReduceMotion(reduceMotion)
      panel.setFrame(
        transition == .opacity ? finalFrame : finalFrame.insetBy(dx: 8, dy: 4),
        display: false
      )
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.08
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().alphaValue = 1
        if transition == .scaleAndOpacity {
          panel.animator().setFrame(finalFrame, display: true)
        }
      }

      if presentation.isSuccess {
        dismissalTask = Task { [weak self] in
          try? await Task.sleep(for: Self.successDismissDelay)
          guard !Task.isCancelled else { return }
          self?.dismiss()
        }
      }
    }

    func dismiss() {
      dismissalTask?.cancel()
      dismissalTask = nil
      panel.orderOut(nil)
    }

    static func frame(in visibleFrame: CGRect) -> CGRect {
      CGRect(
        x: visibleFrame.midX - size.width / 2,
        y: visibleFrame.minY + bottomMargin,
        width: size.width,
        height: size.height
      )
    }

    static func preferredDisplay<T>(
      keyboardFocus: T?,
      pointer: T?,
      primary: T?
    ) -> T? {
      keyboardFocus ?? pointer ?? primary
    }

    private func activeScreen() -> NSScreen? {
      let pointer = NSEvent.mouseLocation
      let pointerScreen = NSScreen.screens.first { $0.frame.contains(pointer) }
      return Self.preferredDisplay(
        keyboardFocus: NSScreen.main,
        pointer: pointerScreen,
        primary: NSScreen.screens.first
      )
    }
  }

  private struct DictationCapsuleView: View {
    let presentation: DictationCapsulePresentation

    var body: some View {
      HStack(spacing: 10) {
        Image(systemName: presentation.symbolName)
          .font(.system(size: 15, weight: .semibold))
        Text(presentation.visibleText)
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(1)
      }
      .foregroundStyle(.primary)
      .padding(.horizontal, 18)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.regularMaterial, in: Capsule())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(presentation.voiceOverText)
    }
  }
#endif
