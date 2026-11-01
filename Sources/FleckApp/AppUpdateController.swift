import Combine
import CoreFoundation
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

struct AppUpdateInformation: Equatable, Sendable {
  let productVersion: String
  let bundleVersion: String
}

enum AppUpdateProbeResult: Equatable, Sendable {
  case current
  case updateAvailable(AppUpdateInformation)
  case error
  case verificationFailure
  case cancelled
}

enum AppUpdatePendingResultPolicy {
  static func allowsUpdateCandidate(after result: AppUpdateProbeResult?) -> Bool {
    result != .verificationFailure
  }

  static func keepsExistingFailureOrCancellation(
    _ existing: AppUpdateProbeResult,
    over next: AppUpdateProbeResult
  ) -> Bool {
    switch (existing, next) {
    case (.verificationFailure, _), (.error, .current), (.error, .updateAvailable(_)),
      (.cancelled, .current), (.cancelled, .updateAvailable(_)):
      return true
    default:
      return false
    }
  }
}

enum AppUpdateErrorPolicy {
  static func containsSparkleSignatureFailure(in error: NSError, domain: String) -> Bool {
    contains(in: error) { candidate in
      candidate.domain == domain && (candidate.code == 3001 || candidate.code == 3002)
    }
  }

  static func containsCancellation(in error: NSError) -> Bool {
    contains(in: error) { candidate in
      (candidate.domain == NSURLErrorDomain && candidate.code == NSURLErrorCancelled)
        || (candidate.domain == NSCocoaErrorDomain && candidate.code == NSUserCancelledError)
    }
  }

  private static func contains(in error: NSError, matching predicate: (NSError) -> Bool) -> Bool {
    var currentError: NSError? = error
    for _ in 0..<8 {
      guard let candidate = currentError else { return false }
      if predicate(candidate) { return true }
      currentError = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return false
  }
}

enum AppUpdateAppcastPolicy {
  static func hasAmbiguousDuplicateItemVersions(_ versionStrings: [String]) -> Bool {
    Set(versionStrings).count != versionStrings.count
  }
}

enum AppUpdateState: Equatable, Sendable {
  case unavailable(String)
  case idle
  case checking
  case current
  case newVersionAvailable(AppUpdateInformation)
  case error(String)
  case verificationFailure(String)
  case cancelled
}

@MainActor
protocol AppUpdateInformationChecking: AnyObject {
  var canCheckForUpdates: Bool { get }
  func startInformationCheck(
    completion: @escaping @MainActor (AppUpdateProbeResult) -> Void
  )
}

struct AppUpdateConfiguration: Equatable, Sendable {
  let feedURL: URL
  let publicKey: Data

  init?(infoDictionary: [String: Any]?) {
    guard let infoDictionary,
      let rawFeedURL = infoDictionary["SUFeedURL"] as? String,
      let feedURL = Self.validatedFeedURL(rawFeedURL),
      let rawPublicKey = infoDictionary["SUPublicEDKey"] as? String,
      let publicKey = Self.validatedPublicKey(rawPublicKey)
    else { return nil }

    let booleanPolicies: [(key: String, value: Bool)] = [
      ("SURequireSignedFeed", true),
      ("SUVerifyUpdateBeforeExtraction", true),
      ("SUEnableAutomaticChecks", false),
      ("SUAutomaticallyUpdate", false),
      ("SUAllowsAutomaticUpdates", false),
      ("SUEnableSystemProfiling", false),
      ("SUEnableJavaScript", false),
      ("SUShowReleaseNotes", false),
    ]
    guard booleanPolicies.allSatisfy({ policy in
      guard let value = infoDictionary[policy.key] as? NSNumber,
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
      else { return false }
      return value.boolValue == policy.value
    }),
      let expiration = infoDictionary["SUSignedFeedFailureExpirationInterval"] as? NSNumber,
      CFGetTypeID(expiration as CFTypeRef) != CFBooleanGetTypeID(),
      expiration.compare(NSNumber(value: 0)) == .orderedSame,
      infoDictionary["SUPublicDSAKey"] == nil,
      infoDictionary["SUPublicDSAKeyFile"] == nil
    else { return nil }

    self.feedURL = feedURL
    self.publicKey = publicKey
  }

  private static func validatedFeedURL(_ value: String) -> URL? {
    guard let components = URLComponents(string: value),
      components.scheme == "https",
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.port == nil || components.port == 443,
      let host = components.host,
      host == "github.com" || host == "raw.githubusercontent.com"
    else { return nil }

    let path = components.percentEncodedPath
    guard path.hasPrefix("/"),
      !path.contains("%"),
      !path.contains("\\"),
      !path.hasSuffix("/")
    else { return nil }

    let segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
    guard segments.allSatisfy({ segment in
      !segment.isEmpty
        && segment != "."
        && segment != ".."
        && segment.range(of: #"^[A-Za-z0-9._~-]+$"#, options: .regularExpression) != nil
    }),
      segments.count >= (host == "github.com" ? 3 : 4),
      segments[0] == "exterminatorrat",
      segments[1] == "fleck"
    else { return nil }

    return components.url
  }

  private static func validatedPublicKey(_ value: String) -> Data? {
    guard let data = Data(base64Encoded: value),
      data.count == 32,
      data.base64EncodedString() == value
    else { return nil }

    #if canImport(CryptoKit)
    guard (try? Curve25519.Signing.PublicKey(rawRepresentation: data)) != nil else {
      return nil
    }
    #endif

    return data
  }
}

struct AppUpdateCurrentIdentity: Equatable, Sendable {
  let productVersion: AppUpdateSemanticVersion
  let buildNumber: UInt64
  let buildID: UUID
  let bundleIdentifier: String
  let buildFlavor: String

  init?(_ identity: BuildIdentity) {
    guard identity.isPackaged,
      let productVersionString = identity.productVersion,
      let productVersion = AppUpdateSemanticVersion(productVersionString),
      let buildNumberString = identity.buildNumber,
      let buildNumber = UInt64(buildNumberString),
      String(buildNumber) == buildNumberString,
      let bundleVersion = identity.bundleVersion,
      AppUpdateBundleVersion.bundleVersion(for: buildNumber) == bundleVersion,
      let buildIDString = identity.buildID,
      let buildID = Self.validatedUUID(buildIDString),
      let buildDate = identity.buildDate,
      ISO8601DateFormatter().date(from: buildDate) != nil,
      let sourceCommit = identity.sourceCommit,
      Self.matches(sourceCommit, pattern: #"^[0-9a-f]{40}$"#),
      let sourceTree = identity.sourceTree,
      Self.matches(sourceTree, pattern: #"^[0-9a-f]{40}$"#),
      let buildFlavor = identity.flavor,
      Self.matches(buildFlavor, pattern: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#),
      let configuration = identity.configuration,
      !configuration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let candidateStatus = identity.candidateStatus,
      !candidateStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let baselineManifestSHA256 = identity.baselineManifestSHA256,
      Self.matches(baselineManifestSHA256, pattern: #"^[0-9a-f]{64}$"#),
      let baselineRecordID = identity.baselineRecordID,
      !baselineRecordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let baselineRegistryStatus = identity.baselineRegistryStatus,
      !baselineRegistryStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      identity.bundleIdentifier == "com.harryjin.fleck"
    else { return nil }

    self.productVersion = productVersion
    self.buildNumber = buildNumber
    self.buildID = buildID
    self.bundleIdentifier = "com.harryjin.fleck"
    self.buildFlavor = buildFlavor
  }

  private static func validatedUUID(_ value: String) -> UUID? {
    guard matches(
      value,
      pattern: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
    ), let uuid = UUID(uuidString: value) else { return nil }
    return uuid
  }

  fileprivate static func matches(_ value: String, pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }
}

struct AppUpdateSemanticVersion: Equatable, Comparable, Sendable {
  private let major: UInt64
  private let minor: UInt64
  private let patch: UInt64
  private let prerelease: [String]

  var isPrerelease: Bool { !prerelease.isEmpty }

  init?(_ value: String) {
    let pattern = #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"#
    guard AppUpdateCurrentIdentity.matches(value, pattern: pattern) else { return nil }

    let versionParts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let core = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
    guard core.count == 3,
      let major = UInt64(core[0]),
      let minor = UInt64(core[1]),
      let patch = UInt64(core[2])
    else { return nil }

    let prerelease = versionParts.count == 2
      ? versionParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
      : []
    guard !prerelease.contains(where: { identifier in
      identifier.allSatisfy(\.isNumber)
        && identifier.count > 1
        && identifier.first == "0"
    }) else { return nil }

    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
    if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty {
      return !lhs.prerelease.isEmpty
    }

    for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
      let leftIsNumber = left.allSatisfy(\.isNumber)
      let rightIsNumber = right.allSatisfy(\.isNumber)
      switch (leftIsNumber, rightIsNumber) {
      case (true, true):
        return left.count == right.count ? left < right : left.count < right.count
      case (true, false):
        return true
      case (false, true):
        return false
      case (false, false):
        return left < right
      }
    }

    return lhs.prerelease.count < rhs.prerelease.count
  }
}

enum AppUpdateBundleVersion {
  static func bundleVersion(for buildNumber: UInt64) -> String? {
    guard buildNumber > 0 else { return nil }
    let zeroBased = buildNumber - 1
    let first = 1 + zeroBased / 10_000
    guard first <= 9_999 else { return nil }
    let second = (zeroBased / 100) % 100
    let third = zeroBased % 100
    return "\(first).\(second).\(third)"
  }

  static func buildNumber(for value: String) -> UInt64? {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts.allSatisfy({ $0.range(of: #"^(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil }),
      let first = UInt64(parts[0]),
      let second = UInt64(parts[1]),
      let third = UInt64(parts[2]),
      (1...9_999).contains(first),
      second < 100,
      third < 100
    else { return nil }

    let number = (first - 1) * 10_000 + second * 100 + third + 1
    guard bundleVersion(for: number) == value else { return nil }
    return number
  }
}

struct AppUpdateCandidateMetadata: Equatable, Sendable {
  let productVersion: String
  let bundleVersion: String
  let buildID: String
  let bundleIdentifier: String
  let buildFlavor: String
  let minimumSystemVersion: String?
  let channel: String?
  let fileURL: URL?
  let contentLength: UInt64
  let enclosureSignature: String?
  let installationType: String?
  let isDeltaUpdate: Bool
  let isInformationOnlyUpdate: Bool
  let supportsCurrentOS: Bool
  let supportsArm64: Bool
  let hardwareRequirements: Set<String>
  let feedSignatureValidated: Bool
  let itemFeedSignatureValidated: Bool
}

enum AppUpdateCandidateAssessment: Equatable, Sendable {
  case newer(AppUpdateInformation)
  case notNewer
  case incompatible
  case verificationFailure
}

enum AppUpdateNoUpdateReason: Equatable, Sendable {
  case latestVersion
  case newerThanLatestVersion
  case incompatible
  case unknown
}

enum AppUpdateCandidatePolicy {
  static func assess(
    _ candidate: AppUpdateCandidateMetadata,
    against current: AppUpdateCurrentIdentity
  ) -> AppUpdateCandidateAssessment {
    guard candidate.feedSignatureValidated, candidate.itemFeedSignatureValidated else {
      return .verificationFailure
    }

    guard candidate.bundleIdentifier == current.bundleIdentifier,
      candidate.buildFlavor == current.buildFlavor,
      let minimumSystemVersion = candidate.minimumSystemVersion,
      AppUpdateCurrentIdentity.matches(
        minimumSystemVersion,
        pattern: #"^(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*)){0,2}$"#
      ),
      candidate.channel == nil || candidate.channel == "stable",
      let productVersion = AppUpdateSemanticVersion(candidate.productVersion),
      !productVersion.isPrerelease,
      let buildNumber = AppUpdateBundleVersion.buildNumber(for: candidate.bundleVersion),
      let buildID = UUID(uuidString: candidate.buildID),
      let fileURL = candidate.fileURL,
      isCanonicalReleaseAssetURL(fileURL),
      candidate.contentLength > 0,
      hasCanonicalSignature(candidate.enclosureSignature),
      candidate.installationType == "application",
      !candidate.isDeltaUpdate,
      !candidate.isInformationOnlyUpdate
    else { return .verificationFailure }

    guard candidate.supportsCurrentOS,
      candidate.supportsArm64,
      candidate.hardwareRequirements.allSatisfy({ $0 == "arm64" })
    else { return .incompatible }

    let productVersionComparison: ComparisonResult
    if productVersion == current.productVersion {
      productVersionComparison = .orderedSame
    } else if productVersion < current.productVersion {
      productVersionComparison = .orderedAscending
    } else {
      productVersionComparison = .orderedDescending
    }
    let buildNumberComparison: ComparisonResult
    if buildNumber == current.buildNumber {
      buildNumberComparison = .orderedSame
    } else if buildNumber < current.buildNumber {
      buildNumberComparison = .orderedAscending
    } else {
      buildNumberComparison = .orderedDescending
    }

    if buildID == current.buildID,
      productVersionComparison != .orderedSame || buildNumberComparison != .orderedSame
    {
      return .verificationFailure
    }

    switch (productVersionComparison, buildNumberComparison) {
    case (.orderedSame, .orderedSame):
      return buildID == current.buildID ? .notNewer : .verificationFailure
    case (.orderedAscending, .orderedAscending):
      return .notNewer
    case (.orderedDescending, .orderedDescending):
      guard buildID != current.buildID else { return .verificationFailure }
      return .newer(
        AppUpdateInformation(
          productVersion: candidate.productVersion,
          bundleVersion: candidate.bundleVersion
        )
      )
    default:
      return .verificationFailure
    }
  }

  private static func hasCanonicalSignature(_ value: String?) -> Bool {
    guard let value,
      let signature = Data(base64Encoded: value),
      signature.count == 64
    else { return false }
    return signature.base64EncodedString() == value
  }

  private static func isCanonicalReleaseAssetURL(_ url: URL) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme == "https",
      components.host == "github.com",
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.port == nil || components.port == 443,
      url.pathExtension == "zip"
    else { return false }

    let path = components.percentEncodedPath
    guard path.hasPrefix("/"),
      !path.contains("%"),
      !path.contains("\\"),
      !path.hasSuffix("/")
    else { return false }

    let segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
    guard segments.count == 6,
      segments.allSatisfy({ segment in
        !segment.isEmpty
          && segment != "."
          && segment != ".."
          && segment.range(of: #"^[A-Za-z0-9._~-]+$"#, options: .regularExpression) != nil
      })
    else { return false }

    return segments[0] == "exterminatorrat"
      && segments[1] == "fleck"
      && segments[2] == "releases"
      && segments[3] == "download"
  }
}

enum AppUpdateNoUpdatePolicy {
  static func result(
    reason: AppUpdateNoUpdateReason,
    candidate: AppUpdateCandidateAssessment?,
    feedCandidates: [AppUpdateCandidateAssessment]
  ) -> AppUpdateProbeResult {
    guard reason == .latestVersion || reason == .newerThanLatestVersion,
      let candidate
    else { return .error }

    if candidate == .verificationFailure || feedCandidates.contains(.verificationFailure) {
      return .verificationFailure
    }
    guard feedCandidates.contains(.notNewer) else { return .error }

    switch candidate {
    case .notNewer:
      if feedCandidates.contains(where: { assessment in
        if case .newer = assessment { return true }
        return false
      }) {
        return .error
      }
      return .current
    case .verificationFailure:
      return .verificationFailure
    case .newer, .incompatible:
      return .error
    }
  }
}

typealias AppUpdateCheckerFactory = @MainActor (
  AppUpdateConfiguration,
  BuildIdentity
) -> (any AppUpdateInformationChecking)?

@MainActor
final class AppUpdateController: ObservableObject {
  @Published private(set) var state: AppUpdateState

  private let configuration: AppUpdateConfiguration?
  private let currentIdentity: AppUpdateCurrentIdentity?
  private let buildIdentity: BuildIdentity?
  private let checkerFactory: AppUpdateCheckerFactory?
  private var activeChecker: (any AppUpdateInformationChecking)?
  private var activeCheckID: UUID?

  convenience init() {
    let bundle = Bundle.main
    let configuration = AppUpdateConfiguration(infoDictionary: bundle.infoDictionary)
    let identity = BuildIdentity.current(bundle: bundle)
    let currentIdentity = AppUpdateCurrentIdentity(identity)

    #if canImport(Sparkle)
    self.init(
      configuration: configuration,
      currentIdentity: currentIdentity,
      buildIdentity: currentIdentity == nil ? nil : identity,
      checkerFactory: { configuration, currentIdentity in
        guard let validatedIdentity = AppUpdateCurrentIdentity(currentIdentity) else { return nil }
        return SparkleUpdateInformationChecker(
          configuration: configuration,
          currentIdentity: validatedIdentity
        )
      }
    )
    #else
    self.init(
      configuration: configuration,
      currentIdentity: currentIdentity,
      buildIdentity: currentIdentity == nil ? nil : identity,
      checkerFactory: nil
    )
    #endif
  }

  convenience init(
    infoDictionary: [String: Any]?,
    identity: BuildIdentity,
    checkerFactory: @escaping AppUpdateCheckerFactory
  ) {
    let currentIdentity = AppUpdateCurrentIdentity(identity)
    self.init(
      configuration: AppUpdateConfiguration(infoDictionary: infoDictionary),
      currentIdentity: currentIdentity,
      buildIdentity: currentIdentity == nil ? nil : identity,
      checkerFactory: checkerFactory
    )
  }

  private init(
    configuration: AppUpdateConfiguration?,
    currentIdentity: AppUpdateCurrentIdentity?,
    buildIdentity: BuildIdentity?,
    checkerFactory: AppUpdateCheckerFactory?
  ) {
    self.configuration = configuration
    self.currentIdentity = currentIdentity
    self.buildIdentity = buildIdentity
    self.checkerFactory = checkerFactory
    self.state = configuration != nil && currentIdentity != nil && checkerFactory != nil
      ? .idle
      : .unavailable("Update checking is unavailable.")
  }

  var canCheckForUpdates: Bool {
    configuration != nil && currentIdentity != nil && buildIdentity != nil && checkerFactory != nil
      && activeCheckID == nil
  }

  var statusText: String {
    switch state {
    case .unavailable(let message), .error(let message), .verificationFailure(let message):
      return message
    case .idle:
      return "Check for updates."
    case .checking:
      return "Checking for updates…"
    case .current:
      return "No newer compatible release is listed in the signed feed."
    case .newVersionAvailable(let information):
      return "Version \(information.productVersion) is listed in signed update information; "
        + "its artifact, architecture, and extraction have not been verified."
    case .cancelled:
      return "The update check was cancelled."
    }
  }

  func checkForUpdates() {
    guard canCheckForUpdates,
      let configuration,
      let buildIdentity,
      let checkerFactory
    else { return }

    let checkID = UUID()
    activeCheckID = checkID
    state = .checking

    guard let checker = checkerFactory(configuration, buildIdentity) else {
      complete(.error, checkID: checkID)
      return
    }
    guard checker.canCheckForUpdates else {
      complete(.error, checkID: checkID)
      return
    }

    activeChecker = checker
    checker.startInformationCheck { [weak self, weak checker] result in
      guard let self,
        let checker,
        self.activeCheckID == checkID,
        self.activeChecker === checker
      else { return }

      self.complete(result, checkID: checkID)
    }
  }

  private func complete(_ result: AppUpdateProbeResult, checkID: UUID) {
    guard activeCheckID == checkID else { return }
    activeCheckID = nil
    activeChecker = nil

    switch result {
    case .current:
      state = .current
    case .updateAvailable(let information):
      state = .newVersionAvailable(information)
    case .error:
      state = .error("The update check failed.")
    case .verificationFailure:
      state = .verificationFailure("Update information could not be verified.")
    case .cancelled:
      state = .cancelled
    }
  }
}
