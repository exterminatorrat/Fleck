#if os(macOS)
  import SwiftUI
  import FleckCore

  enum OnboardingRailItemState: Equatable {
    case completed
    case current
    case upcoming

    var accessibilityValue: String {
      switch self {
      case .completed: "completed"
      case .current: "current"
      case .upcoming: "upcoming"
      }
    }
  }

  struct OnboardingRailItemPresentation: Equatable, Identifiable {
    let step: OnboardingStep
    let title: String
    let subtitle: String?
    let state: OnboardingRailItemState
    var id: OnboardingStep { step }
  }

  struct OnboardingRailPresentation: Equatable {
    let items: [OnboardingRailItemPresentation]

    init(current: OnboardingStep) {
      let titles = [
        "Welcome",
        "Your first note",
        "Dictation",
        "Permissions",
        "Get Fleck",
      ]
      let currentIndex = OnboardingStep.allCases.firstIndex(of: current) ?? 0
      items = zip(OnboardingStep.allCases, titles).enumerated().map {
        index, pair in
        let state: OnboardingRailItemState =
          index < currentIndex ? .completed : index == currentIndex ? .current : .upcoming
        return .init(
          step: pair.0,
          title: pair.1,
          subtitle: nil,
          state: state
        )
      }
    }
  }

  enum OnboardingWelcomePresentation {
    static let title = "Welcome to Fleck"
    static let body =
      "Fleck lives in your menu bar, so a thought is always close. "
      + "Your notes stay on this Mac. No sign-up or subscription."
  }

  struct OnboardingPermissionPresentation: Equatable {
    let title: String
    let body: String
    let primaryTitle: String

    init(
      cursor: OnboardingPermissionCursor,
      modifier: DictationModifierKey
    ) {
      switch cursor {
      case .microphone:
        title = "Let Fleck hear dictation"
        body =
          "Fleck uses the microphone only while you dictate. Audio stays in "
          + "memory and is discarded when capture ends, is cancelled, or fails."
        primaryTitle = "Allow Microphone"
      case .speechRecognition:
        title = "Turn speech into text"
        body =
          "Apple Speech turns your audio into text on this Mac. Fleck requires "
          + "on-device recognition and does not use a cloud fallback."
        primaryTitle = "Allow Speech Recognition"
      case .inputMonitoring:
        title = "Use \(modifier.displayName) anywhere"
        body =
          "Input Monitoring lets Fleck see press and release changes for your "
          + "selected modifier. Fleck does not read, store, or log ordinary keys."
        primaryTitle = "Allow Input Monitoring"
      case .compatibility:
        title = "What works on this Mac"
        body =
          "If cleanup is unavailable, Fleck keeps the original transcript. "
          + "If Smart Capture is unavailable, Fleck saves safely to Inbox."
        primaryTitle = "Continue"
      }
    }
  }

  struct OnboardingActionPresentation: Equatable, Identifiable {
    let action: FleckAccessAction
    let title: String
    let enabled: Bool
    var id: FleckAccessAction { action }
  }

  struct OnboardingGetFleckPresentation: Equatable {
    let body =
      "Full access to notes, dictation, Smart Capture, customization, and "
      + "agent connections. No credit card. No Apple purchase sheet. "
      + "You will not be charged automatically."
    let actions: [OnboardingActionPresentation]

    init(access: FleckAccessPresentation) {
      actions = [
        .init(
          action: .startTrial,
          title: "Start 7-Day Free Trial",
          enabled: access.inFlightAction == nil
        ),
        .init(
          action: .purchaseLifetime,
          title: access.localizedLifetimePrice.map { "Buy Fleck — \($0)" }
            ?? "Buy Fleck — Price unavailable",
          enabled: access.localizedLifetimePrice != nil
            && access.inFlightAction == nil
        ),
        .init(
          action: .restorePurchase,
          title: "Restore Purchase",
          enabled: access.inFlightAction == nil
        ),
      ]
    }
  }

  struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var dictationRuntime: DictationRuntime

    var body: some View {
      HStack(spacing: 0) {
        OnboardingRail(
          presentation: .init(current: coordinator.visibleStep)
        )
        Divider().opacity(0.45)
        VStack(spacing: 0) {
          stepContent
            .id(coordinator.visibleStep)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
          Divider().opacity(0.45)
          OnboardingFooter(coordinator: coordinator)
        }
      }
      .frame(minWidth: 920, idealWidth: 1_080, minHeight: 620, idealHeight: 700)
      .background {
        if reduceTransparency {
          Color(nsColor: .windowBackgroundColor)
        } else {
          Rectangle().fill(.ultraThinMaterial)
        }
      }
      .tint(.blue)
      .preferredColorScheme(.dark)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: coordinator.visibleStep)
    }

    @ViewBuilder
    private var stepContent: some View {
      switch coordinator.visibleStep {
      case .welcome:
        welcome
      case .firstNote:
        liveCanvas(
          title: "Write your first thought",
          detail: "This is Fleck's actual note. Add anything below to continue."
        )
      case .dictation:
        dictation
      case .permissions:
        permissions
      case .getFleck:
        getFleck
      }
    }

    private var welcome: some View {
      VStack(alignment: .leading, spacing: 24) {
        Spacer()
        Image(systemName: "note.text")
          .font(.system(size: 36, weight: .medium))
          .foregroundStyle(.blue)
        Text(OnboardingWelcomePresentation.title)
          .font(.system(size: 34, weight: .semibold))
          .accessibilityHeading(.h1)
        Text(OnboardingWelcomePresentation.body)
          .font(.title3)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 18) {
          Label("Menu bar ready", systemImage: "menubar.rectangle")
          Label("Local-first", systemImage: "lock")
          Label("No subscription", systemImage: "checkmark.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(48)
      .frame(maxWidth: 650, alignment: .leading)
    }

    private func liveCanvas(title: String, detail: String) -> some View {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(.title2.weight(.semibold))
            .accessibilityHeading(.h1)
          Text(detail)
            .foregroundStyle(.secondary)
        }
        NotesPanel(dictationRuntime: dictationRuntime, isPinned: true)
          .environmentObject(appState)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(.white.opacity(0.1))
          }
          .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
      }
      .padding(32)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dictation: some View {
      VStack(alignment: .leading, spacing: 18) {
        Text("Dictate into the note you just made")
          .font(.title2.weight(.semibold))
          .accessibilityHeading(.h1)
        Text(
          "Choose the modifier you want to hold. Fleck's real dictation "
            + "capsule appears at its configured screen edge."
        )
        .foregroundStyle(.secondary)
        Picker("Hold to dictate", selection: $coordinator.selectedModifier) {
          ForEach(DictationModifierKey.allCases, id: \.self) { modifier in
            Text(modifier.displayName).tag(modifier)
          }
        }
        .frame(maxWidth: 320)
        liveCanvas(
          title: "Try it in Fleck",
          detail:
            "Click in the editor, then use \(coordinator.selectedModifier.displayName) "
            + "or Fleck's microphone button."
        )
        .padding(0)
      }
      .padding(32)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var permissions: some View {
      let presentation = OnboardingPermissionPresentation(
        cursor: coordinator.permissionCursor,
        modifier: coordinator.selectedModifier
      )
      VStack(alignment: .leading, spacing: 24) {
        Text(presentation.title)
          .font(.title2.weight(.semibold))
          .accessibilityHeading(.h1)
        Text(presentation.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if coordinator.permissionCursor == .compatibility {
          compatibility
        } else {
          Spacer()
          HStack {
            Button("Not Now") {
              Task { await coordinator.deferCurrentPermission() }
            }
            Spacer()
            Button(presentation.primaryTitle) {
              Task { await coordinator.requestCurrentPermission() }
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
      .padding(40)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var compatibility: some View {
      let presentation = DictationCompatibilityPresentation(
        availability: dictationRuntime.availability
      )
      return VStack(spacing: 10) {
        ForEach(
          [
            presentation.notes,
            presentation.appleSpeech,
            presentation.cleanup,
            presentation.smartCapture,
          ],
          id: \.title
        ) { row in
          HStack {
            Label(
              row.title,
              systemImage: row.available ? "checkmark.circle.fill" : "info.circle"
            )
            .foregroundStyle(row.available ? Color.green : Color.secondary)
            Spacer()
            Text(row.detail).foregroundStyle(.secondary)
          }
          .padding(12)
          .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        }
        Text("You can change any deferred permission later in Settings → Dictation.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }

    private var getFleck: some View {
      let access = coordinator.accessActions.presentation
      let presentation = OnboardingGetFleckPresentation(access: access)
      return VStack(alignment: .leading, spacing: 24) {
        Spacer()
        Image(systemName: "checkmark.seal")
          .font(.system(size: 34))
          .foregroundStyle(.blue)
        Text("Get Fleck")
          .font(.system(size: 32, weight: .semibold))
          .accessibilityHeading(.h1)
        Text("Try everything free for 7 days.")
          .font(.title3.weight(.medium))
        Text(presentation.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        VStack(spacing: 10) {
          ForEach(presentation.actions) { action in
            if action.action == .startTrial {
              accessButton(action)
                .buttonStyle(.borderedProminent)
            } else {
              accessButton(action)
                .buttonStyle(.bordered)
            }
          }
        }
        if let message = coordinator.message ?? access.message {
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(48)
      .frame(maxWidth: 620, alignment: .leading)
    }

    private func accessButton(
      _ action: OnboardingActionPresentation
    ) -> some View {
      Button(action.title) {
        Task { await coordinator.performAccessAction(action.action) }
      }
      .controlSize(.large)
      .frame(maxWidth: .infinity)
      .disabled(!action.enabled || coordinator.isPerformingAccessAction)
    }
  }

  private struct OnboardingRail: View {
    let presentation: OnboardingRailPresentation

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Label("Fleck", systemImage: "note.text")
          .font(.headline)
          .padding(.bottom, 36)
        ForEach(Array(presentation.items.enumerated()), id: \.element.id) {
          index, item in
          HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
              ZStack {
                Circle()
                  .fill(item.state == .current ? Color.blue : Color.white.opacity(0.08))
                  .frame(width: 26, height: 26)
                if item.state == .completed {
                  Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                } else {
                  Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(item.state == .current ? .white : .secondary)
                }
              }
              if index < presentation.items.count - 1 {
                Rectangle()
                  .fill(item.state == .completed ? Color.blue.opacity(0.7) : .white.opacity(0.08))
                  .frame(width: 1, height: 34)
              }
            }
            Text(item.title)
              .font(.callout.weight(item.state == .current ? .semibold : .regular))
              .foregroundStyle(item.state == .upcoming ? .secondary : .primary)
              .padding(.top, 4)
            Spacer()
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(item.title), \(item.state.accessibilityValue)")
        }
        Spacer()
        Label("Notes stay local", systemImage: "lock")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(28)
      .frame(width: 240)
      .frame(maxHeight: .infinity, alignment: .topLeading)
      .background(.black.opacity(0.16))
    }
  }

  private struct OnboardingFooter: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
      HStack {
        Button("Back") {
          coordinator.goBack()
        }
        .disabled(coordinator.visibleStep == .welcome || coordinator.isSaving)
        Spacer()
        HStack(spacing: 6) {
          ForEach(OnboardingStep.allCases, id: \.self) { step in
            Circle()
              .fill(step == coordinator.visibleStep ? Color.blue : Color.secondary.opacity(0.3))
              .frame(width: 6, height: 6)
          }
        }
        .accessibilityHidden(true)
        Spacer()
        if coordinator.visibleStep != .getFleck {
          Button("Continue") {
            Task { await coordinator.continueFromCurrentStep() }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!coordinator.canContinue || coordinator.isSaving)
        }
      }
      .padding(.horizontal, 24)
      .frame(height: 72)
    }
  }
#endif
