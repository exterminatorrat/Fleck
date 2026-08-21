#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import FleckEnhancedCandidateDependencies
import Foundation

@MainActor
enum ParakeetTDTTestActivation {
  struct Result {
    let manager: EnhancedModelManager
    let installer: any AdmittedModelInstalling
  }

  typealias ConfigurationFactory = @MainActor (
    URL,
    ConfigurationHooks
  ) throws -> AdmittedModelSignedConfiguration

  typealias InferenceFactory = @MainActor () -> any EnhancedSpeechInferring

  struct ConfigurationHooks {
    let startup: @MainActor () async throws -> Void
    let calibrate: @MainActor () async throws -> Void
  }

  static let calibrationSampleCount = 4_000

  private static let constructionFailureMessage =
    "Enhanced Local could not be activated. Fleck continues with Apple Speech. "
      + "Verify the signed Parakeet configuration and restart Fleck."

  private static let runtimeFailureMessage =
    "Enhanced Local could not verify the local Parakeet model. Fleck continues "
      + "with Apple Speech. Repair the admitted model in Dictation Settings and "
      + "restart Fleck."

  private enum RuntimeError: Error {
    case repositoryUnavailable
    case repositoryChanged
  }

  private enum RunPhase: Equatable {
    case startup
    case calibration
  }

  private final class InferenceCancellation: @unchecked Sendable {
    let inference: any EnhancedSpeechInferring

    init(inference: any EnhancedSpeechInferring) {
      self.inference = inference
    }

    func request() {
      let inference = inference
      Task { @MainActor in
        await inference.cancel()
      }
    }
  }

  @MainActor
  private final class Runtime {
    let makeInference: InferenceFactory
    weak var manager: EnhancedModelManager?

    init(makeInference: @escaping InferenceFactory) {
      self.makeInference = makeInference
    }

    func startup() async throws {
      try await run(.startup)
    }

    func calibrate() async throws {
      try await run(.calibration)
    }

    private func run(_ phase: RunPhase) async throws {
      guard
        let manager,
        case .ready(let repositoryURL) = manager.verifiedLoadState
      else {
        throw RuntimeError.repositoryUnavailable
      }

      let inference = makeInference()
      let cancellation = InferenceCancellation(inference: inference)
      do {
        ModelHub.offlineMode = true
        try await withTaskCancellationHandler(operation: {
          try await inference.load(from: repositoryURL)
          try Task.checkCancellation()
          if phase == .calibration {
            _ = try await inference.transcribe(
              [Float](
                repeating: 0,
                count: ParakeetTDTTestActivation.calibrationSampleCount
              )
            )
          }
          try Task.checkCancellation()
        }, onCancel: {
          cancellation.request()
        })
        guard
          case .ready(let currentRepositoryURL) = manager.verifiedLoadState,
          currentRepositoryURL == repositoryURL
        else {
          throw RuntimeError.repositoryChanged
        }
      } catch {
        await inference.cancel()
        await inference.releaseResources()
        if !(error is CancellationError), !Task.isCancelled {
          manager.markInferenceLoadFailure(
            message: ParakeetTDTTestActivation.runtimeFailureMessage,
            failedRepositoryURL: repositoryURL
          )
        }
        throw error
      }
      await inference.releaseResources()
    }
  }

  static func make(
    applicationSupportURL: URL,
    configurationFactory: @escaping ConfigurationFactory = { baseRoot, hooks in
      try ParakeetTDTTestConfiguration.make(
        admittedBaseRoot: baseRoot,
        startup: hooks.startup,
        calibrate: hooks.calibrate
      )
    },
    makeInference: @escaping InferenceFactory = {
      FluidEnhancedSpeechInference()
    }
  ) -> Result {
    let admittedBaseRoot = applicationSupportURL
      .appendingPathComponent("DictationModels", isDirectory: true)
    let runtime = Runtime(makeInference: makeInference)

    do {
      let configuration = try configurationFactory(
        admittedBaseRoot,
        ConfigurationHooks(
          startup: { try await runtime.startup() },
          calibrate: { try await runtime.calibrate() }
        )
      )
      runtime.manager = configuration.manager
      return Result(
        manager: configuration.manager,
        installer: makeAdmittedModelInstaller(
          signedConfiguration: configuration
        )
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
        )
      )
    }
  }
}
#endif
