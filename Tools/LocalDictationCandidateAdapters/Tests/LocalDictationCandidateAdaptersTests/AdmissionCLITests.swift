import CryptoKit
import Foundation
import Testing
@testable import LocalDictationCandidateCLI

@Test func reportHashMappingSeparatesRuntimeAndModelRoots() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    .appendingPathComponent("qwen-cli-hash-mapping-\(UUID().uuidString)", isDirectory: true)
  let runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
  let modelRoot = root.appendingPathComponent("model", isDirectory: true)
  try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let runtimeData = Data("runtime-identity".utf8)
  let modelData = Data("model-identity".utf8)
  try runtimeData.write(to: runtimeRoot.appendingPathComponent("runtime.bin"))
  try modelData.write(to: modelRoot.appendingPathComponent("model.bin"))

  let mapping = try reportHashMapping(runtimeRootURL: runtimeRoot, modelRootURL: modelRoot)
  let runtimeHash = SHA256.hash(data: runtimeData).map { String(format: "%02x", $0) }.joined()
  let modelHash = SHA256.hash(data: modelData).map { String(format: "%02x", $0) }.joined()

  #expect(mapping.libraryHashes == ["runtime.bin": runtimeHash])
  #expect(mapping.modelHashes == ["model.bin": modelHash])
}

@Test func qwenEvaluationContextIsMetadataOnly() {
  let plan = evaluationContextPlan(for: ["Fleck", "SwiftUI"])
  #expect(plan.evaluationOnlyPhrases == ["Fleck", "SwiftUI"])
  #expect(plan.appliedPhrases.isEmpty)
}

@Test func cancellationReportStatusRequiresCooperativeCancellation() throws {
  #expect(try cancellationCaseStatus(for: .cooperativeCancellation) == "cancelled")
  #expect(throws: CLIError.self) {
    _ = try cancellationCaseStatus(for: .cooperativeShutdown)
  }
  #expect(throws: CLIError.self) {
    _ = try cancellationCaseStatus(for: .forcedTermination)
  }
}

@Test func successfulReportRequiresCooperativeShutdown() throws {
  try requireCooperativeShutdown(.cooperativeShutdown)
  #expect(throws: CLIError.self) {
    try requireCooperativeShutdown(.forcedTermination)
  }
}
