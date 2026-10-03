import AppKit
import CoreGraphics
import Foundation
import FleckCore
import ObjectiveC.runtime
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
  let modelsViewSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/ModelsView.swift"),
    encoding: .utf8
  )

  #expect(!source.contains("@ObservedObject private var speechViewModel"))
  #expect(!source.contains("@ObservedObject private var cleanupViewModel"))
  #expect(!source.contains("AdmittedModelSettingsPresentation"))
  #expect(!source.contains("SettingsPreferenceRow(\n          \"Dictation model\""))
  #expect(!source.contains("SettingsPreferenceRow(\n          \"Cleanup model\""))
  #expect(!source.contains(#"Section("Speech Engine")"#))
  #expect(!source.contains(#"Text("Active engine:"#))
  #expect(source.contains("private var dictationReadinessButton: some View"))
  #expect(source.contains("private var dictationReadinessPopover: some View"))
  #expect(source.contains(".popover(isPresented: $isReadinessPopoverPresented"))
  #expect(source.contains(".settingsSearchAnchor(.dictationStatus, request: searchRequest)"))
  #expect(source.contains(".accessibilityIdentifier(\"settings-dictation-readiness-button\")"))
  #expect(source.contains(".accessibilityIdentifier(\"settings-dictation-readiness-popover\")"))
  #expect(source.contains("accessibilityValue(isReady ? \"Ready\" : \"Needs attention\")"))
  #expect(source.contains(".accessibilityHint(\"Show dictation readiness and recovery actions.\")"))
  #expect(source.contains("if !dictationModifierPresentation.isReady"))
  #expect(source.contains("ForEach(availabilityIssues, id: \\.title)"))
  #expect(source.contains("ForEach(recoveryActions, id: \\.pane)"))
  #expect(source.contains("runtime.openSystemSettings(action)"))
  #expect(source.contains("case .enableInputMonitoring"))
  #expect(source.contains("Button(\"Enable Input Monitoring\")"))
  #expect(source.contains("case .retry"))
  #expect(source.contains("Button(\"Retry\")"))
  #expect(source.contains("Button(\"Open Models\", action: openModelsFromSettingsNavigation)"))
  #expect(source.contains("private var modelsLink: some View"))
  #expect(source.contains(".buttonStyle(.link)"))
  #expect(source.contains("private var modelsBrowser: some View"))
  #expect(source.contains("ModelsBrowserView("))
  #expect(source.contains("if section == .models"))
  #expect(source.contains("if result.destination == .models"))
  #expect(source.contains("selectedSection = .models"))
  #expect(!source.contains("ModelLibraryLayout.windowIdentifier"))
  #expect(source.contains("SettingsPreferenceRow(\n          \"Appearance\""))
  #expect(source.contains("SettingsPreferenceRow(\n          \"Color theme\""))
  #expect(source.contains("SettingsPreferenceRow(\n          \"Width\""))
  #expect(source.contains("ScrollView"))
  #expect(runtimeSource.contains(".defaultSize(width: 840, height: 600)"))
  #expect(runtimeSource.contains(".windowResizability(.contentMinSize)"))
  #expect(source.contains(".accessibilityElement(children: .contain)"))
  #expect(modelsViewSource.contains(".accessibilityLabel(\"Installation state\")"))
  #expect(modelsViewSource.contains(".accessibilityValue(presentation.compactStatus)"))
  #expect(modelsViewSource.contains("External results"))
  #expect(modelsViewSource.contains("ModelLibraryExternalEvidenceCatalog.evidence(for: entry.descriptor)"))
  #expect(!modelsViewSource.contains("≈110× RTF"))
  #expect(!modelsViewSource.contains("2.01% WER"))
  #expect(!modelsViewSource.contains("≈212 decode tok/s"))
  #expect(modelsViewSource.contains("Cleanup accuracy"))
  #expect(!modelsViewSource.contains("Benchmarks"))
  #expect(!modelsViewSource.contains("ratingSlots"))
  #expect(modelsViewSource.contains("await speechViewModel.refresh()"))
  #expect(modelsViewSource.contains("await cleanupViewModel.refresh()"))
  #expect(modelsViewSource.contains("entry.viewModel.perform(action)"))
  #expect(modelsViewSource.contains("ProgressView(value: progress)"))
  #expect(modelsViewSource.contains(#".accessibilityLabel("\(entry.title) installation progress")"#))
  #expect(modelsViewSource.contains(".focused($focusedModelID, equals: entry.id)"))
  #expect(modelsViewSource.contains(#".accessibilityIdentifier("models-action-\(entry.id)")"#))
  #expect(modelsViewSource.contains("Button(role: action == .remove ? .destructive : nil)"))
  #expect(!runtimeSource.contains("Window(\"Models\", id:"))
  #expect(runtimeSource.contains("SettingsView(runtime: dictationRuntime)"))
  #expect(runtimeSource.contains(".windowResizability(.contentMinSize)"))
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
    "Sources/FleckApp/ModelsView.swift",
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
    #".accessibilityLabel("\(entry.title) installation progress")"#
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
  #expect(SettingsSection.voiceAndWritingCases == [.dictation, .models, .vocabulary])
  #expect(SettingsSection.connectionCases == [.agents])
  #expect(SettingsSection.informationCases == [.about])
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

@Test @MainActor
func DictationSettingsHostedSidebarSelectionUsesPaletteInKeyWindow() async throws {
  let application = NSApplication.shared
  try await withSettingsTestApplicationActivationState(application) {
    for family in [FleckColorTheme.monochrome, .capy] {
      let theme = FleckThemeSnapshot.resolve(
        colorTheme: family,
        mode: .dark,
        systemAppearance: .dark,
        reduceTransparency: false,
        increasedContrast: false
      )
      let host = NSHostingView(
        rootView: SettingsSidebarThemeTestHost()
          .environment(\.fleckThemeSnapshot, theme)
          .environment(\.colorScheme, .dark)
          .frame(width: 220, height: 520)
          .background(theme.color(.sidebar))
      )
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 220, height: 520),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.appearance = NSAppearance(named: .darkAqua)
      window.contentView = host
      defer {
        window.contentView = nil
        window.orderOut(nil)
      }
      window.makeKeyAndOrderFront(nil)
      try #require(await activateSettingsTestApplication(application, keyWindow: window))
      await settleSettingsHost(host)
      try #require(
        await waitForSettingsAppKitState {
          application.isActive && application.keyWindow === window && window.isKeyWindow
        }
      )

      let outline = try #require(settingsSidebarTableView(of: host) as? NSOutlineView)
      let row = try #require(settingsSidebarRow(.appearance, in: outline))

      #expect(window.isKeyWindow)
      #expect(outline.selectedRow == row)
      #expect(outline.accessibilitySelectedRows()?.count == 1)
      #expect(outline.selectionHighlightStyle == .none)
      let rowView = try #require(outline.rowView(atRow: row, makeIfNecessary: true))
      let image = try #require(rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds))
      rowView.cacheDisplay(in: rowView.bounds, to: image)
      let fill = try #require(
        image.colorAt(
          x: Int(CGFloat(image.pixelsWide) * 0.85),
          y: image.pixelsHigh / 2
        ))
      let expectedFill = theme.nsColor(.selectionFill)
      #expect(abs(fill.redComponent - expectedFill.redComponent) < 0.12)
      #expect(abs(fill.greenComponent - expectedFill.greenComponent) < 0.12)
      #expect(abs(fill.blueComponent - expectedFill.blueComponent) < 0.12)
      #expect(fill.blueComponent < 0.5)
      let expectedInk = theme.nsColor(.selectionText)
      func hasSelectedInk(_ image: NSBitmapImageRep) -> Bool {
        (0..<image.pixelsHigh).contains { y in
          (20..<Int(CGFloat(image.pixelsWide) * 0.65)).contains { x in
            guard let pixel = image.colorAt(x: x, y: y) else { return false }
            return abs(pixel.redComponent - expectedInk.redComponent) < 0.05
              && abs(pixel.greenComponent - expectedInk.greenComponent) < 0.05
              && abs(pixel.blueComponent - expectedInk.blueComponent) < 0.05
          }
        }
      }
      #expect(hasSelectedInk(image))
      if family == .monochrome {
        #expect(abs(fill.redComponent - fill.greenComponent) < 0.04)
      } else {
        #expect(fill.greenComponent > fill.redComponent + 0.07)
      }

      if let captureDirectory = ProcessInfo.processInfo.environment[
        "FLECK_SETTINGS_SIDEBAR_CAPTURE_DIR"
      ] {
        let directory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screenshot = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: screenshot)
        let png = try #require(screenshot.representation(using: .png, properties: [:]))
        try png.write(
          to: directory.appendingPathComponent("settings-sidebar-\(family.rawValue).png"))
      }

      let otherWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 180, height: 120),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
      )
      defer { otherWindow.orderOut(nil) }
      otherWindow.makeKeyAndOrderFront(nil)
      await settleSettingsHost(host)
      try #require(
        await waitForSettingsAppKitState {
          application.isActive
            && application.keyWindow === otherWindow
            && otherWindow.isKeyWindow
            && !window.isKeyWindow
        }
      )
      #expect(!window.isKeyWindow)
      #expect(outline.selectedRow == row)
      #expect(outline.accessibilitySelectedRows()?.count == 1)
      let inactiveImage = try #require(rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds))
      rowView.cacheDisplay(in: rowView.bounds, to: inactiveImage)
      let inactiveFill = try #require(
        inactiveImage.colorAt(
          x: Int(CGFloat(inactiveImage.pixelsWide) * 0.85),
          y: inactiveImage.pixelsHigh / 2
        ))
      #expect(abs(inactiveFill.redComponent - fill.redComponent) < 0.04)
      #expect(abs(inactiveFill.greenComponent - fill.greenComponent) < 0.04)
      #expect(abs(inactiveFill.blueComponent - fill.blueComponent) < 0.04)
      #expect(hasSelectedInk(inactiveImage))
    }
  }
}

private struct SettingsSidebarThemeTestHost: View {
  @State private var selection = SettingsSection.appearance

  var body: some View {
    SettingsSectionSidebar(selection: $selection)
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
  #expect(source.contains(".padding(.top, 44)"))
  #expect(source.contains("settings-fleck-sidebar-heading"))
  #expect(source.contains("Text(\"Fleck\")"))
  #expect(source.contains("sectionRows(SettingsSection.fleckCases)"))
  #expect(!source.contains(".padding(.leading, 58)"))
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
  #expect(settingsSource.contains("SettingsPreferenceRow(\n          \"Appearance\""))
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

  #expect(!source.contains("Glass.regular.tint(Color.primary.opacity"))
  #expect(!source.contains("Color.primary.opacity(0.04)"))
  #expect(source.contains(".glassEffect(.regular, in: shape)"))
  #expect(source.contains("shape.fill(.ultraThinMaterial)"))
  #expect(source.contains("FleckChromeMaterialPolicy.current("))
  #expect(source.contains("reduceTransparency: reduceTransparency"))
  #expect(source.contains("increasedContrast: colorSchemeContrast == .increased"))
  #expect(source.contains("theme.color(.window)"))
  #expect(source.contains("theme.color(.sidebar)"))
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
    "Capture",
    "Experience & history",
    "Privacy",
  ])
  #expect(source.contains("private var dictationReadinessButton: some View"))
  #expect(source.contains("private var dictationReadinessPopover: some View"))
  #expect(source.contains("private var dictationModifierRecoveryButton: some View"))
  #expect(source.contains(".settingsSearchAnchor(.dictationStatus, request: searchRequest)"))
  #expect(source.contains(".accessibilityLabel(\"Dictation readiness\")"))
  #expect(source.contains(".accessibilityValue(isReady ? \"Ready\" : \"Needs attention\")"))
  #expect(source.contains(
    ".accessibilityHint(\"Show dictation readiness and recovery actions.\")"
  ))
  #expect(source.contains(".accessibilityIdentifier(\"settings-dictation-readiness-button\")"))
  #expect(source.contains("Text(DictationSettingsGroup.capture.rawValue)"))
  #expect(source.contains(
    "Text(DictationSettingsGroup.experience.rawValue)"
  ))
  #expect(source.contains("isReady ? \"Ready\" : \"Needs attention\""))
  #expect(source.contains("private var modelsLink: some View"))
  #expect(source.contains("Button(\"Open Models\", action: openModelsFromSettingsNavigation)"))
  #expect(source.contains("DisclosureGroup(isExpanded: $isDictationPrivacyExpanded)"))
  #expect(!source.contains("Text(DictationSettingsGroup.models.rawValue)"))
  #expect(!source.contains("SettingsSectionCard(\"Controls\")"))

  let captureStart = try #require(source.range(of: "private var capture: some View {"))
  let experienceStart = try #require(source.range(
    of: "private var experienceAndHistory: some View {",
    range: captureStart.upperBound..<source.endIndex
  ))
  let captureSource = source[captureStart.lowerBound..<experienceStart.lowerBound]
  #expect(captureSource.contains("dictationModifierRecoveryButton"))

  let readinessPopoverStart = try #require(
    source.range(of: "private var dictationReadinessPopover: some View {")
  )
  let readinessEnd = try #require(source.range(
    of: "private var isDictationReady:",
    range: readinessPopoverStart.upperBound..<source.endIndex
  ))
  let readinessPopoverSource = source[readinessPopoverStart.lowerBound..<readinessEnd.lowerBound]
  #expect(readinessPopoverSource.contains("ScrollView(.vertical)"))
  #expect(readinessPopoverSource.contains(
    ".frame(width: 340, height: isReady ? 160 : 300, alignment: .topLeading)"
  ))
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
    "        modelsLink",
    "        capture",
    "        experienceAndHistory",
    "        DisclosureGroup(isExpanded: $isDictationPrivacyExpanded)",
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
func DictationSettingsModelsPaneKeepsSidebarAndFitsRequestedSizes() async throws {
  let previousAccessibility = enableSettingsAccessibility()
  defer { restoreSettingsAccessibility(previousAccessibility) }
  let modelViewModels = try fixtureModelViewModels()
  let fixture = try await RuntimeFixture(
    finalText: nil,
    capsuleEnabled: false,
    speechModelViewModel: modelViewModels.speech,
    cleanupModelViewModel: modelViewModels.cleanup
  )
  let sizes = [NSSize(width: 840, height: 600), NSSize(width: 760, height: 520)]
  let speechID = ModelLibraryEntry.pinKey(
    for: .asr,
    modelID: ModelLibraryCatalog.parakeetModelID
  )
  let cleanupID = ModelLibraryEntry.pinKey(
    for: .cleanup,
    modelID: ModelLibraryCatalog.gemmaModelID
  )

  for size in sizes {
    let host = NSHostingView(
      rootView: SettingsView(runtime: fixture.runtime)
        .environmentObject(fixture.appState)
        .fleckTheme(fixture.appState)
    )
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .resizable, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Settings"
    window.contentView = host
    window.setContentSize(size)
    window.makeKeyAndOrderFront(nil)
    await settleSettingsHost(host)

    let outline = try #require(settingsSidebarTableView(of: host) as? NSOutlineView)
    let modelsRow = try #require(settingsSidebarRow(.models, in: outline))
    outline.selectRowIndexes(IndexSet(integer: modelsRow), byExtendingSelection: false)
    NotificationCenter.default.post(
      name: NSTableView.selectionDidChangeNotification,
      object: outline
    )
    await settleSettingsHost(host)

    let sidebarFrame = outline.convert(outline.bounds, to: nil)
    let browser = try #require(settingsView(withAccessibilityIdentifier: "models-browser", in: host))
    let browserFrame = browser.convert(browser.bounds, to: nil)
    #expect(outline.selectedRow == modelsRow)
    #expect(!outline.isHidden)
    #expect(!sidebarFrame.isEmpty)
    #expect(!browserFrame.isEmpty)
    #expect(ModelLibraryLayout.stacksDetails(width: browserFrame.width, dynamicTypeSize: .medium))
    #expect(settingsAccessibilityElements(in: host, identifier: "models-provider-filter").count == 1)
    #expect(settingsAccessibilityElements(in: host, identifier: "models-type-filter").count == 1)
    #expect(
      settingsAccessibilityElements(in: host, identifier: "models-row-\(speechID)").count == 1
    )
    #expect(
      settingsAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").count == 1
    )
    let speechRow = try #require(
      settingsAccessibilityElements(in: host, identifier: "models-row-\(speechID)").first
    )
    let speechValue = try #require(settingsAccessibilityValue(speechRow))
    #expect(speechValue.contains("Overall audio throughput: 145.8× RTFx"))
    #expect(speechValue.contains("Mean per-file WER: 2.1%"))
    #expect(speechValue.contains("External benchmark on M4 Pro"))
    #expect(!speechValue.contains("LibriSpeech test-clean"))
    #expect(!speechValue.contains("asr-benchmark"))
    let cleanupRow = try #require(
      settingsAccessibilityElements(in: host, identifier: "models-row-\(cleanupID)").first
    )
    let cleanupValue = try #require(settingsAccessibilityValue(cleanupRow))
    #expect(cleanupValue.contains("Aggregate output throughput: 204.29 output tok/s"))
    #expect(cleanupValue.contains("Cleanup accuracy: Not measured"))
    #expect(cleanupValue.contains("External benchmark on M4 Max"))
    #expect(!cleanupValue.contains("65,536 output tokens"))
    #expect(!cleanupValue.contains("128 prompts"))
    #expect(
      settingsAccessibilityElements(in: host, identifier: "models-action-\(speechID)").count == 1
    )

    var sort = try #require(
      settingsAccessibilityElements(in: host, identifier: "models-sort-name").first
    )
    if settingsAccessibilityValue(sort) != "A to Z" {
      #expect(performSettingsAccessibilityPress(sort))
      await settleSettingsHost(host)
      sort = try #require(
        settingsAccessibilityElements(in: host, identifier: "models-sort-name").first
      )
    }
    #expect(settingsAccessibilityValue(sort) == "A to Z")

    if let captureDirectory = ProcessInfo.processInfo.environment[
      "FLECK_SETTINGS_MODELS_CAPTURE_DIR"
    ] {
      let directory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: image)
      let png = try #require(image.representation(using: .png, properties: [:]))
      try png.write(
        to: directory.appendingPathComponent(
          "settings-models-\(Int(size.width))x\(Int(size.height)).png"
        )
      )
    }

    #expect(performSettingsAccessibilityPress(sort))
    await settleSettingsHost(host)
    sort = try #require(
      settingsAccessibilityElements(in: host, identifier: "models-sort-name").first
    )
    #expect(settingsAccessibilityValue(sort) == "Z to A")

    #expect(performSettingsAccessibilityPress(sort))
    await settleSettingsHost(host)
    let ascendingSort = try #require(
      settingsAccessibilityElements(in: host, identifier: "models-sort-name").first
    )
    #expect(settingsAccessibilityValue(ascendingSort) == "A to Z")
    window.contentView = nil
    window.orderOut(nil)
  }
}

@Test @MainActor
func DictationSettingsOpenModelsAndSearchNavigateIntoTheSamePane() async throws {
  let previousAccessibility = enableSettingsAccessibility()
  defer { restoreSettingsAccessibility(previousAccessibility) }
  let modelViewModels = try fixtureModelViewModels()
  let fixture = try await RuntimeFixture(
    finalText: nil,
    capsuleEnabled: false,
    speechModelViewModel: modelViewModels.speech,
    cleanupModelViewModel: modelViewModels.cleanup
  )
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
  window.title = "Settings"
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  defer {
    window.contentView = nil
    window.orderOut(nil)
  }
  await settleSettingsHost(host)

  let outline = try #require(settingsSidebarTableView(of: host) as? NSOutlineView)
  let dictationRow = try #require(settingsSidebarRow(.dictation, in: outline))
  outline.selectRowIndexes(IndexSet(integer: dictationRow), byExtendingSelection: false)
  NotificationCenter.default.post(
    name: NSTableView.selectionDidChangeNotification,
    object: outline
  )
  await settleSettingsHost(host)

  let openModels = try #require(
    settingsAccessibilityElements(in: host, identifier: "settings-dictation-open-models").first
  )
  #expect(performSettingsAccessibilityPress(openModels))
  await settleSettingsHost(host)

  let modelsRow = try #require(settingsSidebarRow(.models, in: outline))
  #expect(outline.selectedRow == modelsRow)
  #expect(settingsView(withAccessibilityIdentifier: "models-browser", in: host) != nil)

  let searchField = try #require(
    settingsView(withAccessibilityIdentifier: "settings-search-field", in: host) as? NSSearchField
  )
  searchField.stringValue = "Cleanup model"
  let searchCoordinator = try #require(searchField.delegate as? SettingsSearchField.Coordinator)
  searchCoordinator.controlTextDidChange(
    Notification(name: NSControl.textDidChangeNotification, object: searchField)
  )
  await settleSettingsHost(host)
  #expect(
    SettingsSearchIndex.results(for: searchField.stringValue).first?.target
      == .dictationCleanupModel
  )
  #expect(searchCoordinator.control(
    searchField,
    textView: NSTextView(),
    doCommandBy: #selector(NSResponder.insertNewline(_:))
  ))
  await settleSettingsHost(host)

  #expect(outline.selectedRow == modelsRow)
  #expect(searchField.stringValue.isEmpty)
  #expect(settingsView(withAccessibilityIdentifier: "models-browser", in: host) != nil)
}

@Test @MainActor
func DictationSettingsHostedWindowUsesNormalMinimizableChromeWithoutFullScreen()
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
  window.level = .floating
  window.collectionBehavior = [.fullScreenPrimary]
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleSettingsHost(host)

  #expect(window.level == .normal)
  #expect(window.isResizable)
  #expect(window.styleMask.contains(.miniaturizable))
  let minimizeButton = try #require(window.standardWindowButton(.miniaturizeButton))
  #expect(!minimizeButton.isHidden)
  #expect(minimizeButton.isEnabled)
  #expect(minimizeButton.target === window)
  #expect(minimizeButton.action == #selector(NSWindow.miniaturize(_:)))
  #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
  #expect(window.collectionBehavior.contains(.fullScreenNone))
  #expect(!window.collectionBehavior.contains(.fullScreenPrimary))
  #expect(!window.collectionBehavior.contains(.fullScreenAuxiliary))

  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor
func DictationSettingsHostedWindowKeepsNativeChromeStableAcrossDestinations()
  async throws
{
  let application = NSApplication.shared
  try requireSettingsTestApplicationBaseline(application)
  let previousAccessibility = enableSettingsAccessibility()
  defer { restoreSettingsAccessibility(previousAccessibility) }
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
        .fleckTheme(fixture.appState)
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
    application.activate(ignoringOtherApps: true)
    await settleSettingsHost(host)
    window.displayIfNeeded()
    host.displayIfNeeded()
    await settleSettingsHost(host)
    #expect(application.isActive, "Expected NSApp to be active for the hosted Settings window")
    #expect(window.isKeyWindow, "Expected the hosted Settings window to be key")

    #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
    #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == false)
    #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
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
      window.displayIfNeeded()
      host.displayIfNeeded()
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
      let currentTrafficLightFrames = trafficLightButtons.compactMap { button in
        button.map { $0.convert($0.bounds, to: nil) }
      }
      #expect(currentTrafficLightFrames.allSatisfy { !$0.intersects(sidebarFrame) })

      if destination == .models {
        let modelsBrowser = try #require(
          settingsView(withAccessibilityIdentifier: "models-browser", in: host)
        )
        let modelsBrowserFrame = modelsBrowser.convert(modelsBrowser.bounds, to: nil)
        #expect(!modelsBrowserFrame.isEmpty)
        #expect(baselineLayoutRect.contains(modelsBrowserFrame.center))
        #expect(modelsBrowserFrame.minX >= baselineLayoutRect.minX - 1)
        #expect(modelsBrowserFrame.maxX <= baselineLayoutRect.maxX + 1)
        #expect(modelsBrowserFrame.minY >= baselineLayoutRect.minY - 1)
        #expect(modelsBrowserFrame.maxY <= baselineLayoutRect.maxY + 1)
        #expect(modelsBrowserFrame.width >= 400)
        #expect(
          ModelLibraryLayout.stacksDetails(
            width: modelsBrowserFrame.width,
            dynamicTypeSize: .large
          )
        )
        #expect(
          settingsAccessibilityElements(in: host, identifier: "models-provider-filter").count
            == 1
        )
        #expect(
          settingsAccessibilityElements(in: host, identifier: "models-type-filter").count == 1
        )
        continue
      }

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
      let pageTitleName = destination == .vocabulary ? "Dictionary" : destination.rawValue
      let pageTitleProbes = settingsSidebarDescendants(of: detailDocument).filter {
        String(reflecting: type(of: $0)).contains("SettingsPageHeaderProbe")
      }
      #expect(pageTitleProbes.count == 1, "Expected visible \(pageTitleName) page title")
      guard let pageTitle = pageTitleProbes.first else { continue }
      #expect(pageTitle.isDescendant(of: detailDocument))
      #expect(settingsScrollViewAncestor(of: pageTitle) === detailScroll)
      let pageTitleFrame = pageTitle.convert(pageTitle.bounds, to: nil)
      #expect(!pageTitleFrame.isEmpty)
      #expect(detailFrame.contains(pageTitleFrame.center))
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
func DictationSettingsReadinessPopoverIsAccessibleAtMinimumWindowSize() async throws {
  let application = NSApplication.shared
  try await withSettingsTestApplicationActivationState(application) {
    let fixture = try await RuntimeFixture(
      finalText: nil,
      capsuleEnabled: false,
      monitorAccessGranted: false,
      monitorRequestAccessResult: false,
      permissionController: DictationPermissionController(
        microphoneStatus: { .denied },
        speechStatus: { .denied }
      ),
      availability: .evaluate(
        .init(
          osMajorVersion: 13,
          architecture: .intel,
          microphonePermission: .denied,
          speechPermission: .denied,
          appleOnDeviceRecognitionSupported: false,
          enhancedModelReady: false,
          foundationModelAvailable: false
        ))
    )
    await fixture.runtime.awaitStartupAssessment()
    fixture.runtime.preferencesDidChange()
    #expect(fixture.runtime.modifierMonitorState == .unauthorized)

    let host = NSHostingView(
      rootView: SettingsView(runtime: fixture.runtime)
        .environmentObject(fixture.appState)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.colorScheme, .light)
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 840, height: 600),
      styleMask: [.titled, .resizable, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Settings"
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.center()
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    window.makeKeyAndOrderFront(nil)
    try #require(
      await activateSettingsTestApplication(application, keyWindow: window)
    )
    await settleSettingsHost(host)

    let sidebar = try #require(settingsSidebarTableView(of: host) as? NSOutlineView)
    let dictationRow = try #require(settingsSidebarRow(.dictation, in: sidebar))
    sidebar.selectRowIndexes(IndexSet(integer: dictationRow), byExtendingSelection: false)
    NotificationCenter.default.post(
      name: NSTableView.selectionDidChangeNotification,
      object: sidebar
    )
    await settleSettingsHost(host)

    let readinessAnchor = try #require(
      settingsView(
        withAccessibilityIdentifier: "settings-search-target-dictation-status",
        in: host
      )
    )
    let readinessCenter = readinessAnchor.convert(
      NSPoint(x: readinessAnchor.bounds.midX, y: readinessAnchor.bounds.midY),
      to: nil
    )
    try #require(
      await waitForSettingsAppKitState {
        application.isActive && application.keyWindow === window && window.isKeyWindow
      }
    )
    let mouseDown = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: readinessCenter,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
      ))
    let mouseUp = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: readinessCenter,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 2,
        clickCount: 1,
        pressure: 0
      ))
    NSApp.sendEvent(mouseDown)
    NSApp.sendEvent(mouseUp)
    await settleSettingsHost(host)

    #expect(
      settingsView(
        withAccessibilityIdentifier: "settings-keyboard-focus-dictation-status", in: host)
        != nil
    )
    #expect(
      settingsView(
        withAccessibilityIdentifier: "settings-keyboard-focus-cue-dictation-status",
        in: host
      ) == nil
    )

    let popoverWindow = try #require(
      NSApplication.shared.windows.first {
        $0 !== window
          && $0.contentView.map {
            settingsView(
              withAccessibilityIdentifier: "settings-dictation-readiness-popover",
              in: $0
            ) != nil
          } == true
      }
    )
    defer { popoverWindow.orderOut(nil) }
    let popover = try #require(popoverWindow.contentView)
    await settleSettingsHost(popover)
    popoverWindow.displayIfNeeded()
    let popoverScrollViews = settingsHostedScrollViews(of: popover)
    let scrollView = try #require(popoverScrollViews.first)
    let documentView = try #require(scrollView.documentView)
    let visibleViewportHeight =
      scrollView.contentView.bounds.height
      - scrollView.contentInsets.top
      - scrollView.contentInsets.bottom
    #expect(scrollView.hasVerticalScroller)
    #expect(visibleViewportHeight <= 300)
    #expect(documentView.frame.height > visibleViewportHeight)

    let captureDirectory = ProcessInfo.processInfo.environment[
      "FLECK_SETTINGS_WINDOW_CAPTURE_DIR"
    ]
    if let captureDirectory {
      let directory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let visibleFrame = try #require(window.screen?.visibleFrame)
      popoverWindow.setFrameOrigin(
        NSPoint(
          x: visibleFrame.midX - popoverWindow.frame.width / 2,
          y: visibleFrame.midY - popoverWindow.frame.height / 2
        ))
      await settleSettingsHost(popover)
      popoverWindow.displayIfNeeded()
      for (name, captureWindow) in [
        ("settings-dictation-840x600", window),
        ("settings-dictation-readiness-popover", popoverWindow),
      ] {
        let cgImage = try #require(
          CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(captureWindow.windowNumber),
            .bestResolution
          ))
        if captureWindow === window {
          #expect(cgImage.width >= 840)
          #expect(cgImage.height >= 600)
        } else if cgImage.width < 300 || cgImage.height < 250 {
          print(
            "Readiness popover window-level capture was incomplete: "
              + "\(cgImage.width)×\(cgImage.height) pixels for a "
              + "\(Int(captureWindow.frame.width))×\(Int(captureWindow.frame.height))-point window."
          )
          continue
        }
        let image = NSBitmapImageRep(cgImage: cgImage)
        let png = try #require(image.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
      }
    }
    #expect(
      settingsView(
        withAccessibilityIdentifier: "settings-dictation-readiness-popover",
        in: popover
      ) != nil
    )
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
  ]
  let trafficLightFrames: [NSRect] = trafficLightButtons.compactMap { button in
    guard let button else { return nil }
    return button.convert(button.bounds, to: nil)
  }
  #expect(trafficLightFrames.count == 2)
  #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
  #expect(trafficLightFrames.allSatisfy {
    settingsRoundedSurfaceContains(
      $0,
      in: surfaceFrame,
      cornerRadius: 22,
      margin: 12
    )
  })

  for destination in SettingsSection.allCases where destination != .models {
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
    let currentTrafficLightFrames = trafficLightButtons.compactMap { button in
      button.map { $0.convert($0.bounds, to: nil) }
    }
    #expect(currentTrafficLightFrames.allSatisfy { !$0.intersects(sidebarFrame) })

    let detailScroll = try #require(
      settingsHostedScrollViews(of: host).first { $0 !== sidebarScroll }
    )
    let detailFrame = detailScroll.convert(detailScroll.bounds, to: nil)
    #expect(!detailFrame.isEmpty)
    #expect(currentTrafficLightFrames.allSatisfy { !$0.intersects(detailFrame) })
  }

  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor
func DictationSettingsHostedSidebarSearchFitsBetweenTrafficLightsAndFleckHeaderAtMinimumSizes()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: nil, capsuleEnabled: false)
  let sizes = [NSSize(width: 760, height: 520), NSSize(width: 840, height: 600)]
  let dynamicTypeSizes: [DynamicTypeSize] = [.large, .accessibility3]
  var windowIndex = 0

  for size in sizes {
    for dynamicTypeSize in dynamicTypeSizes {
      let host = NSHostingView(
        rootView: SettingsView(runtime: fixture.runtime)
          .environmentObject(fixture.appState)
          .environment(\.dynamicTypeSize, dynamicTypeSize)
      )
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .resizable, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.toolbar = NSToolbar(
        identifier: "settings-hosted-header-row-\(windowIndex)"
      )
      windowIndex += 1
      window.toolbarStyle = .unifiedCompact
      window.contentView = host
      window.setContentSize(size)
      window.makeKeyAndOrderFront(nil)
      await settleSettingsHost(host)

      let closeButton = try #require(window.standardWindowButton(.closeButton))
      let minimizeButton = try #require(window.standardWindowButton(.miniaturizeButton))
      let trafficLightFrames = [closeButton, minimizeButton].map {
        $0.convert($0.bounds, to: nil)
      }
      let sidebar = try #require(settingsSidebarTableView(of: host) as? NSOutlineView)
      let fleckHeading = try #require(
        settingsView(
          withAccessibilityIdentifier: "settings-fleck-sidebar-heading",
          in: sidebar
        )
      )
      let searchField = try #require(
        settingsView(withAccessibilityIdentifier: "settings-search-field", in: host)
          as? NSSearchField
      )
      let fleckHeadingFrame = fleckHeading.convert(fleckHeading.bounds, to: nil)
      let searchFieldFrame = searchField.convert(searchField.bounds, to: nil)
      let pageHeader = try #require(
        settingsView(withAccessibilityIdentifier: "settings-page-header", in: host)
      )
      let pageHeaderFrame = pageHeader.convert(pageHeader.bounds, to: nil)
      let sidebarSurface = try #require(settingsSidebarSurface(of: host))
      let sidebarSurfaceFrame = sidebarSurface.convert(sidebarSurface.bounds, to: nil)
      let generalRow = try #require(settingsSidebarRow(.editing, in: sidebar))
      let generalRowView = try #require(sidebar.rowView(atRow: generalRow, makeIfNecessary: true))
      let generalRowFrame = generalRowView.convert(generalRowView.bounds, to: nil)
      let trafficLightsBottom = try #require(trafficLightFrames.map(\.minY).min())
      let fleckHeaderTop = fleckHeadingFrame.maxY
      let gapAboveSearch = trafficLightsBottom - searchFieldFrame.maxY
      let gapBelowSearch = searchFieldFrame.minY - fleckHeaderTop
      let fleckHeaders = settingsSidebarDescendants(of: host)
        .filter { $0.accessibilityIdentifier() == "settings-fleck-sidebar-heading" }

      #expect(!fleckHeadingFrame.isEmpty)
      #expect(!searchFieldFrame.isEmpty)
      #expect(searchFieldFrame.width > 100)
      #expect(fleckHeading.isDescendant(of: sidebar))
      #expect(fleckHeadingFrame.minY > generalRowFrame.midY)
      #expect(fleckHeaders.count == 1)
      #expect(sidebarSurfaceFrame.contains(searchFieldFrame))
      #expect(searchFieldFrame.maxY <= trafficLightsBottom + 1)
      #expect(searchFieldFrame.minY >= fleckHeaderTop - 1)
      #expect(gapAboveSearch >= 0)
      #expect(gapBelowSearch >= 0)
      #expect(abs(gapAboveSearch - gapBelowSearch) <= 1)
      #expect(searchFieldFrame.minY < size.height - 74)
      #expect(abs(fleckHeaderTop - (size.height - 95)) <= 1)
      #expect(abs(trafficLightFrames[0].midY - trafficLightFrames[1].midY) <= 1)
      #expect(trafficLightFrames.allSatisfy { !$0.intersects(fleckHeadingFrame) })
      #expect(trafficLightFrames.allSatisfy { !$0.intersects(searchFieldFrame) })
      #expect(!fleckHeadingFrame.intersects(searchFieldFrame))
      #expect(!searchFieldFrame.intersects(pageHeaderFrame))

      let searchCenter = NSPoint(x: searchFieldFrame.midX, y: searchFieldFrame.midY)
      let searchHit = host.hitTest(searchCenter)
      #expect(searchHit === searchField || searchHit?.isDescendant(of: searchField) == true)

      searchField.stringValue = "definitely-not-a-setting"
      let searchCoordinator = try #require(
        searchField.delegate as? SettingsSearchField.Coordinator
      )
      searchCoordinator.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: searchField)
      )
      await settleSettingsHost(host)

      let emptyResults = try #require(
        settingsView(withAccessibilityIdentifier: "settings-search-empty", in: host)
      )
      let emptyResultsFrame = emptyResults.convert(emptyResults.bounds, to: nil)
      #expect(!emptyResultsFrame.isEmpty)
      #expect(!searchFieldFrame.intersects(emptyResultsFrame))
      #expect(emptyResultsFrame.maxY <= searchFieldFrame.minY)
      #expect(sidebarSurfaceFrame.contains(emptyResultsFrame))

      searchField.stringValue = ""
      searchCoordinator.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: searchField)
      )
      await settleSettingsHost(host)

      for button in [closeButton, minimizeButton] {
        let superview = try #require(button.superview)
        let centerInSuperview = button.convert(
          NSPoint(x: button.bounds.midX, y: button.bounds.midY),
          to: superview
        )
        let hit = superview.hitTest(centerInSuperview)
        #expect(hit === button || hit?.isDescendant(of: button) == true)
      }

      let activeSidebar = try #require(settingsSidebarTableView(of: host) as? NSOutlineView)
      #expect(activeSidebar.isDescendant(of: host))
      let appearanceRow = try #require(settingsSidebarRow(.appearance, in: activeSidebar))
      #expect(window.makeFirstResponder(searchField))
      await settleSettingsHost(host)
      #expect(
        window.firstResponder === searchField
          || window.firstResponder === searchField.currentEditor()
      )
      activeSidebar.selectRowIndexes(IndexSet(integer: appearanceRow), byExtendingSelection: false)
      NotificationCenter.default.post(
        name: NSTableView.selectionDidChangeNotification,
        object: activeSidebar
      )
      await settleSettingsHost(host)

      #expect(activeSidebar.selectedRow == appearanceRow)
      let activeSidebarScroll = try #require(settingsScrollViewAncestor(of: activeSidebar))
      let detailScroll = try #require(
        settingsHostedScrollViews(of: host).first { $0 !== activeSidebarScroll }
      )
      let detailDocument = try #require(detailScroll.documentView)
      let appearanceHeader = try #require(
        settingsView(withAccessibilityIdentifier: "settings-page-header", in: detailDocument)
      )
      let appearanceThemeContent = try #require(
        settingsView(
          withAccessibilityIdentifier: "settings-search-target-appearance-theme",
          in: detailDocument
        )
      )
      let appearanceHeaderFrame = appearanceHeader.convert(appearanceHeader.bounds, to: nil)
      let appearanceThemeFrame = appearanceThemeContent.convert(
        appearanceThemeContent.bounds,
        to: nil
      )
      let detailFrame = detailScroll.convert(detailScroll.bounds, to: nil)
      let searchFieldAfterSwitch = try #require(
        settingsView(withAccessibilityIdentifier: "settings-search-field", in: host)
          as? NSSearchField
      )
      let searchFieldFrameAfterSwitch = searchFieldAfterSwitch.convert(
        searchFieldAfterSwitch.bounds,
        to: nil
      )
      #expect(!appearanceHeaderFrame.isEmpty)
      #expect(appearanceHeader.isDescendant(of: detailDocument))
      #expect(!appearanceThemeFrame.isEmpty)
      #expect(appearanceThemeContent.isDescendant(of: detailDocument))
      #expect(detailFrame.contains(appearanceThemeFrame.center))
      #expect(sidebarSurfaceFrame.contains(searchFieldFrameAfterSwitch))
      #expect(!searchFieldFrameAfterSwitch.intersects(appearanceHeaderFrame))
      #expect(searchFieldAfterSwitch === searchField)
      await settleSettingsHost(host)
      #expect(
        window.firstResponder === searchFieldAfterSwitch
          || window.firstResponder === searchFieldAfterSwitch.currentEditor()
      )

      window.contentView = nil
      window.orderOut(nil)
    }
  }
}

@Test @MainActor
func DictationSettingsTrafficLightsRecoverAfterNativeTitlebarReset() async throws {
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
  window.toolbar = NSToolbar(identifier: "settings-native-titlebar-reset-toolbar")
  window.toolbarStyle = .unifiedCompact
  let buttons = [
    window.standardWindowButton(.closeButton),
    window.standardWindowButton(.miniaturizeButton),
  ].compactMap { $0 }
  let nativeOrigins = buttons.map(\.frame.origin)

  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleSettingsHost(host)

  let surface = try #require(settingsSidebarSurface(of: host))
  let surfaceFrame = surface.convert(surface.bounds, to: nil)
  #expect(buttons.allSatisfy {
    settingsRoundedSurfaceContains(
      $0.convert($0.bounds, to: nil),
      in: surfaceFrame,
      cornerRadius: 22,
      margin: 12
    )
  })

  for (button, origin) in zip(buttons, nativeOrigins) {
    button.setFrameOrigin(origin)
  }
  for _ in 0..<10 { await Task.yield() }

  #expect(buttons.allSatisfy {
    settingsRoundedSurfaceContains(
      $0.convert($0.bounds, to: nil),
      in: surfaceFrame,
      cornerRadius: 22,
      margin: 12
    )
  })

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

  for destination in SettingsSection.allCases where destination != .models {
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
    ]
    let trafficLightFrames = trafficLightButtons.compactMap { button in
      button.map { $0.convert($0.bounds, to: nil) }
    }
    #expect(trafficLightFrames.count == 2)
    #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
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
private func settingsAccessibilityElements(in value: Any?, identifier: String) -> [NSObject] {
  guard let element = value as? NSObject else { return [] }
  let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
  let matchesIdentifier = element.responds(to: identifierSelector)
    && element.perform(identifierSelector)?.takeUnretainedValue() as? String == identifier
  var matches = matchesIdentifier ? [element] : []
  let childrenSelector = NSSelectorFromString("accessibilityChildren")
  let rawChildren = element.responds(to: childrenSelector)
    ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any] : nil
  for child in NSAccessibility.unignoredChildren(from: rawChildren ?? []) {
    matches.append(contentsOf: settingsAccessibilityElements(in: child, identifier: identifier))
  }
  return matches
}

@MainActor
private func settingsAccessibilityValue(_ element: NSObject) -> String? {
  let selector = NSSelectorFromString("accessibilityValue")
  guard element.responds(to: selector) else { return nil }
  return element.perform(selector)?.takeUnretainedValue() as? String
}

@MainActor
private func enableSettingsAccessibility() -> Any? {
  let application = NSApplication.shared
  let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
  let previousValue = application.accessibilityAttributeValue(attribute)
  application.accessibilitySetValue(true, forAttribute: attribute)
  return previousValue
}

@MainActor
private func restoreSettingsAccessibility(_ value: Any?) {
  NSApplication.shared.accessibilitySetValue(
    value,
    forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
  )
}

@MainActor
private func performSettingsAccessibilityPress(_ element: NSObject) -> Bool {
  let selector = NSSelectorFromString("accessibilityPerformPress")
  guard let method = class_getInstanceMethod(type(of: element), selector),
    let typeEncoding = method_getTypeEncoding(method)
  else {
    return false
  }
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

@Test func SettingsSearchConnectsGlobalResultsToExistingControlAnchors() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settings = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
  let agents = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/AgentSettingsView.swift"),
    encoding: .utf8
  )
  let about = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/AboutSettingsView.swift"),
    encoding: .utf8
  )

  #expect(settings.contains("SettingsSearchField("))
  #expect(settings.contains("SettingsSearchResultsView("))
  #expect(settings.contains("SettingsSearchIndex.results(for: searchQuery)"))
  #expect(settings.contains("onSubmit: submitHighlightedSearchResult"))
  #expect(settings.contains("searchRequest = SettingsSearchRequest(target: result.target, anchor: anchor)"))
  #expect(settings.contains("if result.destination == .models"))
  #expect(settings.contains("if section == .models"))
  #expect(settings.contains("private func openModelsFromSettingsNavigation()"))
  #expect(settings.contains("selectedSection = .models"))
  #expect(settings.contains("ModelsBrowserView("))
  #expect(!settings.contains("openWindow(id: ModelLibraryLayout.windowIdentifier)"))
  #expect(!settings.contains("private var modelLibraryDestination: some View"))
  #expect(settings.contains(".settingsSearchAnchor(.dictationStatus, request: searchRequest)"))
  #expect(settings.contains("isReadinessPopoverPresented = result.target == .dictationStatus"))
  #expect(settings.contains("proxy.scrollTo(pageScrollAnchor, anchor: isTransferFooter ? .bottom : .center)"))
  #expect(settings.contains(".id(SettingsSearchTarget.vocabularyTransferFooter)"))
  #expect(settings.contains("if searchRequest.anchor.usesVocabularyFocusLifecycle"))
  #expect(settings.contains(".environment(\\.settingsSearchRequest, searchRequest)"))
  #expect(settings.contains(".settingsSearchAnchor(.appearanceTheme, request: searchRequest)"))
  #expect(settings.contains(".settingsSearchAnchor(.dictationPrivacy, request: searchRequest)"))
  #expect(
    settings.range(
      of: #"SettingsPageHeader\(\s*section: \.vocabulary,\s*title: "Dictionary",\s*searchRequest: visibleSearchRequest\s*\)"#,
      options: .regularExpression
    ) != nil
  )

  let sharedHeaderStart = try #require(settings.range(of: "struct SettingsPageHeader: View"))
  let sharedHeaderEnd = try #require(
    settings.range(
      of: "struct SettingsSectionCard<Content: View>",
      range: sharedHeaderStart.upperBound..<settings.endIndex
    )
  )
  let sharedHeaderSource = settings[sharedHeaderStart.lowerBound..<sharedHeaderEnd.lowerBound]
  #expect(
    sharedHeaderSource.components(
      separatedBy: ".settingsSearchAnchor(.section(section), request: searchRequest)"
    ).count == 2
  )
  #expect(
    settings.range(
      of: #"if selectedSection != \.vocabulary\s*\{\s*SettingsPageHeader\(\s*section: selectedSection,\s*searchRequest: searchRequest,\s*accessory: selectedSection == \.dictation\s*\?\s*AnyView\(dictationReadinessButton\)\s*:\s*nil\s*\)\s*\}"#,
      options: .regularExpression
    ) != nil
  )
  #expect(!settings.contains("vocabularyFilter"))
  #expect(settings.contains(".settingsSearchAnchor(.vocabularySort, request: visibleSearchRequest)"))
  #expect(settings.contains(".settingsSearchAnchor(.vocabularyReload, request: visibleSearchRequest)"))
  #expect(settings.contains("settingsSearchAnchor(.vocabularyTransfer, request: optionsSearchRequest)"))
  #expect(settings.contains("searchRequest: $searchRequest"))
  #expect(settings.contains("pageScrollReadyRequestID: vocabularyPageScrollRequestID"))
  #expect(agents.contains(".settingsSearchAnchor(.agentsActivity, request: searchRequest)"))
  #expect(agents.contains(".settingsSearchAnchor(.agentsAccess, request: searchRequest)"))
  #expect(agents.contains("isActivityExpanded = true"))
  #expect(agents.contains("isAccessExpanded = true"))
  #expect(about.contains(".settingsSearchAnchor(.aboutMetadata, request: searchRequest)"))
  #expect(about.contains("isMetadataExpanded = true"))
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

@MainActor
private struct SettingsTestApplicationActivationState {
  private let activationPolicy: NSApplication.ActivationPolicy
  private let wasActive: Bool

  init(_ application: NSApplication) {
    activationPolicy = application.activationPolicy()
    wasActive = application.isActive
  }

  func restore(_ application: NSApplication) async {
    defer {
      #expect(application.activationPolicy() == activationPolicy)
      #expect(application.isActive == wasActive)
    }

    if application.activationPolicy() != activationPolicy {
      Issue.record("NSApp's activation policy changed during the test; host policy was not reset")
      return
    }

    if wasActive && !application.isActive {
      application.activate(ignoringOtherApps: true)
      guard
        await waitForSettingsAppKitState(condition: {
          application.activationPolicy() == activationPolicy && application.isActive
        })
      else {
        Issue.record("Failed to restore NSApp's active state")
        return
      }
    }
  }
}

@MainActor
private func withSettingsTestApplicationActivationState(
  _ application: NSApplication,
  operation: @MainActor () async throws -> Void
) async throws {
  try requireSettingsTestApplicationBaseline(application)
  let activationState = SettingsTestApplicationActivationState(application)
  do {
    try await operation()
    await Task { @MainActor in
      await activationState.restore(application)
    }.value
  } catch {
    await Task { @MainActor in
      await activationState.restore(application)
    }.value
    throw error
  }
}

@MainActor
private func requireSettingsTestApplicationBaseline(_ application: NSApplication) throws {
  try #require(
    application.activationPolicy() == .regular,
    "Expected the test host's declared .regular activation policy"
  )
  try #require(application.isActive, "Expected the test host's active application baseline")
}

@MainActor
private func activateSettingsTestApplication(
  _ application: NSApplication,
  keyWindow: NSWindow
) async -> Bool {
  guard application.activationPolicy() == .regular else { return false }
  application.activate(ignoringOtherApps: true)
  return await waitForSettingsAppKitState {
    application.isActive && application.keyWindow === keyWindow && keyWindow.isKeyWindow
  }
}

@MainActor
private func waitForSettingsAppKitState(
  timeout: TimeInterval = 2,
  condition: @MainActor () -> Bool
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .milliseconds(Int64(timeout * 1_000)))
  while true {
    guard !Task.isCancelled else { return false }
    if condition() { return true }
    let remaining = clock.now.duration(to: deadline)
    guard remaining > .zero else { return false }
    do {
      try await Task.sleep(for: min(.milliseconds(10), remaining))
    } catch {
      return false
    }
  }
}

@Test @MainActor func DictationRuntimeUpdatesRailAccentWithoutRewritingPreference() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved", capsuleEnabled: true)
  await fixture.runtime.awaitStartupAssessment()

  let legacyAccentHex = "#E64A19"
  fixture.appState.updatePreferences {
    $0.accentHex = legacyAccentHex
    $0.colorTheme = .capy
  }
  fixture.runtime.preferencesDidChange()

  #expect(
    fixture.runtime.capsuleController.presentationModel.colors.accentHex
      == fixture.appState.themeSnapshot.palette[.accent]
  )
  #expect(fixture.appState.preferences.accentHex == legacyAccentHex)
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
  #expect(presentation.statusCopy == "Hold Right Option to dictate.")
  #expect(presentation.detailCopy == "Double-tap for hands-free.")
  #expect(
    presentation.capsuleAccessibilityLabel
      == "Fleck dictation ready. Hold Right Option to dictate. Double-tap for hands-free."
  )
  #expect(presentation.isPickerEnabled)
  #expect(presentation.recoveryAction == nil)
}

@Test func dictationModifierSettingsShowsDeniedUnavailableRetryAndActiveCaptureCopy() {
  let denied = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .unauthorized,
    canChange: true
  )
  #expect(denied.statusCopy == "Enable Input Monitoring to use Right Option.")
  #expect(denied.recoveryAction == .enableInputMonitoring)
  #expect(denied.recoveryButtonTitle == "Open Input Monitoring")
  #expect(denied.guidanceCopy == "Turn on Fleck, then return here.")
  #expect(denied.detailCopy == "Turn on Fleck, then return here.")
  #expect(!denied.capsuleAccessibilityLabel.contains("ready"))

  let unavailable = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .stopped,
    canChange: true
  )
  #expect(unavailable.statusCopy.contains("unavailable"))
  #expect(!unavailable.capsuleAccessibilityLabel.contains("ready"))

  let failed = DictationModifierSettingsPresentation(
    selected: .rightOption,
    monitorStatus: .failed,
    canChange: true
  )
  #expect(failed.statusCopy == "Right Option shortcut could not start.")
  #expect(failed.recoveryAction == .retry)
  #expect(failed.recoveryButtonTitle == "Retry")
  #expect(!failed.capsuleAccessibilityLabel.contains("ready"))

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

@Test func dictationModifierSettingsUsesEveryConfiguredKeyInShortcutCopy() {
  for key in DictationModifierKey.allCases {
    let presentation = DictationModifierSettingsPresentation(
      selected: key,
      monitorStatus: .running,
      canChange: true
    )
    #expect(presentation.statusCopy == "Hold \(key.displayName) to dictate.")
    #expect(presentation.capsuleAccessibilityLabel.contains(key.displayName))
  }
}

@Test func dictationShortcutHelpModeDismissesOnlyTheHealthyIdleGuide() {
  #expect(DictationShortcutHelpMode.readyTutorial.canDismissGuide)
  #expect(!DictationShortcutHelpMode.recovery.canDismissGuide)
  #expect(
    DictationShortcutHelpMode.resolve(
      isReady: true,
      isCaptureActive: false,
      showsGuide: true
    ) == .readyTutorial
  )
  #expect(
    DictationShortcutHelpMode.resolve(
      isReady: true,
      isCaptureActive: false,
      showsGuide: false
    ) == nil
  )
  #expect(
    DictationShortcutHelpMode.resolve(
      isReady: false,
      isCaptureActive: false,
      showsGuide: false
    ) == .recovery
  )
  #expect(
    DictationShortcutHelpMode.resolve(
      isReady: true,
      isCaptureActive: true,
      showsGuide: false
    ) == nil
  )
}

@Test func dictationShortcutHelpModeOmitsEveryActiveCaptureGuide() {
  for isReady in [false, true] {
    for showsGuide in [false, true] {
      #expect(
        DictationShortcutHelpMode.resolve(
          isReady: isReady,
          isCaptureActive: true,
          showsGuide: showsGuide
        ) == nil
      )
    }
  }
}

@Test @MainActor
func hostedNotesPanelOmitsActiveDestinationGuideForFocusedAndSmartCapture()
  async throws
{
  let note = Note(title: "Example note")
  let fixture = try await RuntimeFixture(finalText: nil, routingNotes: [note])
  await fixture.runtime.awaitStartupAssessment()
  let editorCommands = EditorCommands()
  let size = NSSize(width: 720, height: 480)
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: fixture.runtime,
      sizing: .container,
      editorCommands: editorCommands
    )
    .environmentObject(fixture.appState)
    .frame(width: size.width, height: size.height)
  )
  let window = DictationKeyWindowProbe(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  window.isReleasedWhenClosed = false
  window.contentView = host
  await settleSettingsHost(host)
  defer {
    window.contentView = nil
    window.close()
  }

  func capture(_ name: String) throws -> Data {
    let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: image)
    let pngData = try #require(image.representation(using: .png, properties: [:]))
    #expect(!pngData.isEmpty)
    if let captureDirectory = ProcessInfo.processInfo.environment[
      "FLECK_DICTATION_BANNER_CAPTURE_DIR"
    ] {
      let directory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try pngData.write(to: directory.appendingPathComponent(name + ".png"))
    }
    return pngData
  }

  #expect(fixture.appState.preferences.showDictationShortcutGuide)
  #expect(
    DictationShortcutHelpMode.resolve(
      isReady: fixture.runtime.modifierShortcutPresentation.isReady,
      isCaptureActive: fixture.runtime.canCancel,
      showsGuide: fixture.appState.preferences.showDictationShortcutGuide
    ) == .readyTutorial
  )
  let idleImage = try capture("notes-panel-idle-guide")

  let textView = try #require(editorCommands.textView)
  window.reportsKey = true
  #expect(window.makeFirstResponder(textView))
  await fixture.runtime.toggle()
  #expect(fixture.runtime.canCancel)
  #expect(fixture.runtime.destinationGuidanceCopy == "Dictating into Example note")
  #expect(
    DictationShortcutHelpMode.resolve(
      isReady: fixture.runtime.modifierShortcutPresentation.isReady,
      isCaptureActive: fixture.runtime.canCancel,
      showsGuide: fixture.appState.preferences.showDictationShortcutGuide
    ) == nil
  )
  await settleSettingsHost(host)
  let focusedImage = try capture("notes-panel-active-focused")
  #expect(focusedImage != idleImage)
  await fixture.runtime.cancel()

  _ = window.makeFirstResponder(nil)
  window.reportsKey = false
  await fixture.runtime.toggle()
  #expect(fixture.runtime.canCancel)
  #expect(fixture.runtime.destinationGuidanceCopy == "Smart Capture")
  #expect(
    DictationShortcutHelpMode.resolve(
      isReady: fixture.runtime.modifierShortcutPresentation.isReady,
      isCaptureActive: fixture.runtime.canCancel,
      showsGuide: fixture.appState.preferences.showDictationShortcutGuide
    ) == nil
  )
  await settleSettingsHost(host)
  let smartCaptureImage = try capture("notes-panel-active-smart-capture")
  #expect(smartCaptureImage != idleImage)
  await fixture.runtime.cancel()
}

@Test func notesPanelExposesModifierMonitoringRecoveryBesideTheEditor() throws {
  let testsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: testsDirectory.appendingPathComponent("Sources/FleckApp/NotesPanel.swift")
  )

  #expect(source.contains("DictationShortcutHelpRow"))
  #expect(source.contains("modifierShortcutPresentation"))
  #expect(source.contains("destinationCopy: dictationRuntime.destinationGuidanceCopy"))
  #expect(source.contains("Say a specific note title to help Fleck choose."))
  #expect(source.contains("Example: “Travel plans.”"))
  #expect(source.contains("await dictationRuntime.performModifierShortcutRecovery"))
}

@Test func notesPanelBannerPolicyOmitsRoutineUndoWhileKeepingFailures() {
  let captureFailure = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )
  let agentChange = NotesPanelBannerOccurrence.agentChange(changeID: UUID(), count: 1)

  let active = NotesPanelBannerPolicy.activeOccurrences(
    captureFailure: captureFailure,
    routineRecoveryAction: .undo,
    agentChange: agentChange
  )

  #expect(active == [captureFailure, agentChange])
}

@Test func notesPanelBannerDismissalInitiallyPresentsAllActiveOccurrences() {
  let captureFailure = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )
  let agentChange = NotesPanelBannerOccurrence.agentChange(changeID: UUID(), count: 1)
  var state = NotesPanelBannerDismissalState()
  state.reconcile(activeOccurrences: [captureFailure, agentChange])

  #expect(state.isPresented(captureFailure))
  #expect(state.isPresented(agentChange))
}

@Test func notesPanelBannerDismissalHidesOnlyTheExactActiveIdentity() {
  let captureFailure = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )
  let changedFailure = NotesPanelBannerOccurrence.captureFailure(
    message: "Speech Recognition permission is required",
    actionPanes: [.speechRecognition]
  )
  let agentChange = NotesPanelBannerOccurrence.agentChange(changeID: UUID(), count: 1)
  var state = NotesPanelBannerDismissalState()
  state.reconcile(activeOccurrences: [captureFailure, changedFailure, agentChange])
  state.dismiss(captureFailure)

  #expect(!state.isPresented(captureFailure))
  #expect(state.isPresented(changedFailure))
  #expect(state.isPresented(agentChange))
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

@Test func notesPanelBannerDismissalForgetsAgentChangesWithoutClearingCaptureFailure() {
  let captureFailure = NotesPanelBannerOccurrence.captureFailure(
    message: "Microphone permission is required",
    actionPanes: [.microphone]
  )
  let agentChange = NotesPanelBannerOccurrence.agentChange(changeID: UUID(), count: 1)
  var state = NotesPanelBannerDismissalState()
  state.reconcile(activeOccurrences: [captureFailure, agentChange])
  state.dismiss(captureFailure)
  state.dismiss(agentChange)
  #expect(!state.isPresented(captureFailure))
  #expect(!state.isPresented(agentChange))

  state.forgetDismissedOccurrences(in: .agentChange)

  #expect(!state.isPresented(captureFailure))
  #expect(state.isPresented(agentChange))
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
    if finalText != nil {
      let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)
      #expect(await sleeper.requestedDurations.isEmpty)
      fixture.runtime.capsuleController.selectRoutingChoice(
        captureID: captureID,
        noteID: nil
      )
      for _ in 0..<1_000 {
        if fixture.runtime.coordinator.routingAmbiguity == nil { break }
        await Task.yield()
      }
      #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
    }
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
  #expect(fixture.runtime.capsuleController.currentContext.detailText == "No clear destination")

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = false }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.capsuleController.currentChooser == nil)
  #expect(fixture.runtime.coordinator.routingAmbiguity?.captureID == firstCaptureID)

  fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
  fixture.runtime.preferencesDidChange()
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Inbox"))
  #expect(fixture.runtime.capsuleController.currentChooser?.captureID == firstCaptureID)
  #expect(fixture.runtime.capsuleController.currentContext.detailText == "No clear destination")

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

@Test func DictationCapsuleChooserKeepsEveryManualChoiceAndDisambiguatesFolders() throws {
  let captureID = UUID()
  let choices = (0..<6).map { index in
    DictationRoutingChoice(
      destination: .init(noteID: UUID(), title: index < 2 ? "Travel plans" : "Note \(index)"),
      contextHint: index == 0 ? "Work" : index == 1 ? "Home" : ""
    )
  }

  let chooser = DictationCapsuleChooser(
    ambiguity: .init(captureID: captureID, choices: choices)
  )

  #expect(chooser.choices.count == 6)
  #expect(chooser.choices[0].menuTitle == "Travel plans — Work")
  #expect(chooser.choices[1].menuTitle == "Travel plans — Home")
  #expect(chooser.choices[2].menuTitle == "Note 2")
}

@Test func DictationCapsuleShowsInboxFallbackReasonWithoutReplacingSavedStatus() {
  let presentation = DictationCapsulePresentation(
    status: .saved(destination: "Inbox"),
    context: .init(
      status: .saved(destination: "Inbox"),
      detailText: "No clear destination"
    )
  )

  #expect(presentation.visibleText == "Saved to Inbox")
  #expect(presentation.secondaryVisibleText == "No clear destination")
  #expect(presentation.voiceOverText == "Saved to Inbox. No clear destination")
}

@Test @MainActor func DictationRuntimeNormalInboxFallbackOffersAllNotesThenMovesOnce()
  async throws
{
  let sleeper = RuntimeCapsuleSleeper()
  let notes = (0..<6).map { Note(title: $0 == 0 ? "Note" : "Note \($0 + 1)") }
  let fixture = try await RuntimeFixture(
    finalText: "Move this saved capture",
    capsuleEnabled: true,
    routingNotes: notes,
    capsuleSleeper: { duration in await sleeper.sleep(duration) }
  )
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()
  await fixture.runtime.toggle()

  let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)
  let chooser = try #require(fixture.runtime.capsuleController.currentChooser)
  #expect(chooser.choices.count == 6)
  #expect(chooser.choices.map(\.id) == notes.map(\.id))
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Inbox"))
  #expect(fixture.runtime.capsuleController.currentContext.detailText == "No clear destination")
  #expect(await sleeper.requestedDurations.isEmpty)

  fixture.runtime.capsuleController.selectRoutingChoice(
    captureID: captureID,
    noteID: notes[0].id
  )
  for _ in 0..<1_000 {
    if fixture.runtime.coordinator.routingAmbiguity == nil { break }
    await Task.yield()
  }

  #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
  #expect(fixture.runtime.currentCapsuleStatus == .saved(destination: "Note"))
  #expect(fixture.runtime.capsuleController.currentContext.detailText == nil)
  await sleeper.waitForRequest()
  #expect(await sleeper.requestedDurations == [.milliseconds(1_600)])
  await sleeper.resumeAll()
  #expect(fixture.appState.workspace.notes.first(where: { $0.id == notes[0].id })?
    .body.contains("Move this saved capture") == true)
  #expect(fixture.appState.workspace.notes.first(where: {
    $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
  })?.body.contains("Move this saved capture") == false)
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
    if finalText != nil {
      let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)
      #expect(
        await fixture.runtime.coordinator.chooseDestination(
          captureID: captureID,
          noteID: nil
        ) == .completed
      )
      #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
    }

    fixture.appState.updatePreferences { $0.dictationCapsuleEnabled = true }
    fixture.runtime.preferencesDidChange()
    #expect(fixture.runtime.currentCapsuleStatus == .idle)
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
    if finalText != nil {
      let captureID = try #require(fixture.runtime.coordinator.routingAmbiguity?.captureID)
      #expect(await sleeper.requestedDurations.isEmpty)
      fixture.runtime.capsuleController.selectRoutingChoice(
        captureID: captureID,
        noteID: nil
      )
      for _ in 0..<1_000 {
        if fixture.runtime.coordinator.routingAmbiguity == nil { break }
        await Task.yield()
      }
      #expect(fixture.runtime.coordinator.routingAmbiguity == nil)
    }
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

@Test @MainActor func DictationRuntimeKeepsFocusedDestinationGuidanceStableAcrossSelectionChanges()
  async throws
{
  let travel = Note(title: "Travel plans")
  let shopping = Note(title: "Shopping")
  let fixture = try await RuntimeFixture(
    finalText: "Focused",
    capsuleEnabled: true,
    routingNotes: [travel, shopping]
  )
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
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.runtime.destinationGuidanceCopy == "Click in this note to dictate here.")
  await fixture.runtime.toggle()
  #expect(fixture.runtime.destinationGuidanceCopy == "Dictating into Travel plans")
  #expect(
    fixture.runtime.capsuleController.currentContext.detailText
      == "Dictating into Travel plans"
  )
  #expect(fixture.runtime.capsuleController.currentContext.compactDetailText == "Travel plans")
  #expect(
    DictationCapsulePresentation(
      status: fixture.runtime.capsuleController.currentContext.status,
      context: fixture.runtime.capsuleController.currentContext
    ).voiceOverText
      == "Dictation listening. Dictating into Travel plans"
  )

  fixture.appState.select(shopping.id)
  #expect(fixture.runtime.destinationGuidanceCopy == "Dictating into Travel plans")
  #expect(
    fixture.runtime.capsuleController.currentContext.detailText
      == "Dictating into Travel plans"
  )

  await fixture.runtime.cancel()
  #expect(fixture.runtime.destinationGuidanceCopy == "Click in this note to dictate here.")
}

@Test @MainActor func DictationRuntimeLabelsGlobalCaptureAsSmartCapture() async throws {
  let fixture = try await RuntimeFixture(finalText: "Global", capsuleEnabled: true)
  await fixture.runtime.awaitStartupAssessment()

  await fixture.runtime.toggle()

  #expect(fixture.runtime.destinationGuidanceCopy == "Smart Capture")
  #expect(fixture.runtime.capsuleController.currentContext.detailText == "Smart Capture")
  #expect(fixture.runtime.capsuleController.currentContext.compactDetailText == "Smart Capture")
  await fixture.runtime.cancel()
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

@Test @MainActor func DictationRuntimeKeepsIdleCapsuleShortcutReadinessTruthfulOnActivation()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    capsuleEnabled: true,
    preferredModifier: .leftCommand,
    monitorAccessGranted: false,
    monitorRequestAccessResult: false
  )
  await fixture.runtime.awaitStartupAssessment()

  #expect(fixture.runtime.currentCapsuleStatus == .idle)
  #expect(
    fixture.runtime.capsuleController.presentationModel.voiceOverLabel
      == "Fleck global shortcut unavailable. Enable Input Monitoring to use Left Command. "
        + "Turn on Fleck, then return here."
  )

  fixture.monitor.accessGranted = true
  fixture.runtime.applicationDidBecomeActive()

  #expect(fixture.runtime.modifierMonitorState == .running)
  #expect(
    fixture.runtime.capsuleController.presentationModel.voiceOverLabel
      == "Fleck dictation ready. Hold Left Command to dictate. Double-tap for hands-free."
  )

  fixture.appState.preferences.dictationModifierKey = .rightControl
  fixture.runtime.preferencesDidChange()

  #expect(fixture.runtime.actualModifier == .rightControl)
  #expect(
    fixture.runtime.capsuleController.presentationModel.voiceOverLabel
      == "Fleck dictation ready. Hold Right Control to dictate. Double-tap for hands-free."
  )
}

@Test @MainActor func DictationRuntimeRefreshesIdleCapsuleAfterSettingsModifierChange()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    capsuleEnabled: true,
    preferredModifier: .leftCommand
  )
  await fixture.runtime.awaitStartupAssessment()

  let changed = await fixture.runtime.changeModifier(to: .rightControl)

  #expect(changed)
  #expect(fixture.runtime.actualModifier == .rightControl)
  #expect(
    fixture.runtime.capsuleController.presentationModel.voiceOverLabel
      == "Fleck dictation ready. Hold Right Control to dictate. Double-tap for hands-free."
  )
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

@Test @MainActor func DictationRuntimeShortcutHelpActionRequestsThenOpensOrRetriesAsNeeded()
  async throws
{
  let denied = try await RuntimeFixture(
    finalText: "saved",
    monitorAccessGranted: false,
    monitorRequestAccessResult: false
  )
  await denied.runtime.awaitStartupAssessment()
  var deniedSettings: [DictationSystemSettingsAction] = []

  await denied.runtime.performModifierShortcutRecovery {
    deniedSettings.append($0)
  }

  #expect(denied.monitor.requestCount == 1)
  #expect(deniedSettings.map(\.pane) == [.inputMonitoring])
  #expect(
    deniedSettings.first?.url.absoluteString
      == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
  )
  #expect(denied.runtime.modifierMonitorState == .unauthorized)

  let firstRequestGranted = try await RuntimeFixture(
    finalText: "saved",
    monitorAccessGranted: false,
    monitorRequestAccessResult: true
  )
  await firstRequestGranted.runtime.awaitStartupAssessment()
  var grantedSettings: [DictationSystemSettingsAction] = []

  await firstRequestGranted.runtime.performModifierShortcutRecovery {
    grantedSettings.append($0)
  }

  #expect(firstRequestGranted.monitor.requestCount == 1)
  #expect(grantedSettings.isEmpty)
  #expect(firstRequestGranted.runtime.modifierMonitorState == .running)
  await firstRequestGranted.runtime.performModifierShortcutRecovery {
    grantedSettings.append($0)
  }
  #expect(firstRequestGranted.monitor.requestCount == 1)
  #expect(grantedSettings.isEmpty)

  let failed = try await RuntimeFixture(finalText: "saved")
  await failed.runtime.awaitStartupAssessment()
  failed.monitor.publish(.failed)
  await failed.runtime.shortcutController.drainEvents()
  var failedSettings: [DictationSystemSettingsAction] = []

  await failed.runtime.performModifierShortcutRecovery {
    failedSettings.append($0)
  }

  #expect(failedSettings.isEmpty)
  #expect(failed.monitor.requestCount == 0)
  #expect(failed.runtime.modifierMonitorState == .running)
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

@Test @MainActor func DictationRuntimeRegistersEscapeDuringSuspendedCaptureStartup()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  let providerGate = DictationTestGate()
  fixture.provider.gate = providerGate
  let starting = Task { await fixture.runtime.toggle() }
  await fixture.provider.waitUntilRequested()

  #expect(fixture.runtime.phase == .arming)
  #expect(fixture.escapeRegistrar.registerCount == 1)
  #expect(fixture.escapeRegistrar.isRegistered)

  fixture.escapeRegistrar.emit()
  await providerGate.open()
  await starting.value
  for _ in 0..<100 where fixture.runtime.phase != .idle {
    await Task.yield()
  }
  #expect(fixture.runtime.phase == .idle)
  #expect(fixture.engine.cancelCount == 1)
  #expect(fixture.escapeRegistrar.unregisterCount == 1)
}

@Test @MainActor func DictationRuntimeEscapeIsOnceOnlyAndInactiveOutsideCapture() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  fixture.escapeRegistrar.emit()
  #expect(fixture.engine.cancelCount == 0)

  await fixture.runtime.toggle()
  fixture.escapeRegistrar.emit()
  fixture.escapeRegistrar.emit()
  for _ in 0..<100 where fixture.runtime.phase != .idle {
    await Task.yield()
  }

  #expect(fixture.runtime.phase == .idle)
  #expect(fixture.engine.cancelCount == 1)
  #expect(fixture.escapeRegistrar.registerCount == 1)
  #expect(fixture.escapeRegistrar.unregisterCount == 1)
  fixture.escapeRegistrar.emit()
  await Task.yield()
  #expect(fixture.engine.cancelCount == 1)
}

@Test @MainActor func DictationRuntimeQueuedEscapeCannotCancelNextCapture() async throws {
  let queue = RuntimeEscapeOperationQueue()
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    scheduleEscapeCancellation: { operation in queue.append(operation) }
  )
  await fixture.runtime.toggle()
  fixture.escapeRegistrar.emit()
  fixture.escapeRegistrar.emit()
  #expect(queue.count == 1)

  await fixture.runtime.cancel()
  await fixture.runtime.toggle()
  #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))

  await queue.runFirst()
  #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))

  fixture.escapeRegistrar.emit()
  await queue.runFirst()
  #expect(fixture.runtime.phase == .idle)
}

@Test @MainActor func DictationRuntimePinsEffectiveModifierForEscapeCapture() async throws {
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    preferredModifier: .rightOption
  )
  await fixture.runtime.awaitStartupAssessment()
  #expect(fixture.runtime.actualModifier == .rightOption)

  await fixture.runtime.toggle()
  fixture.appState.preferences.dictationModifierKey = .leftControl

  #expect(fixture.escapeRegistrar.registeredModifiers == [.rightOption])
  await fixture.runtime.cancel()
  #expect(fixture.escapeRegistrar.unregisterCount == 1)
}

@Test @MainActor func DictationRuntimeEscapeRegistrationFailureWarnsWithoutStoppingCapture()
  async throws
{
  let fixture = try await RuntimeFixture(
    finalText: "saved",
    escapeRegisterError: GlobalHoldShortcut.RegistrationError.system(-70)
  )

  await fixture.runtime.toggle()

  #expect(fixture.runtime.phase == .listening(mode: .smartCapture, engine: .standard))
  #expect(fixture.escapeRegistrar.registerCount == 1)
  #expect(fixture.engine.finishCount == 0)
  #expect(fixture.engine.cancelCount == 0)
  #expect(fixture.history.records.isEmpty)
  #expect(fixture.appState.saveError
    == "Escape cancellation could not be enabled for this recording. Use Cancel Dictation.")

  fixture.escapeRegistrar.emit()
  await Task.yield()
  #expect(fixture.engine.cancelCount == 0)
  await fixture.runtime.cancel()
  #expect(fixture.engine.cancelCount == 1)
  #expect(fixture.escapeRegistrar.registerCount == 1)
}

@Test @MainActor func DictationRuntimeShutdownCleansRuntimeOwnedEscapeOnce() async throws {
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.toggle()

  await fixture.runtime.shutdown()
  await fixture.runtime.shutdown()

  #expect(fixture.escapeRegistrar.unregisterCount == 1)
  #expect(fixture.escapeRegistrar.eventHandler == nil)
}

@Test @MainActor func DictationRuntimeReportsEscapeCleanupFailureAndRetriesAtShutdown()
  async throws
{
  let fixture = try await RuntimeFixture(finalText: "saved")
  await fixture.runtime.toggle()
  fixture.escapeRegistrar.unregisterError =
    GlobalHoldShortcut.RegistrationError.system(-71)

  await fixture.runtime.cancel()

  #expect(fixture.escapeRegistrar.unregisterCount == 1)
  #expect(fixture.appState.saveError
    == "Escape cancellation could not be disabled. The shortcut may remain reserved until Fleck quits.")

  fixture.escapeRegistrar.unregisterError = nil
  await fixture.runtime.shutdown()
  #expect(fixture.escapeRegistrar.unregisterCount == 2)
  #expect(!fixture.escapeRegistrar.isRegistered)
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
    speechModelViewModel: AdmittedModelSettingsViewModel? = nil,
    cleanupModelViewModel: AdmittedModelSettingsViewModel? = nil,
    routingNotes: [Note] = [],
    ambiguousRouting: Bool = false,
    cleanupFails: Bool = false,
    historySaveFailureAttempt: Int? = nil,
    historySaveBlockingAttempt: Int? = nil,
    escapeRegisterError: Error? = nil,
    saving: (any DictationSaving)? = nil,
    capsuleSleeper: @escaping @MainActor (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    },
    scheduleEscapeCancellation: @escaping @MainActor (
      @escaping @MainActor () async -> Void
    ) -> Void = { operation in
      _ = Task { @MainActor in await operation() }
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
    escapeRegistrar.registerError = escapeRegisterError
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
    let admittedModelSettingsViewModel = speechModelViewModel
      ?? AdmittedModelSettingsViewModel(installer: makeAdmittedModelInstaller())
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
      cleanupAdmittedModelSettingsViewModel: cleanupModelViewModel,
      availabilityProvider: availabilityProvider ?? { availability },
      capsuleSleeper: capsuleSleeper,
      scheduleEscapeCancellation: scheduleEscapeCancellation,
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
  var registerError: Error?
  var unregisterError: Error?
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0
  private(set) var registeredModifiers: [DictationModifierKey?] = []
  private(set) var isRegistered = false

  func register() throws {
    try register(modifier: nil)
  }

  func register(modifier: DictationModifierKey?) throws {
    registerCount += 1
    registeredModifiers.append(modifier)
    if let registerError { throw registerError }
    isRegistered = true
  }

  func unregister() throws {
    guard isRegistered else { return }
    unregisterCount += 1
    if let unregisterError { throw unregisterError }
    isRegistered = false
  }

  func emit() {
    guard isRegistered else { return }
    eventHandler?()
  }
}

@MainActor
private final class RuntimeEscapeOperationQueue {
  private var operations: [@MainActor () async -> Void] = []
  var count: Int { operations.count }

  func append(_ operation: @escaping @MainActor () async -> Void) {
    operations.append(operation)
  }

  func runFirst() async {
    guard !operations.isEmpty else { return }
    await operations.removeFirst()()
  }
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
  private(set) var finishCount = 0
  private(set) var cancelCount = 0
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
    finishCount += 1
    if let finishGate { await finishGate.wait() }
    return finalText
  }

  func cancel() async { cancelCount += 1 }
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
