import Testing
@testable import WhisperASRPreflight

private func whisperPreflightArguments(
  backend: String = "metal",
  runtimePath: String = "/prospective/runtime",
  modelPath: String = "/prospective/model",
  helperPath: String = "/prospective/helper"
) throws -> WhisperASRPreflightArguments {
  try WhisperASRPreflight.parse(arguments: [
    "whisper-asr-preflight",
    "--backend", backend,
    "--runtime-path", runtimePath,
    "--model-path", modelPath,
    "--helper-path", helperPath,
  ])
}

@Test func whisperPreflightAcceptsOnlyMetalBackend() throws {
  #expect(try whisperPreflightArguments().backend == .metal)

  var capturedError: WhisperASRPreflightError?
  do {
    _ = try whisperPreflightArguments(backend: "cpu")
  } catch let error as WhisperASRPreflightError {
    capturedError = error
  }
  #expect(capturedError == .invalidBackend("cpu"))
}

@Test func whisperPreflightAcceptsOnlyAbsoluteLocalProspectivePaths() throws {
  var relativeError: WhisperASRPreflightError?
  do {
    _ = try whisperPreflightArguments(runtimePath: "relative/runtime")
  } catch let error as WhisperASRPreflightError {
    relativeError = error
  }
  #expect(relativeError == .invalidArgument("runtime-path"))

  var urlError: WhisperASRPreflightError?
  do {
    _ = try whisperPreflightArguments(modelPath: "https" + "://example.invalid/model")
  } catch let error as WhisperASRPreflightError {
    urlError = error
  }
  #expect(urlError == .invalidArgument("model-path"))
}

@Test func whisperUnadmittedFailurePrecedesPathResolutionAndNativeLoad() throws {
  let arguments = try whisperPreflightArguments()
  var pathProbeCount = 0
  var nativeLoadCount = 0

  var capturedError: WhisperASRPreflightError?
  do {
    try WhisperASRPreflight.evaluate(
      metadata: .candidate,
      arguments: arguments,
      resolvePath: { _, _ in pathProbeCount += 1 },
      loadNative: { nativeLoadCount += 1 }
    )
  } catch let error as WhisperASRPreflightError {
    capturedError = error
  }

  #expect(capturedError == .runtimeIdentityUnavailable)
  #expect(pathProbeCount == 0)
  #expect(nativeLoadCount == 0)
}

@Test func whisperCommandFailureUsesStableRuntimeIdentityError() throws {
  let arguments = try whisperPreflightArguments(
    runtimePath: "/does/not/exist/runtime",
    modelPath: "/does/not/exist/model",
    helperPath: "/does/not/exist/helper"
  )

  var capturedError: WhisperASRPreflightError?
  do {
    try WhisperASRPreflight.run(arguments: [
      "whisper-asr-preflight",
      "--backend", arguments.backend.rawValue,
      "--runtime-path", arguments.runtimePath,
      "--model-path", arguments.modelPath,
      "--helper-path", arguments.helperPath,
    ])
  } catch let error as WhisperASRPreflightError {
    capturedError = error
  }

  #expect(capturedError?.description == "artifact-identity-unadmitted/runtime-identity-unavailable")
}

@Test func whisperPreflightDoesNotAcceptCallerSuppliedExecutable() {
  var capturedError: WhisperASRPreflightError?
  do {
    _ = try WhisperASRPreflight.parse(arguments: [
      "whisper-asr-preflight",
      "--preflight", "/tmp/fake-preflight",
    ])
  } catch let error as WhisperASRPreflightError {
    capturedError = error
  } catch {
    Issue.record("unexpected error: \(error)")
  }

  #expect(capturedError == .invalidArgument("--preflight"))
}

@Test func whisperCapabilityMetadataSeparatesFutureFinalOnlyIntentFromCurrentPreflight() {
  let capabilities = WhisperASRPreflight.capabilityMetadata

  #expect(capabilities.intendedResultSemantics == "batch-final-only")
  #expect(!capabilities.intendedSupportsStreaming)
  #expect(!capabilities.intendedSupportsRollingPartials)
  #expect(capabilities.intendedEvaluationCases == ["en", "zh", "mixed"])
  #expect(!capabilities.emitsReady)
  #expect(!capabilities.emitsPartial)
  #expect(!capabilities.emitsFinal)
  #expect(!capabilities.supportsCancellation)
  #expect(!capabilities.supportsContext)
  #expect(!capabilities.supportsNativeExecution)
}
