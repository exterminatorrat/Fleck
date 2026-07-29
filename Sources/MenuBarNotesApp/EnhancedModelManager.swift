#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
  import Combine
  import CryptoKit
  import Foundation
  import MenuBarNotesCore
  import Security

  enum EnhancedModelState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double)
    case verifying
    case installing
    case ready
    case updateAvailable
    case repairRequired(message: String)
    case removing
  }

  enum EnhancedModelVerifiedLoadState: Equatable, Sendable {
    case unavailable
    case ready(repositoryURL: URL)
  }

  struct EnhancedModelFile: Codable, Equatable, Sendable {
    let path: String
    let byteCount: Int64
    let sha256: String
  }

  struct EnhancedModelManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let modelID: String
    let revision: String
    let totalByteCount: Int64
    let files: [EnhancedModelFile]
  }

  struct ModelResumeToken: Equatable, Sendable {
    let data: Data

    init(issuedData: Data) {
      data = issuedData
    }
  }

  protocol ModelDownloading: Sendable {
    func sessionProducedResumeToken(
      for data: Data,
      remoteURL: URL
    ) -> ModelResumeToken?

    func download(
      from remoteURL: URL,
      resumeToken: ModelResumeToken?,
      progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> ModelDownloadResult
  }

  struct ModelDownloadResult: Sendable {
    let temporaryURL: URL
    let resumeData: Data?
  }

  enum ModelDownloadError: Error, Equatable {
    case cancelled(resumeData: Data?)
    case redirectRejected
    case failed(String)
  }

  enum EnhancedModelManagerError: Error, Equatable, LocalizedError {
    case candidateDisabled
    case unsupportedArchitecture
    case insufficientSpace(required: Int64, available: Int64)
    case invalidManifestPath(String)
    case invalidManifest
    case checksumMismatch(String)
    case wrongByteCount(String)
    case unexpectedFile(String)
    case operationInProgress
    case unsafeFilesystemPath(String)

    var errorDescription: String? {
      switch self {
      case .candidateDisabled:
        return "This speech engine is unavailable in this release."
      case .unsupportedArchitecture:
        return "Enhanced dictation requires Apple silicon."
      case .insufficientSpace(let required, let available):
        return "Insufficient space. \(required) bytes are required; \(available) bytes are available."
      case .invalidManifestPath(let path):
        return "The model manifest contains an unsafe path: \(path)"
      case .invalidManifest:
        return "The model manifest is invalid."
      case .checksumMismatch(let path):
        return "The downloaded model failed checksum verification: \(path)"
      case .wrongByteCount(let path):
        return "The downloaded model has the wrong size: \(path)"
      case .unexpectedFile(let path):
        return "The model contains an unexpected file: \(path)"
      case .operationInProgress:
        return "Another model operation is already in progress."
      case .unsafeFilesystemPath(let path):
        return "The model storage path is unsafe: \(path)"
      }
    }
  }

  @MainActor
  final class EnhancedModelManager: ObservableObject {
    static let requiredAvailableCapacity: Int64 = 1_197_261_950

    @Published private(set) var state: EnhancedModelState = .notInstalled
    private(set) var verifiedRepositoryURL: URL?
    var verifiedLoadState: EnhancedModelVerifiedLoadState {
      guard candidateEnabled else {
        return .unavailable
      }
      guard let verifiedRepositoryURL else {
        return .unavailable
      }
      switch state {
      case .ready, .updateAvailable, .downloading, .verifying, .installing:
        return .ready(repositoryURL: verifiedRepositoryURL)
      case .notInstalled, .repairRequired, .removing:
        return .unavailable
      }
    }
    let isArchitectureSupported: Bool

    private let context: FileContext
    private let manifest: EnhancedModelManifest
    private let trustedManifests: [EnhancedModelManifest]
    private let capacityProvider: @Sendable () throws -> Int64
    private let candidateEnabled: Bool
    private let clock: @Sendable () -> Date
    private let transport: any ModelDownloading
    private let assessmentDidComplete: @Sendable () -> Void
    private let cleanupWillBegin: @Sendable () -> Void
    private let removalWillBegin: @Sendable () -> Void
    private let resumeAuthenticationKeyProvider: @Sendable () throws -> SymmetricKey
    private var stateChangedAt: Date
    private var activeOperationID: UUID?
    private var activeAssessmentCount = 0
    private var pendingInferenceLoadFailure: (message: String, repositoryURL: URL)?
    private var lifecycleEpoch: UInt64 = 0
    private var highestProgress = 0.0

    init(
      modelRootURL: URL? = nil,
      fileManager: FileManager = .default,
      manifest: EnhancedModelManifest? = nil,
      trustedManifests: [EnhancedModelManifest]? = nil,
      candidateEnabled: Bool = CleanDictationFeatures.enhancedLocalCandidateEnabled,
      capacityProvider: @escaping @Sendable () throws -> Int64 = {
        let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
          forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values.volumeAvailableCapacityForImportantUsage ?? 0
      },
      architectureProvider: @escaping @Sendable () -> Bool = {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
          $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine == "arm64"
      },
      clock: @escaping @Sendable () -> Date = { Date() },
      transport: any ModelDownloading = URLSessionModelDownloader(),
      assessmentDidComplete: @escaping @Sendable () -> Void = {},
      cleanupWillBegin: @escaping @Sendable () -> Void = {},
      removalWillBegin: @escaping @Sendable () -> Void = {},
      resumeAuthenticationKeyProvider: @escaping @Sendable () throws -> SymmetricKey = {
        try EnhancedModelManager.loadOrCreateResumeAuthenticationKey()
      }
    ) {
      let root = modelRootURL ?? fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )[0]
      .appendingPathComponent(
        FleckProductPaths.canonicalDirectoryName,
        isDirectory: true
      )
      .appendingPathComponent("DictationModels", isDirectory: true)
      let selectedManifest = manifest ?? Self.embeddedManifest()
      self.context = FileContext(root: root, fileManager: fileManager)
      self.manifest = selectedManifest
      self.trustedManifests = trustedManifests ?? [selectedManifest]
      self.candidateEnabled = candidateEnabled
      self.capacityProvider = capacityProvider
      self.isArchitectureSupported = architectureProvider()
      self.clock = clock
      self.transport = transport
      self.assessmentDidComplete = assessmentDidComplete
      self.cleanupWillBegin = cleanupWillBegin
      self.removalWillBegin = removalWillBegin
      self.resumeAuthenticationKeyProvider = resumeAuthenticationKeyProvider
      stateChangedAt = clock()
    }

    func refreshState() async {
      guard candidateEnabled else {
        verifiedRepositoryURL = nil
        setState(.notInstalled)
        return
      }
      guard activeOperationID == nil else { return }
      activeAssessmentCount += 1
      defer {
        activeAssessmentCount -= 1
        applyPendingInferenceLoadFailureIfCurrent()
      }
      lifecycleEpoch &+= 1
      let epoch = lifecycleEpoch
      guard isArchitectureSupported else {
        guard activeOperationID == nil, lifecycleEpoch == epoch else { return }
        setState(.notInstalled)
        return
      }
      let context = context
      let manifest = manifest
      let trustedManifests = trustedManifests
      let assessmentDidComplete = assessmentDidComplete
      let assessment = await Task.detached {
        let result = Result {
          try Self.assess(
            context: context,
            manifest: manifest,
            trustedManifests: trustedManifests
          )
        }
        assessmentDidComplete()
        return result
      }.value
      guard activeOperationID == nil, lifecycleEpoch == epoch else { return }
      switch assessment {
      case .success(let result):
        verifiedRepositoryURL = result.repositoryURL
        setState(result.state)
      case .failure(let error):
        verifiedRepositoryURL = nil
        setState(.repairRequired(message: error.localizedDescription))
      }
    }

    func download() async throws {
      guard candidateEnabled else {
        throw EnhancedModelManagerError.candidateDisabled
      }
      try await installCurrentModel()
    }

    func repair() async throws {
      guard candidateEnabled else {
        throw EnhancedModelManagerError.candidateDisabled
      }
      try await installCurrentModel()
    }

    func update() async throws {
      guard candidateEnabled else {
        throw EnhancedModelManagerError.candidateDisabled
      }
      try await installCurrentModel()
    }

    func markInferenceLoadFailure(
      message: String,
      failedRepositoryURL: URL
    ) {
      guard verifiedRepositoryURL == failedRepositoryURL else { return }
      if activeOperationID != nil || activeAssessmentCount > 0 {
        pendingInferenceLoadFailure = (message, failedRepositoryURL)
        return
      }
      lifecycleEpoch &+= 1
      verifiedRepositoryURL = nil
      setState(.repairRequired(message: message))
    }

    func deleteModel() async throws {
      guard candidateEnabled else {
        throw EnhancedModelManagerError.candidateDisabled
      }
      guard isArchitectureSupported else {
        setState(.notInstalled)
        return
      }
      let operationID = try beginOperation()
      setState(.removing)
      let context = context
      let removalWillBegin = removalWillBegin
      do {
        try await Task.detached {
          removalWillBegin()
          for url in [
            context.installedRoot,
            context.stagingRoot,
            context.resumeRoot,
            context.derivedRoot,
          ] {
            try Self.removeOwnedTreeIfPresent(url, context: context)
          }
        }.value
        finishOperation(operationID)
        verifiedRepositoryURL = nil
        setState(.notInstalled)
        applyPendingInferenceLoadFailureIfCurrent()
      } catch {
        finishOperation(operationID)
        setState(.repairRequired(message: error.localizedDescription))
        applyPendingInferenceLoadFailureIfCurrent()
        throw error
      }
    }

    nonisolated static func remoteURL(
      for file: EnhancedModelFile,
      manifest: EnhancedModelManifest
    ) throws -> URL {
      try validateRelativePath(file.path)
      try validateRevision(manifest.revision)
      let revisionRoot = URL(
        string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/"
      )!.appendingPathComponent(manifest.revision, isDirectory: true)
      let artifactURL = file.path.split(separator: "/").reduce(revisionRoot) {
        $0.appendingPathComponent(String($1))
      }
      var components = URLComponents(
        url: artifactURL,
        resolvingAgainstBaseURL: false
      )!
      components.queryItems = [URLQueryItem(name: "download", value: "true")]
      return components.url!
    }

    private func installCurrentModel() async throws {
      guard isArchitectureSupported else {
        throw EnhancedModelManagerError.unsupportedArchitecture
      }
      let operationID = try beginOperation()
      let previousRepositoryURL = verifiedRepositoryURL
      let previousState = state
      let context = context
      let manifest = manifest

      do {
        let available = try capacityProvider()
        guard available >= Self.requiredAvailableCapacity else {
          throw EnhancedModelManagerError.insufficientSpace(
            required: Self.requiredAvailableCapacity,
            available: available
          )
        }
        highestProgress = 0
        setState(.downloading(progress: 0))
        try await Task.detached {
          try Self.prepareRoot(context)
          try Self.validateManifest(manifest)
        }.value

        let stagingRepository = try Self.repositoryURL(
          under: context.stagingRevision(manifest.revision),
          manifest: manifest
        )
        var completedBytes: Int64 = 0
        for file in manifest.files {
          try Task.checkCancellation()
          let target = try Self.containedURL(
            for: file.path,
            under: stagingRepository
          )
          let alreadyValid = await Task.detached {
            (try? Self.verifyFile(
              file,
              at: target,
              ownershipRoot: context.root,
              fileManager: context.fileManager
            )) != nil
          }.value
          if alreadyValid {
            completedBytes += file.byteCount
            updateProgress(
              completedBytes: completedBytes,
              receivedBytes: 0,
              operationID: operationID
            )
            continue
          }

          let resumeURL = try Self.resumeURL(
            for: file,
            context: context,
            manifest: manifest
          )
          let remoteURL = try Self.remoteURL(for: file, manifest: manifest)
          let transport = transport
          let resumeAuthenticationKeyProvider = resumeAuthenticationKeyProvider
          let resumeToken = await Task.detached { () -> ModelResumeToken? in
            guard
              (try? Self.assertOwnedPath(resumeURL, context: context)) != nil,
              let stored = try? Data(contentsOf: resumeURL),
              let envelope = try? JSONDecoder().decode(
                ModelResumeEnvelope.self,
                from: stored
              ),
              envelope.remoteURL == remoteURL,
              let key = try? resumeAuthenticationKeyProvider(),
              envelope.isAuthenticated(using: key)
            else { return nil }
            return ModelResumeToken(issuedData: envelope.data)
          }.value
          do {
            let completedBeforeFile = completedBytes
            let result = try await transport.download(
              from: remoteURL,
              resumeToken: resumeToken
            ) { [weak self] received, _ in
              Task { @MainActor in
                self?.updateProgress(
                  completedBytes: completedBeforeFile,
                  receivedBytes: min(max(received, 0), file.byteCount),
                  operationID: operationID
                )
              }
            }
            try await Task.detached {
              try Self.createOwnedDirectory(
                target.deletingLastPathComponent(),
                context: context
              )
              try Self.removeOwnedItemIfPresent(target, context: context)
              try context.fileManager.moveItem(at: result.temporaryURL, to: target)
              try Self.removeOwnedItemIfPresent(resumeURL, context: context)
            }.value
            completedBytes += file.byteCount
            updateProgress(
              completedBytes: completedBytes,
              receivedBytes: 0,
              operationID: operationID
            )
          } catch ModelDownloadError.cancelled(let data) {
            if
              let data,
              let token = transport.sessionProducedResumeToken(
                for: data,
                remoteURL: remoteURL
              ),
              let key = try? resumeAuthenticationKeyProvider()
            {
              try await Task.detached {
                try Self.createOwnedDirectory(
                  resumeURL.deletingLastPathComponent(),
                  context: context
                )
                try JSONEncoder().encode(
                  ModelResumeEnvelope(
                    remoteURL: remoteURL,
                    data: token.data,
                    authenticationKey: key
                  )
                ).write(to: resumeURL, options: .atomic)
              }.value
            } else {
              try? await Task.detached {
                try Self.removeOwnedItemIfPresent(resumeURL, context: context)
              }.value
            }
            throw ModelDownloadError.cancelled(resumeData: data)
          }
        }

        setState(.verifying)
        do {
          try await Task.detached {
            try Self.verifyRepository(
              at: stagingRepository,
              manifest: manifest,
              fileManager: context.fileManager,
              ownershipRoot: context.root
            )
          }.value
        } catch {
          try? await Task.detached {
            try Self.removeStagingAndResume(context)
          }.value
          throw error
        }

        setState(.installing)
        let installedRepository = try await Task.detached {
          try Self.commitVerifiedStaging(context, manifest: manifest)
        }.value
        verifiedRepositoryURL = installedRepository
        let cleanupWillBegin = cleanupWillBegin
        try await Task.detached {
          cleanupWillBegin()
          try Self.cleanupCommittedInstallation(
            context,
            manifest: manifest,
            installedRepository: installedRepository
          )
        }.value
        finishOperation(operationID)
        setState(.ready)
        applyPendingInferenceLoadFailureIfCurrent()
      } catch {
        finishOperation(operationID)
        if
          let installError = error as? ModelInstallError,
          case .cleanupFailed(let repositoryURL, _) = installError
        {
          verifiedRepositoryURL = repositoryURL
          setState(.ready)
        } else if let previousRepositoryURL {
          verifiedRepositoryURL = previousRepositoryURL
          setState(previousState == .updateAvailable ? .updateAvailable : .ready)
        } else if
          let managerError = error as? EnhancedModelManagerError,
          case .insufficientSpace = managerError
        {
          setState(previousState)
        } else if !(error is CancellationError), !(error is ModelDownloadError) {
          verifiedRepositoryURL = nil
          setState(.repairRequired(message: error.localizedDescription))
        } else {
          await refreshState()
        }
        applyPendingInferenceLoadFailureIfCurrent()
        throw error
      }
    }

    private func beginOperation() throws -> UUID {
      guard activeOperationID == nil else {
        throw EnhancedModelManagerError.operationInProgress
      }
      lifecycleEpoch &+= 1
      let operationID = UUID()
      activeOperationID = operationID
      return operationID
    }

    private func finishOperation(_ operationID: UUID) {
      guard activeOperationID == operationID else { return }
      activeOperationID = nil
    }

    private func applyPendingInferenceLoadFailureIfCurrent() {
      guard activeOperationID == nil, activeAssessmentCount == 0 else { return }
      guard let pendingInferenceLoadFailure else { return }
      self.pendingInferenceLoadFailure = nil
      guard verifiedRepositoryURL == pendingInferenceLoadFailure.repositoryURL else { return }
      lifecycleEpoch &+= 1
      verifiedRepositoryURL = nil
      setState(.repairRequired(message: pendingInferenceLoadFailure.message))
    }

    private func updateProgress(
      completedBytes: Int64,
      receivedBytes: Int64,
      operationID: UUID
    ) {
      guard activeOperationID == operationID else { return }
      let progress = manifest.totalByteCount > 0
        ? min(Double(completedBytes + receivedBytes) / Double(manifest.totalByteCount), 1)
        : 1
      highestProgress = max(highestProgress, progress)
      setState(.downloading(progress: highestProgress))
    }

    private func setState(_ newState: EnhancedModelState) {
      stateChangedAt = clock()
      state = newState
    }

    private static func embeddedManifest() -> EnhancedModelManifest {
      let url = Bundle.module.url(
        forResource: "EnhancedModelManifest",
        withExtension: "json"
      )!
      return try! JSONDecoder().decode(
        EnhancedModelManifest.self,
        from: Data(contentsOf: url)
      )
    }

    nonisolated static func resumeAuthenticationKeychainBaseQuery()
      -> [CFString: Any]
    {
      [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.motes.enhanced-model-resume",
        kSecAttrAccount: "default",
        kSecUseDataProtectionKeychain: true,
      ]
    }

    nonisolated private static func loadOrCreateResumeAuthenticationKey() throws
      -> SymmetricKey
    {
      let baseQuery = resumeAuthenticationKeychainBaseQuery()
      var lookup = baseQuery
      lookup[kSecReturnData] = true
      lookup[kSecMatchLimit] = kSecMatchLimitOne
      var result: CFTypeRef?
      var status = SecItemCopyMatching(lookup as CFDictionary, &result)
      if status == errSecSuccess, let data = result as? Data {
        return SymmetricKey(data: data)
      }
      guard status == errSecItemNotFound else {
        throw keychainError(status)
      }

      var bytes = Data(count: 32)
      let randomStatus = bytes.withUnsafeMutableBytes {
        SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
      }
      guard randomStatus == errSecSuccess else {
        throw keychainError(randomStatus)
      }
      var insertion = baseQuery
      insertion[kSecValueData] = bytes
      insertion[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(insertion as CFDictionary, nil)
      if status == errSecSuccess {
        return SymmetricKey(data: bytes)
      }
      guard status == errSecDuplicateItem else {
        throw keychainError(status)
      }

      result = nil
      status = SecItemCopyMatching(lookup as CFDictionary, &result)
      guard status == errSecSuccess, let data = result as? Data else {
        throw keychainError(status)
      }
      return SymmetricKey(data: data)
    }

    nonisolated private static func keychainError(_ status: OSStatus) -> NSError {
      NSError(
        domain: NSOSStatusErrorDomain,
        code: Int(status),
        userInfo: [
          NSLocalizedDescriptionKey:
            SecCopyErrorMessageString(status, nil) as String?
              ?? "Keychain operation failed."
        ]
      )
    }

    nonisolated private static func assess(
      context: FileContext,
      manifest: EnhancedModelManifest,
      trustedManifests: [EnhancedModelManifest]
    ) throws -> Assessment {
      try prepareRoot(context)
      try validateManifest(manifest)
      for trustedManifest in trustedManifests {
        try validateManifest(trustedManifest)
      }
      let currentRevision = context.installedRevision(manifest.revision)
      if context.fileManager.fileExists(atPath: currentRevision.path) {
        let repository = try repositoryURL(under: currentRevision, manifest: manifest)
        do {
          try verifyRepository(
            at: repository,
            manifest: manifest,
            fileManager: context.fileManager,
            ownershipRoot: context.root
          )
          return Assessment(state: .ready, repositoryURL: repository)
        } catch {
          return Assessment(
            state: .repairRequired(message: error.localizedDescription),
            repositoryURL: nil
          )
        }
      }

      guard context.fileManager.fileExists(atPath: context.installedRoot.path) else {
        return Assessment(state: .notInstalled, repositoryURL: nil)
      }
      try assertOwnedPath(context.installedRoot, context: context)
      let revisions = try context.fileManager.contentsOfDirectory(
        at: context.installedRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
      )
      for revision in revisions where revision.lastPathComponent != manifest.revision {
        guard
          let oldManifest = trustedManifests.first(where: {
            $0.revision == revision.lastPathComponent && $0.modelID == manifest.modelID
          }),
          oldManifest.modelID == manifest.modelID,
          let repository = try? repositoryURL(
            under: revision,
            manifest: oldManifest
          ),
          (try? verifyRepository(
            at: repository,
            manifest: oldManifest,
            fileManager: context.fileManager,
            ownershipRoot: context.root
          )) != nil
        else { continue }
        return Assessment(state: .updateAvailable, repositoryURL: repository)
      }
      return Assessment(state: .notInstalled, repositoryURL: nil)
    }

    nonisolated private static func prepareRoot(_ context: FileContext) throws {
      try assertSafeModelRoot(context)
      try context.fileManager.createDirectory(
        at: context.root,
        withIntermediateDirectories: true
      )
      try assertSafeModelRoot(context)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var root = context.root
      try root.setResourceValues(values)
    }

    nonisolated private static func validateManifest(
      _ manifest: EnhancedModelManifest
    ) throws {
      guard
        manifest.schemaVersion == 1,
        !manifest.modelID.isEmpty,
        manifest.totalByteCount >= 0,
        manifest.files.reduce(Int64(0), { $0 + $1.byteCount })
          == manifest.totalByteCount,
        Set(manifest.files.map(\.path)).count == manifest.files.count
      else {
        throw EnhancedModelManagerError.invalidManifest
      }
      try validateRevision(manifest.revision)
      for file in manifest.files {
        try validateRelativePath(file.path)
        guard
          file.byteCount >= 0,
          file.sha256.count == 64,
          file.sha256.allSatisfy({ $0.isHexDigit })
        else {
          throw EnhancedModelManagerError.invalidManifest
        }
      }
    }

    nonisolated private static func validateRelativePath(_ path: String) throws {
      let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
      guard
        !path.isEmpty,
        !path.hasPrefix("/"),
        pieces.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
      else {
        throw EnhancedModelManagerError.invalidManifestPath(path)
      }
    }

    nonisolated private static func validateRevision(_ revision: String) throws {
      guard
        !revision.isEmpty,
        !revision.contains("/"),
        revision != ".",
        revision != ".."
      else {
        throw EnhancedModelManagerError.invalidManifest
      }
    }

    nonisolated private static func repositoryURL(
      under revisionURL: URL,
      manifest: EnhancedModelManifest
    ) throws -> URL {
      guard
        let name = manifest.modelID.split(separator: "/").last,
        !name.isEmpty
      else {
        throw EnhancedModelManagerError.invalidManifest
      }
      return try containedURL(for: String(name), under: revisionURL)
    }

    nonisolated private static func containedURL(
      for relativePath: String,
      under root: URL
    ) throws -> URL {
      try validateRelativePath(relativePath)
      let root = lexicallyNormalizedURL(root)
      let candidate = relativePath.split(separator: "/").reduce(root) {
        $0.appendingPathComponent(String($1))
      }
      guard candidate.path.hasPrefix(root.path + "/") else {
        throw EnhancedModelManagerError.invalidManifestPath(relativePath)
      }
      return candidate
    }

    nonisolated private static func verifyRepository(
      at repository: URL,
      manifest: EnhancedModelManifest,
      fileManager: FileManager,
      ownershipRoot: URL
    ) throws {
      let allowed = Set(manifest.files.map(\.path))
      let allowedDirectories = Set(manifest.files.flatMap { file -> [String] in
        let pieces = file.path.split(separator: "/").dropLast()
        return pieces.indices.map {
          pieces.prefix(through: $0).joined(separator: "/")
        }
      })
      try assertOwnedPath(
        repository,
        root: ownershipRoot,
        fileManager: fileManager
      )
      for file in manifest.files {
        let url = try containedURL(for: file.path, under: repository)
        try verifyFile(
          file,
          at: url,
          ownershipRoot: ownershipRoot,
          fileManager: fileManager
        )
      }
      guard
        let enumerator = fileManager.enumerator(
          at: repository,
          includingPropertiesForKeys: [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
          ]
        )
      else {
        throw EnhancedModelManagerError.wrongByteCount(repository.path)
      }
      for case let url as URL in enumerator {
        let values = try url.resourceValues(
          forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        let standardizedRepositoryPath = repository.standardizedFileURL.path
        let repositoryPath = standardizedRepositoryPath.hasSuffix("/")
          ? String(standardizedRepositoryPath.dropLast())
          : standardizedRepositoryPath
        let relative = String(
          url.standardizedFileURL.path.dropFirst(repositoryPath.count + 1)
        )
        if values.isSymbolicLink == true {
          throw EnhancedModelManagerError.unexpectedFile(relative)
        }
        if values.isRegularFile == true {
          guard allowed.contains(relative) else {
            throw EnhancedModelManagerError.unexpectedFile(relative)
          }
        } else if values.isDirectory == true {
          guard allowedDirectories.contains(relative) else {
            throw EnhancedModelManagerError.unexpectedFile(relative)
          }
        } else {
          throw EnhancedModelManagerError.unexpectedFile(relative)
        }
      }
    }

    nonisolated private static func verifyFile(
      _ file: EnhancedModelFile,
      at url: URL,
      ownershipRoot: URL,
      fileManager: FileManager
    ) throws {
      try assertOwnedPath(url, root: ownershipRoot, fileManager: fileManager)
      let values = try url.resourceValues(
        forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
      )
      guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw EnhancedModelManagerError.wrongByteCount(file.path)
      }
      guard Int64(values.fileSize ?? -1) == file.byteCount else {
        throw EnhancedModelManagerError.wrongByteCount(file.path)
      }
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      var digest = SHA256()
      while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        digest.update(data: data)
      }
      let value = digest.finalize().map { String(format: "%02x", $0) }.joined()
      guard value.caseInsensitiveCompare(file.sha256) == .orderedSame else {
        throw EnhancedModelManagerError.checksumMismatch(file.path)
      }
    }

    nonisolated private static func resumeURL(
      for file: EnhancedModelFile,
      context: FileContext,
      manifest: EnhancedModelManifest
    ) throws -> URL {
      let repository = try repositoryURL(
        under: context.resumeRevision(manifest.revision),
        manifest: manifest
      )
      return try containedURL(for: file.path + ".resumeData", under: repository)
    }

    nonisolated private static func removeStagingAndResume(
      _ context: FileContext
    ) throws {
      for url in [
        context.stagingRoot,
        context.resumeRoot,
      ] {
        try removeOwnedTreeIfPresent(url, context: context)
      }
    }

    nonisolated private static func commitVerifiedStaging(
      _ context: FileContext,
      manifest: EnhancedModelManifest
    ) throws -> URL {
      let staging = context.stagingRevision(manifest.revision)
      try assertOwnedPath(staging, context: context)
      try JSONEncoder().encode(manifest).write(
        to: staging.appendingPathComponent("manifest.json"),
        options: .atomic
      )
      try createOwnedDirectory(context.installedRoot, context: context)
      let final = context.installedRevision(manifest.revision)
      try removeOwnedTreeIfPresent(final, context: context)
      try context.fileManager.moveItem(at: staging, to: final)
      return try repositoryURL(under: final, manifest: manifest)
    }

    nonisolated private static func cleanupCommittedInstallation(
      _ context: FileContext,
      manifest: EnhancedModelManifest,
      installedRepository: URL
    ) throws {
      let final = context.installedRevision(manifest.revision)
      do {
        let revisions = try context.fileManager.contentsOfDirectory(
          at: context.installedRoot,
          includingPropertiesForKeys: [.isSymbolicLinkKey]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for revision in revisions
        where revision.standardizedFileURL.path != final.standardizedFileURL.path {
          try removeOwnedTreeIfPresent(revision, context: context)
        }
        let resume = context.resumeRevision(manifest.revision)
        try removeOwnedTreeIfPresent(resume, context: context)
      } catch {
        throw ModelInstallError.cleanupFailed(
          repositoryURL: installedRepository,
          message: error.localizedDescription
        )
      }
    }

    nonisolated private static func createOwnedDirectory(
      _ url: URL,
      context: FileContext
    ) throws {
      try assertOwnedPath(url, context: context)
      try context.fileManager.createDirectory(
        at: url,
        withIntermediateDirectories: true
      )
      try assertOwnedPath(url, context: context)
    }

    nonisolated private static func removeOwnedItemIfPresent(
      _ url: URL,
      context: FileContext
    ) throws {
      try assertOwnedPath(url, context: context)
      guard try fileType(at: url, fileManager: context.fileManager) != nil else {
        return
      }
      try context.fileManager.removeItem(at: url)
    }

    nonisolated private static func removeOwnedTreeIfPresent(
      _ url: URL,
      context: FileContext
    ) throws {
      try removeOwnedItemIfPresent(url, context: context)
    }

    nonisolated private static func assertSafeModelRoot(
      _ context: FileContext
    ) throws {
      try assertNoSymlinkAncestors(
        context.root,
        fileManager: context.fileManager
      )
      if let type = try fileType(at: context.root, fileManager: context.fileManager),
        type != .typeDirectory
      {
        throw EnhancedModelManagerError.unsafeFilesystemPath(context.root.path)
      }
    }

    nonisolated private static func assertOwnedPath(
      _ url: URL,
      context: FileContext
    ) throws {
      try assertOwnedPath(
        url,
        root: context.root,
        fileManager: context.fileManager
      )
    }

    nonisolated private static func assertOwnedPath(
      _ url: URL,
      root: URL,
      fileManager: FileManager
    ) throws {
      let root = lexicallyNormalizedURL(root)
      let candidate = lexicallyNormalizedURL(url)
      guard candidate == root || candidate.path.hasPrefix(root.path + "/") else {
        throw EnhancedModelManagerError.unsafeFilesystemPath(candidate.path)
      }

      try assertNoSymlinkAncestors(candidate, fileManager: fileManager)
    }

    nonisolated private static func assertNoSymlinkAncestors(
      _ url: URL,
      fileManager: FileManager
    ) throws {
      let candidate = lexicallyNormalizedURL(url)
      var current = candidate
      while true {
        if let type = try fileType(at: current, fileManager: fileManager) {
          guard type != .typeSymbolicLink else {
            throw EnhancedModelManagerError.unsafeFilesystemPath(current.path)
          }
          if current != candidate, type != .typeDirectory {
            throw EnhancedModelManagerError.unsafeFilesystemPath(current.path)
          }
        }
        let next = current.deletingLastPathComponent()
        if next.path == current.path { return }
        current = next
      }
    }

    nonisolated private static func lexicallyNormalizedURL(_ url: URL) -> URL {
      var components: [Substring] = []
      for component in url.path.split(separator: "/", omittingEmptySubsequences: true) {
        if component == "." { continue }
        if component == ".." {
          if !components.isEmpty { components.removeLast() }
        } else {
          components.append(component)
        }
      }
      return URL(fileURLWithPath: "/" + components.joined(separator: "/"))
    }

    nonisolated private static func fileType(
      at url: URL,
      fileManager: FileManager
    ) throws -> FileAttributeType? {
      guard fileManager.fileExists(atPath: url.path) else {
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
          return .typeSymbolicLink
        }
        return nil
      }
      return try fileManager.attributesOfItem(atPath: url.path)[.type]
        as? FileAttributeType
    }
  }

  private struct Assessment: Sendable {
    let state: EnhancedModelState
    let repositoryURL: URL?
  }

  private enum ModelInstallError: Error, LocalizedError, Sendable {
    case cleanupFailed(repositoryURL: URL, message: String)

    var errorDescription: String? {
      switch self {
      case .cleanupFailed(_, let message):
        return "The new model is ready, but old model cleanup failed: \(message)"
      }
    }
  }

  private struct ModelResumeEnvelope: Codable, Sendable {
    let remoteURL: URL
    let data: Data
    let authenticationTag: Data

    init(remoteURL: URL, data: Data, authenticationKey: SymmetricKey) {
      self.remoteURL = remoteURL
      self.data = data
      authenticationTag = Data(HMAC<SHA256>.authenticationCode(
        for: Self.authenticatedBytes(remoteURL: remoteURL, data: data),
        using: authenticationKey
      ))
    }

    func isAuthenticated(using key: SymmetricKey) -> Bool {
      HMAC<SHA256>.isValidAuthenticationCode(
        authenticationTag,
        authenticating: Self.authenticatedBytes(remoteURL: remoteURL, data: data),
        using: key
      )
    }

    private static func authenticatedBytes(remoteURL: URL, data: Data) -> Data {
      var bytes = Data(remoteURL.absoluteString.utf8)
      bytes.append(0)
      bytes.append(data)
      return bytes
    }
  }

  private final class FileContext: @unchecked Sendable {
    let root: URL
    let fileManager: FileManager

    init(root: URL, fileManager: FileManager) {
      self.root = root
      self.fileManager = fileManager
    }

    var installedRoot: URL {
      root.appendingPathComponent("installed", isDirectory: true)
    }

    var stagingRoot: URL {
      root.appendingPathComponent("staging", isDirectory: true)
    }

    var resumeRoot: URL {
      root.appendingPathComponent("resume", isDirectory: true)
    }

    var derivedRoot: URL {
      root.appendingPathComponent("derived", isDirectory: true)
    }

    func installedRevision(_ revision: String) -> URL {
      installedRoot.appendingPathComponent(revision, isDirectory: true)
    }

    func stagingRevision(_ revision: String) -> URL {
      stagingRoot.appendingPathComponent(revision, isDirectory: true)
    }

    func resumeRevision(_ revision: String) -> URL {
      resumeRoot.appendingPathComponent(revision, isDirectory: true)
    }
  }

  final class URLSessionModelDownloader: NSObject, ModelDownloading, @unchecked Sendable {
    private let resumeLock = NSLock()
    private var sessionProducedResumeData: [Data: URL] = [:]

    func sessionProducedResumeToken(
      for data: Data,
      remoteURL: URL
    ) -> ModelResumeToken? {
      resumeLock.withLock {
        guard sessionProducedResumeData[data] == remoteURL else { return nil }
        sessionProducedResumeData.removeValue(forKey: data)
        return ModelResumeToken(issuedData: data)
      }
    }

    func recordSessionProducedResumeData(_ data: Data, for remoteURL: URL) {
      resumeLock.withLock {
        sessionProducedResumeData[data] = remoteURL
      }
    }

    func download(
      from remoteURL: URL,
      resumeToken: ModelResumeToken?,
      progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> ModelDownloadResult {
      guard Self.isPinnedInitialURL(remoteURL) else {
        throw ModelDownloadError.redirectRejected
      }
      let delegate = DownloadDelegate(progress: progress)
      do {
        return try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation { continuation in
            delegate.start(
              remoteURL: remoteURL,
              resumeData: resumeToken?.data,
              continuation: continuation
            )
          }
        } onCancel: {
          delegate.cancel()
        }
      } catch ModelDownloadError.cancelled(let data) {
        if let data {
          recordSessionProducedResumeData(data, for: remoteURL)
        }
        throw ModelDownloadError.cancelled(resumeData: data)
      }
    }

    static func isAllowedRedirectHost(_ host: String) -> Bool {
      let host = host.lowercased()
      return host == "huggingface.co"
        || host.hasSuffix(".huggingface.co")
        || host.hasSuffix(".xethub.hf.co")
    }

    static func isAllowedRedirectURL(_ url: URL) -> Bool {
      url.scheme?.lowercased() == "https"
        && url.host.map(isAllowedRedirectHost) == true
    }

    private static func isPinnedInitialURL(_ url: URL) -> Bool {
      url.scheme?.lowercased() == "https"
        && url.host?.lowercased() == "huggingface.co"
    }
  }

  final class DownloadStartHandshake: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationRequested = false
    private var task: URLSessionDownloadTask?

    func installAndResume(_ task: URLSessionDownloadTask) -> Bool {
      lock.withLock {
        guard !cancellationRequested else { return false }
        self.task = task
        task.resume()
        return true
      }
    }

    func requestCancellation() -> URLSessionDownloadTask? {
      lock.withLock {
        cancellationRequested = true
        return task
      }
    }

    func clear() {
      lock.withLock { task = nil }
    }
  }

  private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate,
    @unchecked Sendable
  {
    private let lock = NSLock()
    private let startHandshake = DownloadStartHandshake()
    private let progress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<ModelDownloadResult, Error>?
    private var session: URLSession?
    private var downloadedURL: URL?

    init(progress: @escaping @Sendable (Int64, Int64) -> Void) {
      self.progress = progress
    }

    func start(
      remoteURL: URL,
      resumeData: Data?,
      continuation: CheckedContinuation<ModelDownloadResult, Error>
    ) {
      let task = lock.withLock { () -> URLSessionDownloadTask in
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(
          configuration: configuration,
          delegate: self,
          delegateQueue: nil
        )
        self.session = session
        return resumeData.map(session.downloadTask(withResumeData:))
          ?? session.downloadTask(with: remoteURL)
      }
      guard startHandshake.installAndResume(task) else {
        finish(.failure(ModelDownloadError.cancelled(resumeData: nil)))
        return
      }
    }

    func cancel() {
      let task = startHandshake.requestCancellation()
      task?.cancel { [weak self] data in
        self?.finish(.failure(ModelDownloadError.cancelled(resumeData: data)))
      }
    }

    func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64,
      totalBytesExpectedToWrite: Int64
    ) {
      progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest,
      completionHandler: @escaping (URLRequest?) -> Void
    ) {
      guard
        let url = request.url,
        URLSessionModelDownloader.isAllowedRedirectURL(url)
      else {
        completionHandler(nil)
        finish(.failure(ModelDownloadError.redirectRejected))
        return
      }
      completionHandler(request)
    }

    func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didFinishDownloadingTo location: URL
    ) {
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      do {
        try FileManager.default.moveItem(at: location, to: destination)
        lock.withLock { downloadedURL = destination }
      } catch {
        finish(.failure(error))
      }
    }

    func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didCompleteWithError error: Error?
    ) {
      if let error {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
          let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
          finish(.failure(ModelDownloadError.cancelled(resumeData: data)))
        } else {
          finish(.failure(ModelDownloadError.failed(error.localizedDescription)))
        }
      } else if let url = lock.withLock({ downloadedURL }) {
        finish(.success(ModelDownloadResult(temporaryURL: url, resumeData: nil)))
      } else {
        finish(.failure(ModelDownloadError.failed("The download produced no file.")))
      }
    }

    private func finish(_ result: Result<ModelDownloadResult, Error>) {
      let continuation = lock.withLock { () -> CheckedContinuation<ModelDownloadResult, Error>? in
        defer {
          self.continuation = nil
          startHandshake.clear()
          session?.finishTasksAndInvalidate()
          session = nil
        }
        return self.continuation
      }
      continuation?.resume(with: result)
    }
  }
#endif
