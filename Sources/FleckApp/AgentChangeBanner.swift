#if os(macOS)
  import SwiftUI
  import FleckCore

  struct AgentBannerPresentation: Equatable {
    enum TransitionStyle {
      case crossfade
      case spatial
    }

    private(set) var feedback: AgentChangeFeedback
    private(set) var count: Int

    init(feedback: AgentChangeFeedback, count: Int = 1) {
      self.feedback = feedback
      self.count = count
    }

    var message: String {
      let actor: String
      switch feedback.actor {
      case .integration(_, let displayName): actor = displayName
      case .localUser: actor = "Motes"
      }
      let suffix = count > 1 ? " (\(count))" : ""
      return "\(actor) updated \(feedback.noteTitle)\(suffix)"
    }

    mutating func coalesce(feedback: AgentChangeFeedback) {
      self.feedback = feedback
      count += 1
    }

    static func transition(reduceMotion: Bool) -> TransitionStyle {
      reduceMotion ? .crossfade : .spatial
    }
  }

  struct AgentChangeBanner: View {
    let presentation: AgentBannerPresentation
    let motion: AppMotion
    let onUndo: () -> Void

    var body: some View {
      HStack(spacing: 8) {
        Image(systemName: "point.3.connected.trianglepath.dotted")
        Text(presentation.message)
          .font(.caption)
          .lineLimit(1)
        Spacer()
        Button("Undo", action: onUndo)
          .buttonStyle(.borderless)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(.quaternary.opacity(0.45))
      .accessibilityElement(children: .contain)
      .transition(
        motion.reduceMotion
          ? .opacity
          : .opacity.combined(with: .offset(y: -motion.offset))
      )
    }
  }
#endif
