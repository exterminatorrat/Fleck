#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import Testing

private struct FakeFixture {
  let root: URL
  let build: URL
  let tools: URL
  let gemmaPackage: URL
  let temporaryDirectory: URL
  let holdFile: URL
  let resolverEntered: URL
  let entries: URL
  let candidateLock: URL
  let originalLock: URL
  let originalGemmaLock: URL
  let gemmaBuildLog: URL
  let codesignLog: URL
  let rpathState: URL
  let unsafeStaging: URL
  let appScript: URL
}

private struct RunningPackager {
  let process: Process
  let standardError: Pipe
}

private enum FixtureError: Error {
  case missingRepositoryRoot
}

private var fileManager: FileManager { .default }

private func repositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

private func writeExecutable(_ source: String, to url: URL) throws {
  try Data(source.utf8).write(to: url)
  try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: url.path)
}

private func makeFakeFixture() throws -> FakeFixture {
  let sourceRoot = repositoryRoot()
  guard fileManager.fileExists(atPath: sourceRoot.appendingPathComponent("Package.resolved").path) else {
    throw FixtureError.missingRepositoryRoot
  }

  let root = fileManager.temporaryDirectory
    .appendingPathComponent("fleck-parakeet-packaging-\(UUID().uuidString)", isDirectory: true)
  let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
  let sources = root.appendingPathComponent("Sources/FleckApp/Resources", isDirectory: true)
  let tools = root.appendingPathComponent("tools", isDirectory: true)
  let gemmaPackage = root.appendingPathComponent(
    "Tools/GemmaCleanupBenchmark/NativeRuntime",
    isDirectory: true
  )
  let build = root.appendingPathComponent(".build", isDirectory: true)
  let temporaryDirectory = root.appendingPathComponent("tmp", isDirectory: true)
  try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
  try fileManager.createDirectory(at: sources, withIntermediateDirectories: true)
  try fileManager.createDirectory(at: tools, withIntermediateDirectories: true)
  try fileManager.createDirectory(at: gemmaPackage, withIntermediateDirectories: true)
  try fileManager.createDirectory(at: build, withIntermediateDirectories: true)
  try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  try fileManager.createDirectory(
    at: root.appendingPathComponent("website/public", isDirectory: true),
    withIntermediateDirectories: true
  )

  let appScript = scripts.appendingPathComponent("build-parakeet-test-app.sh")
  try fileManager.copyItem(
    at: sourceRoot.appendingPathComponent("Scripts/build-parakeet-test-app.sh"),
    to: appScript
  )
  try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: appScript.path)
  try Data("candidate lock\n".utf8).write(to: root.appendingPathComponent("candidate.Package.resolved"))
  try fileManager.copyItem(
    at: sourceRoot.appendingPathComponent("Package.resolved"),
    to: root.appendingPathComponent("Package.resolved")
  )
  try fileManager.copyItem(
    at: sourceRoot.appendingPathComponent("Sources/FleckApp/Info.plist"),
    to: root.appendingPathComponent("Sources/FleckApp/Info.plist")
  )
  try fileManager.copyItem(
    at: sourceRoot.appendingPathComponent("website/public/fleck-mark.png"),
    to: root.appendingPathComponent("website/public/fleck-mark.png")
  )
  try fileManager.copyItem(
    at: sourceRoot.appendingPathComponent("Sources/FleckApp/Resources/EnhancedModelManifest.json"),
    to: sources.appendingPathComponent("EnhancedModelManifest.json")
  )
  try fileManager.copyItem(
    at: sourceRoot.appendingPathComponent("Sources/FleckApp/Resources/ThirdPartyNotices.md"),
    to: sources.appendingPathComponent("ThirdPartyNotices.md")
  )
  try fileManager.copyItem(
    at: sourceRoot.appendingPathComponent("Tools/GemmaCleanupBenchmark/NativeRuntime/Package.swift"),
    to: gemmaPackage.appendingPathComponent("Package.swift")
  )
  try fileManager.copyItem(
    at: sourceRoot.appendingPathComponent("Tools/GemmaCleanupBenchmark/NativeRuntime/Package.resolved"),
    to: gemmaPackage.appendingPathComponent("Package.resolved")
  )

  let originalLock = root.appendingPathComponent("original.Package.resolved")
  try fileManager.copyItem(
    at: root.appendingPathComponent("Package.resolved"),
    to: originalLock
  )
  let originalGemmaLock = root.appendingPathComponent("original.NativeRuntime.Package.resolved")
  try fileManager.copyItem(
    at: gemmaPackage.appendingPathComponent("Package.resolved"),
    to: originalGemmaLock
  )
  let holdFile = root.appendingPathComponent("hold")
  try Data().write(to: holdFile)
  let gemmaBuildLog = root.appendingPathComponent("gemma-build.log")
  let codesignLog = root.appendingPathComponent("codesign.log")

  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    [[ "$1" == "--find" ]]
    case "$2" in
      swift) printf '%s\n' "$FAKE_TOOLS/swift" ;;
      codesign) printf '%s\n' "$FAKE_TOOLS/codesign" ;;
      lipo) printf '%s\n' "$FAKE_TOOLS/lipo" ;;
      otool) printf '%s\n' "$FAKE_TOOLS/otool" ;;
      install_name_tool) printf '%s\n' "$FAKE_TOOLS/install_name_tool" ;;
      *) exit 2 ;;
    esac
    """#, to: tools.appendingPathComponent("xcrun"))
  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    if [[ "$1" == "-e" ]]; then
      args=("$@")
      last=$(( $# - 1 ))
      staged="${args[$((last - 1))]}"
      destination="${args[$last]}"
      [[ ! -e "$destination" && ! -L "$destination" ]]
      /bin/mv "$staged" "$destination"
      exit 0
    fi
    scratch=""
    package_path=""
    product=""
    show_bin=0
    while (($#)); do
      case "$1" in
        --package-path) package_path="$2"; shift 2 ;;
        --scratch-path) scratch="$2"; shift 2 ;;
        --product) product="$2"; shift 2 ;;
        --show-bin-path) show_bin=1; shift ;;
        *) shift ;;
      esac
    done
    bin="$scratch/arm64-apple-macosx/debug"
    /bin/mkdir -p "$bin"
    if [[ "$product" == "Fleck" ]]; then
      printf '%s\n' "$FAKE_RUN_ID" > "$bin/Fleck"
      /bin/chmod 755 "$bin/Fleck"
      /bin/mkdir -p "$bin/Fleck_FleckApp.bundle"
      /bin/cp "$FAKE_MANIFEST" "$bin/Fleck_FleckApp.bundle/EnhancedModelManifest.json"
      /bin/cp "$FAKE_NOTICES" "$bin/Fleck_FleckApp.bundle/ThirdPartyNotices.md"
    elif [[ "$product" == "fleck-agent" ]]; then
      printf '%s\n' "$FAKE_RUN_ID" > "$bin/fleck-agent"
      /bin/chmod 755 "$bin/fleck-agent"
    elif [[ "$product" == "gemma-cleanup-helper" ]]; then
      [[ "$package_path" == "$FAKE_GEMMA_PACKAGE" ]]
      printf 'package=%s\nscratch=%s\nproduct=%s\n' \
        "$package_path" "$scratch" "$product" > "$FAKE_GEMMA_BUILD_LOG"
      if [[ "${FAKE_GEMMA_BUILD_FAIL:-0}" == "1" ]]; then
        exit 77
      fi
      printf 'gemma-helper-%s\n' "$FAKE_RUN_ID" > "$bin/gemma-cleanup-helper"
      /bin/chmod 755 "$bin/gemma-cleanup-helper"
    fi
    if (( show_bin )); then
      printf '%s\n' "$bin"
    fi
    """#, to: tools.appendingPathComponent("swift"))
  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    case "$1" in
      -l)
        printf 'Load command 0\n'
        printf '      cmd LC_RPATH\n'
        printf '      cmdsize 32\n'
        printf '      path /usr/lib/swift (offset 12)\n'
        if [[ ! -e "$FAKE_RPATH_STATE" ]]; then
          printf 'Load command 1\n'
          printf '      cmd LC_RPATH\n'
          printf '      cmdsize 80\n'
          printf '      path /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx (offset 12)\n'
        fi
        ;;
      -L)
        printf '%s:\n' "$2"
        printf '\t/usr/lib/swift/libswiftCore.dylib (compatibility version 0.0.0, current version 0.0.0)\n'
        ;;
      *) exit 2 ;;
    esac
    """#, to: tools.appendingPathComponent("otool"))
  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    [[ "$1" == "-delete_rpath" ]]
    printf '%s\n' "$2" > "$FAKE_RPATH_STATE"
    """#, to: tools.appendingPathComponent("install_name_tool"))
  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    if [[ "$1" == "--force" ]]; then
      args=("$@")
      path="${args[$(( $# - 1 ))]}"
      identifier=""
      for ((index = 0; index < $#; index++)); do
        if [[ "${args[$index]}" == "--identifier" ]]; then
          identifier="${args[$((index + 1))]}"
        fi
      done
      printf '%s|%s\n' "$path" "$identifier" >> "$FAKE_CODESIGN_LOG"
    fi
    case "$1" in
      --force) exit 0 ;;
      --verify) exit 0 ;;
      -dv)
        args=("$@")
        path="${args[$(( $# - 1 ))]}"
        if [[ "$path" == *"gemma-cleanup-helper" ]]; then
          printf 'Identifier=com.harryjin.fleck.gemma-cleanup-helper\nSignature=adhoc\n' >&2
        elif [[ "$path" == *"fleck-agent" ]]; then
          printf 'Identifier=com.harryjin.fleck.agent\nSignature=adhoc\n' >&2
        else
          printf 'Identifier=com.harryjin.fleck\nSignature=adhoc\n' >&2
        fi
        ;;
      -d)
        printf 'designated => identifier "com.harryjin.fleck"\n' >&2
        ;;
      *) exit 2 ;;
    esac
    """#, to: tools.appendingPathComponent("codesign"))
  try writeExecutable("#!/bin/bash\nprintf 'arm64\\n'\n", to: tools.appendingPathComponent("lipo"))
  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    if [[ "$FAKE_UNSAFE_STAGING" == "1" && "$1" == "-d" && "$2" == *".parakeet-test."* ]]; then
      /bin/mkdir -p "$FAKE_UNSAFE_STAGING_PATH"
      printf '%s\n' "$FAKE_UNSAFE_STAGING_PATH"
      exit 0
    fi
    exec /usr/bin/mktemp "$@"
    """#, to: tools.appendingPathComponent("mktemp"))

  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    scratch="$1"
    shift
    /bin/cp "$FAKE_CANDIDATE_LOCK" "$FAKE_REPO/Package.resolved"
    restore() { /bin/cp "$FAKE_ORIGINAL_LOCK" "$FAKE_REPO/Package.resolved"; }
    trap restore EXIT
    printf '%s\n' "$FAKE_RUN_ID" >> "$FAKE_ENTRIES"
    : > "$FAKE_RESOLVER_ENTERED"
    while [[ -e "$FAKE_HOLD" ]]; do
      /bin/sleep 0.02
    done
    "$@"
    """#, to: scripts.appendingPathComponent("resolve-enhanced-candidate.sh"))

  return FakeFixture(
    root: root,
    build: build,
    tools: tools,
    gemmaPackage: gemmaPackage,
    temporaryDirectory: temporaryDirectory,
    holdFile: holdFile,
    resolverEntered: root.appendingPathComponent("resolver-entered"),
    entries: root.appendingPathComponent("entries"),
    candidateLock: root.appendingPathComponent("candidate.Package.resolved"),
    originalLock: originalLock,
    originalGemmaLock: originalGemmaLock,
    gemmaBuildLog: gemmaBuildLog,
    codesignLog: codesignLog,
    rpathState: root.appendingPathComponent("rpath-state"),
    unsafeStaging: root.appendingPathComponent("unsafe-staging"),
    appScript: appScript
  )
}

private func environment(
  for fixture: FakeFixture,
  runID: String,
  unsafeStaging: Bool = false,
  gemmaBuildFails: Bool = false
) -> [String: String] {
  var environment = ProcessInfo.processInfo.environment
  let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
  environment["PATH"] = "\(fixture.tools.path):\(existingPath)"
  environment["TMPDIR"] = fixture.temporaryDirectory.path
  environment["FAKE_REPO"] = fixture.root.path
  environment["FAKE_TOOLS"] = fixture.tools.path
  environment["FAKE_RUN_ID"] = runID
  environment["FAKE_MANIFEST"] = fixture.root.appendingPathComponent("Sources/FleckApp/Resources/EnhancedModelManifest.json").path
  environment["FAKE_NOTICES"] = fixture.root.appendingPathComponent("Sources/FleckApp/Resources/ThirdPartyNotices.md").path
  environment["FAKE_GEMMA_PACKAGE"] = fixture.gemmaPackage.path
  environment["FAKE_GEMMA_BUILD_LOG"] = fixture.gemmaBuildLog.path
  environment["FAKE_GEMMA_BUILD_FAIL"] = gemmaBuildFails ? "1" : "0"
  environment["FAKE_CODESIGN_LOG"] = fixture.codesignLog.path
  environment["FAKE_CANDIDATE_LOCK"] = fixture.candidateLock.path
  environment["FAKE_ORIGINAL_LOCK"] = fixture.originalLock.path
  environment["FAKE_HOLD"] = unsafeStaging
    ? fixture.root.appendingPathComponent("no-hold").path
    : fixture.holdFile.path
  environment["FAKE_RESOLVER_ENTERED"] = fixture.resolverEntered.path
  environment["FAKE_ENTRIES"] = fixture.entries.path
  environment["FAKE_RPATH_STATE"] = fixture.rpathState.path
  environment["FAKE_UNSAFE_STAGING"] = unsafeStaging ? "1" : "0"
  environment["FAKE_UNSAFE_STAGING_PATH"] = fixture.unsafeStaging.path
  return environment
}

private func launchPackager(
  fixture: FakeFixture,
  runID: String,
  unsafeStaging: Bool = false,
  gemmaBuildFails: Bool = false
) throws -> RunningPackager {
  let standardError = Pipe()
  let process = Process()
  process.executableURL = fixture.appScript
  process.currentDirectoryURL = fixture.root
  process.environment = environment(
    for: fixture,
    runID: runID,
    unsafeStaging: unsafeStaging,
    gemmaBuildFails: gemmaBuildFails
  )
  process.standardOutput = FileHandle.nullDevice
  process.standardError = standardError
  try process.run()
  return RunningPackager(process: process, standardError: standardError)
}

private func waitForPath(_ url: URL, timeout: TimeInterval = 5) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if fileManager.fileExists(atPath: url.path) {
      return true
    }
    Thread.sleep(forTimeInterval: 0.02)
  }
  return fileManager.fileExists(atPath: url.path)
}

private func waitForExit(_ running: RunningPackager, timeout: TimeInterval = 10) {
  let deadline = Date().addingTimeInterval(timeout)
  while running.process.isRunning && Date() < deadline {
    Thread.sleep(forTimeInterval: 0.02)
  }
  if running.process.isRunning {
    running.process.terminate()
  }
  running.process.waitUntilExit()
}

private func output(from pipe: Pipe) -> String {
  String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

@Test
func parakeetTestAppPackagingScriptUsesContentsResourcesBundle() {
  let script = repositoryRoot().appendingPathComponent("Scripts/build-parakeet-test-app.sh")
  let executable = fileManager.isExecutableFile(atPath: script.path)

  #expect(executable)
  guard executable, let source = try? String(contentsOf: script, encoding: .utf8) else {
    return
  }

  #expect(source.contains(#"readonly staged_bundle="$staged_app/Contents/Resources/Fleck_FleckApp.bundle""#))
  #expect(source.contains("Contents/Resources/Fleck_FleckApp.bundle/EnhancedModelManifest.json"))
  #expect(source.contains("Contents/Resources/Fleck_FleckApp.bundle/ThirdPartyNotices.md"))
  #expect(source.contains(#"publish_atomic "$staged_app" "$app_destination""#))
  #expect(!source.contains(#"publish_atomic "$staged_app/Fleck_FleckApp.bundle""#))
  #expect(!source.contains(#"publish_atomic "$sibling_resource_output""#))
  #expect(!source.contains("bundle_destination"))
  #expect(!source.contains(#"publish_atomic "$staged_bundle""#))
  #expect(source.contains("mkdir \"$lock_path\""))
  #expect(source.contains("another Parakeet test app packager is already running"))
  #expect(source.contains("validate_cleanup_target"))
  #expect(source.contains("cleanup marker"))
  #expect(source.contains("LC_RPATH"))
  #expect(source.contains("delete_rpath"))
  #expect(source.contains("/usr/lib/swift"))
  #expect(source.contains("@executable_path/"))
  #expect(source.contains("@loader_path/"))
  #expect(source.contains("Tools/GemmaCleanupBenchmark/NativeRuntime"))
  #expect(source.contains("gemma-cleanup-helper"))
  #expect(source.contains("Contents/SharedSupport/gemma-cleanup-helper"))
  #expect(source.contains("$bundle_identifier.gemma-cleanup-helper"))
  #expect(source.contains("--disable-automatic-resolution"))
  #expect(!source.contains("admitted Enhanced Local Parakeet model"))
  #expect(source.contains("pinned experimental Parakeet candidate"))
}

@Test
func parakeetPackagersSerializeSharedResolutionAndPublication() throws {
  let fixture = try makeFakeFixture()
  defer { try? fileManager.removeItem(at: fixture.root) }

  var first: RunningPackager?
  var second: RunningPackager?
  defer {
    try? fileManager.removeItem(at: fixture.holdFile)
    if let first, first.process.isRunning {
      first.process.terminate()
      first.process.waitUntilExit()
    }
    if let second, second.process.isRunning {
      second.process.terminate()
      second.process.waitUntilExit()
    }
  }

  first = try launchPackager(fixture: fixture, runID: "first")
  #expect(waitForPath(fixture.resolverEntered))
  second = try launchPackager(fixture: fixture, runID: "second")
  if let second {
    waitForExit(second)
    let error = output(from: second.standardError)
    #expect(second.process.terminationStatus != 0)
    #expect(error.contains("another Parakeet test app packager is already running"))
  }

  try fileManager.removeItem(at: fixture.holdFile)
  if let first {
    waitForExit(first)
    #expect(first.process.terminationStatus == 0)
  }

  let entries = try String(contentsOf: fixture.entries, encoding: .utf8)
    .split(whereSeparator: \.isNewline)
  #expect(entries == ["first"])
  let restoredLock = try Data(contentsOf: fixture.root.appendingPathComponent("Package.resolved"))
  let originalLock = try Data(contentsOf: fixture.originalLock)
  #expect(restoredLock == originalLock)
  let restoredGemmaLock = try Data(contentsOf: fixture.gemmaPackage.appendingPathComponent("Package.resolved"))
  let originalGemmaLock = try Data(contentsOf: fixture.originalGemmaLock)
  #expect(restoredGemmaLock == originalGemmaLock)

  let gemmaBuildLines = try String(contentsOf: fixture.gemmaBuildLog, encoding: .utf8)
    .split(whereSeparator: \.isNewline)
    .map(String.init)
  func normalizedTemporaryPath(_ path: String) -> String {
    path.replacingOccurrences(of: "/private/var/", with: "/var/")
  }
  #expect(gemmaBuildLines.count == 3)
  #expect(normalizedTemporaryPath(gemmaBuildLines[0]) == "package=\(normalizedTemporaryPath(fixture.gemmaPackage.path))")
  #expect(normalizedTemporaryPath(gemmaBuildLines[1]).hasPrefix("scratch=\(normalizedTemporaryPath(fixture.build.path))/.parakeet-gemma-cleanup."))
  #expect(gemmaBuildLines[2] == "product=gemma-cleanup-helper")

  let app = fixture.build.appendingPathComponent("parakeet-test/Fleck.app")
  let executableContents = try String(
    contentsOf: app.appendingPathComponent("Contents/MacOS/Fleck"),
    encoding: .utf8
  )
  #expect(executableContents == "first\n")
  let helper = app.appendingPathComponent("Contents/SharedSupport/gemma-cleanup-helper")
  #expect(fileManager.isExecutableFile(atPath: helper.path))
  #expect(try String(contentsOf: helper, encoding: .utf8) == "gemma-helper-first\n")
  let appContents = fileManager.subpaths(atPath: app.path) ?? []
  #expect(appContents.filter { $0 == "Contents/SharedSupport/gemma-cleanup-helper" }.count == 1)

  let signEvents = try String(contentsOf: fixture.codesignLog, encoding: .utf8)
    .split(whereSeparator: \.isNewline)
    .map(String.init)
  #expect(signEvents.count == 3)
  #expect(signEvents[0].hasSuffix("/Contents/SharedSupport/gemma-cleanup-helper|com.harryjin.fleck.gemma-cleanup-helper"))
  #expect(signEvents[1].hasSuffix("/Contents/SharedSupport/fleck-agent|com.harryjin.fleck.agent"))
  #expect(signEvents[2].hasSuffix("/Fleck.app|com.harryjin.fleck"))
  #expect(!fileManager.fileExists(atPath: fixture.build.appendingPathComponent("Fleck_FleckApp.bundle").path))
  #expect(!fileManager.fileExists(atPath: fixture.build.appendingPathComponent(".parakeet-test.lock").path))
  #expect((try? fileManager.contentsOfDirectory(atPath: fixture.temporaryDirectory.path))?.isEmpty == true)
  let buildChildren = try fileManager.contentsOfDirectory(atPath: fixture.build.path)
  #expect(!buildChildren.contains(where: { $0.hasPrefix(".parakeet-test.") }))
  #expect(!buildChildren.contains(where: { $0.hasPrefix(".parakeet-gemma-cleanup.") }))
}

@Test
func parakeetPackagerCleansHelperBuildAfterFailure() throws {
  let fixture = try makeFakeFixture()
  defer { try? fileManager.removeItem(at: fixture.root) }

  let running = try launchPackager(fixture: fixture, runID: "failed", gemmaBuildFails: true)
  waitForExit(running)
  #expect(!running.process.isRunning)
  #expect(running.process.terminationStatus != 0)
  #expect(!fileManager.fileExists(atPath: fixture.build.appendingPathComponent("parakeet-test/Fleck.app").path))
  #expect(!fileManager.fileExists(atPath: fixture.build.appendingPathComponent(".parakeet-test.lock").path))
  #expect(!fileManager.fileExists(atPath: fixture.codesignLog.path))
  #expect((try? fileManager.contentsOfDirectory(atPath: fixture.temporaryDirectory.path))?.isEmpty == true)
  let buildChildren = try fileManager.contentsOfDirectory(atPath: fixture.build.path)
  #expect(!buildChildren.contains(where: { $0.hasPrefix(".parakeet-gemma-cleanup.") }))

  let restoredLock = try Data(contentsOf: fixture.root.appendingPathComponent("Package.resolved"))
  let originalLock = try Data(contentsOf: fixture.originalLock)
  #expect(restoredLock == originalLock)
  let restoredGemmaLock = try Data(contentsOf: fixture.gemmaPackage.appendingPathComponent("Package.resolved"))
  let originalGemmaLock = try Data(contentsOf: fixture.originalGemmaLock)
  #expect(restoredGemmaLock == originalGemmaLock)
}

@Test
func parakeetPackagerRefusesUnsafeTempSubstitution() throws {
  let fixture = try makeFakeFixture()
  defer { try? fileManager.removeItem(at: fixture.root) }

  let running = try launchPackager(fixture: fixture, runID: "unsafe", unsafeStaging: true)
  waitForExit(running)
  let error = output(from: running.standardError)
  #expect(running.process.terminationStatus != 0)
  #expect(error.contains("refusing cleanup"))
  #expect(fileManager.fileExists(atPath: fixture.unsafeStaging.path))
  #expect(!fileManager.fileExists(atPath: fixture.build.appendingPathComponent("parakeet-test/Fleck.app").path))
  #expect(!fileManager.fileExists(atPath: fixture.build.appendingPathComponent("Fleck_FleckApp.bundle").path))
  #expect(!fileManager.fileExists(atPath: fixture.build.appendingPathComponent(".parakeet-test.lock").path))
  let restoredLock = try Data(contentsOf: fixture.root.appendingPathComponent("Package.resolved"))
  let originalLock = try Data(contentsOf: fixture.originalLock)
  #expect(restoredLock == originalLock)
}
#endif
