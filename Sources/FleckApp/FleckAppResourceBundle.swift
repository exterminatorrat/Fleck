#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation

enum FleckAppResourceBundleError: Error, Equatable {
  case invalidPackagedBundle
  case invalidPackagedResource(String)
  case missingResource(String)
  case invalidModuleResource(String)
}

enum FleckAppResourceBundle {
  private static let packagedBundleName = "Fleck_FleckApp.bundle"

  static func defaultModuleBundle() -> Bundle? {
    guard Bundle.main.bundleURL.pathExtension
      .caseInsensitiveCompare("app") != .orderedSame else {
      return nil
    }
    return Bundle.module
  }

  // Policy: only an absent packaged bundle permits the SwiftPM module fallback.
  // A present but invalid package or resource fails closed.
  static func url(
    forResource name: String,
    withExtension fileExtension: String,
    applicationResourceRoot: URL? = Bundle.main.resourceURL,
    moduleBundle: Bundle? = FleckAppResourceBundle.defaultModuleBundle()
  ) throws -> URL {
    let fileName = "\(name).\(fileExtension)"
    if let applicationResourceRoot {
      let packagedBundle = applicationResourceRoot.appendingPathComponent(
        packagedBundleName,
        isDirectory: true
      )
      switch entryKind(at: packagedBundle) {
      case .missing:
        break
      case .directory:
        return try packagedResourceURL(
          fileName: fileName,
          in: packagedBundle
        )
      case .regular, .invalid:
        throw FleckAppResourceBundleError.invalidPackagedBundle
      }
    }

    guard let moduleBundle,
          let resource = moduleBundle.url(
      forResource: name,
      withExtension: fileExtension
    ) else {
      throw FleckAppResourceBundleError.missingResource(fileName)
    }
    guard entryKind(at: resource) == .regular else {
      throw FleckAppResourceBundleError.invalidModuleResource(fileName)
    }
    return resource
  }

  private static func packagedResourceURL(
    fileName: String,
    in bundle: URL
  ) throws -> URL {
    let resource = bundle.appendingPathComponent(fileName)
    guard entryKind(at: resource) == .regular else {
      throw FleckAppResourceBundleError.invalidPackagedResource(fileName)
    }
    return resource
  }

  private enum EntryKind {
    case missing
    case directory
    case regular
    case invalid
  }

  private static func entryKind(at url: URL) -> EntryKind {
    do {
      let values = try url.resourceValues(forKeys: [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isAliasFileKey,
      ])
      if values.isSymbolicLink == true || values.isAliasFile == true {
        return .invalid
      }
      if values.isDirectory == true {
        return .directory
      }
      if values.isRegularFile == true {
        return .regular
      }
      if values.isDirectory == nil && values.isRegularFile == nil {
        return .missing
      }
      return .invalid
    } catch {
      return FileManager.default.fileExists(atPath: url.path)
        ? .invalid
        : .missing
    }
  }
}
#endif
