import AppKit
import Foundation
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test func settingsSourceUsesCompactModelsRowsAndRemovesTechnicalMetadata() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let runtimeSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )

  #expect(source.contains(
    "@ObservedObject private var admittedModelSettingsViewModel: AdmittedModelSettingsViewModel"
  ))
  #expect(source.contains(
    "@ObservedObject private var cleanupAdmittedModelSettingsViewModel: AdmittedModelSettingsViewModel"
  ))
  #expect(source.contains("_admittedModelSettingsViewModel = ObservedObject("))
  #expect(source.contains("wrappedValue: runtime.admittedModelSettingsViewModel"))
  #expect(source.contains("_cleanupAdmittedModelSettingsViewModel = ObservedObject("))
  #expect(source.contains("wrappedValue: runtime.cleanupAdmittedModelSettingsViewModel"))
  #expect(source.contains("AdmittedModelSettingsPresentation"))
  #expect(source.contains("SettingsPreferenceRow(\n          \"Dictation model\""))
  #expect(source.contains("SettingsPreferenceRow(\n          \"Cleanup model\""))
  #expect(source.contains(
    "presentation: admittedModelSettingsViewModel.presentation,\n" +
      "            viewModel: admittedModelSettingsViewModel,"
  ))
  #expect(source.contains(
    "presentation: cleanupAdmittedModelSettingsViewModel.presentation,\n" +
      "            viewModel: cleanupAdmittedModelSettingsViewModel,"
  ))
  #expect(!source.contains(#"Section("Speech Engine")"#))
  #expect(!source.contains(#"Text("Active engine:"#))
  #expect(source.contains(#"Text("Model: \(presentation.modelLabel)")"#))
  #expect(source.contains("presentation.modelLabel"))
  #expect(source.contains("if presentation.showsStatus"))
  #expect(source.contains("if presentation.showsDetail"))
  #expect(source.contains("SettingsPreferenceRow(\n          \"Theme\""))
  #expect(source.contains("SettingsPreferenceRow(\n          \"Editor text color\""))
  #expect(source.contains("SettingsPreferenceRow(\n          \"Width\""))
  #expect(source.contains("ScrollView"))
  #expect(runtimeSource.contains(".defaultSize(width: 840, height: 600)"))
  #expect(runtimeSource.contains(".windowResizability(.contentMinSize)"))
  #expect(source.contains(".focusable(presentation.isKeyboardFocusable)"))
  #expect(source.contains(".accessibilityElement(children: .contain)"))
  #expect(source.contains(".accessibilityLabel(presentation.accessibilityLabel)"))
  #expect(source.contains(".accessibilityValue(presentation.accessibilityValue)"))
  #expect(source.contains("await admittedModelSettingsViewModel.refresh()"))
  #expect(source.contains("await cleanupAdmittedModelSettingsViewModel.refresh()"))
  #expect(source.contains("Button(label) { viewModel.perform(action) }"))
  #expect(source.contains(
    #"progressAccessibilityLabel: "Enhanced local dictation installation progress""#
  ))
  #expect(source.contains(
    #"progressAccessibilityLabel: "Enhanced local cleanup installation progress""#
  ))
  #expect(source.contains(".accessibilityLabel(progressAccessibilityLabel)"))
  #expect(!source.contains("cleanupModelLabel"))
  #expect(!source.contains("runtime.availability.foundationModelAvailability"))
  #expect(!source.contains(#"LabeledContent("Cleanup", value:"#))
  #expect(!source.contains("private func perform(_ action: AdmittedModelSettingsAction)"))
  #expect(!source.contains("Button(label) { perform(action) }"))
  #expect(!source.contains("License"))
  #expect(!source.contains("Checksums"))
  #expect(!source.contains("Supported architectures"))
  #expect(!source.contains("Supported languages"))
  #expect(!source.contains("Download size"))
  #expect(!source.contains("Installed size"))
  #expect(!source.contains(" bytes"))
  #expect(!source.contains("Admitted model installation progress"))
  #expect(!source.contains("Picker(\"Engine\""))
  #expect(!source.contains("ModelConsentView"))
  #expect(!source.contains("DictationModelConsentPresentation"))
  #expect(!source.contains("Download Enhanced Model"))
  #expect(!source.contains("Loading"))
  #expect(!source.contains("modelError"))
  #expect(!source.contains("clearModelError"))
  #expect(!runtimeSource.contains("modelError"))
  #expect(!runtimeSource.contains("clearModelError"))
#if CLEAN_DICTATION_ENHANCED_CANDIDATE
  #expect(runtimeSource.contains(
    "let destinationRouter: any DestinationRouting = cleanupComposition.destinationRouter"
  ))
  #expect(runtimeSource.contains(
    "localRoutingModelReady: localRoutingModelReady(cleanupPresentation)"
  ))
#endif
}

@Test func admittedModelSourcesUseNeutralUserFacingCopy() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let sourcePaths = [
    "Sources/FleckApp/AdmittedModelSettingsPresentation.swift",
    "Sources/FleckApp/SettingsView.swift",
    "Sources/FleckApp/ParakeetTDTTestActivation.swift",
  ]
  let sources = try sourcePaths.map { path in
    (
      path,
      try String(contentsOf: repository.appendingPathComponent(path), encoding: .utf8)
    )
  }
  var offendingQuotedCopy: [String] = []
  for (path, source) in sources {
    offendingQuotedCopy.append(contentsOf: source.split(whereSeparator: \.isNewline).filter { line in
      let lowercasedLine = line.lowercased()
      return lowercasedLine.contains("\"") && (
        lowercasedLine.contains("admitted model") ||
        lowercasedLine.contains("admitted local model")
      )
    }.map { "\(path): \($0)" })
  }

  #expect(offendingQuotedCopy.isEmpty)
  #expect(sources[0].1.contains(
    "Enhanced local dictation failed:"
  ))
  #expect(sources[1].1.contains(
    #"progressAccessibilityLabel: "Enhanced local dictation installation progress""#
  ))
  #expect(sources[2].1.contains(
    "Repair the experimental enhanced local model candidate in Dictation Settings"
  ))
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test
func candidateStartupUsesActivatedConfigurationAndRefreshesItsInstaller() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let runtimeSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )

  #expect(runtimeSource.contains("ParakeetTDTTestActivation"))
  #expect(!runtimeSource.contains(
    "let signedConfiguration: AdmittedModelSignedConfiguration? = nil"
  ))
  #expect(runtimeSource.contains("await admittedModelSettingsViewModel.refresh()"))
}
#endif

@Test func DictationSettingsExposesNativeSidebarGroupsAndMetadata() {
  #expect(SettingsSection.fleckCases == [.editing, .appearance, .shortcuts])
  #expect(SettingsSection.voiceAndWritingCases == [.dictation, .vocabulary])
  #expect(SettingsSection.connectionCases == [.agents])
  #expect(SettingsSection.editing.title == "General")
  #expect(SettingsSection.editing.description ==
    "Choose how Fleck edits and organizes your notes.")
  #expect(!SettingsSection.editing.systemImage.isEmpty)
}

@Test @MainActor
func DictationSettingsSidebarFitsMinimumWindowAtAccessibilitySizes() async throws {
  var selection = SettingsSection.appearance
  let selected = Binding(
    get: { selection },
    set: { selection = $0 }
  )

  for dynamicTypeSize in [DynamicTypeSize.large, DynamicTypeSize.accessibility3] {
    let host = NSHostingView(
      rootView: SettingsSectionSidebar(selection: selected)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .frame(width: 200, height: 520)
    )
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 520)
    let window = NSWindow(
      contentRect: host.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    await settleSettingsHost(host)

    let visibleFrames = settingsSidebarDescendants(of: host)
      .filter { !$0.isHidden && $0.alphaValue > 0 && !$0.bounds.isEmpty }
      .map { $0.convert($0.bounds, to: host) }
    #expect(!visibleFrames.isEmpty)
    #expect(visibleFrames.allSatisfy { host.bounds.insetBy(dx: -1, dy: -1).contains($0) })

    let table = try #require(settingsSidebarTableView(of: host))
    let outline = try #require(table as? NSOutlineView)
    let selectableRows = (0..<outline.numberOfRows).filter { row in
      guard let item = outline.item(atRow: row) else { return false }
      return !(outline.delegate?.outlineView?(outline, isGroupItem: item) ?? false)
    }
    let vocabularyIndex = try #require(SettingsSection.allCases.firstIndex(of: .vocabulary))
    try #require(selectableRows.indices.contains(vocabularyIndex))
    let vocabularyRow = selectableRows[vocabularyIndex]
    window.makeKeyAndOrderFront(nil)
    table.selectRowIndexes(IndexSet(integer: vocabularyRow), byExtendingSelection: false)
    NotificationCenter.default.post(
      name: NSTableView.selectionDidChangeNotification,
      object: table
    )
    await settleSettingsHost(host)

    #expect(selection == .vocabulary)
    #expect(table.selectedRow == vocabularyRow)

    window.contentView = nil
    window.orderOut(nil)
  }
}

@Test func DictationSettingsUsesNativeSidebarAccessibilityAndSelectionContracts() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(source.contains("struct SettingsSectionSidebar: View"))
  #expect(source.contains("List(selection: $selection)"))
  #expect(source.contains(".listStyle(.sidebar)"))
  #expect(source.contains(".tag(section)"))
  #expect(source.contains(".accessibilityLabel(\"Settings sections\")"))
  #expect(source.contains("SettingsSidebarSurface"))
  #expect(source.contains("SettingsPageHeaderProbe"))
  #expect(source.contains("settings-page-header"))
  #expect(source.contains("Toggle(isOn: $isOn)"))
  #expect(!source.contains("Toggle(\"\", isOn: $isOn)"))
  #expect(source.contains(".accessibilityLabel(title)"))
  #expect(source.contains(".accessibilityHint(detail)"))
  #expect(source.contains(".accessibilityIdentifier(title)"))
  #expect(source.contains("case .editing:\n        \"gearshape\""))
  #expect(source.contains(".padding(.top, 38)"))
  let sectionGroupStart = try #require(source.range(of: "private func sectionGroup("))
  let sidebarSurfaceStart = try #require(
    source.range(
      of: "  struct SettingsSidebarSurface",
      range: sectionGroupStart.upperBound..<source.endIndex
    )
  )
  let sectionGroupSource = source[sectionGroupStart.lowerBound..<sidebarSurfaceStart.lowerBound]
  #expect(sectionGroupSource.contains(".padding(.bottom, 4)"))
  #expect(source.contains("Create lists automatically"))
  #expect(source.contains("Recognize list-shaped lines while you edit."))
  #expect(source.contains("Confirm before moving notes to Trash"))
  #expect(source.contains("Ask before a note is moved to the Trash folder."))
  #expect(source.contains("Launch at login"))
  #expect(source.contains("Start Fleck automatically when you sign in."))
  #expect(!source.contains("NavigationSplitView"))
  #expect(!source.contains("NavigationSplitViewVisibility"))
  #expect(!source.contains("navigationSplitViewColumnWidth"))
  #expect(!source.contains("SettingsSectionSelector"))
  #expect(!source.contains("matchedGeometryEffect"))
  #expect(!source.contains("Picker(\"Settings section\""))
}

@Test func SettingsSidebarUsesTransparentListAndVocabularyKeepsOneTeachingHeadline() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(source.contains(".scrollContentBackground(.hidden)"))
  #expect(source.contains(".background(Color.clear)"))
  #expect(SettingsSection.vocabulary.description ==
    "Manage personal vocabulary and dictation corrections.")
  #expect(SettingsSection.vocabulary.description !=
    "Teach Fleck the words and spellings that matter to you.")
}

@Test func SettingsPresentationUsesNativeSwitchesAndConsumerPreferenceRows() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let agentSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/AgentSettingsView.swift"),
    encoding: .utf8
  )

  #expect(settingsSource.contains("struct SettingsPreferenceRow"))
  #expect(settingsSource.contains(".toggleStyle(.switch)"))
  #expect(settingsSource.contains(".controlSize(.small)"))
  #expect(settingsSource.contains("SettingsToggleRow(\n          title: \"Create lists automatically\""))
  #expect(settingsSource.contains("SettingsToggleRow(\n          title: \"Confirm before moving notes to Trash\""))
  #expect(settingsSource.contains("SettingsToggleRow(\n          title: \"Launch at login\""))
  #expect(settingsSource.contains("SettingsPreferenceRow(\n          \"Theme\""))
  #expect(settingsSource.contains("SettingsPreferenceRow(\n          \"Modifier key\""))
  #expect(settingsSource.contains("SettingsToggleRow(\n          title: \"Show status capsule\""))
  #expect(!settingsSource.contains("SettingsSectionCard(\"Behavior\")"))
  #expect(!settingsSource.contains("JSON workspace manifest"))
  #expect(agentSource.contains("SettingsPreferenceRow("))
  #expect(agentSource.contains(
    "SettingsPreferenceRow(\n          AgentConnectorPresentation.sectionTitle"
  ))
  #expect(agentSource.contains("SettingsPreferenceRow(integration.displayName"))
  #expect(agentSource.contains("SettingsPreferenceRow(profile.displayName"))
}

@Test func DictationSettingsUsesFleckNeutralGlassContractWithAdaptiveFallback() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(source.contains("Color.black.opacity(0.10)"))
  #expect(source.contains("Glass.regular.tint(Color.black.opacity(0.18))"))
  #expect(source.contains("shape.fill(.ultraThinMaterial)"))
  #expect(source.contains("if reduceTransparency"))
  #expect(source.contains("Color(nsColor: .windowBackgroundColor)"))
}

@Test func DictationSettingsUsesReadinessCaptureAndHistoryGroups() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(DictationSettingsGroup.allCases.map(\.rawValue) == [
    "Status",
    "Models",
    "Capture",
    "Experience & history",
    "Privacy",
  ])
  #expect(source.contains("private var readiness"))
  #expect(source.contains("Text(DictationSettingsGroup.capture.rawValue)"))
  #expect(source.contains(
    "Text(DictationSettingsGroup.experience.rawValue)"
  ))
  #expect(source.contains("isReady ? \"Ready\" : \"Needs attention\""))
  #expect(source.contains("Text(DictationSettingsGroup.models.rawValue)"))
  #expect(source.contains("DisclosureGroup(DictationSettingsGroup.privacy.rawValue)"))
  #expect(!source.contains("SettingsSectionCard(\"Controls\")"))
}

@Test func DictationSettingsRendersItsDestinationGroupsInReadingOrder() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let dictationStart = try #require(source.range(of: "private var dictation: some View"))
  let vocabularyStart = try #require(
    source.range(of: "private var vocabulary:", range: dictationStart.upperBound..<source.endIndex)
  )
  let dictationSource = source[dictationStart.lowerBound..<vocabularyStart.lowerBound]
  let markers = [
    "        readiness",
    "        models",
    "        capture",
    "        experienceAndHistory",
    "        DisclosureGroup(DictationSettingsGroup.privacy.rawValue)",
  ]
  var cursor = dictationSource.startIndex
  for marker in markers {
    let next = try #require(dictationSource.range(of: marker, range: cursor..<dictationSource.endIndex))
    cursor = next.upperBound
  }
}

@Test @MainActor
func DictationSettingsHostedWindowDoesNotEnableFullSizeContentViewChrome()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: nil, capsuleEnabled: false)
  let host = NSHostingView(
    rootView: SettingsView(runtime: fixture.runtime)
      .environmentObject(fixture.appState)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 840, height: 600),
    styleMask: [.titled, .resizable, .closable],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleSettingsHost(host)

  #expect(!window.styleMask.contains(.fullSizeContentView))

  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor
func DictationSettingsHostedWindowKeepsNativeChromeStableAcrossDestinations()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: nil, capsuleEnabled: false)
  let sizes = [
    NSSize(width: 840, height: 600),
    NSSize(width: 760, height: 520),
  ]
  let destinations = SettingsSection.allCases

  for size in sizes {
    let host = NSHostingView(
      rootView: SettingsView(runtime: fixture.runtime)
        .environmentObject(fixture.appState)
        .environment(\.dynamicTypeSize, .large)
    )
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .resizable, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Settings"
    let toolbar = NSToolbar(identifier: "settings-hosted-test-toolbar-\(Int(size.width))")
    window.toolbar = toolbar
    window.toolbarStyle = .unifiedCompact
    #expect(window.toolbar === toolbar)
    #expect(window.toolbarStyle == .unifiedCompact)
    window.contentView = host
    window.setContentSize(size)
    window.makeKeyAndOrderFront(nil)
    await settleSettingsHost(host)

    #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
    #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == false)
    #expect(window.standardWindowButton(.zoomButton)?.isHidden == false)
    let contentView = try #require(window.contentView)
    #expect(settingsNativeSplitViewController(of: contentView) == nil)
    let toolbarItemIdentifiers = toolbar.items.map(\.itemIdentifier)
    #expect(!toolbarItemIdentifiers.contains(.toggleSidebar))
    #expect(!toolbarItemIdentifiers.contains(.sidebarTrackingSeparator))
    let sidebar = try #require(settingsSidebarTableView(of: host))
    let outline = try #require(sidebar as? NSOutlineView)
    let sidebarScroll = try #require(settingsScrollViewAncestor(of: sidebar))
    let sidebarSurface = try #require(settingsSidebarSurface(of: host))
    let baselineContentFrame = contentView.convert(contentView.bounds, to: nil)
    let baselineLayoutRect = window.contentLayoutRect
    let baselineSidebarFrame = sidebar.convert(sidebar.bounds, to: nil)
    let baselineSidebarSurfaceFrame = sidebarScroll.convert(sidebarScroll.bounds, to: nil)
    let outerSidebarSurfaceFrame = sidebarSurface.convert(sidebarSurface.bounds, to: nil)

    #expect(window.isResizable)
    #expect(!baselineContentFrame.isEmpty)
    #expect(!baselineLayoutRect.isEmpty)
    #expect(!baselineSidebarFrame.isEmpty)
    #expect(!outerSidebarSurfaceFrame.isEmpty)
    #expect(outerSidebarSurfaceFrame.minX >= baselineContentFrame.minX + 8)
    #expect(outerSidebarSurfaceFrame.maxX <= baselineContentFrame.maxX - 8)
    let trafficLightButtons: [NSButton?] = [
      window.standardWindowButton(.closeButton),
      window.standardWindowButton(.miniaturizeButton),
      window.standardWindowButton(.zoomButton),
    ]
    let trafficLightFrames: [NSRect] = trafficLightButtons.compactMap { button in
      guard let button else { return nil }
      return button.convert(button.bounds, to: nil)
    }
    #expect(!trafficLightFrames.isEmpty)
    #expect(trafficLightFrames.allSatisfy {
      settingsRoundedSurfaceContains(
        $0,
        in: outerSidebarSurfaceFrame,
        cornerRadius: 22,
        margin: 8
      )
    })
    #expect(trafficLightFrames.allSatisfy { !$0.intersects(baselineSidebarFrame) })

    for destination in destinations {
      let row = try #require(settingsSidebarRow(destination, in: outline))
      outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      NotificationCenter.default.post(
        name: NSTableView.selectionDidChangeNotification,
        object: outline
      )
      await settleSettingsHost(host)

      #expect(outline.selectedRow == row)

      let contentFrame = contentView.convert(contentView.bounds, to: nil)
      #expect(approximatelyEqual(contentFrame, baselineContentFrame))
      #expect(approximatelyEqual(window.contentLayoutRect, baselineLayoutRect))

      let sidebarFrame = sidebar.convert(sidebar.bounds, to: nil)
      let sidebarSurfaceFrame = sidebarScroll.convert(sidebarScroll.bounds, to: nil)
      #expect(!sidebar.isHidden)
      #expect(sidebar.alphaValue > 0)
      #expect(baselineLayoutRect.contains(sidebarFrame.center))
      #expect(approximatelyEqual(sidebarFrame, baselineSidebarFrame))
      #expect(approximatelyEqual(sidebarSurfaceFrame, baselineSidebarSurfaceFrame))
      #expect(approximatelyEqual(
        sidebarSurface.convert(sidebarSurface.bounds, to: nil),
        outerSidebarSurfaceFrame
      ))
      #expect(trafficLightFrames.allSatisfy { !$0.intersects(sidebarFrame) })

      let detailScroll = settingsHostedScrollViews(of: host)
        .first { $0 !== sidebarScroll }
      #expect(detailScroll != nil)
      guard let detailScroll else { continue }
      #expect(detailScroll !== sidebarScroll)
      let detailDocument = try #require(detailScroll.documentView)
      #expect(!detailDocument.bounds.isEmpty)
      #expect(!detailScroll.contentView.bounds.isEmpty)

      let detailFrame = detailScroll.convert(detailScroll.bounds, to: nil)
      #expect(!detailFrame.isEmpty)
      #expect(baselineLayoutRect.contains(detailFrame.center))
      let detailDocumentFrame = detailDocument.convert(detailDocument.bounds, to: nil)
      #expect(detailDocumentFrame.minX >= baselineLayoutRect.minX - 1)
      #expect(detailDocumentFrame.maxX <= baselineLayoutRect.maxX + 1)
      #expect(detailDocumentFrame.maxY <= baselineLayoutRect.maxY + 1)
      #expect(detailDocumentFrame.intersects(baselineLayoutRect))
      let detailTopGap = baselineLayoutRect.maxY - detailDocumentFrame.maxY
      #expect(detailTopGap >= -1)
      #expect(detailTopGap <= 20)
      let pageTitle = try #require(
        settingsView(withAccessibilityIdentifier: "settings-page-header", in: detailDocument)
      )
      let pageTitleFrame = pageTitle.convert(pageTitle.bounds, to: nil)
      #expect(!pageTitleFrame.isEmpty)
      #expect(pageTitleFrame.minX >= detailDocumentFrame.minX - 1)
      #expect(pageTitleFrame.maxX <= detailDocumentFrame.maxX + 1)
      let pageTitleTopGap = baselineLayoutRect.maxY - pageTitleFrame.maxY
      #expect(pageTitleTopGap >= -1)
      #expect(pageTitleTopGap <= 20)

    }

    let detailScrollViews = settingsHostedScrollViews(of: host)
      .filter { $0 !== sidebarScroll }
    #expect(!detailScrollViews.isEmpty)
    window.contentView = nil
    window.orderOut(nil)
  }
}

@Test @MainActor
func DictationSettingsHostedWindowKeepsInsetSidebarAndTrafficLightsContained()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: nil, capsuleEnabled: false)
  let size = NSSize(width: 840, height: 600)
  let host = NSHostingView(
    rootView: SettingsView(runtime: fixture.runtime)
      .environmentObject(fixture.appState)
      .environment(\.dynamicTypeSize, .large)
  )
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.titled, .resizable, .closable, .fullSizeContentView],
    backing: .buffered,
    defer: false
  )
  window.title = "Settings"
  let toolbar = NSToolbar(identifier: "settings-hosted-inset-sidebar-toolbar")
  window.toolbar = toolbar
  window.toolbarStyle = .unifiedCompact
  window.contentView = host
  window.setContentSize(size)
  window.makeKeyAndOrderFront(nil)
  await settleSettingsHost(host)

  let contentView = try #require(window.contentView)
  let outline = try #require(settingsSidebarTableView(of: host) as? NSOutlineView)
  let sidebar = try #require(settingsSidebarTableView(of: host))
  let sidebarScroll = try #require(settingsScrollViewAncestor(of: sidebar))
  let sidebarSurface = try #require(settingsSidebarSurface(of: host))
  let contentFrame = contentView.convert(contentView.bounds, to: nil)
  let surfaceFrame = sidebarSurface.convert(sidebarSurface.bounds, to: nil)
  let topInset = contentFrame.maxY - surfaceFrame.maxY
  let bottomInset = surfaceFrame.minY - contentFrame.minY

  #expect(surfaceFrame.minX >= contentFrame.minX + 8)
  #expect(topInset >= 8)
  #expect(topInset <= 12)
  #expect(bottomInset >= 8)
  #expect(bottomInset <= 12)
  #expect(window.titleVisibility == .hidden)
  #expect(window.titlebarSeparatorStyle == .none)
  #expect(window.titlebarAppearsTransparent)

  let trafficLightButtons: [NSButton?] = [
    window.standardWindowButton(.closeButton),
    window.standardWindowButton(.miniaturizeButton),
    window.standardWindowButton(.zoomButton),
  ]
  let trafficLightFrames: [NSRect] = trafficLightButtons.compactMap { button in
    guard let button else { return nil }
    return button.convert(button.bounds, to: nil)
  }
  #expect(trafficLightFrames.count == 3)
  #expect(trafficLightFrames.allSatisfy {
    settingsRoundedSurfaceContains(
      $0,
      in: surfaceFrame,
      cornerRadius: 22,
      margin: 12
    )
  })

  for destination in SettingsSection.allCases {
    let row = try #require(settingsSidebarRow(destination, in: outline))
    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    NotificationCenter.default.post(
      name: NSTableView.selectionDidChangeNotification,
      object: outline
    )
    await settleSettingsHost(host)

    #expect(outline.selectedRow == row)
    let currentSurfaceFrame = sidebarSurface.convert(sidebarSurface.bounds, to: nil)
    #expect(approximatelyEqual(currentSurfaceFrame, surfaceFrame))
    let sidebarFrame = sidebar.convert(sidebar.bounds, to: nil)
    #expect(!sidebar.isHidden)
    #expect(!sidebarFrame.isEmpty)
    #expect(trafficLightFrames.allSatisfy { !$0.intersects(sidebarFrame) })

    let detailScroll = try #require(
      settingsHostedScrollViews(of: host).first { $0 !== sidebarScroll }
    )
    let detailFrame = detailScroll.convert(detailScroll.bounds, to: nil)
    #expect(!detailFrame.isEmpty)
    #expect(trafficLightFrames.allSatisfy { !$0.intersects(detailFrame) })
  }

  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor
func DictationSettingsHostedWindowResetsDetailScrollWhenSwitchingDestinations()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: nil, capsuleEnabled: false)
  let size = NSSize(width: 840, height: 600)
  let host = NSHostingView(
    rootView: SettingsView(runtime: fixture.runtime)
      .environmentObject(fixture.appState)
      .environment(\.dynamicTypeSize, .large)
  )
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.titled, .resizable, .closable, .fullSizeContentView],
    backing: .buffered,
    defer: false
  )
  window.title = "Settings"
  window.toolbar = NSToolbar(identifier: "settings-hosted-scroll-reset-toolbar")
  window.toolbarStyle = .unifiedCompact
  window.contentView = host
  window.setContentSize(size)
  window.makeKeyAndOrderFront(nil)
  await settleSettingsHost(host)

  let contentLayoutRect = window.contentLayoutRect
  let outline = try #require(settingsSidebarTableView(of: host) as? NSOutlineView)
  let sidebarTable = try #require(settingsSidebarTableView(of: host))
  let sidebarScroll = try #require(settingsScrollViewAncestor(of: sidebarTable))

  func select(_ destination: SettingsSection) async throws {
    let row = try #require(settingsSidebarRow(destination, in: outline))
    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    NotificationCenter.default.post(
      name: NSTableView.selectionDidChangeNotification,
      object: outline
    )
    await settleSettingsHost(host)
  }

  try await select(.dictation)
  let initialDetailScroll = try #require(
    settingsHostedScrollViews(of: host).first { $0 !== sidebarScroll }
  )
  var previousDetailScroll = initialDetailScroll
  let initialDocument = try #require(initialDetailScroll.documentView)
  let initialBounds = initialDetailScroll.contentView.bounds
  let initialDocumentFrame = initialDocument.frame
  #expect(initialDocumentFrame.height > initialBounds.height + 1)

  let maximumOriginY = max(
    initialDocumentFrame.minY,
    initialDocumentFrame.maxY - initialBounds.height
  )
  initialDetailScroll.contentView.scroll(
    to: NSPoint(x: initialBounds.origin.x, y: maximumOriginY)
  )
  initialDetailScroll.reflectScrolledClipView(initialDetailScroll.contentView)
  await settleSettingsHost(host)
  #expect(
    initialDetailScroll.contentView.bounds.origin.y > initialBounds.origin.y + 1
  )

  for destination in SettingsSection.allCases {
    try await select(destination)

    let detailScroll = try #require(
      settingsHostedScrollViews(of: host).first { $0 !== sidebarScroll }
    )
    #expect(detailScroll !== previousDetailScroll)
    previousDetailScroll = detailScroll
    let detailDocument = try #require(detailScroll.documentView)
    let pageTitle = try #require(
      settingsView(withAccessibilityIdentifier: "settings-page-header", in: detailDocument)
    )
    let pageTitleFrame = pageTitle.convert(pageTitle.bounds, to: nil)
    #expect(!pageTitleFrame.isEmpty)
    let pageTitleTopGap = contentLayoutRect.maxY - pageTitleFrame.maxY
    #expect(pageTitleTopGap >= -1)
    #expect(pageTitleTopGap <= 20)
  }

  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor
func DictationSettingsReduceTransparencyKeepsHostedSurfacesDistinctInLightAndDark()
  async throws
{
  for (appearanceName, appearanceLabel) in [
    (NSAppearance.Name.aqua, "light"),
    (.darkAqua, "dark"),
  ] {
    let host = NSHostingView(
      rootView: ZStack {
        Color(nsColor: .windowBackgroundColor)
        HStack(spacing: 24) {
          SettingsSidebarSurface {
            Color.clear
              .frame(width: 180, height: 200)
          }
          .frame(width: 220, height: 260)

          SettingsSectionCard("Card") {
            Color.clear
              .frame(maxWidth: .infinity, minHeight: 200)
          }
          .frame(width: 220)
        }
        .padding(20)
      }
      .environment(\._accessibilityReduceTransparency, true)
      .frame(width: 520, height: 320)
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.appearance = NSAppearance(named: appearanceName)
    window.contentView = host
    window.orderFront(nil)
    await settleSettingsHost(host)

    let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: image)
    let scaleX = CGFloat(image.pixelsWide) / host.bounds.width
    let scaleY = CGFloat(image.pixelsHigh) / host.bounds.height
    func color(at point: NSPoint) throws -> NSColor {
      let x = min(image.pixelsWide - 1, max(0, Int(point.x * scaleX)))
      let y = min(image.pixelsHigh - 1, max(0, Int(point.y * scaleY)))
      return try #require(image.colorAt(x: x, y: y))
    }

    let rootColor = try color(at: NSPoint(x: 500, y: 160))
    let sidebarColor = try color(at: NSPoint(x: 130, y: 160))
    let cardColor = try color(at: NSPoint(x: 374, y: 160))
    #expect(settingsColorDistance(rootColor, sidebarColor) > 0.01)
    #expect(settingsColorDistance(sidebarColor, cardColor) > 0.01)

    if let captureDirectory = ProcessInfo.processInfo.environment[
      "FLECK_SETTINGS_REDUCE_TRANSPARENCY_CAPTURE_DIR"
    ] {
      let directory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let captureURL = directory.appendingPathComponent(
        "settings-reduce-transparency-" + appearanceLabel + ".png"
      )
      let pngData = try #require(
        image.representation(using: .png, properties: [:])
      )
      try pngData.write(to: captureURL)
    }

    window.contentView = nil
    window.orderOut(nil)
  }
}

@Test @MainActor
func DictationSettingsHostedWindowKeepsChromeAfterSameWindowResize() async throws {
  let fixture = try await RuntimeFixture(finalText: nil, capsuleEnabled: false)
  let host = NSHostingView(
    rootView: SettingsView(runtime: fixture.runtime)
      .environmentObject(fixture.appState)
      .environment(\.dynamicTypeSize, .large)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 840, height: 600),
    styleMask: [.titled, .resizable, .closable, .fullSizeContentView],
    backing: .buffered,
    defer: false
  )
  window.title = "Settings"
  let toolbar = NSToolbar(identifier: "settings-hosted-resize-toolbar")
  window.toolbar = toolbar
  window.toolbarStyle = .unifiedCompact
  window.contentView = host
  window.setContentSize(NSSize(width: 840, height: 600))
  window.makeKeyAndOrderFront(nil)
  await settleSettingsHost(host)

  for size in [
    NSSize(width: 840, height: 600),
    NSSize(width: 760, height: 520),
    NSSize(width: 840, height: 600),
  ] {
    window.setContentSize(size)
    await settleSettingsHost(host)

    let contentView = try #require(window.contentView)
    let contentFrame = contentView.convert(contentView.bounds, to: nil)
    let layoutRect = window.contentLayoutRect
    let sidebar = try #require(settingsSidebarTableView(of: host))
    let outline = try #require(sidebar as? NSOutlineView)
    let sidebarScroll = try #require(settingsScrollViewAncestor(of: sidebar))
    let sidebarSurface = try #require(settingsSidebarSurface(of: host))
    let sidebarSurfaceFrame = sidebarSurface.convert(sidebarSurface.bounds, to: nil)
    let topInset = contentFrame.maxY - sidebarSurfaceFrame.maxY
    let bottomInset = sidebarSurfaceFrame.minY - contentFrame.minY

    #expect(!contentFrame.isEmpty)
    #expect(!layoutRect.isEmpty)
    #expect(sidebarSurfaceFrame.minX >= contentFrame.minX + 8)
    #expect(sidebarSurfaceFrame.maxX <= contentFrame.maxX - 8)
    #expect(topInset >= 8)
    #expect(topInset <= 12)
    #expect(bottomInset >= 8)
    #expect(bottomInset <= 12)
    #expect(window.toolbar === toolbar)
    let toolbarItemIdentifiers = toolbar.items.map(\.itemIdentifier)
    #expect(!toolbarItemIdentifiers.contains(.toggleSidebar))
    #expect(!toolbarItemIdentifiers.contains(.sidebarTrackingSeparator))

    let trafficLightButtons: [NSButton?] = [
      window.standardWindowButton(.closeButton),
      window.standardWindowButton(.miniaturizeButton),
      window.standardWindowButton(.zoomButton),
    ]
    let trafficLightFrames = trafficLightButtons.compactMap { button in
      button.map { $0.convert($0.bounds, to: nil) }
    }
    #expect(trafficLightFrames.count == 3)
    #expect(trafficLightFrames.allSatisfy {
      settingsRoundedSurfaceContains(
        $0,
        in: sidebarSurfaceFrame,
        cornerRadius: 22,
        margin: 12
      )
    })

    let sidebarFrame = sidebar.convert(sidebar.bounds, to: nil)
    #expect(!sidebar.isHidden)
    #expect(!sidebarFrame.isEmpty)
    #expect(layoutRect.contains(sidebarFrame.center))
    #expect(trafficLightFrames.allSatisfy { !$0.intersects(sidebarFrame) })

    let detailScroll = try #require(
      settingsHostedScrollViews(of: host).first { $0 !== sidebarScroll }
    )
    let detailFrame = detailScroll.convert(detailScroll.bounds, to: nil)
    #expect(!detailFrame.isEmpty)
    #expect(layoutRect.contains(detailFrame.center))
    #expect(trafficLightFrames.allSatisfy { !$0.intersects(detailFrame) })

    let detailDocument = try #require(detailScroll.documentView)
    let pageTitle = try #require(
      settingsView(withAccessibilityIdentifier: "settings-page-header", in: detailDocument)
    )
    let pageTitleFrame = pageTitle.convert(pageTitle.bounds, to: nil)
    let pageTitleTopGap = layoutRect.maxY - pageTitleFrame.maxY
    #expect(!pageTitleFrame.isEmpty)
    #expect(pageTitleTopGap >= -1)
    #expect(pageTitleTopGap <= 20)
    #expect(outline.numberOfRows > 0)
  }

  window.contentView = nil
  window.orderOut(nil)
}

@MainActor
private func settingsSidebarDescendants(of view: NSView) -> [NSView] {
  view.subviews + view.subviews.flatMap(settingsSidebarDescendants)
}

@MainActor
private func settingsSidebarTableView(of view: NSView) -> NSTableView? {
  settingsSidebarDescendants(of: view).compactMap { $0 as? NSTableView }.first
}

@MainActor
private func settingsNativeSplitViewController(of view: NSView) -> NSSplitViewController? {
  var responder: NSResponder? = view
  while let current = responder {
    if let controller = current as? NSSplitViewController {
      return controller
    }
    responder = current.nextResponder
  }

  for subview in view.subviews {
    if let controller = settingsNativeSplitViewController(of: subview) {
      return controller
    }
  }
  return nil
}

@MainActor
private func settingsSidebarSurface(of view: NSView) -> NSView? {
  if view.accessibilityIdentifier() == "settings-sidebar-surface" {
    return view
  }
  return settingsSidebarDescendants(of: view)
    .first { $0.accessibilityIdentifier() == "settings-sidebar-surface" }
}

@MainActor
private func settingsView(withAccessibilityIdentifier identifier: String, in view: NSView)
  -> NSView?
{
  if view.accessibilityIdentifier() == identifier {
    return view
  }
  return settingsSidebarDescendants(of: view)
    .first { $0.accessibilityIdentifier() == identifier }
}

@MainActor
private func settingsRoundedSurfaceContains(
  _ candidate: NSRect,
  in surface: NSRect,
  cornerRadius: CGFloat,
  margin: CGFloat
) -> Bool {
  guard surface.insetBy(dx: margin, dy: margin).contains(candidate) else { return false }
  let path = NSBezierPath(
    roundedRect: surface,
    xRadius: cornerRadius,
    yRadius: cornerRadius
  )
  let corners = [
    NSPoint(x: candidate.minX, y: candidate.minY),
    NSPoint(x: candidate.minX, y: candidate.maxY),
    NSPoint(x: candidate.maxX, y: candidate.minY),
    NSPoint(x: candidate.maxX, y: candidate.maxY),
  ]
  return corners.allSatisfy(path.contains)
}

@MainActor
private func settingsSidebarRow(_ section: SettingsSection, in outline: NSOutlineView) -> Int? {
  let selectableRows = (0..<outline.numberOfRows).filter { row in
    guard let item = outline.item(atRow: row) else { return false }
    return !(outline.delegate?.outlineView?(outline, isGroupItem: item) ?? false)
  }
  guard let sectionIndex = SettingsSection.allCases.firstIndex(of: section),
    selectableRows.indices.contains(sectionIndex)
  else {
    return nil
  }
  return selectableRows[sectionIndex]
}

@MainActor
private func settingsHostedScrollViews(of view: NSView) -> [NSScrollView] {
  var scrollViews: [NSScrollView] = []
  if let scrollView = view as? NSScrollView {
    scrollViews.append(scrollView)
  }
  for subview in view.subviews {
    scrollViews.append(contentsOf: settingsHostedScrollViews(of: subview))
  }
  return scrollViews
}

@MainActor
private func settingsScrollViewAncestor(of view: NSView) -> NSScrollView? {
  var current = view.superview
  while let candidate = current {
    if let scrollView = candidate as? NSScrollView {
      return scrollView
    }
    current = candidate.superview
  }
  return nil
}

private extension NSRect {
  var center: NSPoint {
    NSPoint(x: midX, y: midY)
  }
}

private func approximatelyEqual(_ lhs: NSRect, _ rhs: NSRect, tolerance: CGFloat = 1) -> Bool {
  abs(lhs.minX - rhs.minX) <= tolerance
    && abs(lhs.minY - rhs.minY) <= tolerance
    && abs(lhs.width - rhs.width) <= tolerance
    && abs(lhs.height - rhs.height) <= tolerance
}

private func settingsColorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
  guard let lhs = lhs.usingColorSpace(.sRGB), let rhs = rhs.usingColorSpace(.sRGB) else {
    return 0
  }
  let red = lhs.redComponent - rhs.redComponent
  let green = lhs.greenComponent - rhs.greenComponent
  let blue = lhs.blueComponent - rhs.blueComponent
  return (red * red + green * green + blue * blue).squareRoot()
}

@Test func DictationSettingsSeparatesVocabularyAndOnlySurfacesAvailabilityProblems() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(source.contains("case vocabulary = \"Vocabulary\""))
  #expect(source.contains("case .vocabulary:"))
  #expect(source.contains("PersonalDictionarySettingsSection("))
  #expect(source.contains("private var availabilityIssues"))
  #expect(source.contains(".filter { !$0.available }"))
  #expect(source.contains("isReady ? \"Ready\" : \"Needs attention\""))
  #expect(!source.contains("Section(\"Availability\")"))

  let dictationStart = try #require(source.range(of: "private var dictation:"))
  let vocabularyStart = try #require(
    source.range(of: "private var vocabulary:", range: dictationStart.upperBound..<source.endIndex)
  )
  let dictationSource = source[dictationStart.lowerBound..<vocabularyStart.lowerBound]
  #expect(!dictationSource.contains("PersonalDictionarySettingsSection"))
}

@Test @MainActor func DictationSettingsPendingRouteIsDurableAndConsumedOnce() async throws {
  let fixture = try await RuntimeFixture(finalText: nil, capsuleEnabled: false)
  fixture.runtime.requestSettings(.dictation)
  #expect(fixture.runtime.pendingSettingsSection == .dictation)
  #expect(fixture.runtime.consumePendingSettingsSection() == .dictation)
  #expect(fixture.runtime.consumePendingSettingsSection() == nil)
}

@Test @MainActor func DictationSettingsBridgeLifecycleOpensOnceAndSettingsViewConsumesRoute()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: nil, capsuleEnabled: false)
  var openSettingsCalls = 0

  fixture.runtime.requestSettings(.dictation)
  #expect(fixture.runtime.pendingSettingsSection == .dictation)
  #expect(openSettingsCalls == 0)

  let bridge = DictationSettingsEnvironmentBridge(
    runtime: fixture.runtime,
    openSettingsAction: { openSettingsCalls += 1 }
  ) {
    Text("Resident bridge")
  }
  let bridgeHost = NSHostingView(rootView: bridge)
  let bridgeWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  bridgeWindow.contentView = bridgeHost
  bridgeWindow.makeKeyAndOrderFront(nil)
  await settleSettingsHost(bridgeHost)

  #expect(openSettingsCalls == 1)
  #expect(fixture.runtime.pendingSettingsSection == .dictation)

  let settingsHost = NSHostingView(
    rootView: SettingsView(runtime: fixture.runtime)
      .environmentObject(fixture.appState)
  )
  let settingsWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  settingsWindow.contentView = settingsHost
  settingsWindow.makeKeyAndOrderFront(nil)
  await settleSettingsHost(settingsHost)

  #expect(fixture.runtime.pendingSettingsSection == nil)
  #expect(openSettingsCalls == 1)

  settingsWindow.contentView = nil
  settingsWindow.orderOut(nil)
  bridgeWindow.contentView = nil
  bridgeWindow.orderOut(nil)
}

@MainActor
private func settleSettingsHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@Test @MainActor func DictationRuntimeUpdatesRailAccentWithoutRewritingPreference() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  await fixture.runtime.awaitStartupAssessment()

  let accentHex = "#E64A19"
  fixture.appState.updatePreferences { $0.accentHex = accentHex }
  fixture.runtime.preferencesDidChange()

  #expect(fixture.runtime.capsuleController.presentationModel.colors.accentHex == accentHex)
  #expect(fixture.appState.preferences.accentHex == accentHex)
}

@Test @MainActor func DictationRuntimeMapsTheRealSaveBoundaryToSaving() {
  let id = UUID(uuidString: "7EF3CE15-48DD-42E2-9A58-4F0C0A5A0783")!
  let event = DictationCoordinatorEvent(
    phase: .routing,
    terminal: nil,
    context: DictationCoordinatorContext(
      sessionID: id,
      mode: .smartCapture,
      pipelineStage: .save,
      cleanupOutcome: .cleaned,
      failureStage: nil
    )
  )

  let context = DictationRuntime.capsuleContext(for: event)
  #expect(context.status == .saving)
  #expect(context.status.presentation.visibleText == "Saving")
  #expect(context.pipelineStage == .save)
}

@Test @MainActor func DictationRuntimePointerStartPublishesOwnerContextImmediately() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.runtime.shortcutController.startPointerHandsFree())
  for _ in 0..<100 {
    if fixture.runtime.capsuleController.currentContext.sessionID != nil { break }
    await Task.yield()
  }

  let context = fixture.runtime.capsuleController.currentContext
  #expect(context.status == .arming || context.status == .listening)
  #expect(context.sessionID != nil)
  #expect(context.trigger == .pointer)
  #expect(context.mode == .smartCapture)
  #expect(context.isHandsFree)

  await fixture.runtime.shortcutController.cancelOwnedSession()
  await fixture.runtime.shortcutController.waitForTerminalObservation()
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
}

@Test @MainActor func DictationRuntimeActionBearingFailureDoesNotScheduleReturnTimer() async throws {
  let sleeper = RuntimeCapsuleSleeper()
  let saver = RuntimeSaving(error: DictationFailure.saveFailed)
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    capsuleEnabled: true,
    saving: saver,
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  for _ in 0..<100 {
    if fixture.runtime.phase == .failed("Unable to save dictation.") { break }
    await Task.yield()
  }

  #expect(fixture.runtime.phase == .failed("Unable to save dictation."))
  #expect(fixture.runtime.recoveryAction == .openHistory)
  #expect(await sleeper.requestedDurations.isEmpty)
  await fixture.runtime.shortcutController.waitForTerminalObservation()
  #expect(fixture.runtime.currentCapsuleStatus == .failed("Unable to save dictation."))
  await fixture.runtime.cancel()
}

@Test @MainActor func DictationSettingsHistoryClearRequiresConfirmation() {
  let record = DictationHistoryRecord(
    id: UUID(),
    mode: .smartCapture,
    engine: .standard,
    startedAt: Date(timeIntervalSince1970: 1),
    completedAt: Date(timeIntervalSince1970: 2),
    rawTranscript: "raw",
    cleanedTranscript: "clean",
    cleanupOutcome: .cleaned,
    insertionOutcome: .unsaved
  )
  let controller = DictationHistoryController(
    records: [record],
    load: { [record] },
    save: { _ in },
    delete: { _ in },
    clear: {}
  )
  let model = DictationHistoryViewModel(controller: controller)

  model.requestClear()

  #expect(model.pendingConfirmation == .clear)
  #expect(controller.records == [record])
}

@Test @MainActor func DictationSettingsHistoryRollsBackOptimisticClearAndDelete() async {
  let first = DictationHistoryRecord(
    id: UUID(),
    mode: .smartCapture,
    engine: .standard,
    startedAt: Date(timeIntervalSince1970: 1),
    completedAt: Date(timeIntervalSince1970: 2),
    rawTranscript: "first",
    cleanupOutcome: .usedRaw,
    insertionOutcome: .unsaved
  )
  let second = DictationHistoryRecord(
    id: UUID(),
    mode: .focused,
    engine: .enhancedLocal,
    startedAt: Date(timeIntervalSince1970: 3),
    completedAt: Date(timeIntervalSince1970: 4),
    rawTranscript: "second",
    cleanedTranscript: "Second.",
    cleanupOutcome: .cleaned,
    insertionOutcome: .saved
  )
  let deleteGate = DictationTestGate()
  let clearGate = DictationTestGate()
  let controller = DictationHistoryController(
    records: [second, first],
    load: { [second, first] },
    save: { _ in },
    delete: { _ in
      await deleteGate.wait()
      throw DictationSettingsTestError.failed
    },
    clear: {
      await clearGate.wait()
      throw DictationSettingsTestError.failed
    }
  )
  let model = DictationHistoryViewModel(controller: controller)

  model.requestDelete(first.id)
  let deletion = Task { await model.confirmRemoval() }
  await deleteGate.waitUntilWaiting()
  #expect(controller.records == [second])
  await deleteGate.open()
  await deletion.value
  #expect(controller.records == [second, first])

  model.requestClear()
  let clearing = Task { await model.confirmRemoval() }
  await clearGate.waitUntilWaiting()
  #expect(controller.records.isEmpty)
  await clearGate.open()
  await clearing.value
  #expect(controller.records == [second, first])
}

@Test func DictationToolbarMakesProcessingPrimaryActionsInertButKeepsCancel() {
  let expected: [(DictationPhase, String)] = [
    (.finalizing, "Finalizing Dictation"),
    (.cleaning, "Cleaning Dictation"),
    (.routing, "Routing Dictation"),
  ]

  for (phase, label) in expected {
    let presentation = DictationToolbarPresentation(phase: phase)
    #expect(presentation.primaryLabel == label)
    #expect(presentation.primaryAction == nil)
    #expect(presentation.canCancel)
  }
}

@Test @MainActor func DictationCapsuleMapsTerminalModeCleanupDestinationAndFailures() {
  let destination = DictationDestination(noteID: UUID(), title: "Ideas")
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .saved(destination),
    terminal: .saved(mode: .smartCapture, cleanup: .cleaned, destination: destination)
  )) == .saved(destination: "Ideas"))
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .idle,
    terminal: .saved(mode: .focused, cleanup: .usedRaw, destination: nil)
  )) == .savedWithoutCleanup(destination: "current note"))
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .failed("No speech"),
    terminal: .failed("No speech")
  )) == .failed("No speech"))
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .finalizing,
    terminal: nil
  )) == .finalizing)
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .cleaning,
    terminal: nil
  )) == .cleaning)
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .routing,
    terminal: nil
  )) == .routing)
  #expect(DictationRuntime.capsuleStatus(for: .init(
    phase: .idle,
    terminal: .cancelled
  )) == .idle)
}

@Test func DictationHistoryRowDoesNotMislabelOrDuplicateRawFallback() {
  let raw = historyRecord(raw: "raw", cleaned: nil, cleanup: .usedRaw)
  let rawPresentation = DictationHistoryRowPresentation(record: raw)
  #expect(rawPresentation.primaryTitle == "Raw fallback")
  #expect(rawPresentation.primaryTranscript == "raw")
  #expect(rawPresentation.rawTranscript == nil)
  #expect(!rawPresentation.canCopyClean)

  let cleaned = historyRecord(raw: "raw", cleaned: "Clean.", cleanup: .cleaned)
  let cleanPresentation = DictationHistoryRowPresentation(record: cleaned)
  #expect(cleanPresentation.primaryTitle == "Cleaned")
  #expect(cleanPresentation.primaryTranscript == "Clean.")
  #expect(cleanPresentation.rawTranscript == "raw")
  #expect(cleanPresentation.canCopyClean)
}

@Test func dictationModifierSettingsShowsAllPhysicalKeysAndItsRunningStatus() {
  let presentation = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .running,
    canChange: true
  )

  #expect(presentation.rows.count == 7)
  #expect(presentation.recommended == .rightOption)
  #expect(presentation.statusCopy == "Input Monitoring enabled")
  #expect(presentation.isPickerEnabled)
  #expect(presentation.recoveryAction == nil)
}

@Test func dictationModifierSettingsShowsDeniedUnavailableRetryAndActiveCaptureCopy() {
  let denied = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .unauthorized,
    canChange: true
  )
  #expect(denied.statusCopy.contains("required"))
  #expect(denied.recoveryAction == .enableInputMonitoring)
  #expect(denied.recoveryButtonTitle == "Enable Right Option")

  let unavailable = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .stopped,
    canChange: true
  )
  #expect(unavailable.statusCopy.contains("unavailable"))

  let failed = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .failed,
    canChange: true
  )
  #expect(failed.statusCopy.contains("could not start"))
  #expect(failed.recoveryAction == .retry)
  #expect(failed.recoveryButtonTitle == "Retry Right Option")

  let activeCapture = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .running,
    canChange: false
  )
  #expect(!activeCapture.isPickerEnabled)
  #expect(activeCapture.statusCopy.contains("finish"))
  #expect(activeCapture.recoveryButtonTitle == nil)

  let deniedDuringCapture = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .unauthorized,
    canChange: false
  )
  #expect(deniedDuringCapture.recoveryButtonTitle == nil)
}

@Test func notesPanelExposesModifierMonitoringRecoveryBesideTheEditor() throws {
  let testsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: testsDirectory.appendingPathComponent("Sources/FleckApp/NotesPanel.swift")
  )

  #expect(source.contains("modifierRecoveryPresentation"))
  #expect(source.contains("await dictationRuntime.recoverModifierMonitoring()"))
}

@Test func notesPanelBannerPolicyOmitsRoutineUndoWhileKeepingFailures() {
  let modifier = NotesPanelBannerOccurrence.modifierRecovery(
    statusCopy: "Input Monitoring is required",
    recoveryButtonTitle: "Enable Right Option"
  )
  let captureFailure = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )

  let active = NotesPanelBannerPolicy.activeOccurrences(
    modifierRecovery: modifier,
    captureFailure: captureFailure,
    routineRecoveryAction: .undo,
    agentChange: nil
  )

  #expect(active == [modifier, captureFailure])
}

@Test func notesPanelBannerDismissalInitiallyPresentsAllActiveOccurrences() {
  let modifier = NotesPanelBannerOccurrence.modifierRecovery(
    statusCopy: "Input Monitoring is required",
    recoveryButtonTitle: "Enable Right Option"
  )
  let captureFailure = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )
  var state = NotesPanelBannerDismissalState()
  state.reconcile(activeOccurrences: [modifier, captureFailure])

  #expect(state.isPresented(modifier))
  #expect(state.isPresented(captureFailure))
}

@Test func notesPanelBannerDismissalHidesOnlyTheExactActiveIdentity() {
  let modifier = NotesPanelBannerOccurrence.modifierRecovery(
    statusCopy: "Input Monitoring is required",
    recoveryButtonTitle: "Enable Right Option"
  )
  let changedModifier = NotesPanelBannerOccurrence.modifierRecovery(
    statusCopy: "Input Monitoring could not start",
    recoveryButtonTitle: "Retry Right Option"
  )
  let captureFailure = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )
  var state = NotesPanelBannerDismissalState()
  state.reconcile(activeOccurrences: [modifier, changedModifier, captureFailure])
  state.dismiss(modifier)

  #expect(!state.isPresented(modifier))
  #expect(state.isPresented(changedModifier))
  #expect(state.isPresented(captureFailure))
}

@Test func notesPanelBannerDismissalForgetsIdentityAfterDisappearanceBeforeRecurrence() {
  let occurrence = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )
  var state = NotesPanelBannerDismissalState()
  state.reconcile(activeOccurrences: [occurrence])
  state.dismiss(occurrence)
  #expect(!state.isPresented(occurrence))

  state.reconcile(activeOccurrences: [])
  state.reconcile(activeOccurrences: [occurrence])

  #expect(state.isPresented(occurrence))
}

@Test func notesPanelBannerDismissalPresentsIdenticalCaptureFailureAfterSynchronousClearAndReemit() {
  let occurrence = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )
  var state = NotesPanelBannerDismissalState()
  state.reconcile(activeOccurrences: [occurrence])
  state.dismiss(occurrence)
  #expect(!state.isPresented(occurrence))

  // The source emitted nil and re-emitted this same failure before a render.
  state.forgetDismissedOccurrences(in: .captureFailure)
  state.reconcile(activeOccurrences: [occurrence])

  #expect(state.isPresented(occurrence))
}

@Test func notesPanelBannerDismissalResetsModifierOnCaptureArmingWithoutClearingCaptureFailure() {
  let modifier = NotesPanelBannerOccurrence.modifierRecovery(
    statusCopy: "Input Monitoring is required",
    recoveryButtonTitle: "Enable Right Option"
  )
  let captureFailure = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )
  var state = NotesPanelBannerDismissalState()
  state.reconcile(activeOccurrences: [modifier, captureFailure])
  state.dismiss(modifier)
  state.dismiss(captureFailure)
  #expect(!state.isPresented(modifier))
  #expect(!state.isPresented(captureFailure))

  state.dictationPhaseDidEmit(.arming)

  #expect(state.isPresented(modifier))
  #expect(!state.isPresented(captureFailure))
}

@Test func dictationModifierSettingsExplainsFnAndConflictProneKeys() {
  let function = DictationModifierSettingsPresentation(
    selected: .function,
    monitorStatus: .running,
    canChange: true
  )
  #expect(function.guidanceCopy?.contains("best-effort") == true)

  for key in [
    DictationModifierKey.leftCommand,
    .rightCommand,
    .leftOption,
    .leftControl,
    .rightControl,
  ] {
    let presentation = DictationModifierSettingsPresentation(
      selected: key,
      monitorStatus: .running,
      canChange: true
    )
    #expect(presentation.guidanceCopy?.contains("conflict") == true)
  }
}

@Test func settingsSourceDoesNotInstantiateTheLegacyShortcutRecorder() throws {
  let testsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: testsDirectory.appendingPathComponent("Sources/FleckApp/SettingsView.swift")
  )

  #expect(!source.contains("DictationShortcutRecorder("))
  #expect(source.contains("Button(\"Enable Input Monitoring\")"))
  #expect(source.contains("await runtime.recoverModifierMonitoring()"))
  #expect(source.contains("runtime.openSystemSettings(settings)"))
}

@Test @MainActor func DictationEditorRegistryUsesOnlyTheActualFirstResponder() {
  let registry = DictationEditorRegistry()
  let body = EditorCommands()
  let bodyView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let titleView = NSTextField(frame: NSRect(x: 0, y: 90, width: 200, height: 24))
  let otherView = NSTextField(frame: NSRect(x: 0, y: 115, width: 80, height: 24))
  let window = DictationKeyWindowProbe(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 140),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  let content = NSView(frame: window.contentView?.bounds ?? .zero)
  content.addSubview(bodyView)
  content.addSubview(titleView)
  content.addSubview(otherView)
  window.contentView = content
  window.reportsKey = true
  body.textView = bodyView
  registry.register(body)

  window.makeFirstResponder(titleView)
  #expect(registry.focusedEditor() == nil)
  window.makeFirstResponder(bodyView)
  #expect(registry.focusedEditor() === body)
  window.makeFirstResponder(otherView)
  #expect(registry.focusedEditor() == nil)
}

@Test @MainActor func DictationEditorRegistryRejectsRetainedResponderInNonKeyWindow() {
  let registry = DictationEditorRegistry()
  let body = EditorCommands()
  let bodyView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let window = DictationKeyWindowProbe(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = bodyView
  window.reportsKey = false
  body.textView = bodyView
  registry.register(body)

  #expect(window.makeFirstResponder(bodyView))
  #expect(!window.isKeyWindow)
  #expect(window.firstResponder === bodyView)
  #expect(registry.focusedEditor() == nil)
}

private final class DictationKeyWindowProbe: NSWindow {
  var reportsKey = false

  override var isKeyWindow: Bool { reportsKey }
}

@Test @MainActor func DictationHistoryControllerSharesWritesAcrossPresentationsAndSettingsClear()
  async
{
  let record = historyRecord(raw: "raw", cleaned: "Clean.", cleanup: .cleaned)
  let controller = DictationHistoryController(
    records: [record],
    load: { [record] },
    save: { _ in },
    delete: { _ in },
    clear: {}
  )
  let first = DictationHistoryViewModel(controller: controller)
  let second = DictationHistoryViewModel(controller: controller)

  first.requestDelete(record.id)
  await first.confirmRemoval()
  #expect(controller.records.isEmpty)
  #expect(second.controller.records.isEmpty)

  await controller.save(record)
  await controller.clear()
  #expect(first.controller.records.isEmpty)
  #expect(second.controller.records.isEmpty)
}

@Test @MainActor func DictationHistoryControllerSerializesOverlappingMutationsAndRollsBackOnlyFailure()
  async
{
  let first = historyRecord(raw: "first", cleaned: nil, cleanup: .usedRaw)
  let second = historyRecord(raw: "second", cleaned: nil, cleanup: .usedRaw)
  let gate = DictationTestGate()
  let log = DictationOperationLog()
  let controller = DictationHistoryController(
    records: [first, second],
    load: { [first, second] },
    save: { _ in },
    delete: { id in
      await log.append("delete-\(id)")
      await gate.wait()
      throw DictationSettingsTestError.failed
    },
    clear: {
      await log.append("clear")
    }
  )

  let deletion = Task { await controller.delete(first.id) }
  await gate.waitUntilWaiting()
  let clear = Task { await controller.clear() }
  await Task.yield()
  #expect(await log.values.count == 1)
  await gate.open()
  _ = await deletion.value
  await clear.value

  #expect(await log.values == ["delete-\(first.id)", "clear"])
  #expect(controller.records.isEmpty)
  #expect(controller.errorMessage == nil)
}

@Test @MainActor func DictationHistoryControllerSharesFailureAndRestoresOnlyFailedOperation()
  async
{
  let first = historyRecord(raw: "first", cleaned: nil, cleanup: .usedRaw)
  let second = historyRecord(raw: "second", cleaned: nil, cleanup: .usedRaw)
  let controller = DictationHistoryController(
    records: [first, second],
    load: { [first, second] },
    save: { _ in },
    delete: { _ in throw DictationSettingsTestError.failed },
    clear: {}
  )
  let otherPresentation = DictationHistoryViewModel(controller: controller)

  await controller.delete(first.id)

  #expect(controller.records == [first, second])
  #expect(controller.errorMessage?.contains("Could not update") == true)
  #expect(otherPresentation.controller.errorMessage == controller.errorMessage)
}

@Test @MainActor func DictationHistoryDelayedLoadCannotResurrectClearedRowsAcrossScenes() async {
  let record = historyRecord(raw: "private", cleaned: nil, cleanup: .usedRaw)
  let loadGate = DictationTestGate()
  let controller = DictationHistoryController(
    records: [record],
    load: {
      await loadGate.wait()
      return [record]
    },
    save: { _ in },
    delete: { _ in },
    clear: {}
  )
  let otherScene = DictationHistoryViewModel(controller: controller)

  let loading = Task { await controller.load() }
  await loadGate.waitUntilWaiting()
  let clearing = Task { await controller.clear() }
  await Task.yield()
  await loadGate.open()
  await loading.value
  await clearing.value

  #expect(controller.records.isEmpty)
  #expect(otherScene.controller.records.isEmpty)
}

@Test @MainActor func DictationHistoryDelayedLoadCannotResurrectDeletedRowsAcrossScenes() async {
  let first = historyRecord(raw: "first", cleaned: nil, cleanup: .usedRaw)
  let second = historyRecord(raw: "second", cleaned: nil, cleanup: .usedRaw)
  let loadGate = DictationTestGate()
  let controller = DictationHistoryController(
    records: [first, second],
    load: {
      await loadGate.wait()
      return [first, second]
    },
    save: { _ in },
    delete: { _ in },
    clear: {}
  )
  let otherScene = DictationHistoryViewModel(controller: controller)

  let loading = Task { await controller.load() }
  await loadGate.waitUntilWaiting()
  let deleting = Task { await controller.delete(first.id) }
  await Task.yield()
  await loadGate.open()
  await loading.value
  _ = await deleting.value

  #expect(controller.records == [second])
  #expect(otherScene.controller.records == [second])
}

@Test @MainActor func DictationRuntimeAssessesOnceBeforeAuthoritativeEnhancedDowngrade() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", startupBlocked: true)
  fixture.appState.preferences.dictationSpeechEngine = .enhancedLocal

  #expect(fixture.appState.preferences.dictationSpeechEngine == .enhancedLocal)
  await fixture.startupGate.waitUntilWaiting()
  #expect(await fixture.startupLog.value == 1)
  let firstWaiter = Task { await fixture.runtime.awaitStartupAssessment() }
  let secondWaiter = Task { await fixture.runtime.awaitStartupAssessment() }
  await fixture.startupGate.open()
  await firstWaiter.value
  await secondWaiter.value

  #expect(fixture.appState.preferences.dictationSpeechEngine == .standard)
  #expect(await fixture.startupLog.value == 1)
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
@Test @MainActor
func DictationRuntimeAutomaticallySelectsInstalledRecommendationOverStalePreference() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let installed = AdmittedModelSettingsPresentation(snapshot: .init(
    recommendation: .recommended(descriptor),
    phase: .installed,
    lastError: nil
  ))
  let notInstalled = AdmittedModelSettingsPresentation(snapshot: .init(
    recommendation: .recommended(descriptor),
    phase: .ready,
    lastError: nil
  ))

  #expect(
    DictationRuntime.effectiveEngine(
      preference: .standard,
      presentation: installed
    ) == .enhancedLocal
  )
  #expect(
    DictationRuntime.effectiveEngine(
      preference: .enhancedLocal,
      presentation: notInstalled
    ) == .standard
  )
}
#endif

@Test @MainActor
func DictationRuntimeRoutesStaleEnhancedPreferenceToAppleSpeechWhenAdmittedInstallerIsBuiltIn()
  async throws
{
  let speechRequests = RuntimeCounter()
  let permissionController = DictationPermissionController(
    microphoneStatus: { .authorized },
    speechStatus: { .notDetermined },
    requestMicrophone: { true },
    requestSpeech: {
      await speechRequests.increment()
      return true
    }
  )
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    permissionController: permissionController
  )

  fixture.appState.updatePreferences { $0.dictationSpeechEngine = .enhancedLocal }
  await fixture.runtime.requestPermissionsAfterShortcutSetup()
  #expect(await speechRequests.value == 1)

  await fixture.runtime.toggle()
  #expect(fixture.provider.requestedKinds == [.standard])
  await fixture.runtime.cancel()
}

@Test @MainActor func DictationRuntimeWaitsForLoadedModifierWithoutRequestingAccess()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    preferredModifier: .leftCommand,
    waitForInitialLoadBeforeRuntime: false
  )

  #expect(fixture.runtime.actualModifier == nil)
  #expect(fixture.monitor.requestCount == 0)

  await fixture.appState.waitUntilInitialLoad()
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.runtime.actualModifier == .leftCommand)
  #expect(fixture.monitor.requestCount == 0)
}

@Test @MainActor func DictationRuntimeLoadsCapsuleVisibilityAndDockBeforeFirstPresentation()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    capsuleEnabled: false,
    preferredDock: .left,
    waitForInitialLoadBeforeRuntime: false
  )

  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(!fixture.runtime.capsuleController.panel.isVisible)

  await fixture.appState.waitUntilInitialLoad()
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(!fixture.runtime.capsuleController.panel.isVisible)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
  #expect(fixture.runtime.capsuleController.currentDock == .left)
  #expect(fixture.runtime.capsuleController.panel.isVisible)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(!fixture.runtime.capsuleController.panel.isVisible)
}

@Test @MainActor func DictationRuntimeSyncsCapsuleWhenModifierMonitorFailsToStart()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    capsuleEnabled: true,
    preferredModifier: .leftCommand,
    waitForInitialLoadBeforeRuntime: false,
    blockInitialLoad: true
  )
  let blocker = try #require(fixture.initialLoadBlocker)
  fixture.monitor.startError = DictationSettingsTestError.failed

  blocker.release()
  await fixture.appState.waitUntilInitialLoad()
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.runtime.modifierMonitorState == .failed)
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
  #expect(fixture.runtime.capsuleController.panel.isVisible)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(!fixture.runtime.capsuleController.panel.isVisible)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
  #expect(fixture.runtime.capsuleController.panel.isVisible)
}

@Test @MainActor func DictationRuntimeBuffersCapsuleEventsUntilLoadedPreferencesAreApplied()
  async throws
{
  for capsuleEnabled in [false, true] {
    let fixture = try await RuntimeFixture(
      finalText: "saved",
      capsuleEnabled: capsuleEnabled,
      preferredDock: .left,
      waitForInitialLoadBeforeRuntime: false,
      blockInitialLoad: true
    )
    guard let loadBlocker = fixture.initialLoadBlocker else {
      Issue.record("Expected a deterministic initial-load blocker")
      continue
    }
    defer { loadBlocker.release() }
    for _ in 0..<1_000 {
      if loadBlocker.hasBlocked { break }
      await Task.yield()
    }
    guard loadBlocker.hasBlocked else {
      Issue.record("Initial load did not reach the deterministic blocker")
      continue
    }
    let orderProbe = RuntimeCapsuleOrderProbe(panel: fixture.runtime.capsuleController.panel)
    defer { orderProbe.stop() }

    await fixture.runtime.toggle()

    #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))
    #expect(fixture.runtime.currentCapsuleStatus == nil)
    #expect(!fixture.runtime.capsuleController.panel.isVisible)
    #expect(orderProbe.count == 0)

    loadBlocker.release()
    await fixture.appState.waitUntilInitialLoad()
    await fixture.runtime.awaitStartupAssessment()

    #expect(fixture.runtime.capsuleController.currentDock == .left)
    if capsuleEnabled {
      #expect(fixture.runtime.currentCapsuleStatus == .listening)
      #expect(fixture.runtime.capsuleController.panel.isVisible)
      #expect(orderProbe.count == 1)
    } else {
      #expect(fixture.runtime.currentCapsuleStatus == nil)
      #expect(!fixture.runtime.capsuleController.panel.isVisible)
      #expect(orderProbe.count == 0)

      fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
      fixture.runtime.preferencesDidChange()
      #expect(fixture.runtime.currentCapsuleStatus == .listening)
      #expect(fixture.runtime.capsuleController.panel.isVisible)
      #expect(orderProbe.count == 1)
    }

    await fixture.runtime.cancel()
  }
}

@Test @MainActor func DictationRuntimeReturnTimersCannotReplaceNewerListeningState()
  async throws
{
  for (finalText, delay) in [
    ("saved", Duration.milliseconds(1_600)),
    (nil, Duration.seconds(3)),
  ] as [(String?, Duration)] {
    let sleeper = RuntimeCapsuleSleeper()
    let fixture = try await RuntimeFixture(
      finalText: finalText,
      capsuleEnabled: true,
      capsuleSleeper: { duration in await sleeper.sleep(duration) }
    )
    await fixture.runtime.awaitStartupAssessment()

    await fixture.runtime.toggle()
    await fixture.runtime.toggle()
    await sleeper.waitForRequest()
    #expect(await sleeper.requestedDurations == [delay])

    await fixture.runtime.toggle()
    #expect(fixture.runtime.currentCapsuleStatus == .listening)
    await sleeper.resumeAll()
    await Task.yield()
    #expect(fixture.runtime.currentCapsuleStatus == .listening)

    await fixture.runtime.cancel()
    #expect(fixture.runtime.currentCapsuleStatus == .idle)
  }
}

@Test @MainActor func DictationRuntimeKeepsAmbiguousCaptureVisibleUntilExactChoiceCompletes()
  async throws
{
  let sleeper = RuntimeCapsuleSleeper()
  let project = Note(title: "Projects", body: "Roadmap and milestones")
  let personal = Note(title: "Personal", body: "Weekend plans")
  let fixture = try await RuntimeFixture(
    finalText: "Plan the launch",
    capsuleEnabled: true,
    routingNotes: [project, personal],
    ambiguousRouting: true,
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()

  let ambiguity = try #require(fixture.runtime.coordinator.routingAmbiguity)
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Inbox"))
  #expect(fixture.runtime.capsuleController.currentChooser?.captureID == ambiguity.captureID)
  #expect(fixture.runtime.recoveryAction == .undo)
  #expect(fixture.runtime.capsuleController.panel.allowsActions)
  #expect(await sleeper.requestedDurations.isEmpty)

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: ambiguity.captureID,
    noteID: project.id
  )
  for _ in 0..<1_000 {
    if fixture.runtime.coordinator.routingAmbiguity == nil { break }
    await Task.yield()
  }

  #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Projects"))
  #expect(fixture.runtime.capsuleController.currentChooser == nil)
  #expect(fixture.appState.workspace.notes.first(where: { $0.id == project.id })?.body.contains("Plan the launch") == true)
  #expect(fixture.appState.workspace.notes.first(where: {
    $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
  })?.body.contains("Plan the launch") == false)
  await sleeper.waitForRequest()
  #expect(await sleeper.requestedDurations == [.milliseconds(1_600)])
  await sleeper.resumeAll()
}

@Test @MainActor func DictationRuntimeReplaysValidChooserAndInvalidatesItForNewCapture()
  async throws
{
  let project = Note(title: "Projects", body: "Roadmap")
  let personal = Note(title: "Personal", body: "Weekend")
  let fixture = try await RuntimeFixture(
    finalText: "First capture",
    capsuleEnabled: true,
    routingNotes: [project, personal],
    ambiguousRouting: true
  )
  await fixture.runtime.awaitStartupAssessment()
  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let firstCaptureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.capsuleController.currentChooser == nil)
  #expect(fixture.runtime.coordinator.routingAmbiguity?.captureID == firstCaptureID)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Inbox"))
  #expect(fixture.runtime.capsuleController.currentChooser?.captureID == firstCaptureID)

  await fixture.runtime.toggle()
  #expect(fixture.runtime.currentCapsuleStatus == .listening)
  #expect(fixture.runtime.capsuleController.currentChooser == nil)
  #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: firstCaptureID,
    noteID: project.id
  )
  #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))
  await fixture.runtime.cancel()
}

@Test @MainActor func DictationRuntimeReplaysRawFallbackChooserAfterDisableAndReenable()
  async throws
{
  let project = Note(title: "Projects", body: "Roadmap")
  let personal = Note(title: "Personal", body: "Weekend")
  let fixture = try await RuntimeFixture(
    finalText: "Raw fallback capture",
    capsuleEnabled: true,
    routingNotes: [project, personal],
    ambiguousRouting: true,
    cleanupFails: true
  )
  await fixture.runtime.awaitStartupAssessment()
  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)
  #expect(fixture.runtime.currentCapsuleStatus == .savedWithoutCleanup(destination: "Inbox"))

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == nil)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .savedWithoutCleanup(destination: "Inbox"))
  #expect(fixture.runtime.capsuleController.currentChooser?.captureID == captureID)
}

@Test @MainActor func DictationRuntimeKeepInboxCompletesChooserWithoutMovingCapture()
  async throws
{
  let sleeper = RuntimeCapsuleSleeper()
  let project = Note(title: "Projects", body: "Roadmap")
  let personal = Note(title: "Personal", body: "Weekend")
  let fixture = try await RuntimeFixture(
    finalText: "Leave this here",
    capsuleEnabled: true,
    routingNotes: [project, personal],
    ambiguousRouting: true,
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()
  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: captureID,
    noteID: nil
  )
  for _ in 0..<1_000 {
    if fixture.runtime.coordinator.routingAmbiguity == nil { break }
    await Task.yield()
  }

  #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Inbox"))
  #expect(fixture.runtime.capsuleController.currentChooser == nil)
  #expect(fixture.appState.workspace.notes.first(where: {
    $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
  })?.body.contains("Leave this here") == true)
  #expect(fixture.appState.workspace.notes.first(where: { $0.id == project.id })?.body == "Roadmap")
  await sleeper.waitForRequest()
  #expect(await sleeper.requestedDurations == [.milliseconds(1_600)])
  await sleeper.resumeAll()
}

@Test @MainActor func DictationRuntimeDeletedChoiceShowsActionableFailureWithOnlyValidChoices()
  async throws
{
  let sleeper = RuntimeCapsuleSleeper()
  let project = Note(title: "Projects", body: "Roadmap")
  let personal = Note(title: "Personal", body: "Weekend")
  let fixture = try await RuntimeFixture(
    finalText: "Still in Inbox",
    capsuleEnabled: true,
    routingNotes: [project, personal],
    ambiguousRouting: true,
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()
  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)
  fixture.appState.workspace.notes.removeAll { $0.id == project.id }

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: captureID,
    noteID: project.id
  )
  for _ in 0..<100 { await Task.yield() }

  #expect(fixture.runtime.coordinator.routingAmbiguity?.captureID == captureID)
  #expect(fixture.runtime.currentCapsuleStatus == .routingFailure(
    status: "Inbox saved · retry",
    message: "Still saved to Inbox. Projects is no longer available. Choose another note or keep this dictation in Inbox."
  ))
  #expect(fixture.runtime.currentCapsuleStatus?.presentation.visibleText == "Inbox saved · retry")
  #expect(
    fixture.runtime.currentCapsuleStatus?.presentation.voiceOverText
      == "Dictation routing needs attention: Still saved to Inbox. Projects is no longer available. Choose another note or keep this dictation in Inbox."
  )
  let chooser = try #require(fixture.runtime.capsuleController.currentChooser)
  #expect(chooser.captureID == captureID)
  #expect(chooser.choices.map(\.id) == [personal.id])
  #expect(chooser.allowsKeepInInbox)
  #expect(await sleeper.requestedDurations.isEmpty)
  #expect(fixture.appState.workspace.notes.first(where: {
    $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
  })?.body.contains("Still in Inbox") == true)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .routingFailure(
    status: "Inbox saved · retry",
    message: "Still saved to Inbox. Projects is no longer available. Choose another note or keep this dictation in Inbox."
  ))
  #expect(fixture.runtime.capsuleController.currentChooser?.choices.map(\.id) == [personal.id])

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: captureID,
    noteID: personal.id
  )
  for _ in 0..<1_000 {
    if fixture.runtime.coordinator.routingAmbiguity == nil { break }
    await Task.yield()
  }

  #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Personal"))
  #expect(fixture.runtime.capsuleController.currentChooser == nil)
  #expect(fixture.appState.workspace.notes.first(where: { $0.id == personal.id })?.body.contains("Still in Inbox") == true)
  await sleeper.waitForRequest()
  #expect(await sleeper.requestedDurations == [.milliseconds(1_600)])
  await sleeper.resumeAll()
}

@Test @MainActor func DictationRuntimeHistoryFailureKeepsMovedDestinationTruthfulAndRetryable()
  async throws
{
  let sleeper = RuntimeCapsuleSleeper()
  let project = Note(title: "Projects", body: "Roadmap")
  let personal = Note(title: "Personal", body: "Weekend")
  let fixture = try await RuntimeFixture(
    finalText: "Moved before history failed",
    capsuleEnabled: true,
    routingNotes: [project, personal],
    ambiguousRouting: true,
    cleanupFails: true,
    historySaveFailureAttempt: 3,
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()
  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: captureID,
    noteID: project.id
  )
  for _ in 0..<1_000 {
    if fixture.history.errorMessage != nil { break }
    await Task.yield()
  }
  for _ in 0..<1_000 {
    if case .routingFailure? = fixture.runtime.currentCapsuleStatus { break }
    await Task.yield()
  }

  #expect(fixture.history.errorMessage != nil)
  #expect(fixture.runtime.coordinator.routingAmbiguity?.captureID == captureID)
  #expect(fixture.runtime.currentCapsuleStatus == .routingFailure(
    status: "Projects saved raw · retry",
    message: "Still saved to Projects without cleanup. Dictation History could not be updated. Retry Projects or choose another note."
  ))
  #expect(
    fixture.runtime.currentCapsuleStatus?.presentation.visibleText
      == "Projects saved raw · retry"
  )
  let chooser = try #require(fixture.runtime.capsuleController.currentChooser)
  #expect(chooser.captureID == captureID)
  #expect(!chooser.allowsKeepInInbox)
  #expect(!chooser.menuAccessibilityHint.contains("Inbox"))
  #expect(chooser.choices.allSatisfy { !$0.accessibilityHint.contains("from Inbox") })
  fixture.runtime.capsuleController.selectRoutingChoice(captureID: captureID, noteID: nil)
  for _ in 0..<100 { await Task.yield() }
  #expect(fixture.runtime.currentCapsuleStatus == .routingFailure(
    status: "Projects saved raw · retry",
    message: "Still saved to Projects without cleanup. Dictation History could not be updated. Retry Projects or choose another note."
  ))
  #expect(fixture.runtime.coordinator.routingAmbiguity?.captureID == captureID)
  #expect(await sleeper.requestedDurations.isEmpty)

  fixture.runtime.capsuleController.selectRoutingChoice(captureID: captureID, noteID: project.id)
  for _ in 0..<1_000 {
    if fixture.runtime.coordinator.routingAmbiguity == nil { break }
    await Task.yield()
  }
  #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
  #expect(fixture.runtime.currentCapsuleStatus == .savedWithoutCleanup(destination: "Projects"))
  #expect(fixture.runtime.capsuleController.currentChooser == nil)
  await sleeper.waitForRequest()
  #expect(await sleeper.requestedDurations == [.milliseconds(1_600)])
  await sleeper.resumeAll()
  #expect(fixture.appState.workspace.notes.first(where: { $0.id == project.id })?.body.contains("Moved before history failed") == true)
  #expect(fixture.appState.workspace.notes.first(where: {
    $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
  })?.body.contains("Moved before history failed") == false)
}

@Test @MainActor func DictationCapsuleRendersKeepInboxWhenNoNoteChoicesRemain() {
  let captureID = UUID()
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  var selectedNoteID: UUID??
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(captureID: captureID, choices: []),
    allowsKeepInInbox: true
  )

  controller.render(
    .failed("Still saved to Inbox."),
    chooser: chooser,
    onChoice: { _, noteID in selectedNoteID = noteID }
  )

  #expect(panel.allowsActions)
  controller.selectRoutingChoice(captureID: captureID, noteID: nil)
  #expect(selectedNoteID == .some(nil))
}

@Test @MainActor func DictationRuntimeKeepsInboxActionWhenEveryChoiceWasDeleted()
  async throws
{
  let sleeper = RuntimeCapsuleSleeper()
  let project = Note(title: "Projects", body: "Roadmap")
  let personal = Note(title: "Personal", body: "Weekend")
  let fixture = try await RuntimeFixture(
    finalText: "Keep after every choice disappears",
    capsuleEnabled: true,
    routingNotes: [project, personal],
    ambiguousRouting: true,
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()
  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)
  fixture.appState.workspace.notes.removeAll { $0.id == project.id || $0.id == personal.id }

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: captureID,
    noteID: project.id
  )
  for _ in 0..<1_000 {
    if case .routingFailure? = fixture.runtime.currentCapsuleStatus { break }
    await Task.yield()
  }

  #expect(fixture.runtime.currentCapsuleStatus == .routingFailure(
    status: "Inbox saved · keep/undo",
    message: "Still saved to Inbox. Projects is no longer available. Keep this dictation in Inbox or use Undo."
  ))
  let chooser = try #require(fixture.runtime.capsuleController.currentChooser)
  #expect(chooser.choices.isEmpty)
  #expect(chooser.allowsKeepInInbox)
  #expect(await sleeper.requestedDurations.isEmpty)

  fixture.runtime.capsuleController.selectRoutingChoice(captureID: captureID, noteID: nil)
  for _ in 0..<1_000 {
    if fixture.runtime.coordinator.routingAmbiguity == nil { break }
    await Task.yield()
  }
  #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Inbox"))
  await sleeper.waitForRequest()
  #expect(await sleeper.requestedDurations == [.milliseconds(1_600)])
  await sleeper.resumeAll()
}

@Test @MainActor func DictationRuntimeClearsOldFailureWhenAlternateMoveIsPending()
  async throws
{
  let project = Note(title: "Projects", body: "Roadmap")
  let personal = Note(title: "Personal", body: "Weekend")
  let fixture = try await RuntimeFixture(
    finalText: "Move after retry failure",
    capsuleEnabled: true,
    routingNotes: [project, personal],
    ambiguousRouting: true,
    cleanupFails: true,
    historySaveFailureAttempt: 3,
    historySaveBlockingAttempt: 4
  )
  await fixture.runtime.awaitStartupAssessment()
  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: captureID,
    noteID: project.id
  )
  for _ in 0..<1_000 {
    if case .routingFailure? = fixture.runtime.currentCapsuleStatus { break }
    await Task.yield()
  }

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: captureID,
    noteID: personal.id
  )
  await fixture.historySaveGate.waitUntilWaiting()

  #expect(fixture.runtime.currentCapsuleStatus == .savedWithoutCleanup(destination: "Personal"))
  #expect(fixture.runtime.capsuleController.currentChooser?.captureID == captureID)

  await fixture.historySaveGate.open()
  for _ in 0..<1_000 {
    if fixture.runtime.coordinator.routingAmbiguity == nil { break }
    await Task.yield()
  }
}

@Test @MainActor func DictationRuntimeCompletesChoiceReplayedDuringInFlightDisableAndReenable()
  async throws
{
  let sleeper = RuntimeCapsuleSleeper()
  let project = Note(title: "Projects", body: "Roadmap")
  let personal = Note(title: "Personal", body: "Weekend")
  let fixture = try await RuntimeFixture(
    finalText: "Move while capsule is hidden",
    capsuleEnabled: true,
    routingNotes: [project, personal],
    ambiguousRouting: true,
    historySaveBlockingAttempt: 3,
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()
  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: captureID,
    noteID: project.id
  )
  await fixture.historySaveGate.waitUntilWaiting()
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Projects"))

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.capsuleController.currentChooser == nil)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.capsuleController.currentChooser?.captureID == captureID)

  await fixture.historySaveGate.open()
  for _ in 0..<1_000 {
    if fixture.runtime.coordinator.routingAmbiguity == nil { break }
    await Task.yield()
  }
  for _ in 0..<100 { await Task.yield() }

  #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Projects"))
  #expect(fixture.runtime.capsuleController.currentChooser == nil)
  #expect(await sleeper.requestedDurations == [.milliseconds(1_600)])
}

@Test @MainActor func DictationRuntimeDoesNotReplayTerminalUpdatesReceivedWhileDisabled()
  async throws
{
  for finalText in ["saved", nil] as [String?] {
    let sleeper = RuntimeCapsuleSleeper()
    let fixture = try await RuntimeFixture(
      finalText: finalText,
      capsuleEnabled: false,
      capsuleSleeper: { duration in await sleeper.sleep(duration) }
    )
    await fixture.runtime.awaitStartupAssessment()

    await fixture.runtime.toggle()
    await fixture.runtime.toggle()
    await Task.yield()
    #expect(fixture.runtime.currentCapsuleStatus == nil)
    #expect(await sleeper.requestedDurations.isEmpty)

    fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
    fixture.runtime.preferencesDidChange()
    #expect(fixture.runtime.currentCapsuleStatus == .idle)
    if fixture.runtime.currentCapsuleStatus != .idle {
      await sleeper.waitForRequest()
    }
    #expect(await sleeper.requestedDurations.isEmpty)
    await sleeper.resumeAll()
  }

  let availability = DictationAvailability.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .denied,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  let preflight = try await RuntimeFixture(
    finalText: nil,
    capsuleEnabled: false,
    availability: availability
  )
  await preflight.runtime.awaitStartupAssessment()
  await preflight.runtime.toggle()
  preflight.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  preflight.runtime.preferencesDidChange()
  #expect(preflight.runtime.currentCapsuleStatus == .idle)
}

@Test @MainActor func DictationRuntimeClearsVisibleTerminalReplayWhenDisabled()
  async throws
{
  for (finalText, delay) in [
    ("saved", Duration.milliseconds(1_600)),
    (nil, Duration.seconds(3)),
  ] as [(String?, Duration)] {
    let sleeper = RuntimeCapsuleSleeper()
    let fixture = try await RuntimeFixture(
      finalText: finalText,
      capsuleEnabled: true,
      capsuleSleeper: { duration in await sleeper.sleep(duration) }
    )
    await fixture.runtime.awaitStartupAssessment()

    await fixture.runtime.toggle()
    await fixture.runtime.toggle()
    await sleeper.waitForRequest()
    #expect(await sleeper.requestedDurations == [delay])

    fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
    fixture.runtime.preferencesDidChange()
    fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
    fixture.runtime.preferencesDidChange()

    #expect(fixture.runtime.currentCapsuleStatus == .idle)
    if fixture.runtime.currentCapsuleStatus != .idle {
      for _ in 0..<1_000 {
        if await sleeper.requestedDurations.count >= 2 { break }
        await Task.yield()
      }
    }
    await sleeper.resumeAll()
    await Task.yield()
    #expect(fixture.runtime.currentCapsuleStatus == .idle)
    #expect(await sleeper.requestedDurations == [delay])
  }
}

@Test @MainActor func DictationRuntimeReplaysLiveDictationWhenReenabled() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: false)
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()
  #expect(fixture.runtime.currentCapsuleStatus == nil)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .listening)

  await fixture.runtime.cancel()
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
}

@Test @MainActor func DictationRuntimeForwardsLevelsOnlyToAnActiveVisibleCapsule() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: false)
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()
  fixture.engine.emitLevel(0.8)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  fixture.engine.emitLevel(0.8)
  #expect(fixture.runtime.capsuleController.waveformModel.energy > 0)

  await fixture.runtime.cancel()
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)
  fixture.engine.emitLevel(1)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)
}

@Test @MainActor
func DictationRuntimeCaptureFeedbackRendersEarlyLevelAfterListening() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  await fixture.runtime.awaitStartupAssessment()
  let startGate = DictationTestGate()
  fixture.engine.startGate = startGate

  let toggle = Task { await fixture.runtime.toggle() }
  await startGate.waitUntilWaiting()

  #expect(fixture.runtime.currentCapsuleStatus == .arming)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)

  fixture.engine.emitLevel(0.8)

  #expect(fixture.runtime.currentCapsuleStatus == .listening)
  #expect(fixture.runtime.capsuleController.waveformModel.energy > 0)

  await startGate.open()
  await toggle.value
  #expect(fixture.runtime.currentCapsuleStatus == .listening)
  #expect(fixture.runtime.capsuleController.waveformModel.energy > 0)
  await fixture.runtime.cancel()
}

@Test @MainActor
func DictationRuntimeCaptureFeedbackZeroLevelShowsQuietListening() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  await fixture.runtime.awaitStartupAssessment()
  let startGate = DictationTestGate()
  fixture.engine.startGate = startGate

  let toggle = Task { await fixture.runtime.toggle() }
  await startGate.waitUntilWaiting()
  fixture.engine.emitLevel(0)

  #expect(fixture.runtime.currentCapsuleStatus == .listening)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)

  await startGate.open()
  await toggle.value
  await fixture.runtime.cancel()
}

@Test @MainActor
func DictationRuntimeCaptureFeedbackRespectsHiddenPreference() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: false)
  await fixture.runtime.awaitStartupAssessment()
  let startGate = DictationTestGate()
  fixture.engine.startGate = startGate

  let toggle = Task { await fixture.runtime.toggle() }
  await startGate.waitUntilWaiting()
  #expect(fixture.runtime.currentCapsuleStatus == nil)

  fixture.engine.emitLevel(0.8)

  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)

  await startGate.open()
  await toggle.value
  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)
  await fixture.runtime.cancel()
}

@Test @MainActor
func DictationRuntimeCaptureFeedbackCancellationRejectsLateEnergyDuringSuspendedStart()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  await fixture.runtime.awaitStartupAssessment()
  let startGate = DictationTestGate()
  fixture.engine.startGate = startGate

  let toggle = Task { await fixture.runtime.toggle() }
  await startGate.waitUntilWaiting()
  fixture.engine.emitLevel(0.8)
  #expect(fixture.runtime.capsuleController.waveformModel.energy > 0)

  await fixture.runtime.cancel()
  let energyAfterCancellation = fixture.runtime.capsuleController.waveformModel.energy

  fixture.engine.emitLevel(1)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == energyAfterCancellation)
  #expect(fixture.runtime.capsuleController.waveformModel.barHeights(
    at: Date().addingTimeInterval(1),
    reduceMotion: false
  ) == Array(
    repeating: DictationWaveformModel.minimumHeight,
    count: DictationWaveformModel.barCount
  ))

  await startGate.open()
  await toggle.value
  #expect(fixture.runtime.currentCapsuleStatus == .idle)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)
}

@Test @MainActor func DictationRuntimeIgnoresAStaleEngineCallbackAfterANewCapture() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()
  for _ in 0..<100 {
    if fixture.engine.captureCallbackCount == 1 { break }
    await Task.yield()
  }
  #expect(fixture.engine.captureCallbackCount == 1)
  fixture.engine.emitLevel(0.8)
  #expect(fixture.runtime.capsuleController.waveformModel.energy > 0)

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  for _ in 0..<100 {
    if fixture.engine.captureCallbackCount == 2 { break }
    await Task.yield()
  }
  #expect(fixture.engine.captureCallbackCount == 2)
  #expect(fixture.runtime.capsuleController.currentContext.status == .listening)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)

  fixture.engine.emitLevel(fromCaptureAt: 0, value: 0.8)
  #expect(fixture.runtime.capsuleController.waveformModel.energy == 0)
  fixture.engine.emitLevel(fromCaptureAt: 1, value: 0.8)
  #expect(fixture.runtime.capsuleController.waveformModel.energy > 0)

  await fixture.runtime.cancel()
}

@Test @MainActor func DictationRuntimeUsesCoordinatorEventsAndAppliesModifierAfterTerminal() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  let replacement = DictationModifierKey.leftCommand
  await fixture.runtime.awaitStartupAssessment()
  #expect(!DictationRuntime.usesPeriodicObservation)

  await fixture.runtime.toggle()
  #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))
  fixture.appState.preferences.dictationModifierKey = replacement
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.actualModifier != replacement)

  await fixture.runtime.toggle()
  await fixture.runtime.waitForTerminalSynchronization()
  #expect(fixture.runtime.actualModifier == replacement)
  #expect(fixture.runtime.phase != .finalizing)
}

@Test @MainActor func DictationRuntimeFocusedToolbarPersistsTheSelectedNoteDestination()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "Focused")
  let commands = EditorCommands()
  let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let window = DictationKeyWindowProbe(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  window.reportsKey = true
  commands.textView = textView
  fixture.editorRegistry.register(commands)
  window.makeFirstResponder(textView)
  let selected = try #require(fixture.appState.selectedNote)

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()

  let record = try #require(fixture.history.records.first)
  #expect(record.mode == .focused)
  #expect(record.destination == .init(noteID: selected.id, title: selected.displayTitle))
  #expect(record.insertionOutcome == .saved)
}

@Test @MainActor func DictationRuntimeFocusedGlobalShortcutPersistsTheSelectedNoteDestination()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "Focused")
  let commands = EditorCommands()
  let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let window = DictationKeyWindowProbe(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  window.reportsKey = true
  commands.textView = textView
  fixture.editorRegistry.register(commands)
  window.makeFirstResponder(textView)
  let selected = try #require(fixture.appState.selectedNote)
  await fixture.runtime.awaitStartupAssessment()

  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.runtime.shortcutController.drainEvents()
  for _ in 0..<20 {
    if case .listening = fixture.runtime.phase { break }
    await Task.yield()
  }
  fixture.monitor.emit(.released(.rightOption))
  await fixture.runtime.shortcutController.drainEvents()
  await fixture.runtime.waitForTerminalSynchronization()

  let record = try #require(fixture.history.records.first)
  #expect(record.mode == .focused)
  #expect(record.destination == .init(noteID: selected.id, title: selected.displayTitle))
  #expect(record.insertionOutcome == .saved)
}

@Test @MainActor func DictationRuntimeAppliesPendingModifierAfterSavedAndFailedSessions()
  async throws
{
  for finalText in ["saved", nil] as [String?] {
    let fixture = try await RuntimeFixture(finalText: finalText)
    await fixture.runtime.awaitStartupAssessment()
    let replacement = DictationModifierKey.leftCommand

    fixture.monitor.emit(.pressed(.rightOption))
    await fixture.runtime.shortcutController.drainEvents()
    for _ in 0..<20 {
      if case .listening = fixture.runtime.phase { break }
      await Task.yield()
    }
    if case .listening = fixture.runtime.phase {
      // Capture is active, not merely arming.
    } else {
      Issue.record("Expected listening phase, got \(fixture.runtime.phase)")
    }

    fixture.appState.updatePreferences { $0.dictationModifierKey = replacement }
    fixture.runtime.preferencesDidChange()
    fixture.monitor.emit(.released(.rightOption))
    await fixture.runtime.shortcutController.drainEvents()
    await fixture.runtime.waitForTerminalSynchronization()

    #expect(fixture.runtime.actualModifier == replacement)
    if finalText == nil {
      #expect(fixture.runtime.phase == .failed("No speech detected."))
    } else {
      guard case .saved(let destination) = fixture.runtime.phase else {
        Issue.record("Expected saved Inbox phase, got \(fixture.runtime.phase)")
        continue
      }
      #expect(destination.title == "Inbox")
    }
  }
}

@Test @MainActor func DictationRuntimeDeniedModifierChangePreservesActiveAndStoredModifier()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.awaitStartupAssessment()
  let old = fixture.appState.preferences.dictationModifierKey
  fixture.monitor.accessGranted = false
  fixture.monitor.requestAccessResult = false

  let changed = await fixture.runtime.changeModifier(to: .leftCommand)

  #expect(!changed)
  #expect(fixture.runtime.actualModifier == old)
  #expect(fixture.appState.preferences.dictationModifierKey == old)
  #expect(fixture.monitor.stopCount == 0)
}

@Test @MainActor func DictationRuntimeEnablesStoredModifierAfterAccessIsGranted()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    preferredModifier: .leftCommand,
    monitorAccessGranted: false,
    monitorRequestAccessResult: false
  )
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.monitor.requestCount == 0)
  #expect(fixture.runtime.modifierMonitorState == .unauthorized)
  #expect(fixture.runtime.actualModifier == nil)
  #expect(fixture.appState.preferences.dictationModifierKey == .leftCommand)

  fixture.monitor.accessGranted = true
  fixture.runtime.applicationDidBecomeActive()
  #expect(fixture.runtime.modifierMonitorState == .running)
  #expect(fixture.runtime.actualModifier == .leftCommand)
  #expect(fixture.appState.preferences.dictationModifierKey == .leftCommand)
}

@Test @MainActor func DictationRuntimeModifierRecoveryReturnsSettingsOnlyWhenAccessIsDenied()
  async throws
{
  let denied = try await RuntimeFixture(
    finalText: "saved",
    monitorAccessGranted: false,
    monitorRequestAccessResult: false
  )
  await denied.runtime.awaitStartupAssessment()

  let recovery = await denied.runtime.recoverModifierMonitoring()

  #expect(recovery?.pane == .inputMonitoring)
  #expect(denied.monitor.requestCount == 1)
  #expect(denied.runtime.modifierMonitorState == .unauthorized)
  #expect(denied.runtime.actualModifier == nil)

  let granted = try await RuntimeFixture(
    finalText: "saved",
    monitorAccessGranted: false,
    monitorRequestAccessResult: true
  )
  await granted.runtime.awaitStartupAssessment()

  let noRecovery = await granted.runtime.recoverModifierMonitoring()

  #expect(noRecovery == nil)
  #expect(granted.monitor.requestCount == 1)
  #expect(granted.runtime.modifierMonitorState == .running)
  #expect(granted.runtime.actualModifier == .rightOption)
}

@Test @MainActor func DictationRuntimeNeverRequestsModifierMonitoringAtStartup() async throws {
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    monitorAccessGranted: false,
    monitorRequestAccessResult: true
  )

  await fixture.runtime.awaitStartupAssessment()
  fixture.runtime.preferencesDidChange()

  #expect(fixture.monitor.requestCount == 0)
  #expect(fixture.runtime.modifierMonitorState == .unauthorized)
  #expect(fixture.runtime.actualModifier == nil)
}

@Test @MainActor func DictationRuntimeRunningMonitorChangesWithoutRestart()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.awaitStartupAssessment()
  fixture.monitor.startError = DictationSettingsTestError.failed

  let changed = await fixture.runtime.changeModifier(to: .leftCommand)

  #expect(changed)
  #expect(fixture.runtime.actualModifier == .leftCommand)
  #expect(fixture.appState.preferences.dictationModifierKey == .leftCommand)
  #expect(fixture.monitor.startCount == 1)
  #expect(fixture.monitor.stopCount == 0)
}

@Test @MainActor func DictationRuntimeFailedRestartPreservesStoredSemanticModifier()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.awaitStartupAssessment()
  let old = fixture.appState.preferences.dictationModifierKey
  fixture.monitor.publish(.failed)
  await fixture.runtime.shortcutController.drainEvents()
  fixture.monitor.startError = DictationSettingsTestError.failed

  let changed = await fixture.runtime.changeModifier(to: .leftCommand)

  #expect(!changed)
  #expect(fixture.appState.preferences.dictationModifierKey == old)
  #expect(fixture.runtime.shortcutController.registeredModifier == old)
  #expect(fixture.runtime.actualModifier == nil)
}

@Test @MainActor func DictationRecoveryRemainsReachableWhenCapsuleIsDisabled()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "recoverable", capsuleEnabled: false)

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()

  #expect(fixture.runtime.currentCapsuleStatus == nil)
  #expect(fixture.runtime.recoveryAction == .undo)
  #expect(fixture.runtime.recoveryCommand == .init(title: "Undo", isEnabled: true))

  await fixture.runtime.performRecoveryAction()

  #expect(fixture.runtime.recoveryAction == nil)
  #expect(!fixture.runtime.recoveryCommand.isEnabled)
}

@Test @MainActor func DictationRecoveryCommandDisablesWhileShortcutIsArmed()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "recoverable")

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()
  let session = try #require(fixture.runtime.coordinator.beginShortcut(editor: nil))

  #expect(!fixture.runtime.recoveryCommand.isEnabled)

  await fixture.runtime.coordinator.cancelShortcut(session)
  #expect(fixture.runtime.recoveryCommand.isEnabled)
}

@Test @MainActor func DictationRuntimePreflightsDeniedMicrophoneAndSpeechPermissions()
  async throws
{
  for (microphone, speech, expectedPane, expectedTitle) in [
    (
      DictationPermissionStatus.denied,
      DictationPermissionStatus.authorized,
      DictationPrivacyPane.microphone,
      "Open Microphone Settings"
    ),
    (
      DictationPermissionStatus.authorized,
      DictationPermissionStatus.denied,
      DictationPrivacyPane.speechRecognition,
      "Open Speech Recognition Settings"
    ),
  ] {
    let availability = DictationAvailability.evaluate(.init(
      osMajorVersion: 26,
      architecture: .appleSilicon,
      microphonePermission: microphone,
      speechPermission: speech,
      appleOnDeviceRecognitionSupported: true,
      enhancedModelReady: false,
      foundationModelAvailable: true
    ))
    let fixture = try await RuntimeFixture(finalText: nil, availability: availability)

    await fixture.runtime.toggle()

    guard case .failed(let message) = fixture.runtime.phase else {
      Issue.record("Expected permission preflight failure")
      continue
    }
    #expect(message == availability.standardFailureCopy)
    #expect(fixture.runtime.permissionRecoveryActions().map(\.pane) == [expectedPane])
    #expect(fixture.runtime.captureFailure?.message == message)
    #expect(fixture.runtime.captureFailure?.actions.map(\.title) == [expectedTitle])
    #expect(fixture.provider.requestCount == 0)
  }
}

@Test @MainActor func DictationRuntimePreflightsUnavailableOnDeviceRecognizer()
  async throws
{
  let availability = DictationAvailability.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .authorized,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: false,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  let fixture = try await RuntimeFixture(finalText: nil, availability: availability)

  await fixture.runtime.toggle()

  #expect(
    fixture.runtime.phase
      == .failed(
        "Standard — Apple Speech is unavailable because on-device English recognition is not installed or supported."
      )
  )
  #expect(fixture.runtime.permissionRecoveryActions().isEmpty)
  #expect(
    fixture.runtime.captureFailure?.message
      == "Standard — Apple Speech is unavailable because on-device English recognition is not installed or supported."
  )
  #expect(fixture.runtime.captureFailure?.actions.isEmpty == true)
  #expect(fixture.provider.requestCount == 0)
}

@Test @MainActor func DictationRuntimePreflightFailureUsesProtectedCapsuleReturnTimer()
  async throws
{
  let availability = RuntimeAvailabilityBox(.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .denied,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  )))
  let sleeper = RuntimeCapsuleSleeper()
  let fixture = try await RuntimeFixture(
    finalText: "Saved",
    capsuleEnabled: true,
    availabilityProvider: { availability.value },
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()

  guard
    fixture.runtime.currentCapsuleStatus
      == .failed(availability.value.standardFailureCopy ?? "")
  else {
    Issue.record("Expected preflight failure capsule")
    return
  }
  await sleeper.waitForRequest()
  #expect(await sleeper.requestedDurations == [Duration.seconds(3)])

  availability.value = .evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .authorized,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  await fixture.runtime.toggle()
  #expect(fixture.runtime.currentCapsuleStatus == .listening)

  await sleeper.resumeAll()
  await Task.yield()
  #expect(fixture.runtime.currentCapsuleStatus == .listening)
  await fixture.runtime.cancel()
}

@Test @MainActor func DictationRuntimeClearsVisiblePreflightFailureOnRetryAndSuccess()
  async throws
{
  let availability = RuntimeAvailabilityBox(.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .denied,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  )))
  let fixture = try await RuntimeFixture(
    finalText: "Saved",
    availabilityProvider: { availability.value }
  )

  await fixture.runtime.toggle()
  #expect(fixture.runtime.captureFailure != nil)

  availability.value = .evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .authorized,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  await fixture.runtime.toggle()

  #expect(fixture.runtime.captureFailure == nil)
  #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))

  await fixture.runtime.toggle()
  #expect(fixture.runtime.captureFailure == nil)
}

@Test @MainActor func DictationRuntimePublishesGlobalPermissionFailureInNotesPanel()
  async throws
{
  let availability = DictationAvailability.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .denied,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  let fixture = try await RuntimeFixture(finalText: nil, availability: availability)
  fixture.provider.error = DictationFailure.permissionDenied
  await fixture.runtime.awaitStartupAssessment()

  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.runtime.shortcutController.drainEvents()
  for _ in 0..<20 {
    if fixture.runtime.captureFailure != nil { break }
    await Task.yield()
  }

  #expect(fixture.runtime.captureFailure?.message == availability.standardFailureCopy)
  #expect(
    fixture.runtime.captureFailure?.actions.map(\.title)
      == ["Open Microphone Settings"]
  )
}

@Test @MainActor func DictationRuntimeShutdownAwaitsCancelledStartupAssessment() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", startupBlocked: true)
  await fixture.startupGate.waitUntilWaiting()
  let completed = RuntimeCompletionProbe()

  let shutdown = Task {
    await fixture.runtime.shutdown()
    await completed.complete()
  }
  await Task.yield()
  #expect(!(await completed.isComplete))

  await fixture.startupGate.open()
  await shutdown.value
  #expect(await completed.isComplete)
}

@Test @MainActor func DictationRuntimeShutdownAwaitsSuspendedProviderAndLateRelease() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  let providerGate = DictationTestGate()
  let releaseGate = DictationTestGate()
  fixture.provider.gate = providerGate
  fixture.engine.releaseGate = releaseGate
  let starting = Task { await fixture.runtime.toggle() }
  await fixture.provider.waitUntilRequested()
  let completed = RuntimeCompletionProbe()

  let shutdown = Task {
    await fixture.runtime.shutdown()
    await completed.complete()
  }
  await Task.yield()
  #expect(!(await completed.isComplete))

  await providerGate.open()
  await releaseGate.waitUntilWaiting()
  #expect(!(await completed.isComplete))
  await releaseGate.open()
  await starting.value
  await shutdown.value
  #expect(fixture.engine.releaseCount == 1)
}

@Test @MainActor func DictationRuntimeShutdownAwaitsSuspendedFinishAndLateRelease() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  let finishGate = DictationTestGate()
  let releaseGate = DictationTestGate()
  fixture.engine.finishGate = finishGate
  fixture.engine.releaseGate = releaseGate
  await fixture.runtime.toggle()
  let finishing = Task { await fixture.runtime.toggle() }
  await finishGate.waitUntilWaiting()
  let completed = RuntimeCompletionProbe()

  let shutdown = Task {
    await fixture.runtime.shutdown()
    await completed.complete()
  }
  await Task.yield()
  #expect(!(await completed.isComplete))

  await finishGate.open()
  await releaseGate.waitUntilWaiting()
  #expect(!(await completed.isComplete))
  await releaseGate.open()
  await finishing.value
  await shutdown.value
  #expect(fixture.engine.releaseCount == 1)
}

@Test @MainActor func DictationRuntimeShutdownIsIdempotentAndDoesNotRetainRuntime() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  var runtime: DictationRuntime? = fixture.runtime
  weak let weakRuntime = runtime
  await runtime?.shutdown()
  await runtime?.shutdown()
  #expect(runtime?.shutdownCount == 1)
  runtime = nil
  fixture.releaseRuntime()
  await Task.yield()
  #expect(weakRuntime == nil)
}

@Test @MainActor
func DictationRuntimeStopsResourceMonitoringBeforeDrainAndCoolsAfterDrain() async throws {
  let lifecycle = RuntimeResourceLifecycleProbe()
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    resourceLifecycle: lifecycle
  )
  await fixture.runtime.toggle()

  let releaseGate = DictationTestGate()
  fixture.engine.releaseGate = releaseGate
  let shutdown = Task { await fixture.runtime.shutdown() }
  await releaseGate.waitUntilWaiting()

  #expect(lifecycle.events == [.monitorStarted, .monitorStopped])

  await releaseGate.open()
  await shutdown.value

  #expect(lifecycle.events == [
    .monitorStarted,
    .monitorStopped,
    .engineReleased,
    .forceCold,
  ])

  await fixture.runtime.shutdown()
  #expect(lifecycle.events == [
    .monitorStarted,
    .monitorStopped,
    .engineReleased,
    .forceCold,
  ])
}

@Test @MainActor
func DictationRuntimeDeinitDrainsStartupBeforeCoolingWithoutRetainingRuntime()
  async throws
{
  let lifecycle = RuntimeResourceLifecycleProbe()
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    startupBlocked: true,
    resourceLifecycle: lifecycle
  )
  await fixture.startupGate.waitUntilWaiting()

  var runtime: DictationRuntime? = fixture.runtime
  weak let weakRuntime = runtime
  fixture.releaseRuntime()
  runtime = nil

  await lifecycle.monitorStoppedGate.wait()
  #expect(weakRuntime == nil)
  #expect(lifecycle.events == [.monitorStarted, .monitorStopped])

  await Task.yield()
  #expect(lifecycle.events == [.monitorStarted, .monitorStopped])

  await fixture.startupGate.open()
  await lifecycle.forceColdGate.wait()
  #expect(lifecycle.events == [
    .monitorStarted,
    .monitorStopped,
    .forceCold,
  ])

  await Task.yield()
  await Task.yield()
  #expect(lifecycle.events == [
    .monitorStarted,
    .monitorStopped,
    .forceCold,
  ])
}

@Test @MainActor
func DictationRuntimeDeinitStopsAndCoolsWhenFinalReleaseHappensOffMainActor()
  async throws
{
  let lifecycle = RuntimeResourceLifecycleProbe()
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    startupBlocked: true,
    resourceLifecycle: lifecycle
  )
  await fixture.startupGate.waitUntilWaiting()

  weak let weakRuntime = fixture.runtime
  let releaseBox = RuntimeOffActorReleaseBox(runtime: fixture.runtime)
  fixture.releaseRuntime()
  let release = Task.detached {
    releaseBox.release()
  }

  await lifecycle.monitorStoppedGate.wait()
  await release.value
  #expect(weakRuntime == nil)
  #expect(lifecycle.events == [.monitorStarted, .monitorStopped])

  await Task.yield()
  #expect(lifecycle.events == [.monitorStarted, .monitorStopped])

  await fixture.startupGate.open()
  await lifecycle.forceColdGate.wait()
  #expect(lifecycle.events == [
    .monitorStarted,
    .monitorStopped,
    .forceCold,
  ])

  await Task.yield()
  await Task.yield()
  #expect(lifecycle.events == [
    .monitorStarted,
    .monitorStopped,
    .forceCold,
  ])
}

private func historyRecord(
  raw: String,
  cleaned: String?,
  cleanup: DictationCleanupOutcome
) -> DictationHistoryRecord {
  DictationHistoryRecord(
    id: UUID(),
    mode: .smartCapture,
    engine: .standard,
    startedAt: Date(timeIntervalSince1970: 1),
    completedAt: Date(timeIntervalSince1970: 2),
    rawTranscript: raw,
    cleanedTranscript: cleaned,
    cleanupOutcome: cleanup,
    insertionOutcome: .saved
  )
}

private enum DictationSettingsTestError: Error {
  case failed
}

@MainActor
private func focusRuntimeEditor(
  _ fixture: RuntimeFixture
) -> (commands: EditorCommands, window: NSWindow) {
  let commands = EditorCommands()
  let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  commands.textView = textView
  fixture.editorRegistry.register(commands)
  window.makeFirstResponder(textView)
  return (commands, window)
}

private actor DictationTestGate {
  private var openState = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var observers: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !openState else { return }
    let current = observers
    observers.removeAll()
    current.forEach { $0.resume() }
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilWaiting() async {
    guard waiters.isEmpty else { return }
    await withCheckedContinuation { observers.append($0) }
  }

  func open() {
    openState = true
    let current = waiters
    waiters.removeAll()
    current.forEach { $0.resume() }
  }
}

private actor DictationOperationLog {
  private(set) var values: [String] = []

  func append(_ value: String) {
    values.append(value)
  }
}

private enum RuntimeResourceLifecycleEvent: Equatable {
  case monitorStarted
  case monitorStopped
  case engineReleased
  case forceCold
}

@MainActor
private final class RuntimeResourceLifecycleProbe {
  private(set) var events: [RuntimeResourceLifecycleEvent] = []
  let monitorStoppedGate = DictationTestGate()
  let forceColdGate = DictationTestGate()

  func append(_ event: RuntimeResourceLifecycleEvent) {
    events.append(event)
    switch event {
    case .monitorStopped:
      Task { await monitorStoppedGate.open() }
    case .forceCold:
      Task { await forceColdGate.open() }
    case .monitorStarted, .engineReleased:
      break
    }
  }
}

private final class RuntimeOffActorReleaseBox: @unchecked Sendable {
  private var runtime: DictationRuntime?

  init(runtime: DictationRuntime) {
    self.runtime = runtime
  }

  func release() {
    runtime = nil
  }
}

@MainActor
private final class RuntimeFixture {
  let appState: AppState
  let monitor = RuntimeModifierMonitor()
  let escapeRegistrar = RuntimeEscapeRegistrar()
  let startupGate = DictationTestGate()
  let startupLog = RuntimeCounter()
  let engine: RuntimeSpeechEngine
  let provider: RuntimeEngineProvider
  let history: DictationHistoryController
  let historySaveGate = DictationTestGate()
  let editorRegistry = DictationEditorRegistry()
  let initialLoadBlocker: RuntimeBlockingFileManager?
  var runtime: DictationRuntime!

  init(
    finalText: String?,
    startupBlocked: Bool = false,
    capsuleEnabled: Bool = false,
    preferredEngine: DictationSpeechEngine = .standard,
    preferredModifier: DictationModifierKey = .rightOption,
    preferredDock: DictationCapsuleDock = .bottom,
    waitForInitialLoadBeforeRuntime: Bool = true,
    blockInitialLoad: Bool = false,
    monitorAccessGranted: Bool = true,
    monitorRequestAccessResult: Bool = true,
    permissionController: DictationPermissionController = .init(),
    resourceLifecycle: RuntimeResourceLifecycleProbe? = nil,
    availability: DictationAvailability = .evaluate(.init(
      osMajorVersion: 26,
      architecture: .appleSilicon,
      microphonePermission: .authorized,
      speechPermission: .authorized,
      appleOnDeviceRecognitionSupported: true,
      enhancedModelReady: true,
      foundationModelAvailable: true
    )),
    availabilityProvider: (@MainActor () -> DictationAvailability)? = nil,
    routingNotes: [Note] = [],
    ambiguousRouting: Bool = false,
    cleanupFails: Bool = false,
    historySaveFailureAttempt: Int? = nil,
    historySaveBlockingAttempt: Int? = nil,
    saving: (any DictationSaving)? = nil,
    capsuleSleeper: @escaping @MainActor (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    }
  ) async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("runtime-\(UUID().uuidString)", isDirectory: true)
    initialLoadBlocker = blockInitialLoad ? RuntimeBlockingFileManager() : nil
    let store: LocalStore
    if let initialLoadBlocker {
      nonisolated(unsafe) let fileManager: FileManager = initialLoadBlocker
      store = LocalStore(rootURL: root, fileManager: fileManager)
    } else {
      store = LocalStore(rootURL: root)
    }
    let preferences = AppPreferences(
      dictationSpeechEngine: preferredEngine,
      dictationModifierKey: preferredModifier,
      dictationCapsuleDock: preferredDock,
      dictationCapsuleEnabled: capsuleEnabled
    )
    var workspace = Workspace(
      notes: routingNotes,
      selectedNoteID: routingNotes.first?.id
    )
    workspace.ensureNoteExists()
    let persistedSelectedNoteID = workspace.selectedNoteID
    try await store.save(
      workspace: workspace,
      preferences: preferences,
      trashedNotes: []
    )
    initialLoadBlocker?.beginBlocking()
    appState = AppState(store: store, saveOperation: { _, _, _ in })
    if waitForInitialLoadBeforeRuntime {
      for _ in 0..<100 {
        if appState.selectedNote?.id == persistedSelectedNoteID { break }
        try await Task.sleep(for: .milliseconds(1))
      }
      guard appState.selectedNote?.id == persistedSelectedNoteID else {
        throw DictationSettingsTestError.failed
      }
      appState.preferences = preferences
    }
    monitor.accessGranted = monitorAccessGranted
    monitor.requestAccessResult = monitorRequestAccessResult
    engine = RuntimeSpeechEngine(
      finalText: finalText,
      kind: preferredEngine,
      onRelease: { resourceLifecycle?.append(.engineReleased) }
    )
    provider = RuntimeEngineProvider(engine: engine)
    let historySaveProbe = RuntimeHistorySaveProbe(
      failureAttempt: historySaveFailureAttempt,
      blockingAttempt: historySaveBlockingAttempt,
      gate: historySaveGate
    )
    history = DictationHistoryController(
      load: { [] },
      save: { _ in try await historySaveProbe.save() },
      delete: { _ in },
      clear: {}
    )
    let admittedModelSettingsViewModel = AdmittedModelSettingsViewModel(
      installer: makeAdmittedModelInstaller()
    )
    let coordinator = DictationCoordinator(
      engineProvider: provider,
      preferredEngine: { [weak appState, admittedModelSettingsViewModel] in
        DictationRuntime.effectiveEngine(
          preference: appState?.preferences.dictationSpeechEngine,
          presentation: admittedModelSettingsViewModel.presentation
        )
      },
      cleaner: RuntimeCleaner(fails: cleanupFails),
      router: RuntimeRouter(returnsAmbiguity: ambiguousRouting),
      saver: saving ?? appState,
      historyController: history,
      historyEnabled: { true },
      holdThreshold: .zero,
      holdSleeper: { _ in }
    )
    let shortcut = GlobalHoldShortcut(
      handler: coordinator,
      editorProvider: { [editorRegistry] in editorRegistry.focusedEditor() },
      destinationProvider: { [weak appState] in
        appState?.selectedNote.map {
          DictationDestination(noteID: $0.id, title: $0.displayTitle)
        }
      },
      monitor: monitor,
      escapeRegistrar: escapeRegistrar
    )
    let modelRoot = root.appendingPathComponent("model", isDirectory: true)
    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      let modelManager = DictationModelCapability(
        modelRootURL: modelRoot,
        candidateEnabled: true,
        architectureProvider: { true }
      )
    #else
      let modelManager = DictationModelCapability()
    #endif
    let gate = startupGate
    let log = startupLog
    runtime = DictationRuntime(
      appState: appState,
      modelManager: modelManager,
      engineProvider: provider,
      coordinator: coordinator,
      shortcutController: shortcut,
      capsuleController: DictationCapsuleController(),
      historyController: history,
      permissionController: permissionController,
      editorRegistry: editorRegistry,
      startupAssessment: {
        await log.increment()
        if startupBlocked { await gate.wait() }
      },
      admittedModelSettingsViewModel: admittedModelSettingsViewModel,
      availabilityProvider: availabilityProvider ?? { availability },
      capsuleSleeper: capsuleSleeper,
      startResourceMonitoring: {
        resourceLifecycle?.append(.monitorStarted)
      },
      stopResourceMonitoring: {
        resourceLifecycle?.append(.monitorStopped)
      },
      forceEnhancedInferenceCold: {
        resourceLifecycle?.append(.forceCold)
      }
    )
  }

  func releaseRuntime() {
    runtime = nil
  }
}

@MainActor
private final class RuntimeModifierMonitor: ModifierKeyMonitoring {
  var transitionHandler: ((ModifierKeyTransition) -> Void)?
  var stateHandler: ((ModifierMonitorState) -> Void)?
  var accessGranted = true
  var requestAccessResult = true
  var startError: Error?
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var requestCount = 0

  func start() throws {
    startCount += 1
    if let startError { throw startError }
    stateHandler?(.running)
  }

  func stop() {
    stopCount += 1
    stateHandler?(.stopped)
  }

  func requestAccess() -> Bool {
    requestCount += 1
    accessGranted = requestAccessResult
    return requestAccessResult
  }

  func emit(_ transition: ModifierKeyTransition) {
    transitionHandler?(transition)
  }

  func publish(_ state: ModifierMonitorState) {
    stateHandler?(state)
  }
}

@MainActor
private final class RuntimeEscapeRegistrar: EscapeHotKeyRegistering {
  var eventHandler: (() -> Void)?

  func register() throws {}
  func unregister() {}
}

@MainActor
private final class RuntimeEngineProvider: SpeechEngineProviding {
  let engine: RuntimeSpeechEngine
  var gate: DictationTestGate?
  var error: Error?
  private(set) var requestedKinds: [DictationSpeechEngine] = []
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var requestCount = 0

  init(engine: RuntimeSpeechEngine) {
    self.engine = engine
  }

  func engineForCapture(preferred: DictationSpeechEngine) async throws -> any SpeechEngine {
    requestCount += 1
    requestedKinds.append(preferred)
    let waiters = requestWaiters
    requestWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if let gate { await gate.wait() }
    if let error { throw error }
    return engine
  }

  func waitUntilRequested() async {
    guard requestCount == 0 else { return }
    await withCheckedContinuation { requestWaiters.append($0) }
  }
}

@MainActor
private final class RuntimeSpeechEngine: SpeechEngine {
  let kind: DictationSpeechEngine
  let finalText: String?
  var startGate: DictationTestGate?
  var finishGate: DictationTestGate?
  var releaseGate: DictationTestGate?
  private(set) var releaseCount = 0
  private var level: (@MainActor (Float) -> Void)?
  private var levelCallbacks: [@MainActor (Float) -> Void] = []

  var captureCallbackCount: Int { levelCallbacks.count }

  init(
    finalText: String?,
    kind: DictationSpeechEngine = .standard,
    onRelease: (() -> Void)? = nil
  ) {
    self.finalText = finalText
    self.kind = kind
    self.onRelease = onRelease
  }

  private let onRelease: (() -> Void)?

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws {
    self.level = level
    levelCallbacks.append(level)
    if let startGate { await startGate.wait() }
  }

  func finish() async throws -> String? {
    if let finishGate { await finishGate.wait() }
    return finalText
  }

  func cancel() async {}
  func emitLevel(_ value: Float) { level?(value) }
  func emitLevel(fromCaptureAt index: Int, value: Float) {
    levelCallbacks[index](value)
  }
  func releaseResources() async {
    releaseCount += 1
    if let releaseGate { await releaseGate.wait() }
    onRelease?()
  }
}

private struct RuntimeCleaner: TranscriptCleaning {
  let fails: Bool

  init(fails: Bool = false) {
    self.fails = fails
  }

  func clean(_ transcript: String) async throws -> String {
    if fails { throw DictationSettingsTestError.failed }
    return transcript
  }
}

@MainActor
private final class RuntimeSaving: DictationSaving {
  let error: Error?
  let destination = DictationDestination(noteID: UUID(), title: "Inbox")

  init(error: Error? = nil) {
    self.error = error
  }

  func activeDestinations() -> [DictationRoutingCandidate] {
    [DictationRoutingCandidate(destination: destination, semanticContext: "")]
  }

  func saveSmartCapture(
    text: String,
    captureID: UUID,
    destinationID: UUID?
  ) async throws -> DictationInsertionReceipt {
    if let error { throw error }
    return DictationInsertionReceipt(
      captureID: captureID,
      noteID: destination.noteID,
      insertedSuffix: text
    )
  }

  func undoSmartCapture(_ receipt: DictationInsertionReceipt) async -> Bool {
    true
  }

  func flushFocusedDictationSave(
    captureID: UUID
  ) async throws -> FocusedDictationPersistenceReceipt {
    FocusedDictationPersistenceReceipt(captureID: captureID)
  }

  func compensateFocusedDictationSave(
    _ receipt: FocusedDictationPersistenceReceipt
  ) async -> Bool {
    true
  }
}

private struct RuntimeRouter: DestinationRouting {
  let returnsAmbiguity: Bool

  init(returnsAmbiguity: Bool = false) {
    self.returnsAmbiguity = returnsAmbiguity
  }

  func route(
    transcript: String,
    candidates: [DictationRoutingCandidate],
    inboxID: UUID?
  ) async -> DictationRoutingDecision {
    if returnsAmbiguity {
      return .ambiguous(candidates.prefix(4).map {
        DictationRoutingChoice(
          destination: $0.destination,
          contextHint: DictationRoutingChoice.boundedContextHint(from: $0.semanticContext)
        )
      })
    }
    return .inbox
  }
}

private actor RuntimeCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

private actor RuntimeHistorySaveProbe {
  let failureAttempt: Int?
  let blockingAttempt: Int?
  let gate: DictationTestGate
  private var attempts = 0

  init(
    failureAttempt: Int?,
    blockingAttempt: Int?,
    gate: DictationTestGate
  ) {
    self.failureAttempt = failureAttempt
    self.blockingAttempt = blockingAttempt
    self.gate = gate
  }

  func save() async throws {
    attempts += 1
    if attempts == blockingAttempt {
      await gate.wait()
    }
    if attempts == failureAttempt {
      throw DictationSettingsTestError.failed
    }
  }
}

private actor RuntimeCapsuleSleeper {
  private(set) var requestedDurations: [Duration] = []
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private var requestObservers: [CheckedContinuation<Void, Never>] = []

  func sleep(_ duration: Duration) async {
    requestedDurations.append(duration)
    let observers = requestObservers
    requestObservers.removeAll()
    observers.forEach { $0.resume() }
    await withCheckedContinuation { continuations.append($0) }
  }

  func waitForRequest() async {
    guard requestedDurations.isEmpty else { return }
    await withCheckedContinuation { requestObservers.append($0) }
  }

  func resumeAll() {
    let pending = continuations
    continuations.removeAll()
    pending.forEach { $0.resume() }
  }
}

private final class RuntimeBlockingFileManager: FileManager, @unchecked Sendable {
  private let lock = NSLock()
  private let releaseSemaphore = DispatchSemaphore(value: 0)
  private var isBlocking = false
  private var didBlock = false

  var hasBlocked: Bool {
    lock.withLock { didBlock }
  }

  func beginBlocking() {
    lock.withLock {
      isBlocking = true
      didBlock = false
    }
  }

  func release() {
    let shouldSignal = lock.withLock {
      let shouldSignal = isBlocking
      isBlocking = false
      return shouldSignal
    }
    if shouldSignal {
      releaseSemaphore.signal()
    }
  }

  override func createDirectory(
    at url: URL,
    withIntermediateDirectories createIntermediates: Bool,
    attributes: [FileAttributeKey: Any]? = nil
  ) throws {
    try super.createDirectory(
      at: url,
      withIntermediateDirectories: createIntermediates,
      attributes: attributes
    )
    let shouldBlock = lock.withLock {
      guard isBlocking else { return false }
      didBlock = true
      return true
    }
    if shouldBlock {
      releaseSemaphore.wait()
    }
  }
}

@MainActor
private final class RuntimeCapsuleOrderProbe: NSObject {
  private(set) var count = 0
  private let panel: NSPanel

  init(panel: NSPanel) {
    self.panel = panel
    super.init()
    panel.addObserver(
      self,
      forKeyPath: "visible",
      options: [.new],
      context: nil
    )
  }

  func stop() {
    panel.removeObserver(self, forKeyPath: "visible")
  }

  override nonisolated func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    guard
      keyPath == "visible",
      change?[.newKey] as? Bool == true
    else { return }
    MainActor.assumeIsolated {
      count += 1
    }
  }
}

@MainActor
private final class RuntimeBool {
  var value = false
}

@MainActor
private final class RuntimeAvailabilityBox {
  var value: DictationAvailability

  init(_ value: DictationAvailability) {
    self.value = value
  }
}

private actor RuntimeCompletionProbe {
  private(set) var isComplete = false

  func complete() {
    isComplete = true
  }
}
