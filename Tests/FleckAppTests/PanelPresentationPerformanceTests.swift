#if os(macOS)
  import Foundation
  import Testing

  @Test func FleckPanelPresentationScriptDeclaresTheAXPressMeasurementBoundary() throws {
    let source = try measurementScriptSource()
    let jxa = try measurementJXASource(from: source)

    for required in [
      "#!/bin/sh",
      "set -eu",
      "Darwin",
      "FLECK_PERFORMANCE_PID",
      "Fleck.app/Contents/MacOS/Fleck",
      "Application Support/Fleck",
      "[ -L",
      "/usr/bin/osascript -l JavaScript -",
      "Date.now",
      "AXMenuBarItem",
      "AXMenuExtra",
      "AXWindow",
      "AXSystemDialog",
      "AXPress",
      "AX-press-to-accessible-window",
      "31",
      "cold",
      "warm",
      "p50",
      "p95",
      "min",
      "max",
    ] {
      #expect(source.contains(required), Comment(rawValue: required))
    }

    for forbidden in [
      "log show",
      "--info",
      "panel_presentation",
      "activation_preference",
      "FleckPanelPresentationMeasurement",
      "didBecomeActive",
      "didResignActive",
      "key code 53",
      "System Events Escape",
      "open ",
      "kill",
      "pkill",
      "killall",
      "rm -rf",
      "cp ",
      "mv ",
      "AX-press-to-accessible-visible",
      "function isVisible",
      "visiblePanelWindows",
      "attribute(window, \"visible\")",
      "visible=true",
      "entireContents",
      "uiElements",
      "note",
      "body",
      "profileID",
    ] {
      #expect(!source.contains(forbidden), Comment(rawValue: forbidden))
    }

    #expect(!jxa.contains("Application Support"))
    #expect(!jxa.contains("entireContents"))
    #expect(!jxa.contains("uiElements"))
    #expect(!jxa.contains("note"))
    #expect(!jxa.contains("body"))
    #expect(!jxa.contains("AXVisible"))
  }

  @Test func FleckPanelProductionJXARunReturnsTheTSVToItsShellCaller() throws {
    let source = try measurementScriptSource()
    let jxa = try measurementJXASource(from: source)
    let run = try measurementRunJXASource(from: source)
    let productionRun = run.replacingOccurrences(
      of: "function run(argv, systemEventsOverride)",
      with: "function productionRun(argv, systemEventsOverride)",
      options: [],
      range: run.startIndex..<run.endIndex
    )
    let fixture = #"""
var state = { open: false, actions: 0 };
var panel = {
  role: function() { return "AXWindow"; },
  subrole: function() { return "AXSystemDialog"; },
  size: function() { return [520, 430]; }
};
var exactItem = {
  title: function() { return "Fleck"; },
  name: function() { return "Fleck"; },
  role: function() { return "AXMenuBarItem"; },
  subrole: function() { return "AXMenuExtra"; },
  actions: {
    byName: function(name) {
      if (name !== "AXPress") throw new Error("unexpected action");
      return { perform: function() { state.open = !state.open; state.actions += 1; } };
    }
  }
};
var fakeProcess = {
  unixId: function() { return 42; },
  name: function() { return "Fleck"; },
  menuBars: function() { return [{ menuBarItems: function() { return [exactItem]; } }]; },
  windows: function() { return state.open ? [panel] : []; }
};
var fakeSystemEvents = {
  applicationProcesses: function() { return [fakeProcess]; }
};
function run(argv) { return productionRun(["42", "31"], fakeSystemEvents); }
"""#
    let result = try runJXA(jxa + "\n" + productionRun + "\n" + fixture)
    let rows = result.stdout.split(whereSeparator: \.isNewline)

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(rows.count == 32)
    #expect(rows.first == "sample_label\tsample_number\telapsed_ms")
    #expect(rows.dropFirst().first == "cold\t1\t0")
    #expect(rows.last == "warm\t31\t0")
  }

  @Test func FleckPanelPresentationJXAUsesFakeAXFixturesForClosedNormalizationAnd31Samples() throws {
    let jxa = try measurementJXASource(from: measurementScriptSource())
    let fixture = #"""
function run(argv) {
var state = { open: true, now: 1_000, actions: 0 };
var panel = {
  role: function() { return "AXWindow"; },
  subrole: function() { return "AXSystemDialog"; },
  size: function() { return [520, 430]; }
};
var exactItem = {
  title: function() { return "Fleck"; },
  name: function() { return "Fleck"; },
  role: function() { return "AXMenuBarItem"; },
  subrole: function() { return "AXMenuExtra"; },
  actions: {
    byName: function(name) {
      if (name !== "AXPress") throw new Error("unexpected action");
      return { perform: function() { state.open = !state.open; state.now += 37; state.actions += 1; } };
    }
  }
};
var decoyItem = {
  title: function() { return "Fleck"; },
  name: function() { return "Fleck"; },
  role: function() { return "AXMenuBarItem"; },
  subrole: function() { return "AXMenuItem"; }
};
var fakeProcess = {
  unixId: function() { return 42; },
  name: function() { return "Fleck"; },
  menuBars: function() { return [
    { menuBarItems: function() { return [decoyItem]; } },
    { menuBarItems: function() { return [exactItem]; } }
  ]; },
  windows: function() { return state.open ? [panel] : []; }
};
var menuExtra = findUniqueMenuExtra(fakeProcess);
var samples = collectSamples(
  fakeProcess,
  menuExtra,
  31,
  function() { return state.now; },
  function(milliseconds) { state.now += milliseconds; },
  100
);
if (samples.length !== 31) throw new Error("sample count");
if (samples[0].sampleLabel !== "cold" || samples[30].sampleLabel !== "warm") throw new Error("labels");
if (samples.some(function(sample) { return sample.elapsedMilliseconds !== 37; })) throw new Error("elapsed");
if (state.actions !== 63 || state.open) throw new Error("closed normalization or close verification");
return JSON.stringify({ count: samples.length, actions: state.actions, elapsed: samples[0].elapsedMilliseconds });
}
"""#
    let result = try runJXA(jxa + "\n" + fixture)

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(result.stdout.contains(#""count":31"#))
    #expect(result.stdout.contains(#""actions":63"#))
    #expect(result.stdout.contains(#""elapsed":37"#))
  }

  @Test func FleckPanelPresentationJXACleansUpAfterAXPressThrowsAfterOpening() throws {
    let jxa = try measurementJXASource(from: measurementScriptSource())
    let fixture = #"""
function run(argv) {
var state = { open: false, now: 1_000, actions: 0, throwAfterOpen: true };
var panel = {
  role: function() { return "AXWindow"; },
  subrole: function() { return "AXSystemDialog"; },
  size: function() { return [520, 430]; }
};
var item = {
  title: function() { return "Fleck"; },
  name: function() { return "Fleck"; },
  role: function() { return "AXMenuBarItem"; },
  subrole: function() { return "AXMenuExtra"; },
  actions: {
    byName: function(name) {
      return { perform: function() {
        if (name !== "AXPress") throw new Error("unexpected action");
        state.open = !state.open;
        state.actions += 1;
        if (state.open && state.throwAfterOpen) {
          state.throwAfterOpen = false;
          throw new Error("synthetic post-press failure");
        }
      } };
    }
  }
};
var process = {
  windows: function() { return state.open ? [panel] : []; }
};
var failure = "";
try {
  collectSamples(process, item, 1, function() { return state.now; }, function(milliseconds) { state.now += milliseconds; }, 100);
} catch (error) {
  failure = String(error);
}
if (failure.indexOf("synthetic post-press failure") < 0) throw new Error("original error was masked");
if (state.open) throw new Error("panel remained open after failed sample");
return JSON.stringify({ open: state.open, actions: state.actions });
}
"""#
    let result = try runJXA(jxa + "\n" + fixture)

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(result.stdout.contains(#""open":false"#))
    #expect(result.stdout.contains(#""actions":2"#))
  }

  @Test func FleckPanelPresentationJXAFailsClosedForAmbiguousMenuExtrasAndTimeouts() throws {
    let jxa = try measurementJXASource(from: measurementScriptSource())
    let ambiguousFixture = #"""
function run(argv) {
var item = { title: function() { return "Fleck"; }, name: function() { return "Fleck"; }, role: function() { return "AXMenuBarItem"; }, subrole: function() { return "AXMenuExtra"; } };
var process = { menuBars: function() { return [{ menuBarItems: function() { return [item, item]; } }]; } };
findUniqueMenuExtra(process);
}
"""#
    let ambiguous = try runJXA(jxa + "\n" + ambiguousFixture)
    #expect(ambiguous.status != 0)
    #expect(ambiguous.stderr.contains("exactly one"))

    let ambiguousWindowFixture = #"""
function run(argv) {
var panel = {
  role: function() { return "AXWindow"; },
  subrole: function() { return "AXSystemDialog"; },
  size: function() { return [520, 430]; }
};
var process = { windows: function() { return [panel, panel]; } };
collectSamples(process, {}, 1, function() { return 1_000; }, function() {}, 30);
}
"""#
    let ambiguousWindow = try runJXA(jxa + "\n" + ambiguousWindowFixture)
    #expect(ambiguousWindow.status != 0)
    #expect(ambiguousWindow.stderr.contains("ambiguous accessible panel window"))

    let timeoutFixture = #"""
function run(argv) {
var state = { now: 1_000 };
var item = {
  title: function() { return "Fleck"; },
  name: function() { return "Fleck"; },
  role: function() { return "AXMenuBarItem"; },
  subrole: function() { return "AXMenuExtra"; },
  actions: { byName: function() { return { perform: function() {} }; } }
};
var process = {
  windows: function() { return []; },
  menuBars: function() { return [{ menuBarItems: function() { return [item]; } }]; }
};
collectSamples(process, item, 1, function() { return state.now; }, function(milliseconds) { state.now += milliseconds; }, 30);
}
"""#
    let timeout = try runJXA(jxa + "\n" + timeoutFixture)
    #expect(timeout.status != 0)
    #expect(timeout.stderr.contains("accessible panel window timeout"))
  }

  @Test func FleckPanelMeasurementScriptFailsClosedForInvalidInputs() throws {
    let root = repositoryRoot()
    let script = root.appendingPathComponent("Scripts/measure-fleck-panel-presentation.sh")
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-ax-measurement-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    #expect(try run(script: script, arguments: []).status != 0)
    #expect(try run(
      script: script,
      arguments: [temporaryDirectory.appendingPathComponent("missing").path]
    ).status != 0)

    let symlink = temporaryDirectory.appendingPathComponent("output-link")
    try FileManager.default.createSymbolicLink(
      at: symlink,
      withDestinationURL: temporaryDirectory
    )
    #expect(try run(script: script, arguments: [symlink.path]).status != 0)

    let nonFleck = try run(
      script: script,
      arguments: [temporaryDirectory.path],
      environment: ["FLECK_PERFORMANCE_PID": String(ProcessInfo.processInfo.processIdentifier)]
    )
    #expect(nonFleck.status != 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path) == ["output-link"])
  }

  @Test func FleckPanelMeasurementScriptAcceptsOnlyThePackagedFleckExecutableShape() throws {
    let source = try measurementScriptSource()
    let functionStart = try #require(source.range(of: "is_packaged_fleck_path_shape() {"))
    let functionEnd = try #require(
      source.range(of: "\n}\n", range: functionStart.upperBound..<source.endIndex)
    )
    let command = String(source[functionStart.lowerBound..<functionEnd.upperBound])
      + "\nis_packaged_fleck_path_shape \"$1\""
    let packagedPath = repositoryRoot()
      .appendingPathComponent(".build/Fleck.app/Contents/MacOS/Fleck")
      .path

    #expect(try runShell(command, arguments: [packagedPath]).status == 0)
    #expect(try runShell(command, arguments: ["/tmp/Fleck"]).status != 0)
    #expect(try runShell(command, arguments: ["/tmp/Other.app/Contents/MacOS/Other"]).status != 0)
  }

  @Test func FleckPanelMeasurementRejectsCanonicalFleckApplicationSupportWithLexicalHome() throws {
    let root = repositoryRoot()
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-home-canonicalization-" + UUID().uuidString, isDirectory: true)
    let homeDirectory = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
    let homeChild = homeDirectory.appendingPathComponent("child", isDirectory: true)
    let applicationSupport = homeDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent("Fleck", isDirectory: true)
    try FileManager.default.createDirectory(at: homeChild, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let lexicalHome = homeChild.appendingPathComponent("..", isDirectory: true).path
    let result = try run(
      script: root.appendingPathComponent("Scripts/measure-fleck-panel-presentation.sh"),
      arguments: [applicationSupport.path],
      environment: ["HOME": lexicalHome]
    )

    #expect(result.status != 0)
  }

  private struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
  }

  private func runJXA(_ source: String) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "JavaScript", "-"]
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    try process.run()
    input.fileHandleForWriting.write(Data(source.utf8))
    input.fileHandleForWriting.closeFile()
    let stdoutData = output.fileHandleForReading.readDataToEndOfFile()
    let stderrData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ProcessResult(
      status: process.terminationStatus,
      stdout: String(data: stdoutData, encoding: .utf8) ?? "",
      stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
  }

  private func runShell(_ command: String, arguments: [String]) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command, "shell"] + arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    let stdoutData = output.fileHandleForReading.readDataToEndOfFile()
    let stderrData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ProcessResult(
      status: process.terminationStatus,
      stdout: String(data: stdoutData, encoding: .utf8) ?? "",
      stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
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

  private func measurementScriptSource() throws -> String {
    try String(
      contentsOf: repositoryRoot().appendingPathComponent(
        "Scripts/measure-fleck-panel-presentation.sh"
      ),
      encoding: .utf8
    )
  }

  private func measurementJXASource(from source: String) throws -> String {
    let begin = try #require(source.range(of: "// AX_MEASUREMENT_JXA_BEGIN\n"))
    let end = try #require(
      source.range(of: "\n// AX_MEASUREMENT_JXA_END", range: begin.upperBound..<source.endIndex)
    )
    return String(source[begin.upperBound..<end.lowerBound])
  }

  private func measurementRunJXASource(from source: String) throws -> String {
    let begin = try #require(source.range(of: "// AX_MEASUREMENT_JXA_RUN_BEGIN\n"))
    let end = try #require(
      source.range(
        of: "\n// AX_MEASUREMENT_JXA_RUN_END",
        range: begin.upperBound..<source.endIndex
      )
    )
    return String(source[begin.upperBound..<end.lowerBound])
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
#endif
