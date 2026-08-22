import Foundation

public struct QwenASRHelperDescriptor: Equatable, Sendable {
  public let executablePath: String
  public let arguments: [String]

  public init(executablePath: String, arguments: [String] = []) {
    self.executablePath = executablePath
    self.arguments = arguments
  }
}

public enum QwenASRPreflightError: Error, Equatable, CustomStringConvertible {
  case invalidArgument(String)
  case helperUnavailable

  public var description: String {
    switch self {
    case .invalidArgument(let field): return "invalid-argument:\(field)"
    case .helperUnavailable: return "native-helper-unavailable"
    }
  }
}

public enum QwenASRPreflight {
  public static func launchIfAdmitted(
    manifest: ArtifactManifest,
    descriptor: QwenASRHelperDescriptor,
    launch: (QwenASRHelperDescriptor) throws -> Void
  ) throws {
    try manifest.requireAdmitted()
    try launch(descriptor)
  }

  public static func run(arguments: [String]) throws {
    let inputs = try Inputs(arguments: arguments)
    let descriptor = QwenASRHelperDescriptor(executablePath: inputs.helperPath)

    // The injected closure is the only future helper boundary. Admission is
    // deliberately evaluated before it can resolve or invoke that boundary.
    try launchIfAdmitted(
      manifest: QwenASRArtifactManifests.sherpa,
      descriptor: descriptor
    ) { _ in
      _ = try StartupPathPolicy.requireLocalDirectory(inputs.runtimeRoot, field: "runtime-root")
      _ = try StartupPathPolicy.requireLocalDirectory(inputs.modelRoot, field: "model-root")
      throw QwenASRPreflightError.helperUnavailable
    }
  }

  private struct Inputs {
    let runtimeRoot: String
    let modelRoot: String
    let helperPath: String

    init(arguments: [String]) throws {
      var values: [String: String] = [:]
      var index = 1
      while index < arguments.count {
        guard index + 1 < arguments.count else {
          throw QwenASRPreflightError.invalidArgument("value")
        }
        let flag = arguments[index]
        guard ["--runtime-root", "--model-root", "--helper-path"].contains(flag),
          values[flag] == nil,
          !arguments[index + 1].isEmpty
        else {
          throw QwenASRPreflightError.invalidArgument(flag)
        }
        values[flag] = arguments[index + 1]
        index += 2
      }
      guard let runtimeRoot = values["--runtime-root"],
        let modelRoot = values["--model-root"],
        let helperPath = values["--helper-path"]
      else {
        throw QwenASRPreflightError.invalidArgument("runtime-model-helper")
      }
      self.runtimeRoot = runtimeRoot
      self.modelRoot = modelRoot
      self.helperPath = helperPath
    }
  }
}
