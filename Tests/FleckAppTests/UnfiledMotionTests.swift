import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor func unfiledCompactDisclosureDoesNotSelectAndRepeatedReversalRestoresEndpoint()
  async throws
{
  NSApplication.shared.accessibilitySetValue(
    true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let folder = try Folder(id: UUID(), name: "School")
  let note = Note(title: "Filed fixture", body: "Fixture", folderID: folder.id)
  let state = AppState(
    store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [folder])
  state.updatePreferences { $0.isUnfiledCompact = false }
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime, isPinned: false, editorCommands: EditorCommands()
    ).environmentObject(state))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430), styleMask: [.titled],
    backing: .buffered, defer: false)
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  defer {
    window.contentView = nil
    window.orderOut(nil)
  }
  await unfiledSettle(host)
  let initial = try #require(unfiledKeyViews(host).first)
  let expanded = try #require(
    unfiledAX(host, label: "Unfiled")?.value(forKey: "accessibilityFrame") as? NSValue
  ).rectValue
  #expect(window.makeFirstResponder(initial))
  await unfiledSettle(host)
  if let directory = ProcessInfo.processInfo.environment["UNFILED_CAPTURE_DIR"] {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let recording = Process()
    recording.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    recording.arguments = [
      "-x", "-v", "-V", "3", "-l", String(window.windowNumber), directory + "/unfiled-normal.mov",
    ]
    try recording.run()
    try await Task.sleep(for: .milliseconds(700))
    for delay in [100, 400, 500, 400] {
      let label = state.preferences.isUnfiledCompact ? "Expand Unfiled" : "Collapse Unfiled"
      let frame = try #require(
        unfiledAX(host, label: label)?.value(forKey: "accessibilityFrame") as? NSValue
      ).rectValue
      let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
      for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(
          NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
        window.sendEvent(event)
      }
      try await Task.sleep(for: .milliseconds(delay))
      await unfiledSettle(host)
    }
    try await Task.sleep(for: .seconds(1))
    print("UNFILED capture exit: \(recording.isRunning ? -1 : recording.terminationStatus)")
  }
  state.updatePreferences { $0.isUnfiledCompact = false }
  _ = window.makeFirstResponder(unfiledKeyViews(host).first)
  await unfiledSettle(host)
  for compact in [true, false, true, false] {
    let button = try #require(
      unfiledAX(host, label: compact ? "Collapse Unfiled" : "Expand Unfiled"))
    _ = button.perform(NSSelectorFromString("accessibilityPerformPress"))
    await unfiledSettle(host)
    #expect(state.preferences.isUnfiledCompact == compact)
    #expect(state.workspace.selectedNoteID == note.id)
  }
  let final = try #require(
    unfiledAX(host, label: "Unfiled")?.value(forKey: "accessibilityFrame") as? NSValue
  ).rectValue
  #expect(final == expanded)
  print("UNFILED expanded selection frame: \(expanded)")
  let collapse = try #require(unfiledAX(host, label: "Collapse Unfiled"))
  _ = collapse.perform(NSSelectorFromString("accessibilityPerformPress"))
  await unfiledSettle(host)
  let compact = try #require(
    unfiledAX(host, label: "Unfiled")?.value(forKey: "accessibilityFrame") as? NSValue
  ).rectValue
  print("UNFILED compact selection frame: \(compact)")
  #expect(compact.minX == expanded.minX)
  #expect(compact.height == expanded.height)
  #expect(compact.width < expanded.width)
  let select = try #require(unfiledAX(host, label: "Unfiled"))
  _ = select.perform(NSSelectorFromString("accessibilityPerformPress"))
  await unfiledSettle(host)
  #expect(state.preferences.isUnfiledCompact)
  #expect(
    (unfiledAX(host, label: "Unfiled")?.value(forKey: "accessibilityValue") as? String)?.contains(
      "Selected") == true)
}

@MainActor private func unfiledSettle(_ host: NSView) async {
  try? await Task.sleep(for: .milliseconds(50))
  for _ in 0..<12 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@MainActor private func unfiledKeyViews(_ root: NSView) -> [NSView] {
  var result: [NSView] = []
  func visit(_ view: NSView) {
    let frame = view.convert(view.bounds, to: root)
    if String(describing: type(of: view)) == "KeyViewProxy", frame.minY >= 42, frame.maxY <= 82 {
      result.append(view)
    }
    for child in view.subviews { visit(child) }
  }
  visit(root)
  return result.sorted {
    $0.convert($0.bounds, to: root).minX < $1.convert($1.bounds, to: root).minX
  }
}

@MainActor private func unfiledAX(_ value: Any, label: String) -> NSObject? {
  guard let element = value as? NSObject else { return nil }
  let labelSelector = NSSelectorFromString("accessibilityLabel")
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let name =
    element.responds(to: labelSelector)
    ? element.perform(labelSelector)?.takeUnretainedValue() as? String : nil
  if name == label { return element }
  let children =
    element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
  for child in children ?? [] { if let found = unfiledAX(child, label: label) { return found } }
  return nil
}
