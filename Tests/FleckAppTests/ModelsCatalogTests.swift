#if os(macOS)
  import AppKit
  import Foundation
  import ObjectiveC.runtime
  import SwiftUI
  import Testing

  @testable import FleckApp

  @MainActor
  private final class ModelLibraryTestInstaller: AdmittedModelInstalling {
    let snapshot: AdmittedModelInstallationSnapshot
    let updates: AsyncStream<AdmittedModelInstallationSnapshot>
    private(set) var actions: [AdmittedModelSettingsAction] = []

    init(
      descriptor: AdmittedModelDescriptor?,
      phase: AdmittedModelInstallPhase = .notInstalled,
      errorMessage: String? = nil
    ) {
      let initialPhase: AdmittedModelInstallPhase
      if descriptor == nil, let errorMessage {
        initialPhase = .failed(message: errorMessage)
      } else if descriptor == nil {
        initialPhase = .builtIn
      } else {
        initialPhase = phase
      }
      let initial = AdmittedModelInstallationSnapshot(
        recommendation: descriptor.map { .recommended($0) } ?? .builtIn,
        phase: initialPhase,
        lastError: errorMessage
      )
      snapshot = initial
      updates = AsyncStream { continuation in
        continuation.yield(initial)
        continuation.finish()
      }
    }

    func refresh() async {}
    func install() async { actions.append(.install) }
    func cancel() { actions.append(.cancel) }
    func repair() async { actions.append(.repair) }
    func update() async { actions.append(.update) }
    func remove() async { actions.append(.remove) }
  }

private func modelLibraryDescriptor(
  role: AdmittedModelRole,
  modelID: String,
  revision: String = "fixture-revision",
  license: String = "CC-BY-4.0"
) throws -> AdmittedModelDescriptor {
  let downloadBytes: Int64 = role == .asr ? 464_413_247 : 771_863_021
  return try AdmittedModelDescriptor(validating: RawAdmittedModelDescriptor(
      role: role,
      modelID: modelID,
      revision: revision,
      runtimeABI: "fixture-runtime",
      conversion: "fixture conversion",
      quantization: "fixture quantization",
      license: license,
      notices: "Fixture-only attribution notice.",
      source: URL(string: "https://huggingface.co/\(modelID)")!,
      files: [
      .init(
        path: "model.bin",
        byteCount: downloadBytes,
        sha256: TestFixtures.tinySHA256
      )
    ],
    downloadBytes: downloadBytes,
    installedBytes: downloadBytes * 2,
      languages: ["en"],
      architectures: ["arm64"]
    ))
  }

  @MainActor
  private func modelLibraryViewModel(
    _ descriptor: AdmittedModelDescriptor?,
    role: AdmittedModelRole,
    phase: AdmittedModelInstallPhase = .notInstalled,
    errorMessage: String? = nil
  ) -> AdmittedModelSettingsViewModel {
    makeModelLibraryViewModel(
      descriptor,
      role: role,
      phase: phase,
      errorMessage: errorMessage
    ).viewModel
  }

  @MainActor
  private func makeModelLibraryViewModel(
    _ descriptor: AdmittedModelDescriptor?,
    role: AdmittedModelRole,
    phase: AdmittedModelInstallPhase = .notInstalled,
    errorMessage: String? = nil
  ) -> (viewModel: AdmittedModelSettingsViewModel, installer: ModelLibraryTestInstaller) {
    let installer = ModelLibraryTestInstaller(
      descriptor: descriptor,
      phase: phase,
      errorMessage: errorMessage
    )
    let viewModel = AdmittedModelSettingsViewModel(
      installer: installer,
      context: role == .asr ? .dictation : .cleanup(fallbackLabel: "Fixture fallback")
    )
    return (viewModel, installer)
  }

  @MainActor
  func fixtureModelViewModels() throws -> (
    speech: AdmittedModelSettingsViewModel,
    cleanup: AdmittedModelSettingsViewModel
  ) {
    let speech = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID,
      revision: "ee09c569f73759e6d44c9bd16766f477b2b36d39"
    )
    let cleanup = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID,
      revision: "15fed4eafb456c6fcb2a1165f19ac609670ed14b",
      license: "Gemma Terms of Use"
    )
    return (
      modelLibraryViewModel(speech, role: .asr),
      modelLibraryViewModel(cleanup, role: .cleanup)
    )
  }

  @MainActor
  private func fixtureModelEntries() throws -> [ModelLibraryEntry] {
    let viewModels = try fixtureModelViewModels()
    return ModelLibraryCatalog.entries(
      speechViewModel: viewModels.speech,
      cleanupViewModel: viewModels.cleanup
    )
  }

  @MainActor
  private final class ModelBrowserSelection: ObservableObject {
    @Published var selectedModelID: String?

    init(selectedModelID: String? = nil) {
      self.selectedModelID = selectedModelID
    }

    var binding: Binding<String?> {
      Binding(
        get: { self.selectedModelID },
        set: { self.selectedModelID = $0 }
      )
    }
  }

  private struct ModelSearchEscapeEvent: @unchecked Sendable {
    let event: NSEvent
  }

  @MainActor
  private struct ModelBrowserFixture: View {
    let speechViewModel: AdmittedModelSettingsViewModel
    let cleanupViewModel: AdmittedModelSettingsViewModel
    let theme: FleckThemeSnapshot
    let size: CGSize
    let dynamicTypeSize: DynamicTypeSize
    @State private var pinnedModelKeys: Set<String> = []
    @State private var modelTypeFilter: ModelLibraryTypeFilter = .all
    @ObservedObject private var selection: ModelBrowserSelection
    @State private var searchQuery = ""

    init(
      speechViewModel: AdmittedModelSettingsViewModel,
      cleanupViewModel: AdmittedModelSettingsViewModel,
      theme: FleckThemeSnapshot,
      size: CGSize,
      dynamicTypeSize: DynamicTypeSize = .medium,
      selectedModelID: String? = nil,
      selection: ModelBrowserSelection? = nil
    ) {
      self.speechViewModel = speechViewModel
      self.cleanupViewModel = cleanupViewModel
      self.theme = theme
      self.size = size
      self.dynamicTypeSize = dynamicTypeSize
      _selection = ObservedObject(
        wrappedValue: selection
          ?? ModelBrowserSelection(
            selectedModelID: selectedModelID
          )
      )
    }

    var body: some View {
      ModelsBrowserView(
        speechViewModel: speechViewModel,
        cleanupViewModel: cleanupViewModel,
        pinnedModelKeys: $pinnedModelKeys,
        selectedModelID: selection.binding,
        searchQuery: $searchQuery,
        typeFilter: $modelTypeFilter
      )
      .environment(\.fleckThemeSnapshot, theme)
      .environment(\.colorScheme, theme.colorScheme)
      .environment(\.dynamicTypeSize, dynamicTypeSize)
      .tint(theme.color(.accent))
      .frame(width: size.width, height: size.height)
    }
  }

  @MainActor
  private func enableModelBrowserAccessibility() -> Any? {
    let application = NSApplication.shared
    let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    let previousValue = application.accessibilityAttributeValue(attribute)
    application.accessibilitySetValue(true, forAttribute: attribute)
    return previousValue
  }

  @MainActor
  private func restoreModelBrowserAccessibility(_ value: Any?) {
    NSApplication.shared.accessibilitySetValue(
      value,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
  }

  @MainActor
  private func modelAccessibilityElements(in value: Any?, identifier: String) -> [NSObject] {
    guard let element = value as? NSObject else { return [] }
    let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
    let matchesIdentifier = element.responds(to: identifierSelector)
      && element.perform(identifierSelector)?.takeUnretainedValue() as? String == identifier
    var matches = matchesIdentifier ? [element] : []
    let childrenSelector = NSSelectorFromString("accessibilityChildren")
    let rawChildren = element.responds(to: childrenSelector)
      ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
    for child in NSAccessibility.unignoredChildren(from: rawChildren ?? []) {
      matches.append(contentsOf: modelAccessibilityElements(in: child, identifier: identifier))
    }
    return matches
  }

  @MainActor
  private func modelAccessibilityElements(
    in windows: [NSWindow],
    identifier: String
  ) -> [NSObject] {
    windows.flatMap { modelAccessibilityElements(in: $0, identifier: identifier) }
  }

  @MainActor
  private func modelAccessibilityLabel(_ element: NSObject) -> String? {
    let selector = NSSelectorFromString("accessibilityLabel")
    guard element.responds(to: selector) else { return nil }
    return element.perform(selector)?.takeUnretainedValue() as? String
  }

  @MainActor
  private func modelAccessibilityValue(_ element: NSObject) -> String? {
    let selector = NSSelectorFromString("accessibilityValue")
    guard element.responds(to: selector) else { return nil }
    return element.perform(selector)?.takeUnretainedValue() as? String
  }

  @MainActor
  private func modelAccessibilityText(_ element: NSObject) -> String? {
    modelAccessibilityValue(element) ?? modelAccessibilityLabel(element)
  }

  @MainActor
  private func modelAccessibilityFrame(_ element: NSObject) -> CGRect? {
    (element.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue
  }

  @MainActor
  private func modelLibraryRowOrder(in host: NSView) -> [String] {
    let identifiers = [
      ModelLibraryEntry.pinKey(for: .asr, modelID: ModelLibraryCatalog.parakeetModelID),
      ModelLibraryEntry.pinKey(for: .cleanup, modelID: ModelLibraryCatalog.gemmaModelID),
    ]
    let rows = identifiers.compactMap { identifier -> (String, CGRect)? in
      guard let element = modelAccessibilityElements(
        in: host,
        identifier: "models-row-\(identifier)"
      ).first,
      let frame = modelAccessibilityFrame(element) else {
        return nil
      }
      return (identifier, frame)
    }
    return rows.sorted { $0.1.midY > $1.1.midY }.map(\.0)
  }

  @MainActor
  private func sendModelMouseClick(at screenPoint: NSPoint, to window: NSWindow) throws {
    let windowPoint = window.convertPoint(fromScreen: screenPoint)
    let events: [NSEvent.EventType] = [.leftMouseDown, .leftMouseUp]
    for (eventNumber, type) in events.enumerated() {
      let event = try #require(NSEvent.mouseEvent(
        with: type,
        location: windowPoint,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime + Double(eventNumber) * 0.01,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: type == .leftMouseUp ? 0 : 1
      ))
      NSApp.sendEvent(event)
    }
  }

  @MainActor
  private func sendModelTrackedMouseClick(at screenPoint: NSPoint, to window: NSWindow) throws {
    let windowPoint = window.convertPoint(fromScreen: screenPoint)
    let timestamp = ProcessInfo.processInfo.systemUptime
    let mouseUp = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: windowPoint,
        modifierFlags: [],
        timestamp: timestamp + 0.01,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 0
      )
    )
    NSApp.postEvent(mouseUp, atStart: true)
    let mouseDown = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: windowPoint,
        modifierFlags: [],
        timestamp: timestamp,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
      )
    )
    NSApp.sendEvent(mouseDown)
  }

  @MainActor
  private func modelSearchField(in view: NSView?) -> NSTextField? {
    guard let view else { return nil }
    if let textField = view as? NSTextField,
      textField.accessibilityIdentifier() == "models-search-field"
        || textField.placeholderString == "Search models"
    {
      return textField
    }
    for subview in view.subviews {
      if let searchField = modelSearchField(in: subview) {
        return searchField
      }
    }
    return nil
  }

  @MainActor
  private func modelTypeFilterControl(in view: NSView?) -> NSSegmentedControl? {
    guard let view else { return nil }
    if let control = view as? NSSegmentedControl,
      control.segmentCount == 3,
      control.label(forSegment: 0) == "All",
      control.label(forSegment: 1) == "Voice",
      control.label(forSegment: 2) == "Cleanup"
    {
      return control
    }
    for subview in view.subviews {
      if let control = modelTypeFilterControl(in: subview) {
        return control
      }
    }
    return nil
  }

  @MainActor
  private func sendModelKey(
    _ keyCode: UInt16,
    characters: String,
    modifierFlags: NSEvent.ModifierFlags = [],
    to window: NSWindow
  ) throws {
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
      )
    )
    NSApp.sendEvent(event)
    let keyUp = try #require(
      NSEvent.keyEvent(
        with: .keyUp,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
        windowNumber: window.windowNumber,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
      )
    )
    NSApp.sendEvent(keyUp)
  }

  @MainActor
  private func modelEscapePassesNextLocalMonitor(in window: NSWindow) throws -> Bool {
    var didReceiveEscape = false
    guard
      let monitor = NSEvent.addLocalMonitorForEvents(
        matching: .keyDown,
        handler: { event in
          let monitoredEvent = ModelSearchEscapeEvent(event: event)
          MainActor.assumeIsolated {
            if monitoredEvent.event.window === window, monitoredEvent.event.keyCode == 53 {
              didReceiveEscape = true
            }
          }
          return event
        })
    else {
      return false
    }
    defer { NSEvent.removeMonitor(monitor) }
    try sendModelKey(53, characters: "\u{1b}", to: window)
    return didReceiveEscape
  }

  @MainActor
  private func typeModelText(_ text: String, in window: NSWindow) throws {
    let keyCodes: [Character: UInt16] = [
      "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
      "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
      "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1,
      "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
      " ": 49,
    ]
    for character in text {
      try sendModelKey(
        try #require(keyCodes[character]),
        characters: String(character),
        to: window
      )
    }
  }

  @MainActor
  private func settleModelBrowser(_ host: NSView) async throws {
    try await Task.sleep(for: .milliseconds(120))
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
  }

  @MainActor
  private func clickModelElement(_ element: NSObject, in window: NSWindow) throws {
    let frame = try #require(modelAccessibilityFrame(element))
    try sendModelMouseClick(at: NSPoint(x: frame.midX, y: frame.midY), to: window)
  }

  @MainActor
  private func clickModelView(_ view: NSView, in window: NSWindow) throws {
    let windowPoint = view.convert(
      NSPoint(x: view.bounds.midX, y: view.bounds.midY),
      to: nil
    )
    try sendModelTrackedMouseClick(at: window.convertPoint(toScreen: windowPoint), to: window)
  }

  @MainActor
  private func performModelAccessibilityPress(_ element: NSObject) -> Bool {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    guard let method = class_getInstanceMethod(type(of: element), selector) else { return false }
    guard let typeEncoding = method_getTypeEncoding(method) else { return false }
    let returnType = String(cString: typeEncoding).first
    guard returnType == "B" || returnType == "c" else { return false }
    let press = unsafeBitCast(
      method_getImplementation(method),
      to: (@convention(c) (AnyObject, Selector) -> Bool).self
    )
    if press(element, selector) { return true }
    if let cell = element as? NSCell {
      cell.performClick(nil)
      return true
    }
    return false
  }

  @MainActor
  private func captureModelFixture<Content: View>(
    _ content: Content,
    name: String,
    size: CGSize
  ) throws -> NSHostingView<Content> {
    let host = NSHostingView(rootView: content)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    for _ in 0..<5 { host.layoutSubtreeIfNeeded() }
    try writeModelFixture(name, in: host)
    return host
  }

  @MainActor
  private func makeModelFixtureWindow(contentView: NSView) -> NSWindow {
    let window = NSWindow(
      contentRect: contentView.frame,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = contentView
    window.makeKeyAndOrderFront(nil)
    return window
  }

  @MainActor
  private func writeModelFixture(_ name: String, in host: NSView) throws {
    let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: imageRep)
    let image = try #require(imageRep.representation(using: .png, properties: [:]))
    #expect(!image.isEmpty)

    if let path = ProcessInfo.processInfo.environment[
      "FLECK_MODEL_LIBRARY_VISUAL_CAPTURE_DIRECTORY"
    ] {
      let directory = URL(fileURLWithPath: path, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try image.write(to: directory.appendingPathComponent("\(name).png"))
    }
  }

  @Test @MainActor
  func builtInOnlyBuildHasNoOptionalModelsOrProviders() {
    let entries = ModelLibraryCatalog.entries(
      speechViewModel: modelLibraryViewModel(nil, role: .asr),
      cleanupViewModel: modelLibraryViewModel(nil, role: .cleanup)
    )

    #expect(entries.isEmpty)
    #expect(ModelLibraryCatalog.providers(in: entries).isEmpty)
  }

  @Test @MainActor
  func catalogFiltersOnlyTheExpectedAdmittedRoleAndModelIdentities() throws {
    let parakeet = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let gemma = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID,
      license: "Gemma Terms of Use"
    )
    let unapproved = try modelLibraryDescriptor(role: .asr, modelID: "fixture/unapproved")
    let wrongRole = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: ModelLibraryCatalog.parakeetModelID
    )

    let entries = ModelLibraryCatalog.entries(
      speechViewModel: modelLibraryViewModel(wrongRole, role: .asr),
      cleanupViewModel: modelLibraryViewModel(unapproved, role: .cleanup)
    )
    #expect(entries.isEmpty)

    let matchingEntries = ModelLibraryCatalog.entries(
      speechViewModel: modelLibraryViewModel(parakeet, role: .asr),
      cleanupViewModel: modelLibraryViewModel(gemma, role: .cleanup)
    )
    #expect(matchingEntries.map(\.id) == [
      ModelLibraryEntry.pinKey(for: .asr, modelID: ModelLibraryCatalog.parakeetModelID),
      ModelLibraryEntry.pinKey(for: .cleanup, modelID: ModelLibraryCatalog.gemmaModelID),
    ])
    #expect(matchingEntries.map(\.provider) == [.nvidia, .google])
    #expect(ModelLibraryCatalog.providers(in: matchingEntries) == [.google, .nvidia])
    #expect(matchingEntries.map(\.modelCardURL.absoluteString) == [
      "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2",
      "https://huggingface.co/google/gemma-3-1b-it",
    ])
    #expect(matchingEntries.map(\.revisionURL.absoluteString) == [
      "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/tree/fixture-revision",
      "https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit/tree/fixture-revision",
    ])
  }

  @Test @MainActor
  func filtersIntersectSearchProviderAndTypeAndKeepPinsFirst() throws {
    let entries = try fixtureModelEntries()
    let speech = try #require(entries.first { $0.descriptor.role == .asr })
    let cleanup = try #require(entries.first { $0.descriptor.role == .cleanup })

    #expect(ModelLibraryCatalog.filtered(
      entries,
      searchQuery: "fluidinference",
      provider: "all",
      type: .all,
      pins: [],
      ascending: true
    ).map(\.id) == [speech.id])
    #expect(ModelLibraryCatalog.filtered(
      entries,
      searchQuery: "",
      provider: "Google",
      type: .voice,
      pins: [],
      ascending: true
    ).isEmpty)
    #expect(ModelLibraryCatalog.filtered(
      entries,
      searchQuery: "cleanup",
      provider: "Google",
      type: .cleanup,
      pins: [],
      ascending: true
    ).map(\.id) == [cleanup.id])

    let pinnedDescending = ModelLibraryCatalog.filtered(
      entries,
      searchQuery: "",
      provider: "all",
      type: .all,
      pins: [cleanup.id],
      ascending: false
    )
    #expect(pinnedDescending.map(\.id) == [cleanup.id, speech.id])
  }

  @Test @MainActor
  func modelPinsUseStableRoleAndModelIdentityAndRespectTermsGate() throws {
    let modelID = ModelLibraryCatalog.gemmaModelID
    let gemmaPin = ModelLibraryEntry.pinKey(for: .cleanup, modelID: modelID)
    let gemma = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: modelID,
      license: "Apache-2.0"
    )
    let parakeet = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let gemmaTermsDescriptor = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: "fixture/custom-cleanup",
      license: "Gemma Terms of Use"
    )

    #expect(gemmaPin == "cleanup:\(modelID)")
    #expect(gemmaPin != ModelLibraryEntry.pinKey(for: .asr, modelID: modelID))
    #expect(ModelLibraryCatalog.requiresTermsReview(
      for: .install,
      descriptor: gemma
    ))
    #expect(ModelLibraryCatalog.requiresTermsReview(
      for: .update,
      descriptor: gemma
    ))
    #expect(ModelLibraryCatalog.requiresTermsReview(
      for: .repair,
      descriptor: gemma
    ))
    #expect(!ModelLibraryCatalog.requiresTermsReview(
      for: .install,
      descriptor: parakeet
    ))
    #expect(ModelLibraryCatalog.requiresTermsReview(
      for: .install,
      descriptor: gemmaTermsDescriptor
    ))
    #expect(ModelLibraryCatalog.requiresTermsReview(
      for: .repair,
      descriptor: gemmaTermsDescriptor
    ))
    #expect(!ModelLibraryCatalog.requiresTermsReview(
      for: .repair,
      descriptor: parakeet
    ))
  }

  @Test @MainActor
  func modelDetailsStackAtSettingsPaneWidthsAndAccessibilityTextSize() {
    #expect(ModelLibraryLayout.stacksDetails(width: 470, dynamicTypeSize: .medium))
    #expect(ModelLibraryLayout.stacksDetails(width: 840, dynamicTypeSize: .medium))
    #expect(ModelLibraryLayout.stacksDetails(width: 1_019, dynamicTypeSize: .medium))
    #expect(!ModelLibraryLayout.stacksDetails(width: 1_020, dynamicTypeSize: .medium))
    #expect(ModelLibraryLayout.stacksDetails(width: 1_100, dynamicTypeSize: .accessibility1))
  }

  @Test @MainActor
  func externalBenchmarkEvidenceRequiresExactRoleModelAndRevision() throws {
    let parakeet = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID,
      revision: ModelLibraryExternalEvidenceCatalog.parakeetRevision
    )
    let parakeetEvidence = try #require(
      ModelLibraryExternalEvidenceCatalog.evidence(for: parakeet)
    )
    #expect(parakeetEvidence.metrics.map(\.value) == ["145.8× RTFx", "2.1%"])
    #expect(parakeetEvidence.metrics.map(\.label) == ["Overall audio throughput", "Mean per-file WER"])
    #expect(parakeetEvidence.context.contains("FluidAudio v2 benchmark runtime reference"))
    #expect(
      parakeetEvidence.sources.map(\.id) == ["fluidaudio-benchmark"]
    )
    #expect(
      parakeetEvidence.sources.first?.url.absoluteString
        == "https://github.com/FluidInference/FluidAudio/blob/87a39dfe4068fef0f1c69bfe704b2b3ef4fbc5bc/Documentation/Benchmarks.md"
    )

    let gemma = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID,
      revision: ModelLibraryExternalEvidenceCatalog.gemmaRevision,
      license: "Gemma Terms of Use"
    )
    let gemmaEvidence = try #require(
      ModelLibraryExternalEvidenceCatalog.evidence(for: gemma)
    )
    #expect(gemmaEvidence.metrics.map(\.value) == ["204.29 output tokens/s"])
    #expect(gemmaEvidence.context.contains("Concurrency 1"))
    #expect(gemmaEvidence.context.contains("128 prompts capped at 512 output tokens each"))
    #expect(gemmaEvidence.unmeasuredCleanupAccuracyContext != nil)
    #expect(Set(gemmaEvidence.sources.map(\.id)) == ["abstractcore-mlx-docs", "abstractcore-mlx-csv"])
    #expect(
      gemmaEvidence.sources.first { $0.id == "abstractcore-mlx-csv" }?.url.absoluteString
        == "https://raw.githubusercontent.com/lpalbou/AbstractCore/cf2fc6c85f3db31df480811d594fc50699049379/docs/assets/mlx_concurrency/mlx_concurrency_summary_20260128_210057.csv"
    )

    let wrongRole = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: ModelLibraryCatalog.parakeetModelID,
      revision: ModelLibraryExternalEvidenceCatalog.parakeetRevision
    )
    let wrongModel = try modelLibraryDescriptor(
      role: .asr,
      modelID: "FluidInference/unlisted-model",
      revision: ModelLibraryExternalEvidenceCatalog.parakeetRevision
    )
    let wrongRevision = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID,
      revision: "different-parakeet-revision"
    )
    #expect(ModelLibraryExternalEvidenceCatalog.evidence(for: wrongRole) == nil)
    #expect(ModelLibraryExternalEvidenceCatalog.evidence(for: wrongModel) == nil)
    #expect(ModelLibraryExternalEvidenceCatalog.evidence(for: wrongRevision) == nil)
  }

  @Test @MainActor
  func fixtureBrowserRendersAccessibleRowsAndResponsiveDetails() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let viewModels = try fixtureModelViewModels()
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )

    func browser(width: CGFloat, height: CGFloat) -> some View {
      ModelBrowserFixture(
        speechViewModel: viewModels.speech,
        cleanupViewModel: viewModels.cleanup,
        theme: theme,
        size: CGSize(width: width, height: height)
      )
    }

    let tableHost = try captureModelFixture(
      browser(width: 1_100, height: 760),
      name: "models-table-fixture",
      size: CGSize(width: 1_100, height: 760)
    )
    let tableWindow = makeModelFixtureWindow(contentView: tableHost)
    defer {
      tableWindow.orderOut(nil)
      tableWindow.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    tableHost.layoutSubtreeIfNeeded()

    let speechID = ModelLibraryEntry.pinKey(
      for: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let speechRows = modelAccessibilityElements(in: tableHost, identifier: "models-row-\(speechID)")
    #expect(speechRows.count == 1)
    let speechRow = try #require(speechRows.first)
    #expect(modelAccessibilityLabel(speechRow)?.contains("Parakeet") == true)
    #expect(modelAccessibilityElements(in: tableHost, identifier: "models-sort-name").count == 1)
    #expect(modelAccessibilityElements(in: tableHost, identifier: "models-pin-\(speechID)").count == 1)
    let downloadActions = modelAccessibilityElements(
      in: tableHost,
      identifier: "models-action-\(speechID)"
    )
    #expect(downloadActions.count == 1)
    let downloadAction = try #require(downloadActions.first)
    #expect(modelAccessibilityLabel(downloadAction) == "Download")

    #expect(performModelAccessibilityPress(speechRow))
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      tableHost.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    #expect(modelAccessibilityElements(in: tableHost, identifier: "models-detail-title").count == 1)
    #expect(modelAccessibilityElements(in: tableHost, identifier: "models-verified-specifications").count == 1)
    #expect(modelAccessibilityElements(in: tableHost, identifier: "models-external-results").count == 1)
    #expect(
      modelAccessibilityElements(
        in: tableHost,
        identifier: "models-external-source-\(speechID)-fluidaudio-benchmark"
      ).count == 1
    )
    #expect(
      modelAccessibilityElements(in: tableHost, identifier: "models-license-link-\(speechID)")
        .count == 1
    )
    let installActions = modelAccessibilityElements(
      in: tableHost,
      identifier: "models-action-\(speechID)"
    )
    #expect(installActions.count == 1)
    let installAction = try #require(installActions.first)
    #expect(modelAccessibilityLabel(installAction) == "Install")
    try writeModelFixture("models-detail-fixture", in: tableHost)

    let compactPaneHost = try captureModelFixture(
      browser(width: 900, height: 620),
      name: "models-compact-900-fixture",
      size: CGSize(width: 900, height: 620)
    )
    let compactPaneWindow = makeModelFixtureWindow(contentView: compactPaneHost)
    defer {
      compactPaneWindow.orderOut(nil)
      compactPaneWindow.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    compactPaneHost.layoutSubtreeIfNeeded()
    #expect(ModelLibraryLayout.stacksDetails(width: compactPaneHost.bounds.width, dynamicTypeSize: .medium))
    #expect(
      modelAccessibilityElements(
        in: compactPaneHost,
        identifier: "models-row-\(speechID)"
      ).count == 1
    )
    #expect(modelAccessibilityElements(in: compactPaneHost, identifier: "models-sort-name").count == 1)
    try writeModelFixture("models-compact-900-fixture", in: compactPaneHost)

    let narrowHost = try captureModelFixture(
      browser(width: 900, height: 620),
      name: "models-detail-narrow-fixture",
      size: CGSize(width: 900, height: 620)
    )
    let narrowWindow = makeModelFixtureWindow(contentView: narrowHost)
    defer {
      narrowWindow.orderOut(nil)
      narrowWindow.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    narrowHost.layoutSubtreeIfNeeded()

    let narrowRows = modelAccessibilityElements(
      in: narrowHost,
      identifier: "models-row-\(speechID)"
    )
    #expect(narrowRows.count == 1)
    let narrowRow = try #require(narrowRows.first)
    #expect(performModelAccessibilityPress(narrowRow))
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      narrowHost.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    #expect(modelAccessibilityElements(in: narrowHost, identifier: "models-back").count == 1)
    #expect(modelAccessibilityElements(in: narrowHost, identifier: "models-detail-title").count == 1)
    try writeModelFixture("models-detail-narrow-fixture", in: narrowHost)
    #expect(ModelLibraryLayout.stacksDetails(width: narrowHost.bounds.width, dynamicTypeSize: .medium))

    let accessibilitySizeHost = try captureModelFixture(
      ModelBrowserFixture(
        speechViewModel: viewModels.speech,
        cleanupViewModel: viewModels.cleanup,
        theme: theme,
        size: CGSize(width: 1_100, height: 760),
        dynamicTypeSize: .accessibility1,
        selectedModelID: speechID
      ),
      name: "models-detail-accessibility-size-fixture",
      size: CGSize(width: 1_100, height: 760)
    )
    let accessibilitySizeWindow = makeModelFixtureWindow(contentView: accessibilitySizeHost)
    defer {
      accessibilitySizeWindow.orderOut(nil)
      accessibilitySizeWindow.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    accessibilitySizeHost.layoutSubtreeIfNeeded()
    #expect(modelAccessibilityElements(in: accessibilitySizeHost, identifier: "models-back").count == 1)
    #expect(
      modelAccessibilityElements(in: accessibilitySizeHost, identifier: "models-detail-title")
        .count == 1
    )
    let accessibilitySizeAction = try #require(
      modelAccessibilityElements(
        in: accessibilitySizeHost,
        identifier: "models-action-\(speechID)"
      ).first
    )
    #expect(modelAccessibilityLabel(accessibilitySizeAction) == "Install")
    try writeModelFixture("models-detail-accessibility-size-fixture", in: accessibilitySizeHost)

    let darkTheme = FleckThemeSnapshot.resolve(
      colorTheme: .capy,
      mode: .dark,
      systemAppearance: .dark,
      reduceTransparency: true,
      increasedContrast: true
    )
    let darkThemeHost = try captureModelFixture(
      ModelBrowserFixture(
        speechViewModel: viewModels.speech,
        cleanupViewModel: viewModels.cleanup,
        theme: darkTheme,
        size: CGSize(width: 1_100, height: 760)
      ),
      name: "models-table-dark-high-contrast-fixture",
      size: CGSize(width: 1_100, height: 760)
    )
    let darkThemeWindow = makeModelFixtureWindow(contentView: darkThemeHost)
    defer {
      darkThemeWindow.orderOut(nil)
      darkThemeWindow.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    darkThemeHost.layoutSubtreeIfNeeded()
    #expect(
      modelAccessibilityElements(in: darkThemeHost, identifier: "models-row-\(speechID)")
        .count == 1
    )
    try writeModelFixture("models-table-dark-high-contrast-fixture", in: darkThemeHost)

    let emptyBrowser = ModelBrowserFixture(
      speechViewModel: modelLibraryViewModel(nil, role: .asr),
      cleanupViewModel: modelLibraryViewModel(nil, role: .cleanup),
      theme: theme,
      size: CGSize(width: 1_100, height: 760)
    )
    let emptyHost = try captureModelFixture(
      emptyBrowser,
      name: "models-empty-fixture",
      size: CGSize(width: 1_100, height: 760)
    )
    let emptyWindow = makeModelFixtureWindow(contentView: emptyHost)
    defer {
      emptyWindow.orderOut(nil)
      emptyWindow.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    emptyHost.layoutSubtreeIfNeeded()
    #expect(modelAccessibilityElements(in: emptyHost, identifier: "models-empty-state").count == 1)
  }

  @Test @MainActor
  func modelSearchBlursWithoutSwallowingActionsAcrossThemesAndSizes() async throws {
    enum OutsideAction {
      case blankPane
      case pin
      case openDetails
      case clearFilters
    }
    struct Scenario {
      let name: String
      let size: CGSize
      let theme: FleckThemeSnapshot
      let action: OutsideAction
    }

    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let viewModels = try fixtureModelViewModels()
    let lightTheme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let darkTheme = FleckThemeSnapshot.resolve(
      colorTheme: .capy,
      mode: .dark,
      systemAppearance: .dark,
      reduceTransparency: true,
      increasedContrast: true
    )
    let scenarios: [Scenario] = [
      Scenario(
        name: "840x600-light-blank",
        size: CGSize(width: 840, height: 600),
        theme: lightTheme,
        action: .blankPane
      ),
      Scenario(
        name: "760x520-light-pin",
        size: CGSize(width: 760, height: 520),
        theme: lightTheme,
        action: .pin
      ),
      Scenario(
        name: "840x600-dark-details",
        size: CGSize(width: 840, height: 600),
        theme: darkTheme,
        action: .openDetails
      ),
      Scenario(
        name: "760x520-dark-clear",
        size: CGSize(width: 760, height: 520),
        theme: darkTheme,
        action: .clearFilters
      ),
    ]
    let speechID = ModelLibraryEntry.pinKey(
      for: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let cleanupID = ModelLibraryEntry.pinKey(
      for: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID
    )

    for scenario in scenarios {
      let query = scenario.action == .clearFilters ? "a" : "parakeet"
      let selection = ModelBrowserSelection()
      let host = try captureModelFixture(
        ModelBrowserFixture(
          speechViewModel: viewModels.speech,
          cleanupViewModel: viewModels.cleanup,
          theme: scenario.theme,
          size: scenario.size,
          selection: selection
        ),
        name: "models-search-\(scenario.name)",
        size: scenario.size
      )
      let window = makeModelFixtureWindow(contentView: host)
      do {
        defer {
          window.orderOut(nil)
          window.contentView = nil
        }
        for _ in 0..<5 {
          host.layoutSubtreeIfNeeded()
          await Task.yield()
        }

        let searchField = try #require(modelSearchField(in: host))
        let searchElements = modelAccessibilityElements(
          in: host,
          identifier: "models-search-field"
        )
        #expect(searchElements.count == 1)
        #expect(modelAccessibilityLabel(try #require(searchElements.first)) == "Search models")
        #expect(searchField.placeholderString == "Search models")
        let searchFrame = searchField.convert(searchField.bounds, to: nil)
        #expect(searchFrame.width > 100)
        #expect(searchFrame.height > 14)

        try writeModelFixture("models-search-\(scenario.name)-idle", in: host)
        try clickModelView(searchField, in: window)
        let fieldEditor = try #require(searchField.currentEditor())
        #expect(window.firstResponder === fieldEditor)
        let editor = try #require(fieldEditor as? NSTextView)
        #expect(editor.delegate === searchField)
        editor.selectAll(nil)
        try typeModelText(query, in: window)
        try await settleModelBrowser(host)
        #expect(searchField.stringValue == query)
        #expect(modelAccessibilityValue(try #require(searchElements.first)) == query)
        #expect(
          modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").count == 1
        )
        if scenario.action == .clearFilters {
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").count == 1
          )
        } else {
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").isEmpty
          )
        }
        try writeModelFixture("models-search-\(scenario.name)-focused", in: host)

        switch scenario.action {
        case .blankPane:
          let windowPoint = host.convert(
            NSPoint(x: host.bounds.maxX - 32, y: host.bounds.minY + 520),
            to: nil
          )
          try sendModelMouseClick(at: window.convertPoint(toScreen: windowPoint), to: window)
          try await settleModelBrowser(host)
          try writeModelFixture("models-search-blank-after-outside-click", in: host)
          #expect(window.firstResponder !== fieldEditor)
          try sendModelKey(7, characters: "x", to: window)
          try await settleModelBrowser(host)
          #expect(searchField.stringValue == query)
        case .pin:
          let pin = try #require(
            modelAccessibilityElements(in: host, identifier: "models-pin-\(speechID)").first
          )
          #expect(modelAccessibilityValue(pin) == "Not pinned")
          try clickModelElement(pin, in: window)
          try await settleModelBrowser(host)
          let updatedPin = try #require(
            modelAccessibilityElements(in: host, identifier: "models-pin-\(speechID)").first
          )
          #expect(modelAccessibilityValue(updatedPin) == "Pinned")
          #expect(window.firstResponder !== fieldEditor)
          #expect(searchField.stringValue == query)
        case .openDetails:
          let row = try #require(
            modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").first
          )
          try clickModelElement(row, in: window)
          try await settleModelBrowser(host)
          try writeModelFixture("models-search-details-open", in: host)
          #expect(selection.selectedModelID == speechID)
          #expect(window.firstResponder !== fieldEditor)
          #expect(searchField.stringValue == query)

          let settingsSearchField = NSTextField()
          settingsSearchField.placeholderString = "Settings search"
          settingsSearchField.setAccessibilityIdentifier("settings-search-field")
          settingsSearchField.stringValue = "settings"
          settingsSearchField.frame = NSRect(
            x: host.bounds.midX - 80,
            y: host.bounds.minY + 12,
            width: 160,
            height: 22
          )
          host.addSubview(settingsSearchField)
          #expect(window.makeFirstResponder(settingsSearchField))
          let settingsEditor = try #require(settingsSearchField.currentEditor())
          #expect(window.firstResponder === settingsEditor)
          #expect((settingsEditor as? NSTextView)?.delegate === settingsSearchField)
          #expect(try modelEscapePassesNextLocalMonitor(in: window))
          try await settleModelBrowser(host)
          try #require(selection.selectedModelID == speechID)
          #expect(searchField.stringValue == query)

          try clickModelView(searchField, in: window)
          let focusedEditor = try #require(searchField.currentEditor())
          #expect(window.firstResponder === focusedEditor)
          if NSApp.isFullKeyboardAccessEnabled {
            try sendModelKey(48, characters: "\t", to: window)
            try await settleModelBrowser(host)
            #expect(window.firstResponder !== focusedEditor)
            try sendModelKey(48, characters: "\t", modifierFlags: [.shift], to: window)
            try await settleModelBrowser(host)
            let returnedEditor = try #require(searchField.currentEditor())
            #expect(window.firstResponder === returnedEditor)
          } else {
            try sendModelKey(48, characters: "\t", to: window)
            try await settleModelBrowser(host)
            #expect(window.firstResponder === focusedEditor)
          }
          let returnedEditor = try #require(searchField.currentEditor())
          #expect(window.firstResponder === returnedEditor)
          try sendModelKey(53, characters: "\u{1b}", to: window)
          try await settleModelBrowser(host)
          #expect(window.firstResponder !== returnedEditor)
          #expect(searchField.stringValue == query)
          #expect(selection.selectedModelID == speechID)
          try sendModelKey(53, characters: "\u{1b}", to: window)
          try await settleModelBrowser(host)
          #expect(selection.selectedModelID == nil)
          #expect(searchField.stringValue == query)
        case .clearFilters:
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-type-filter").count == 1
          )
          let typeFilterControl = try #require(modelTypeFilterControl(in: host))
          #expect(typeFilterControl.selectedSegment == 0)
          let voiceSegmentPoint = typeFilterControl.convert(
            NSPoint(
              x: typeFilterControl.bounds.midX,
              y: typeFilterControl.bounds.midY
            ),
            to: nil
          )
          try sendModelTrackedMouseClick(
            at: window.convertPoint(toScreen: voiceSegmentPoint),
            to: window
          )
          try await settleModelBrowser(host)
          let filteredTypeFilterControl = try #require(modelTypeFilterControl(in: host))
          #expect(filteredTypeFilterControl.selectedSegment == 1)
          #expect(window.firstResponder !== fieldEditor)
          #expect(searchField.stringValue == query)
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").count == 1
          )
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").isEmpty
          )

          try clickModelView(searchField, in: window)
          let emptySearchEditor = try #require(searchField.currentEditor())
          emptySearchEditor.selectAll(nil)
          try typeModelText("zzzz", in: window)
          try await settleModelBrowser(host)
          #expect(searchField.stringValue == "zzzz")
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").isEmpty
          )
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").isEmpty
          )

          let noResultsBlankPoint = host.convert(
            NSPoint(x: host.bounds.maxX - 32, y: host.bounds.minY + 110),
            to: nil
          )
          try sendModelMouseClick(
            at: window.convertPoint(toScreen: noResultsBlankPoint),
            to: window
          )
          try await settleModelBrowser(host)
          #expect(window.firstResponder !== emptySearchEditor)
          #expect(searchField.stringValue == "zzzz")

          try clickModelView(searchField, in: window)
          let refocusedEditor = try #require(searchField.currentEditor())
          #expect(window.firstResponder === refocusedEditor)
          try await settleModelBrowser(host)
          try sendModelKey(53, characters: "\u{1b}", to: window)
          try await settleModelBrowser(host)
          #expect(window.firstResponder !== refocusedEditor)
          #expect(searchField.stringValue == "zzzz")
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").isEmpty
          )
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").isEmpty
          )

          let clearFiltersButton = try #require(
            modelAccessibilityElements(in: host, identifier: "models-clear-filters").first
          )
          try clickModelElement(clearFiltersButton, in: window)
          try await settleModelBrowser(host)
          #expect(searchField.stringValue.isEmpty)
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").count == 1
          )
          #expect(
            modelAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").count == 1
          )
        }
      }
    }
  }

  @Test @MainActor
  func compactBrowserKeepsModelFactsActionsAndDetailsAccessible() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let viewModels = try fixtureModelViewModels()
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let size = CGSize(width: 470, height: 440)
    let host = try captureModelFixture(
      ModelBrowserFixture(
        speechViewModel: viewModels.speech,
        cleanupViewModel: viewModels.cleanup,
        theme: theme,
        size: size
      ),
      name: "models-compact-list-fixture",
      size: size
    )
    let window = makeModelFixtureWindow(contentView: host)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    host.layoutSubtreeIfNeeded()

    let speechID = ModelLibraryEntry.pinKey(
      for: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let speech = try #require(viewModels.speech.presentation.descriptor)
    let sizeFormatter = ByteCountFormatter()
    sizeFormatter.allowedUnits = [.useMB]
    sizeFormatter.countStyle = .decimal
    sizeFormatter.includesActualByteCount = false
    let speechRow = try #require(
      modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").first
    )
    let rowValue = try #require(modelAccessibilityValue(speechRow))
    #expect(modelAccessibilityLabel(speechRow)?.contains("Parakeet") == true)
    #expect(rowValue.contains("NVIDIA"))
    #expect(rowValue.contains("Voice recognition"))
    #expect(rowValue.contains("Available to install"))
    #expect(rowValue.contains("download size \(sizeFormatter.string(fromByteCount: speech.downloadBytes))"))
    #expect(rowValue.contains("Overall audio throughput: 145.8× RTFx"))
    #expect(rowValue.contains("Mean per-file WER: 2.1%"))
    #expect(rowValue.contains("External benchmark on M4 Pro"))
    #expect(!rowValue.contains("LibriSpeech test-clean"))
    #expect(!rowValue.contains("macOS 26.0"))
    #expect(!rowValue.contains("asr-benchmark"))
    #expect(!rowValue.contains("not measured by Fleck"))
    #expect(!rowValue.localizedCaseInsensitiveContains("not rated"))
    #expect(modelAccessibilityElements(in: host, identifier: "models-sort-name").count == 1)

    let cleanupID = ModelLibraryEntry.pinKey(
      for: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID
    )
    let cleanupRow = try #require(
      modelAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").first
    )
    let cleanupValue = try #require(modelAccessibilityValue(cleanupRow))
    #expect(cleanupValue.contains("Aggregate output throughput: 204.29 output tok/s"))
    #expect(cleanupValue.contains("External benchmark on M4 Max"))
    #expect(cleanupValue.contains("Cleanup accuracy: Not measured"))
    #expect(!cleanupValue.contains("65,536 output tokens"))
    #expect(!cleanupValue.contains("128 prompts"))
    #expect(!cleanupValue.contains("conversion SHA"))

    let pin = try #require(
      modelAccessibilityElements(in: host, identifier: "models-pin-\(speechID)").first
    )
    #expect(modelAccessibilityLabel(pin)?.hasPrefix("Pin Parakeet") == true)
    let action = try #require(
      modelAccessibilityElements(in: host, identifier: "models-action-\(speechID)").first
    )
    #expect(modelAccessibilityLabel(action) == "Download")
    #expect(performModelAccessibilityPress(speechRow))
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }

    #expect(modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").isEmpty)
    #expect(modelAccessibilityElements(in: host, identifier: "models-back").count == 1)
    #expect(modelAccessibilityElements(in: host, identifier: "models-detail-title").count == 1)
    #expect(modelAccessibilityElements(in: host, identifier: "models-external-results").count == 1)
    #expect(modelAccessibilityElements(in: host, identifier: "models-action-\(speechID)").count == 1)
    let speechContext = try #require(
      modelAccessibilityElements(
        in: host,
        identifier: "models-external-context-\(speechID)"
      ).first
    )
    let speechContextLabel = try #require(modelAccessibilityText(speechContext))
    #expect(speechContextLabel.contains("LibriSpeech test-clean (2,620 files)"))
    #expect(speechContextLabel.contains("M4 Pro, 48 GB RAM"))
    #expect(speechContextLabel.contains("asr-benchmark --max-files all --model-version v2"))
    #expect(speechContextLabel.contains("not measured by Fleck or this exact pinned conversion artifact"))

    let back = try #require(modelAccessibilityElements(in: host, identifier: "models-back").first)
    #expect(performModelAccessibilityPress(back))
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    #expect(modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").count == 1)

    let cleanupRowAgain = try #require(
      modelAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").first
    )
    #expect(performModelAccessibilityPress(cleanupRowAgain))
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    let cleanupContext = try #require(
      modelAccessibilityElements(
        in: host,
        identifier: "models-external-context-\(cleanupID)"
      ).first
    )
    let cleanupContextLabel = try #require(modelAccessibilityText(cleanupContext))
    #expect(cleanupContextLabel.contains("Concurrency 1"))
    #expect(cleanupContextLabel.contains("128 prompts capped at 512 output tokens each"))
    #expect(cleanupContextLabel.contains("MacBook Pro M4 Max, 128 GB"))
    let cleanupAccuracyContext = try #require(
      modelAccessibilityElements(
        in: host,
        identifier: "models-external-accuracy-context-\(cleanupID)"
      ).first
    )
    #expect(
      modelAccessibilityText(cleanupAccuracyContext)
        == "The throughput benchmark did not measure cleanup accuracy."
    )
    let conversionCaveat = try #require(
      modelAccessibilityElements(
        in: host,
        identifier: "models-external-conversion-caveat-\(cleanupID)"
      ).first
    )
    let conversionCaveatLabel = try #require(modelAccessibilityText(conversionCaveat))
    #expect(conversionCaveatLabel.contains("MLX model ID, not a conversion SHA"))
    #expect(conversionCaveatLabel.contains("does not verify this pinned converted revision"))
    #expect(
      modelAccessibilityElements(
        in: host,
        identifier: "models-external-source-\(cleanupID)-abstractcore-mlx-csv"
      ).count == 1
    )
  }

  @Test @MainActor
  func externalMetricsDoNotCarryAcrossAdmittedRevisions() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let speech = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID,
      revision: "different-parakeet-revision"
    )
    let cleanup = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID,
      revision: "different-gemma-revision",
      license: "Gemma Terms of Use"
    )
    let speechViewModel = modelLibraryViewModel(speech, role: .asr)
    let cleanupViewModel = modelLibraryViewModel(cleanup, role: .cleanup)
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let size = CGSize(width: 470, height: 520)
    let host = try captureModelFixture(
      ModelBrowserFixture(
        speechViewModel: speechViewModel,
        cleanupViewModel: cleanupViewModel,
        theme: theme,
        size: size
      ),
      name: "models-wrong-revisions-fixture",
      size: size
    )
    let window = makeModelFixtureWindow(contentView: host)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    host.layoutSubtreeIfNeeded()

    let speechID = ModelLibraryEntry.pinKey(
      for: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let speechRow = try #require(
      modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").first
    )
    let speechValue = try #require(modelAccessibilityValue(speechRow))
    #expect(!speechValue.contains("RTF"))
    #expect(!speechValue.contains("WER"))
    #expect(
      modelAccessibilityElements(
        in: host,
        identifier: "models-external-source-\(speechID)-fluidaudio-benchmark"
      ).isEmpty
    )

    let cleanupID = ModelLibraryEntry.pinKey(
      for: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID
    )
    let cleanupRow = try #require(
      modelAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").first
    )
    let cleanupValue = try #require(modelAccessibilityValue(cleanupRow))
    #expect(!cleanupValue.contains("MLX decode"))
    #expect(!cleanupValue.contains("204.29"))
    #expect(
      modelAccessibilityElements(
        in: host,
        identifier: "models-external-source-\(cleanupID)-abstractcore-mlx-docs"
      ).isEmpty
    )
    try writeModelFixture("models-wrong-revisions-fixture", in: host)
  }

  @Test @MainActor
  func compactSortChangesUnpinnedOrderAndKeepsPinnedModelFirst() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let viewModels = try fixtureModelViewModels()
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let size = CGSize(width: 470, height: 520)
    let host = try captureModelFixture(
      ModelBrowserFixture(
        speechViewModel: viewModels.speech,
        cleanupViewModel: viewModels.cleanup,
        theme: theme,
        size: size
      ),
      name: "models-compact-sort-fixture",
      size: size
    )
    let window = makeModelFixtureWindow(contentView: host)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    host.layoutSubtreeIfNeeded()

    let speechID = ModelLibraryEntry.pinKey(
      for: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let cleanupID = ModelLibraryEntry.pinKey(
      for: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID
    )
    let sort = try #require(
      modelAccessibilityElements(in: host, identifier: "models-sort-name").first
    )
    let valueBefore = try #require(modelAccessibilityValue(sort))
    #expect(valueBefore == "A to Z" || valueBefore == "Z to A")
    let orderBefore = modelLibraryRowOrder(in: host)
    #expect(orderBefore.count == 2)
    #expect(performModelAccessibilityPress(sort))
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    let sortAfterToggle = try #require(
      modelAccessibilityElements(in: host, identifier: "models-sort-name").first
    )
    let valueAfter = try #require(modelAccessibilityValue(sortAfterToggle))
    #expect(valueAfter != valueBefore)
    #expect(modelLibraryRowOrder(in: host) == Array(orderBefore.reversed()))

    if valueAfter != "A to Z" {
      #expect(performModelAccessibilityPress(sortAfterToggle))
      try await Task.sleep(for: .milliseconds(150))
      for _ in 0..<5 {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
      }
    }
    let speechPin = try #require(
      modelAccessibilityElements(in: host, identifier: "models-pin-\(speechID)").first
    )
    #expect(performModelAccessibilityPress(speechPin))
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
    #expect(modelAccessibilityValue(try #require(
      modelAccessibilityElements(in: host, identifier: "models-sort-name").first
    )) == "A to Z")
    #expect(modelLibraryRowOrder(in: host) == [speechID, cleanupID])
    try writeModelFixture("models-compact-sort-pinned-fixture", in: host)
  }

  @Test @MainActor
  func tableDetailsOpenFromANonControlColumnClick() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let parakeet = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let speech = modelLibraryViewModel(parakeet, role: .asr)
    let cleanup = modelLibraryViewModel(nil, role: .cleanup)
    let selectedID = ModelLibraryEntry.pinKey(for: .asr, modelID: ModelLibraryCatalog.parakeetModelID)
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let size = CGSize(width: 1_100, height: 760)
    let host = NSHostingView(
      rootView: ModelBrowserFixture(
        speechViewModel: speech,
        cleanupViewModel: cleanup,
        theme: theme,
        size: size
      )
    )
    host.frame = CGRect(origin: .zero, size: size)
    let window = makeModelFixtureWindow(contentView: host)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }

    let row = try #require(
      modelAccessibilityElements(in: host, identifier: "models-row-\(selectedID)").first
    )
    let rowFrame = try #require(modelAccessibilityFrame(row))
    let rowCenter = host.convert(
      NSPoint(x: rowFrame.midX, y: rowFrame.midY),
      from: nil
    )
    let sizeColumnPoint = host.convert(
      NSPoint(x: host.bounds.maxX - 179, y: rowCenter.y),
      to: nil
    )
    #expect(rowFrame.contains(sizeColumnPoint))
    try sendModelMouseClick(at: sizeColumnPoint, to: window)
    try await Task.sleep(for: .milliseconds(150))
    #expect(modelAccessibilityElements(in: host, identifier: "models-detail-title").count == 1)
  }

  @Test @MainActor
  func unavailableRoleErrorRemainsVisibleWithAnotherAdmittedModel() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let parakeet = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let speech = modelLibraryViewModel(parakeet, role: .asr)
    let cleanup = modelLibraryViewModel(
      nil,
      role: .cleanup,
      errorMessage: "Insufficient staging storage."
    )
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let size = CGSize(width: 1_100, height: 760)
    let host = NSHostingView(
      rootView: ModelBrowserFixture(
        speechViewModel: speech,
        cleanupViewModel: cleanup,
        theme: theme,
        size: size
      )
    )
    host.frame = CGRect(origin: .zero, size: size)
    let window = makeModelFixtureWindow(contentView: host)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }

    try writeModelFixture("models-unavailable-role-error-fixture", in: host)
    let unavailableDetail = try #require(
      modelAccessibilityElements(in: host, identifier: "models-unavailable-role-detail-0").first
    )
    let unavailableLabel = try #require(
      modelAccessibilityLabel(unavailableDetail) ?? modelAccessibilityValue(unavailableDetail)
    )
    #expect(unavailableLabel.contains("Enhanced local cleanup failed"))
    #expect(unavailableLabel.contains("Insufficient staging storage."))
    let speechID = ModelLibraryEntry.pinKey(for: .asr, modelID: ModelLibraryCatalog.parakeetModelID)
    #expect(
      modelAccessibilityElements(in: host, identifier: "models-row-\(speechID)").count == 1
    )
    #expect(modelAccessibilityElements(in: host, identifier: "models-empty-state").isEmpty)
  }

  @Test @MainActor
  func gemmaTermsSheetPrecedesInstallAndOnlyAcceptanceStartsTheInstaller() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let gemma = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID,
      license: "Gemma Terms of Use"
    )
    let cleanup = makeModelLibraryViewModel(gemma, role: .cleanup)
    let speech = modelLibraryViewModel(nil, role: .asr)
    let selectedID = ModelLibraryEntry.pinKey(for: .cleanup, modelID: ModelLibraryCatalog.gemmaModelID)
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let host = try captureModelFixture(
      ModelBrowserFixture(
        speechViewModel: speech,
        cleanupViewModel: cleanup.viewModel,
        theme: theme,
        size: CGSize(width: 1_100, height: 760),
        selectedModelID: selectedID
      ),
      name: "models-gemma-detail-fixture",
      size: CGSize(width: 1_100, height: 760)
    )
    let window = makeModelFixtureWindow(contentView: host)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }

    let installAction = try #require(
      modelAccessibilityElements(in: host, identifier: "models-action-\(selectedID)").first
    )
    #expect(modelAccessibilityLabel(installAction) == "Install")
    #expect(performModelAccessibilityPress(installAction))
    try await Task.sleep(for: .milliseconds(150))
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review"
    ).isEmpty)
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review-license-link"
    ).isEmpty)
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review-required-capacity"
    ).isEmpty)
    #expect(cleanup.installer.actions.isEmpty)

    let acceptAction = try #require(
      modelAccessibilityElements(
        in: NSApplication.shared.windows,
        identifier: "models-install-review-continue"
      ).first
    )
    #expect(modelAccessibilityLabel(acceptAction) == "Accept and Download")
    #expect(performModelAccessibilityPress(acceptAction))
    try await Task.sleep(for: .milliseconds(150))
    #expect(cleanup.installer.actions == [.install])
  }

  @Test @MainActor
  func gemmaRepairTermsSheetPrecedesRepairAndOnlyAcceptanceStartsTheInstaller() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let gemma = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID,
      license: "Gemma Terms of Use"
    )
    let cleanup = makeModelLibraryViewModel(
      gemma,
      role: .cleanup,
      phase: .repairRequired(message: "The installed files failed verification.")
    )
    let speech = modelLibraryViewModel(nil, role: .asr)
    let selectedID = ModelLibraryEntry.pinKey(for: .cleanup, modelID: ModelLibraryCatalog.gemmaModelID)
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let size = CGSize(width: 1_100, height: 760)
    let host = NSHostingView(
      rootView: ModelBrowserFixture(
        speechViewModel: speech,
        cleanupViewModel: cleanup.viewModel,
        theme: theme,
        size: size,
        selectedModelID: selectedID
      )
    )
    host.frame = CGRect(origin: .zero, size: size)
    let window = makeModelFixtureWindow(contentView: host)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))

    let repairAction = try #require(
      modelAccessibilityElements(in: host, identifier: "models-action-\(selectedID)").first
    )
    #expect(modelAccessibilityLabel(repairAction) == "Repair")
    #expect(performModelAccessibilityPress(repairAction))
    try await Task.sleep(for: .milliseconds(150))
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review"
    ).isEmpty)
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review-license-link"
    ).isEmpty)
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review-required-capacity"
    ).isEmpty)
    #expect(cleanup.installer.actions.isEmpty)

    let acceptAction = try #require(
      modelAccessibilityElements(
        in: NSApplication.shared.windows,
        identifier: "models-install-review-continue"
      ).first
    )
    #expect(modelAccessibilityLabel(acceptAction) == "Accept and Repair")
    #expect(performModelAccessibilityPress(acceptAction))
    try await Task.sleep(for: .milliseconds(150))
    #expect(cleanup.installer.actions == [.repair])
  }

  @Test @MainActor
  func parakeetDownloadReviewShowsAttributionAndStorageBeforeStartingInstaller() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let parakeet = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let speech = makeModelLibraryViewModel(parakeet, role: .asr)
    let cleanup = modelLibraryViewModel(nil, role: .cleanup)
    let selectedID = ModelLibraryEntry.pinKey(for: .asr, modelID: ModelLibraryCatalog.parakeetModelID)
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let host = NSHostingView(
      rootView: ModelBrowserFixture(
        speechViewModel: speech.viewModel,
        cleanupViewModel: cleanup,
        theme: theme,
        size: CGSize(width: 1_100, height: 760)
      )
    )
    host.frame = CGRect(origin: .zero, size: CGSize(width: 1_100, height: 760))
    host.layoutSubtreeIfNeeded()
    let window = makeModelFixtureWindow(contentView: host)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }

    let downloadAction = try #require(
      modelAccessibilityElements(in: host, identifier: "models-action-\(selectedID)").first
    )
    #expect(modelAccessibilityLabel(downloadAction) == "Download")
    #expect(performModelAccessibilityPress(downloadAction))
    try await Task.sleep(for: .milliseconds(150))
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review"
    ).isEmpty)
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review-license"
    ).isEmpty)
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review-source"
    ).isEmpty)
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review-license-link"
    ).isEmpty)
    #expect(!modelAccessibilityElements(
      in: NSApplication.shared.windows,
      identifier: "models-install-review-required-capacity"
    ).isEmpty)
    #expect(speech.installer.actions.isEmpty)

    let continueAction = try #require(
      modelAccessibilityElements(
        in: NSApplication.shared.windows,
        identifier: "models-install-review-continue"
      ).first
    )
    #expect(modelAccessibilityLabel(continueAction) == "Download Model")
    #expect(performModelAccessibilityPress(continueAction))
    try await Task.sleep(for: .milliseconds(150))
    #expect(speech.installer.actions == [.install])
  }

  @Test @MainActor
  func modelRemovalRequiresConfirmationBeforeInstallerMutation() async throws {
    let previousAccessibility = enableModelBrowserAccessibility()
    defer { restoreModelBrowserAccessibility(previousAccessibility) }
    let parakeet = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let speech = makeModelLibraryViewModel(parakeet, role: .asr, phase: .installed)
    let cleanup = modelLibraryViewModel(nil, role: .cleanup)
    let selectedID = ModelLibraryEntry.pinKey(for: .asr, modelID: ModelLibraryCatalog.parakeetModelID)
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .light,
      systemAppearance: .light,
      reduceTransparency: true,
      increasedContrast: false
    )
    let host = try captureModelFixture(
      ModelBrowserFixture(
        speechViewModel: speech.viewModel,
        cleanupViewModel: cleanup,
        theme: theme,
        size: CGSize(width: 1_100, height: 760),
        selectedModelID: selectedID
      ),
      name: "models-installed-detail-fixture",
      size: CGSize(width: 1_100, height: 760)
    )
    let window = makeModelFixtureWindow(contentView: host)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }

    let removeAction = try #require(
      modelAccessibilityElements(in: host, identifier: "models-action-\(selectedID)").first
    )
    #expect(modelAccessibilityLabel(removeAction) == "Remove")
    #expect(performModelAccessibilityPress(removeAction))
    try await Task.sleep(for: .milliseconds(150))
    let confirmAction = try #require(
      modelAccessibilityElements(
        in: NSApplication.shared.windows,
        identifier: "models-confirm-removal"
      ).first
    )
    #expect(modelAccessibilityLabel(confirmAction) == "Remove Model")
    #expect(speech.installer.actions.isEmpty)
    #expect(performModelAccessibilityPress(confirmAction))
    try await Task.sleep(for: .milliseconds(150))
    #expect(speech.installer.actions == [.remove])
  }
#endif
