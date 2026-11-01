#if os(macOS)
  import AppKit
  import FleckCore
  import Foundation
  import SwiftUI
  import Testing

  @testable import FleckApp

  @Suite("SettingsSearch")
  struct SettingsSearchTests {
    @Test func emptyAndWhitespaceQueriesReturnNoResults() {
      #expect(SettingsSearchIndex.results(for: "").isEmpty)
      #expect(SettingsSearchIndex.results(for: "  \n\t ").isEmpty)
    }

    @Test func colorThemeRemainsSearchableWithoutDormantColorControls() {
      #expect(
        SettingsSearchIndex.results(for: "COLOR THEME").first?.target
          == .appearanceColorTheme
      )
      #expect(SettingsSearchIndex.results(for: "accent color").isEmpty)
      #expect(SettingsSearchIndex.results(for: "editor text color").isEmpty)
      #expect(SettingsSearchIndex.results(for: "editor background").isEmpty)
    }

    @Test func aliasesAndAllQueryTokensMustMatch() {
      #expect(
        SettingsSearchIndex.results(for: "automatic bullets").first?.target
          == .generalAutomaticLists
      )
      #expect(
        SettingsSearchIndex.results(for: "permission recovery").first?.target
          == .dictationStatus
      )
      #expect(SettingsSearchIndex.results(for: "automatic microphone").isEmpty)
    }

    @Test func glassAndOpacityRemainSearchableAsSeparateSettings() throws {
      let glass = try #require(SettingsSearchIndex.results(for: "glass").first)
      let opacity = try #require(SettingsSearchIndex.results(for: "glass opacity").first)

      #expect(glass.target == .appearanceChromeAppearance)
      #expect(glass.anchor == .appearanceChromeAppearance)
      #expect(opacity.target == .appearanceGlassOpacity)
      #expect(opacity.anchor == .appearanceGlassOpacity)
    }

    @Test func noMatchReturnsAnEmptyDeterministicResultList() {
      #expect(SettingsSearchIndex.results(for: "definitely-not-a-setting").isEmpty)
      #expect(
        SettingsSearchIndex.results(for: "model")
          == SettingsSearchIndex.results(for: "model")
      )
    }

    @Test func titleMatchesRankBeforeAliasesAndCatalogOrderBreaksTies() {
      let exact = SettingsSearchIndex.results(for: "Build")
      #expect(exact.first?.target == .aboutBuild)

      let history = SettingsSearchIndex.results(for: "history")
      #expect(
        history.map(\.target).prefix(2) == [
          .dictationLocalHistory,
          .dictationClearHistory,
        ])
    }

    @Test func everySectionHasASectionResultAndGeneralMatchesEditing() {
      #expect(
        SettingsSection.allCases.allSatisfy { section in
          SettingsSearchIndex.catalog.contains {
            $0.target == .section(section)
              && $0.destination == section
              && $0.anchor == .section(section)
          }
        }
      )
      #expect(SettingsSearchIndex.results(for: "Editing").first?.target == .section(.editing))
    }

    @Test func modelsSearchResultsTargetTheSettingsModelsPane() throws {
      let results: [(String, SettingsSearchTarget)] = [
        ("Models", .section(.models)),
        ("model library", .section(.models)),
        ("optional local models", .section(.models)),
        ("Dictation model", .dictationModel),
        ("Cleanup model", .dictationCleanupModel),
      ]

      for (query, target) in results {
        let result = try #require(SettingsSearchIndex.results(for: query).first)
        #expect(result.target == target)
        #expect(result.destination == .models)
        #expect(result.anchor == .section(.models))
      }
    }

    @Test func catalogCoversEveryApprovedTargetExactlyOnce() {
      let expected = Set(
        SettingsSection.allCases.map(SettingsSearchTarget.section)
          + [
            .generalLaunchAtLogin,
            .generalAutomaticLists,
            .generalConfirmTrash,
            .appearanceTheme,
            .appearanceColorTheme,
            .appearanceChromeAppearance,
            .appearanceGlassOpacity,
            .appearanceWidth,
            .appearanceHeight,
          ]
          + Shortcut.Action.allCases.map(SettingsSearchTarget.shortcut)
          + [
            .dictationStatus,
            .dictationModel,
            .dictationCleanupModel,
            .dictationModifier,
            .dictationMicrophone,
            .dictationRecognitionLanguage,
            .dictationStatusCapsule,
            .dictationShortcutGuide,
            .dictationLocalHistory,
            .dictationClearHistory,
            .dictationPrivacy,
            .vocabularyAdd,
            .vocabularySearch,
          ]
          + [
            .vocabularySort,
            .vocabularyReload,
            .vocabularyTransfer,
            .vocabularyExportDictionary,
            .vocabularyExportCSV,
            .vocabularyImportDictionary,
            .agentsConnector,
          ]
          + AgentIntegrationKind.allCases.map(SettingsSearchTarget.agentIntegration)
          + [
            .agentsConnectedProfiles,
            .agentsSetup,
            .agentsActivity,
            .agentsUpdateBanners,
            .agentsOpenActivity,
            .agentsClearActivity,
            .agentsAccess,
            .aboutProductVersion,
            .aboutBuild,
            .aboutSource,
            .aboutCandidateStatus,
            .aboutMetadata,
            .aboutCopyBuildInfo,
          ]
      )

      #expect(Set(SettingsSearchIndex.catalog.map(\.target)) == expected)
      #expect(SettingsSearchIndex.catalog.count == expected.count)
      #expect(SettingsSearchIndex.catalog.allSatisfy { !$0.title.isEmpty })
      #expect(SettingsSearchIndex.catalog.allSatisfy { expected.contains($0.anchor) })
    }

    @Test func vocabularyActionsAndSuggestionsRemainDiscoverableInGlobalSettingsSearch() {
      let queries: [(String, SettingsSearchTarget)] = [
        ("Add New", .vocabularyAdd),
        ("Search vocabulary", .vocabularySearch),
        ("Suggestions", .section(.vocabulary)),
        ("Sort", .vocabularySort),
        ("Reload", .vocabularyReload),
        ("Transfer", .vocabularyTransfer),
        ("Export Dictionary", .vocabularyExportDictionary),
        ("Export Entries (CSV)", .vocabularyExportCSV),
        ("Import Dictionary", .vocabularyImportDictionary),
      ]

      for (query, target) in queries {
        #expect(SettingsSearchIndex.results(for: query).first?.target == target)
      }
    }

    @Test func suggestionsSearchUsesTheDictionarySectionInsteadOfADeadFilterTarget() throws {
      let result = try #require(SettingsSearchIndex.results(for: "suggestions").first)

      #expect(result.target == .section(.vocabulary))
      #expect(result.anchor == .section(.vocabulary))
      #expect(result.destination == .vocabulary)
      #expect(
        !SettingsSearchIndex.catalog.contains {
          $0.target.identifier.hasPrefix("vocabulary-filter-")
        }
      )
    }

    @Test func visibleDictionaryHeadingRanksToItsSectionAndKeepsExistingAliases() throws {
      for query in ["Dictionary", "Vocabulary", "Suggestions", "  vOCaBulary  "] {
        let result = try #require(SettingsSearchIndex.results(for: query).first)

        #expect(result.target == .section(.vocabulary))
        #expect(result.destination == .vocabulary)
        #expect(result.anchor == .section(.vocabulary))
      }

      #expect(SettingsSearchIndex.results(for: "Dictionary").first?.title == "Dictionary")
    }

    @Test func labelsComeFromTheirAuthoritativeTypes() throws {
      for section in SettingsSection.allCases {
        let result = try #require(
          SettingsSearchIndex.catalog.first { $0.target == .section(section) })
        #expect(result.title == (section == .vocabulary ? "Dictionary" : section.title))
      }
      for action in Shortcut.Action.allCases {
        let result = try #require(
          SettingsSearchIndex.catalog.first { $0.target == .shortcut(action) })
        #expect(result.title == action.title)
      }
      for integration in AgentIntegrationKind.allCases {
        let result = try #require(
          SettingsSearchIndex.catalog.first { $0.target == .agentIntegration(integration) }
        )
        #expect(result.title == integration.displayName)
      }
    }

    @Test func highlightMovementIsBoundedAndDoesNotCommitAResult() throws {
      let results = SettingsSearchIndex.results(for: "model")
      let first = try #require(results.first?.target)
      let second = try #require(results.dropFirst().first?.target)

      #expect(
        SettingsSearchIndex.movingHighlight(
          .down,
          from: nil,
          in: results
        ) == first
      )
      #expect(
        SettingsSearchIndex.movingHighlight(
          .down,
          from: first,
          in: results
        ) == second
      )
      #expect(
        SettingsSearchIndex.movingHighlight(
          .up,
          from: first,
          in: results
        ) == first
      )
    }

    @Test func repeatedRequestsReceiveFreshIdentities() {
      let first = SettingsSearchRequest(target: .dictationPrivacy)
      let second = SettingsSearchRequest(target: .dictationPrivacy)

      #expect(first.target == second.target)
      #expect(first.id != second.id)
    }

    @Test func unpackagedAboutTargetsRevealAvailableMetadata() {
      for target in [
        SettingsSearchTarget.aboutProductVersion,
        .aboutSource,
        .aboutCandidateStatus,
      ] {
        #expect(target.revealAnchor(isPackaged: false) == .aboutMetadata)
        #expect(target.revealAnchor(isPackaged: true) == target)
      }
    }

    @Test func vocabularyTargetsScrollThePageToTheDictionaryHeader() {
      let vocabularyTargets: [SettingsSearchTarget] = [
        .section(.vocabulary),
        .vocabularyAdd,
        .vocabularySearch,
        .vocabularySort,
        .vocabularyReload,
        .vocabularyTransfer,
        .vocabularyExportDictionary,
        .vocabularyExportCSV,
        .vocabularyImportDictionary,
      ]
      let transferTargets: [SettingsSearchTarget] = [
        .vocabularyTransfer,
        .vocabularyExportDictionary,
        .vocabularyExportCSV,
        .vocabularyImportDictionary,
      ]

      #expect(
        vocabularyTargets.filter { !transferTargets.contains($0) }.allSatisfy {
          $0.pageScrollAnchor == .section(.vocabulary)
        }
      )
      #expect(
        transferTargets.allSatisfy { $0.pageScrollAnchor == .vocabularyTransferFooter }
      )
      #expect(
        SettingsSearchTarget.vocabularyTransferFooter.pageScrollAnchor
          == .vocabularyTransferFooter
      )
      #expect(SettingsSearchTarget.section(.vocabulary).pageScrollAnchor == .section(.vocabulary))
      #expect(SettingsSearchTarget.appearanceTheme.pageScrollAnchor == .appearanceTheme)
      #expect(SettingsSearchTarget.dictationPrivacy.pageScrollAnchor == .dictationPrivacy)
      #expect(vocabularyTargets.allSatisfy { $0.usesVocabularyFocusLifecycle })
      #expect(SettingsSearchTarget.section(.vocabulary).usesVocabularyFocusLifecycle)
      #expect(!SettingsSearchTarget.appearanceTheme.usesVocabularyFocusLifecycle)
      #expect(!SettingsSearchTarget.dictationPrivacy.usesVocabularyFocusLifecycle)
    }

    @Test @MainActor
    func readinessReturnRejectsAnAnchorMovedToAnotherWindow() {
      let (window, view, attachment) = readinessReturnHost()
      let otherWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless], backing: .buffered, defer: false
      )
      defer {
        window.contentView = nil
        otherWindow.contentView = nil
      }
      let inputID = UUID()
      let request = SettingsKeyboardFocusReturnRequest(window: window, inputID: inputID)
      let generation = attachment.generation
      #expect(attachment.matches(request, generation: generation, inputID: inputID))

      window.contentView = nil
      otherWindow.contentView = view
      #expect(view.window === otherWindow)
      #expect(!attachment.matches(request, generation: generation, inputID: inputID))
      #expect(!attachment.matches(request, generation: attachment.generation, inputID: inputID))
    }

    @Test @MainActor
    func readinessReturnRejectsDetachedAndReattachedNativeAttachment() {
      let (window, view, attachment) = readinessReturnHost()
      defer { window.contentView = nil }
      let inputID = UUID()
      let request = SettingsKeyboardFocusReturnRequest(window: window, inputID: inputID)
      let generation = attachment.generation
      #expect(attachment.matches(request, generation: generation, inputID: inputID))

      window.contentView = nil
      #expect(view.window == nil)
      #expect(!attachment.matches(request, generation: generation, inputID: inputID))
      window.contentView = view
      #expect(view.window === window)
      #expect(!attachment.matches(request, generation: generation, inputID: inputID))
      let currentGeneration = attachment.generation
      #expect(attachment.matches(request, generation: currentGeneration, inputID: inputID))
      attachment.invalidate()
      #expect(!attachment.matches(request, generation: currentGeneration, inputID: inputID))
    }

    @Test @MainActor
    func readinessReturnReplacementSurvivesOldAttachmentDismantling() {
      let (window, oldView, attachment) = readinessReturnHost()
      defer { window.contentView = nil }
      let inputID = UUID()
      let request = SettingsKeyboardFocusReturnRequest(window: window, inputID: inputID)
      let generation = attachment.generation
      #expect(attachment.matches(request, generation: generation, inputID: inputID))

      let replacement = SettingsSearchProbe.ProbeView()
      replacement.bind(to: attachment)
      window.contentView = replacement
      oldView.bind(to: nil)
      #expect(attachment.view === replacement)
      #expect(!attachment.matches(request, generation: generation, inputID: inputID))
      #expect(attachment.matches(request, generation: attachment.generation, inputID: inputID))
    }

    @Test(arguments: [false, true]) @MainActor
    func readinessReturnRejectsInterveningPointerOrKeyInput(isKeyboard: Bool) {
      let (window, _, attachment) = readinessReturnHost()
      defer { window.contentView = nil }
      let inputModality = SettingsSearchInputModality()
      inputModality.record(isKeyboardInput: true, windowNumber: window.windowNumber)
      let request = SettingsKeyboardFocusReturnRequest(
        window: window, inputID: inputModality.inputID
      )
      let generation = attachment.generation
      #expect(attachment.matches(request, generation: generation, inputID: inputModality.inputID))

      inputModality.record(isKeyboardInput: isKeyboard, windowNumber: window.windowNumber)
      #expect(request.inputID != inputModality.inputID)
      #expect(!attachment.matches(request, generation: generation, inputID: inputModality.inputID))
    }

    @Test @MainActor
    func readinessReturnProducerWritesTheBoundWindowAndReplacesTheCurrentInput() throws {
      let (window, _, attachment) = readinessReturnHost()
      defer { window.contentView = nil }
      var boundRequest: SettingsKeyboardFocusReturnRequest?
      let requestBinding = Binding(
        get: { boundRequest },
        set: { boundRequest = $0 }
      )
      let firstInputID = UUID()

      attachment.publishReturnRequest(inputID: firstInputID, to: requestBinding)
      let firstRequest = try #require(boundRequest)
      #expect(firstRequest.window === window)
      #expect(firstRequest.inputID == firstInputID)

      let currentInputID = UUID()
      attachment.publishReturnRequest(inputID: currentInputID, to: requestBinding)
      let currentRequest = try #require(boundRequest)
      #expect(currentRequest.id != firstRequest.id)
      #expect(currentRequest.window === window)
      #expect(currentRequest.inputID == currentInputID)
    }

    @Test @MainActor
    func readinessReturnProducerClearsUnboundAndDetachedRequests() {
      let (window, view, attachment) = readinessReturnHost()
      let fallbackWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless], backing: .buffered, defer: false
      )
      defer {
        window.contentView = nil
        fallbackWindow.contentView = nil
      }
      var boundRequest: SettingsKeyboardFocusReturnRequest? =
        SettingsKeyboardFocusReturnRequest(window: fallbackWindow, inputID: UUID())
      let requestBinding = Binding(
        get: { boundRequest },
        set: { boundRequest = $0 }
      )

      view.bind(to: nil)
      #expect(attachment.view == nil)
      #expect(view.window === window)
      attachment.publishReturnRequest(inputID: UUID(), to: requestBinding)
      #expect(boundRequest == nil)

      view.bind(to: attachment)
      window.contentView = nil
      #expect(attachment.view === view)
      #expect(view.window == nil)
      boundRequest = SettingsKeyboardFocusReturnRequest(window: fallbackWindow, inputID: UUID())
      attachment.publishReturnRequest(inputID: UUID(), to: requestBinding)
      #expect(boundRequest == nil)
    }

    @MainActor
    private func readinessReturnHost() -> (
      NSWindow, SettingsSearchProbe.ProbeView, SettingsKeyboardFocusReturnAttachment
    ) {
      _ = NSApplication.shared
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless], backing: .buffered, defer: false
      )
      let attachment = SettingsKeyboardFocusReturnAttachment()
      let view = SettingsSearchProbe.ProbeView()
      view.bind(to: attachment)
      window.contentView = view
      return (window, view, attachment)
    }

    @Test func searchSelectionUsesThePaletteAccentAndPairedSelectionTokens() {
      for family in FleckColorTheme.allCases {
        for appearance in FleckThemeAppearance.allCases {
          let snapshot = FleckThemeSnapshot.resolve(
            colorTheme: family,
            mode: appearance == .light ? .light : .dark,
            systemAppearance: appearance,
            reduceTransparency: false,
            increasedContrast: false
          )
          let presentation = SettingsAccentPresentation(theme: snapshot)
          #expect(presentation.color == snapshot.color(.accent))
          #expect(presentation.selectionColor == snapshot.color(.selectionFill))
          #expect(presentation.contrastingColor == snapshot.color(.selectionText))
          #expect(presentation.primaryTextColor == snapshot.color(.textPrimary))
          #expect(presentation.secondaryTextColor == snapshot.color(.caption))
        }
      }
    }
  }
#endif
