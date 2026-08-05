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
  #expect(plist["LSUIElement"] as? Bool == true)
  #expect(StatusItemContextMenuController.quitTitle == "Quit Fleck")

  let appSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )
  #expect(appSource.contains("fleck-mark.png"))
  #expect(appSource.contains("FleckMark.image(template: true)"))
  #expect(appSource.contains("MenuBarExtra"))
  #expect(appSource.contains("accessibilityLabel(\"Fleck\")"))
  #expect(appSource.contains(#"Window("Fleck""#))
  let notesPanelSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  #expect(notesPanelSource.contains("FleckMark.image(template: false)"))
}

@Test func agentConnectorDocumentationUsesPackagedLaunch() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let documentationNames = [
    "README.md",
    "TESTING.md",
    "IMPLEMENTATION_STATUS.md",
  ]
  let documentation = try documentationNames.map {
    try String(
      contentsOf: root.appendingPathComponent($0),
      encoding: .utf8
    )
  }
  let testing = try String(
    contentsOf: root.appendingPathComponent("TESTING.md"),
    encoding: .utf8
  )
  let sources = try sourceText(in: root.appendingPathComponent("Sources"))

  #expect(documentation.allSatisfy { $0.contains("Agent Connector") })
  #expect(testing.contains("Scripts/build-fleck-app.sh"))
  #expect(testing.contains("/usr/bin/open -n .build/Fleck.app"))
  #expect(!testing.contains("swift run Fleck"))
  #expect(!testing.contains("Product → Run"))
  #expect(
    (documentation + [sources]).allSatisfy {
      !$0.localizedCaseInsensitiveContains("command bridge")
    }
  )
}

@Test func packagedDevelopmentBuildUsesStableFleckCodeIdentity() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let buildScript = try String(
    contentsOf: root.appendingPathComponent("Scripts/build-fleck-app.sh"),
    encoding: .utf8
  )
  let validationScript = try String(
    contentsOf: root.appendingPathComponent("Scripts/validate-macos.sh"),
    encoding: .utf8
  )

  #expect(buildScript.contains(#"--identifier "$bundle_identifier""#))
  #expect(buildScript.contains(#"designated => identifier \"$bundle_identifier\""#))
  #expect(buildScript.contains(#"/usr/bin/codesign --verify --deep --strict "$staged_app""#))
  #expect(!buildScript.contains("Built unsigned app bundle"))
  #expect(buildScript.contains("website/public/fleck-mark.png"))
  #expect(buildScript.contains("Contents/Resources/fleck-mark.png"))
  #expect(validationScript.contains("signature identifier does not match bundle identifier"))
  #expect(validationScript.contains("signature uses a build-specific code hash"))
  #expect(validationScript.contains("Contents/Resources/fleck-mark.png"))
  #expect(validationScript.contains("LSUIElement"))
}

private func sourceText(in root: URL) throws -> String {
  guard
    let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey]
    )
  else { return "" }
  var result = ""
  for case let file as URL in enumerator
  where file.pathExtension == "swift" {
    result += try String(contentsOf: file, encoding: .utf8)
  }
  return result
}
