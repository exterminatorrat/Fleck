import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor
func personalDictionarySettingsLoadsEntriesInStableOrder() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let store = PersonalDictionaryStore(rootURL: root)
  try await store.upsert(PersonalDictionaryEntry(preferredForm: "Zeta"))
  try await store.upsert(PersonalDictionaryEntry(preferredForm: "Alpha"))
  let viewModel = PersonalDictionarySettingsViewModel(store: store)

  await viewModel.load()

  #expect(viewModel.entries.map { $0.preferredForm } == ["Alpha", "Zeta"])
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsAddsTrimmedPreferredFormAndSeparatedAliases() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )

  await viewModel.add(
    preferredForm: "  FleckApp \n",
    aliases: " fleck app, Fleck application\n fleck app "
  )

  #expect(viewModel.entries.count == 1)
  #expect(viewModel.entries[0].preferredForm == "FleckApp")
  #expect(viewModel.entries[0].aliases == ["fleck app", "Fleck application"])
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsSerializesMutationsAndSupportsEnableDisableAndDelete() async {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )

  async let first: Void = viewModel.add(preferredForm: "First", aliases: "one")
  async let second: Void = viewModel.add(preferredForm: "Second", aliases: "two")
  await first
  await second

  #expect(viewModel.entries.map { $0.preferredForm } == ["First", "Second"])
  let firstID = viewModel.entries[0].id

  await viewModel.setEnabled(false, id: firstID)
  #expect(viewModel.entries.first?.isEnabled == false)

  await viewModel.delete(id: firstID)
  #expect(viewModel.entries.map { $0.preferredForm } == ["Second"])
  #expect(viewModel.errorMessage == nil)
}

@Test @MainActor
func personalDictionarySettingsReportsNonSensitiveLoadErrors() async throws {
  let root = temporarySettingsDictionaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let directory = root.appendingPathComponent("PersonalDictionary", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data("not json".utf8).write(
    to: directory.appendingPathComponent("dictionary-v1.json")
  )

  let viewModel = PersonalDictionarySettingsViewModel(
    store: PersonalDictionaryStore(rootURL: root)
  )
  await viewModel.load()

  #expect(viewModel.entries.isEmpty)
  #expect(viewModel.errorMessage?.contains("Could not load personal dictionary") == true)
  #expect(viewModel.errorMessage?.contains(root.path) == false)
}

@Test
func personalDictionaryRuntimeAndSettingsUseOneStoreAndNativeFormSurface() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let runtimeSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(runtimeSource.contains(
    "let personalDictionaryStore = PersonalDictionaryStore(rootURL: applicationSupportURL)"
  ))
  #expect(runtimeSource.contains(
    "try await personalDictionaryStore.snapshot().entries"
  ))
  #expect(runtimeSource.contains(
    "let personalDictionarySettingsViewModel = PersonalDictionarySettingsViewModel("
  ))
  #expect(runtimeSource.contains("store: personalDictionaryStore"))
  #expect(settingsSource.contains("Section(\"Personal Dictionary\")"))
  #expect(settingsSource.contains("TextField(\"Preferred form\""))
  #expect(settingsSource.contains("TextField(\"Aliases\""))
  #expect(settingsSource.contains("Button(\"Add Entry\""))
  #expect(settingsSource.contains("Toggle("))
  #expect(settingsSource.contains("role: .destructive"))
  #expect(settingsSource.contains("accessibilityLabel"))
}

private func temporarySettingsDictionaryRoot() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckSettingsTests-\(UUID().uuidString)", isDirectory: true)
}
