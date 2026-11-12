import AppKit
import Combine
import SwiftUI
import Testing

@testable import FleckApp

@MainActor
private final class AboutAccessibilityState: ObservableObject {
  @Published var showsAbout = false
  @Published var searchRequest: SettingsSearchRequest?
}

@MainActor
private struct AboutAccessibilityFixture: View {
  @ObservedObject var state: AboutAccessibilityState
  let identity: BuildIdentity
  let updates: AppUpdateController

  var body: some View {
    ScrollView {
      if state.showsAbout {
        AboutSettingsView(identity: identity, updateController: updates)
          .environment(\.settingsSearchRequest, state.searchRequest)
      } else {
        Text("Synthetic General settings")
      }
    }
    .padding(20)
  }
}

@MainActor
private struct AboutAccessibilityElement {
  let identifier: String
  let role: String
  let label: String
  let value: String
}

@MainActor
private func aboutAccessibilityElements(in root: NSObject) throws -> [AboutAccessibilityElement] {
  var pending = [root]
  var visited: Set<ObjectIdentifier> = []
  var elements: [AboutAccessibilityElement] = []

  while let object = pending.popLast() {
    guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
    try #require(visited.count <= 512, "The synthetic About accessibility tree must be bounded")

    func string(_ attribute: String) -> String {
      let selector = NSSelectorFromString(attribute)
      guard object.responds(to: selector) else { return "" }
      return object.perform(selector)?.takeUnretainedValue() as? String ?? ""
    }

    let role = string("accessibilityRole")
    let label = string("accessibilityLabel")
    let value = string("accessibilityValue")
    _ = string("accessibilityHelp")
    elements.append(
      AboutAccessibilityElement(
        identifier: string("accessibilityIdentifier"),
        role: role,
        label: label,
        value: value
      )
    )

    let selector = NSSelectorFromString("accessibilityChildren")
    if object.responds(to: selector),
      let children = object.perform(selector)?.takeUnretainedValue() as? [Any]
    {
      pending.append(contentsOf: NSAccessibility.unignoredChildren(from: children).compactMap {
        $0 as? NSObject
      })
    }
  }
  return elements
}

@Test(.serialized, arguments: [true, false]) @MainActor
func aboutSettingsAccessibilitySurvivesNavigationAndMetadataExpansion(isPackaged: Bool) async throws {
  let identity = BuildIdentity(
    infoDictionary: isPackaged ? [
      "CFBundleIdentifier": "org.fleck.synthetic.about-accessibility",
      "CFBundleVersion": "1.0.1",
      "FleckVersion": "1.0.0-beta.1",
      "FleckBuildNumber": "2",
      "FleckBuildID": "00000000-0000-4000-8000-000000000001",
      "FleckBuildDate": "2026-01-01T00:00:00Z",
      "FleckSourceCommit": String(repeating: "a", count: 40),
      "FleckSourceTree": String(repeating: "b", count: 40),
      "FleckBuildFlavor": "development",
      "FleckBuildConfiguration": "Debug",
      "FleckCandidateStatus": "Synthetic fixture - not accepted",
      "FleckBaselineManifestSHA256": String(repeating: "c", count: 64),
      "FleckBaselineRecordID": "synthetic-fixture",
      "FleckBaselineRegistryStatus": "active",
    ] : nil,
    bundleIdentifier: "org.fleck.synthetic.about-accessibility"
  )
  let updates = AppUpdateController(infoDictionary: nil, identity: identity) { _, _ in
    Issue.record("An accessibility fixture must not create an update checker")
    return nil
  }
  let state = AboutAccessibilityState()
  let host = NSHostingView(
    rootView: AboutAccessibilityFixture(state: state, identity: identity, updates: updates)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
  )
  window.title = "Synthetic About accessibility fixture"
  window.contentView = host
  window.orderFrontRegardless()
  let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
  let previous = NSApplication.shared.accessibilityAttributeValue(attribute)
  NSApplication.shared.accessibilitySetValue(true, forAttribute: attribute)
  defer {
    NSApplication.shared.accessibilitySetValue(previous, forAttribute: attribute)
    window.contentView = nil
    window.orderOut(nil)
  }

  for _ in 0..<20 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
  }
  #expect(!(try aboutAccessibilityElements(in: host)).isEmpty)

  state.showsAbout = true
  for _ in 0..<30 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
  }
  let collapsed = try aboutAccessibilityElements(in: host)
  #expect(collapsed.contains {
    $0.identifier == SettingsSearchTarget.aboutCopyBuildInfo.accessibilityIdentifier
  })
  #expect(!collapsed.contains { $0.identifier == "settings-about-metadata-content" })
  let expectedValues: [(String, String)] = isPackaged
    ? [
      ("Product version", "1.0.0-beta.1"),
      ("Build", "#2"),
      ("Source", String(repeating: "a", count: 12)),
      ("Candidate status", "Synthetic fixture - not accepted"),
    ]
    : [("Build", "Unpackaged development build")]
  for (label, value) in expectedValues {
    #expect(collapsed.contains {
      $0.role == "AXStaticText" && $0.label == label && $0.value == value
    })
  }

  state.searchRequest = SettingsSearchRequest(target: .aboutMetadata)
  var metadata: AboutAccessibilityElement?
  for _ in 0..<60 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    metadata = try aboutAccessibilityElements(in: host).first {
      $0.identifier == "settings-about-metadata-content"
    }
    if metadata != nil { break }
  }
  let content = try #require(metadata, "Search must expand and expose full build metadata")
  #expect(content.label == "Full build metadata")
  #expect(content.value == identity.copyText)
  #expect(content.role == "AXStaticText")
  #expect(!updates.canCheckForUpdates)

  if let path = ProcessInfo.processInfo.environment["FLECK_SETTINGS_WINDOW_CAPTURE_DIR"] {
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: image)
    let data = try #require(image.representation(using: .png, properties: [:]))
    try data.write(
      to: directory.appendingPathComponent("about-accessibility-\(isPackaged ? "packaged" : "unpackaged").png"),
      options: .atomic
    )
  }
}
