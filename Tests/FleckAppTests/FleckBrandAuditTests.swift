import Foundation
import Testing

@testable import FleckApp

@MainActor
@Test func canonicalBundleAndVisibleIdentityAreFleck() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let plistURL = root.appendingPathComponent("Sources/FleckApp/Info.plist")
  let plist = try #require(
    PropertyListSerialization.propertyList(
      from: Data(contentsOf: plistURL),
      format: nil
    ) as? [String: Any]
  )

  #expect(plist["CFBundleDisplayName"] as? String == "Fleck")
  #expect(plist["CFBundleExecutable"] as? String == "Fleck")
  #expect(plist["CFBundleIdentifier"] as? String == "com.harryjin.fleck")
  #expect(plist["CFBundleName"] as? String == "Fleck")
  #expect(StatusItemContextMenuController.quitTitle == "Quit Fleck")

  let appSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )
  #expect(appSource.contains(#"MenuBarExtra("Fleck""#))
  #expect(appSource.contains(#"Window("Fleck""#))
}
