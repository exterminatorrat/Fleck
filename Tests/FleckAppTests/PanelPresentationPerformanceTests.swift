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
      "/usr/bin/perl",
      "File::Temp",
      "rename",
      "# AX_MEASUREMENT_OUTPUT_HELPERS_BEGIN",
      "# AX_MEASUREMENT_PERL_BEGIN",
      "measurement_output_helper",
      "publish_output_file",
      "AX-press-to-accessible-window",
      "AXPress toggles panel presentation state",
      "mutation_boundary=no note/editor/Application Support mutation; presentation-state AXPress is intentional",
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
      "/bin/mv -h",
      "mktemp \"$output_dir",
      "> \"$raw_temp\"",
      "> \"$summary_temp\"",
      "> \"$metadata_temp\"",
      "AX-press-to-accessible-visible",
      "function isVisible",
      "visiblePanelWindows",
      "attribute(window, \"visible\")",
      "visible=true",
      "entireContents",
      "uiElements",
      "note_title",
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
    let helperStart = try #require(run.range(of: "function runMeasurement(argv, systemEvents)"))
    let productionHelper = String(run[helperStart.lowerBound..<run.endIndex])
      .components(separatedBy: "\nfunction run(argv)").first ?? ""
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
function run(argv) { return runMeasurement(["42", "31"], fakeSystemEvents); }
"""#
    let result = try runJXA(jxa + "\n" + productionHelper + "\n" + fixture)
    let rows = result.stdout.split(whereSeparator: \.isNewline)

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(rows.count == 32)
    #expect(rows.first == "sample_label\tsample_number\telapsed_ms")
    for (offset, row) in rows.dropFirst().enumerated() {
      let fields = row.split(separator: "\t", omittingEmptySubsequences: false)
      #expect(fields.count == 3)
      guard fields.count == 3 else { continue }
      #expect(String(fields[0]) == (offset == 0 ? "cold" : "warm"))
      #expect(Int(String(fields[1])) == offset + 1)
      #expect(
        String(fields[2]).range(
          of: #"^[0-9]+([.][0-9]+)?$"#,
          options: .regularExpression
        ) != nil
      )
    }
  }

  @Test func FleckPanelProductionEntryUsesOnlyOsascriptArgv() throws {
    let run = try measurementRunJXASource(from: measurementScriptSource())

    #expect(run.contains("function run(argv)"))
    #expect(!run.contains("function run(argv, systemEventsOverride)"))
    #expect(!run.contains("systemEventsOverride"))

    let entryStart = try #require(run.range(of: "function run(argv)"))
    let productionEntry = String(run[entryStart.lowerBound..<run.endIndex])
      .replacingOccurrences(of: "function run(argv)", with: "function productionEntry(argv)")
      .replacingOccurrences(of: "Application(\"System Events\")", with: "fakeSystemEvents")
    let fixture = #"""
var fakeSystemEvents = {};
function runMeasurement(argv, systemEvents) {
  if (argv.length !== 2 || argv[0] !== "one" || argv[1] !== "two") throw new Error("argv mismatch");
  if (systemEvents !== fakeSystemEvents) throw new Error("hidden context was used");
  return "production-entry-used-only-argv";
}
function run(argv) { return productionEntry(argv); }
"""#
    let result = try runJXA(productionEntry + "\n" + fixture, arguments: ["one", "two"])

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(result.stdout.contains("production-entry-used-only-argv"))
  }

  @Test func FleckPanelProductionAWKAcceptsCompleteTSVAndRejectsIncompleteTSV() throws {
    let programs = try measurementAWKPrograms()
    var rows = ["sample_label\tsample_number\telapsed_ms", "cold\t1\t1"]
    rows += (2...31).map { "warm\t\($0)\t\($0)" }
    let validFixture = rows.joined(separator: "\n") + "\n"
    let incompleteFixture = rows.dropLast().joined(separator: "\n") + "\n"

    let valid = try runAWK(
      programs.validation,
      arguments: ["-F", "\t", "-v", "expected=31"],
      input: validFixture
    )
    #expect(valid.status == 0, Comment(rawValue: valid.stderr))

    let incomplete = try runAWK(
      programs.validation,
      arguments: ["-F", "\t", "-v", "expected=31"],
      input: incompleteFixture
    )
    #expect(incomplete.status != 0)

    let malformedElapsed = try runAWK(
      programs.validation,
      arguments: ["-F", "\t", "-v", "expected=31"],
      input: validFixture.replacingOccurrences(of: "warm\t2\t2", with: "warm\t2\t")
    )
    #expect(malformedElapsed.status != 0)

    let statistics = try runAWK(
      programs.statistics,
      arguments: ["-v", "expected=31"],
      input: (1...31).map(String.init).joined(separator: "\n") + "\n"
    )
    #expect(statistics.status == 0, Comment(rawValue: statistics.stderr))
    #expect(statistics.stdout == "31\t16\t30\t1\t31\n")
  }

  @Test func FleckPanelMeasurementPublishesWithoutFollowingSymlinksOrHardLinks() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-publish-safety-" + UUID().uuidString, isDirectory: true)
    let sentinel = temporaryDirectory.appendingPathComponent("sentinel.txt")
    let foreignDirectory = temporaryDirectory.appendingPathComponent("foreign", isDirectory: true)
    let foreignSentinel = foreignDirectory.appendingPathComponent("sentinel.txt")
    try FileManager.default.createDirectory(at: foreignDirectory, withIntermediateDirectories: true)
    try "sentinel\n".write(to: sentinel, atomically: true, encoding: .utf8)
    try "foreign\n".write(to: foreignSentinel, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let publishHook = temporaryDirectory.appendingPathComponent("make-directory.sh")
    try "#!/bin/sh\nset -eu\nmkdir \"$1\"\n".write(
      to: publishHook,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o755)],
      ofItemAtPath: publishHook.path
    )

    let command = try measurementOutputHelpersShellSource() + "\n" + #"""
set -eu
output_dir=$1
sentinel=$2
foreign_directory=$3
publish_hook=$4

publish_payload() {
  destination=$1
  payload=$2
  temporary=$(printf '%s\n' "$payload" | measurement_output_helper create "$output_dir")
  publish_output_file "$temporary" "$destination"
}

destination="$output_dir/symlink-file"
if [ -e "$destination" ] || [ -L "$destination" ]; then exit 10; fi
ln -s "$sentinel" "$destination"
publish_payload "$destination" "symlink-file-payload"

destination="$output_dir/symlink-directory"
if [ -e "$destination" ] || [ -L "$destination" ]; then exit 11; fi
ln -s "$foreign_directory" "$destination"
publish_payload "$destination" "symlink-directory-payload"

destination="$output_dir/existing-directory"
mkdir "$destination"
temporary=$(printf '%s\n' 'directory-payload' | measurement_output_helper create "$output_dir")
if publish_output_file "$temporary" "$destination"; then exit 12; fi
cleanup_output_temp "$temporary"

destination="$output_dir/raced-directory"
temporary=$(printf '%s\n' 'raced-directory-payload' | measurement_output_helper create "$output_dir")
export FLECK_MEASUREMENT_PUBLISH_HOOK="$publish_hook"
if publish_output_file "$temporary" "$destination"; then exit 14; fi
unset FLECK_MEASUREMENT_PUBLISH_HOOK
[ -d "$destination" ]
[ -f "$temporary" ] && [ ! -L "$temporary" ]
cleanup_output_temp "$temporary"
[ ! -e "$temporary" ]
[ ! -e "$destination/raced-directory-payload" ]

destination="$output_dir/hard-link"
if [ -e "$destination" ] || [ -L "$destination" ]; then exit 13; fi
ln "$sentinel" "$destination"
publish_payload "$destination" "hard-link-payload"

leftover=$(find "$output_dir" -maxdepth 1 -name '.fleck-panel-measurement.*' -print -quit)
[ -z "$leftover" ]
"""#
    let result = try runShell(
      command,
      arguments: [
        temporaryDirectory.path,
        sentinel.path,
        foreignDirectory.path,
        publishHook.path,
      ]
    )

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "sentinel\n")
    #expect(try String(contentsOf: foreignSentinel, encoding: .utf8) == "foreign\n")
    #expect(try String(
      contentsOf: temporaryDirectory.appendingPathComponent("symlink-file"),
      encoding: .utf8
    ) == "symlink-file-payload\n")
    #expect(try String(
      contentsOf: temporaryDirectory.appendingPathComponent("symlink-directory"),
      encoding: .utf8
    ) == "symlink-directory-payload\n")
    #expect(try String(
      contentsOf: temporaryDirectory.appendingPathComponent("hard-link"),
      encoding: .utf8
    ) == "hard-link-payload\n")
    #expect(!FileManager.default.fileExists(
      atPath: foreignDirectory.appendingPathComponent("symlink-directory-payload").path
    ))
    #expect(FileManager.default.fileExists(
      atPath: temporaryDirectory.appendingPathComponent("existing-directory").path
    ))
    #expect(FileManager.default.fileExists(
      atPath: temporaryDirectory.appendingPathComponent("raced-directory").path
    ))
    #expect(!FileManager.default.fileExists(
      atPath: temporaryDirectory
        .appendingPathComponent("existing-directory", isDirectory: true)
        .appendingPathComponent("directory-payload")
        .path
    ))
  }

  @Test func FleckPanelMeasurementTempWriteSurvivesPathSymlinkSubstitution() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-temp-write-safety-" + UUID().uuidString, isDirectory: true)
    let sentinel = temporaryDirectory.appendingPathComponent("sentinel.txt")
    let hook = temporaryDirectory.appendingPathComponent("replace-temp.sh")
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try "sentinel\n".write(to: sentinel, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nset -eu\n/bin/unlink \"$1\"\n/bin/ln -s \"$FLECK_MEASUREMENT_TEST_SENTINEL\" \"$1\"\n".write(
      to: hook,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o755)],
      ofItemAtPath: hook.path
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let command = try measurementOutputHelpersShellSource() + "\n" + #"""
set -eu
output_dir=$1
sentinel=$2
hook=$3
export FLECK_MEASUREMENT_TEMP_HOOK="$hook"
export FLECK_MEASUREMENT_TEST_SENTINEL="$sentinel"
if printf '%s\n' 'payload' | measurement_output_helper create "$output_dir"; then exit 10; fi
[ "$(/usr/bin/sed -n '1p' "$sentinel")" = sentinel ]
leftover=$(find "$output_dir" -maxdepth 1 -name '.fleck-panel-measurement.*' -print -quit)
[ -z "$leftover" ]
"""#
    let result = try runShell(
      command,
      arguments: [temporaryDirectory.path, sentinel.path, hook.path]
    )

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "sentinel\n")
  }

  @Test func FleckPanelMeasurementEmbeddedPerlHelperCompiles() throws {
    let result = try runPerl(try measurementOutputHelperPerlSource())

    #expect(result.status == 0, Comment(rawValue: result.stderr))
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

  private func runJXA(_ source: String, arguments: [String] = []) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "JavaScript", "-"] + arguments
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

  private func runPerl(_ source: String) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-MFile::Temp", "-c", "-e", source]
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

  private func runAWK(
    _ program: String,
    arguments: [String],
    input: String
  ) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/awk")
    process.arguments = arguments + [program]
    let stdin = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.standardInput = stdin
    process.standardOutput = output
    process.standardError = error
    try process.run()
    stdin.fileHandleForWriting.write(Data(input.utf8))
    stdin.fileHandleForWriting.closeFile()
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

  private func measurementOutputHelpersShellSource() throws -> String {
    let source = try measurementScriptSource()
    let begin = try #require(source.range(of: "# AX_MEASUREMENT_OUTPUT_HELPERS_BEGIN\n"))
    let end = try #require(
      source.range(
        of: "\n# AX_MEASUREMENT_OUTPUT_HELPERS_END",
        range: begin.upperBound..<source.endIndex
      )
    )
    return String(source[begin.upperBound..<end.lowerBound])
  }

  private func measurementOutputHelperPerlSource() throws -> String {
    let source = try measurementScriptSource()
    let begin = try #require(source.range(of: "# AX_MEASUREMENT_PERL_BEGIN\n"))
    let end = try #require(
      source.range(
        of: "\n# AX_MEASUREMENT_PERL_END",
        range: begin.upperBound..<source.endIndex
      )
    )
    return String(source[begin.upperBound..<end.lowerBound])
  }

  private func measurementAWKPrograms() throws -> (validation: String, statistics: String) {
    let source = try measurementScriptSource()
    let validationStart = try #require(
      source.range(of: "awk -F '\\t' -v expected=\"$total_samples\" '\n")
    )
    let validationEnd = try #require(
      source.range(
        of: "\n'; then",
        range: validationStart.upperBound..<source.endIndex
      )
    )
    let statisticsStart = try #require(
      source.range(of: "sort -n | awk -v expected=\"$total_samples\" '\n")
    )
    let statisticsEnd = try #require(
      source.range(
        of: "\n') ||",
        range: statisticsStart.upperBound..<source.endIndex
      )
    )
    return (
      validation: String(source[validationStart.upperBound..<validationEnd.lowerBound]),
      statistics: String(source[statisticsStart.upperBound..<statisticsEnd.lowerBound])
    )
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
#endif
