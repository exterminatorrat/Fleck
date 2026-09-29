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
  license: String = "CC-BY-4.0"
) throws -> AdmittedModelDescriptor {
  let downloadBytes: Int64 = role == .asr ? 464_413_247 : 771_863_021
  return try AdmittedModelDescriptor(validating: RawAdmittedModelDescriptor(
      role: role,
      modelID: modelID,
      revision: "fixture-revision",
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
  private func fixtureModelViewModels() throws -> (
    speech: AdmittedModelSettingsViewModel,
    cleanup: AdmittedModelSettingsViewModel
  ) {
    let speech = try modelLibraryDescriptor(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID
    )
    let cleanup = try modelLibraryDescriptor(
      role: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID,
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
  private struct ModelBrowserFixture: View {
    let speechViewModel: AdmittedModelSettingsViewModel
    let cleanupViewModel: AdmittedModelSettingsViewModel
    let theme: FleckThemeSnapshot
    let size: CGSize
    let dynamicTypeSize: DynamicTypeSize
    @State private var pinnedModelKeys: Set<String> = []
    @State private var selectedModelID: String?

    init(
      speechViewModel: AdmittedModelSettingsViewModel,
      cleanupViewModel: AdmittedModelSettingsViewModel,
      theme: FleckThemeSnapshot,
      size: CGSize,
      dynamicTypeSize: DynamicTypeSize = .medium,
      selectedModelID: String? = nil
    ) {
      self.speechViewModel = speechViewModel
      self.cleanupViewModel = cleanupViewModel
      self.theme = theme
      self.size = size
      self.dynamicTypeSize = dynamicTypeSize
      _selectedModelID = State(initialValue: selectedModelID)
    }

    var body: some View {
      ModelsBrowserView(
        speechViewModel: speechViewModel,
        cleanupViewModel: cleanupViewModel,
        pinnedModelKeys: $pinnedModelKeys,
        selectedModelID: $selectedModelID
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
  private func modelAccessibilityFrame(_ element: NSObject) -> CGRect? {
    (element.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue
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
  func modelDetailsStackAtNarrowWidthAndAccessibilityTextSize() {
    #expect(ModelLibraryLayout.minimumWindowWidth == 900)
    #expect(ModelLibraryLayout.defaultWindowWidth == 1_100)
    #expect(ModelLibraryLayout.stacksDetails(width: 1_019, dynamicTypeSize: .medium))
    #expect(!ModelLibraryLayout.stacksDetails(width: 1_020, dynamicTypeSize: .medium))
    #expect(ModelLibraryLayout.stacksDetails(width: 1_100, dynamicTypeSize: .accessibility1))
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

    let minimumTableHost = try captureModelFixture(
      browser(width: 900, height: 620),
      name: "models-table-minimum-fixture",
      size: CGSize(width: 900, height: 620)
    )
    let minimumTableWindow = makeModelFixtureWindow(contentView: minimumTableHost)
    defer {
      minimumTableWindow.orderOut(nil)
      minimumTableWindow.contentView = nil
    }
    for _ in 0..<5 { await Task.yield() }
    minimumTableHost.layoutSubtreeIfNeeded()
    #expect(minimumTableHost.bounds.width == ModelLibraryLayout.minimumWindowWidth)
    #expect(
      modelAccessibilityElements(
        in: minimumTableHost,
        identifier: "models-row-\(speechID)"
      ).count == 1
    )
    #expect(
      modelAccessibilityElements(in: minimumTableHost, identifier: "models-sort-name").count == 1
    )
    try writeModelFixture("models-table-minimum-fixture", in: minimumTableHost)

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
    #expect(narrowHost.bounds.width == 900)

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
