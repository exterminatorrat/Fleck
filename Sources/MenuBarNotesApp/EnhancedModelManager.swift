#if os(macOS)
  import Combine
  import CryptoKit
  import Foundation

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

  protocol ModelDownloading: Sendable {
    func download(
      from remoteURL: URL,
      resumeData: Data?,
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
    case unsupportedArchitecture
    case insufficientSpace(required: Int64, available: Int64)
    case invalidManifestPath(String)
    case invalidManifest
    case checksumMismatch(String)
    case wrongByteCount(String)
    case unexpectedFile(String)

    var errorDescription: String? {
      switch self {
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
      }
    }
  }

  @MainActor
  final class EnhancedModelManager: ObservableObject {
    static let requiredAvailableCapacity: Int64 = 1_197_261_950

    @Published private(set) var state: EnhancedModelState = .notInstalled
    private(set) var verifiedRepositoryURL: URL?
    let isArchitectureSupported: Bool

    private let context: FileContext
    private let manifest: EnhancedModelManifest
    private let capacityProvider: @Sendable () throws -> Int64
    private let clock: @Sendable () -> Date
    private let transport: any ModelDownloading
    private var stateChangedAt: Date
    private var activeOperationID: UUID?
    private var highestProgress = 0.0

    init(
      modelRootURL: URL? = nil,
      fileManager: FileManager = .default,
      manifest: EnhancedModelManifest? = nil,
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
      transport: any ModelDownloading = URLSessionModelDownloader()
    ) {
      let root = modelRootURL ?? fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )[0]
      .appendingPathComponent("MenuBarNotes", isDirectory: true)
      .appendingPathComponent("DictationModels", isDirectory: true)
      self.context = FileContext(root: root, fileManager: fileManager)
      self.manifest = manifest ?? Self.embeddedManifest()
      self.capacityProvider = capacityProvider
      self.isArchitectureSupported = architectureProvider()
      self.clock = clock
      self.transport = transport
      stateChangedAt = clock()
    }

    func refreshState() async {
      guard isArchitectureSupported else {
        setState(.notInstalled)
        return
      }
      let context = context
      let manifest = manifest
      let assessment = await Task.detached {
        Result { try Self.assess(context: context, manifest: manifest) }
      }.value
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
      try await installCurrentModel()
    }

    func repair() async throws {
      try await installCurrentModel()
    }

    func update() async throws {
      try await installCurrentModel()
    }

    func deleteModel() async throws {
      guard isArchitectureSupported else {
        setState(.notInstalled)
        return
      }
      setState(.removing)
      let context = context
      do {
        try await Task.detached {
          for url in [
            context.installedRoot,
            context.stagingRoot,
            context.resumeRoot,
            context.derivedRoot,
          ] where context.fileManager.fileExists(atPath: url.path) {
            try context.fileManager.removeItem(at: url)
          }
        }.value
        verifiedRepositoryURL = nil
        setState(.notInstalled)
      } catch {
        setState(.repairRequired(message: error.localizedDescription))
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
      let available = try capacityProvider()
      guard available >= Self.requiredAvailableCapacity else {
        throw EnhancedModelManagerError.insufficientSpace(
          required: Self.requiredAvailableCapacity,
          available: available
        )
      }

      let operationID = UUID()
      activeOperationID = operationID
      highestProgress = 0
      setState(.downloading(progress: 0))
      let context = context
      let manifest = manifest

      do {
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
            (try? Self.verifyFile(file, at: target)) != nil
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
          let resumeData = await Task.detached { () -> Data? in
            guard
              let data = try? Data(contentsOf: resumeURL),
              Self.isValidResumeData(data)
            else { return nil }
            return data
          }.value
          let remoteURL = try Self.remoteURL(for: file, manifest: manifest)
          do {
            let completedBeforeFile = completedBytes
            let result = try await transport.download(
              from: remoteURL,
              resumeData: resumeData
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
              try context.fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
              )
              if context.fileManager.fileExists(atPath: target.path) {
                try context.fileManager.removeItem(at: target)
              }
              try context.fileManager.moveItem(at: result.temporaryURL, to: target)
              if context.fileManager.fileExists(atPath: resumeURL.path) {
                try context.fileManager.removeItem(at: resumeURL)
              }
            }.value
            completedBytes += file.byteCount
            updateProgress(
              completedBytes: completedBytes,
              receivedBytes: 0,
              operationID: operationID
            )
          } catch ModelDownloadError.cancelled(let data) {
            if let data, Self.isValidResumeData(data) {
              try await Task.detached {
                try context.fileManager.createDirectory(
                  at: resumeURL.deletingLastPathComponent(),
                  withIntermediateDirectories: true
                )
                try data.write(to: resumeURL, options: .atomic)
              }.value
            } else {
              try? await Task.detached {
                if context.fileManager.fileExists(atPath: resumeURL.path) {
                  try context.fileManager.removeItem(at: resumeURL)
                }
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
              fileManager: context.fileManager
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
          try Self.installVerifiedStaging(context, manifest: manifest)
        }.value
        verifiedRepositoryURL = installedRepository
        setState(.ready)
      } catch {
        activeOperationID = nil
        if !(error is CancellationError),
          !(error is ModelDownloadError)
        {
          verifiedRepositoryURL = nil
          setState(.repairRequired(message: error.localizedDescription))
        } else {
          await refreshState()
        }
        throw error
      }
      activeOperationID = nil
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

    nonisolated private static func assess(
      context: FileContext,
      manifest: EnhancedModelManifest
    ) throws -> Assessment {
      try prepareRoot(context)
      try validateManifest(manifest)
      let currentRevision = context.installedRevision(manifest.revision)
      if context.fileManager.fileExists(atPath: currentRevision.path) {
        let repository = try repositoryURL(under: currentRevision, manifest: manifest)
        do {
          try verifyRepository(
            at: repository,
            manifest: manifest,
            fileManager: context.fileManager
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
      let revisions = try context.fileManager.contentsOfDirectory(
        at: context.installedRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
      for revision in revisions where revision.lastPathComponent != manifest.revision {
        let manifestURL = revision.appendingPathComponent("manifest.json")
        guard
          let data = try? Data(contentsOf: manifestURL),
          let oldManifest = try? JSONDecoder().decode(
            EnhancedModelManifest.self,
            from: data
          ),
          oldManifest.modelID == manifest.modelID,
          oldManifest.revision == revision.lastPathComponent,
          let repository = try? repositoryURL(
            under: revision,
            manifest: oldManifest
          ),
          (try? verifyRepository(
            at: repository,
            manifest: oldManifest,
            fileManager: context.fileManager
          )) != nil
        else { continue }
        return Assessment(state: .updateAvailable, repositoryURL: nil)
      }
      return Assessment(state: .notInstalled, repositoryURL: nil)
    }

    nonisolated private static func prepareRoot(_ context: FileContext) throws {
      try context.fileManager.createDirectory(
        at: context.root,
        withIntermediateDirectories: true
      )
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
      let root = root.standardizedFileURL
      let candidate = relativePath.split(separator: "/").reduce(root) {
        $0.appendingPathComponent(String($1))
      }.standardizedFileURL
      guard candidate.path.hasPrefix(root.path + "/") else {
        throw EnhancedModelManagerError.invalidManifestPath(relativePath)
      }
      return candidate
    }

    nonisolated private static func verifyRepository(
      at repository: URL,
      manifest: EnhancedModelManifest,
      fileManager: FileManager
    ) throws {
      let allowed = Set(manifest.files.map(\.path))
      for file in manifest.files {
        let url = try containedURL(for: file.path, under: repository)
        try verifyFile(file, at: url)
      }
      guard
        let enumerator = fileManager.enumerator(
          at: repository,
          includingPropertiesForKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
          ]
        )
      else {
        throw EnhancedModelManagerError.wrongByteCount(repository.path)
      }
      for case let url as URL in enumerator {
        let values = try url.resourceValues(
          forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
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
        if values.isRegularFile == true, !allowed.contains(relative) {
          throw EnhancedModelManagerError.unexpectedFile(relative)
        }
      }
    }

    nonisolated private static func verifyFile(
      _ file: EnhancedModelFile,
      at url: URL
    ) throws {
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

    nonisolated private static func isValidResumeData(_ data: Data) -> Bool {
      guard
        let value = try? PropertyListSerialization.propertyList(
          from: data,
          options: [],
          format: nil
        ),
        let dictionary = value as? [String: Any]
      else { return false }
      return dictionary["NSURLSessionResumeCurrentRequest"] != nil
        || dictionary["NSURLSessionResumeOriginalRequest"] != nil
        || dictionary["NSURLSessionDownloadURL"] != nil
    }

    nonisolated private static func removeStagingAndResume(
      _ context: FileContext
    ) throws {
      for url in [
        context.stagingRoot,
        context.resumeRoot,
      ] where context.fileManager.fileExists(atPath: url.path) {
        try context.fileManager.removeItem(at: url)
      }
    }

    nonisolated private static func installVerifiedStaging(
      _ context: FileContext,
      manifest: EnhancedModelManifest
    ) throws -> URL {
      let staging = context.stagingRevision(manifest.revision)
      try JSONEncoder().encode(manifest).write(
        to: staging.appendingPathComponent("manifest.json"),
        options: .atomic
      )
      try context.fileManager.createDirectory(
        at: context.installedRoot,
        withIntermediateDirectories: true
      )
      let final = context.installedRevision(manifest.revision)
      if context.fileManager.fileExists(atPath: final.path) {
        try context.fileManager.removeItem(at: final)
      }
      try context.fileManager.moveItem(at: staging, to: final)

      let revisions = try context.fileManager.contentsOfDirectory(
        at: context.installedRoot,
        includingPropertiesForKeys: nil
      )
      for revision in revisions
      where revision.standardizedFileURL.path != final.standardizedFileURL.path {
        try context.fileManager.removeItem(at: revision)
      }
      let resume = context.resumeRevision(manifest.revision)
      if context.fileManager.fileExists(atPath: resume.path) {
        try context.fileManager.removeItem(at: resume)
      }
      return try repositoryURL(under: final, manifest: manifest)
    }
  }

  private struct Assessment: Sendable {
    let state: EnhancedModelState
    let repositoryURL: URL?
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
    func download(
      from remoteURL: URL,
      resumeData: Data?,
      progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> ModelDownloadResult {
      let delegate = DownloadDelegate(progress: progress)
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          delegate.start(
            remoteURL: remoteURL,
            resumeData: resumeData,
            continuation: continuation
          )
        }
      } onCancel: {
        delegate.cancel()
      }
    }

    static func isAllowedRedirectHost(_ host: String) -> Bool {
      let host = host.lowercased()
      return host == "huggingface.co"
        || host.hasSuffix(".huggingface.co")
        || host.hasSuffix(".xethub.hf.co")
    }
  }

  private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate,
    @unchecked Sendable
  {
    private let lock = NSLock()
    private let progress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<ModelDownloadResult, Error>?
    private var task: URLSessionDownloadTask?
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
      lock.withLock {
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(
          configuration: configuration,
          delegate: self,
          delegateQueue: nil
        )
        self.session = session
        let task = resumeData.map(session.downloadTask(withResumeData:))
          ?? session.downloadTask(with: remoteURL)
        self.task = task
        task.resume()
      }
    }

    func cancel() {
      let task = lock.withLock { self.task }
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
        let host = request.url?.host,
        URLSessionModelDownloader.isAllowedRedirectHost(host)
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
          task = nil
          session?.finishTasksAndInvalidate()
          session = nil
        }
        return self.continuation
      }
      continuation?.resume(with: result)
    }
  }
#endif
