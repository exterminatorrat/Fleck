import Combine
import Foundation

enum AdmittedModelSettingsAction: Equatable, Sendable {
  case install
  case cancel
  case repair
  case update
  case remove
}

struct AdmittedModelSettingsPresentation: Equatable {
  let title: String
  let detail: String
  let phase: AdmittedModelInstallPhase
  let identity: String?
  let revision: String?
  let license: String?
  let checksums: [String]
  let supportedArchitectures: [String]
  let supportedLanguages: [String]
  let downloadBytes: Int64?
  let installedBytes: Int64?
  let progress: Double?
  let progressAccessibilityValue: String?
  let accessibilityLabel: String
  let accessibilityValue: String
  let isKeyboardFocusable: Bool
  let primaryAction: AdmittedModelSettingsAction?
  let primaryActionLabel: String?
  let showsModelPicker: Bool

  var allowsEnhancedPreference: Bool {
    identity != nil && phase == .installed
  }

  var activeEngineLabel: String {
    allowsEnhancedPreference ? "Enhanced Local (Parakeet TDT)" : "Apple Speech"
  }

  init(snapshot: AdmittedModelInstallationSnapshot) {
    phase = snapshot.phase

    let descriptor: AdmittedModelDescriptor?
    switch snapshot.recommendation {
    case .builtIn:
      descriptor = nil
    case .recommended(let value):
      descriptor = value
    }

    identity = descriptor?.modelID
    revision = descriptor?.revision
    license = descriptor?.license
    checksums = descriptor?.files.map(\.sha256) ?? []
    supportedArchitectures = descriptor?.architectures ?? []
    supportedLanguages = descriptor?.languages ?? []
    downloadBytes = descriptor?.downloadBytes
    installedBytes = descriptor?.installedBytes

    switch snapshot.phase {
    case .downloading(let receivedBytes, let totalBytes) where totalBytes > 0:
      progress = Double(receivedBytes) / Double(totalBytes)
      progressAccessibilityValue = "\(receivedBytes) of \(totalBytes) bytes"
    default:
      progress = nil
      progressAccessibilityValue = nil
    }

    primaryAction = Self.action(for: snapshot.phase, hasDescriptor: descriptor != nil)
    primaryActionLabel = primaryAction?.label
    isKeyboardFocusable = primaryAction != nil
    showsModelPicker = false
    title = Self.title(for: snapshot.phase)
    detail = Self.detail(
      for: snapshot.phase,
      descriptor: descriptor,
      lastError: snapshot.lastError
    )
    accessibilityLabel = Self.accessibilityLabel(
      for: snapshot.phase,
      hasDescriptor: descriptor != nil
    )
    accessibilityValue = Self.accessibilityValue(
      for: snapshot.phase,
      descriptor: descriptor,
      lastError: snapshot.lastError
    )
  }

  private static func title(for phase: AdmittedModelInstallPhase) -> String {
    switch phase {
    case .builtIn:
      "Apple Speech — Built in"
    case .notInstalled:
      "Enhanced local model available"
    case .downloading:
      "Downloading enhanced local model"
    case .verifying:
      "Verifying enhanced local model"
    case .installing:
      "Installing enhanced local model"
    case .ready:
      "Enhanced local model prepared to start"
    case .starting:
      "Starting enhanced local model"
    case .calibrating:
      "Calibrating enhanced local model"
    case .installed:
      "Enhanced local model installed"
    case .updateAvailable:
      "Enhanced local model update available"
    case .repairRequired:
      "Enhanced local model needs repair"
    case .removing:
      "Removing enhanced local model"
    case .cancelled:
      "Enhanced local model installation cancelled"
    case .failed:
      "Enhanced local model action failed"
    }
  }

  private static func detail(
    for phase: AdmittedModelInstallPhase,
    descriptor: AdmittedModelDescriptor?,
    lastError: String?
  ) -> String {
    let phaseDetail: String
    switch phase {
    case .builtIn:
      phaseDetail = "No custom model is installed. On-device recognition uses Apple Speech on this Mac."
    case .notInstalled:
      phaseDetail = "The experimental enhanced local model candidate is available to install."
    case .downloading(let receivedBytes, let totalBytes):
      phaseDetail = "Downloading \(receivedBytes) of \(totalBytes) bytes for the experimental enhanced local model candidate."
    case .verifying:
      phaseDetail = "Verifying the downloaded experimental enhanced local model candidate."
    case .installing:
      phaseDetail = "Installing the verified experimental enhanced local model candidate."
    case .ready:
      phaseDetail = "The experimental enhanced local model candidate is prepared to start."
    case .starting:
      phaseDetail = "Starting the experimental enhanced local model candidate."
    case .calibrating:
      phaseDetail = "Calibrating the experimental enhanced local model candidate."
    case .installed:
      phaseDetail = "The experimental enhanced local model candidate is installed and available."
    case .updateAvailable:
      phaseDetail = "An update is available for the experimental enhanced local model candidate."
    case .repairRequired(let message):
      phaseDetail = "The experimental enhanced local model candidate needs repair: \(message)"
    case .removing:
      phaseDetail = "Removing the experimental enhanced local model candidate and returning to Apple Speech."
    case .cancelled:
      phaseDetail = "Experimental enhanced local model candidate installation was cancelled. You can install it again when ready."
    case .failed(let message):
      phaseDetail = "The experimental enhanced local model candidate or its configuration action failed: \(message) Fleck continues with Apple Speech. Verify or update the signed configuration, then restart Fleck."
    }

    guard let descriptor else {
      return phaseDetail
    }

    var metadata = [
      "Model: \(descriptor.modelID)",
      "Revision: \(descriptor.revision)",
      "License: \(descriptor.license)",
      "Supported architectures: \(descriptor.architectures.joined(separator: ", "))",
      "Supported languages: \(descriptor.languages.joined(separator: ", "))",
      "Download size: \(descriptor.downloadBytes) bytes",
      "Installed size: \(descriptor.installedBytes) bytes",
      "Checksums: \(descriptor.files.map(\.sha256).joined(separator: ", "))",
      "Experimental candidate for hands-on testing; not a release claim.",
    ]
    if let lastError, !lastError.isEmpty, !phaseDetail.contains(lastError) {
      metadata.append("Error: \(lastError)")
    }
    return ([phaseDetail] + metadata).joined(separator: "\n")
  }

  private static func accessibilityLabel(
    for phase: AdmittedModelInstallPhase,
    hasDescriptor: Bool
  ) -> String {
    switch phase {
    case .downloading, .verifying, .installing, .starting, .calibrating, .removing:
      "Experimental enhanced local model candidate installation"
    default:
      hasDescriptor ? "Experimental enhanced local model candidate" : "Apple Speech"
    }
  }

  private static func accessibilityValue(
    for phase: AdmittedModelInstallPhase,
    descriptor: AdmittedModelDescriptor?,
    lastError: String?
  ) -> String {
    if case .downloading(let receivedBytes, let totalBytes) = phase {
      return "Downloading experimental enhanced local model candidate, \(receivedBytes) of \(totalBytes) bytes"
    }

    var values = [title(for: phase)]
    if let descriptor {
      values.append("Model \(descriptor.modelID)")
      values.append("Revision \(descriptor.revision)")
      values.append("Supported architectures \(descriptor.architectures.joined(separator: ", "))")
      values.append("Supported languages \(descriptor.languages.joined(separator: ", "))")
    }
    if let lastError, !lastError.isEmpty {
      values.append(lastError)
    }
    return values.joined(separator: ". ")
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
    case .ready, .installed:
      return .remove
    case .updateAvailable:
      return .update
    case .repairRequired:
      return .repair
    case .failed:
      return nil
    case .builtIn:
      return nil
    }
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
  private let cancellationRelay: AdmittedModelSettingsCancellationRelay
  private var updatesTask: Task<Void, Never>?
  private var actionTask: Task<Void, Never>?

  init(installer: any AdmittedModelInstalling) {
    self.installer = installer
    cancellationRelay = AdmittedModelSettingsCancellationRelay(installer: installer)
    presentation = AdmittedModelSettingsPresentation(snapshot: installer.snapshot)
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
    presentation = AdmittedModelSettingsPresentation(snapshot: snapshot)
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
  signedConfiguration: AdmittedModelSignedConfiguration? = nil
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
    hardware: signedConfiguration.hardware
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
      recommendation: .recommended(recommended),
      message: String(describing: error)
    )
  }

  do {
    return try EnhancedModelManagerInstaller(
      manager: signedConfiguration.manager,
      descriptor: descriptor,
      startup: signedConfiguration.startup,
      calibrate: signedConfiguration.calibrate
    )
  } catch {
    return FailedAdmittedModelInstaller(
      recommendation: .recommended(recommended),
      message: String(describing: error)
    )
  }
}
#else
@MainActor
func makeAdmittedModelInstaller() -> any AdmittedModelInstalling {
  BuiltInAdmittedModelInstaller()
}
#endif
