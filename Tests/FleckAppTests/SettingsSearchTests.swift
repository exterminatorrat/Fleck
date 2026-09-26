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

    @Test func labelsComeFromTheirAuthoritativeTypes() throws {
      for section in SettingsSection.allCases {
        let result = try #require(
          SettingsSearchIndex.catalog.first { $0.target == .section(section) })
        #expect(result.title == section.title)
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
