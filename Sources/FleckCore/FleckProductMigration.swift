import Foundation

public enum FleckProductPaths {
  public static let canonicalDirectoryName = "Fleck"
  public static let legacyDirectoryName = "MenuBarNotes"
  public static let migrationReceiptName = "motes-to-fleck-v1.json"
}

public struct FleckMigrationReceipt: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let migratedAt: Date
  public let legacyPath: String
  public let canonicalPath: String

  public init(
    schemaVersion: Int,
    migratedAt: Date,
    legacyPath: String,
    canonicalPath: String
  ) {
    self.schemaVersion = schemaVersion
    self.migratedAt = migratedAt
    self.legacyPath = legacyPath
    self.canonicalPath = canonicalPath
  }
}

public enum FleckProductMigrationError: Error, Equatable, Sendable {
  case unsafeLegacyRoot
  case conflictingWorkspaces(legacyPath: String, canonicalPath: String)
  case invalidMigratedWorkspace
  case rollbackFailed(legacyPath: String, canonicalPath: String)
  case filesystemFailure
}

public enum FleckProductMigrationOutcome: Equatable, Sendable {
  case freshInstall(URL)
  case migrated(URL)
  case alreadyMigrated(URL)
  case failed(URL, FleckProductMigrationError)
}

public struct FleckProductMigration {
  private let applicationSupportParent: URL
  private let fileManager: FileManager
  private let now: @Sendable () -> Date

  public init(
    applicationSupportParent: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.applicationSupportParent = applicationSupportParent.standardizedFileURL
    self.fileManager = fileManager
    self.now = now
  }

  public func prepare() -> FleckProductMigrationOutcome {
    let legacy = applicationSupportParent.appendingPathComponent(
      FleckProductPaths.legacyDirectoryName,
      isDirectory: true
    )
    let canonical = applicationSupportParent.appendingPathComponent(
      FleckProductPaths.canonicalDirectoryName,
      isDirectory: true
    )

    do {
      try fileManager.createDirectory(
        at: applicationSupportParent,
        withIntermediateDirectories: true
      )
      let legacyExists = fileManager.fileExists(atPath: legacy.path)
      let canonicalExists = fileManager.fileExists(atPath: canonical.path)
      if legacyExists && isSymbolicLink(legacy) {
        return .failed(canonical, .unsafeLegacyRoot)
      }

      let legacyHasWorkspace = legacyExists && containsWorkspaceData(legacy)
      let canonicalHasWorkspace =
        canonicalExists && containsWorkspaceData(canonical)
      let canonicalIsDisposable =
        canonicalExists && containsOnlyEmptyGeneratedScaffolding(canonical)
      if legacyHasWorkspace && canonicalHasWorkspace && !canonicalIsDisposable {
        return .failed(
          canonical,
          .conflictingWorkspaces(
            legacyPath: legacy.path,
            canonicalPath: canonical.path
          )
        )
      }
      if canonicalExists {
        if legacyHasWorkspace {
          guard canonicalIsDisposable else {
            return .failed(canonical, .filesystemFailure)
          }
          try fileManager.removeItem(at: canonical)
          return migrate(legacy: legacy, canonical: canonical)
        }
        return .alreadyMigrated(canonical)
      }
      guard legacyHasWorkspace else {
        try fileManager.createDirectory(
          at: canonical,
          withIntermediateDirectories: false
        )
        return .freshInstall(canonical)
      }

      return migrate(legacy: legacy, canonical: canonical)
    } catch {
      return .failed(canonical, .filesystemFailure)
    }
  }

  private func migrate(
    legacy: URL,
    canonical: URL
  ) -> FleckProductMigrationOutcome {
    let staging = applicationSupportParent.appendingPathComponent(
      ".fleck-migration-\(UUID().uuidString)",
      isDirectory: true
    )
    do {
      try fileManager.moveItem(at: legacy, to: staging)
      do {
        try fileManager.moveItem(at: staging, to: canonical)
      } catch {
        return rollback(
          from: staging,
          to: legacy,
          canonical: canonical,
          error: .filesystemFailure
        )
      }

      do {
        let snapshot = try LocalStoreSnapshotWriter(
          rootURL: canonical,
          fileManager: fileManager,
          now: now
        ).loadSnapshot()
        guard snapshot.source != .fresh else {
          return rollback(
            from: canonical,
            to: legacy,
            canonical: canonical,
            error: .invalidMigratedWorkspace
          )
        }
        try writeReceipt(legacy: legacy, canonical: canonical)
        return .migrated(canonical)
      } catch {
        return rollback(
          from: canonical,
          to: legacy,
          canonical: canonical,
          error:
            error as? LocalStore.StoreError == .invalidSnapshot
            ? .invalidMigratedWorkspace
            : .filesystemFailure
        )
      }
    } catch {
      return .failed(canonical, .filesystemFailure)
    }
  }

  private func rollback(
    from source: URL,
    to legacy: URL,
    canonical: URL,
    error: FleckProductMigrationError
  ) -> FleckProductMigrationOutcome {
    do {
      try fileManager.moveItem(at: source, to: legacy)
      return .failed(canonical, error)
    } catch {
      return .failed(
        canonical,
        .rollbackFailed(
          legacyPath: legacy.path,
          canonicalPath: canonical.path
        )
      )
    }
  }

  private func writeReceipt(legacy: URL, canonical: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let receipt = FleckMigrationReceipt(
      schemaVersion: 1,
      migratedAt: now(),
      legacyPath: legacy.path,
      canonicalPath: canonical.path
    )
    try encoder.encode(receipt).write(
      to: canonical.appendingPathComponent(
        FleckProductPaths.migrationReceiptName
      ),
      options: .atomic
    )
  }

  private func isSymbolicLink(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink)
      == true
  }

  private func containsWorkspaceData(_ root: URL) -> Bool {
    let manifest = root.appendingPathComponent("workspace.json")
    if fileManager.fileExists(atPath: manifest.path) {
      return true
    }
    let workspaceDirectories: Set<String> = [
      "Trash",
      "DictationHistory",
      "DictationRecovery",
      "Models",
      "AgentIntegrations",
      "AgentActivity",
    ]
    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]
      )
    else { return false }
    return contents.contains { item in
      if workspaceDirectories.contains(item.lastPathComponent) {
        return true
      }
      return ["md", "rtf"].contains(item.pathExtension.lowercased())
    }
  }

  private func containsOnlyEmptyGeneratedScaffolding(_ root: URL) -> Bool {
    guard !isSymbolicLink(root) else { return false }
    let allowedDirectories: Set<String> = [
      "AgentActivity",
      "AgentActivity/Prepared",
      "AgentActivity/Records",
      "AgentActivity/Tombstones",
    ]
    let rootComponents = root.standardizedFileURL.pathComponents
    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      )
    else { return false }
    for case let item as URL in enumerator {
      let values = try? item.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      )
      let relativePath = item.standardizedFileURL.pathComponents
        .dropFirst(rootComponents.count)
        .joined(separator: "/")
      guard
        values?.isDirectory == true,
        values?.isSymbolicLink != true,
        allowedDirectories.contains(relativePath)
      else { return false }
    }
    return true
  }
}
