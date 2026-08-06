import Foundation
import Testing

@testable import FleckApp

@Test func FleckPerformanceSignpostSourceDefinesStableOSLogContracts() throws {
  let sourceURL = repositoryRoot()
    .appendingPathComponent("Sources/FleckApp/FleckPerformanceSignposts.swift")
  #expect(FileManager.default.fileExists(atPath: sourceURL.path))
  let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

  for required in [
    "import OSLog",
    "internal enum FleckPerformanceSignposts",
    "OSSignposter",
    #"static let subsystem = "com.harryjin.fleck""#,
    #"static let category = "performance""#,
    #"static let launch = StaticString("launch")"#,
    #"static let snapshotLoad = StaticString("snapshot-load")"#,
    #"static let searchQuery = StaticString("search-query")"#,
    #"static let noteSwitch = StaticString("note-switch")"#,
    #"static let snapshotSave = StaticString("snapshot-save")"#,
    #"static let panelPresentation = StaticString("panel-presentation")"#,
  ] {
    #expect(source.contains(required), Comment(rawValue: required))
  }

  for forbidden in [
    "beginInterval",
    "endInterval",
    "emitEvent",
    "OSLogStore",
    "import FleckCore",
    "import SwiftUI",
  ] {
    #expect(!source.contains(forbidden), Comment(rawValue: forbidden))
  }
}

@Test func FleckPerformanceProfileScriptDeclaresSafeExplicitOutputWorkflow() throws {
  let sourceURL = repositoryRoot()
    .appendingPathComponent("Scripts/profile-fleck-performance.sh")
  #expect(FileManager.default.fileExists(atPath: sourceURL.path))
  let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

  for required in [
    "#!/bin/sh",
    "set -eu",
    "output_dir",
    "swift build -c release --product Fleck --disable-automatic-resolution",
    "FLECK_PERFORMANCE_PID",
    "logical disk writes",
  ] {
    #expect(source.contains(required), Comment(rawValue: required))
  }

  for forbidden in [
    "rm -rf",
    "cp ",
    "mv ",
    "kill",
    "pkill",
    "killall",
    "body.md",
    ".rtf",
    "workspace.json",
    "preferences.json",
  ] {
    #expect(!source.contains(forbidden), Comment(rawValue: forbidden))
  }
}

@Test func FleckPerformanceDocumentationNamesMeasurementsAndManualBoundary() throws {
  let root = repositoryRoot()
  let template = (try? String(
    contentsOf: root.appendingPathComponent("docs/performance/fleck-baseline-template.md"),
    encoding: .utf8
  )) ?? ""
  let testing = (try? String(
    contentsOf: root.appendingPathComponent("TESTING.md"),
    encoding: .utf8
  )) ?? ""
  let documentation = template + testing

  for required in [
    "10-note",
    "100-note",
    "1,000-note",
    "launch",
    "panel presentation",
    "note switching",
    "typing",
    "save duration",
    "logical disk writes",
    "idle CPU",
    "resident memory",
    "executable size",
    "p50",
    "p95",
    "Application Support",
    "manual",
  ] {
    #expect(documentation.localizedCaseInsensitiveContains(required), Comment(rawValue: required))
  }
}

private func repositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
