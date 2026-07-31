import Combine
import FleckCore

enum OnboardingBootstrapDecision: Equatable {
  case persistAndRequire(OnboardingProgress)
  case requireExisting
  case persistAndSkip(OnboardingProgress)
  case skipExisting
}

enum OnboardingBootstrapPolicy {
  static func resolve(
    source: LocalStoreSnapshotSource,
    progress: OnboardingProgress?
  ) -> OnboardingBootstrapDecision {
    guard let progress else {
      if source == .fresh {
        return .persistAndRequire(
          OnboardingProgress(status: .inProgress(step: .welcome))
        )
      }
      return .persistAndSkip(
        OnboardingProgress(status: .existingUserExempt)
      )
    }

    switch progress.status {
    case .inProgress:
      return .requireExisting
    case .completed, .existingUserExempt:
      return .skipExisting
    }
  }
}

enum OnboardingGateState: Equatable {
  case loading
  case required
  case complete
  case blocked(String)
}

@MainActor
final class OnboardingCoordinator: ObservableObject {
  static let firstNoteTitle = "First Note"
  static let firstNoteBody =
    "Fleck lives in your menu bar and keeps this note on your Mac.\n\n"
    + "Add your first thought below."

  @Published private(set) var gateState: OnboardingGateState = .loading
  @Published private(set) var visibleStep: OnboardingStep = .welcome
  @Published private(set) var permissionCursor: OnboardingPermissionCursor = .microphone
  @Published private(set) var isSaving = false
  @Published private(set) var isPerformingAccessAction = false
  @Published private(set) var message: String?
  @Published var selectedModifier: DictationModifierKey

  let accessActions: any FleckAccessActions

  private let appState: AppState
  private weak var dictationRuntime: DictationRuntime?
  private var accessAlreadyGranted = false

  init(
    appState: AppState,
    dictationRuntime: DictationRuntime?,
    accessActions: any FleckAccessActions
  ) {
    self.appState = appState
    self.dictationRuntime = dictationRuntime
    self.accessActions = accessActions
    selectedModifier = appState.preferences.dictationModifierKey
  }

  var persistedStep: OnboardingStep? {
    guard
      case .inProgress(let step) =
        appState.preferences.onboardingProgress?.status
    else { return nil }
    return step
  }

  var canContinue: Bool {
    guard visibleStep == .firstNote else { return true }
    guard let note = appState.selectedNote else { return false }
    return note.title != Self.firstNoteTitle
      || note.body != Self.firstNoteBody
      || note.richTextRTF != nil
  }

  func bootstrap() async {
    await appState.waitUntilInitialLoad()
    guard let source = appState.initialSnapshotSource else {
      gateState = .blocked(
        appState.saveError ?? "Fleck could not load the local notes workspace."
      )
      return
    }

    let decision = OnboardingBootstrapPolicy.resolve(
      source: source,
      progress: appState.preferences.onboardingProgress
    )
    do {
      switch decision {
      case .persistAndRequire(let progress):
        try await persist(progress)
        apply(progress)
        gateState = .required
      case .requireExisting:
        if let progress = appState.preferences.onboardingProgress {
          apply(progress)
        }
        gateState = .required
      case .persistAndSkip(let progress):
        try await persist(progress)
        gateState = .complete
      case .skipExisting:
        gateState = .complete
      }
    } catch {
      gateState = .blocked(error.localizedDescription)
    }
  }

  func prepareFirstNoteIfNeeded() async {
    guard appState.workspace.notes.count == 1,
      let note = appState.selectedNote
    else { return }
    guard note.title == "Untitled", note.body.isEmpty, note.richTextRTF == nil else {
      return
    }

    appState.updateSelected(
      title: Self.firstNoteTitle,
      body: Self.firstNoteBody
    )
    do {
      try await appState.saveNow(transactionOwned: true).value
    } catch {
      message = error.localizedDescription
    }
  }

  func continueFromCurrentStep() async {
    switch visibleStep {
    case .welcome:
      await advance(to: .firstNote)
      await prepareFirstNoteIfNeeded()
    case .firstNote:
      guard canContinue else { return }
      await advance(to: .dictation)
    case .dictation:
      appState.updatePreferences { $0.dictationModifierKey = selectedModifier }
      dictationRuntime?.preferencesDidChange()
      await advance(to: .permissions)
    case .permissions:
      guard permissionCursor == .compatibility else { return }
      await advance(to: .getFleck)
    case .getFleck:
      break
    }
  }

  func goBack() {
    guard
      let index = OnboardingStep.allCases.firstIndex(of: visibleStep),
      index > 0
    else { return }
    visibleStep = OnboardingStep.allCases[index - 1]
  }

  func requestCurrentPermission() async {
    switch permissionCursor {
    case .microphone:
      await dictationRuntime?.requestMicrophonePermission()
    case .speechRecognition:
      await dictationRuntime?.requestSpeechRecognitionPermission()
    case .inputMonitoring:
      _ = await dictationRuntime?.requestInputMonitoringPermission()
    case .compatibility:
      await continueFromCurrentStep()
      return
    }
    await advancePermission()
  }

  func deferCurrentPermission() async {
    await advancePermission()
  }

  func performAccessAction(_ action: FleckAccessAction) async {
    guard !isPerformingAccessAction else { return }
    isPerformingAccessAction = true
    defer { isPerformingAccessAction = false }
    message = nil

    let result: FleckAccessActionResult
    switch action {
    case .startTrial:
      result = await accessActions.startTrial()
    case .purchaseLifetime:
      result = await accessActions.purchaseLifetime()
    case .restorePurchase:
      result = await accessActions.restorePurchase()
    }

    switch result {
    case .trialActive where accessActions.presentation.hasFullAccess:
      accessAlreadyGranted = true
      await persistCompletion()
    case .purchased where accessActions.presentation.hasFullAccess:
      accessAlreadyGranted = true
      await persistCompletion()
    case .cancelled, .pending, .nothingToRestore, .unavailable:
      message = accessActions.presentation.message
    case .failed(let failure):
      message = failure
    case .trialActive, .purchased:
      message = "Fleck could not verify access. Please try again."
    }
  }

  func finishSetupAfterPersistenceFailure() async {
    guard accessAlreadyGranted, accessActions.presentation.hasFullAccess else {
      return
    }
    await persistCompletion()
  }

  private func advance(to step: OnboardingStep) async {
    let progress = OnboardingProgress(
      status: .inProgress(step: step),
      permissionCursor: permissionCursor
    )
    do {
      try await persist(progress)
      visibleStep = step
      message = nil
    } catch {
      message = error.localizedDescription
    }
  }

  private func advancePermission() async {
    guard
      let index = OnboardingPermissionCursor.allCases.firstIndex(of: permissionCursor),
      index + 1 < OnboardingPermissionCursor.allCases.count
    else { return }
    let next = OnboardingPermissionCursor.allCases[index + 1]
    let step = persistedStep ?? .permissions
    let progress = OnboardingProgress(
      status: .inProgress(step: step),
      permissionCursor: next
    )
    do {
      try await persist(progress)
      permissionCursor = next
      message = nil
    } catch {
      message = error.localizedDescription
    }
  }

  private func persistCompletion() async {
    do {
      try await persist(OnboardingProgress(status: .completed))
      gateState = .complete
      message = nil
    } catch {
      gateState = .required
      message = "Access is active, but Fleck could not finish setup: \(error.localizedDescription)"
    }
  }

  private func persist(_ progress: OnboardingProgress) async throws {
    isSaving = true
    defer { isSaving = false }
    try await appState.persistOnboardingProgress(progress)
  }

  private func apply(_ progress: OnboardingProgress) {
    permissionCursor = progress.permissionCursor
    if case .inProgress(let step) = progress.status {
      visibleStep = step
    }
  }
}
