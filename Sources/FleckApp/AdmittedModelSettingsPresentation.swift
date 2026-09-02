import Combine
import Foundation

enum AdmittedModelSettingsAction: Equatable, Sendable {
  case install
  case cancel
  case repair
  case update
  case remove
}

enum AdmittedModelSettingsContext: Equatable, Sendable {
  case dictation
  case cleanup(fallbackLabel: String)
}

struct AdmittedModelSettingsPresentation: Equatable {
  let detail: String
  let phase: AdmittedModelInstallPhase
  let identity: String?
  let modelLabel: String
  let progress: Double?
  let progressAccessibilityValue: String?
  let accessibilityLabel: String
  let accessibilityValue: String
  let isKeyboardFocusable: Bool
  let primaryAction: AdmittedModelSettingsAction?
  let primaryActionLabel: String?

  var allowsEnhancedPreference: Bool {
    identity != nil && phase == .installed
  }

  var showsStatus: Bool {
    Self.showsStatus(for: phase)
  }

  var showsDetail: Bool {
    Self.showsDetail(for: phase)
  }

  var compactStatus: String {
    Self.compactStatus(for: phase)
  }

  init(
    snapshot: AdmittedModelInstallationSnapshot,
    context: AdmittedModelSettingsContext = .dictation
  ) {
    phase = snapshot.phase

    let descriptor: AdmittedModelDescriptor?
    switch snapshot.recommendation {
    case .builtIn:
      descriptor = nil
    case .recommended(let value):
      descriptor = value
    }

    identity = descriptor?.modelID
    switch context {
    case .dictation:
      modelLabel = descriptor == nil ? "Apple Speech" : "Parakeet TDT 0.6B v2"
    case .cleanup(let fallbackLabel):
      modelLabel = descriptor == nil ? fallbackLabel : "Gemma 3 1B"
    }

    switch snapshot.phase {
    case .downloading(let receivedBytes, let totalBytes) where totalBytes > 0:
      progress = Double(receivedBytes) / Double(totalBytes)
      progressAccessibilityValue = Self.progressAccessibilityValue(
        receivedBytes: receivedBytes,
        totalBytes: totalBytes
      )
    default:
      progress = nil
      progressAccessibilityValue = nil
    }

    primaryAction = Self.action(for: snapshot.phase, hasDescriptor: descriptor != nil)
    primaryActionLabel = primaryAction.map {
      Self.label(for: $0, phase: snapshot.phase)
    }
    isKeyboardFocusable = primaryAction != nil
    detail = Self.detail(
      for: snapshot.phase,
      lastError: snapshot.lastError,
      context: context
    )
    switch context {
    case .dictation:
      accessibilityLabel = "Dictation model"
    case .cleanup:
      accessibilityLabel = "Cleanup model"
    }
    accessibilityValue = Self.accessibilityValue(
      for: snapshot.phase,
      modelLabel: modelLabel,
      lastError: snapshot.lastError,
      context: context
    )
  }

  private static func compactStatus(for phase: AdmittedModelInstallPhase) -> String {
    switch phase {
    case .builtIn:
      "Built in"
    case .notInstalled:
      "Available to install"
    case .downloading:
      "Downloading"
    case .verifying:
      "Verifying"
    case .installing:
      "Installing"
    case .ready:
      "Prepared to start"
    case .starting:
      "Starting"
    case .calibrating:
      "Calibrating"
    case .installed:
      "Installed"
    case .updateAvailable:
      "Update available"
    case .repairRequired:
      "Needs repair"
    case .removing:
      "Removing"
    case .cancelled:
      "Installation cancelled"
    case .failed:
      "Action failed"
    }
  }

  private static func showsStatus(for phase: AdmittedModelInstallPhase) -> Bool {
    switch phase {
    case .builtIn, .notInstalled, .installed:
      false
    default:
      true
    }
  }

  private static func showsDetail(for phase: AdmittedModelInstallPhase) -> Bool {
    switch phase {
    case .repairRequired, .cancelled, .failed:
      true
    default:
      false
    }
  }

  private static func detail(
    for phase: AdmittedModelInstallPhase,
    lastError: String?,
    context: AdmittedModelSettingsContext
  ) -> String {
    let phaseDetail: String = switch context {
    case .dictation:
      dictationDetail(for: phase)
    case .cleanup(let fallbackLabel):
      cleanupDetail(for: phase, fallbackLabel: fallbackLabel)
    }

    guard let lastError, !lastError.isEmpty, !phaseDetail.contains(lastError) else {
      return phaseDetail
    }
    return "\(phaseDetail) Error: \(lastError)"
  }

  private static func dictationDetail(for phase: AdmittedModelInstallPhase) -> String {
    switch phase {
    case .builtIn:
      "No custom model is installed. On-device recognition uses Apple Speech on this Mac."
    case .notInstalled:
      "The experimental enhanced local model candidate is available to install."
    case .downloading:
      "Downloading the experimental enhanced local model candidate."
    case .verifying:
      "Verifying the downloaded experimental enhanced local model candidate."
    case .installing:
      "Installing the verified experimental enhanced local model candidate."
    case .ready:
      "The experimental enhanced local model candidate is prepared to start."
    case .starting:
      "Starting the experimental enhanced local model candidate."
    case .calibrating:
      "Calibrating the experimental enhanced local model candidate."
    case .installed:
      "The experimental enhanced local model candidate is installed and available."
    case .updateAvailable:
      "An update is available for the experimental enhanced local model candidate."
    case .repairRequired(let message):
      "The experimental enhanced local model candidate needs repair: \(message)"
    case .removing:
      "Removing the experimental enhanced local model candidate and returning to Apple Speech."
    case .cancelled:
      "Experimental enhanced local model candidate installation was cancelled. You can install it again when ready."
    case .failed(let message):
      "Enhanced local dictation failed: \(message) Fleck continues with Apple Speech."
    }
  }

  private static func cleanupDetail(
    for phase: AdmittedModelInstallPhase,
    fallbackLabel: String
  ) -> String {
    let fallback = "Fleck continues with faithful local fallback (\(fallbackLabel))."
    return switch phase {
    case .builtIn:
      "No custom cleanup model is installed. \(fallback)"
    case .notInstalled:
      "The experimental enhanced local cleanup model is available to install."
    case .downloading:
      "Downloading the experimental enhanced local cleanup model."
    case .verifying:
      "Verifying the downloaded experimental enhanced local cleanup model."
    case .installing:
      "Installing the verified experimental enhanced local cleanup model."
    case .ready:
      "The experimental enhanced local cleanup model is prepared to start."
    case .starting:
      "Starting the experimental enhanced local cleanup model."
    case .calibrating:
      "Calibrating the experimental enhanced local cleanup model."
    case .installed:
      "The experimental enhanced local cleanup model is installed and available."
    case .updateAvailable:
      "An update is available for the experimental enhanced local cleanup model."
    case .repairRequired(let message):
      "The experimental enhanced local cleanup model needs repair: \(message). \(fallback)"
    case .removing:
      "Removing the experimental enhanced local cleanup model. \(fallback)"
    case .cancelled:
      "Enhanced local cleanup model installation was cancelled. \(fallback) You can install it again when ready."
    case .failed(let message):
      "Enhanced local cleanup failed: \(message) \(fallback)"
    }
  }

  private static func accessibilityValue(
    for phase: AdmittedModelInstallPhase,
    modelLabel: String,
    lastError: String?,
    context: AdmittedModelSettingsContext
  ) -> String {
    let state: String
    if case .downloading(let receivedBytes, let totalBytes) = phase,
       totalBytes > 0 {
      let progress = progressAccessibilityValue(
        receivedBytes: receivedBytes,
        totalBytes: totalBytes
      )
      state = "Downloading, \(progress)"
    } else if showsDetail(for: phase) {
      state = detail(for: phase, lastError: lastError, context: context)
    } else {
      state = compactStatus(for: phase)
    }
    return "\(modelLabel), \(state)"
  }

  private static func progressAccessibilityValue(
    receivedBytes: Int64,
    totalBytes: Int64
  ) -> String {
    let fraction = min(max(Double(receivedBytes) / Double(totalBytes), 0), 1)
    return "\(Int((fraction * 100).rounded()))%"
  }

  private static func action(
    for phase: AdmittedModelInstallPhase,
    hasDescriptor: Bool
  ) -> AdmittedModelSettingsAction? {
    guard hasDescriptor else { return nil }
    switch phase {
    case .notInstalled, .cancelled:
      return .install
    case .downloading, .verifying, .installing, .starting, .calibrating, .removing:
      return .cancel
    case .ready:
      return .cancel
    case .installed:
      return .remove
    case .updateAvailable:
      return .update
    case .repairRequired, .failed:
      return .repair
    case .builtIn:
      return nil
    }
  }

  private static func label(
    for action: AdmittedModelSettingsAction,
    phase: AdmittedModelInstallPhase
  ) -> String {
    if action == .repair, case .failed = phase {
      return "Retry"
    }
    return action.label
  }
}

private extension AdmittedModelSettingsAction {
  var label: String {
    switch self {
    case .install:
      "Install"
    case .cancel:
      "Cancel"
    case .repair:
      "Repair"
    case .update:
      "Update"
    case .remove:
      "Remove"
    }
  }
}

@MainActor
private final class AdmittedModelSettingsCancellationRelay {
  private let installer: any AdmittedModelInstalling
  private var hasCancelled = false

  init(installer: any AdmittedModelInstalling) {
    self.installer = installer
  }

  func begin() {
    hasCancelled = false
  }

  func reset() {
    hasCancelled = false
  }

  func cancelOnce() {
    guard !hasCancelled else { return }
    hasCancelled = true
    installer.cancel()
  }

  nonisolated func requestCancellation() {
    Task { @MainActor [weak self] in
      self?.cancelOnce()
    }
  }
}

@MainActor
final class AdmittedModelSettingsViewModel: ObservableObject {
  @Published private(set) var presentation: AdmittedModelSettingsPresentation

  private let installer: any AdmittedModelInstalling
  private let context: AdmittedModelSettingsContext
  private let cancellationRelay: AdmittedModelSettingsCancellationRelay
  private var updatesTask: Task<Void, Never>?
  private var actionTask: Task<Void, Never>?

  init(
    installer: any AdmittedModelInstalling,
    context: AdmittedModelSettingsContext = .dictation
  ) {
    self.installer = installer
    self.context = context
    cancellationRelay = AdmittedModelSettingsCancellationRelay(installer: installer)
    presentation = AdmittedModelSettingsPresentation(
      snapshot: installer.snapshot,
      context: context
    )
    subscribeToUpdates()
  }

  func refresh() async {
    await installer.refresh()
  }

  func perform(_ action: AdmittedModelSettingsAction) {
    if action == .cancel {
      cancellationRelay.cancelOnce()
      return
    }

    guard actionTask == nil else { return }
    cancellationRelay.begin()
    let installer = self.installer
    let cancellationRelay = self.cancellationRelay
    actionTask = Task { @MainActor [weak self, installer, cancellationRelay] in
      defer {
        if let self {
          self.actionTask = nil
          self.cancellationRelay.reset()
        }
      }

      await withTaskCancellationHandler(operation: {
        switch action {
        case .install:
          await installer.install()
        case .repair:
          await installer.repair()
        case .update:
          await installer.update()
        case .remove:
          await installer.remove()
        case .cancel:
          installer.cancel()
        }
      }, onCancel: {
        cancellationRelay.requestCancellation()
      })
    }
  }

  private func subscribeToUpdates() {
    let installer = self.installer
    updatesTask = Task { @MainActor [weak self] in
      for await snapshot in installer.updates {
        guard !Task.isCancelled else { return }
        self?.apply(snapshot)
      }
    }
  }

  private func apply(_ snapshot: AdmittedModelInstallationSnapshot) {
    presentation = AdmittedModelSettingsPresentation(snapshot: snapshot, context: context)
  }

  deinit {
    updatesTask?.cancel()
    actionTask?.cancel()
  }
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
struct AdmittedModelSignedConfiguration {
  let rawDescriptor: RawAdmittedModelDescriptor
  let hardware: AdmittedModelHardwareProfile
  let manager: EnhancedModelManager
  let startup: @MainActor () async throws -> Void
  let calibrate: @MainActor () async throws -> Void
}

@MainActor
func makeAdmittedModelInstaller(
  signedConfiguration: AdmittedModelSignedConfiguration? = nil,
  expectedRole: AdmittedModelRole = .asr
) -> any AdmittedModelInstalling {
  guard let signedConfiguration else {
    return BuiltInAdmittedModelInstaller()
  }

  let descriptor: AdmittedModelDescriptor
  do {
    descriptor = try AdmittedModelDescriptor(validating: signedConfiguration.rawDescriptor)
  } catch {
    return FailedAdmittedModelInstaller(
      recommendation: .builtIn,
      message: String(describing: error)
    )
  }

  let catalog = AdmittedModelCatalog(
    signedDescriptor: descriptor,
    hardware: signedConfiguration.hardware,
    expectedRole: expectedRole
  )
  guard case .recommended(let recommended) = catalog.recommendation(),
        recommended == descriptor else {
    return FailedAdmittedModelInstaller(
      recommendation: .builtIn,
      message: "This model is not supported by the current Mac, language, or available staging capacity."
    )
  }

  do {
    try AdmittedModelStorageNamespace.validate(
      managerRootURL: signedConfiguration.manager.modelRootURL,
      selected: signedConfiguration.manager.selectedAdmittedStorageNamespace,
      descriptor: descriptor
    )
  } catch {
    return FailedAdmittedModelInstaller(
      recommendation: .builtIn,
      message: String(describing: error)
    )
  }

  do {
    return try EnhancedModelManagerInstaller(
      manager: signedConfiguration.manager,
      descriptor: descriptor,
      expectedRole: expectedRole,
      startup: signedConfiguration.startup,
      calibrate: signedConfiguration.calibrate
    )
  } catch {
    return FailedAdmittedModelInstaller(
      recommendation: .builtIn,
      message: String(describing: error)
    )
  }
}
#else
@MainActor
func makeAdmittedModelInstaller(
  expectedRole: AdmittedModelRole = .asr
) -> any AdmittedModelInstalling {
  BuiltInAdmittedModelInstaller()
}
#endif
