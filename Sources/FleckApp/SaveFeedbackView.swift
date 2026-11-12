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
    private var activeWrites: Set<UUID> = []
    private var revealedWrites: Set<UUID> = []

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

    @discardableResult
    func writeBegan() -> UUID {
      let id = UUID()
      activeWrites.insert(id)
      if revealedWrites.isEmpty { state = .pending }
      scheduleReveal(Self.revealDelay) { [weak self] in
        guard let self,
          self.activeWrites.contains(id)
        else { return }
        self.revealedWrites.insert(id)
        self.state = .saving
      }
      return id
    }

    func writeEnded(_ id: UUID) {
      activeWrites.remove(id)
      revealedWrites.remove(id)
      if revealedWrites.isEmpty, state == .saving {
        state = .pending
      }
    }

    func settle(_ outcome: SaveFeedbackState) {
      guard activeWrites.isEmpty, outcome != .saving else { return }
      state = outcome
    }

    func reset() {
      activeWrites.removeAll()
      revealedWrites.removeAll()
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
