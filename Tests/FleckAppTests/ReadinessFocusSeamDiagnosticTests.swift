import AppKit
import SwiftUI
import Testing

@testable import FleckApp

@MainActor
private struct ReadinessFocusSeamDiagnostic: View {
  let variant: Int
  let initialRequest = SettingsSearchRequest(target: .dictationStatus)
  @State private var isPresented = false
  @State private var returnRequest: SettingsKeyboardFocusReturnRequest?
  @StateObject private var attachment = SettingsKeyboardFocusReturnAttachment()
  @FocusState private var nativeFocused: Bool

  private var trigger: some View {
    Button("Readiness seam") { isPresented = true }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("readiness-seam-trigger")
  }

  private var popover: some View {
    VStack {
      Text("Synthetic focus seam")
      Button("Synthetic action") {}
    }
    .padding()
    .onExitCommand {
      if variant == 2 {
        nativeFocused = true
      } else {
        attachment.publishReturnRequest(
          inputID: SettingsSearchInputModality.shared.inputID,
          to: $returnRequest
        )
      }
      print("SEAM-EXIT variant=\(variant) pending=\(returnRequest != nil) keyMatches=\(returnRequest?.window != nil && NSApp.keyWindow === returnRequest?.window)")
      isPresented = false
    }
    .onDisappear { print("SEAM-DISAPPEAR variant=\(variant)") }
  }

  private var anchoredTrigger: some View {
    trigger
      .popover(isPresented: $isPresented) { popover }
      .settingsSearchAnchor(.dictationStatus, request: initialRequest) { attachment }
      .environment(\.settingsKeyboardFocusReturnRequest, $returnRequest)
  }

  private var publiclyNamedTrigger: some View {
    anchoredTrigger
      .accessibilityLabel("Dictation readiness")
      .accessibilityValue("Needs attention")
      .accessibilityHint("Show dictation readiness and recovery actions.")
      .accessibilityIdentifier("readiness-seam-trigger")
  }

  private var correctedTrigger: some View {
    trigger
      .popover(isPresented: $isPresented) { popover }
      .accessibilityLabel("Dictation readiness")
      .accessibilityValue("Needs attention")
      .accessibilityHint("Show dictation readiness and recovery actions.")
      .settingsSearchAnchor(
        .dictationStatus, request: initialRequest,
        nativeControlIdentifier: "readiness-seam-trigger"
      ) { attachment }
      .environment(\.settingsKeyboardFocusReturnRequest, $returnRequest)
  }

  private var nativeAnchorBeforePopover: some View {
    trigger
      .accessibilityLabel("Dictation readiness")
      .accessibilityValue("Needs attention")
      .accessibilityHint("Show dictation readiness and recovery actions.")
      .settingsSearchAnchor(
        .dictationStatus, request: initialRequest,
        nativeControlIdentifier: "readiness-seam-trigger"
      ) { attachment }
      .environment(\.settingsKeyboardFocusReturnRequest, $returnRequest)
      .popover(isPresented: $isPresented) { popover }
  }

  var body: some View {
    VStack {
      if variant == 0 {
        anchoredTrigger
      } else if variant == 1 {
        trigger
          .settingsSearchAnchor(.dictationStatus, request: initialRequest) { attachment }
          .popover(isPresented: $isPresented) { popover }
          .environment(\.settingsKeyboardFocusReturnRequest, $returnRequest)
      } else if variant == 2 || variant == 6 {
        trigger
          .background(SettingsSearchProbe(identifier: "native-seam-attachment", returnAttachment: attachment))
          .focused($nativeFocused)
          .popover(isPresented: $isPresented) { popover }
          .background {
            if nativeFocused {
              SettingsSearchProbe(identifier: "settings-keyboard-focus-cue-dictation-status")
            }
          }
          .task { nativeFocused = true }
      } else if variant == 3 {
        publiclyNamedTrigger
      } else if variant == 4 {
        HStack {
          Text("Dictation section")
          publiclyNamedTrigger
        }
        .settingsSearchAnchor(.section(.dictation), request: nil)
      } else if variant == 5 {
        HStack {
          Text("Dictation section")
          correctedTrigger
        }
        .settingsSearchAnchor(.section(.dictation), request: nil)
      } else {
        HStack {
          Text("Dictation section")
          nativeAnchorBeforePopover
        }
        .settingsSearchAnchor(.section(.dictation), request: nil)
      }
    }
    .padding(40)
    .onChange(of: nativeFocused) { oldValue, newValue in
      print("SEAM-DIRECT-FOCUS variant=\(variant) old=\(oldValue) new=\(newValue)")
    }
    .task(id: returnRequest?.id) { @MainActor in
      guard variant == 6, let request = returnRequest else { return }
      let generation = attachment.generation
      await Task.yield()
      guard !Task.isCancelled, returnRequest?.id == request.id else { return }
      returnRequest = nil
      guard NSApp.isActive, let window = request.window,
        attachment.matches(request, generation: generation, inputID: SettingsSearchInputModality.shared.inputID),
        NSApp.keyWindow === window, window.isKeyWindow, window.isVisible
      else {
        print("SEAM-DELIVERY variant=6 accepted=false focused=\(nativeFocused)")
        return
      }
      print("SEAM-DELIVERY variant=6 accepted=true focusedBefore=\(nativeFocused) cancelled=\(Task.isCancelled)")
      SettingsSearchInputModality.shared.record(isKeyboardInput: true, windowNumber: window.windowNumber)
      nativeFocused = true
      print("SEAM-DELIVERY variant=6 focusedAfter=\(nativeFocused) cancelled=\(Task.isCancelled)")
      await Task.yield()
      print("SEAM-DELIVERY variant=6 afterSuspension focused=\(nativeFocused) cancelled=\(Task.isCancelled)")
    }
  }
}

@Test @MainActor
func readinessFocusSeamDiagnostic() async throws {
  let application = NSApplication.shared
  let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
  let previous = application.accessibilityAttributeValue(attribute)
  application.accessibilitySetValue(true, forAttribute: attribute)
  defer { application.accessibilitySetValue(previous, forAttribute: attribute) }

  func elements(_ object: NSObject) -> [NSObject] {
    let selector = NSSelectorFromString("accessibilityChildren")
    let children = object.responds(to: selector)
      ? object.perform(selector)?.takeUnretainedValue() as? [NSObject] : nil
    return [object] + (children ?? []).flatMap(elements)
  }
  func identifier(_ object: NSObject?) -> String {
    let selector = NSSelectorFromString("accessibilityIdentifier")
    guard let object, object.responds(to: selector) else { return "none" }
    return object.perform(selector)?.takeUnretainedValue() as? String ?? "none"
  }
  func focused(_ window: NSWindow) -> NSObject? {
    let selector = NSSelectorFromString("accessibilityFocusedUIElement")
    return window.perform(selector)?.takeUnretainedValue() as? NSObject
  }
  func hasCue(_ view: NSView) -> Bool {
    view.accessibilityIdentifier() == "settings-keyboard-focus-cue-dictation-status"
      || view.subviews.contains(where: hasCue)
  }
  func probeDetails(_ view: NSView) -> [String] {
    let current = view is SettingsSearchProbe.ProbeView
      ? ["id=\(view.accessibilityIdentifier() ?? "nil") frame=\(view.frame) hidden=\(view.isHiddenOrHasHiddenAncestor) window=\(view.window != nil)"] : []
    return current + view.subviews.flatMap(probeDetails)
  }
  func settle(_ host: NSView) async throws {
    for _ in 0..<20 {
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  func key(_ code: UInt16, _ characters: String, window: NSWindow) throws {
    let event = try #require(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: characters,
      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
    ))
    window.sendEvent(event)
  }

  var currentVariant = -1
  let modality = SettingsSearchInputModality.shared
  let previousObservation = modality.readinessReturnObservation
  modality.readinessReturnObservation = { _, record in
    print("SEAM-STATE variant=\(currentVariant) \(record)")
  }
  defer { modality.readinessReturnObservation = previousObservation }
  for variant in 0...7 {
    currentVariant = variant
    let host = NSHostingView(rootView: ReadinessFocusSeamDiagnostic(variant: variant))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
      styleMask: [.titled, .closable], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.title = "Synthetic readiness focus seam"
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    defer {
      window.makeFirstResponder(nil)
      window.orderOut(nil)
      window.contentView = nil
      window.close()
    }
    SettingsSearchInputModality.shared.record(
      isKeyboardInput: true, windowNumber: window.windowNumber
    )
    try await settle(host)
    let beforeWindows = Set(application.windows.map(ObjectIdentifier.init))
    let beforeCue = hasCue(host)
    print("SEAM variant=\(variant) stage=initial fullKeyboard=\(application.isFullKeyboardAccessEnabled) focus=\(identifier(focused(window))) cue=\(beforeCue)")
    print("SEAM-PROBES variant=\(variant) stage=initial \(probeDetails(host))")
    try key(49, " ", window: window)
    try await settle(host)
    let popoverWindow = application.windows.first {
      !beforeWindows.contains(ObjectIdentifier($0)) && $0.isVisible
    }
    print("SEAM variant=\(variant) stage=open opened=\(popoverWindow != nil)")
    if let popoverWindow {
      try key(53, "\u{1b}", window: popoverWindow)
      try await settle(host)
      let afterCue = hasCue(host)
      print("SEAM variant=\(variant) stage=returned focus=\(identifier(focused(window))) cue=\(afterCue) closed=\(!popoverWindow.isVisible)")
      print("SEAM-PROBES variant=\(variant) stage=returned \(probeDetails(host))")
      if let path = ProcessInfo.processInfo.environment["FLECK_SETTINGS_WINDOW_CAPTURE_DIR"] {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        let png = try #require(image.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("seam-\(variant)-returned.png"))
      }
      popoverWindow.orderOut(nil)
    }
  }
}
