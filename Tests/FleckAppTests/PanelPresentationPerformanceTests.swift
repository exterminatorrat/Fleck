#if os(macOS)
  import AppKit
  import Foundation
  import Testing

  @testable import FleckApp

  @Test @MainActor func FleckPanelPresentationMeasurementCompletesOnceWithInjectedMonotonicTime() {
    var now: UInt64 = 1_000_000_000
    var samples: [FleckPanelPresentationMeasurementSample] = []
    let measurement = FleckPanelPresentationMeasurement(
      now: { now },
      completionSink: { samples.append($0) }
    )

    #expect(measurement.begin())
    #expect(!measurement.begin())
    now += 275_000_000
    #expect(measurement.end(rootState: .notes))
    #expect(!measurement.end(rootState: .notes))
    #expect(samples == [
      FleckPanelPresentationMeasurementSample(
        elapsedMilliseconds: 275,
        rootState: .notes
      )
    ])
  }

  @Test @MainActor func FleckPanelPresentationMeasurementIgnoresMissingEndsAndClearsCancelledIntervals() {
    var now: UInt64 = 4_000_000_000
    var samples: [FleckPanelPresentationMeasurementSample] = []
    let measurement = FleckPanelPresentationMeasurement(
      now: { now },
      completionSink: { samples.append($0) }
    )

    #expect(!measurement.end(rootState: .loading))
    #expect(measurement.begin())
    #expect(measurement.cancel())
    #expect(!measurement.end(rootState: .blocked))
    #expect(measurement.begin())
    now += 50_000_000
    #expect(measurement.end(rootState: .resume))
    #expect(samples.count == 1)
    #expect(samples[0].rootState == .resume)
  }

  @Test @MainActor func FleckPanelPresentationEventDiscriminationKeepsRightClickConsumptionSeparate() {
    let handlesRightStatusBar = StatusItemContextMenuController.handles(
      eventType: .rightMouseDown,
      windowLevel: .statusBar
    )
    let handlesLeftStatusBar = StatusItemContextMenuController.handles(
      eventType: .leftMouseDown,
      windowLevel: .statusBar
    )
    let startsLeftStatusBar = StatusItemContextMenuController.startsPanelPresentationMeasurement(
      eventType: .leftMouseDown,
      windowLevel: .statusBar
    )
    let startsRightStatusBar = StatusItemContextMenuController.startsPanelPresentationMeasurement(
      eventType: .rightMouseDown,
      windowLevel: .statusBar
    )
    let startsLeftNormal = StatusItemContextMenuController.startsPanelPresentationMeasurement(
      eventType: .leftMouseDown,
      windowLevel: .normal
    )
    #expect(handlesRightStatusBar)
    #expect(!handlesLeftStatusBar)
    #expect(startsLeftStatusBar)
    #expect(!startsRightStatusBar)
    #expect(!startsLeftNormal)
  }

  @Test func FleckMenuBarRootWiresOnlyTheActualStatusBarWindowProbe() throws {
    let source = try String(
      contentsOf: repositoryRoot().appendingPathComponent(
        "Sources/FleckApp/OnboardingWindowPresenter.swift"
      ),
      encoding: .utf8
    )
    let rootStart = try #require(source.range(of: "struct FleckMenuBarRoot"))
    let pinnedStart = try #require(source.range(of: "struct FleckPinnedNotesRoot"))
    let rootSource = String(source[rootStart.lowerBound..<pinnedStart.lowerBound])

    #expect(rootSource.contains("FleckMenuBarPresentationProbe"))
    #expect(source.contains("NSWindow.didBecomeKeyNotification"))
    #expect(source.contains("NSWindow.didBecomeMainNotification"))
    #expect(source.contains("window.level == .statusBar"))
    #expect(source.contains("window.isVisible"))
    #expect(source.contains("FleckPanelPresentationMeasurement.shared"))
    #expect(!rootSource.contains("makeKeyAndOrderFront"))
    #expect(!rootSource.contains(".animation("))
    #expect(!rootSource.contains("hitTest"))
  }

  @Test func FleckStatusItemMonitorReturnsLeftClicksAndConsumesOnlyRightClicks() throws {
    let source = try String(
      contentsOf: repositoryRoot().appendingPathComponent(
        "Sources/FleckApp/StatusItemContextMenuController.swift"
      ),
      encoding: .utf8
    )
    #expect(source.contains("matching: [.leftMouseDown, .rightMouseDown]"))
    #expect(source.contains("FleckPanelPresentationMeasurement.shared.begin()"))
    #expect(source.contains("return event"))
    #expect(source.contains("NSMenu.popUpContextMenu(menu, with: event, for: view)"))
  }

  @Test func FleckActivationPreferenceTimingIsWiredAroundTheExistingCall() throws {
    let source = try String(
      contentsOf: repositoryRoot().appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
      encoding: .utf8
    )
    let methodStart = try #require(source.range(of: "func applicationDidBecomeActive()"))
    let methodEnd = try #require(source.range(of: "func awaitStartupAssessment()", range: methodStart.upperBound..<source.endIndex))
    let methodSource = String(source[methodStart.lowerBound..<methodEnd.lowerBound])

    #expect(methodSource.contains("measureActivationPreferenceSynchronization"))
    #expect(methodSource.contains("synchronizePreferences()"))
  }

  @Test func FleckPanelMeasurementScriptDeclaresAClosedSafeAccessibilityWorkflow() throws {
    let source = try String(
      contentsOf: repositoryRoot().appendingPathComponent(
        "Scripts/measure-fleck-panel-presentation.sh"
      ),
      encoding: .utf8
    )

    for required in [
      "#!/bin/sh",
      "set -eu",
      "Darwin",
      "FLECK_PERFORMANCE_PID",
      "ps -p",
      "System Events",
      "description of itemRef",
      "title of itemRef",
      "key code 53",
      "com.harryjin.fleck",
      "category ==",
      "panel_presentation elapsed_ms=",
      "cold",
      "warm",
      "warm_sample_count=30",
      "p50",
      "p95",
      "output_dir",
      "[ -L",
      "Application Support/Fleck",
    ] {
      #expect(source.contains(required), Comment(rawValue: required))
    }

    for forbidden in [
      "open ",
      "kill",
      "pkill",
      "killall",
      "rm -rf",
      "cp ",
      "mv ",
      "body.md",
      "workspace.json",
      "preferences.json",
    ] {
      #expect(!source.contains(forbidden), Comment(rawValue: forbidden))
    }
  }

  @Test func FleckPanelPresentationMeasurementAcceptsOnlyThePackagedFleckExecutablePath() throws {
    let source = try String(
      contentsOf: repositoryRoot().appendingPathComponent(
        "Scripts/measure-fleck-panel-presentation.sh"
      ),
      encoding: .utf8
    )
    let functionStart = try #require(source.range(of: "is_exact_fleck_command() {"))
    let functionEnd = try #require(
      source.range(of: "\n}\n", range: functionStart.upperBound..<source.endIndex)
    )
    let functionSource = String(source[functionStart.lowerBound..<functionEnd.upperBound])
    let command = functionSource + "\nis_exact_fleck_command \"$1\""
    let packagedPath = repositoryRoot()
      .appendingPathComponent(".build/Fleck.app/Contents/MacOS/Fleck")
      .path
    let nonFleckPath = repositoryRoot()
      .appendingPathComponent(".build/Other.app/Contents/MacOS/Other")
      .path

    #expect(try runShell(command: command, arguments: ["--", packagedPath]) == 0)
    #expect(try runShell(command: command, arguments: ["--", nonFleckPath]) != 0)
    #expect(try runShell(command: command, arguments: ["--", "Fleck"]) != 0)
  }

  @Test func FleckPanelMeasurementScriptFailsClosedForInvalidInputs() throws {
    let root = repositoryRoot()
    let script = root.appendingPathComponent("Scripts/measure-fleck-panel-presentation.sh")
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-panel-measurement-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let missingArguments = try run(
      script: script,
      arguments: []
    )
    #expect(missingArguments.status != 0)

    let nonexistentDirectory = temporaryDirectory.appendingPathComponent("missing")
    let nonexistent = try run(
      script: script,
      arguments: [nonexistentDirectory.path]
    )
    #expect(nonexistent.status != 0)

    let symlink = temporaryDirectory.appendingPathComponent("output-link")
    try FileManager.default.createSymbolicLink(
      at: symlink,
      withDestinationURL: temporaryDirectory
    )
    let symlinkResult = try run(
      script: script,
      arguments: [symlink.path]
    )
    #expect(symlinkResult.status != 0)

    let nonFleckPID = String(ProcessInfo.processInfo.processIdentifier)
    let nonFleck = try run(
      script: script,
      arguments: [temporaryDirectory.path],
      environment: ["FLECK_PERFORMANCE_PID": nonFleckPID]
    )
    #expect(nonFleck.status != 0)
    let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
    #expect(remainingFiles == ["output-link"])
  }

  private struct CommandResult {
    let status: Int32
  }

  private func run(
    script: URL,
    arguments: [String],
    environment: [String: String] = [:]
  ) throws -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script.path] + arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    try process.run()
    process.waitUntilExit()
    return CommandResult(status: process.terminationStatus)
  }

  private func runShell(command: String, arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command] + arguments
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
#endif
