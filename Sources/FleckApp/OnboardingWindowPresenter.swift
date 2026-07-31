#if os(macOS)
  import AppKit
  import SwiftUI

  enum FleckRootContent: Equatable {
    case loading
    case resumeOnboarding
    case onboarding
    case notes
    case blocked
  }

  enum FleckRootPresentation {
    static func menuBar(for state: OnboardingGateState) -> FleckRootContent {
      switch state {
      case .loading: .loading
      case .required: .resumeOnboarding
      case .complete: .notes
      case .blocked: .blocked
      }
    }

    static func pinned(for state: OnboardingGateState) -> FleckRootContent {
      switch state {
      case .loading: .loading
      case .required: .onboarding
      case .complete: .notes
      case .blocked: .blocked
      }
    }
  }

  struct FleckMenuBarRoot: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var onboarding: OnboardingCoordinator
    @ObservedObject var dictationRuntime: DictationRuntime
    @State private var openedOnboarding = false

    var body: some View {
      Group {
        switch FleckRootPresentation.menuBar(for: onboarding.gateState) {
        case .loading:
          ProgressView("Opening Fleck…")
            .padding(28)
        case .resumeOnboarding:
          OnboardingResumePanel {
            openWindow(id: OnboardingWindowPresenter.windowIdentifier)
          }
        case .notes:
          NotesPanel(dictationRuntime: dictationRuntime)
        case .blocked:
          NotesPanel(dictationRuntime: dictationRuntime)
        case .onboarding:
          EmptyView()
        }
      }
      .task {
        await onboarding.bootstrap()
        openOnboardingIfNeeded()
      }
      .onChange(of: onboarding.gateState) {
        openOnboardingIfNeeded()
      }
    }

    private func openOnboardingIfNeeded() {
      guard onboarding.gateState == .required, !openedOnboarding else { return }
      openedOnboarding = true
      openWindow(id: OnboardingWindowPresenter.windowIdentifier)
    }
  }

  struct FleckPinnedNotesRoot: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var onboarding: OnboardingCoordinator
    @ObservedObject var dictationRuntime: DictationRuntime

    var body: some View {
      Group {
        switch FleckRootPresentation.pinned(for: onboarding.gateState) {
        case .loading:
          ProgressView("Opening Fleck…")
            .frame(width: 520, height: 430)
        case .onboarding:
          OnboardingFlowView(
            coordinator: onboarding,
            dictationRuntime: dictationRuntime
          )
        case .notes, .blocked:
          NotesPanel(dictationRuntime: dictationRuntime, isPinned: true)
        case .resumeOnboarding:
          EmptyView()
        }
      }
      .background(
        OnboardingWindowPresenter(
          gateState: onboarding.gateState,
          completedSize: NSSize(
            width: appState.preferences.panelWidth,
            height: appState.preferences.panelHeight
          )
        )
      )
      .task {
        await onboarding.bootstrap()
      }
    }
  }

  struct OnboardingResumePanel: View {
    let resume: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Label("Finish setting up Fleck", systemImage: "sparkles")
          .font(.headline)
        Text("Your place is saved. Continue onboarding to use Fleck.")
          .font(.callout)
          .foregroundStyle(.secondary)
        Button("Resume Onboarding", action: resume)
          .buttonStyle(.borderedProminent)
      }
      .padding(20)
      .frame(width: 320, alignment: .leading)
    }
  }

  struct OnboardingWindowPresenter: NSViewRepresentable {
    nonisolated static let windowIdentifier = "pinned-notes"
    nonisolated static let onboardingTitle = "Welcome to Fleck"
    nonisolated static let completedTitle = "Fleck"

    let gateState: OnboardingGateState
    let completedSize: NSSize

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    func makeNSView(context _: Context) -> NSView {
      NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
      DispatchQueue.main.async {
        context.coordinator.apply(
          gateState: gateState,
          completedSize: completedSize,
          to: view.window
        )
      }
    }

    @MainActor
    final class Coordinator {
      private var appliedState: OnboardingGateState?

      func apply(
        gateState: OnboardingGateState,
        completedSize: NSSize,
        to window: NSWindow?
      ) {
        guard let window, appliedState != gateState else { return }
        appliedState = gateState
        switch gateState {
        case .required:
          window.title = OnboardingWindowPresenter.onboardingTitle
          window.setContentSize(NSSize(width: 1_080, height: 700))
          NSApp.activate(ignoringOtherApps: true)
          window.makeKeyAndOrderFront(nil)
        case .complete:
          window.title = OnboardingWindowPresenter.completedTitle
          window.setContentSize(completedSize)
        case .loading, .blocked:
          break
        }
      }
    }
  }
#endif
