#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FLECK_ENHANCED_CANDIDATE+x}" ]]; then
  printf '%s\n' \
    'error: unset FLECK_ENHANCED_CANDIDATE before validating an ordinary release' \
    >&2
  exit 2
fi

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

physical_directory() {
  (cd -P -- "$1" 2>/dev/null && pwd)
}

nearest_app_root() {
  local current="$1"
  local parent
  local name

  while :; do
    name="$(lowercase "$(basename "$current")")"
    if [[ "$name" == *.app ]]; then
      physical_directory "$current"
      return
    fi
    parent="$(dirname "$current")"
    if [[ "$parent" == "$current" || "$current" == "." ]]; then
      return 1
    fi
    current="$parent"
  done
}

is_model_context_path() {
  local path="$1"
  local boundary="$2"
  local relative_path
  local boundary_name

  if [[ "$path" == "$boundary" ]]; then
    relative_path="${path##*/}"
  elif [[ "$path" == "$boundary/"* ]]; then
    relative_path="${path#"$boundary/"}"
  else
    relative_path="${path##*/}"
  fi

  path="$(lowercase "$path")"
  relative_path="$(lowercase "$relative_path")"
  boundary_name="$(lowercase "${boundary##*/}")"
  case "$boundary_name" in
    model|models|*.mlmodelc|*.mlpackage)
      return 0
      ;;
  esac
  case "$relative_path" in
    *.mlmodelc|*.mlmodelc/*|*.mlpackage|*.mlpackage/*|\
      model|model/*|models|models/*|*/model|*/model/*|*/models|*/models/*)
      return 0
      ;;
  esac
  return 1
}

is_forbidden_model_path() {
  local path="$1"
  local boundary="$2"
  local model_context="${3:-false}"
  local filename
  local original_path="$path"

  path="$(lowercase "$path")"
  filename="${path##*/}"
  case "$filename" in
    *.mlmodel|*.mlpackage|*.mlmodelc|coremldata.bin|weight.bin|weights.bin)
      return 0
      ;;
  esac

  case "$filename" in
    *.bin)
      if [[ "$model_context" == true ]] \
        || is_model_context_path "$original_path" "$boundary"; then
        return 0
      fi
      ;;
  esac
  return 1
}

readonly target="${1:-.build/release/Fleck}"
readonly limit_mb="${APP_SIZE_LIMIT_MB:-15}"
readonly limit_bytes=$((limit_mb * 1024 * 1024))
readonly repository_root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly sources_root="$repository_root/Sources"
readonly enhanced_capture="$sources_root/FleckApp/EnhancedSpeechCapture.swift"

if ! command -v realpath >/dev/null 2>&1; then
  printf 'error: realpath is required for safe release artifact traversal\n' >&2
  exit 2
fi

additional_artifact_root=""
if [[ -f "$target" ]]; then
  set +e
  resolved_executable="$(realpath "$target" 2>/dev/null)"
  realpath_exit=$?
  set -e
  if (( realpath_exit != 0 )) || [[ ! -f "$resolved_executable" ]]; then
    printf 'error: cannot resolve release executable: %s\n' "$target" >&2
    exit 2
  fi
  readonly executable="$resolved_executable"
  executable_directory="$(dirname "$resolved_executable")"
  logical_app_root=""
  resolved_app_root=""
  if app_root="$(nearest_app_root "$(dirname "$target")")"; then
    logical_app_root="$app_root"
  fi
  if app_root="$(nearest_app_root "$executable_directory")"; then
    resolved_app_root="$app_root"
  fi
  if [[ -n "$resolved_app_root" ]]; then
    readonly artifact_root="$resolved_app_root"
    if [[ -n "$logical_app_root" && "$logical_app_root" != "$resolved_app_root" ]]; then
      additional_artifact_root="$logical_app_root"
    fi
  elif [[ -n "$logical_app_root" ]]; then
    readonly artifact_root="$logical_app_root"
  else
    readonly artifact_root="$executable_directory"
  fi
elif [[ -d "$target" ]]; then
  resolved_target="$(physical_directory "$target")" || {
    printf 'error: cannot resolve release artifact directory: %s\n' "$target" >&2
    exit 2
  }
  if [[ -f "$resolved_target/Contents/MacOS/Fleck" ]]; then
    readonly executable="$resolved_target/Contents/MacOS/Fleck"
    readonly artifact_root="$resolved_target"
  elif [[ -f "$resolved_target/Fleck" ]]; then
    readonly executable="$resolved_target/Fleck"
    readonly artifact_root="$resolved_target"
  else
    printf 'error: release executable not found in artifact: %s\n' "$target" >&2
    exit 2
  fi
else
  printf 'error: release executable or artifact not found: %s\n' "$target" >&2
  exit 2
fi

helper_candidate="$artifact_root/Contents/SharedSupport/fleck-agent"
if [[ ! -f "$helper_candidate" ]]; then
  helper_candidate="$(dirname "$executable")/fleck-agent"
fi
if [[ ! -f "$helper_candidate" ]]; then
  printf 'error: release helper not found beside Fleck or in SharedSupport: %s\n' \
    "$target" >&2
  exit 2
fi
resolved_helper="$(realpath "$helper_candidate" 2>/dev/null)" || {
  printf 'error: cannot resolve release helper: %s\n' "$helper_candidate" >&2
  exit 2
}
readonly helper="$resolved_helper"

size_bytes="$(wc -c < "$executable" | tr -d '[:space:]')"
helper_size_bytes="$(wc -c < "$helper" | tr -d '[:space:]')"
printf 'Fleck executable: %s bytes (budget: %s MB)\n' "$size_bytes" "$limit_mb"
printf 'fleck-agent helper: %s bytes\n' "$helper_size_bytes"

if (( size_bytes > limit_bytes )); then
  printf 'error: release executable exceeds the %s MB budget\n' "$limit_mb" >&2
  exit 1
fi

scan_output="$(mktemp "${TMPDIR:-/tmp}/fleck-release-scan.XXXXXX")" || {
  printf 'error: could not create release artifact scan output\n' >&2
  exit 2
}
scan_errors="$(mktemp "${TMPDIR:-/tmp}/fleck-release-scan-errors.XXXXXX")" || {
  printf 'error: could not create release artifact scan error output\n' >&2
  /bin/rm -f "$scan_output"
  exit 2
}
inspector_source="${scan_output}-inspector.swift"
inspector_binary="${scan_output}-inspector"
inspector_output="${scan_output}-inspector-output"
cleanup_scan_files() {
  /bin/rm -f "$scan_output" "$scan_errors" \
    "$inspector_source" "$inspector_binary" "$inspector_output"
}
trap cleanup_scan_files EXIT

forbidden_model_assets=()
scan_roots=("$artifact_root")
scan_logical_roots=("$artifact_root")
scan_boundaries=("$artifact_root")
scan_model_contexts=(false)
if [[ -n "$additional_artifact_root" ]]; then
  scan_roots+=("$additional_artifact_root")
  scan_logical_roots+=("$additional_artifact_root")
  scan_boundaries+=("$additional_artifact_root")
  scan_model_contexts+=(false)
fi
seen_scan_roots=()
seen_scan_contexts=()
scan_index=0
while (( scan_index < ${#scan_roots[@]} )); do
  scan_root="${scan_roots[$scan_index]}"
  scan_logical_root="${scan_logical_roots[$scan_index]}"
  scan_boundary="${scan_boundaries[$scan_index]}"
  scan_model_context="${scan_model_contexts[$scan_index]}"
  scan_index=$((scan_index + 1))

  already_scanned=false
  if (( ${#seen_scan_roots[@]} > 0 )); then
    seen_index=0
    while (( seen_index < ${#seen_scan_roots[@]} )); do
      if [[ "${seen_scan_roots[$seen_index]}" == "$scan_root" \
        && "${seen_scan_contexts[$seen_index]}" == "$scan_model_context" ]]; then
        already_scanned=true
        break
      fi
      seen_index=$((seen_index + 1))
    done
  fi
  if [[ "$already_scanned" == true ]]; then continue; fi
  seen_scan_roots+=("$scan_root")
  seen_scan_contexts+=("$scan_model_context")

  : > "$scan_output"
  : > "$scan_errors"
  set +e
  find "$scan_root" \
    \( -type l -o -iname '*.mlmodel' -o -iname '*.mlpackage' \
      -o -iname '*.mlmodelc' -o -iname '*.bin' \
      -o -iname 'EnhancedModelManifest.json' \
      -o -iname 'ThirdPartyNotices.md' \) \
    -print0 >"$scan_output" 2>"$scan_errors"
  find_exit=$?
  set -e
  if (( find_exit != 0 )); then
    printf 'error: release artifact traversal failed at %s (exit %s)\n' \
      "$scan_root" "$find_exit" >&2
    if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
    exit 2
  fi

  while IFS= read -r -d '' path; do
    logical_path="$scan_logical_root${path#"$scan_root"}"
    case "$(basename "$logical_path")" in
      EnhancedModelManifest.json|ThirdPartyNotices.md)
        forbidden_model_assets+=("$logical_path")
        ;;
    esac
    if is_forbidden_model_path \
      "$logical_path" "$scan_boundary" "$scan_model_context"; then
      forbidden_model_assets+=("$logical_path")
    fi

    if [[ -L "$path" ]]; then
      : > "$scan_errors"
      set +e
      resolved_path="$(realpath "$path" 2>"$scan_errors")"
      realpath_exit=$?
      set -e
      if (( realpath_exit != 0 )) || [[ ! -e "$resolved_path" ]]; then
        printf 'error: release artifact symlink cannot be resolved: %s\n' \
          "$path" >&2
        if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
        exit 2
      fi
      if is_forbidden_model_path "$resolved_path" "$(dirname "$resolved_path")"; then
        forbidden_model_assets+=("$logical_path -> $resolved_path")
      fi
      if [[ -d "$resolved_path" ]]; then
        linked_model_context="$scan_model_context"
        if is_model_context_path "$logical_path" "$scan_boundary" \
          || is_model_context_path "$resolved_path" "$resolved_path"; then
          linked_model_context=true
        fi
        scan_roots+=("$resolved_path")
        scan_logical_roots+=("$logical_path")
        scan_boundaries+=("$scan_boundary")
        scan_model_contexts+=("$linked_model_context")
      fi
    fi
  done < "$scan_output"
done

if (( ${#forbidden_model_assets[@]} > 0 )); then
  printf 'error: release artifact contains model assets:\n' >&2
  for path in "${forbidden_model_assets[@]}"; do
    printf '  %s\n' "$path" >&2
  done
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  printf 'error: xcrun is required for Swift source inspection\n' >&2
  exit 2
fi
readonly xcrun_path="$(command -v xcrun)"

: > "$scan_errors"
set +e
swiftc_path="$("$xcrun_path" --find swiftc 2>"$scan_errors")"
xcrun_exit=$?
set -e
if (( xcrun_exit != 0 )) || [[ ! -x "$swiftc_path" ]]; then
  printf 'error: xcrun could not locate the active Swift compiler\n' >&2
  if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
  exit 2
fi
swiftc_directory="$(physical_directory "$(dirname "$swiftc_path")")" || {
  printf 'error: could not resolve the active Swift compiler directory\n' >&2
  exit 2
}
toolchain_root="$(physical_directory "$swiftc_directory/../..")" || {
  printf 'error: could not resolve the active Swift toolchain\n' >&2
  exit 2
}
swift_syntax_host="$toolchain_root/usr/lib/swift/host"

if [[ ! -x /usr/bin/plutil ]]; then
  printf 'error: plutil is required for Swift target inspection\n' >&2
  exit 2
fi

: > "$scan_output"
: > "$scan_errors"
set +e
"$xcrun_path" swiftc -print-target-info \
  >"$scan_output" 2>"$scan_errors"
target_info_exit=$?
set -e
if (( target_info_exit != 0 )); then
  printf 'error: active Swift compiler target inspection failed\n' >&2
  if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
  exit 2
fi

extract_target_value() {
  local key="$1"
  local value
  local plutil_exit

  : > "$scan_errors"
  set +e
  value="$(/usr/bin/plutil -extract "$key" raw -o - "$scan_output" 2>"$scan_errors")"
  plutil_exit=$?
  set -e
  if (( plutil_exit != 0 )) || [[ -z "$value" ]]; then
    printf 'error: active Swift compiler target is missing %s\n' "$key" >&2
    if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
    exit 2
  fi
  printf '%s' "$value"
}

active_target_arch="$(extract_target_value target.arch)"
active_target_base="$(extract_target_value target.unversionedTriple)"
active_compiler_version="$(extract_target_value compilerVersion)"
active_compiler_version_number="$(
  printf '%s\n' "$active_compiler_version" \
    | /usr/bin/sed -E -n 's/.*Swift version ([0-9]+(\.[0-9]+)+).*/\1/p'
)"
active_compiler_major="${active_compiler_version_number%%.*}"
active_compiler_version_tail="${active_compiler_version_number#*.}"
active_compiler_minor="${active_compiler_version_tail%%.*}"
if [[ -z "$active_compiler_version_number" \
  || "$active_compiler_major" == *[!0-9]* \
  || "$active_compiler_minor" == *[!0-9]* ]] \
  || (( active_compiler_major < 6 \
    || (active_compiler_major == 6 && active_compiler_minor < 1) )); then
  printf 'error: release source inspection requires Xcode 16.3 or later with Swift 6.1 or later (found: %s)\n' \
    "$active_compiler_version" >&2
  exit 2
fi
if [[ ! -d "$swift_syntax_host/SwiftSyntax.swiftmodule" \
  || ! -d "$swift_syntax_host/SwiftParser.swiftmodule" \
  || ! -d "$swift_syntax_host/SwiftIfConfig.swiftmodule" ]]; then
  printf 'error: release source inspection requires Xcode 16.3 or later with Swift 6.1 or later and host SwiftSyntax, SwiftParser, and SwiftIfConfig modules: %s\n' \
    "$swift_syntax_host" >&2
  exit 2
fi
case "$active_target_base" in
  *-apple-macosx)
    ;;
  *)
    printf 'error: active Swift compiler does not target macOS: %s\n' \
      "$active_target_base" >&2
    exit 2
    ;;
esac
readonly release_target="${active_target_base}14.0"
readonly release_modules="$repository_root/.build/release/Modules"

cat > "$inspector_source" <<'SWIFT'
import Foundation
import SwiftIfConfig
import SwiftParser
import SwiftSyntax

enum InspectorError: Error {
  case invalidConfiguration
  case unknownCondition
}

final class ReleaseBuildConfiguration: BuildConfiguration {
  private let xcrunPath: String
  private let targetArchitecture: String
  private let targetTriple: String
  private let moduleSearchPath: String
  private var conditionCache: [String: Bool] = [:]

  let targetPointerBitWidth = 64
  let targetAtomicBitWidths = [8, 16, 32, 64]
  let endianness = Endianness.little
  let languageVersion = VersionTuple(6, 0)
  let compilerVersion: VersionTuple

  init(
    xcrunPath: String,
    targetArchitecture: String,
    targetTriple: String,
    compilerDescription: String,
    moduleSearchPath: String
  ) throws {
    guard
      FileManager.default.isExecutableFile(atPath: xcrunPath),
      Self.isIdentifier(targetArchitecture),
      targetTriple.hasSuffix("-apple-macosx14.0")
    else {
      throw InspectorError.invalidConfiguration
    }
    guard
      let marker = compilerDescription.range(of: "Swift version "),
      let versionRange = compilerDescription[marker.upperBound...].range(
        of: #"^[0-9]+(?:\.[0-9]+)*"#,
        options: .regularExpression
      ),
      let compilerVersion = VersionTuple(
        parsing: String(compilerDescription[versionRange])
      )
    else {
      throw InspectorError.invalidConfiguration
    }

    self.xcrunPath = xcrunPath
    self.targetArchitecture = targetArchitecture
    self.targetTriple = targetTriple
    self.compilerVersion = compilerVersion
    self.moduleSearchPath = moduleSearchPath
  }

  func isCustomConditionSet(name: String) -> Bool {
    name == "SWIFT_PACKAGE"
      || name == "SWIFT_MODULE_RESOURCE_BUNDLE_AVAILABLE"
  }

  func hasFeature(name: String) throws -> Bool {
    throw InspectorError.unknownCondition
  }

  func hasAttribute(name: String) throws -> Bool {
    throw InspectorError.unknownCondition
  }

  func canImport(
    importPath: [(TokenSyntax, String)],
    version: CanImportVersion
  ) throws -> Bool {
    guard case .unversioned = version else {
      throw InspectorError.unknownCondition
    }
    let path = try importPath.map { try validated($0.1) }.joined(separator: ".")
    return try evaluate("canImport(\(path))")
  }

  func isActiveTargetOS(name: String) -> Bool {
    name == "macOS"
  }

  func isActiveTargetArchitecture(name: String) -> Bool {
    name == targetArchitecture
  }

  func isActiveTargetEnvironment(name: String) throws -> Bool {
    throw InspectorError.unknownCondition
  }

  func isActiveTargetRuntime(name: String) throws -> Bool {
    throw InspectorError.unknownCondition
  }

  func isActiveTargetPointerAuthentication(name: String) throws -> Bool {
    throw InspectorError.unknownCondition
  }

  func isActiveTargetObjectFormat(name: String) -> Bool {
    name == "MachO"
  }

  private static func isIdentifier(_ value: String) -> Bool {
    value.range(
      of: #"^[A-Za-z_][A-Za-z0-9_]*$"#,
      options: .regularExpression
    ) != nil
  }

  private func validated(_ value: String) throws -> String {
    guard Self.isIdentifier(value) else {
      throw InspectorError.unknownCondition
    }
    return value
  }

  private func evaluate(_ condition: String) throws -> Bool {
    if let cached = conditionCache[condition] {
      return cached
    }

    let positive = """
      #if \(condition)
      #else
      #error("inactive")
      #endif
      """
    if try compilerAccepts(positive) {
      conditionCache[condition] = true
      return true
    }

    let negative = """
      #if \(condition)
      #error("active")
      #endif
      """
    if try compilerAccepts(negative) {
      conditionCache[condition] = false
      return false
    }
    throw InspectorError.unknownCondition
  }

  private func compilerAccepts(_ source: String) throws -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: xcrunPath)
    process.arguments = [
      "swiftc",
      "-typecheck",
      "-swift-version", "6",
      "-O",
      "-target", targetTriple,
    ]
    if FileManager.default.fileExists(atPath: moduleSearchPath) {
      process.arguments?.append(contentsOf: ["-I", moduleSearchPath])
    }
    process.arguments?.append("-")

    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    input.fileHandleForWriting.write(Data(source.utf8))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    return process.terminationReason == .exit && process.terminationStatus == 0
  }
}

enum Finding: String, Comparable {
  case requiredOfflineTrue = "required-offline-true"
  case forbiddenFluidAudioImport = "forbidden-fluidaudio-import"
  case forbiddenCandidateDependencyImport = "forbidden-candidate-dependency-import"
  case forbiddenOfflineFalse = "forbidden-offline-false"
  case forbiddenDownloadAndLoad = "forbidden-asr-download-and-load"
  case forbiddenModelHubDownload = "forbidden-modelhub-download"
  case forbiddenModelHubFetchFile = "forbidden-modelhub-fetch-file"
  case forbiddenGlobalMonitor = "forbidden-global-monitor"
  case forbiddenEnhancedConstruction = "forbidden-enhanced-construction"
  case forbiddenCandidateImplementation = "forbidden-candidate-implementation"

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

final class ReleaseVisitor: SyntaxVisitor {
  private let configuredRegions: ConfiguredRegions
  private(set) var findings = Set<Finding>()
  private(set) var hasUnknownRequiredRegion = false

  init(configuredRegions: ConfiguredRegions) {
    self.configuredRegions = configuredRegions
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    guard let base = node.base.flatMap(baseName),
      let finding = memberFinding(base: base, member: node.declName.baseName.text)
    else {
      return .visitChildren
    }
    findings.insert(finding)
    return .visitChildren
  }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    let importPath = node.path.trimmedDescription
    guard importPath == "FluidAudio"
      || importPath == "FleckEnhancedCandidateDependencies"
    else {
      return .visitChildren
    }
    switch configuredRegions.isActive(node) {
    case .active:
      findings.insert(
        importPath == "FluidAudio"
          ? .forbiddenFluidAudioImport
          : .forbiddenCandidateDependencyImport
      )
    case .inactive:
      break
    case .unparsed:
      hasUnknownRequiredRegion = true
    @unknown default:
      hasUnknownRequiredRegion = true
    }
    return .visitChildren
  }

  override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
    let elements = Array(node.elements)
    guard elements.count == 3,
      let member = transparent(elements[0]).as(MemberAccessExprSyntax.self),
      elements[1].is(AssignmentExprSyntax.self),
      let value = transparent(elements[2]).as(BooleanLiteralExprSyntax.self),
      baseName(member.base) == "ModelHub",
      member.declName.baseName.text == "offlineMode"
    else {
      return .visitChildren
    }

    switch value.literal.tokenKind {
    case .keyword(.true):
      switch configuredRegions.isActive(node) {
      case .active:
        findings.insert(.requiredOfflineTrue)
      case .inactive:
        break
      case .unparsed:
        hasUnknownRequiredRegion = true
      @unknown default:
        hasUnknownRequiredRegion = true
      }
    case .keyword(.false):
      findings.insert(.forbiddenOfflineFalse)
    default:
      break
    }
    return .visitChildren
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard baseName(node.calledExpression) == "EnhancedSpeechCapture" else {
      return .visitChildren
    }
    switch configuredRegions.isActive(node) {
    case .active:
      findings.insert(.forbiddenEnhancedConstruction)
    case .inactive:
      break
    case .unparsed:
      hasUnknownRequiredRegion = true
    @unknown default:
      hasUnknownRequiredRegion = true
    }
    return .visitChildren
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    inspectCandidateDeclaration(node.name.text, node: Syntax(node))
    return .visitChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    inspectCandidateDeclaration(node.name.text, node: Syntax(node))
    return .visitChildren
  }

  private func inspectCandidateDeclaration(_ name: String, node: Syntax) {
    guard [
      "EnhancedModelManager",
      "EnhancedModelManifest",
      "URLSessionModelDownloader",
    ].contains(name) else { return }
    switch configuredRegions.isActive(node) {
    case .active:
      findings.insert(.forbiddenCandidateImplementation)
    case .inactive:
      break
    case .unparsed:
      hasUnknownRequiredRegion = true
    @unknown default:
      hasUnknownRequiredRegion = true
    }
  }

  private func baseName(_ expression: ExprSyntax?) -> String? {
    expression.flatMap(baseName)
  }

  private func baseName(_ expression: ExprSyntax) -> String? {
    let expression = transparent(expression)
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
      return reference.baseName.text
    }
    if let member = expression.as(MemberAccessExprSyntax.self) {
      return member.declName.baseName.text
    }
    return nil
  }

  private func transparent(_ expression: ExprSyntax) -> ExprSyntax {
    var expression = expression
    while true {
      if let member = expression.as(MemberAccessExprSyntax.self),
        member.declName.baseName.text == "self",
        let base = member.base
      {
        expression = base
        continue
      }
      if let tuple = expression.as(TupleExprSyntax.self),
        tuple.elements.count == 1,
        let element = tuple.elements.first,
        element.label == nil,
        element.colon == nil
      {
        expression = element.expression
        continue
      }
      return expression
    }
  }

  private func memberFinding(base: String, member: String) -> Finding? {
    switch (base, member) {
    case ("AsrModels", "downloadAndLoad"):
      return .forbiddenDownloadAndLoad
    case ("ModelHub", "download"):
      return .forbiddenModelHubDownload
    case ("ModelHub", "fetchFile"):
      return .forbiddenModelHubFetchFile
    case ("NSEvent", "addGlobalMonitorForEvents"):
      return .forbiddenGlobalMonitor
    default:
      return nil
    }
  }
}

guard CommandLine.arguments.count == 7 else {
  FileHandle.standardError.write(
    Data("error: release inspector received invalid configuration\n".utf8)
  )
  exit(2)
}

let source: String
do {
  source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
} catch {
  FileHandle.standardError.write(
    Data("error: release inspector could not read Swift source\n".utf8)
  )
  exit(2)
}

let configuration: ReleaseBuildConfiguration
do {
  configuration = try ReleaseBuildConfiguration(
    xcrunPath: CommandLine.arguments[2],
    targetArchitecture: CommandLine.arguments[3],
    targetTriple: CommandLine.arguments[4],
    compilerDescription: CommandLine.arguments[5],
    moduleSearchPath: CommandLine.arguments[6]
  )
} catch {
  FileHandle.standardError.write(
    Data("error: release inspector could not configure macOS release conditions\n".utf8)
  )
  exit(2)
}

let tree = Parser.parse(source: source)
guard !tree.hasError else {
  FileHandle.standardError.write(
    Data("error: release inspector found malformed Swift source\n".utf8)
  )
  exit(2)
}

let configuredRegions = tree.configuredRegions(in: configuration)
guard configuredRegions.diagnostics.isEmpty,
  !configuredRegions.contains(where: { $0.state == .unparsed })
else {
  FileHandle.standardError.write(
    Data("error: release inspector could not evaluate compilation conditions\n".utf8)
  )
  exit(2)
}

let visitor = ReleaseVisitor(configuredRegions: configuredRegions)
visitor.walk(tree)
guard !visitor.hasUnknownRequiredRegion else {
  FileHandle.standardError.write(
    Data("error: release inspector found an unknown required-source region\n".utf8)
  )
  exit(2)
}
for finding in visitor.findings.sorted() {
  print(finding.rawValue)
}
SWIFT

: > "$scan_output"
: > "$scan_errors"
set +e
"$xcrun_path" swiftc \
  -swift-version 6 \
  -I "$swift_syntax_host" \
  -L "$swift_syntax_host" \
  -lSwiftIfConfig \
  -lSwiftParser \
  -lSwiftSyntax \
  -Xlinker -rpath \
  -Xlinker "$swift_syntax_host" \
  "$inspector_source" \
  -o "$inspector_binary" \
  >"$scan_output" 2>"$scan_errors"
inspector_compile_exit=$?
set -e
if (( inspector_compile_exit != 0 )) || [[ ! -x "$inspector_binary" ]]; then
  printf 'error: could not compile the Swift release source inspector\n' >&2
  if [[ -s "$scan_output" ]]; then cat "$scan_output" >&2; fi
  if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
  exit 2
fi

enhanced_found=false
source_scan_roots=("$sources_root")
source_logical_roots=("$sources_root")
source_ancestor_separator=$'\034'
source_ancestor_chains=(
  "${source_ancestor_separator}${sources_root}${source_ancestor_separator}"
)
seen_source_roots=()
seen_source_logical_roots=()
source_physical_files=()
source_logical_files=()
source_is_enhanced=()
source_scan_index=0
while (( source_scan_index < ${#source_scan_roots[@]} )); do
  source_scan_root="${source_scan_roots[$source_scan_index]}"
  source_logical_root="${source_logical_roots[$source_scan_index]}"
  source_ancestor_chain="${source_ancestor_chains[$source_scan_index]}"
  source_scan_index=$((source_scan_index + 1))

  source_root_seen=false
  if (( ${#seen_source_roots[@]} > 0 )); then
    seen_index=0
    while (( seen_index < ${#seen_source_roots[@]} )); do
      if [[ "${seen_source_roots[$seen_index]}" == "$source_scan_root" \
        && "${seen_source_logical_roots[$seen_index]}" == "$source_logical_root" ]]; then
        source_root_seen=true
        break
      fi
      seen_index=$((seen_index + 1))
    done
  fi
  if [[ "$source_root_seen" == true ]]; then continue; fi
  seen_source_roots+=("$source_scan_root")
  seen_source_logical_roots+=("$source_logical_root")

  : > "$scan_output"
  : > "$scan_errors"
  set +e
  find "$source_scan_root" \
    \( -type l -o \( -type f -name '*.swift' \) \) \
    -print0 >"$scan_output" 2>"$scan_errors"
  find_exit=$?
  set -e
  if (( find_exit != 0 )); then
    printf 'error: Swift source traversal failed at %s (exit %s)\n' \
      "$source_logical_root" "$find_exit" >&2
    if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
    exit 2
  fi

  while IFS= read -r -d '' source_path; do
    logical_source_path="$source_logical_root${source_path#"$source_scan_root"}"
    physical_source_path="$source_path"

    if [[ -L "$source_path" ]]; then
      : > "$scan_errors"
      set +e
      physical_source_path="$(realpath "$source_path" 2>"$scan_errors")"
      realpath_exit=$?
      set -e
      if (( realpath_exit != 0 )) || [[ ! -e "$physical_source_path" ]]; then
        printf 'error: Swift source symlink cannot be resolved: %s\n' \
          "$logical_source_path" >&2
        if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
        exit 2
      fi

      if [[ -d "$physical_source_path" ]]; then
        source_parent="$(dirname "$source_path")"
        if [[ "$source_parent" == "$physical_source_path" \
          || "$source_parent" == "$physical_source_path/"* \
          || "$source_ancestor_chain" == \
            *"${source_ancestor_separator}${physical_source_path}${source_ancestor_separator}"* ]]; then
          printf 'error: Swift source symlink cycle detected: %s\n' \
            "$logical_source_path" >&2
          exit 2
        fi
        source_scan_roots+=("$physical_source_path")
        source_logical_roots+=("$logical_source_path")
        source_ancestor_chains+=(
          "${source_ancestor_chain}${physical_source_path}${source_ancestor_separator}"
        )
        continue
      fi
    fi

    case "$logical_source_path" in
      *.swift)
        ;;
      *)
        continue
        ;;
    esac
    if [[ ! -f "$physical_source_path" ]]; then
      printf 'error: Swift source path is not a file: %s\n' \
        "$logical_source_path" >&2
      exit 2
    fi

    if [[ "$logical_source_path" == "$enhanced_capture" ]]; then
      enhanced_found=true
      logical_is_enhanced=true
    else
      logical_is_enhanced=false
    fi

    source_file_index=-1
    if (( ${#source_physical_files[@]} > 0 )); then
      candidate_index=0
      while (( candidate_index < ${#source_physical_files[@]} )); do
        if [[ "${source_physical_files[$candidate_index]}" == "$physical_source_path" ]]; then
          source_file_index=$candidate_index
          break
        fi
        candidate_index=$((candidate_index + 1))
      done
    fi

    if (( source_file_index >= 0 )); then
      if [[ "$logical_is_enhanced" == true ]]; then
        source_logical_files[$source_file_index]="$logical_source_path"
        source_is_enhanced[$source_file_index]=true
      fi
      continue
    fi

    source_physical_files+=("$physical_source_path")
    source_logical_files+=("$logical_source_path")
    source_is_enhanced+=("$logical_is_enhanced")
  done < "$scan_output"
done

if [[ "$enhanced_found" != true ]]; then
  printf 'error: EnhancedSpeechCapture Swift source was not found\n' >&2
  exit 2
fi

forbidden_source_findings=()
source_file_index=0
while (( source_file_index < ${#source_physical_files[@]} )); do
  physical_source_path="${source_physical_files[$source_file_index]}"
  logical_source_path="${source_logical_files[$source_file_index]}"
  logical_is_enhanced="${source_is_enhanced[$source_file_index]}"
  source_file_index=$((source_file_index + 1))

  : > "$inspector_output"
  : > "$scan_errors"
  set +e
  "$inspector_binary" \
    "$physical_source_path" \
    "$xcrun_path" \
    "$active_target_arch" \
    "$release_target" \
    "$active_compiler_version" \
    "$release_modules" \
    >"$inspector_output" 2>"$scan_errors"
  inspector_exit=$?
  set -e
  if (( inspector_exit != 0 )); then
    printf 'error: Swift release source inspection failed: %s\n' \
      "$logical_source_path" >&2
    if [[ -s "$scan_errors" ]]; then cat "$scan_errors" >&2; fi
    exit 2
  fi

  while IFS= read -r finding; do
    case "$finding" in
      required-offline-true)
        ;;
      forbidden-fluidaudio-import)
        forbidden_source_findings+=(
          "$logical_source_path: active FluidAudio import in release"
        )
        ;;
      forbidden-candidate-dependency-import)
        forbidden_source_findings+=(
          "$logical_source_path: active candidate dependency import in release"
        )
        ;;
      forbidden-offline-false)
        forbidden_source_findings+=(
          "$logical_source_path: ModelHub.offlineMode = false"
        )
        ;;
      forbidden-asr-download-and-load)
        forbidden_source_findings+=(
          "$logical_source_path: AsrModels.downloadAndLoad"
        )
        ;;
      forbidden-modelhub-download)
        forbidden_source_findings+=(
          "$logical_source_path: ModelHub.download"
        )
        ;;
      forbidden-modelhub-fetch-file)
        forbidden_source_findings+=(
          "$logical_source_path: ModelHub.fetchFile"
        )
        ;;
      forbidden-global-monitor)
        forbidden_source_findings+=(
          "$logical_source_path: NSEvent.addGlobalMonitorForEvents"
        )
        ;;
      forbidden-enhanced-construction)
        forbidden_source_findings+=(
          "$logical_source_path: EnhancedSpeechCapture construction in release"
        )
        ;;
      forbidden-candidate-implementation)
        forbidden_source_findings+=(
          "$logical_source_path: active candidate implementation in release"
        )
        ;;
      "")
        ;;
      *)
        printf 'error: Swift release source inspector emitted an unknown finding for %s\n' \
          "$logical_source_path" >&2
        exit 2
        ;;
    esac
  done < "$inspector_output"
done

if (( ${#forbidden_source_findings[@]} > 0 )); then
  printf 'error: forbidden production source found:\n' >&2
  for finding in "${forbidden_source_findings[@]}"; do
    printf '  %s\n' "$finding" >&2
  done
  exit 1
fi

if ! command -v strings >/dev/null 2>&1; then
  printf 'error: strings is required for release UI assertions\n' >&2
  exit 2
fi
strings "$executable" > "$scan_output"
for forbidden_ui_string in \
  'Enhanced Local' \
  'Download Enhanced Model' \
  'Delete the Enhanced model?' \
  'Enhanced model download'
do
  if grep -Fq "$forbidden_ui_string" "$scan_output"; then
    printf 'error: release executable exposes Enhanced UI string: %s\n' \
      "$forbidden_ui_string" >&2
    exit 1
  fi
done

if ! command -v nm >/dev/null 2>&1; then
  printf 'error: nm is required for release SDK symbol assertions\n' >&2
  exit 2
fi
nm -a "$executable" > "$scan_output"
for forbidden_sdk_symbol in \
  'FluidAudio' \
  'Parakeet' \
  'AsrModels' \
  'ModelHub' \
  'FluidEnhancedSpeech' \
  'EnhancedModelManager' \
  'EnhancedModelManifest' \
  'URLSessionModelDownloader'
do
  if grep -Fiq "$forbidden_sdk_symbol" "$scan_output"; then
    printf 'error: release executable contains candidate SDK symbol: %s\n' \
      "$forbidden_sdk_symbol" >&2
    exit 1
  fi
done

printf 'Release artifact contains no bundled model assets.\n'
printf 'Release artifact exposes no Enhanced candidate controls.\n'
printf 'Release artifact contains no candidate SDK symbols.\n'
printf 'Release source assertions passed.\n'
