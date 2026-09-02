#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import Testing

@testable import FleckApp

private enum ResourceTestError: Error {
  case bundleUnavailable
}

private let manifestFileName = "EnhancedModelManifest.json"
private let noticesFileName = "ThirdPartyNotices.md"

private func temporaryRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("fleck-resource-bundle-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(
    at: root,
    withIntermediateDirectories: true
  )
  return root
}

private func makeBundle(at root: URL) throws -> Bundle {
  try FileManager.default.createDirectory(
    at: root,
    withIntermediateDirectories: true
  )
  guard let bundle = Bundle(url: root) else {
    throw ResourceTestError.bundleUnavailable
  }
  return bundle
}

private func write(_ contents: String, to directory: URL, named name: String) throws {
  try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
}

private func resourceRoot(under root: URL) throws -> URL {
  let resourceRoot = root
    .appendingPathComponent("Contents", isDirectory: true)
    .appendingPathComponent("Resources", isDirectory: true)
  try FileManager.default.createDirectory(
    at: resourceRoot,
    withIntermediateDirectories: true
  )
  return resourceRoot
}

private func packagedBundle(under resourceRoot: URL) throws -> URL {
  let bundle = resourceRoot.appendingPathComponent(
    "Fleck_FleckApp.bundle",
    isDirectory: true
  )
  try FileManager.default.createDirectory(
    at: bundle,
    withIntermediateDirectories: true
  )
  return bundle
}

private func moduleBundle(under root: URL) throws -> (directory: URL, bundle: Bundle) {
  let directory = root.appendingPathComponent("module.bundle", isDirectory: true)
  return (directory, try makeBundle(at: directory))
}

private func validCompatibilityManifest(schemaVersion: Int = 1) -> String {
  """
  {"schemaVersion":\(schemaVersion),"modelID":"module/model","revision":"revision","totalByteCount":0,"files":[]}
  """
}

private func resourceURL(
  applicationResourceRoot: URL?,
  moduleBundle: Bundle
) throws -> URL {
  try FleckAppResourceBundle.url(
    forResource: "EnhancedModelManifest",
    withExtension: "json",
    applicationResourceRoot: applicationResourceRoot,
    moduleBundle: moduleBundle
  )
}

@Test
func validPackagedBundleIsPreferredOverModuleBundle() throws {
  let root = try temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appResourceRoot = try resourceRoot(under: root)
  let packaged = try packagedBundle(under: appResourceRoot)
  try write("packaged", to: packaged, named: manifestFileName)
  try write("packaged notices", to: packaged, named: noticesFileName)
  let module = try moduleBundle(under: root)
  try write("module", to: module.directory, named: manifestFileName)
  try write("module notices", to: module.directory, named: noticesFileName)

  let url = try resourceURL(
    applicationResourceRoot: appResourceRoot,
    moduleBundle: module.bundle
  )

  #expect(url == packaged.appendingPathComponent(manifestFileName))
  #expect(try String(contentsOf: url, encoding: .utf8) == "packaged")
}

@Test
func absentPackagedBundleFallsBackToModuleBundle() throws {
  let root = try temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appResourceRoot = try resourceRoot(under: root)
  let module = try moduleBundle(under: root)
  try write("module", to: module.directory, named: manifestFileName)
  try write("module notices", to: module.directory, named: noticesFileName)

  let url = try resourceURL(
    applicationResourceRoot: appResourceRoot,
    moduleBundle: module.bundle
  )

  #expect(url == module.directory.appendingPathComponent(manifestFileName))
  #expect(try String(contentsOf: url, encoding: .utf8) == "module")
}

@Test
func packagedBundleSymlinkDoesNotFallBackToModuleBundle() throws {
  let root = try temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appResourceRoot = try resourceRoot(under: root)
  let actualBundle = root.appendingPathComponent("actual.bundle", isDirectory: true)
  try FileManager.default.createDirectory(at: actualBundle, withIntermediateDirectories: true)
  try write("actual", to: actualBundle, named: manifestFileName)
  try write("actual notices", to: actualBundle, named: noticesFileName)
  let packaged = appResourceRoot.appendingPathComponent(
    "Fleck_FleckApp.bundle",
    isDirectory: true
  )
  try FileManager.default.createSymbolicLink(
    at: packaged,
    withDestinationURL: actualBundle
  )
  let module = try moduleBundle(under: root)
  try write("module", to: module.directory, named: manifestFileName)

  #expect(throws: FleckAppResourceBundleError.invalidPackagedBundle) {
    try resourceURL(
      applicationResourceRoot: appResourceRoot,
      moduleBundle: module.bundle
    )
  }
}

@Test
func packagedBundleNonDirectoryDoesNotFallBackToModuleBundle() throws {
  let root = try temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appResourceRoot = try resourceRoot(under: root)
  let packaged = appResourceRoot.appendingPathComponent(
    "Fleck_FleckApp.bundle",
    isDirectory: true
  )
  try Data("not a directory".utf8).write(to: packaged)
  let module = try moduleBundle(under: root)
  try write("module", to: module.directory, named: manifestFileName)

  #expect(throws: FleckAppResourceBundleError.invalidPackagedBundle) {
    try resourceURL(
      applicationResourceRoot: appResourceRoot,
      moduleBundle: module.bundle
    )
  }
}

@Test
func packagedResourceSymlinkDoesNotFallBackToModuleBundle() throws {
  let root = try temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appResourceRoot = try resourceRoot(under: root)
  let packaged = try packagedBundle(under: appResourceRoot)
  let outsideManifest = root.appendingPathComponent(manifestFileName)
  try write("outside", to: root, named: manifestFileName)
  try FileManager.default.createSymbolicLink(
    at: packaged.appendingPathComponent(manifestFileName),
    withDestinationURL: outsideManifest
  )
  try write("packaged notices", to: packaged, named: noticesFileName)
  let module = try moduleBundle(under: root)
  try write("module", to: module.directory, named: manifestFileName)

  #expect(
    throws: FleckAppResourceBundleError.invalidPackagedResource(manifestFileName)
  ) {
    try resourceURL(
      applicationResourceRoot: appResourceRoot,
      moduleBundle: module.bundle
    )
  }
}

@Test
func packagedResourceNonRegularFileDoesNotFallBackToModuleBundle() throws {
  let root = try temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appResourceRoot = try resourceRoot(under: root)
  let packaged = try packagedBundle(under: appResourceRoot)
  try FileManager.default.createDirectory(
    at: packaged.appendingPathComponent(manifestFileName),
    withIntermediateDirectories: true
  )
  try write("packaged notices", to: packaged, named: noticesFileName)
  let module = try moduleBundle(under: root)
  try write("module", to: module.directory, named: manifestFileName)

  #expect(
    throws: FleckAppResourceBundleError.invalidPackagedResource(manifestFileName)
  ) {
    try resourceURL(
      applicationResourceRoot: appResourceRoot,
      moduleBundle: module.bundle
    )
  }
}

@Test @MainActor
func malformedManifestFailsParakeetConfigurationWithoutFatalConstruction() throws {
  let root = try temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appResourceRoot = try resourceRoot(under: root)
  let packaged = try packagedBundle(under: appResourceRoot)
  try write("not json", to: packaged, named: manifestFileName)
  try write("packaged notices", to: packaged, named: noticesFileName)
  let module = try moduleBundle(under: root)
  try write(validCompatibilityManifest(), to: module.directory, named: manifestFileName)
  try write("module notices", to: module.directory, named: noticesFileName)

  #expect(throws: ParakeetTDTTestConfigurationError.invalidManifest) {
    _ = try ParakeetTDTTestConfiguration.make(
      admittedBaseRoot: root.appendingPathComponent("models", isDirectory: true),
      startup: {},
      calibrate: {},
      applicationResourceRoot: appResourceRoot,
      moduleBundle: module.bundle
    )
  }
}

@Test @MainActor
func missingManifestFallsBackToAppleSpeechDuringActivation() throws {
  let root = try temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appResourceRoot = try resourceRoot(under: root)
  let packaged = try packagedBundle(under: appResourceRoot)
  try write("packaged notices", to: packaged, named: noticesFileName)
  let module = try moduleBundle(under: root)
  try write(validCompatibilityManifest(), to: module.directory, named: manifestFileName)
  try write("module notices", to: module.directory, named: noticesFileName)

  let activation = ParakeetTDTTestActivation.make(
    applicationSupportURL: root,
    configurationFactory: { baseRoot, hooks in
      try ParakeetTDTTestConfiguration.make(
        admittedBaseRoot: baseRoot,
        startup: hooks.startup,
        calibrate: hooks.calibrate,
        applicationResourceRoot: appResourceRoot,
        moduleBundle: module.bundle
      )
    }
  )

  #expect(activation.manager.state == .notInstalled)
  #expect(activation.installer.snapshot.recommendation == .builtIn)
  guard case .failed(let message) = activation.installer.snapshot.phase else {
    Issue.record("Expected a safe Apple Speech fallback")
    return
  }
  #expect(message.contains("Apple Speech"))
}

@Test @MainActor
func compatibilityManagerDisablesCandidateWhenPackagedResourcesAreInvalid() async throws {
  let root = try temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let appResourceRoot = try resourceRoot(under: root)
  let actualBundle = root.appendingPathComponent("actual.bundle", isDirectory: true)
  try FileManager.default.createDirectory(at: actualBundle, withIntermediateDirectories: true)
  let packaged = appResourceRoot.appendingPathComponent(
    "Fleck_FleckApp.bundle",
    isDirectory: true
  )
  try FileManager.default.createSymbolicLink(
    at: packaged,
    withDestinationURL: actualBundle
  )
  let module = try moduleBundle(under: root)
  try write(validCompatibilityManifest(schemaVersion: 99), to: module.directory, named: manifestFileName)
  try write("module notices", to: module.directory, named: noticesFileName)

  let manager = EnhancedModelManager(
    modelRootURL: root.appendingPathComponent("models", isDirectory: true),
    candidateEnabled: true,
    architectureProvider: { true },
    applicationResourceRoot: appResourceRoot,
    moduleBundle: module.bundle
  )
  await manager.refreshState()

  #expect(manager.state == .notInstalled)
}
#endif
