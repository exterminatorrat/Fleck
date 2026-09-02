import Foundation

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
import Combine
#endif

enum AdmittedModelInstallPhase: Equatable, Sendable {
  case builtIn
  case notInstalled
  case downloading(receivedBytes: Int64, totalBytes: Int64)
  case verifying
  case installing
  case ready
  case starting
  case calibrating
  case installed
  case updateAvailable
  case repairRequired(message: String)
  case removing
  case cancelled
  case failed(message: String)
}

struct AdmittedModelInstallationSnapshot: Equatable, Sendable {
  let recommendation: AdmittedModelRecommendation
  let phase: AdmittedModelInstallPhase
  let lastError: String?
}

@MainActor
protocol AdmittedModelInstalling: AnyObject {
  var snapshot: AdmittedModelInstallationSnapshot { get }
  var updates: AsyncStream<AdmittedModelInstallationSnapshot> { get }
  func refresh() async
  func install() async
  func cancel()
  func repair() async
  func update() async
  func remove() async
}

@MainActor
final class BuiltInAdmittedModelInstaller: AdmittedModelInstalling {
  private(set) var snapshot: AdmittedModelInstallationSnapshot
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>
  private let continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation

  init() {
    var continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation!
    updates = AsyncStream { continuation = $0 }
    self.continuation = continuation
    snapshot = .init(
      recommendation: .builtIn,
      phase: .builtIn,
      lastError: nil
    )
    continuation.yield(snapshot)
  }

  func refresh() async {}
  func install() async {}
  func cancel() {}
  func repair() async {}
  func update() async {}
  func remove() async {}
}

@MainActor
final class FailedAdmittedModelInstaller: AdmittedModelInstalling {
  let recommendation: AdmittedModelRecommendation
  let snapshot: AdmittedModelInstallationSnapshot
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>

  init(
    recommendation: AdmittedModelRecommendation,
    message: String
  ) {
    self.recommendation = recommendation
    let initial = AdmittedModelInstallationSnapshot(
      recommendation: recommendation,
      phase: .failed(message: message),
      lastError: message
    )
    snapshot = initial
    updates = AsyncStream { continuation in continuation.yield(initial) }
  }

  func refresh() async {}
  func install() async {}
  func cancel() {}
  func repair() async {}
  func update() async {}
  func remove() async {}
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
struct EnhancedModelArtifactIdentity: Equatable, Sendable {
  let role: AdmittedModelRole
  let sourceRepository: URL
  let modelID: String
  let revision: String
  let license: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
  let requiredCapacityBytes: Int64

  init(
    role: AdmittedModelRole = .asr,
    sourceRepository: URL,
    modelID: String,
    revision: String,
    license: String,
    runtimeABI: String,
    conversion: String,
    quantization: String,
    files: [AdmittedModelFile],
    downloadBytes: Int64,
    installedBytes: Int64,
    requiredCapacityBytes: Int64
  ) {
    self.role = role
    self.sourceRepository = sourceRepository
    self.modelID = modelID
    self.revision = revision
    self.license = license
    self.runtimeABI = runtimeABI
    self.conversion = conversion
    self.quantization = quantization
    self.files = files
    self.downloadBytes = downloadBytes
    self.installedBytes = installedBytes
    self.requiredCapacityBytes = requiredCapacityBytes
  }

  var immutableIdentity: AdmittedModelImmutableIdentity {
    .init(
      role: role,
      sourceRepository: sourceRepository,
      modelID: modelID,
      revision: revision,
      license: license,
      runtimeABI: runtimeABI,
      conversion: conversion,
      quantization: quantization,
      files: files,
      downloadBytes: downloadBytes,
      installedBytes: installedBytes,
      requiredCapacityBytes: requiredCapacityBytes
    )
  }

  var manifestIdentity: EnhancedModelManifestIdentity {
    .init(
      schemaVersion: 1,
      modelID: modelID,
      revision: revision,
      files: files,
      totalByteCount: downloadBytes
    )
  }
}

struct EnhancedModelManifestIdentity: Equatable, Sendable {
  let schemaVersion: Int
  let modelID: String
  let revision: String
  let files: [AdmittedModelFile]
  let totalByteCount: Int64

  init(
    schemaVersion: Int,
    modelID: String,
    revision: String,
    files: [AdmittedModelFile],
    totalByteCount: Int64
  ) {
    self.schemaVersion = schemaVersion
    self.modelID = modelID
    self.revision = revision
    self.files = files
    self.totalByteCount = totalByteCount
  }

  init(manifest: EnhancedModelManifest) {
    schemaVersion = manifest.schemaVersion
    modelID = manifest.modelID
    revision = manifest.revision
    files = manifest.files.map {
      AdmittedModelFile(
        path: $0.path,
        byteCount: $0.byteCount,
        sha256: $0.sha256
      )
    }
    totalByteCount = manifest.totalByteCount
  }
}

enum AdmittedModelArtifactMismatch: Error, Equatable {
  case descriptorArtifactMismatch
  case artifactManifestMismatch
}

enum AdmittedModelArtifactBinding {
  static func validate(
    descriptor: AdmittedModelDescriptor,
    artifact: EnhancedModelArtifactIdentity,
    manifest: EnhancedModelManifest
  ) throws {
    guard descriptor.immutableIdentity == artifact.immutableIdentity else {
      throw AdmittedModelArtifactMismatch.descriptorArtifactMismatch
    }
    guard artifact.manifestIdentity == EnhancedModelManifestIdentity(
      manifest: manifest
    ) else {
      throw AdmittedModelArtifactMismatch.artifactManifestMismatch
    }
  }
}

@MainActor
final class EnhancedModelManagerInstaller: AdmittedModelInstalling {
  let manager: EnhancedModelManager
  let descriptor: AdmittedModelDescriptor
  private let startup: @MainActor () async throws -> Void
  private let calibrate: @MainActor () async throws -> Void
  private(set) var snapshot: AdmittedModelInstallationSnapshot
  private(set) var phaseHistory: [AdmittedModelInstallPhase] = []
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>
  private let continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation
  private var progressSubscription: AnyCancellable?
  private var stateSubscription: AnyCancellable?
  private var healthSubscription: AnyCancellable?
  private var operationTask: Task<Void, Never>?
  private var operationID: UUID?
  private var lastReceivedBytes: Int64 = 0
  private var managerReady = false
  private var cancellationRequested = false

  init(
    manager: EnhancedModelManager,
    descriptor: AdmittedModelDescriptor,
    expectedRole: AdmittedModelRole = .asr,
    startup: @escaping @MainActor () async throws -> Void,
    calibrate: @escaping @MainActor () async throws -> Void
  ) throws {
    guard descriptor.role == expectedRole,
          manager.admittedArtifactIdentity.role == expectedRole else {
      throw AdmittedModelArtifactMismatch.descriptorArtifactMismatch
    }
    try AdmittedModelArtifactBinding.validate(
      descriptor: descriptor,
      artifact: manager.admittedArtifactIdentity,
      manifest: manager.admittedManifest
    )
    try AdmittedModelStorageNamespace.validate(
      managerRootURL: manager.modelRootURL,
      selected: manager.selectedAdmittedStorageNamespace,
      descriptor: descriptor
    )
    var continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation!
    updates = AsyncStream { continuation = $0 }
    self.continuation = continuation
    self.manager = manager
    self.descriptor = descriptor
    self.startup = startup
    self.calibrate = calibrate
    self.snapshot = .init(
      recommendation: .recommended(descriptor),
      phase: .notInstalled,
      lastError: nil
    )
    continuation.yield(snapshot)
    healthSubscription = manager.$state
      .dropFirst()
      .sink { [weak self] state in
        guard case .repairRequired = state,
              self?.operationID == nil else { return }
        self?.publishManagerState(state, allowOutsideOperation: true)
      }
  }

  private func publish(_ next: AdmittedModelInstallationSnapshot) {
    snapshot = next
    phaseHistory.append(next.phase)
    continuation.yield(next)
  }

  private func beginOperationSubscriptions() {
    operationID = UUID()
    managerReady = false
    cancellationRequested = false
    lastReceivedBytes = 0
    progressSubscription = manager.$byteProgress
      .compactMap { $0 }
      .sink { [weak self] progress in
        guard let self,
              self.operationID != nil, !self.cancellationRequested,
              progress.totalBytes == self.descriptor.downloadBytes,
              progress.receivedBytes >= 0,
              progress.receivedBytes <= progress.totalBytes,
              progress.receivedBytes > self.lastReceivedBytes else { return }
        self.lastReceivedBytes = progress.receivedBytes
        self.publish(.init(
          recommendation: .recommended(self.descriptor),
          phase: .downloading(
            receivedBytes: progress.receivedBytes,
            totalBytes: progress.totalBytes
          ),
          lastError: nil
        ))
      }
    stateSubscription = manager.$state
      .sink { [weak self] state in
        self?.publishManagerState(state)
      }
  }

  private func publishManagerState(
    _ state: EnhancedModelState,
    allowOutsideOperation: Bool = false
  ) {
    guard allowOutsideOperation
      || (operationID != nil && !cancellationRequested) else { return }
    switch state {
    case .notInstalled:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .notInstalled,
        lastError: nil
      ))
    case .downloading(_):
      break // byteProgress is the authoritative live download phase.
    case .verifying:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .verifying,
        lastError: nil
      ))
    case .installing:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .installing,
        lastError: nil
      ))
    case .ready:
      managerReady = true
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .ready,
        lastError: nil
      ))
    case .updateAvailable:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .updateAvailable,
        lastError: nil
      ))
    case .repairRequired(let message):
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .repairRequired(message: message),
        lastError: message
      ))
    case .removing:
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .removing,
        lastError: nil
      ))
    }
  }

  private func endOperation() {
    operationID = nil
    progressSubscription?.cancel()
    progressSubscription = nil
    stateSubscription?.cancel()
    stateSubscription = nil
  }

  private func checkCancellation() -> Bool {
    guard !Task.isCancelled, !cancellationRequested else {
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .cancelled,
        lastError: "Model operation cancelled."
      ))
      return false
    }
    return true
  }

  private func runStartupAndCalibration() async throws -> Bool {
    guard checkCancellation() else { return false }
    publish(.init(
      recommendation: .recommended(descriptor),
      phase: .starting,
      lastError: nil
    ))
    try await startup()
    guard checkCancellation() else { return false }
    publish(.init(
      recommendation: .recommended(descriptor),
      phase: .calibrating,
      lastError: nil
    ))
    try await calibrate()
    guard checkCancellation() else { return false }
    publish(.init(
      recommendation: .recommended(descriptor),
      phase: .installed,
      lastError: nil
    ))
    return true
  }

  private func runManagerOperation(
    initialPhase: AdmittedModelInstallPhase,
    runsStartupAndCalibration: Bool,
    requiresTransferCapacityPreflight: Bool,
    _ operation: @escaping @MainActor () async throws -> Void
  ) async {
    guard operationTask == nil else {
      publish(.init(
        recommendation: .recommended(descriptor),
        phase: .failed(message: "Another model operation is already running."),
        lastError: "Another model operation is already running."
      ))
      return
    }
    if requiresTransferCapacityPreflight {
      do {
        try manager.preflightTransferCapacity()
      } catch {
        publish(.init(
          recommendation: .recommended(descriptor),
          phase: .failed(message: error.localizedDescription),
          lastError: error.localizedDescription
        ))
        return
      }
    }
    beginOperationSubscriptions()
    publish(.init(
      recommendation: .recommended(descriptor),
      phase: initialPhase,
      lastError: nil
    ))
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.endOperation() }
      do {
        try await operation()
        guard !Task.isCancelled, !self.cancellationRequested else {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .cancelled,
            lastError: "Model operation cancelled."
          ))
          return
        }
        guard !runsStartupAndCalibration || self.managerReady || self.manager.state == .ready else {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .failed(message: "The model did not reach ready state."),
            lastError: "The model did not reach ready state."
          ))
          return
        }
        guard runsStartupAndCalibration else { return }
        _ = try await self.runStartupAndCalibration()
      } catch is CancellationError {
        self.publish(.init(
          recommendation: .recommended(self.descriptor),
          phase: .cancelled,
          lastError: "Model operation cancelled."
        ))
      } catch {
        if self.cancellationRequested || Task.isCancelled {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .cancelled,
            lastError: "Model operation cancelled."
          ))
        } else if case .repairRequired(let message) = self.manager.state {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .repairRequired(message: message),
            lastError: message
          ))
        } else {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .failed(message: String(describing: error)),
            lastError: String(describing: error)
          ))
        }
      }
    }
    operationTask = task
    await task.value
    operationTask = nil
  }

  func install() async {
    await runManagerOperation(
      initialPhase: .downloading(
        receivedBytes: 0,
        totalBytes: descriptor.downloadBytes
      ),
      runsStartupAndCalibration: true,
      requiresTransferCapacityPreflight: true
    ) { try await self.manager.download() }
  }

  func repair() async {
    await runManagerOperation(
      initialPhase: .downloading(
        receivedBytes: 0,
        totalBytes: descriptor.downloadBytes
      ),
      runsStartupAndCalibration: true,
      requiresTransferCapacityPreflight: true
    ) { try await self.manager.repair() }
  }

  func update() async {
    await runManagerOperation(
      initialPhase: .downloading(
        receivedBytes: 0,
        totalBytes: descriptor.downloadBytes
      ),
      runsStartupAndCalibration: true,
      requiresTransferCapacityPreflight: true
    ) { try await self.manager.update() }
  }

  func refresh() async {
    guard operationTask == nil else { return }
    beginOperationSubscriptions()
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.endOperation() }
      await self.manager.refreshState()
      guard self.checkCancellation() else { return }
      guard self.manager.state == .ready else { return }
      do {
        _ = try await self.runStartupAndCalibration()
      } catch is CancellationError {
        _ = self.checkCancellation()
      } catch {
        if self.cancellationRequested || Task.isCancelled {
          _ = self.checkCancellation()
        } else if case .repairRequired(let message) = self.manager.state {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .repairRequired(message: message),
            lastError: message
          ))
        } else {
          self.publish(.init(
            recommendation: .recommended(self.descriptor),
            phase: .failed(message: String(describing: error)),
            lastError: String(describing: error)
          ))
        }
      }
    }
    operationTask = task
    await task.value
    operationTask = nil
  }

  func cancel() {
    guard let operationTask else { return }
    cancellationRequested = true
    operationTask.cancel()
  }

  func remove() async {
    await runManagerOperation(
      initialPhase: .removing,
      runsStartupAndCalibration: false,
      requiresTransferCapacityPreflight: false
    ) { try await self.manager.deleteModel() }
  }
}
#endif
