import CryptoKit
import Foundation

enum LocalModelFamily: String, Equatable, Sendable {
  case appleSpeech
  case parakeetTDT
  case gemma3
  case lexicon
  case rules
}

enum LocalModelCatalogRole: String, Equatable, Sendable {
  case dictation
  case vocabulary
  case cleanup
  case routing
  case deterministic
  case system
}

enum LocalModelDistribution: String, Equatable, Sendable {
  case system
  case fleckManaged
  case deterministic
}

enum LocalModelHardwareArchitecture: String, Equatable, Sendable {
  case arm64
  case x86_64
}

enum LocalModelLicenseState: String, Equatable, Sendable {
  case system
  case fleckOwned
  case ccBy40Reviewed
  case gemmaTermsReviewed
}

enum LocalModelEvidenceTier: String, Equatable, Sendable {
  case platform
  case deterministic
  case documented
  case identityVerified
  case labCompatible
  case fleckQualified
  case twoDeviceAccepted
  case signedDistributionAccepted
  case releaseAdmitted
}

enum LocalModelAdmissionState: String, Equatable, Sendable {
  case notAdmitted
  case twoDeviceAccepted
  case signedDistributionAccepted
  case releaseAdmitted
}

enum LocalModelClaimScope: String, Equatable, Sendable {
  case general
  case ownerPrivate
}

enum LocalModelSpeakerCohort: String, Equatable, Sendable {
  case generalAdult
  case owner
}

enum LocalModelAcousticCohort: String, Equatable, Sendable {
  case general
  case quiet
}

enum LocalModelBuildCapability: String, Equatable, Sendable {
  case ordinarySafe
  case developmentQuality
  case signedDistributionCandidate
}

struct RawLocalModelArtifactFile: Equatable, Sendable {
  let path: String
  let byteCount: Int64
  let sha256: String
}

struct RawLocalModelArtifactIdentity: Equatable, Sendable {
  let sourceRepository: URL
  let artifactURL: URL?
  let modelID: String
  let revision: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let requiredPaths: [String]
  let files: [RawLocalModelArtifactFile]
  let downloadBytes: Int64
  let installedBytes: Int64
}

struct RawLocalModelCompatibility: Equatable, Sendable {
  let configurationABI: String
  let architectures: [String]
  let minimumOSMajor: Int
  let maximumOSMajor: Int
  let languages: [String]
}

struct LocalModelResourceEnvelope: Equatable, Sendable {
  let minimumRAMBytes: Int64
  let workingRAMBytes: Int64
  let storageBytes: Int64
}

struct RawLocalModelProfile: Equatable, Sendable {
  let family: String
  let profileID: String
  let role: String
  let distribution: String
  let artifact: RawLocalModelArtifactIdentity?
  let compatibility: RawLocalModelCompatibility
  let resources: LocalModelResourceEnvelope
  let license: String
  let evidence: String
  let admission: String
  let claimScope: String
  let speakerCohort: String
  let acousticCohort: String
  let buildCapability: String
}

struct RawLocalModelConfiguration: Equatable, Sendable {
  let key: String
  let requiredRoles: [String]
  let profiles: [RawLocalModelProfile]
}

struct LocalModelBuildEnvironment: Equatable, Sendable {
  let architecture: LocalModelHardwareArchitecture
  let osMajor: Int
  let languages: Set<String>
  let buildCapability: LocalModelBuildCapability
}

struct LocalModelArtifactFile: Equatable, Sendable {
  let path: String
  let byteCount: Int64
  let sha256: String
}

struct LocalModelArtifactIdentity: Equatable, Sendable {
  let sourceRepository: URL
  let modelID: String
  let revision: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let files: [LocalModelArtifactFile]
  let downloadBytes: Int64
  let installedBytes: Int64
  let requiredCapacityBytes: Int64
}

struct LocalModelCompatibility: Equatable, Sendable {
  let configurationABI: String
  let architectures: Set<LocalModelHardwareArchitecture>
  let minimumOSMajor: Int
  let maximumOSMajor: Int
  let languages: Set<String>
}

struct LocalModelProfile: Equatable, Sendable {
  let family: LocalModelFamily
  let profileID: String
  let role: LocalModelCatalogRole
  let distribution: LocalModelDistribution
  let artifact: LocalModelArtifactIdentity?
  let compatibility: LocalModelCompatibility
  let resources: LocalModelResourceEnvelope
  let license: LocalModelLicenseState
  let evidence: LocalModelEvidenceTier
  let admission: LocalModelAdmissionState
  let claimScope: LocalModelClaimScope
  let speakerCohort: LocalModelSpeakerCohort
  let acousticCohort: LocalModelAcousticCohort
  let buildCapability: LocalModelBuildCapability
}

struct LocalModelConfiguration: Equatable, Sendable {
  let key: String
  let digest: String
  let profiles: [LocalModelProfile]
}

enum LocalModelCatalogError: Error, Equatable, Sendable {
  case invalidValue(field: String, value: String)
  case invalidConfigurationKey
  case mutableRevision(String)
  case artifactURLNotAllowed(URL)
  case invalidSourceRepository
  case unsafeArtifactPath(String)
  case artifactPathCollision(String)
  case artifactSetMismatch
  case invalidArtifactIdentity
  case invalidByteCount
  case byteCountOverflow
  case artifactByteCountMismatch
  case managedArtifactRequired
  case unmanagedArtifact
  case unmanagedThirdPartyLicense
  case duplicateRole(LocalModelCatalogRole)
  case missingMandatoryRole(LocalModelCatalogRole)
  case incompatibleConfigurationABI
  case incompatibleHardware
  case incompatibleOS
  case incompatibleLanguage
  case incompatibleBuildCapability
  case evidenceAdmissionMismatch
  case claimScopeMismatch
  case speakerCohortMismatch
  case acousticCohortMismatch
  case ownerPrivateEvidenceForbidden
}

enum LocalModelCatalog {
  static func validate(
    _ raw: RawLocalModelConfiguration,
    for environment: LocalModelBuildEnvironment
  ) throws -> LocalModelConfiguration {
    guard isConfigurationKey(raw.key) else {
      throw LocalModelCatalogError.invalidConfigurationKey
    }

    let requiredRoles = try Set(raw.requiredRoles.map {
      try parse(LocalModelCatalogRole.self, $0, field: "requiredRole")
    })
    let mandatoryRoles: Set<LocalModelCatalogRole> = [.dictation, .cleanup]
    for role in mandatoryRoles where !requiredRoles.contains(role) {
      throw LocalModelCatalogError.missingMandatoryRole(role)
    }

    var profiles: [LocalModelProfile] = []
    for rawProfile in raw.profiles {
      profiles.append(try validateProfile(rawProfile, for: environment))
    }

    var roles = Set<LocalModelCatalogRole>()
    for profile in profiles {
      guard roles.insert(profile.role).inserted else {
        throw LocalModelCatalogError.duplicateRole(profile.role)
      }
    }
    for role in requiredRoles where !roles.contains(role) {
      throw LocalModelCatalogError.missingMandatoryRole(role)
    }

    guard Set(profiles.map(\.compatibility.configurationABI)).count == 1 else {
      throw LocalModelCatalogError.incompatibleConfigurationABI
    }
    guard Set(profiles.map(\.claimScope)).count == 1 else {
      throw LocalModelCatalogError.claimScopeMismatch
    }
    guard Set(profiles.map(\.speakerCohort)).count == 1 else {
      throw LocalModelCatalogError.speakerCohortMismatch
    }
    guard Set(profiles.map(\.acousticCohort)).count == 1 else {
      throw LocalModelCatalogError.acousticCohortMismatch
    }
    guard Set(profiles.map(\.buildCapability)).count == 1 else {
      throw LocalModelCatalogError.incompatibleBuildCapability
    }

    profiles.sort { $0.role.rawValue < $1.role.rawValue }
    let digest = try canonicalDigest(
      key: raw.key,
      requiredRoles: requiredRoles,
      profiles: profiles
    )
    return .init(key: raw.key, digest: digest, profiles: profiles)
  }

  private static func validateProfile(
    _ raw: RawLocalModelProfile,
    for environment: LocalModelBuildEnvironment
  ) throws -> LocalModelProfile {
    let family = try parse(LocalModelFamily.self, raw.family, field: "family")
    let role = try parse(LocalModelCatalogRole.self, raw.role, field: "role")
    let distribution = try parse(
      LocalModelDistribution.self,
      raw.distribution,
      field: "distribution"
    )
    let license = try parse(LocalModelLicenseState.self, raw.license, field: "license")
    let evidence = try parse(LocalModelEvidenceTier.self, raw.evidence, field: "evidence")
    let admission = try parse(
      LocalModelAdmissionState.self,
      raw.admission,
      field: "admission"
    )
    let claimScope = try parse(
      LocalModelClaimScope.self,
      raw.claimScope,
      field: "claimScope"
    )
    let speakerCohort = try parse(
      LocalModelSpeakerCohort.self,
      raw.speakerCohort,
      field: "speakerCohort"
    )
    let acousticCohort = try parse(
      LocalModelAcousticCohort.self,
      raw.acousticCohort,
      field: "acousticCohort"
    )
    let buildCapability = try parse(
      LocalModelBuildCapability.self,
      raw.buildCapability,
      field: "buildCapability"
    )

    guard !raw.profileID.isEmpty,
          raw.profileID == raw.profileID.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.compatibility.configurationABI.isEmpty,
          raw.compatibility.configurationABI
            == raw.compatibility.configurationABI.trimmingCharacters(in: .whitespacesAndNewlines) else {
      throw LocalModelCatalogError.invalidValue(field: "profileIdentity", value: raw.profileID)
    }
    guard raw.resources.minimumRAMBytes > 0,
          raw.resources.workingRAMBytes >= raw.resources.minimumRAMBytes,
          raw.resources.storageBytes >= 0 else {
      throw LocalModelCatalogError.invalidByteCount
    }

    let artifact: LocalModelArtifactIdentity?
    switch distribution {
    case .fleckManaged:
      guard let rawArtifact = raw.artifact else {
        throw LocalModelCatalogError.managedArtifactRequired
      }
      guard license == .ccBy40Reviewed
              || license == .gemmaTermsReviewed
              || license == .fleckOwned else {
        throw LocalModelCatalogError.unmanagedThirdPartyLicense
      }
      artifact = try validateArtifact(rawArtifact)
    case .system:
      guard raw.artifact == nil else {
        throw LocalModelCatalogError.unmanagedArtifact
      }
      guard license == .system else {
        throw LocalModelCatalogError.unmanagedThirdPartyLicense
      }
      artifact = nil
    case .deterministic:
      guard raw.artifact == nil else {
        throw LocalModelCatalogError.unmanagedArtifact
      }
      guard license == .fleckOwned else {
        throw LocalModelCatalogError.unmanagedThirdPartyLicense
      }
      artifact = nil
    }

    if claimScope == .ownerPrivate && buildCapability == .ordinarySafe {
      throw LocalModelCatalogError.ownerPrivateEvidenceForbidden
    }
    guard evidenceMatchesState(
      evidence: evidence,
      admission: admission,
      distribution: distribution,
      buildCapability: buildCapability,
      claimScope: claimScope
    ) else {
      throw LocalModelCatalogError.evidenceAdmissionMismatch
    }

    let architectures = try Set(raw.compatibility.architectures.map {
      try parse(LocalModelHardwareArchitecture.self, $0, field: "architecture")
    })
    let languages = Set(raw.compatibility.languages)
    guard !architectures.isEmpty,
          raw.compatibility.minimumOSMajor > 0,
          raw.compatibility.maximumOSMajor >= raw.compatibility.minimumOSMajor,
          !languages.isEmpty,
          languages.allSatisfy({
            !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
          }) else {
      throw LocalModelCatalogError.invalidValue(field: "compatibility", value: raw.profileID)
    }
    guard architectures == [.arm64], environment.architecture == .arm64 else {
      throw LocalModelCatalogError.incompatibleHardware
    }
    guard (raw.compatibility.minimumOSMajor...raw.compatibility.maximumOSMajor)
      .contains(environment.osMajor) else {
      throw LocalModelCatalogError.incompatibleOS
    }
    guard environment.languages.isSubset(of: languages) else {
      throw LocalModelCatalogError.incompatibleLanguage
    }
    guard buildCapability == environment.buildCapability else {
      throw LocalModelCatalogError.incompatibleBuildCapability
    }

    return .init(
      family: family,
      profileID: raw.profileID,
      role: role,
      distribution: distribution,
      artifact: artifact,
      compatibility: .init(
        configurationABI: raw.compatibility.configurationABI,
        architectures: architectures,
        minimumOSMajor: raw.compatibility.minimumOSMajor,
        maximumOSMajor: raw.compatibility.maximumOSMajor,
        languages: languages
      ),
      resources: raw.resources,
      license: license,
      evidence: evidence,
      admission: admission,
      claimScope: claimScope,
      speakerCohort: speakerCohort,
      acousticCohort: acousticCohort,
      buildCapability: buildCapability
    )
  }

  private static func validateArtifact(
    _ raw: RawLocalModelArtifactIdentity
  ) throws -> LocalModelArtifactIdentity {
    if let artifactURL = raw.artifactURL {
      throw LocalModelCatalogError.artifactURLNotAllowed(artifactURL)
    }
    guard raw.revision.count == 40,
          raw.revision.allSatisfy({ "0123456789abcdef".contains($0) }) else {
      throw LocalModelCatalogError.mutableRevision(raw.revision)
    }
    guard validRepository(raw.sourceRepository) else {
      throw LocalModelCatalogError.invalidSourceRepository
    }
    guard !raw.modelID.isEmpty,
          !raw.runtimeABI.isEmpty,
          !raw.conversion.isEmpty,
          !raw.quantization.isEmpty,
          !raw.files.isEmpty else {
      throw LocalModelCatalogError.invalidArtifactIdentity
    }
    guard raw.downloadBytes > 0, raw.installedBytes >= raw.downloadBytes else {
      throw LocalModelCatalogError.invalidByteCount
    }

    let requiredPaths = try canonicalPaths(raw.requiredPaths)
    let filePaths = try canonicalPaths(raw.files.map(\.path))
    guard Set(requiredPaths) == Set(filePaths) else {
      throw LocalModelCatalogError.artifactSetMismatch
    }

    var aggregate: Int64 = 0
    var files: [LocalModelArtifactFile] = []
    for (rawFile, path) in zip(raw.files, filePaths) {
      guard rawFile.byteCount > 0 else {
        throw LocalModelCatalogError.invalidByteCount
      }
      let (next, overflow) = aggregate.addingReportingOverflow(rawFile.byteCount)
      guard !overflow else {
        throw LocalModelCatalogError.byteCountOverflow
      }
      aggregate = next
      guard rawFile.sha256.count == 64,
            rawFile.sha256.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else {
        throw LocalModelCatalogError.invalidArtifactIdentity
      }
      files.append(.init(
        path: path,
        byteCount: rawFile.byteCount,
        sha256: rawFile.sha256.lowercased()
      ))
    }
    guard aggregate == raw.downloadBytes else {
      throw LocalModelCatalogError.artifactByteCountMismatch
    }
    let (requiredCapacityBytes, overflow) = raw.downloadBytes
      .addingReportingOverflow(raw.installedBytes)
    guard !overflow else {
      throw LocalModelCatalogError.byteCountOverflow
    }

    files.sort { $0.path < $1.path }
    return .init(
      sourceRepository: raw.sourceRepository,
      modelID: raw.modelID,
      revision: raw.revision,
      runtimeABI: raw.runtimeABI,
      conversion: raw.conversion,
      quantization: raw.quantization,
      files: files,
      downloadBytes: raw.downloadBytes,
      installedBytes: raw.installedBytes,
      requiredCapacityBytes: requiredCapacityBytes
    )
  }

  private static func canonicalPaths(_ paths: [String]) throws -> [String] {
    var seen = Set<String>()
    return try paths.map { rawPath in
      let path: String
      do {
        path = try AdmittedModelPathRules.canonicalize(rawPath)
      } catch {
        throw LocalModelCatalogError.unsafeArtifactPath(rawPath)
      }
      let collisionKey = path.lowercased()
      guard seen.insert(collisionKey).inserted else {
        throw LocalModelCatalogError.artifactPathCollision(collisionKey)
      }
      return path
    }
  }

  private static func validRepository(_ url: URL) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          url.baseURL == nil,
          components.scheme?.lowercased() == "https",
          components.host?.isEmpty == false,
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil,
          !components.path.isEmpty else {
      return false
    }
    var path = components.percentEncodedPath
    for _ in 0..<3 {
      guard let decoded = path.removingPercentEncoding else { return false }
      if decoded == path { break }
      path = decoded
    }
    return !path.contains("%")
      && !path.split(separator: "/").contains("..")
  }

  private static func evidenceMatchesState(
    evidence: LocalModelEvidenceTier,
    admission: LocalModelAdmissionState,
    distribution: LocalModelDistribution,
    buildCapability: LocalModelBuildCapability,
    claimScope: LocalModelClaimScope
  ) -> Bool {
    switch (evidence, admission, distribution, buildCapability, claimScope) {
    case (.platform, .notAdmitted, .system, .ordinarySafe, .general),
         (.platform, .notAdmitted, .system, .developmentQuality, .general),
         (.platform, .notAdmitted, .system, .developmentQuality, .ownerPrivate),
         (.platform, .notAdmitted, .system, .signedDistributionCandidate, .general),
         (.platform, .notAdmitted, .system, .signedDistributionCandidate, .ownerPrivate),
         (.deterministic, .notAdmitted, .deterministic, .ordinarySafe, .general),
         (.deterministic, .notAdmitted, .deterministic, .developmentQuality, .general),
         (.deterministic, .notAdmitted,
          .deterministic, .developmentQuality, .ownerPrivate),
         (.deterministic, .notAdmitted,
          .deterministic, .signedDistributionCandidate, .general),
         (.deterministic, .notAdmitted,
          .deterministic, .signedDistributionCandidate, .ownerPrivate),
         (.documented, .notAdmitted, .fleckManaged, .developmentQuality, .general),
         (.documented, .notAdmitted, .fleckManaged, .developmentQuality, .ownerPrivate),
         (.identityVerified, .notAdmitted, .fleckManaged, .developmentQuality, .general),
         (.identityVerified, .notAdmitted, .fleckManaged, .developmentQuality, .ownerPrivate),
         (.labCompatible, .notAdmitted, .fleckManaged, .developmentQuality, .general),
         (.labCompatible, .notAdmitted, .fleckManaged, .developmentQuality, .ownerPrivate),
         (.fleckQualified, .notAdmitted, .fleckManaged, .developmentQuality, .general),
         (.fleckQualified, .notAdmitted, .fleckManaged, .developmentQuality, .ownerPrivate),
         (.twoDeviceAccepted, .twoDeviceAccepted, .fleckManaged, .developmentQuality, .general),
         (.twoDeviceAccepted, .twoDeviceAccepted,
          .fleckManaged, .developmentQuality, .ownerPrivate),
         (.twoDeviceAccepted, .twoDeviceAccepted,
          .fleckManaged, .signedDistributionCandidate, .general),
         (.twoDeviceAccepted, .twoDeviceAccepted,
          .fleckManaged, .signedDistributionCandidate, .ownerPrivate),
         (.signedDistributionAccepted, .signedDistributionAccepted,
          .fleckManaged, .signedDistributionCandidate, .general),
         (.signedDistributionAccepted, .signedDistributionAccepted,
          .fleckManaged, .signedDistributionCandidate, .ownerPrivate),
         (.releaseAdmitted, .releaseAdmitted, .fleckManaged, .ordinarySafe, .general):
      return true
    default:
      return false
    }
  }

  private static func parse<Value: RawRepresentable>(
    _ type: Value.Type,
    _ raw: String,
    field: String
  ) throws -> Value where Value.RawValue == String {
    guard let value = Value(rawValue: raw) else {
      throw LocalModelCatalogError.invalidValue(field: field, value: raw)
    }
    return value
  }

  private static func isConfigurationKey(_ key: String) -> Bool {
    guard let first = key.first,
          first.isASCII,
          first.isLowercase || first.isNumber else {
      return false
    }
    return key.allSatisfy {
      $0.isASCII && ($0.isLowercase || $0.isNumber || ".-_".contains($0))
    }
  }

  private static func canonicalDigest(
    key: String,
    requiredRoles: Set<LocalModelCatalogRole>,
    profiles: [LocalModelProfile]
  ) throws -> String {
    var encoder = LocalModelCanonicalEncoder()
    try encoder.append("fleck.local-model-configuration.v1")
    try encoder.append(key)
    try encoder.append(requiredRoles.map(\.rawValue).sorted())
    try encoder.appendCount(profiles.count)
    for profile in profiles {
      try encoder.append(profile.family.rawValue)
      try encoder.append(profile.profileID)
      try encoder.append(profile.role.rawValue)
      try encoder.append(profile.distribution.rawValue)
      try encoder.append(profile.compatibility.configurationABI)
      try encoder.append(profile.compatibility.architectures.map(\.rawValue).sorted())
      try encoder.append(String(profile.compatibility.minimumOSMajor))
      try encoder.append(String(profile.compatibility.maximumOSMajor))
      try encoder.append(profile.compatibility.languages.sorted())
      try encoder.append(String(profile.resources.minimumRAMBytes))
      try encoder.append(String(profile.resources.workingRAMBytes))
      try encoder.append(String(profile.resources.storageBytes))
      try encoder.append(profile.license.rawValue)
      try encoder.append(profile.claimScope.rawValue)
      try encoder.append(profile.speakerCohort.rawValue)
      try encoder.append(profile.acousticCohort.rawValue)
      try encoder.append(profile.buildCapability.rawValue)
      if let artifact = profile.artifact {
        try encoder.append("artifact")
        try encoder.append(artifact.sourceRepository.absoluteString)
        try encoder.append(artifact.modelID)
        try encoder.append(artifact.revision)
        try encoder.append(artifact.runtimeABI)
        try encoder.append(artifact.conversion)
        try encoder.append(artifact.quantization)
        try encoder.append(String(artifact.downloadBytes))
        try encoder.append(String(artifact.installedBytes))
        try encoder.append(String(artifact.requiredCapacityBytes))
        try encoder.appendCount(artifact.files.count)
        for file in artifact.files {
          try encoder.append(file.path)
          try encoder.append(String(file.byteCount))
          try encoder.append(file.sha256)
        }
      } else {
        try encoder.append("no-artifact")
      }
    }
    return SHA256.hash(data: encoder.data)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

private struct LocalModelCanonicalEncoder {
  private(set) var data = Data()

  mutating func append(_ values: [String]) throws {
    try appendCount(values.count)
    for value in values {
      try append(value)
    }
  }

  mutating func appendCount(_ count: Int) throws {
    guard count >= 0, let exact = UInt64(exactly: count) else {
      throw LocalModelCatalogError.byteCountOverflow
    }
    appendLength(exact)
  }

  mutating func append(_ value: String) throws {
    let bytes = Data(value.utf8)
    guard let length = UInt64(exactly: bytes.count) else {
      throw LocalModelCatalogError.byteCountOverflow
    }
    appendLength(length)
    data.append(bytes)
  }

  private mutating func appendLength(_ length: UInt64) {
    var bigEndian = length.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
  }
}
