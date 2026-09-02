import Testing
@testable import NemotronASRPreflight

private func preflightArguments(
  backend: String = "cpu",
  runtimePath: String = "/prospective/runtime",
  modelPath: String = "/prospective/model",
  helperPath: String = "/prospective/helper"
) throws -> NemotronASRPreflightArguments {
  try NemotronASRPreflight.parse(arguments: [
    "nemotron-asr-preflight",
    "--backend", backend,
    "--runtime-path", runtimePath,
    "--model-path", modelPath,
    "--helper-path", helperPath,
  ])
}

@Test func nemotronPreflightAcceptsOnlyCPUAndMetalBackends() throws {
  #expect(try preflightArguments(backend: "cpu").backend == .cpu)
  #expect(try preflightArguments(backend: "metal").backend == .metal)

  var capturedError: NemotronASRPreflightError?
  do {
    _ = try preflightArguments(backend: "gpu")
  } catch let error as NemotronASRPreflightError {
    capturedError = error
  }
  #expect(capturedError == .invalidBackend("gpu"))
}

@Test func nemotronPreflightAcceptsOnlyAbsoluteLocalProspectivePaths() throws {
  var relativeError: NemotronASRPreflightError?
  do {
    _ = try preflightArguments(runtimePath: "relative/runtime")
  } catch let error as NemotronASRPreflightError {
    relativeError = error
  }
  #expect(relativeError == .invalidArgument("runtime-path"))

  var urlError: NemotronASRPreflightError?
  do {
    _ = try preflightArguments(modelPath: "https" + "://" + "example.invalid/model")
  } catch let error as NemotronASRPreflightError {
    urlError = error
  }
  #expect(urlError == .invalidArgument("model-path"))
}

@Test func nemotronUnadmittedFailurePrecedesPathResolutionAndNativeLoad() throws {
  let arguments = try preflightArguments()
  var pathProbeCount = 0
  var nativeLoadCount = 0

  var capturedError: NemotronASRPreflightError?
  do {
    try NemotronASRPreflight.evaluate(
      metadata: .candidate,
      arguments: arguments,
      resolvePath: { _, _ in pathProbeCount += 1 },
      loadNative: { nativeLoadCount += 1 }
    )
  } catch let error as NemotronASRPreflightError {
    capturedError = error
  }

  #expect(capturedError == .runtimeIdentityUnavailable)
  #expect(pathProbeCount == 0)
  #expect(nativeLoadCount == 0)
}

@Test func nemotronCommandFailureUsesStableRuntimeIdentityError() throws {
  let arguments = try preflightArguments(
    runtimePath: "/does/not/exist/runtime",
    modelPath: "/does/not/exist/model",
    helperPath: "/does/not/exist/helper"
  )

  var capturedError: NemotronASRPreflightError?
  do {
    try NemotronASRPreflight.run(arguments: [
      "nemotron-asr-preflight",
      "--backend", arguments.backend.rawValue,
      "--runtime-path", arguments.runtimePath,
      "--model-path", arguments.modelPath,
      "--helper-path", arguments.helperPath,
    ])
  } catch let error as NemotronASRPreflightError {
    capturedError = error
  }

  #expect(capturedError?.description == "artifact-identity-unadmitted/runtime-identity-unavailable")
}

@Test func nemotronPreflightDoesNotAcceptCallerSuppliedExecutable() {
  var capturedError: NemotronASRPreflightError?
  do {
    _ = try NemotronASRPreflight.parse(arguments: [
      "nemotron-asr-preflight",
      "--preflight", "/tmp/fake-preflight",
    ])
  } catch let error as NemotronASRPreflightError {
    capturedError = error
  } catch {
    Issue.record("unexpected error: \(error)")
  }

  #expect(capturedError == .invalidArgument("--preflight"))
}

@Test func nemotronCapabilityMetadataSeparatesFutureIntentFromCurrentPreflight() {
  let capabilities = NemotronASRPreflight.capabilityMetadata

  #expect(capabilities.intendedSupportsStreaming)
  #expect(capabilities.intendedSupportsInterimResults)
  #expect(capabilities.intendedEvaluationLocales == ["en", "zh"])
  #expect(!capabilities.emitsReady)
  #expect(!capabilities.emitsPartial)
  #expect(!capabilities.emitsFinal)
  #expect(!capabilities.supportsCancellation)
  #expect(!capabilities.supportsContext)
  #expect(!capabilities.supportsNativeExecution)
}
