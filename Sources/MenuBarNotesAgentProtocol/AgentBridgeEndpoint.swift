import Foundation
import MenuBarNotesCore

public enum AgentBridgeEndpoint {
  public static func applicationSupportURL(
    fileManager: FileManager = .default
  ) -> URL {
    fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    .appendingPathComponent(
      FleckProductPaths.canonicalDirectoryName,
      isDirectory: true
    )
  }

  public static func socketURL(
    fileManager: FileManager = .default
  ) -> URL {
    applicationSupportURL(fileManager: fileManager)
      .appendingPathComponent("AgentBridge", isDirectory: true)
      .appendingPathComponent("fleck.sock")
  }
}
