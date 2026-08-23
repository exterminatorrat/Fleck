#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation

@MainActor
enum GemmaCleanupTestActivation {
  struct Result {
    let manager: EnhancedModelManager
    let installer: any AdmittedModelInstalling
    let helperExecutableURL: URL
    let makeTransport: @Sendable (URL) -> any GemmaCleanupTransport
  }

  typealias ConfigurationFactory = @MainActor (
    URL,
    ConfigurationHooks
  ) throws -> AdmittedModelSignedConfiguration

  typealias RuntimeProbe = @MainActor @Sendable (URL, URL) async throws -> Void

  struct ConfigurationHooks {
    let startup: @MainActor () async throws -> Void
    let calibrate: @MainActor () async throws -> Void
    let modelMutationWillBegin: @Sendable () async -> Void
  }

  private static let constructionFailureMessage =
    "Enhanced cleanup could not be activated. Fleck will use faithful deterministic cleanup. "
      + "Verify the packaged Gemma helper and restart Fleck."

  private static let runtimeFailureMessage =
    "Fleck could not verify the local cleanup model. Repair the Gemma cleanup model in Settings and try again."

  private static let probeBaseline = "Hello world."
  private static let probeTimeout: Duration = .seconds(90)

  private enum RuntimeError: Error {
    case repositoryUnavailable
    case repositoryChanged
    case missingProof
  }

  @MainActor
  private final class Runtime {
    let helperExecutableURL: URL
    let probe: RuntimeProbe
    weak var manager: EnhancedModelManager?
    private var proofRepositoryURL: URL?

    init(
      helperExecutableURL: URL,
      probe: @escaping RuntimeProbe
    ) {
      self.helperExecutableURL = helperExecutableURL
      self.probe = probe
    }

    func startup() async throws {
      proofRepositoryURL = nil
      guard
        let manager,
        case .ready(let repositoryURL) = manager.verifiedLoadState
      else {
        throw RuntimeError.repositoryUnavailable
      }

      do {
        try await probe(helperExecutableURL, repositoryURL)
        try Task.checkCancellation()
        guard
          case .ready(let currentRepositoryURL) = manager.verifiedLoadState,
          currentRepositoryURL == repositoryURL
        else {
          throw RuntimeError.repositoryChanged
        }
        proofRepositoryURL = repositoryURL
      } catch {
        proofRepositoryURL = nil
        markRepairIfNeeded(
          manager: manager,
          failedRepositoryURL: repositoryURL,
          error: error
        )
        throw error
      }
    }

    func calibrate() async throws {
      guard let manager, let proofRepositoryURL else {
        throw RuntimeError.missingProof
      }
      do {
        try Task.checkCancellation()
        guard
          case .ready(let currentRepositoryURL) = manager.verifiedLoadState,
          currentRepositoryURL == proofRepositoryURL
        else {
          throw RuntimeError.repositoryChanged
        }
      } catch {
        markRepairIfNeeded(
          manager: manager,
          failedRepositoryURL: proofRepositoryURL,
          error: error
        )
        throw error
      }
    }

    private func markRepairIfNeeded(
      manager: EnhancedModelManager,
      failedRepositoryURL: URL,
      error: Error
    ) {
      guard !(error is CancellationError), !Task.isCancelled else { return }
      let currentRepositoryURL: URL
      if case .ready(let current) = manager.verifiedLoadState {
        currentRepositoryURL = current
      } else {
        currentRepositoryURL = failedRepositoryURL
      }
      manager.markInferenceLoadFailure(
        message: GemmaCleanupTestActivation.runtimeFailureMessage,
        failedRepositoryURL: currentRepositoryURL
      )
    }
  }

  static func make(
    applicationSupportURL: URL,
    bundleURL: URL = Bundle.main.bundleURL,
    modelMutationWillBegin: @escaping @Sendable () async -> Void = {},
    configurationFactory: @escaping ConfigurationFactory = { baseRoot, hooks in
      try GemmaCleanupTestConfiguration.make(
        admittedBaseRoot: baseRoot,
        modelMutationWillBegin: hooks.modelMutationWillBegin,
        startup: hooks.startup,
        calibrate: hooks.calibrate
      )
    },
    probe: RuntimeProbe? = nil
  ) -> Result {
    let admittedBaseRoot = applicationSupportURL
      .appendingPathComponent("CleanupModels", isDirectory: true)
    let helperExecutableURL = bundleURL
      .appendingPathComponent(
        "Contents/SharedSupport/gemma-cleanup-helper",
        isDirectory: false
      )
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let selectedProbe = probe ?? liveProbe
    let runtime = Runtime(
      helperExecutableURL: helperExecutableURL,
      probe: selectedProbe
    )
    let makeTransport: @Sendable (URL) -> any GemmaCleanupTransport = {
      repositoryURL in
      GemmaCleanupProcessTransport(
        helperExecutableURL: helperExecutableURL,
        modelDirectoryURL: repositoryURL
      )
    }

    do {
      let configuration = try configurationFactory(
        admittedBaseRoot,
        ConfigurationHooks(
          startup: { try await runtime.startup() },
          calibrate: { try await runtime.calibrate() },
          modelMutationWillBegin: modelMutationWillBegin
        )
      )
      runtime.manager = configuration.manager
      return Result(
        manager: configuration.manager,
        installer: makeAdmittedModelInstaller(
          signedConfiguration: configuration,
          expectedRole: .cleanup
        ),
        helperExecutableURL: helperExecutableURL,
        makeTransport: makeTransport
      )
    } catch {
      return Result(
        manager: EnhancedModelManager(
          modelRootURL: admittedBaseRoot,
          candidateEnabled: false
        ),
        installer: FailedAdmittedModelInstaller(
          recommendation: .builtIn,
          message: constructionFailureMessage
        ),
        helperExecutableURL: helperExecutableURL,
        makeTransport: makeTransport
      )
    }
  }

  private static func liveProbe(
    helperExecutableURL: URL,
    repositoryURL: URL
  ) async throws {
    let transport = GemmaCleanupProcessTransport(
      helperExecutableURL: helperExecutableURL,
      modelDirectoryURL: repositoryURL
    )
    let generator = GemmaCleanupGenerator(
      transportFactory: { transport }
    )
    let clock = ContinuousClock()
    let session = try generator.start(
      IncrementalCleanupRequest(
        baseline: probeBaseline,
        protectedForms: [],
        replacements: 0,
        deadline: clock.now.advanced(by: probeTimeout)
      ),
      maximumOutputTokens: 32
    )

    do {
      try await withTaskCancellationHandler(operation: {
        _ = try await session.result()
        try Task.checkCancellation()
      }, onCancel: {
        session.requestCancellation()
      })
      await session.acknowledgement()
    } catch {
      session.requestCancellation()
      await session.acknowledgement()
      throw error
    }
  }
}
#endif
