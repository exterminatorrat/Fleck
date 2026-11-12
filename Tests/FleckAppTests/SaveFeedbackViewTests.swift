import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Suite("SaveFeedbackView")
@MainActor
struct SaveFeedbackViewTests {
  @Test
  func hostedFeedbackKeepsQuietChromeGeometryAndApprovedAccessibility() async throws {
    let previousAXEnhancedUserInterface = enableHostedAccessibility()
    defer { restoreHostedAccessibility(previousAXEnhancedUserInterface) }

    let themes: [(name: String, theme: FleckThemeSnapshot, appearance: NSAppearance.Name)] = [
      (
        "light",
        FleckThemeSnapshot.resolve(
          colorTheme: .monochrome,
          mode: .light,
          systemAppearance: .light,
          reduceTransparency: false,
          increasedContrast: false
        ),
        .aqua
      ),
      (
        "dark",
        FleckThemeSnapshot.resolve(
          colorTheme: .capy,
          mode: .dark,
          systemAppearance: .dark,
          reduceTransparency: false,
          increasedContrast: false
        ),
        .darkAqua
      ),
      (
        "high-contrast",
        FleckThemeSnapshot.resolve(
          colorTheme: .monochrome,
          mode: .light,
          systemAppearance: .light,
          reduceTransparency: false,
          increasedContrast: true
        ),
        .accessibilityHighContrastAqua
      ),
    ]
    let widths: [(name: String, width: CGFloat)] = [("narrow", 320), ("wide", 900)]

    for themeCase in themes {
      for widthCase in widths {
        let fixture = HostedSaveFeedbackFixture(
          width: widthCase.width,
          theme: themeCase.theme,
          appearance: themeCase.appearance,
          reduceMotion: false
        )
        defer { fixture.close() }

        for state in HostedSaveFeedbackFixture.states {
          fixture.show(state)
          let element = try #require(
            try await fixture.waitForAccessibilityElement(
              value: state.accessibilityValue
            ),
            "Missing save status element for \(themeCase.name) \(widthCase.name) \(state)"
          )
          await fixture.settle()
          #expect(hostedAccessibilityLabel(element) == "Save status")
          #expect(
            hostedAccessibilityValue(element) == state.accessibilityValue,
            "Expected \(state.accessibilityValue) for \(themeCase.name) \(widthCase.name)"
          )
          #expect(!fixture.accessibilityTexts().contains("Saved"))
          #expect(abs(fixture.host.fittingSize.width - widthCase.width) < 0.5)
          #expect(abs(fixture.host.fittingSize.height - 22) < 0.5)
          let frame = try #require(fixture.accessibilityFrame(element))
          #expect(abs(frame.width - 62) < 1)
          #expect(abs(frame.height - 22) < 1)
          try fixture.capture(
            state: state,
            theme: themeCase.name,
            width: widthCase.name,
            reduceMotion: false
          )
        }
      }
    }
  }

  @Test
  func reduceMotionFeedbackKeepsGeometryAndAccessibility() async throws {
    let previousAXEnhancedUserInterface = enableHostedAccessibility()
    defer { restoreHostedAccessibility(previousAXEnhancedUserInterface) }

    let fixture = HostedSaveFeedbackFixture(
      width: 320,
      theme: FleckThemeSnapshot.resolve(
        colorTheme: .monochrome,
        mode: .light,
        systemAppearance: .light,
        reduceTransparency: false,
        increasedContrast: false
      ),
      appearance: .aqua,
      reduceMotion: true
    )
    defer { fixture.close() }

    for state in HostedSaveFeedbackFixture.states {
      fixture.show(state)
      let element = try #require(
        try await fixture.waitForAccessibilityElement(value: state.accessibilityValue)
      )
      await fixture.settle()
      #expect(hostedAccessibilityValue(element) == state.accessibilityValue)
      let frame = try #require(fixture.accessibilityFrame(element))
      #expect(abs(frame.width - 62) < 1)
      #expect(abs(frame.height - 22) < 1)
      #expect(abs(fixture.host.fittingSize.width - 320) < 0.5)
      #expect(abs(fixture.host.fittingSize.height - 22) < 0.5)
      try fixture.capture(
        state: state,
        theme: "light",
        width: "narrow",
        reduceMotion: true
      )
    }
  }
}

@MainActor
private final class HostedSaveFeedbackFixture {
  let presentation: SaveFeedbackPresentation
  let host: NSHostingView<AnyView>

  private let scheduler: SaveFeedbackRevealScheduler
  private let window: NSWindow

  init(
    width: CGFloat,
    theme: FleckThemeSnapshot,
    appearance: NSAppearance.Name,
    reduceMotion: Bool
  ) {
    let scheduler = SaveFeedbackRevealScheduler()
    self.scheduler = scheduler
    let presentation = SaveFeedbackPresentation(scheduleReveal: scheduler.schedule)
    self.presentation = presentation
    host = NSHostingView(
      rootView: AnyView(
        HStack(spacing: 0) {
          Spacer(minLength: 0)
          SaveFeedbackView(
            presentation: presentation,
            motion: AppMotion(reduceMotion: reduceMotion)
          )
        }
        .frame(width: width, height: 22)
        .environment(\.fleckThemeSnapshot, theme)
      )
    )
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 22),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: appearance)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
  }

  static let states: [SaveFeedbackState] = [.saved, .pending, .saving, .failed]

  func show(_ state: SaveFeedbackState) {
    presentation.reset()
    switch state {
    case .saved:
      break
    case .pending:
      presentation.changesScheduled()
    case .saving:
      presentation.changesScheduled()
      presentation.writeBegan()
      scheduler.fireAll()
    case .failed:
      presentation.changesScheduled()
      presentation.writeBegan()
      presentation.writeEnded()
      presentation.settle(.failed)
    }
  }

  func settle() async {
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    host.displayIfNeeded()
  }

  func waitForAccessibilityElement(value: String) async throws -> NSObject? {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
      await settle()
      if let element = accessibilityElement(),
        hostedAccessibilityValue(element) == value
      {
        return element
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    return accessibilityElement()
  }

  func accessibilityElement() -> NSObject? {
    let byIdentifier = hostedAccessibilityElements(in: host, identifier: "save-feedback")
    return byIdentifier.first
      ?? hostedAccessibilityElements(in: host, label: "Save status").first
  }

  func accessibilityFrame(_ element: NSObject) -> CGRect? {
    (element.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue
  }

  func accessibilityTexts() -> [String] {
    hostedAccessibilityTexts(in: host)
  }

  func capture(
    state: SaveFeedbackState,
    theme: String,
    width: String,
    reduceMotion: Bool
  ) throws {
    guard
      let directoryPath = ProcessInfo.processInfo.environment["FLECK_LAYOUT_EVIDENCE_DIR"]
    else { return }
    let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    host.displayIfNeeded()
    let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: image)
    let png = try #require(image.representation(using: .png, properties: [:]))
    let name =
      "save-feedback-\(stateName(state))-\(theme)-\(width)-rm\(reduceMotion ? 1 : 0).png"
    try png.write(to: directory.appendingPathComponent(name), options: .atomic)
  }

  func close() {
    window.orderOut(nil)
    window.contentView = nil
  }

  private func stateName(_ state: SaveFeedbackState) -> String {
    switch state {
    case .saved: "saved"
    case .pending: "pending"
    case .saving: "saving"
    case .failed: "failed"
    }
  }
}

@MainActor
private final class SaveFeedbackRevealScheduler {
  private var actions: [@MainActor () -> Void] = []

  func schedule(
    after delay: Duration,
    _ action: @escaping @MainActor () -> Void
  ) {
    actions.append(action)
  }

  func fireAll() {
    let pending = actions
    actions.removeAll()
    for action in pending { action() }
  }
}

@MainActor
private func enableHostedAccessibility() -> Any? {
  let application = NSApplication.shared
  let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
  let previousValue = application.accessibilityAttributeValue(attribute)
  application.accessibilitySetValue(true, forAttribute: attribute)
  return previousValue
}

@MainActor
private func restoreHostedAccessibility(_ value: Any?) {
  NSApplication.shared.accessibilitySetValue(
    value,
    forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
  )
}

@MainActor
private func hostedAccessibilityElements(in value: Any?, identifier: String) -> [NSObject] {
  guard let element = value as? NSObject else { return [] }
  let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
  let matchesIdentifier =
    element.responds(to: identifierSelector)
    && element.perform(identifierSelector)?.takeUnretainedValue() as? String == identifier
  var matches = matchesIdentifier ? [element] : []
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let rawChildren =
    element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
  for child in NSAccessibility.unignoredChildren(from: rawChildren ?? []) {
    matches.append(contentsOf: hostedAccessibilityElements(in: child, identifier: identifier))
  }
  return matches
}

@MainActor
private func hostedAccessibilityElements(in value: Any?, label: String) -> [NSObject] {
  guard let element = value as? NSObject else { return [] }
  var matches = hostedAccessibilityLabel(element) == label ? [element] : []
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let rawChildren =
    element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
  for child in NSAccessibility.unignoredChildren(from: rawChildren ?? []) {
    matches.append(contentsOf: hostedAccessibilityElements(in: child, label: label))
  }
  return matches
}

@MainActor
private func hostedAccessibilityLabel(_ element: NSObject) -> String? {
  for attribute in ["accessibilityLabel", "accessibilityTitle"] {
    let selector = NSSelectorFromString(attribute)
    guard element.responds(to: selector),
      let value = element.perform(selector)?.takeUnretainedValue()
    else { continue }
    if let text = value as? String, !text.isEmpty { return text }
    if let text = value as? NSAttributedString, !text.string.isEmpty { return text.string }
  }
  return nil
}

@MainActor
private func hostedAccessibilityValue(_ element: NSObject) -> String? {
  for attribute in ["accessibilityValue", "accessibilityValueDescription"] {
    let selector = NSSelectorFromString(attribute)
    guard element.responds(to: selector),
      let value = element.perform(selector)?.takeUnretainedValue()
    else { continue }
    if let text = value as? String, !text.isEmpty { return text }
    if let text = value as? NSAttributedString, !text.string.isEmpty { return text.string }
  }
  return nil
}

@MainActor
private func hostedAccessibilityTexts(in value: Any?) -> [String] {
  guard let element = value as? NSObject else { return [] }
  var texts: [String] = []
  if let label = hostedAccessibilityLabel(element) { texts.append(label) }
  if let valueText = hostedAccessibilityValue(element) { texts.append(valueText) }
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let rawChildren =
    element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
  for child in NSAccessibility.unignoredChildren(from: rawChildren ?? []) {
    texts.append(contentsOf: hostedAccessibilityTexts(in: child))
  }
  return texts
}
