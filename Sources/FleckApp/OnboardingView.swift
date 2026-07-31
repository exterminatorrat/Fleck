#if os(macOS)
  import SwiftUI
  import FleckCore

  struct OnboardingLayoutPresentation: Equatable {
    enum Tier: Equatable {
      case compact
      case regular
    }

    let tier: Tier

    init(width: CGFloat, height: CGFloat) {
      tier = width >= 920 && height >= 620 ? .regular : .compact
    }

    var railWidth: CGFloat { tier == .regular ? 240 : 188 }
    var contentPadding: CGFloat { tier == .regular ? 32 : 20 }
    var footerHeight: CGFloat { tier == .regular ? 72 : 64 }
    var minimumEditorHeight: CGFloat { tier == .regular ? 240 : 180 }
  }

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
      GeometryReader { geometry in
        let layout = OnboardingLayoutPresentation(
          width: geometry.size.width,
          height: geometry.size.height
        )

        HStack(spacing: 0) {
          OnboardingRail(
            presentation: .init(current: coordinator.visibleStep),
            layout: layout
          )
          Divider().opacity(0.45)
          VStack(spacing: 0) {
            stepContent(layout: layout)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .clipped()
              .id(coordinator.visibleStep)
              .transition(
                reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
              )
            Divider().opacity(0.45)
            OnboardingFooter(coordinator: coordinator, layout: layout)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(
        minWidth: OnboardingWindowPresenter.minimumSize.width,
        idealWidth: OnboardingWindowPresenter.defaultSize.width,
        minHeight: OnboardingWindowPresenter.minimumSize.height,
        idealHeight: OnboardingWindowPresenter.defaultSize.height
      )
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
    private func stepContent(layout: OnboardingLayoutPresentation) -> some View {
      switch coordinator.visibleStep {
      case .welcome:
        welcome(layout: layout)
      case .firstNote:
        firstNote(layout: layout)
      case .dictation:
        dictation(layout: layout)
      case .permissions:
        permissions(layout: layout)
      case .getFleck:
        getFleck(layout: layout)
      }
    }

    private func welcome(layout: OnboardingLayoutPresentation) -> some View {
      adaptiveStaticStep(layout: layout) {
        welcomeContent
      }
    }

    private var welcomeContent: some View {
      VStack(alignment: .leading, spacing: 24) {
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
      }
      .frame(maxWidth: 650, alignment: .leading)
    }

    private func firstNote(layout: OnboardingLayoutPresentation) -> some View {
      VStack(alignment: .leading, spacing: layout.tier == .regular ? 18 : 14) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Write your first thought")
            .font(.title2.weight(.semibold))
            .accessibilityHeading(.h1)
          Text("This is Fleck's actual note. Add anything below to continue.")
            .foregroundStyle(.secondary)
        }
        liveEditorCanvas(layout: layout)
      }
      .padding(layout.contentPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func liveEditorCanvas(layout: OnboardingLayoutPresentation) -> some View {
      NotesPanel(
        dictationRuntime: dictationRuntime,
        isPinned: true,
        sizing: .container
      )
      .environmentObject(appState)
      .frame(minHeight: layout.minimumEditorHeight, maxHeight: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(.white.opacity(0.1))
      }
      .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
      .layoutPriority(1)
    }

    private func dictation(layout: OnboardingLayoutPresentation) -> some View {
      VStack(
        alignment: .leading,
        spacing: layout.tier == .regular ? 18 : 12
      ) {
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
        VStack(alignment: .leading, spacing: 6) {
          Text("Try it in Fleck")
            .font(.headline)
          Text(
            "Click in the editor, then use \(coordinator.selectedModifier.displayName) "
              + "or Fleck's microphone button."
          )
          .foregroundStyle(.secondary)
        }
        liveEditorCanvas(layout: layout)
        if coordinator.dictationDemoSucceeded {
          Label("Dictation added to First Note", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(.green)
        }
      }
      .padding(layout.contentPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .onAppear {
        coordinator.beginObservingDictationDemo()
      }
      .onChange(of: dictationRuntime.phase) {
        coordinator.observeDictationTerminalState()
      }
    }

    @ViewBuilder
    private func permissions(layout: OnboardingLayoutPresentation) -> some View {
      let presentation = OnboardingPermissionPresentation(
        cursor: coordinator.permissionCursor,
        modifier: coordinator.selectedModifier
      )
      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            Text(presentation.title)
              .font(.title2.weight(.semibold))
              .accessibilityHeading(.h1)
            Text(presentation.body)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if coordinator.permissionCursor == .compatibility {
              compatibility
            }
          }
          .padding(layout.contentPadding)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        if coordinator.permissionCursor != .compatibility {
          Divider().opacity(0.25)
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
          .padding(.horizontal, layout.contentPadding)
          .frame(height: layout.footerHeight)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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
          HStack(alignment: .firstTextBaseline) {
            Label(
              row.title,
              systemImage: row.available ? "checkmark.circle.fill" : "info.circle"
            )
            .foregroundStyle(row.available ? Color.green : Color.secondary)
            Spacer()
            Text(row.detail)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.trailing)
              .fixedSize(horizontal: false, vertical: true)
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

    private func getFleck(layout: OnboardingLayoutPresentation) -> some View {
      adaptiveStaticStep(layout: layout) {
        getFleckContent
      }
    }

    private var getFleckContent: some View {
      let access = coordinator.accessActions.presentation
      let presentation = OnboardingGetFleckPresentation(access: access)
      return VStack(alignment: .leading, spacing: 24) {
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
      }
      .frame(maxWidth: 620, alignment: .leading)
    }

    @ViewBuilder
    private func adaptiveStaticStep<Content: View>(
      layout: OnboardingLayoutPresentation,
      @ViewBuilder content: () -> Content
    ) -> some View {
      ViewThatFits(in: .vertical) {
        VStack {
          Spacer(minLength: 0)
          content()
            .frame(maxWidth: .infinity, alignment: .leading)
          Spacer(minLength: 0)
        }
        .padding(layout.contentPadding)
        ScrollView {
          content()
            .padding(layout.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
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
    let layout: OnboardingLayoutPresentation

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
      .padding(layout.tier == .regular ? 28 : 20)
      .frame(width: layout.railWidth)
      .frame(maxHeight: .infinity, alignment: .topLeading)
      .background(.black.opacity(0.16))
    }
  }

  private struct OnboardingFooter: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let layout: OnboardingLayoutPresentation

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
      .padding(.horizontal, layout.tier == .regular ? 24 : 20)
      .frame(height: layout.footerHeight)
    }
  }
#endif
