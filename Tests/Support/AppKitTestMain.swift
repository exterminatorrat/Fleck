import AppKit
import Darwin
import Foundation
import Testing

private enum ModelsClickProbeNotification {
  static let arm = Notification.Name("org.fleck.appkit-test-host.models-click.arm")
  static let windowEvent = Notification.Name(
    "org.fleck.appkit-test-host.models-click.window-event"
  )
  static let disarm = Notification.Name("org.fleck.appkit-test-host.models-click.disarm")
  static let trackingMouseUpReceipt = Notification.Name(
    "org.fleck.appkit-test-host.models-click.tracking-mouse-up-receipt"
  )
}

@MainActor
private struct ModelsClickProbeEvent {
  let type: NSEvent.EventType
  let windowNumber: Int
  let eventNumber: Int
  let timestamp: TimeInterval
  let x: Double
  let y: Double
  let modifierFlags: NSEvent.ModifierFlags.RawValue
  let clickCount: Int

  init?(prefix: String, windowNumber: Int, userInfo: [AnyHashable: Any]) {
    guard let rawType = userInfo["\(prefix).type"] as? NSNumber,
      let eventNumber = userInfo["\(prefix).eventNumber"] as? NSNumber,
      let timestamp = userInfo["\(prefix).timestamp"] as? NSNumber,
      let x = userInfo["\(prefix).x"] as? NSNumber,
      let y = userInfo["\(prefix).y"] as? NSNumber,
      let modifierFlags = userInfo["\(prefix).flags"] as? NSNumber,
      let clickCount = userInfo["\(prefix).clickCount"] as? NSNumber
    else {
      return nil
    }

    let expectedType: NSEvent.EventType
    switch prefix {
    case "down":
      expectedType = .leftMouseDown
    case "up":
      expectedType = .leftMouseUp
    case "event":
      if rawType.intValue == Int(NSEvent.EventType.leftMouseDown.rawValue) {
        expectedType = .leftMouseDown
      } else if rawType.intValue == Int(NSEvent.EventType.leftMouseUp.rawValue) {
        expectedType = .leftMouseUp
      } else {
        return nil
      }
    default:
      return nil
    }
    guard rawType.intValue == Int(expectedType.rawValue) else { return nil }

    type = expectedType
    self.windowNumber = windowNumber
    self.eventNumber = eventNumber.intValue
    self.timestamp = timestamp.doubleValue
    self.x = x.doubleValue
    self.y = y.doubleValue
    self.modifierFlags = modifierFlags.uintValue
    self.clickCount = clickCount.intValue
  }

  func matches(_ event: NSEvent, in window: NSWindow) -> Bool {
    guard event.type == type,
      type == .leftMouseDown || type == .leftMouseUp,
      event.window === window
    else {
      return false
    }
    return event.windowNumber == windowNumber
      && window.windowNumber == windowNumber
      && event.eventNumber == eventNumber
      && event.timestamp == timestamp
      && Double(event.locationInWindow.x) == x
      && Double(event.locationInWindow.y) == y
      && event.modifierFlags.rawValue == modifierFlags
      && event.clickCount == clickCount
  }

  func hasSameIdentity(as other: ModelsClickProbeEvent) -> Bool {
    type == other.type
      && windowNumber == other.windowNumber
      && eventNumber == other.eventNumber
      && timestamp == other.timestamp
      && x == other.x
      && y == other.y
      && modifierFlags == other.modifierFlags
      && clickCount == other.clickCount
  }

  var typeName: String {
    type == .leftMouseDown ? "leftMouseDown" : "leftMouseUp"
  }

  var diagnosticIdentity: String {
    "type=\(typeName),eventNumber=\(eventNumber),timestamp=\(timestamp),"
      + "point=\(x):\(y),flags=\(modifierFlags),clickCount=\(clickCount)"
  }
}

@MainActor
private struct ArmedModelsClick {
  let generation: UUID
  let scenario: String
  let ordinal: Int
  let targetKind: String
  let window: NSWindow
  let windowNumber: Int
  let down: ModelsClickProbeEvent
  let up: ModelsClickProbeEvent
}

@MainActor
private struct ModelsClickProbeState {
  var downDispatchActive = false
  var downSuperDispatchReturned = false
  var upSuperDispatchReturned = false
  var nextEventUpSeen = false
  var nextEventUpDequeued = false
  var nextEventUpInTracking = false
  var nextEventUpDuringDown = false
  var nextEventUpDequeuedInTracking = false
  var nextEventUpDequeuedDuringDown = false
  var nextEventUpDequeuedInTrackingDuringDown = false
  var trackingMouseUpEvent: NSEvent?
  var qualifiedTrackingReceiptPosted = false
}

@MainActor
@objc(AppKitTestProbeApplication)
final class AppKitTestProbeApplication: NSApplication {
  private var hasInstalledModelsClickObservers = false
  private var armedModelsClick: ArmedModelsClick?
  private var modelsClickState = ModelsClickProbeState()

  func installModelsClickObservers() {
    guard !hasInstalledModelsClickObservers else { return }
    hasInstalledModelsClickObservers = true
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(armModelsClick(_:)),
      name: ModelsClickProbeNotification.arm,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(recordModelsWindowEvent(_:)),
      name: ModelsClickProbeNotification.windowEvent,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(disarmModelsClick(_:)),
      name: ModelsClickProbeNotification.disarm,
      object: nil
    )
  }

  override func nextEvent(
    matching mask: NSEvent.EventTypeMask,
    until expiration: Date?,
    inMode mode: RunLoop.Mode,
    dequeue: Bool
  ) -> NSEvent? {
    let event = super.nextEvent(
      matching: mask,
      until: expiration,
      inMode: mode,
      dequeue: dequeue
    )
    if let event,
      let armedModelsClick,
      armedModelsClick.up.matches(event, in: armedModelsClick.window)
    {
      modelsClickState.nextEventUpSeen = true
      if dequeue {
        modelsClickState.nextEventUpDequeued = true
        if mode == .eventTracking {
          modelsClickState.nextEventUpDequeuedInTracking = true
        }
        if modelsClickState.downDispatchActive {
          modelsClickState.nextEventUpDequeuedDuringDown = true
        }
        if mode == .eventTracking && modelsClickState.downDispatchActive {
          modelsClickState.nextEventUpDequeuedInTrackingDuringDown = true
          if modelsClickState.trackingMouseUpEvent == nil {
            modelsClickState.trackingMouseUpEvent = event
          }
        }
      }
      if mode == .eventTracking {
        modelsClickState.nextEventUpInTracking = true
      }
      if modelsClickState.downDispatchActive {
        modelsClickState.nextEventUpDuringDown = true
      }
      writeModelsClickProbe(
        "scenario=\(armedModelsClick.scenario) ordinal=\(armedModelsClick.ordinal) "
          + "target=\(armedModelsClick.targetKind) route=NSApplication.nextEvent "
          + "type=leftMouseUp window=\(windowIdentity(armedModelsClick.window)) "
          + "identity={\(armedModelsClick.up.diagnosticIdentity)} mask=\(mask.rawValue) "
          + "dequeue=\(dequeue) mode=\(mode.rawValue) "
          + "eventTracking=\(mode == .eventTracking) "
          + "duringOwnedWindowSynchronousDown=\(modelsClickState.downDispatchActive) "
          + "downSuperDispatchReturned=\(modelsClickState.downSuperDispatchReturned)"
      )
    }
    return event
  }

  @objc private func armModelsClick(_ notification: Notification) {
    guard let window = notification.object as? NSWindow,
      let userInfo = notification.userInfo,
      let generationValue = userInfo["generation"] as? String,
      let generation = UUID(uuidString: generationValue),
      let scenario = userInfo["scenario"] as? String,
      let ordinal = (userInfo["ordinal"] as? NSNumber)?.intValue,
      let targetKind = userInfo["targetKind"] as? String,
      let windowNumber = (userInfo["windowNumber"] as? NSNumber)?.intValue,
      windowNumber == window.windowNumber,
      let down = ModelsClickProbeEvent(
        prefix: "down",
        windowNumber: windowNumber,
        userInfo: userInfo
      ),
      let up = ModelsClickProbeEvent(
        prefix: "up",
        windowNumber: windowNumber,
        userInfo: userInfo
      ),
      down.eventNumber > 0,
      up.eventNumber > down.eventNumber
    else {
      writeModelsClickProbe("route=armRejected")
      return
    }
    guard armedModelsClick == nil else {
      writeModelsClickProbe("route=armRejected reason=clickAlreadyArmed")
      return
    }
    armedModelsClick = ArmedModelsClick(
      generation: generation,
      scenario: scenario,
      ordinal: ordinal,
      targetKind: targetKind,
      window: window,
      windowNumber: windowNumber,
      down: down,
      up: up
    )
    modelsClickState = ModelsClickProbeState()
    writeModelsClickProbe(
      "scenario=\(scenario) ordinal=\(ordinal) target=\(targetKind) route=armed "
        + "window=\(windowIdentity(window)) down={\(down.diagnosticIdentity)} "
        + "up={\(up.diagnosticIdentity)}"
    )
  }

  @objc private func recordModelsWindowEvent(_ notification: Notification) {
    guard let armedModelsClick,
      let window = notification.object as? NSWindow,
      window === armedModelsClick.window,
      let userInfo = notification.userInfo,
      let phase = userInfo["phase"] as? String,
      let generation = userInfo["generation"] as? String,
      generation == armedModelsClick.generation.uuidString,
      let windowNumber = (userInfo["windowNumber"] as? NSNumber)?.intValue,
      let event = ModelsClickProbeEvent(
        prefix: "event",
        windowNumber: windowNumber,
        userInfo: userInfo
      ),
      windowNumber == armedModelsClick.windowNumber,
      event.hasSameIdentity(as: armedModelsClick.down)
        || event.hasSameIdentity(as: armedModelsClick.up)
    else {
      return
    }

    let isDown = event.type == .leftMouseDown
    switch phase {
    case "entry":
      if isDown {
        modelsClickState.downDispatchActive = true
      }
    case "return":
      if isDown {
        modelsClickState.downDispatchActive = false
        modelsClickState.downSuperDispatchReturned = true
        if let event = modelsClickState.trackingMouseUpEvent,
          modelsClickState.nextEventUpDequeuedInTrackingDuringDown,
          modelsClickState.downSuperDispatchReturned,
          !modelsClickState.qualifiedTrackingReceiptPosted
        {
          modelsClickState.qualifiedTrackingReceiptPosted = true
          NotificationCenter.default.post(
            name: ModelsClickProbeNotification.trackingMouseUpReceipt,
            object: event,
            userInfo: [
              "generation": armedModelsClick.generation.uuidString,
              "windowNumber": armedModelsClick.windowNumber,
              "dequeue": true,
              "mode": RunLoop.Mode.eventTracking.rawValue,
              "dequeuedDuringOwnedWindowSynchronousDown": true,
              "downSuperDispatchReturned": true,
            ]
          )
          writeModelsClickProbe(
            "scenario=\(armedModelsClick.scenario) ordinal=\(armedModelsClick.ordinal) "
              + "target=\(armedModelsClick.targetKind) "
              + "route=qualifiedTrackingReceipt "
              + "generation=\(armedModelsClick.generation.uuidString) "
              + "window=\(windowIdentity(armedModelsClick.window)) "
              + "identity={\(armedModelsClick.up.diagnosticIdentity)} "
              + "dequeue=true mode=\(RunLoop.Mode.eventTracking.rawValue) "
              + "dequeuedDuringOwnedWindowSynchronousDown=true "
              + "downSuperDispatchReturned=true"
          )
        }
      } else {
        modelsClickState.upSuperDispatchReturned = true
      }
    default:
      return
    }
    writeModelsClickProbe(
      "scenario=\(armedModelsClick.scenario) ordinal=\(armedModelsClick.ordinal) "
        + "target=\(armedModelsClick.targetKind) route=NSWindow.sendEvent "
        + "phase=\(phase) type=\(event.typeName) "
        + "window=\(windowIdentity(window)) identity={\(event.diagnosticIdentity)} "
        + "downDispatchActive=\(modelsClickState.downDispatchActive) "
        + "downSuperDispatchReturned=\(modelsClickState.downSuperDispatchReturned) "
        + "upSuperDispatchReturned=\(modelsClickState.upSuperDispatchReturned)"
        + " qualifiedTrackingReceiptPosted=\(modelsClickState.qualifiedTrackingReceiptPosted)"
    )
  }

  @objc private func disarmModelsClick(_ notification: Notification) {
    guard let armedModelsClick,
      let window = notification.object as? NSWindow,
      window === armedModelsClick.window,
      let generation = notification.userInfo?["generation"] as? String,
      generation == armedModelsClick.generation.uuidString
    else {
      return
    }
    writeModelsClickProbe(
      "scenario=\(armedModelsClick.scenario) ordinal=\(armedModelsClick.ordinal) "
        + "target=\(armedModelsClick.targetKind) route=summary "
        + "window=\(windowIdentity(window)) upNextEventSeen=\(modelsClickState.nextEventUpSeen) "
        + "upDequeued=\(modelsClickState.nextEventUpDequeued) "
        + "upInEventTracking=\(modelsClickState.nextEventUpInTracking) "
        + "upDuringOwnedWindowSynchronousDown=\(modelsClickState.nextEventUpDuringDown) "
        + "upDequeuedInEventTracking=\(modelsClickState.nextEventUpDequeuedInTracking) "
        + "upDequeuedDuringOwnedWindowSynchronousDown=\(modelsClickState.nextEventUpDequeuedDuringDown) "
        + "upDequeuedInEventTrackingDuringOwnedWindowSynchronousDown="
        + "\(modelsClickState.nextEventUpDequeuedInTrackingDuringDown) "
        + "downSuperDispatchReturned=\(modelsClickState.downSuperDispatchReturned) "
        + "upSuperDispatchReturned=\(modelsClickState.upSuperDispatchReturned)"
    )
    self.armedModelsClick = nil
    modelsClickState = ModelsClickProbeState()
  }

  private func writeModelsClickProbe(_ fields: String) {
    FileHandle.standardError.write(Data("MODELS_CLICK_PROBE \(fields)\n".utf8))
  }

  private func windowIdentity(_ window: NSWindow) -> String {
    "\(window.windowNumber):\(ObjectIdentifier(window))"
  }
}

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

    let sharedApplication = AppKitTestProbeApplication.shared
    guard let application = sharedApplication as? AppKitTestProbeApplication else {
      failAfterConfiguration(
        "AppKit test host did not instantiate its configured diagnostic NSApplication class",
        configuration: configuration
      )
    }
    application.installModelsClickObservers()
    configuration.writeDiagnostic(
      "MODELS_CLICK_PROBE_INSTALL class=\(NSStringFromClass(type(of: application))) "
        + "exactPrincipalClass=true beforeTestBundle=true"
    )

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

  func writeDiagnostic(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
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
