import AppKit
import Foundation
import ScreenCaptureKit
import SwiftUI
import Testing

@testable import FleckApp
import FleckCore

@MainActor
private func noteTabImageContainsInk(
  _ image: NSBitmapImageRep,
  matching targetColor: NSColor,
  within rect: CGRect,
  viewSize: CGSize,
  viewIsFlipped: Bool = false
) -> Bool {
  guard viewSize.width > 0, viewSize.height > 0,
    let target = targetColor.usingColorSpace(.sRGB)
  else { return false }
  let scaleX = CGFloat(image.pixelsWide) / viewSize.width
  let scaleY = CGFloat(image.pixelsHigh) / viewSize.height
  let xStart = max(0, Int(floor(rect.minX * scaleX)))
  let xEnd = min(image.pixelsWide, Int(ceil(rect.maxX * scaleX)))
  let yStart = max(0, Int(floor(
    (viewIsFlipped ? rect.minY : viewSize.height - rect.maxY) * scaleY
  )))
  let yEnd = min(image.pixelsHigh, Int(ceil(
    (viewIsFlipped ? rect.maxY : viewSize.height - rect.minY) * scaleY
  )))
  return (yStart..<yEnd).contains { y in
    (xStart..<xEnd).contains { x in
      guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
      return color.alphaComponent > 0.5
        && max(
          abs(color.redComponent - target.redComponent),
          max(
            abs(color.greenComponent - target.greenComponent),
            abs(color.blueComponent - target.blueComponent)
          )
        ) < 0.08
    }
  }
}

@Test func selectedNoteTabLabelInkContrastsWithCapsuleFillInLightAndDark() throws {
  let cases: [(NSColor, NSColor, NSColor)] = [
    (
      .white,
      try #require(NSColor(hex: "#F2F3F5")),
      .black
    ),
    (
      try #require(NSColor(hex: "#1C1C1E")),
      try #require(NSColor(hex: "#282A2E")),
      .white
    ),
  ]

  for (surfaceColor, tabColor, expectedInk) in cases {
    let capsuleFill = NoteTabInk.selectedCapsuleFill(
      tabColor: tabColor,
      surfaceColor: surfaceColor
    )
    let ink = NoteTabInk.selectedLabelColor(tabColor: tabColor, surfaceColor: surfaceColor)

    #expect(capsuleFill.alphaComponent == 1)
    #expect(FleckColorContrast.contrastRatio(ink, against: capsuleFill) >= 4.5)
    #expect(ink.usingColorSpace(.sRGB)?.isEqual(expectedInk.usingColorSpace(.sRGB)) == true)
  }
}

@Test func selectedNoteTabUsesContrastSafeInkAgainstItsCapsuleFill() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )
  let selectedLabelInk = try #require(
    source.components(separatedBy: "private func selectedTabLabelInk").last?
      .components(separatedBy: "@ViewBuilder").first
  )

  #expect(tabStrip.contains("selectedTabLabelInk(for: note)"))
  #expect(tabStrip.contains("selectedTabCapsuleFill(for: $0)"))
  #expect(selectedLabelInk.contains("NoteTabInk.selectedLabelColor("))
  #expect(!tabStrip.contains("note.id == appState.workspace.selectedNoteID || colorScheme == .dark"))
}

@Test func menuPanelUsesOneNativeGlassSurfaceWithoutPerimeterEffect() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let panelStart = try #require(source.range(of: "  struct NotesPanel: View"))
  let panel = source[panelStart.lowerBound...]
  let bodyStart = try #require(panel.range(of: "    var body: some View {\n      ZStack {"))
  let bodyEnd = try #require(
    panel.range(of: "\n    private var pinnedNavigationChrome", range: bodyStart.upperBound..<panel.endIndex)
  )
  let body = panel[bodyStart.lowerBound..<bodyEnd.lowerBound]
  let formattingStart = try #require(source.range(of: "  private struct FormattingBarSurface: ViewModifier"))
  let formattingEnd = try #require(
    source.range(of: "  private struct PinnedWritingSurface: NSViewRepresentable", range: formattingStart.upperBound..<source.endIndex)
  )
  let formatting = source[formattingStart.lowerBound..<formattingEnd.lowerBound]

  #expect(body.contains("switch chromeMaterialPolicy"))
  #expect(body.contains(".fill(.regularMaterial)"))
  #expect(body.contains("appState.preferences.panelOpacity"))
  #expect(body.contains("case .opaque:"))
  #expect(!body.contains(".glassEffect("))
  #expect(formatting.contains("let isPinned: Bool"))
  #expect(formatting.contains("if isPinned"))
  #expect(formatting.contains("content.glassEffect("))
  #expect(!source.contains("MenuNavigationChromeSurface"))
}

@Test func glassChromeUsesOpaqueSurfaceForAccessibilityFallbacks() {
  #expect(
    FleckChromeMaterialPolicy.resolve(
      appearance: .glass,
      supportsLiquidGlass: true,
      reduceTransparency: false,
      increasedContrast: false
    ) == .liquidGlass
  )
  #expect(
    FleckChromeMaterialPolicy.resolve(
      appearance: .glass,
      supportsLiquidGlass: true,
      reduceTransparency: true,
      increasedContrast: false
    ) == .opaque
  )
  #expect(
    FleckChromeMaterialPolicy.resolve(
      appearance: .glass,
      supportsLiquidGlass: true,
      reduceTransparency: false,
      increasedContrast: true
    ) == .opaque
  )
}

@Test @MainActor
func selectedNoteTabTitleRendersAboveItsCapsuleInLightAndDark() async throws {
  let application = NSApplication.shared
  let previousApplicationAppearance = application.appearance
  defer { application.appearance = previousApplicationAppearance }
  let customTabColor = try #require(NSColor(hex: "#7030A0"))

  for (dark, windowAppearance, surfaceColor) in [
    (false, NSAppearance.Name.aqua, NSColor.white),
    (true, .darkAqua, try #require(NSColor(hex: "#1C1C1E"))),
  ] {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("selected-note-tab-ink-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let selected = Note(title: "Selected", tabColorHex: "#7030A0")
    let other = Note(title: "Other")
    let state = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _, _ in .committed }
    )
    await state.waitUntilInitialLoad()
    state.workspace = Workspace(notes: [selected, other], selectedNoteID: selected.id, folders: [])
    state.updatePreferences {
      $0.colorTheme = .capy
      $0.theme = dark ? .dark : .light
      $0.chromeAppearance = .glass
      $0.panelOpacity = 0.55
    }
    let theme = state.themeSnapshot
    let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
    let panel = NotesPanel(dictationRuntime: runtime, sizing: .container)
    let host = NSHostingView(rootView: AnyView(FleckThemeTestRoot(state: state) { panel }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: windowAppearance)
    window.backgroundColor = surfaceColor
    window.isOpaque = false
    window.contentView = host
    window.makeKeyAndOrderFront(nil)

    for _ in 0..<40 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }

    func findDestination(in view: NSView) -> FluidTabDestinationView? {
      if let destination = view as? FluidTabDestinationView { return destination }
      return view.subviews.lazy.compactMap { findDestination(in: $0) }.first
    }
    func findSource(_ noteID: UUID, in view: NSView) -> ReorderSourceHostingView? {
      if let source = view as? ReorderSourceHostingView, source.noteID == noteID { return source }
      return view.subviews.lazy.compactMap { findSource(noteID, in: $0) }.first
    }

    let tabHost = try #require(findDestination(in: host))
    let source = try #require(findSource(selected.id, in: tabHost))
    let expectedInk = NoteTabInk.selectedLabelColor(
      tabColor: customTabColor,
      surfaceColor: theme.nsColor(.window)
    )
    let expectedFill = NoteTabInk.selectedCapsuleFill(
      tabColor: customTabColor,
      surfaceColor: theme.nsColor(.window)
    )
    #expect(FleckColorContrast.contrastRatio(expectedInk, against: expectedFill) >= 4.5)

    let sourceImage = try #require(source.bitmapImageRepForCachingDisplay(in: source.bounds))
    source.cacheDisplay(in: source.bounds, to: sourceImage)
    #expect(noteTabImageContainsInk(
      sourceImage,
      matching: expectedInk,
      within: source.labelCapsuleRect.insetBy(dx: 7, dy: 5),
      viewSize: source.bounds.size,
      viewIsFlipped: source.isFlipped
    ))

    #expect(tabHost.selectionHighlightLayer.zPosition < 0)
    if CGPreflightScreenCaptureAccess() {
      let shareableContent = try await SCShareableContent.excludingDesktopWindows(
        true,
        onScreenWindowsOnly: true
      )
      let shareableWindow = try #require(
        shareableContent.windows.first { $0.windowID == CGWindowID(window.windowNumber) }
      )
      let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
      let configuration = SCStreamConfiguration()
      configuration.width = Int(window.frame.width * window.backingScaleFactor)
      configuration.height = Int(window.frame.height * window.backingScaleFactor)
      configuration.showsCursor = false
      let windowImage = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: configuration
      )
      let image = NSBitmapImageRep(cgImage: windowImage)
      let textRect = source.convert(source.labelCapsuleRect.insetBy(dx: 7, dy: 5), to: host)
      #expect(noteTabImageContainsInk(
        image,
        matching: expectedInk,
        within: textRect,
        viewSize: host.bounds.size,
        viewIsFlipped: host.isFlipped
      ), "The selected title must render over its capsule in \(windowAppearance.rawValue)")
      #expect(noteTabImageContainsInk(
        image,
        matching: expectedFill,
        within: source.convert(source.labelCapsuleRect.insetBy(dx: 1, dy: 1), to: host),
        viewSize: host.bounds.size,
        viewIsFlipped: host.isFlipped
      ), "The selected capsule must remain visible in \(windowAppearance.rawValue)")
    }

    window.contentView = nil
    window.orderOut(nil)
    await runtime.shutdown()
  }
}
