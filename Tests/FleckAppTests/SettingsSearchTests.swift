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

    @Test func matchingIsCaseAndDiacriticInsensitive() {
      #expect(SettingsSearchIndex.results(for: "ACCENT COLOR").first?.target == .appearanceAccent)
      #expect(SettingsSearchIndex.results(for: "sélection tint").first?.target == .appearanceAccent)
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
            .appearanceAccent,
            .appearanceEditorText,
            .appearanceEditorBackground,
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
          + PersonalDictionarySettingsViewModel.Filter.allCases.map(
            SettingsSearchTarget.vocabularyFilter
          )
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
        .vocabularyAdd,
        .vocabularySearch,
        .vocabularyFilter(.all),
        .vocabularyFilter(.enabled),
        .vocabularyFilter(.disabled),
        .vocabularyFilter(.suggestions),
        .vocabularySort,
        .vocabularyReload,
        .vocabularyTransfer,
        .vocabularyExportDictionary,
        .vocabularyExportCSV,
        .vocabularyImportDictionary,
      ]

      #expect(
        vocabularyTargets.allSatisfy {
          $0.pageScrollAnchor == .section(.vocabulary)
        }
      )
      #expect(SettingsSearchTarget.section(.vocabulary).pageScrollAnchor == .section(.vocabulary))
      #expect(SettingsSearchTarget.appearanceTheme.pageScrollAnchor == .appearanceTheme)
      #expect(SettingsSearchTarget.dictationPrivacy.pageScrollAnchor == .dictationPrivacy)
      #expect(vocabularyTargets.allSatisfy { $0.usesVocabularyFocusLifecycle })
      #expect(SettingsSearchTarget.section(.vocabulary).usesVocabularyFocusLifecycle)
      #expect(!SettingsSearchTarget.appearanceTheme.usesVocabularyFocusLifecycle)
      #expect(!SettingsSearchTarget.dictationPrivacy.usesVocabularyFocusLifecycle)
    }

    @Test func savedAccentPresentationMaintainsNormalTextContrastOnOpaqueSelections() {
      for colorScheme in [ColorScheme.light, .dark] {
        for increasedContrast in [false, true] {
          for hex in ["#7C6CF2", "#808080", "#FF0000", "#00FF00", "#0000FF"] {
            let presentation = SettingsAccentPresentation(
              hex: hex,
              colorScheme: colorScheme,
              increasedContrast: increasedContrast
            )
            #expect(presentation.selectionFillColor.alphaComponent == 1)
            #expect(presentation.contrastRatio >= 4.5)
            #expect(presentation.usesDarkContent == (colorScheme == .light))
            #expect(presentation.selectionFillColor != NSColor(hex: hex))
          }
        }
      }
    }
  }
#endif
