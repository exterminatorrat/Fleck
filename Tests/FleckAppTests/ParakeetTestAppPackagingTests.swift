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
  let xcodeBuildLog: URL
  let xcodeBuildEntered: URL
  let xcodeHoldFile: URL
  let helperToolLog: URL
  let codesignLog: URL
  let codesignVerifyLog: URL
  let rpathState: URL
  let unsafeStaging: URL
  let gemmaResourceMode: String
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

private func makeFakeFixture(gemmaResourceMode: String = "valid") throws -> FakeFixture {
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
  let xcodeBuildLog = root.appendingPathComponent("xcode-build.log")
  let xcodeBuildEntered = root.appendingPathComponent("xcode-build-entered")
  let xcodeHoldFile = root.appendingPathComponent("xcode-hold")
  let helperToolLog = root.appendingPathComponent("helper-tool.log")
  let codesignLog = root.appendingPathComponent("codesign.log")
  let codesignVerifyLog = root.appendingPathComponent("codesign-verify.log")

  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    [[ "$1" == "--find" ]]
    case "$2" in
      swift) printf '%s\n' "$FAKE_TOOLS/swift" ;;
      xcodebuild) printf '%s\n' "$FAKE_TOOLS/xcodebuild" ;;
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
    product=""
    show_bin=0
    while (($#)); do
      case "$1" in
        --package-path)
          printf '%s\n' 'unsupported Swift-package build route' >&2
          exit 92
          ;;
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
    fi
    if (( show_bin )); then
      printf '%s\n' "$bin"
    fi
    """#, to: tools.appendingPathComponent("swift"))
  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    if [[ "${1:-}" == "-version" ]]; then
      printf '%s\n' 'Xcode 16.4'
      exit 0
    fi
    scheme=""
    configuration=""
    destination=""
    derived_data=""
    products=""
    architectures=""
    only_active_arch=""
    action=""
    while (($#)); do
      case "$1" in
        -scheme) scheme="$2"; shift 2 ;;
        -configuration) configuration="$2"; shift 2 ;;
        -destination) destination="$2"; shift 2 ;;
        -derivedDataPath) derived_data="$2"; shift 2 ;;
        CONFIGURATION_BUILD_DIR=*) products="${1#*=}"; shift ;;
        ARCHS=*) architectures="${1#*=}"; shift ;;
        ONLY_ACTIVE_ARCH=*) only_active_arch="${1#*=}"; shift ;;
        build) action="build"; shift ;;
        *) shift ;;
      esac
    done
    [[ "$action" == "build" ]]
    [[ "$(pwd -P)" == "$FAKE_GEMMA_PACKAGE" ]]
    [[ "$scheme" == "gemma-cleanup-helper" ]]
    [[ "$configuration" == "Release" ]]
    [[ "$destination" == "generic/platform=macOS" ]]
    [[ "$products" == "$derived_data/Products" ]]
    [[ "$architectures" == "arm64" ]]
    [[ "$only_active_arch" == "YES" ]]
    printf 'cwd=%s\nscheme=%s\nconfiguration=%s\ndestination=%s\nderivedData=%s\nproducts=%s\narchitectures=%s\nonlyActiveArch=%s\n' \
      "$(pwd -P)" "$scheme" "$configuration" "$destination" "$derived_data" \
      "$products" "$architectures" "$only_active_arch" \
      > "$FAKE_XCODE_BUILD_LOG"
    : > "$FAKE_XCODE_BUILD_ENTERED"
    if [[ "${FAKE_GEMMA_MUTATE_LOCK:-0}" == "1" ]]; then
      printf 'mutated by xcodebuild\n' > "$FAKE_GEMMA_PACKAGE/Package.resolved"
    fi
    while [[ -e "$FAKE_XCODE_HOLD" ]]; do
      /bin/sleep 0.02
    done
    product="$products"
    /bin/mkdir -p "$product"
    if [[ "${FAKE_GEMMA_BUILD_FAIL:-0}" == "1" ]]; then
      exit 77
    fi
    printf 'gemma-helper-%s\n' "$FAKE_RUN_ID" > "$product/gemma-cleanup-helper"
    /bin/chmod 755 "$product/gemma-cleanup-helper"
    /bin/mkdir -p \
      "$product/gemma-cleanup-helper.dSYM/Contents/Resources/DWARF"
    /bin/cp "$product/gemma-cleanup-helper" \
      "$product/gemma-cleanup-helper.dSYM/Contents/Resources/DWARF/gemma-cleanup-helper"
    printf 'dSYM=%s\n' \
      "$product/gemma-cleanup-helper.dSYM/Contents/Resources/DWARF/gemma-cleanup-helper" \
      >> "$FAKE_XCODE_BUILD_LOG"
    case "$FAKE_GEMMA_RESOURCE_MODE" in
      valid)
        /bin/mkdir -p "$product/mlx-swift_Cmlx.bundle/Contents/Resources"
        printf 'mlx-bundle-info-%s\n' "$FAKE_RUN_ID" \
          > "$product/mlx-swift_Cmlx.bundle/Contents/Info.plist"
        printf 'default-metallib-%s\n' "$FAKE_RUN_ID" \
          > "$product/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        ;;
      missing-bundle)
        ;;
      missing-metadata)
        /bin/mkdir -p "$product/mlx-swift_Cmlx.bundle/Contents/Resources"
        printf 'default-metallib-%s\n' "$FAKE_RUN_ID" \
          > "$product/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        ;;
      missing-metallib)
        /bin/mkdir -p "$product/mlx-swift_Cmlx.bundle/Contents/Resources"
        printf 'mlx-bundle-info-%s\n' "$FAKE_RUN_ID" \
          > "$product/mlx-swift_Cmlx.bundle/Contents/Info.plist"
        ;;
      wrong-resource)
        /bin/mkdir -p "$product/mlx-swift_Cmlx.bundle/Contents/Resources"
        printf 'mlx-bundle-info-%s\n' "$FAKE_RUN_ID" \
          > "$product/mlx-swift_Cmlx.bundle/Contents/Info.plist"
        printf 'wrong-resource\n' \
          > "$product/mlx-swift_Cmlx.bundle/Contents/Resources/wrong.metallib"
        ;;
      extra-resource)
        /bin/mkdir -p "$product/mlx-swift_Cmlx.bundle/Contents/Resources"
        printf 'mlx-bundle-info-%s\n' "$FAKE_RUN_ID" \
          > "$product/mlx-swift_Cmlx.bundle/Contents/Info.plist"
        printf 'default-metallib-%s\n' "$FAKE_RUN_ID" \
          > "$product/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        printf 'extra\n' > "$product/mlx-swift_Cmlx.bundle/Contents/Resources/extra.txt"
        ;;
      symlink-resource)
        /bin/mkdir -p "$product/mlx-swift_Cmlx.bundle/Contents/Resources"
        printf 'mlx-bundle-info-%s\n' "$FAKE_RUN_ID" \
          > "$product/mlx-swift_Cmlx.bundle/Contents/Info.plist"
        /bin/ln -s /tmp/missing-metallib \
          "$product/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        ;;
      *) exit 91 ;;
    esac
    printf 'product=%s\nresource=%s\n' \
      "$product/gemma-cleanup-helper" "$product/mlx-swift_Cmlx.bundle" \
      >> "$FAKE_XCODE_BUILD_LOG"
    """#, to: tools.appendingPathComponent("xcodebuild"))
  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    operation="$1"
    path="$2"
    printf 'otool|%s|%s\n' "$operation" "$path" >> "$FAKE_HELPER_TOOL_LOG"
    case "$1" in
      -l)
        printf 'Load command 0\n'
        printf '      cmd LC_RPATH\n'
        printf '      cmdsize 32\n'
        printf '      path /usr/lib/swift (offset 12)\n'
        path_state="$FAKE_RPATH_STATE.$(/usr/bin/basename "$path")"
        if [[ ! -e "$path_state" ]]; then
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
    path="${@: -1}"
    printf 'install_name_tool|-delete_rpath|%s|%s\n' "$2" "$path" \
      >> "$FAKE_HELPER_TOOL_LOG"
    printf '%s\n' "$2" > "$FAKE_RPATH_STATE"
    : > "$FAKE_RPATH_STATE.$(/usr/bin/basename "$path")"
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
      --verify)
        path="${@: -1}"
        printf '%s\n' "$path" >> "$FAKE_CODESIGN_VERIFY_LOG"
        exit 0
        ;;
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
  try writeExecutable(#"""
    #!/bin/bash
    set -euo pipefail
    [[ "$1" == "-archs" ]]
    printf 'lipo|%s\n' "$2" >> "$FAKE_HELPER_TOOL_LOG"
    printf 'arm64\n'
    """#, to: tools.appendingPathComponent("lipo"))
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
    xcodeBuildLog: xcodeBuildLog,
    xcodeBuildEntered: xcodeBuildEntered,
    xcodeHoldFile: xcodeHoldFile,
    helperToolLog: helperToolLog,
    codesignLog: codesignLog,
    codesignVerifyLog: codesignVerifyLog,
    rpathState: root.appendingPathComponent("rpath-state"),
    unsafeStaging: root.appendingPathComponent("unsafe-staging"),
    gemmaResourceMode: gemmaResourceMode,
    appScript: appScript
  )
}

private func environment(
  for fixture: FakeFixture,
  runID: String,
  unsafeStaging: Bool = false,
  gemmaBuildFails: Bool = false,
  gemmaBuildMutatesLock: Bool = false
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
  environment["FAKE_XCODE_BUILD_LOG"] = fixture.xcodeBuildLog.path
  environment["FAKE_XCODE_BUILD_ENTERED"] = fixture.xcodeBuildEntered.path
  environment["FAKE_XCODE_HOLD"] = fixture.xcodeHoldFile.path
  environment["FAKE_HELPER_TOOL_LOG"] = fixture.helperToolLog.path
  environment["FAKE_GEMMA_BUILD_FAIL"] = gemmaBuildFails ? "1" : "0"
  environment["FAKE_GEMMA_MUTATE_LOCK"] = gemmaBuildMutatesLock ? "1" : "0"
  environment["FAKE_GEMMA_RESOURCE_MODE"] = fixture.gemmaResourceMode
  environment["FAKE_CODESIGN_LOG"] = fixture.codesignLog.path
  environment["FAKE_CODESIGN_VERIFY_LOG"] = fixture.codesignVerifyLog.path
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
  gemmaBuildFails: Bool = false,
  gemmaBuildMutatesLock: Bool = false
) throws -> RunningPackager {
  let standardError = Pipe()
  let process = Process()
  process.executableURL = fixture.appScript
  process.currentDirectoryURL = fixture.root
  process.environment = environment(
    for: fixture,
    runID: runID,
    unsafeStaging: unsafeStaging,
    gemmaBuildFails: gemmaBuildFails,
    gemmaBuildMutatesLock: gemmaBuildMutatesLock
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

  let gemmaBuildLines = try String(contentsOf: fixture.xcodeBuildLog, encoding: .utf8)
    .split(whereSeparator: \.isNewline)
    .map(String.init)
  func normalizedTemporaryPath(_ path: String) -> String {
    path.replacingOccurrences(of: "/private/var/", with: "/var/")
  }
  try #require(gemmaBuildLines.count == 11)
  #expect(normalizedTemporaryPath(gemmaBuildLines[0]) == "cwd=\(normalizedTemporaryPath(fixture.gemmaPackage.path))")
  #expect(gemmaBuildLines[1] == "scheme=gemma-cleanup-helper")
  #expect(gemmaBuildLines[2] == "configuration=Release")
  #expect(gemmaBuildLines[3] == "destination=generic/platform=macOS")
  #expect(normalizedTemporaryPath(gemmaBuildLines[4]).contains("/.parakeet-gemma-cleanup."))
  #expect(gemmaBuildLines[5].hasSuffix("/Products"))
  #expect(gemmaBuildLines[6] == "architectures=arm64")
  #expect(gemmaBuildLines[7] == "onlyActiveArch=YES")
  #expect(gemmaBuildLines[8].hasSuffix(
    "/Products/gemma-cleanup-helper.dSYM/Contents/Resources/DWARF/gemma-cleanup-helper"
  ))
  #expect(gemmaBuildLines[9].hasSuffix("/Products/gemma-cleanup-helper"))
  #expect(gemmaBuildLines[10].hasSuffix("/Products/mlx-swift_Cmlx.bundle"))

  let app = fixture.build.appendingPathComponent("parakeet-test/Fleck.app")
  let executableContents = try String(
    contentsOf: app.appendingPathComponent("Contents/MacOS/Fleck"),
    encoding: .utf8
  )
  #expect(executableContents == "first\n")
  let helper = app.appendingPathComponent("Contents/SharedSupport/gemma-cleanup-helper")
  #expect(fileManager.isExecutableFile(atPath: helper.path))
  #expect(try String(contentsOf: helper, encoding: .utf8) == "gemma-helper-first\n")
  let metallib = app.appendingPathComponent(
    "Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
  )
  let bundleMetadata = app.appendingPathComponent(
    "Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Info.plist"
  )
  #expect(try String(contentsOf: metallib, encoding: .utf8) == "default-metallib-first\n")
  #expect(try String(contentsOf: bundleMetadata, encoding: .utf8) == "mlx-bundle-info-first\n")
  let appContents = fileManager.subpaths(atPath: app.path) ?? []
  #expect(appContents.filter { $0 == "Contents/SharedSupport/gemma-cleanup-helper" }.count == 1)
  #expect(appContents.filter {
    $0 == "Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
  }.count == 1)
  #expect(!appContents.contains("Contents/SharedSupport/mlx-swift_Cmlx.bundle"))

  let helperToolEvents = try String(contentsOf: fixture.helperToolLog, encoding: .utf8)
    .split(whereSeparator: \.isNewline)
    .map(String.init)
  let helperSuffix = "/Contents/SharedSupport/gemma-cleanup-helper"
  #expect(helperToolEvents.contains { $0.hasPrefix("lipo|") && $0.hasSuffix(helperSuffix) })
  #expect(helperToolEvents.contains { $0.hasPrefix("otool|-l|") && $0.hasSuffix(helperSuffix) })
  #expect(helperToolEvents.contains { $0.hasPrefix("otool|-L|") && $0.hasSuffix(helperSuffix) })
  #expect(helperToolEvents.contains {
    $0.hasPrefix("install_name_tool|-delete_rpath|") && $0.hasSuffix(helperSuffix)
  })

  let signEvents = try String(contentsOf: fixture.codesignLog, encoding: .utf8)
    .split(whereSeparator: \.isNewline)
    .map(String.init)
  #expect(signEvents.count == 3)
  #expect(signEvents[0].hasSuffix("/Contents/SharedSupport/gemma-cleanup-helper|com.harryjin.fleck.gemma-cleanup-helper"))
  #expect(signEvents[1].hasSuffix("/Contents/SharedSupport/fleck-agent|com.harryjin.fleck.agent"))
  #expect(signEvents[2].hasSuffix("/Fleck.app|com.harryjin.fleck"))
  let verifyEvents = try String(contentsOf: fixture.codesignVerifyLog, encoding: .utf8)
  #expect(verifyEvents.contains(helperSuffix))
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
  try fileManager.removeItem(at: fixture.holdFile)

  let running = try launchPackager(
    fixture: fixture,
    runID: "failed",
    gemmaBuildFails: true,
    gemmaBuildMutatesLock: true
  )
  waitForExit(running)
  #expect(!running.process.isRunning)
  #expect(running.process.terminationStatus != 0)
  #expect(fileManager.fileExists(atPath: fixture.xcodeBuildEntered.path))
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

@Test(arguments: [
  "missing-bundle",
  "missing-metadata",
  "missing-metallib",
  "wrong-resource",
  "extra-resource",
  "symlink-resource",
])
func parakeetPackagerRejectsIncompleteOrAmbiguousGemmaRuntime(_ resourceMode: String) throws {
  let fixture = try makeFakeFixture(gemmaResourceMode: resourceMode)
  defer { try? fileManager.removeItem(at: fixture.root) }
  try fileManager.removeItem(at: fixture.holdFile)

  let running = try launchPackager(fixture: fixture, runID: resourceMode)
  waitForExit(running)
  let error = output(from: running.standardError)

  #expect(running.process.terminationStatus != 0)
  #expect(fileManager.fileExists(atPath: fixture.xcodeBuildEntered.path))
  switch resourceMode {
  case "missing-bundle":
    #expect(error.contains("exactly one MLX resource bundle"))
  case "missing-metadata":
    #expect(error.contains("MLX resource metadata is missing or unsafe"))
  case "missing-metallib", "wrong-resource":
    #expect(error.contains("MLX resource is missing or unsafe"))
  case "symlink-resource":
    #expect(error.contains("MLX resource bundle contains a symlink"))
  case "extra-resource":
    #expect(error.contains("MLX resource bundle contains unexpected entries"))
  default:
    Issue.record("Unexpected Gemma resource fixture mode")
  }
  #expect(!fileManager.fileExists(
    atPath: fixture.build.appendingPathComponent("parakeet-test/Fleck.app").path
  ))
  #expect(try Data(contentsOf: fixture.gemmaPackage.appendingPathComponent("Package.resolved"))
    == Data(contentsOf: fixture.originalGemmaLock))
  #expect(try Data(contentsOf: fixture.root.appendingPathComponent("Package.resolved"))
    == Data(contentsOf: fixture.originalLock))
  let buildChildren = try fileManager.contentsOfDirectory(atPath: fixture.build.path)
  #expect(!buildChildren.contains(where: { $0.hasPrefix(".parakeet-gemma-cleanup.") }))
}

@Test
func parakeetPackagerRejectsAndRestoresDetectedNestedLockMutation() throws {
  let fixture = try makeFakeFixture()
  defer { try? fileManager.removeItem(at: fixture.root) }
  try fileManager.removeItem(at: fixture.holdFile)

  let running = try launchPackager(
    fixture: fixture,
    runID: "mutated",
    gemmaBuildMutatesLock: true
  )
  waitForExit(running)
  let error = output(from: running.standardError)

  #expect(running.process.terminationStatus != 0)
  #expect(error.contains("changed NativeRuntime Package.resolved"))
  #expect(try Data(contentsOf: fixture.gemmaPackage.appendingPathComponent("Package.resolved"))
    == Data(contentsOf: fixture.originalGemmaLock))
  #expect(try Data(contentsOf: fixture.root.appendingPathComponent("Package.resolved"))
    == Data(contentsOf: fixture.originalLock))
}

@Test
func parakeetPackagerRestoresNestedLockWhenInterruptedDuringXcodeBuild() throws {
  let fixture = try makeFakeFixture()
  defer { try? fileManager.removeItem(at: fixture.root) }
  try fileManager.removeItem(at: fixture.holdFile)
  try Data().write(to: fixture.xcodeHoldFile)

  let running = try launchPackager(
    fixture: fixture,
    runID: "interrupted",
    gemmaBuildMutatesLock: true
  )
  #expect(waitForPath(fixture.xcodeBuildEntered))
  running.process.terminate()
  try fileManager.removeItem(at: fixture.xcodeHoldFile)
  waitForExit(running)

  #expect(running.process.terminationStatus != 0)
  #expect(try Data(contentsOf: fixture.gemmaPackage.appendingPathComponent("Package.resolved"))
    == Data(contentsOf: fixture.originalGemmaLock))
  #expect(try Data(contentsOf: fixture.root.appendingPathComponent("Package.resolved"))
    == Data(contentsOf: fixture.originalLock))
  #expect(!fileManager.fileExists(atPath: fixture.build.appendingPathComponent(".parakeet-test.lock").path))
  let buildChildren = try fileManager.contentsOfDirectory(atPath: fixture.build.path)
  #expect(!buildChildren.contains(where: { $0.hasPrefix(".parakeet-gemma-cleanup.") }))
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
