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
  #expect(appSource.contains("FleckMark.load(template: true)"))
  #expect(appSource.contains("MenuBarExtra"))
  #expect(appSource.contains("accessibilityLabel(\"Fleck\")"))
  #expect(appSource.contains(#"Window("Fleck""#))
  let notesPanelSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  #expect(notesPanelSource.contains("FleckMark.load(template: true)"))
}

@Test func notesPanelHeaderExposesOnlyTheFleckTitleAndMissingMarkWarning() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let header = try #require(source.components(separatedBy: "private var header: some View").dropFirst().first)
  let titleArea = try #require(header.components(separatedBy: "Spacer()").first)
  let mark = try #require(titleArea.range(of: "Image(nsImage: mark)"))
  let title = try #require(titleArea.range(of: "Text(\"Fleck\")"))

  #expect(titleArea[mark.upperBound...].contains(".accessibilityHidden(true)"))
  #expect(titleArea[title.upperBound...].contains(".accessibilityLabel(\"Fleck\")"))
  #expect(titleArea.contains(".accessibilityLabel(\"Fleck mark missing\")"))
}

@Test @MainActor func fleckMarkFailsLoudlyForMissingPackagedResourceButFallsBackInBareDevelopment() {
  switch FleckMark.load(template: true, resourceURL: nil, isPackagedApp: true) {
  case .missingPackagedResource:
    break
  case .image:
    Issue.record("A packaged Fleck.app must not silently use a fallback mark")
  }

  switch FleckMark.load(template: true, resourceURL: nil, isPackagedApp: false) {
  case .image(let image):
    #expect(image.isTemplate)
  case .missingPackagedResource:
    Issue.record("Bare development should retain the explicit note-text fallback")
  }
}

@Test @MainActor func fleckMarkUsesCanonicalTemplateLogicalSizeForMenuBarAndHeader() {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let canonicalAssetDirectory = root.appendingPathComponent("website/public")

  switch FleckMark.load(
    template: true,
    resourceURL: canonicalAssetDirectory,
    isPackagedApp: true
  ) {
  case .image(let image):
    #expect(image.isTemplate)
    #expect(image.size.width == 18)
    #expect(image.size.height == 18)
  case .missingPackagedResource:
    Issue.record("The canonical Fleck mark should load for the menu bar")
  }

  switch FleckMark.load(
    template: true,
    resourceURL: canonicalAssetDirectory,
    isPackagedApp: true
  ) {
  case .image(let image):
    #expect(image.isTemplate)
    #expect(image.size.width == 18)
    #expect(image.size.height == 18)
  case .missingPackagedResource:
    Issue.record("The canonical Fleck mark should load for the header")
  }
}

@Test @MainActor
func fleckMarkRetainsPackagedImageAfterBackingFileDisappears() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let canonicalAsset = root.appendingPathComponent("website/public/fleck-mark.png")
  let temporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckMarkLifetime-\(UUID().uuidString)", isDirectory: true)
  let markURL = temporaryDirectory.appendingPathComponent("fleck-mark.png")
  try FileManager.default.createDirectory(
    at: temporaryDirectory,
    withIntermediateDirectories: false
  )
  defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
  try FileManager.default.copyItem(at: canonicalAsset, to: markURL)

  let loader = FleckMark.Loader(
    resourceURL: temporaryDirectory,
    isPackagedApp: true
  )
  switch loader.load(template: true) {
  case .image(let image):
    #expect(image.isTemplate)
    #expect(image.size.width == 18)
    #expect(image.size.height == 18)
  case .missingPackagedResource:
    Issue.record("The packaged Fleck mark should load before its file disappears")
  }

  try FileManager.default.removeItem(at: markURL)
  #expect(!FileManager.default.fileExists(atPath: markURL.path))

  switch loader.load(template: true) {
  case .image(let image):
    #expect(image.isTemplate)
    #expect(image.size.width == 18)
    #expect(image.size.height == 18)
  case .missingPackagedResource:
    Issue.record("The same loader should retain its decoded packaged mark")
  }

  let freshLoader = FleckMark.Loader(
    resourceURL: temporaryDirectory,
    isPackagedApp: true
  )
  switch freshLoader.load(template: true) {
  case .missingPackagedResource:
    break
  case .image:
    Issue.record("A fresh loader must fail loudly for a missing packaged resource")
  }
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

@Test func packagedDevelopmentAccessIsEnabledOnlyByTheDevelopmentBuildScript() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let buildScript = try String(
    contentsOf: root.appendingPathComponent("Scripts/build-fleck-app.sh"),
    encoding: .utf8
  )

  #expect(
    buildScript.contains(
      #"/usr/bin/plutil -insert FleckDevelopmentAccess -bool true "$staged_app/Contents/Info.plist""#
    )
  )
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
