#if canImport(Sparkle)
import Foundation
import Sparkle

@MainActor
final class SparkleUpdateInformationChecker: NSObject, AppUpdateInformationChecking, SPUUpdaterDelegate {
  private let configuration: AppUpdateConfiguration
  private let currentIdentity: AppUpdateCurrentIdentity
  private let userDriver = InformationOnlyUserDriver()
  private lazy var updater = SPUUpdater(
    hostBundle: .main,
    applicationBundle: .main,
    userDriver: userDriver,
    delegate: self
  )
  private var probeIsActive = false
  private var signedAppcastLoaded = false
  private var appcastCandidateAssessments: [AppUpdateCandidateAssessment]?
  private var pendingResult: AppUpdateProbeResult?
  private var completion: (@MainActor (AppUpdateProbeResult) -> Void)?

  init?(configuration: AppUpdateConfiguration, currentIdentity: AppUpdateCurrentIdentity) {
    guard AppUpdateConfiguration(infoDictionary: Bundle.main.infoDictionary) == configuration else {
      return nil
    }
    self.configuration = configuration
    self.currentIdentity = currentIdentity
    super.init()
  }

  var canCheckForUpdates: Bool { !probeIsActive }

  func startInformationCheck(
    completion: @escaping @MainActor (AppUpdateProbeResult) -> Void
  ) {
    guard !probeIsActive else {
      completion(.error)
      return
    }

    probeIsActive = true
    signedAppcastLoaded = false
    appcastCandidateAssessments = nil
    pendingResult = nil
    self.completion = completion

    let updater = self.updater
    guard updater.feedURL == configuration.feedURL,
      !updater.automaticallyChecksForUpdates,
      !updater.automaticallyDownloadsUpdates,
      !updater.sendsSystemProfile
    else {
      finish(.error)
      return
    }

    do {
      try updater.start()
      updater.checkForUpdateInformation()
    } catch {
      let updaterError = error as NSError
      if AppUpdateErrorPolicy.containsSparkleSignatureFailure(
        in: updaterError,
        domain: SUSparkleErrorDomain
      ) {
        finish(.verificationFailure)
      } else if AppUpdateErrorPolicy.containsCancellation(in: updaterError) {
        finish(.cancelled)
      } else {
        finish(.error)
      }
    }
  }

  func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
    guard updater === self.updater,
      probeIsActive,
      updateCheck == .updateInformation
    else { throw NSError(domain: "Fleck.AppUpdateController", code: 1) }
  }

  func allowedChannels(for updater: SPUUpdater) -> Set<String> {
    ["stable"]
  }

  func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
    []
  }

  func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
    false
  }

  func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
    guard updater === self.updater, probeIsActive else { return }
    guard appcast.signingValidationStatus == .succeeded else {
      setPendingResult(.verificationFailure)
      return
    }
    signedAppcastLoaded = true
    let stableItems = appcast.items.compactMap { $0 as? SUAppcastItem }
      .filter { $0.channel == nil || $0.channel == "stable" }
    guard !AppUpdateAppcastPolicy.hasAmbiguousDuplicateItemVersions(
      stableItems.map(\.versionString)
    ) else {
      setPendingResult(.verificationFailure)
      return
    }
    let assessments = stableItems.map {
      AppUpdateCandidatePolicy.assess(metadata(for: $0), against: currentIdentity)
    }
    appcastCandidateAssessments = assessments
    if assessments.contains(.verificationFailure) {
      setPendingResult(.verificationFailure)
    }
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    guard updater === self.updater, probeIsActive else { return }
    guard AppUpdatePendingResultPolicy.allowsUpdateCandidate(after: pendingResult) else { return }
    guard signedAppcastLoaded else {
      setPendingResult(.verificationFailure)
      return
    }

    switch AppUpdateCandidatePolicy.assess(metadata(for: item), against: currentIdentity) {
    case .newer(let information):
      setPendingResult(.updateAvailable(information))
    case .notNewer, .verificationFailure:
      setPendingResult(.verificationFailure)
    case .incompatible:
      setPendingResult(.error)
    }
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
    guard updater === self.updater, probeIsActive else { return }
    guard pendingResult != .verificationFailure else { return }
    let updaterError = error as NSError
    if AppUpdateErrorPolicy.containsSparkleSignatureFailure(
      in: updaterError,
      domain: SUSparkleErrorDomain
    ) {
      setPendingResult(.verificationFailure)
      return
    }
    if AppUpdateErrorPolicy.containsCancellation(in: updaterError) {
      setPendingResult(.cancelled)
      return
    }
    guard signedAppcastLoaded else {
      setPendingResult(.verificationFailure)
      return
    }

    let sparkleError = error as NSError
    guard sparkleError.domain == SUSparkleErrorDomain,
      sparkleError.code == 1001,
      let rawReason = sparkleError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber,
      let reasonValue = Int32(exactly: rawReason.intValue),
      let reason = SPUNoUpdateFoundReason(rawValue: reasonValue)
    else {
      setPendingResult(.error)
      return
    }

    let noUpdateReason: AppUpdateNoUpdateReason
    switch reason {
    case .onLatestVersion:
      noUpdateReason = .latestVersion
    case .onNewerThanLatestVersion:
      noUpdateReason = .newerThanLatestVersion
    case .systemIsTooOld, .systemIsTooNew, .hardwareDoesNotSupportARM64:
      noUpdateReason = .incompatible
    case .unknown:
      noUpdateReason = .unknown
    @unknown default:
      noUpdateReason = .unknown
    }

    let latestItem = sparkleError.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem
    let candidate = latestItem.map {
      AppUpdateCandidatePolicy.assess(metadata(for: $0), against: currentIdentity)
    }
    setPendingResult(
      AppUpdateNoUpdatePolicy.result(
        reason: noUpdateReason,
        candidate: candidate,
        feedCandidates: appcastCandidateAssessments ?? []
      )
    )
  }

  func updater(
    _ updater: SPUUpdater,
    didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
    error: (any Error)?
  ) {
    guard updater === self.updater,
      probeIsActive,
      updateCheck == .updateInformation
    else { return }

    let result: AppUpdateProbeResult
    if pendingResult == .verificationFailure
      || error.map({
        AppUpdateErrorPolicy.containsSparkleSignatureFailure(
          in: $0 as NSError,
          domain: SUSparkleErrorDomain
        )
      }) == true
    {
      result = .verificationFailure
    } else if pendingResult == .error {
      result = .error
    } else if pendingResult == .cancelled
      || error.map({ AppUpdateErrorPolicy.containsCancellation(in: $0 as NSError) }) == true
    {
      result = .cancelled
    } else if let error {
      let sparkleError = error as NSError
      if pendingResult == .current,
        sparkleError.domain == SUSparkleErrorDomain,
        sparkleError.code == 1001
      {
        result = .current
      } else {
        result = .error
      }
    } else {
      result = pendingResult ?? .error
    }
    finish(result)
  }

  private func metadata(for item: SUAppcastItem) -> AppUpdateCandidateMetadata {
    let properties = item.propertiesDictionary
    let enclosure = properties["enclosure"] as? [String: Any]
    return AppUpdateCandidateMetadata(
      productVersion: properties["fleck:productVersion"] as? String ?? "",
      bundleVersion: item.versionString,
      buildID: properties["fleck:buildID"] as? String ?? "",
      bundleIdentifier: properties["fleck:bundleIdentifier"] as? String ?? "",
      buildFlavor: properties["fleck:buildFlavor"] as? String ?? "",
      minimumSystemVersion: item.minimumSystemVersion,
      channel: item.channel,
      fileURL: item.fileURL,
      contentLength: item.contentLength,
      enclosureSignature: enclosure?["sparkle:edSignature"] as? String,
      installationType: item.installationType,
      isDeltaUpdate: item.isDeltaUpdate,
      isInformationOnlyUpdate: item.isInformationOnlyUpdate,
      supportsCurrentOS: item.minimumOperatingSystemVersionIsOK
        && item.maximumOperatingSystemVersionIsOK,
      supportsArm64: item.arm64HardwareRequirementIsOK,
      hardwareRequirements: item.hardwareRequirements,
      feedSignatureValidated: signedAppcastLoaded,
      itemFeedSignatureValidated: item.signingValidationStatus == .succeeded
    )
  }

  private func setPendingResult(_ result: AppUpdateProbeResult) {
    if let pendingResult,
      AppUpdatePendingResultPolicy.keepsExistingFailureOrCancellation(pendingResult, over: result)
    {
      return
    }
    pendingResult = result
  }

  private func finish(_ result: AppUpdateProbeResult) {
    guard probeIsActive else { return }
    probeIsActive = false
    signedAppcastLoaded = false
    appcastCandidateAssessments = nil
    pendingResult = nil
    let completion = self.completion
    self.completion = nil
    completion?(result)
  }
}

@MainActor
private final class InformationOnlyUserDriver: NSObject, SPUUserDriver {
  func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
    SUUpdatePermissionResponse(
      automaticUpdateChecks: false,
      automaticUpdateDownloading: nil,
      sendSystemProfile: false
    )
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    cancellation()
  }

  func showUpdateFound(
    with appcastItem: SUAppcastItem,
    state: SPUUserUpdateState
  ) async -> SPUUserUpdateChoice {
    .skip
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

  func showUpdateNotFoundWithError(_ error: any Error) async {}

  func showUpdaterError(_ error: any Error) async {}

  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    cancellation()
  }

  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

  func showDownloadDidReceiveData(ofLength length: UInt64) {}

  func showDownloadDidStartExtractingUpdate() {}

  func showExtractionReceivedProgress(_ progress: Double) {}

  func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
    .skip
  }

  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {}

  func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {}

  func dismissUpdateInstallation() {}
}
#endif
