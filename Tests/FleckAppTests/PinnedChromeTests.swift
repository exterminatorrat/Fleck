import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test func pinnedChromeMaterialPolicyUsesNativeGlassWhenAvailable() {
  #expect(
    PinnedChromeMaterialPolicy.resolve(
      supportsLiquidGlass: true,
      reduceTransparency: false,
      increasedContrast: false
    ) == .liquidGlass
  )
}

@Test func pinnedChromeMaterialPolicyUsesLegacyMaterialWithoutGlass() {
  #expect(
    PinnedChromeMaterialPolicy.resolve(
      supportsLiquidGlass: false,
      reduceTransparency: false,
      increasedContrast: false
    ) == .legacyMaterial
  )
}

@Test func pinnedChromeMaterialPolicyUsesOpaqueAccessibilitySurface() {
  #expect(
    PinnedChromeMaterialPolicy.resolve(
      supportsLiquidGlass: true,
      reduceTransparency: true,
      increasedContrast: false
    ) == .opaque
  )
  #expect(
    PinnedChromeMaterialPolicy.resolve(
      supportsLiquidGlass: true,
      reduceTransparency: false,
      increasedContrast: true
    ) == .opaque
  )
  #expect(
    PinnedChromeMaterialPolicy.resolve(
      supportsLiquidGlass: true,
      reduceTransparency: true,
      increasedContrast: true
    ) == .opaque
  )
}

@Test @MainActor func pinnedChromeHostedPanelPreservesSizeAndResponderGeometry() async throws {
  let fixture = try await hostedPinnedPanel()
  do {
    if let capturePath = ProcessInfo.processInfo.environment["FLECK_PINNED_CHROME_CAPTURE_PATH"] {
      try capture(fixture.host, at: URL(fileURLWithPath: capturePath))
    }

    let title = try #require(
      descendants(in: fixture.host, as: NSTextField.self)
        .first { $0.stringValue == "Pinned chrome" }
    )
    let editor = try #require(descendants(in: fixture.host, as: ListAwareTextView.self).first)
    let writingSurface = try #require(
      descendants(in: fixture.host, as: AdaptiveOpaqueSurfaceView.self).first
    )
    let originalTitleFrame = title.convert(title.bounds, to: fixture.host)

    #expect(fixture.host.bounds.size == NSSize(width: 640, height: 430))
    #expect(writingSurface.convert(writingSurface.bounds, to: fixture.host) == fixture.host.bounds)
    #expect(writingSurface.isOpaque)
    #expect(writingSurface.layer?.backgroundColor?.alpha == 1)
    fixture.window.appearance = NSAppearance(named: .aqua)
    await settle(fixture.host)
    writingSurface.needsDisplay = true
    writingSurface.displayIfNeeded()
    let lightSurfaceColor = try #require(writingSurface.layer?.backgroundColor)
    fixture.window.appearance = NSAppearance(named: .darkAqua)
    await settle(fixture.host)
    writingSurface.needsDisplay = true
    writingSurface.displayIfNeeded()
    let darkSurfaceColor = try #require(writingSurface.layer?.backgroundColor)
    #expect(lightSurfaceColor.alpha == 1)
    #expect(darkSurfaceColor.alpha == 1)
    #expect(lightSurfaceColor != darkSurfaceColor)
    fixture.window.appearance = nil
    #expect(fixture.window.makeFirstResponder(title))
    await settle(fixture.host)
    #expect(title.convert(title.bounds, to: fixture.host) == originalTitleFrame)
    #expect(fixture.window.makeFirstResponder(editor))
    await settle(fixture.host)
    #expect(fixture.window.firstResponder === editor)
    #expect(title.convert(title.bounds, to: fixture.host) == originalTitleFrame)
  } catch {
    await fixture.close()
    throw error
  }
  await fixture.close()
}

@Test @MainActor func pinnedChromeKeepsNativeTabDestinationInsideNonemptyAncestors() async throws {
  let fixture = try await hostedPinnedPanel()
  do {
    let destination = try #require(
      descendants(in: fixture.host, as: FluidTabDestinationView.self).first
    )
    var ancestor: NSView? = destination
    while let current = ancestor {
      #expect(!current.bounds.isEmpty, "Native tab destination ancestry must remain nonempty")
      let destinationBounds = current.convert(destination.bounds, from: destination)
      #expect(
        current.bounds.intersects(destinationBounds),
        "Every native ancestor must contain part of the tab destination"
      )
      if current === fixture.host { break }
      ancestor = current.superview
    }
    #expect(ancestor === fixture.host, "Native tab destination must remain under the hosted panel")
  } catch {
    await fixture.close()
    throw error
  }
  await fixture.close()
}

@MainActor
private struct PinnedChromeFixture {
  let root: URL
  let window: NSWindow
  let host: NSHostingView<AnyView>
  let runtime: DictationRuntime

  func close() async {
    window.contentView = nil
    window.orderOut(nil)
    await runtime.shutdown()
    try? FileManager.default.removeItem(at: root)
  }
}

@MainActor
private func hostedPinnedPanel() async throws -> PinnedChromeFixture {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let note = Note(title: "Pinned chrome", body: "First body line\nSecond body line", folderID: nil)
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [])
  state.updatePreferences { $0.showFormattingBar = true }
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let rootView = AnyView(NotesPanel(
    dictationRuntime: runtime,
    isPinned: true,
    sizing: .container
  )
  .environmentObject(state)
  .frame(width: 640, height: 430))
  let host = NSHostingView(rootView: rootView)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settle(host)
  return PinnedChromeFixture(root: root, window: window, host: host, runtime: runtime)
}

@MainActor
private func descendants<T: NSView>(in view: NSView, as type: T.Type) -> [T] {
  var matches = view as? T == nil ? [] : [view as! T]
  for subview in view.subviews {
    matches.append(contentsOf: descendants(in: subview, as: type))
  }
  return matches
}

@MainActor
private func settle(_ view: NSView) async {
  for _ in 0..<5 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@MainActor
private func capture(_ view: NSView, at url: URL) throws {
  let image = try renderedImage(of: view)
  let data = try #require(image.representation(using: .png, properties: [:]))
  try data.write(to: url, options: .atomic)
}

@MainActor
private func renderedImage(of view: NSView) throws -> NSBitmapImageRep {
  view.displayIfNeeded()
  let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
  view.cacheDisplay(in: view.bounds, to: image)
  return image
}
