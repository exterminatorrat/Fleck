import AppKit
import Darwin
import Foundation
import Testing

@main
struct AppKitTestMain {
  @MainActor
  static func main() {
    guard CommandLine.arguments.count >= 2 else {
      fail("usage: AppKitTestMain <test-bundle-binary> [--list-tests] [--filter <regex>] [--no-parallel]")
    }

    var testingArguments = Testing.__CommandLineArguments_v0()
    var filters: [String] = []
    var index = 2
    while index < CommandLine.arguments.count {
      switch CommandLine.arguments[index] {
      case "--list-tests":
        testingArguments.listTests = true
        index += 1
      case "--filter":
        guard index + 1 < CommandLine.arguments.count else {
          fail("missing value for --filter")
        }
        filters.append(CommandLine.arguments[index + 1])
        index += 2
      case "--no-parallel":
        testingArguments.parallel = false
        index += 1
      default:
        fail("unsupported test argument: \(CommandLine.arguments[index])")
      }
    }
    if !filters.isEmpty {
      testingArguments.filter = filters
    }

    let bundlePath = CommandLine.arguments[1]
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: bundlePath, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      fail("test bundle binary is missing: \(bundlePath)")
    }
    guard dlopen(bundlePath, RTLD_NOW | RTLD_GLOBAL) != nil else {
      fail("failed to load test bundle: \(String(cString: dlerror()))")
    }

    let application = NSApplication.shared
    Task { @MainActor in
      let status: CInt = await Testing.__swiftPMEntryPoint(passing: testingArguments)
      Darwin.exit(status)
    }
    application.run()
    fail("NSApplication.run returned before Swift Testing finished")
  }

  @MainActor
  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    Darwin.exit(1)
  }
}
