import Foundation

struct AdmittedModelFile: Codable, Equatable, Sendable {
  let path: String
  let byteCount: Int64
  let sha256: String
}

enum AdmittedModelRole: Codable, Equatable, Sendable {
  case asr
  case cleanup

  var identityComponent: String {
    switch self {
    case .asr: "asr"
    case .cleanup: "cleanup"
    }
  }
}

struct RawAdmittedModelDescriptor: Codable, Equatable, Sendable {
  let role: AdmittedModelRole
  let modelID: String
  let revision: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let license: String
  let notices: String
  let source: URL
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
  let languages: [String]
  let architectures: [String]
}

struct AdmittedModelDescriptor: Equatable, Sendable {
  let role: AdmittedModelRole
  let modelID: String
  let revision: String
  let runtimeABI: String
  let conversion: String
  let quantization: String
  let license: String
  let notices: String
  let source: URL
  let files: [AdmittedModelFile]
  let downloadBytes: Int64
  let installedBytes: Int64
  let languages: [String]
  let architectures: [String]
  let requiredCapacityBytes: Int64

  private init(
    role: AdmittedModelRole,
    modelID: String,
    revision: String,
    runtimeABI: String,
    conversion: String,
    quantization: String,
    license: String,
    notices: String,
    source: URL,
    files: [AdmittedModelFile],
    downloadBytes: Int64,
    installedBytes: Int64,
    languages: [String],
    architectures: [String],
    requiredCapacityBytes: Int64
  ) {
    self.role = role
    self.modelID = modelID
    self.revision = revision
    self.runtimeABI = runtimeABI
    self.conversion = conversion
    self.quantization = quantization
    self.license = license
    self.notices = notices
    self.source = source
    self.files = files
    self.downloadBytes = downloadBytes
    self.installedBytes = installedBytes
    self.languages = languages
    self.architectures = architectures
    self.requiredCapacityBytes = requiredCapacityBytes
  }

  init(validating raw: RawAdmittedModelDescriptor) throws {
    let modelID = raw.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    let revision = raw.revision.trimmingCharacters(in: .whitespacesAndNewlines)
    let runtimeABI = raw.runtimeABI.trimmingCharacters(in: .whitespacesAndNewlines)
    let conversion = raw.conversion.trimmingCharacters(in: .whitespacesAndNewlines)
    let quantization = raw.quantization.trimmingCharacters(in: .whitespacesAndNewlines)
    let license = raw.license.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !modelID.isEmpty else {
      throw AdmittedModelDescriptorError.emptyIdentity
    }
    guard !revision.isEmpty else {
      throw AdmittedModelDescriptorError.emptyRevision
    }
    guard !runtimeABI.isEmpty else {
      throw AdmittedModelDescriptorError.emptyRuntimeABI
    }
    guard !conversion.isEmpty else {
      throw AdmittedModelDescriptorError.emptyConversion
    }
    guard !quantization.isEmpty else {
      throw AdmittedModelDescriptorError.emptyQuantization
    }
    guard !license.isEmpty else {
      throw AdmittedModelDescriptorError.emptyLicense
    }

    guard let source = URLComponents(
      url: raw.source,
      resolvingAgainstBaseURL: false
    ),
      raw.source.baseURL == nil,
      source.scheme?.lowercased() == "https",
      source.host?.isEmpty == false,
      source.user == nil,
      source.password == nil,
      source.fragment == nil,
      source.query == nil,
      !source.path.isEmpty,
      !source.path.split(separator: "/").contains("..") else {
      throw AdmittedModelDescriptorError.invalidSource
    }

    var canonicalPath = source.percentEncodedPath
    for _ in 0..<3 {
      guard let decodedPath = canonicalPath.removingPercentEncoding else {
        throw AdmittedModelDescriptorError.invalidSource
      }
      if decodedPath == canonicalPath {
        break
      }
      canonicalPath = decodedPath
    }
    guard !canonicalPath.contains("%"),
          !canonicalPath.split(separator: "/").contains("..") else {
      throw AdmittedModelDescriptorError.invalidSource
    }

    guard !raw.languages.isEmpty, !raw.architectures.isEmpty else {
      throw AdmittedModelDescriptorError.emptySupport
    }
    guard raw.downloadBytes > 0,
          raw.installedBytes > 0,
          raw.files.allSatisfy({ $0.byteCount > 0 }) else {
      throw AdmittedModelDescriptorError.invalidByteCount
    }

    let (requiredCapacityBytes, requiredCapacityOverflow) =
      raw.installedBytes.addingReportingOverflow(raw.downloadBytes)
    guard !requiredCapacityOverflow else {
      throw AdmittedModelDescriptorError.requiredCapacityOverflow
    }

    var aggregate: Int64 = 0
    for file in raw.files {
      let (next, overflow) = aggregate.addingReportingOverflow(file.byteCount)
      guard !overflow else {
        throw AdmittedModelDescriptorError.fileAggregateOverflow
      }
      aggregate = next
    }
    guard aggregate == raw.downloadBytes,
          raw.installedBytes >= raw.downloadBytes else {
      throw AdmittedModelDescriptorError.aggregateMismatch
    }

    let normalizedPaths: [String]
    do {
      normalizedPaths = try AdmittedModelPathRules.canonicalizeUnique(
        raw.files.map(\.path)
      )
    } catch AdmittedModelPathError.unsafePath(let path) {
      throw AdmittedModelDescriptorError.unsafePath(path)
    } catch AdmittedModelPathError.duplicatePath(let path) {
      throw AdmittedModelDescriptorError.duplicateFilePath(path)
    }

    var normalizedFiles: [AdmittedModelFile] = []
    for (file, normalizedPath) in zip(raw.files, normalizedPaths) {
      guard file.sha256.count == 64,
            file.sha256.allSatisfy({
              "0123456789abcdefABCDEF".contains($0)
            }) else {
        throw AdmittedModelDescriptorError.invalidChecksum(file.sha256)
      }
      normalizedFiles.append(.init(
        path: normalizedPath,
        byteCount: file.byteCount,
        sha256: file.sha256
      ))
    }

    self.init(
      role: raw.role,
      modelID: modelID,
      revision: revision,
      runtimeABI: runtimeABI,
      conversion: conversion,
      quantization: quantization,
      license: license,
      notices: raw.notices,
      source: raw.source,
      files: normalizedFiles,
      downloadBytes: raw.downloadBytes,
      installedBytes: raw.installedBytes,
      languages: raw.languages,
      architectures: raw.architectures,
      requiredCapacityBytes: requiredCapacityBytes
    )
  }

  var immutableIdentity: AdmittedModelImmutableIdentity {
    .init(
      role: role,
      sourceRepository: source,
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
}

struct AdmittedModelImmutableIdentity: Equatable, Sendable {
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
}

enum AdmittedModelDescriptorError: Error, Equatable, Sendable {
  case emptyIdentity
  case emptyRevision
  case emptyRuntimeABI
  case emptyConversion
  case emptyQuantization
  case emptyLicense
  case invalidSource
  case unsafePath(String)
  case duplicateFilePath(String)
  case invalidByteCount
  case invalidChecksum(String)
  case aggregateMismatch
  case requiredCapacityOverflow
  case fileAggregateOverflow
  case emptySupport
}

enum AdmittedModelPathError: Error, Equatable, Sendable {
  case unsafePath(String)
  case duplicatePath(String)
}

enum AdmittedModelPathRules {
  static func canonicalize(_ rawPath: String) throws -> String {
    guard !rawPath.isEmpty else {
      throw AdmittedModelPathError.unsafePath(rawPath)
    }

    var path = rawPath
    for _ in 0..<3 {
      guard let decoded = path.removingPercentEncoding else {
        throw AdmittedModelPathError.unsafePath(rawPath)
      }
      if decoded == path {
        break
      }
      path = decoded
    }

    guard path == rawPath,
          !path.isEmpty,
          !path.hasPrefix("/"),
          !path.contains("\\"),
          !path.contains("%") else {
      throw AdmittedModelPathError.unsafePath(rawPath)
    }

    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw AdmittedModelPathError.unsafePath(rawPath)
    }
    return components.joined(separator: "/")
  }

  static func canonicalizeUnique(_ rawPaths: [String]) throws -> [String] {
    var seen = Set<String>()
    return try rawPaths.map { rawPath in
      let path = try canonicalize(rawPath)
      guard seen.insert(path).inserted else {
        throw AdmittedModelPathError.duplicatePath(path)
      }
      return path
    }
  }
}

struct AdmittedModelHardwareProfile: Equatable, Sendable {
  let architecture: String
  let requestedLanguages: Set<String>
  let availableBytes: Int64
}

enum AdmittedModelRecommendation: Equatable, Sendable {
  case builtIn
  case recommended(AdmittedModelDescriptor)
}

struct AdmittedModelCatalog: Sendable {
  private let signedDescriptor: AdmittedModelDescriptor?
  private let hardware: AdmittedModelHardwareProfile
  private let expectedRole: AdmittedModelRole

  init(
    signedDescriptor: AdmittedModelDescriptor?,
    hardware: AdmittedModelHardwareProfile,
    expectedRole: AdmittedModelRole = .asr
  ) {
    self.signedDescriptor = signedDescriptor
    self.hardware = hardware
    self.expectedRole = expectedRole
  }

  func recommendation() -> AdmittedModelRecommendation {
    let supportedLanguages = Set(signedDescriptor?.languages ?? [])
    guard let descriptor = signedDescriptor,
          descriptor.role == expectedRole,
          descriptor.architectures.contains(hardware.architecture),
          (hardware.requestedLanguages.isEmpty
            || hardware.requestedLanguages.isSubset(of: supportedLanguages)),
          hardware.availableBytes >= descriptor.requiredCapacityBytes else {
      return .builtIn
    }
    return .recommended(descriptor)
  }
}
