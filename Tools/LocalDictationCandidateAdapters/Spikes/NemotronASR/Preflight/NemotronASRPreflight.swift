import Foundation
import NemotronASRSpikeContract

public enum NemotronASRBackend: String, CaseIterable, Equatable, Sendable {
  case cpu
  case metal
}

public enum NemotronASRPathKind: String, Equatable, Sendable {
  case runtime
  case model
  case helper
}

public struct NemotronASRPreflightArguments: Equatable, Sendable {
  public let backend: NemotronASRBackend
  public let runtimePath: String
  public let modelPath: String
  public let helperPath: String

  public init(
    backend: NemotronASRBackend,
    runtimePath: String,
    modelPath: String,
    helperPath: String
  ) throws {
    try Self.requireAbsoluteLocalPath(runtimePath, field: "runtime-path")
    try Self.requireAbsoluteLocalPath(modelPath, field: "model-path")
    try Self.requireAbsoluteLocalPath(helperPath, field: "helper-path")
    self.backend = backend
    self.runtimePath = runtimePath
    self.modelPath = modelPath
    self.helperPath = helperPath
  }

  private static func requireAbsoluteLocalPath(
    _ path: String,
    field: String
  ) throws {
    guard path.hasPrefix("/"), !path.contains("://") else {
      throw NemotronASRPreflightError.invalidArgument(field)
    }
  }
}

public struct NemotronASRCapabilityMetadata: Equatable, Sendable {
  public let intendedSupportsStreaming: Bool
  public let intendedSupportsInterimResults: Bool
  public let intendedEvaluationLocales: [String]
  public let emitsReady: Bool
  public let emitsPartial: Bool
  public let emitsFinal: Bool
  public let supportsCancellation: Bool
  public let supportsContext: Bool
  public let supportsNativeExecution: Bool
}

public enum NemotronASRPreflightError: Error, Equatable, CustomStringConvertible, Sendable {
  case invalidArgument(String)
  case invalidBackend(String)
  case runtimeIdentityUnavailable
  case nativeExecutionUnavailable

  public var description: String {
    switch self {
    case .invalidArgument(let field):
      return "invalid-argument:\(field)"
    case .invalidBackend(let backend):
      return "invalid-backend:\(backend)"
    case .runtimeIdentityUnavailable:
      return "artifact-identity-unadmitted/runtime-identity-unavailable"
    case .nativeExecutionUnavailable:
      return "native-execution-unavailable"
    }
  }
}

public enum NemotronASRPreflight {
  public static let capabilityMetadata = NemotronASRCapabilityMetadata(
    intendedSupportsStreaming: true,
    intendedSupportsInterimResults: true,
    intendedEvaluationLocales: ["en", "zh"],
    emitsReady: false,
    emitsPartial: false,
    emitsFinal: false,
    supportsCancellation: false,
    supportsContext: false,
    supportsNativeExecution: false
  )

  public static func parse(
    arguments: [String]
  ) throws -> NemotronASRPreflightArguments {
    var values: [String: String] = [:]
    var index = 1
    while index < arguments.count {
      guard index + 1 < arguments.count else {
        throw NemotronASRPreflightError.invalidArgument("value")
      }
      let flag = arguments[index]
      guard ["--backend", "--runtime-path", "--model-path", "--helper-path"].contains(flag),
        values[flag] == nil,
        !arguments[index + 1].isEmpty
      else {
        throw NemotronASRPreflightError.invalidArgument(flag)
      }
      values[flag] = arguments[index + 1]
      index += 2
    }

    guard let backendValue = values["--backend"] else {
      throw NemotronASRPreflightError.invalidArgument("backend")
    }
    guard let backend = NemotronASRBackend(rawValue: backendValue) else {
      throw NemotronASRPreflightError.invalidBackend(backendValue)
    }
    guard let runtimePath = values["--runtime-path"],
      let modelPath = values["--model-path"],
      let helperPath = values["--helper-path"]
    else {
      throw NemotronASRPreflightError.invalidArgument("runtime-model-helper")
    }

    return try NemotronASRPreflightArguments(
      backend: backend,
      runtimePath: runtimePath,
      modelPath: modelPath,
      helperPath: helperPath
    )
  }

  public static func evaluate(
    metadata: NemotronASRMetadata,
    arguments: NemotronASRPreflightArguments,
    resolvePath: (NemotronASRPathKind, String) throws -> Void,
    loadNative: () throws -> Void
  ) throws {
    do {
      try metadata.sourceRuntime.compiledRuntime.requireAdmitted()
    } catch NemotronRuntimeAdmissionError.compiledRuntimeIdentityUnavailable {
      throw NemotronASRPreflightError.runtimeIdentityUnavailable
    }

    try resolvePath(.runtime, arguments.runtimePath)
    try resolvePath(.model, arguments.modelPath)
    try resolvePath(.helper, arguments.helperPath)
    try loadNative()
  }

  public static func run(arguments: [String]) throws {
    let inputs = try parse(arguments: arguments)

    // These are inert future boundaries. Current metadata must fail before either is reached.
    try evaluate(
      metadata: .candidate,
      arguments: inputs,
      resolvePath: { _, _ in throw NemotronASRPreflightError.nativeExecutionUnavailable },
      loadNative: { throw NemotronASRPreflightError.nativeExecutionUnavailable }
    )
  }
}
