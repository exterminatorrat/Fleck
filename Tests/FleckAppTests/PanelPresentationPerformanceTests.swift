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
      "lstat($requested_lstat_path)",
      "/usr/bin/osascript -l JavaScript -",
      "Date.now",
      "AXMenuBarItem",
      "AXMenuExtra",
      "AXWindow",
      "AXSystemDialog",
      "AXPress",
      "/usr/bin/perl",
      "File::Temp",
      "link",
      "syscall(13, 9)",
      "bind_measurement_output_directory",
      "# AX_MEASUREMENT_OUTPUT_HELPERS_BEGIN",
      "# AX_MEASUREMENT_DIRECTORY_RECORD_BEGIN",
      "# AX_MEASUREMENT_PERL_BEGIN",
      "measurement_output_helper",
      "measurement_output_directory_record",
      "rollback_output_file",
      "measurement_succeeded",
      "publish_output_file",
      "measurement_output_helper absent",
      "device",
      "inode",
      "tab, carriage return, or line feed",
      "cleanup",
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
      "[ -f \"$temp_file\" ]",
      "[ -L \"$temp_file\" ]",
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
directory_record=$(measurement_output_directory_record "$output_dir")
bind_measurement_output_directory "$output_dir"
sentinel_identity=$(/usr/bin/stat -f '%d:%i' "$sentinel")

publish_payload() {
  destination=$1
  payload=$2
  destination_basename=${destination##*/}
  temporary=$(printf '%s\n' "$payload" | measurement_output_helper create "$directory_record")
  if publish_output_file "$directory_record" "$temporary" "$destination_basename"; then exit 15; fi
  cleanup_output_temp "$directory_record" "$temporary"
}

destination="$output_dir/symlink-file"
if [ -e "$destination" ] || [ -L "$destination" ]; then exit 10; fi
ln -s "$sentinel" "$destination"
publish_payload "$destination" "symlink-file-payload"
[ -L "$destination" ]
[ "$(/bin/cat "$sentinel")" = sentinel ]

destination="$output_dir/symlink-directory"
if [ -e "$destination" ] || [ -L "$destination" ]; then exit 11; fi
ln -s "$foreign_directory" "$destination"
publish_payload "$destination" "symlink-directory-payload"
[ -L "$destination" ]
[ "$(/bin/cat "$foreign_directory/sentinel.txt")" = foreign ]

destination="$output_dir/existing-directory"
mkdir "$destination"
temporary=$(printf '%s\n' 'directory-payload' | measurement_output_helper create "$directory_record")
temporary_path="$output_dir/$(printf '%s\n' "$temporary" | /usr/bin/cut -f1)"
if publish_output_file "$directory_record" "$temporary" existing-directory; then exit 12; fi
cleanup_output_temp "$directory_record" "$temporary"
[ ! -e "$temporary_path" ]

destination="$output_dir/raced-directory"
temporary=$(printf '%s\n' 'raced-directory-payload' | measurement_output_helper create "$directory_record")
temporary_path="$output_dir/$(printf '%s\n' "$temporary" | /usr/bin/cut -f1)"
export FLECK_MEASUREMENT_PUBLISH_HOOK="$publish_hook"
if publish_output_file "$directory_record" "$temporary" raced-directory; then exit 14; fi
unset FLECK_MEASUREMENT_PUBLISH_HOOK
[ -d "$destination" ]
[ -f "$temporary_path" ] && [ ! -L "$temporary_path" ]
cleanup_output_temp "$directory_record" "$temporary"
[ ! -e "$temporary_path" ]
[ ! -e "$destination/raced-directory-payload" ]

destination="$output_dir/hard-link"
if [ -e "$destination" ] || [ -L "$destination" ]; then exit 13; fi
ln "$sentinel" "$destination"
publish_payload "$destination" "hard-link-payload"
[ "$(/usr/bin/stat -f '%d:%i' "$destination")" = "$sentinel_identity" ]
[ "$(/bin/cat "$sentinel")" = sentinel ]

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
    #expect(try FileManager.default.destinationOfSymbolicLink(
      atPath: temporaryDirectory.appendingPathComponent("symlink-file").path
    ) == sentinel.path)
    #expect(try FileManager.default.destinationOfSymbolicLink(
      atPath: temporaryDirectory.appendingPathComponent("symlink-directory").path
    ) == foreignDirectory.path)
    #expect(try String(
      contentsOf: temporaryDirectory.appendingPathComponent("hard-link"),
      encoding: .utf8
    ) == "sentinel\n")
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
    let replacedPathFile = temporaryDirectory.appendingPathComponent("replaced-path.txt")
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try "sentinel\n".write(to: sentinel, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nset -eu\n/bin/unlink \"$1\"\n/bin/ln -s \"$FLECK_MEASUREMENT_TEST_SENTINEL\" \"$1\"\nprintf '%s\\n' \"$1\" > \"$FLECK_MEASUREMENT_TEST_PATH_FILE\"\n".write(
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
path_file=$4
directory_record=$(measurement_output_directory_record "$output_dir")
bind_measurement_output_directory "$output_dir"
export FLECK_MEASUREMENT_TEMP_HOOK="$hook"
export FLECK_MEASUREMENT_TEST_SENTINEL="$sentinel"
export FLECK_MEASUREMENT_TEST_PATH_FILE="$path_file"
if printf '%s\n' 'payload' | measurement_output_helper create "$directory_record"; then exit 10; fi
replaced_path=$(/bin/cat "$path_file")
[ -L "$replaced_path" ]
[ "$(/usr/bin/sed -n '1p' "$sentinel")" = sentinel ]
/bin/unlink "$replaced_path"
[ ! -e "$replaced_path" ]
leftover=$(find "$output_dir" -maxdepth 1 -name '.fleck-panel-measurement.*' -print -quit)
[ -z "$leftover" ]
"""#
    let result = try runShell(
      command,
      arguments: [temporaryDirectory.path, sentinel.path, hook.path, replacedPathFile.path]
    )

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "sentinel\n")
  }

  @Test func FleckPanelMeasurementEmbeddedPerlHelperCompiles() throws {
    let result = try runPerl(try measurementOutputHelperPerlSource())

    #expect(result.status == 0, Comment(rawValue: result.stderr))
  }

  @Test func FleckPanelMeasurementRejectsSubstitutedTempIdentityForCleanupAndPublication() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-temp-identity-safety-" + UUID().uuidString, isDirectory: true)
    let callerOwned = temporaryDirectory.appendingPathComponent("caller-owned.txt")
    let destination = temporaryDirectory.appendingPathComponent("destination.txt")
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let command = try measurementOutputHelpersShellSource() + "\n" + #"""
set -eu
output_dir=$1
caller_owned=$2
destination=$3
directory_record=$(measurement_output_directory_record "$output_dir")
bind_measurement_output_directory "$output_dir"

record=$(printf '%s\n' 'payload' | measurement_output_helper create "$directory_record")
path="$output_dir/$(printf '%s\n' "$record" | /usr/bin/cut -f1)"
printf '%s\n' "$record" | /usr/bin/awk -F '\t' 'NF == 3 && $1 != "" && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { found = 1 } END { exit(found ? 0 : 1) }'
printf '%s\n' 'caller-owned' > "$caller_owned"
/bin/unlink "$path"
printf '%s\n' 'caller-substitute' > "$path"
printf '%s\n' 'destination-original' > "$destination"

cleanup_ok=1
cleanup_output_temp "$directory_record" "$record"
if [ ! -e "$path" ]; then
  cleanup_ok=0
  printf '%s\n' 'caller-substitute' > "$path"
fi

publish_ok=1
if publish_output_file "$directory_record" "$record" destination.txt; then
  publish_ok=0
fi
[ "$publish_ok" -eq 1 ]
[ -e "$path" ]
[ "$(/bin/cat "$path")" = caller-substitute ]
[ "$(/bin/cat "$caller_owned")" = caller-owned ]
[ "$(/bin/cat "$destination")" = destination-original ]
[ "$cleanup_ok" -eq 1 ]
cleanup_output_temp "$directory_record" "$record"
[ -e "$path" ]

hard_record=$(printf '%s\n' 'hard-payload' | measurement_output_helper create "$directory_record")
hard_path="$output_dir/$(printf '%s\n' "$hard_record" | /usr/bin/cut -f1)"
hard_caller="$output_dir/hard-caller.txt"
hard_destination="$output_dir/hard-destination.txt"
printf '%s\n' 'hard-caller' > "$hard_caller"
/bin/unlink "$hard_path"
/bin/ln "$hard_caller" "$hard_path"
printf '%s\n' 'hard-destination-original' > "$hard_destination"
cleanup_output_temp "$directory_record" "$hard_record"
[ -e "$hard_path" ]
[ "$(/bin/cat "$hard_caller")" = hard-caller ]
if publish_output_file "$directory_record" "$hard_record" hard-destination.txt; then exit 12; fi
[ -e "$hard_path" ]
[ "$(/bin/cat "$hard_caller")" = hard-caller ]
[ "$(/bin/cat "$hard_destination")" = hard-destination-original ]
"""#
    let result = try runShell(
      command,
      arguments: [temporaryDirectory.path, callerOwned.path, destination.path]
    )

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(try String(contentsOf: callerOwned, encoding: .utf8) == "caller-owned\n")
    #expect(try String(contentsOf: destination, encoding: .utf8) == "destination-original\n")
  }

  @Test func FleckPanelMeasurementStatisticsUseOnlyInMemoryTSV() throws {
    let source = try measurementScriptSource()
    #expect(!source.contains("raw_temp_path"))
    #expect(!source.contains("cut -f1"))

    let rows = ["sample_label\tsample_number\telapsed_ms", "cold\t1\t1"]
      + (2...31).map { "warm\t\($0)\t\($0)" }
    let fixture = rows.joined(separator: "\n")
    let command = try measurementStatisticsShellSource() + "\n" + #"""
set -eu
total_samples=31
measurement_output=$1
stats=$(calculate_measurement_statistics "$measurement_output")
[ "$stats" = "$(printf '31\t16\t30\t1\t31')" ]
"""#
    let result = try runShell(command, arguments: [fixture])

    #expect(result.status == 0, Comment(rawValue: result.stderr))
  }

  @Test func FleckPanelMeasurementRejectsHookTimeSourceSubstitution() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-hook-source-safety-" + UUID().uuidString, isDirectory: true)
    let hook = temporaryDirectory.appendingPathComponent("replace-source.sh")
    let callerOwned = temporaryDirectory.appendingPathComponent("caller-owned.txt")
    let destination = temporaryDirectory.appendingPathComponent("destination.txt")
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try "#!/bin/sh\nset -eu\n/bin/unlink \"$FLECK_MEASUREMENT_TEST_SOURCE_PATH\"\nprintf '%s\\n' 'hook-substitute' > \"$FLECK_MEASUREMENT_TEST_SOURCE_PATH\"\n".write(
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
hook=$2
caller_owned=$3
destination=$4
directory_record=$(measurement_output_directory_record "$output_dir")
bind_measurement_output_directory "$output_dir"

record=$(printf '%s\n' 'payload' | measurement_output_helper create "$directory_record")
source_path="$output_dir/$(printf '%s\n' "$record" | /usr/bin/cut -f1)"
printf '%s\n' 'caller-owned' > "$caller_owned"
printf '%s\n' 'destination-original' > "$destination"
export FLECK_MEASUREMENT_PUBLISH_HOOK="$hook"
export FLECK_MEASUREMENT_TEST_SOURCE_PATH="$source_path"
if publish_output_file "$directory_record" "$record" destination.txt; then exit 10; fi
unset FLECK_MEASUREMENT_PUBLISH_HOOK
[ -e "$source_path" ]
[ "$(/bin/cat "$source_path")" = hook-substitute ]
[ "$(/bin/cat "$caller_owned")" = caller-owned ]
[ "$(/bin/cat "$destination")" = destination-original ]
cleanup_output_temp "$directory_record" "$record"
[ -e "$source_path" ]
"""#
    let result = try runShell(
      command,
      arguments: [temporaryDirectory.path, hook.path, callerOwned.path, destination.path]
    )

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(try String(contentsOf: callerOwned, encoding: .utf8) == "caller-owned\n")
    #expect(try String(contentsOf: destination, encoding: .utf8) == "destination-original\n")
  }

  @Test func FleckPanelMeasurementRefusesFinalNameSubstitutionDuringExclusivePublication() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-exclusive-publication-" + UUID().uuidString, isDirectory: true)
    let sentinel = temporaryDirectory.appendingPathComponent("sentinel.txt")
    let foreignDirectory = temporaryDirectory.appendingPathComponent("foreign", isDirectory: true)
    let publishHook = temporaryDirectory.appendingPathComponent("substitute-destination.sh")
    try FileManager.default.createDirectory(at: foreignDirectory, withIntermediateDirectories: true)
    try "sentinel\n".write(to: sentinel, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nset -eu\ncase \"$FLECK_MEASUREMENT_TEST_MODE\" in\n  regular) printf '%s\\n' regular-substitute > \"$1\" ;;\n  symlink) /bin/ln -s \"$FLECK_MEASUREMENT_TEST_SENTINEL\" \"$1\" ;;\n  hard-link) /bin/ln \"$FLECK_MEASUREMENT_TEST_SENTINEL\" \"$1\" ;;\n  *) exit 2 ;;\nesac\n".write(
      to: publishHook,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o755)],
      ofItemAtPath: publishHook.path
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let command = try measurementOutputHelpersShellSource() + "\n" + #"""
set -eu
output_dir=$1
sentinel=$2
publish_hook=$3
directory_record=$(measurement_output_directory_record "$output_dir")
bind_measurement_output_directory "$output_dir"
export FLECK_MEASUREMENT_PUBLISH_HOOK="$publish_hook"
export FLECK_MEASUREMENT_TEST_SENTINEL="$sentinel"

run_case() {
  mode=$1
  destination=$2
  record=$(printf '%s\n' "$mode-payload" | measurement_output_helper create "$directory_record")
  export FLECK_MEASUREMENT_TEST_MODE="$mode"
  if publish_output_file "$directory_record" "$record" "$destination"; then
    exit 20
  fi
  unset FLECK_MEASUREMENT_TEST_MODE
  case "$mode" in
    regular)
      [ "$(/bin/cat "$output_dir/$destination")" = regular-substitute ]
      ;;
    symlink)
      [ -L "$output_dir/$destination" ]
      [ "$(/bin/cat "$output_dir/$destination")" = sentinel ]
      ;;
    hard-link)
      [ -f "$output_dir/$destination" ]
      [ "$(/bin/cat "$output_dir/$destination")" = sentinel ]
      ;;
  esac
  cleanup_output_temp "$directory_record" "$record"
  [ -z "$(find "$output_dir" -maxdepth 1 -name '.fleck-panel-measurement.*' -print -quit)" ]
}

run_case regular regular-destination
run_case symlink symlink-destination
run_case hard-link hard-link-destination
[ "$(/bin/cat "$sentinel")" = sentinel ]
"""#
    let result = try runShell(
      command,
      arguments: [temporaryDirectory.path, sentinel.path, publishHook.path]
    )

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "sentinel\n")
    #expect(try FileManager.default.contentsOfDirectory(atPath: foreignDirectory.path) == [])
  }

  @Test func FleckPanelMeasurementPinsOutputDirectoryAcrossPathReplacement() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-output-directory-pin-" + UUID().uuidString, isDirectory: true)
    let approvedDirectory = temporaryDirectory.appendingPathComponent("approved", isDirectory: true)
    let foreignDirectory = temporaryDirectory.appendingPathComponent("foreign", isDirectory: true)
    let approvedAside = temporaryDirectory.appendingPathComponent("approved-aside", isDirectory: true)
    let foreignSentinel = foreignDirectory.appendingPathComponent("sentinel.txt")
    try FileManager.default.createDirectory(at: approvedDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: foreignDirectory, withIntermediateDirectories: true)
    try "foreign\n".write(to: foreignSentinel, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let command = try measurementOutputHelpersShellSource() + "\n" + #"""
set -eu
approved=$1
foreign=$2
approved_aside=$3

directory_record=$(measurement_output_directory_record "$approved")
bind_measurement_output_directory "$approved"
/bin/mv "$approved" "$approved_aside"
/bin/ln -s "$foreign" "$approved"
record=$(printf '%s\n' 'bound-original' | measurement_output_helper create "$directory_record")
record_path=$(printf '%s\n' "$record" | /usr/bin/cut -f1)
[ -f "$approved_aside/$record_path" ]
cleanup_output_temp "$directory_record" "$record"
[ ! -e "$approved_aside/$record_path" ]
[ "$(/bin/cat "$foreign/sentinel.txt")" = foreign ]
leftover=$(find "$foreign" -maxdepth 1 -name '.fleck-panel-measurement.*' -print -quit)
[ -z "$leftover" ]
/bin/unlink "$approved"
/bin/mv "$approved_aside" "$approved"

/bin/mv "$approved" "$approved_aside"
/bin/mkdir "$approved"
record=$(printf '%s\n' 'bound-original-again' | measurement_output_helper create "$directory_record")
record_path=$(printf '%s\n' "$record" | /usr/bin/cut -f1)
[ -f "$approved_aside/$record_path" ]
cleanup_output_temp "$directory_record" "$record"
[ ! -e "$approved_aside/$record_path" ]
leftover=$(find "$approved" -maxdepth 1 -name '.fleck-panel-measurement.*' -print -quit)
[ -z "$leftover" ]
/bin/rmdir "$approved"
/bin/mv "$approved_aside" "$approved"
"""#
    let result = try runShell(
      command,
      arguments: [approvedDirectory.path, foreignDirectory.path, approvedAside.path]
    )

    #expect(result.status == 0, Comment(rawValue: result.stderr))
    #expect(try String(contentsOf: foreignSentinel, encoding: .utf8) == "foreign\n")
  }

  @Test func FleckPanelMeasurementRejectsControlCharactersInOutputDirectoryBeforePIDWork() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-output-directory-serialization-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let paths = [
      temporaryDirectory.appendingPathComponent("tab\toutput", isDirectory: true),
      temporaryDirectory.appendingPathComponent("carriage\routput", isDirectory: true),
      temporaryDirectory.appendingPathComponent("trailing-newline\n", isDirectory: true),
    ]
    for path in paths {
      try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
      let result = try run(
        script: repositoryRoot().appendingPathComponent("Scripts/measure-fleck-panel-presentation.sh"),
        arguments: [path.path],
        environment: ["FLECK_PERFORMANCE_PID": "0"]
      )
      #expect(result.status != 0)
      #expect(result.stderr.contains("tab, carriage return, or line feed"), Comment(rawValue: result.stderr))
    }

    let resolvedParent = temporaryDirectory.appendingPathComponent("resolved\nparent", isDirectory: true)
    let resolvedChild = resolvedParent.appendingPathComponent("output", isDirectory: true)
    let alias = temporaryDirectory.appendingPathComponent("alias", isDirectory: true)
    try FileManager.default.createDirectory(at: resolvedChild, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: resolvedParent)
    let resolvedResult = try run(
      script: repositoryRoot().appendingPathComponent("Scripts/measure-fleck-panel-presentation.sh"),
      arguments: [alias.appendingPathComponent("output", isDirectory: true).path],
      environment: ["FLECK_PERFORMANCE_PID": "0"]
    )
    #expect(resolvedResult.status != 0)
    #expect(
      resolvedResult.stderr.contains("tab, carriage return, or line feed"),
      Comment(rawValue: resolvedResult.stderr)
    )
  }

  @Test func FleckPanelMeasurementRollsBackEarlierPublicationOnLaterFailure() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-output-publication-rollback-" + UUID().uuidString, isDirectory: true)
    let outputDirectory = temporaryDirectory.appendingPathComponent("output", isDirectory: true)
    let publishHook = temporaryDirectory.appendingPathComponent("make-foreign-directory.sh")
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try "#!/bin/sh\nset -eu\nmkdir \"$1\"\nprintf '%s\\n' 'caller-owned' > \"$1/caller-owned.txt\"\n".write(
      to: publishHook,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o755)],
      ofItemAtPath: publishHook.path
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let command = try measurementOutputHelpersShellSource() + "\n" + #"""
set -eu
output_dir=$1
publish_hook=$2
directory_record=$(measurement_output_directory_record "$output_dir")
bind_measurement_output_directory "$output_dir"
raw_record=$(printf '%s\n' raw | measurement_output_helper create "$directory_record")
summary_record=$(printf '%s\n' summary | measurement_output_helper create "$directory_record")
metadata_record=$(printf '%s\n' metadata | measurement_output_helper create "$directory_record")

if ! publish_output_file "$directory_record" "$raw_record" raw.tsv; then exit 10; fi
published_raw=$published_record
export FLECK_MEASUREMENT_PUBLISH_HOOK="$publish_hook"
if publish_output_file "$directory_record" "$summary_record" summary.txt; then exit 11; fi
unset FLECK_MEASUREMENT_PUBLISH_HOOK

rollback_output_file "$directory_record" "$published_raw"
cleanup_output_temp "$directory_record" "$raw_record"
cleanup_output_temp "$directory_record" "$summary_record"
cleanup_output_temp "$directory_record" "$metadata_record"
[ ! -e "$output_dir/raw.tsv" ]
[ -d "$output_dir/summary.txt" ]
[ "$(/bin/cat "$output_dir/summary.txt/caller-owned.txt")" = caller-owned ]
[ ! -e "$output_dir/metadata.txt" ]
leftover=$(find "$output_dir" -maxdepth 1 -name '.fleck-panel-measurement.*' -print -quit)
[ -z "$leftover" ]
"""#
    let result = try runShell(command, arguments: [outputDirectory.path, publishHook.path])

    #expect(result.status == 0, Comment(rawValue: result.stderr))
  }

  @Test func FleckPanelMeasurementRollsBackThroughBoundDirectoryAfterPathReplacement() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-bound-rollback-" + UUID().uuidString, isDirectory: true)
    let outputDirectory = temporaryDirectory.appendingPathComponent("output", isDirectory: true)
    let originalDirectory = temporaryDirectory.appendingPathComponent("original", isDirectory: true)
    let foreignDirectory = temporaryDirectory.appendingPathComponent("foreign", isDirectory: true)
    let publishHook = temporaryDirectory.appendingPathComponent("make-summary-directory.sh")
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: foreignDirectory, withIntermediateDirectories: true)
    try "#!/bin/sh\nset -eu\nmkdir \"$1\"\nprintf '%s\\n' caller-owned > \"$1/caller-owned.txt\"\n".write(
      to: publishHook,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o755)],
      ofItemAtPath: publishHook.path
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let command = try measurementOutputHelpersShellSource() + "\n" + #"""
set -eu
output_dir=$1
original_dir=$2
foreign_dir=$3
publish_hook=$4
directory_record=$(measurement_output_directory_record "$output_dir")
bind_measurement_output_directory "$output_dir"
raw_record=$(printf '%s\n' raw | measurement_output_helper create "$directory_record")
summary_record=$(printf '%s\n' summary | measurement_output_helper create "$directory_record")
metadata_record=$(printf '%s\n' metadata | measurement_output_helper create "$directory_record")
if ! publish_output_file "$directory_record" "$raw_record" raw.tsv; then exit 10; fi
published_raw=$published_record
/bin/mv "$output_dir" "$original_dir"
/bin/ln -s "$foreign_dir" "$output_dir"
export FLECK_MEASUREMENT_PUBLISH_HOOK="$publish_hook"
if publish_output_file "$directory_record" "$summary_record" summary.txt; then exit 11; fi
unset FLECK_MEASUREMENT_PUBLISH_HOOK
rollback_output_file "$directory_record" "$published_raw"
cleanup_output_temp "$directory_record" "$raw_record"
cleanup_output_temp "$directory_record" "$summary_record"
cleanup_output_temp "$directory_record" "$metadata_record"
[ ! -e "$original_dir/raw.tsv" ]
[ -d "$original_dir/summary.txt" ]
[ "$(/bin/cat "$original_dir/summary.txt/caller-owned.txt")" = caller-owned ]
[ ! -e "$original_dir/metadata.txt" ]
[ -z "$(find "$original_dir" -maxdepth 1 -name '.fleck-panel-measurement.*' -print -quit)" ]
[ -z "$(find "$foreign_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]
[ -L "$output_dir" ]
"""#
    let result = try runShell(
      command,
      arguments: [
        outputDirectory.path,
        originalDirectory.path,
        foreignDirectory.path,
        publishHook.path,
      ]
    )

    #expect(result.status == 0, Comment(rawValue: result.stderr))
  }

  @Test func FleckPanelMeasurementContinuesInBoundDirectoryAfterPathReplacement() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-bound-success-" + UUID().uuidString, isDirectory: true)
    let outputDirectory = temporaryDirectory.appendingPathComponent("output", isDirectory: true)
    let originalDirectory = temporaryDirectory.appendingPathComponent("original", isDirectory: true)
    let foreignDirectory = temporaryDirectory.appendingPathComponent("foreign", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: foreignDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let command = try measurementOutputHelpersShellSource() + "\n" + #"""
set -eu
output_dir=$1
original_dir=$2
foreign_dir=$3
directory_record=$(measurement_output_directory_record "$output_dir")
bind_measurement_output_directory "$output_dir"
raw_record=$(printf '%s\n' raw | measurement_output_helper create "$directory_record")
summary_record=$(printf '%s\n' summary | measurement_output_helper create "$directory_record")
metadata_record=$(printf '%s\n' metadata | measurement_output_helper create "$directory_record")
if ! publish_output_file "$directory_record" "$raw_record" raw.tsv; then exit 10; fi
/bin/mv "$output_dir" "$original_dir"
/bin/ln -s "$foreign_dir" "$output_dir"
if ! publish_output_file "$directory_record" "$summary_record" summary.txt; then exit 11; fi
if ! publish_output_file "$directory_record" "$metadata_record" metadata.txt; then exit 12; fi
cleanup_output_temp "$directory_record" "$raw_record"
cleanup_output_temp "$directory_record" "$summary_record"
cleanup_output_temp "$directory_record" "$metadata_record"
[ "$(/bin/cat "$original_dir/raw.tsv")" = raw ]
[ "$(/bin/cat "$original_dir/summary.txt")" = summary ]
[ "$(/bin/cat "$original_dir/metadata.txt")" = metadata ]
[ -z "$(find "$original_dir" -maxdepth 1 -name '.fleck-panel-measurement.*' -print -quit)" ]
[ -z "$(find "$foreign_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]
[ -L "$output_dir" ]
"""#
    let result = try runShell(
      command,
      arguments: [outputDirectory.path, originalDirectory.path, foreignDirectory.path]
    )

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

  @Test func FleckPanelMeasurementRejectsFleckApplicationSupportIdentityAliasesBeforePIDWork() throws {
    let root = repositoryRoot()
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-home-canonicalization-" + UUID().uuidString, isDirectory: true)
    let homeDirectory = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
    let homeChild = homeDirectory.appendingPathComponent("child", isDirectory: true)
    let applicationSupport = homeDirectory
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent("Fleck", isDirectory: true)
    let applicationSupportChild = applicationSupport.appendingPathComponent("child", isDirectory: true)
    try FileManager.default.createDirectory(at: homeChild, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: applicationSupportChild, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let lexicalHome = homeChild.appendingPathComponent("..", isDirectory: true).path
    let script = root.appendingPathComponent("Scripts/measure-fleck-panel-presentation.sh")
    let protectedPaths = [applicationSupport, applicationSupportChild]
    for path in protectedPaths {
      let result = try run(
        script: script,
        arguments: [path.path],
        environment: ["HOME": lexicalHome, "FLECK_PERFORMANCE_PID": "0"]
      )
      #expect(result.status != 0)
      #expect(result.stderr.contains("Application Support"), Comment(rawValue: result.stderr))
      #expect(!result.stderr.contains("must identify Fleck"), Comment(rawValue: result.stderr))
    }

    let caseVariedApplicationSupport = homeDirectory
      .appendingPathComponent("library", isDirectory: true)
      .appendingPathComponent("application support", isDirectory: true)
      .appendingPathComponent("fleck", isDirectory: true)
    guard FileManager.default.fileExists(atPath: caseVariedApplicationSupport.path) else {
      return
    }
    let caseVariedChild = caseVariedApplicationSupport.appendingPathComponent("child", isDirectory: true)
    for path in [caseVariedApplicationSupport, caseVariedChild] {
      let result = try run(
        script: script,
        arguments: [path.path],
        environment: ["HOME": lexicalHome, "FLECK_PERFORMANCE_PID": "0"]
      )
      #expect(result.status != 0)
      #expect(result.stderr.contains("Application Support"), Comment(rawValue: result.stderr))
      #expect(!result.stderr.contains("must identify Fleck"), Comment(rawValue: result.stderr))
    }
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
    let stderr: String
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
    let error = Pipe()
    process.standardError = error
    try process.run()
    let stderrData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return CommandResult(
      status: process.terminationStatus,
      stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
  }

  private func measurementOutputDirectoryRecordShellSource() throws -> String {
    let source = try measurementScriptSource()
    let begin = try #require(source.range(of: "# AX_MEASUREMENT_DIRECTORY_RECORD_BEGIN\n"))
    let end = try #require(
      source.range(
        of: "\n# AX_MEASUREMENT_DIRECTORY_RECORD_END",
        range: begin.upperBound..<source.endIndex
      )
    )
    return String(source[begin.upperBound..<end.lowerBound])
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
    return try measurementOutputDirectoryRecordShellSource()
      + "\n"
      + String(source[begin.upperBound..<end.lowerBound])
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

  private func measurementStatisticsShellSource() throws -> String {
    let source = try measurementScriptSource()
    let begin = try #require(source.range(of: "# AX_MEASUREMENT_STATS_BEGIN\n"))
    let end = try #require(
      source.range(
        of: "\n# AX_MEASUREMENT_STATS_END",
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
        of: "\n'\n}",
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
