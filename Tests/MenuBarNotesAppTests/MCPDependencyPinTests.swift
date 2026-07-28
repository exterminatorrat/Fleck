import Foundation
import Testing

@Test func mcpDependencyAndNoticeArePinned() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let manifest = try String(
    contentsOf: root.appendingPathComponent("Package.swift"),
    encoding: .utf8
  )
  #expect(
    manifest.contains(
      #"url: "https://github.com/modelcontextprotocol/swift-sdk.git""#
    )
  )
  #expect(
    manifest.contains(
      #"revision: "a0ae212ebf6eab5f754c3129608bc5557637e605""#
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
      revision: "a0ae212ebf6eab5f754c3129608bc5557637e605",
      version: nil
    ),
    "swift-system": .init(
      revision: "50688cacbd41d547e9eb9f7a213542340b7c442b",
      version: "1.7.5"
    ),
  ]
  if ProcessInfo.processInfo.environment["MOTES_ENHANCED_CANDIDATE"] == "1" {
    expectedPins["fluidaudio"] = .init(
      revision: "19600a485baa4998812e4654b70d2bab8f2c9949",
      version: nil
    )
  }
  #expect(pins == expectedPins)

  let notices = try String(
    contentsOf: root.appendingPathComponent(
      "Sources/MenuBarNotesApp/Resources/ThirdPartyNotices.md"
    ),
    encoding: .utf8
  )
  #expect(notices.contains("modelcontextprotocol/swift-sdk"))
  #expect(notices.contains("0.12.1"))
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
