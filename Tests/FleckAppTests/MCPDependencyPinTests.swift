import Foundation
import Testing

@Test func enhancedCandidateManifestPinsReviewedTransitiveReleases() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let manifest = try String(
    contentsOf: root.appendingPathComponent("Package.swift"),
    encoding: .utf8
  )
  let candidateDependencies = try #require(
    manifest.components(separatedBy: "if enhancedCandidateEnabled {").last
  )

  #expect(
    candidateDependencies.contains(
      #".package(url: "https://github.com/apple/swift-system.git", exact: "1.7.5")"#
    )
  )
  #expect(
    candidateDependencies.contains(
      #".package(url: "https://github.com/apple/swift-log.git", exact: "1.14.0")"#
    )
  )
}

@Test func mcpDependencyAndNoticeArePinned() throws {
  let mcpRevision = "a0ae212ebf6eab5f754c3129608bc5557637e605"
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let manifest = try String(
    contentsOf: root.appendingPathComponent("Package.swift"),
    encoding: .utf8
  )
  #expect(manifest.contains(#"name: "Fleck""#))
  #expect(manifest.contains(#".library(name: "FleckCore""#))
  #expect(manifest.contains(#"name: "FleckAgentProtocol""#))
  #expect(manifest.contains(#".executable(name: "Fleck""#))
  #expect(manifest.contains(#".executable(name: "fleck-agent""#))
  let legacyProductName = "Mo" + "tes"
  let legacyModulePrefix = "MenuBar" + "Notes"
  #expect(!manifest.contains("name: \"\(legacyProductName)\""))
  #expect(!manifest.contains("name: \"\(legacyModulePrefix)Core\""))
  #expect(!manifest.contains("name: \"\(legacyModulePrefix)AgentProtocol\""))
  #expect(!manifest.contains("name: \"\(legacyModulePrefix)App\""))
  #expect(!manifest.contains("name: \"\(legacyProductName)AgentBridge\""))
  #expect(
    manifest.contains(
      #"url: "https://github.com/modelcontextprotocol/swift-sdk.git""#
    )
  )
  #expect(
    manifest.contains(
      "revision: \"\(mcpRevision)\""
    )
  )

  let resolved = try JSONDecoder().decode(
    ResolvedFile.self,
    from: Data(contentsOf: root.appendingPathComponent("Package.resolved"))
  )
  let pins = Dictionary(
    uniqueKeysWithValues: resolved.pins.map { ($0.identity, $0.state) }
  )
  var expectedPins: [String: ResolvedState] = [
    "eventsource": .init(
      revision: "a3a85a85214caf642abaa96ae664e4c772a59f6e",
      version: "1.4.1"
    ),
    "swift-atomics": .init(
      revision: "0442cb5a3f98ab802acb777929fdb446bda11a34",
      version: "1.3.1"
    ),
    "swift-collections": .init(
      revision: "a0cb0954ecb21e4e31b0070e6ed5674e8556685a",
      version: "1.6.0"
    ),
    "swift-log": .init(
      revision: "a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a",
      version: "1.14.0"
    ),
    "swift-nio": .init(
      revision: "0b18836bd8b0162e7e17a995a3fbee20ed8f3b2b",
      version: "2.101.3"
    ),
    "swift-sdk": .init(
      revision: mcpRevision,
      version: nil
    ),
    "swift-system": .init(
      revision: "50688cacbd41d547e9eb9f7a213542340b7c442b",
      version: "1.7.5"
    ),
  ]
  if ProcessInfo.processInfo.environment["FLECK_ENHANCED_CANDIDATE"] == "1" {
    expectedPins["fluidaudio"] = .init(
      revision: "19600a485baa4998812e4654b70d2bab8f2c9949",
      version: nil
    )
  }
  #expect(pins == expectedPins)

  let notices = try String(
    contentsOf: root.appendingPathComponent(
      "Sources/FleckApp/Resources/ThirdPartyNotices.md"
    ),
    encoding: .utf8
  )
  #expect(notices.contains("modelcontextprotocol/swift-sdk"))
  #expect(notices.contains("| Model Context Protocol Swift SDK | `\(mcpRevision)` |"))
  #expect(notices.contains("swift-sdk/blob/\(mcpRevision)/LICENSE"))
  #expect(notices.contains("Apache-2.0, unrelicensed MIT contributions, and CC BY 4.0 documentation"))
  #expect(notices.contains("Copyright 2024-2025 Model Context Protocol a Series of LF Projects, LLC."))
}

private struct ResolvedFile: Decodable {
  let pins: [ResolvedPin]
}

private struct ResolvedPin: Decodable {
  let identity: String
  let state: ResolvedState
}

private struct ResolvedState: Decodable, Equatable {
  let revision: String
  let version: String?
}
