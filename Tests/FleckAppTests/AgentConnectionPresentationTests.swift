import AppKit
import FleckCore
import Foundation
import SwiftUI
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentConnectionPresentationTests {
  @Test(arguments: [false, true]) @MainActor
  func setupPromptsAreAvailableBeforeConnectorInstallation(increasedContrast: Bool) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(
      store: LocalStore(rootURL: root),
      provisionAgentProfile: { _, _ in Issue.record("A layout fixture must not provision a connector") },
      disconnectAgentProfile: { _ in Issue.record("A layout fixture must not disconnect a connector") }
    )
    await state.waitUntilInitialLoad()
    let previousAppearance = NSApp.appearance
    defer { NSApp.appearance = previousAppearance }
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: increasedContrast ? .dark : .light,
      systemAppearance: increasedContrast ? .dark : .light,
      reduceTransparency: increasedContrast,
      increasedContrast: increasedContrast
    )
    let width: CGFloat = increasedContrast ? 440 : 640
    let host = NSHostingView(
      rootView: ScrollView {
        AgentSettingsView()
          .environmentObject(state)
          .padding(20)
      }
      .environment(\.fleckThemeSnapshot, theme)
      .environment(\.colorScheme, theme.colorScheme)
      .frame(width: width, height: 800)
      .background(theme.color(.window))
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
      styleMask: [.titled, .closable], backing: .buffered, defer: false
    )
    window.title = "Synthetic Fleck agent setup"
    window.appearance = NSAppearance(named: increasedContrast ? .accessibilityHighContrastDarkAqua : .aqua)
    window.contentView = host
    window.orderFrontRegardless()
    let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    let previous = NSApp.accessibilityAttributeValue(attribute)
    NSApp.accessibilitySetValue(true, forAttribute: attribute)
    defer {
      NSApp.accessibilitySetValue(previous, forAttribute: attribute)
      window.orderOut(nil)
      window.contentView = nil
    }
    let expectedLabels = [
      "Copy Codex setup prompt", "Copy Claude Code setup prompt",
      "Copy Kimi setup prompt", "Copy other agent setup prompt",
    ]
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    var buttons: [String: Bool] = [:]
    repeat {
      host.layoutSubtreeIfNeeded()
      buttons = try agentSetupButtons(in: host)
      if expectedLabels.allSatisfy({ buttons[$0] == true }) { break }
      try await Task.sleep(for: .milliseconds(25))
    } while clock.now < deadline
    for label in expectedLabels {
      #expect(buttons[label] == true, "Expected enabled setup action: \(label); observed \(buttons)")
    }
    #expect(state.agentProfiles.isEmpty)
    #expect(state.agentCapabilityState.profiles.isEmpty)
    #expect(state.agentConnectionPromptStatus == .idle)

    if let path = ProcessInfo.processInfo.environment["FLECK_MCP_SETUP_CAPTURE_DIR"] {
      let directory = URL(fileURLWithPath: path, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: image)
      let data = try #require(image.representation(using: .png, properties: [:]))
      try data.write(to: directory.appendingPathComponent(
        increasedContrast ? "agent-setup-narrow-dark-contrast.png" : "agent-setup-wide-light.png"
      ), options: .atomic)
    }
  }
}

@MainActor
private func agentSetupButtons(in root: NSObject) throws -> [String: Bool] {
  var pending = [root]
  var visited: Set<ObjectIdentifier> = []
  var buttons: [String: Bool] = [:]
  while let object = pending.popLast() {
    guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
    try #require(visited.count < 1024)
    func value(_ name: String) -> Any? {
      let selector = NSSelectorFromString(name)
      guard object.responds(to: selector) else { return nil }
      return object.perform(selector)?.takeUnretainedValue()
    }
    if value("accessibilityRole") as? String == "AXButton",
      let label = value("accessibilityLabel") as? String
    {
      if let accessibility = object as? NSAccessibilityProtocol {
        buttons[label] = accessibility.isAccessibilityEnabled()
      } else if object.responds(to: NSSelectorFromString("isAccessibilityEnabled")) {
        buttons[label] = (object.value(forKey: "accessibilityEnabled") as? NSNumber)?.boolValue
      }
    }
    if let children = value("accessibilityChildren") as? [Any] {
      pending.append(contentsOf: NSAccessibility.unignoredChildren(from: children).compactMap {
        $0 as? NSObject
      })
    }
  }
  return buttons
}
