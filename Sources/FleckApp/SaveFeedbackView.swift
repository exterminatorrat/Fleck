#if os(macOS)
  import Combine
  import Foundation
  import SwiftUI

  enum SaveFeedbackState: Equatable, Sendable {
    case saved
    case pending
    case saving
    case failed

    var accessibilityValue: String {
      switch self {
      case .saved: "All changes saved"
      case .pending: "Changes pending"
      case .saving: "Saving"
      case .failed: "Save failed"
      }
    }

    var helpText: String {
      switch self {
      case .saved: "All changes are saved"
      case .pending: "Changes are waiting to be saved"
      case .saving: "Saving changes"
      case .failed: "Fleck could not save changes. Read the message below the note."
      }
    }
  }

  @MainActor
  final class SaveFeedbackPresentation: ObservableObject {
    typealias RevealScheduler = (Duration, @escaping @MainActor () -> Void) -> Void

    static let revealDelay = Duration.milliseconds(800)

    @Published private(set) var state = SaveFeedbackState.saved
    private let scheduleReveal: RevealScheduler
    private var activeWriteCount = 0
    private var generation: UInt64 = 0

    init(
      scheduleReveal: @escaping RevealScheduler = { delay, action in
        Task { @MainActor in
          try? await Task.sleep(for: delay)
          action()
        }
      }
    ) {
      self.scheduleReveal = scheduleReveal
    }

    func changesScheduled() {
      guard state == .saved else { return }
      state = .pending
    }

    func writeBegan() {
      activeWriteCount += 1
      guard activeWriteCount == 1 else { return }
      generation &+= 1
      let revealGeneration = generation
      state = .pending
      scheduleReveal(Self.revealDelay) { [weak self] in
        guard let self,
          self.generation == revealGeneration,
          self.activeWriteCount > 0
        else { return }
        self.state = .saving
      }
    }

    func writeEnded() {
      activeWriteCount = max(0, activeWriteCount - 1)
      guard activeWriteCount == 0 else { return }
      generation &+= 1
    }

    func writeCancelled() {
      guard activeWriteCount == 0, state == .saving else { return }
      generation &+= 1
      state = .pending
    }

    func settle(_ outcome: SaveFeedbackState) {
      guard activeWriteCount == 0, outcome != .saving else { return }
      state = outcome
    }

    func reset() {
      activeWriteCount = 0
      generation &+= 1
      state = .saved
    }
  }

  struct SaveFeedbackView: View {
    @Environment(\.fleckThemeSnapshot) private var theme
    @ObservedObject var presentation: SaveFeedbackPresentation
    let motion: AppMotion

    var body: some View {
      ZStack(alignment: .trailing) {
        Color.clear
        if presentation.state == .saving {
          HStack(spacing: 5) {
            ProgressView()
              .controlSize(.mini)
            Text("Saving")
              .foregroundStyle(theme.color(.caption))
          }
          .transition(.opacity)
        }
      }
      .fleckUIFont(.caption)
      .frame(width: 62, height: 22, alignment: .trailing)
      .animation(motion.reduceMotion ? nil : motion.quick, value: presentation.state)
      .accessibilityElement(children: .ignore)
      .accessibilityIdentifier("save-feedback")
      .accessibilityLabel("Save status")
      .accessibilityValue(presentation.state.accessibilityValue)
      .help(presentation.state.helpText)
    }
  }
#endif
