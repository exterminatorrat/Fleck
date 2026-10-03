import AppKit
import Darwin
import Foundation
import Testing

@main
struct AppKitTestMain {
  @MainActor
  static func main() async {
    let parsedArguments: ParsedArguments
    do {
      parsedArguments = try parseArguments()
    } catch {
      failBeforeConfiguration("\(error)")
    }

    let configuration: HostConfiguration
    do {
      configuration = try HostConfiguration.read(at: parsedArguments.configurationPath)
      try redirectStandardOutput(to: configuration.logPath)
      try writeHostFile(
        "\(configuration.nonce)\t\(getpid())\n",
        to: configuration.processPath
      )
      configuration.writePhase("starting")
    } catch {
      failBeforeConfiguration("failed to initialize the AppKit test host: \(error)")
    }

    do {
      try loadTestBundle(at: parsedArguments.bundlePath)
    } catch {
      failAfterConfiguration("\(error)", configuration: configuration)
    }

    if parsedArguments.testingArguments.listTests == true {
      configuration.writePhase("listingTests")
      let status: CInt = await Testing.__swiftPMEntryPoint(
        passing: parsedArguments.testingArguments
      )
      configuration.finish(status: status)
    }

    let application = NSApplication.shared
    let delegate = AppKitTestApplicationDelegate(
      application: application,
      testingArguments: parsedArguments.testingArguments,
      configuration: configuration
    )
    application.delegate = delegate
    application.run()
    delegate.fail("NSApplication.run returned before Swift Testing finished")
  }

  private static func parseArguments() throws -> ParsedArguments {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let bundlePath = arguments.first else {
      throw HostError("usage: AppKitTestHost <test-bundle-binary> [--list-tests] [--filter <regex>] [--no-parallel] --host-config <path>")
    }

    var testingArguments = Testing.__CommandLineArguments_v0()
    var filters: [String] = []
    var configurationPath: String?
    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--list-tests":
        testingArguments.listTests = true
        index += 1
      case "--filter":
        guard index + 1 < arguments.count else {
          throw HostError("missing value for --filter")
        }
        filters.append(arguments[index + 1])
        index += 2
      case "--no-parallel":
        testingArguments.parallel = false
        index += 1
      case "--host-config":
        guard configurationPath == nil, index + 1 < arguments.count else {
          throw HostError("missing or duplicate value for --host-config")
        }
        configurationPath = arguments[index + 1]
        index += 2
      default:
        throw HostError("unsupported test argument: \(arguments[index])")
      }
    }
    guard let configurationPath else {
      throw HostError("missing value for --host-config")
    }
    if !filters.isEmpty {
      testingArguments.filter = filters
    }
    return ParsedArguments(
      bundlePath: bundlePath,
      configurationPath: configurationPath,
      testingArguments: testingArguments
    )
  }

  private static func loadTestBundle(at path: String) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw HostError("test bundle binary is missing: \(path)")
    }
    guard dlopen(path, RTLD_NOW | RTLD_GLOBAL) != nil else {
      let detail = dlerror().map { String(cString: $0) } ?? "unknown loader error"
      throw HostError("failed to load test bundle: \(detail)")
    }
  }

  private static func failBeforeConfiguration(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    Darwin.exit(1)
  }

  private static func failAfterConfiguration(
    _ message: String,
    configuration: HostConfiguration
  ) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    configuration.finish(status: 1)
  }

  private static func redirectStandardOutput(to path: String) throws {
    let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC, mode_t(0o600))
    guard descriptor >= 0 else {
      throw HostError("could not open host log \(path): \(String(cString: strerror(errno)))")
    }
    defer { _ = Darwin.close(descriptor) }
    guard dup2(descriptor, STDOUT_FILENO) >= 0,
      dup2(descriptor, STDERR_FILENO) >= 0
    else {
      throw HostError("could not redirect host output to \(path)")
    }
  }

  private static func writeHostFile(_ contents: String, to path: String) throws {
    try Data(contents.utf8).write(
      to: URL(fileURLWithPath: path),
      options: .atomic
    )
  }
}

private struct ParsedArguments {
  let bundlePath: String
  let configurationPath: String
  let testingArguments: Testing.__CommandLineArguments_v0
}

private struct HostConfiguration {
  let nonce: String
  let receiptPath: String
  let processPath: String
  let phasePath: String
  let logPath: String

  func writePhase(_ phase: String) {
    do {
      try Data("\(phase)\n".utf8).write(
        to: URL(fileURLWithPath: phasePath),
        options: .atomic
      )
    } catch {
      FileHandle.standardError.write(
        Data("error: could not record host phase \(phase): \(error)\n".utf8)
      )
    }
  }

  func finish(status: CInt) -> Never {
    writePhase("completed")
    do {
      try Data("\(nonce)\t\(getpid())\t\(status)\n".utf8).write(
        to: URL(fileURLWithPath: receiptPath),
        options: .atomic
      )
    } catch {
      FileHandle.standardError.write(
        Data("error: could not write test completion receipt: \(error)\n".utf8)
      )
      Darwin.exit(status == 0 ? 1 : status)
    }
    Darwin.exit(status)
  }

  static func read(at path: String) throws -> HostConfiguration {
    let fields = try Data(contentsOf: URL(fileURLWithPath: path))
      .split(separator: 0, omittingEmptySubsequences: false)
    guard fields.count == 6, fields.last?.isEmpty == true else {
      throw HostError("invalid AppKit test host configuration")
    }
    let values = try fields.dropLast().map { field -> String in
      guard let value = String(data: Data(field), encoding: .utf8) else {
        throw HostError("AppKit test host configuration is not UTF-8")
      }
      return value
    }
    guard UUID(uuidString: values[0]) != nil,
      values.dropFirst().allSatisfy({ !$0.isEmpty })
    else {
      throw HostError("invalid AppKit test host configuration values")
    }
    return HostConfiguration(
      nonce: values[0],
      receiptPath: values[1],
      processPath: values[2],
      phasePath: values[3],
      logPath: values[4]
    )
  }
}

private struct HostError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

@MainActor
private final class AppKitTestApplicationDelegate: NSObject, NSApplicationDelegate {
  private let application: NSApplication
  private let testingArguments: Testing.__CommandLineArguments_v0
  private let configuration: HostConfiguration
  private var didStartTestRun = false

  init(
    application: NSApplication,
    testingArguments: Testing.__CommandLineArguments_v0,
    configuration: HostConfiguration
  ) {
    self.application = application
    self.testingArguments = testingArguments
    self.configuration = configuration
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !didStartTestRun else {
      fail("AppKit test host received a duplicate applicationDidFinishLaunching callback")
    }
    didStartTestRun = true
    guard application.activationPolicy() == .regular else {
      fail("expected the LaunchServices test host to have regular activation policy")
    }
    configuration.writePhase("didFinishLaunching")

    writePhase("requestingActivation")
    application.activate(ignoringOtherApps: true)
    Task { @MainActor in
      guard await waitForActivation() else {
        fail("AppKit test host did not become active within 5 seconds")
      }
      await runTests()
    }
  }

  func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    finish(status: 1)
  }

  private func runTests() async {
    configuration.writePhase("runningTests")
    let status: CInt = await Testing.__swiftPMEntryPoint(passing: testingArguments)
    finish(status: status)
  }

  private func waitForActivation() async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while true {
      if application.activationPolicy() == .regular && application.isActive {
        return true
      }
      let remaining = clock.now.duration(to: deadline)
      guard remaining > .zero else { return false }
      do {
        try await Task.sleep(for: min(.milliseconds(25), remaining))
      } catch {
        return false
      }
    }
  }

  private func writePhase(_ phase: String) {
    configuration.writePhase(phase)
  }

  private func finish(status: CInt) -> Never {
    configuration.finish(status: status)
  }
}
