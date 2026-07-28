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

  let notices = try String(
    contentsOf: root.appendingPathComponent(
      "Sources/MenuBarNotesApp/Resources/ThirdPartyNotices.md"
    ),
    encoding: .utf8
  )
  #expect(notices.contains("modelcontextprotocol/swift-sdk"))
  #expect(notices.contains("0.12.1"))
}
