import Foundation
import SwiftUI

enum ModelLibraryProvider: String, CaseIterable, Identifiable {
  case nvidia = "NVIDIA"
  case google = "Google"

  var id: Self { self }
}

enum ModelLibraryTypeFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case voice = "Voice"
  case cleanup = "Cleanup"

  var id: Self { self }
}

@MainActor
struct ModelLibraryEntry: Identifiable {
  nonisolated let id: String
  let descriptor: AdmittedModelDescriptor
  let presentation: AdmittedModelSettingsPresentation
  let viewModel: AdmittedModelSettingsViewModel
  let title: String
  let provider: ModelLibraryProvider
  let distributor: String
  let symbol: String

  init(
    descriptor: AdmittedModelDescriptor,
    presentation: AdmittedModelSettingsPresentation,
    viewModel: AdmittedModelSettingsViewModel,
    title: String,
    provider: ModelLibraryProvider,
    distributor: String,
    symbol: String
  ) {
    id = Self.pinKey(for: descriptor.role, modelID: descriptor.modelID)
    self.descriptor = descriptor
    self.presentation = presentation
    self.viewModel = viewModel
    self.title = title
    self.provider = provider
    self.distributor = distributor
    self.symbol = symbol
  }

  var typeTitle: String {
    switch descriptor.role {
    case .asr: "Voice recognition"
    case .cleanup: "Text cleanup"
    }
  }

  var shortTypeTitle: String {
    switch descriptor.role {
    case .asr: "Voice"
    case .cleanup: "Cleanup"
    }
  }

  var purpose: String {
    switch descriptor.role {
    case .asr:
      "Transcribes your speech locally. Fleck uses this model automatically while it is installed and healthy; otherwise recognition falls back to Apple Speech."
    case .cleanup:
      "Cleans up captured text locally. Fleck uses this model automatically while it is installed and healthy; otherwise cleanup uses Faithful Local Fallback."
    }
  }

  var fallbackName: String {
    switch descriptor.role {
    case .asr: "Apple Speech"
    case .cleanup: "Faithful Local Fallback"
    }
  }

  var revisionURL: URL {
    descriptor.source
      .appendingPathComponent("tree")
      .appendingPathComponent(descriptor.revision)
  }

  var modelCardURL: URL {
    switch provider {
    case .nvidia:
      URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2")!
    case .google:
      URL(string: "https://huggingface.co/google/gemma-3-1b-it")!
    }
  }

  var licenseURL: URL? {
    switch descriptor.license {
    case "CC-BY-4.0":
      URL(string: "https://creativecommons.org/licenses/by/4.0/")
    case "Gemma Terms of Use":
      URL(string: "https://ai.google.dev/gemma/terms")
    default:
      nil
    }
  }

  var languageNames: [String] {
    descriptor.languages.map {
      Locale.current.localizedString(forLanguageCode: $0) ?? $0
    }
  }

  static func pinKey(for role: AdmittedModelRole, modelID: String) -> String {
    "\(role.identityComponent):\(modelID)"
  }
}

struct ModelLibraryExternalMetric: Identifiable, Equatable {
  let id: String
  let label: String
  let value: String
}

struct ModelLibraryExternalSource: Identifiable, Equatable {
  let id: String
  let label: String
  let url: URL
}

struct ModelLibraryExternalEvidence: Equatable {
  let role: AdmittedModelRole
  let modelID: String
  let admittedRevision: String
  let metrics: [ModelLibraryExternalMetric]
  let context: String
  let sources: [ModelLibraryExternalSource]
  let unmeasuredCleanupAccuracyContext: String?
}

@MainActor
enum ModelLibraryExternalEvidenceCatalog {
  static let parakeetRevision = "ee09c569f73759e6d44c9bd16766f477b2b36d39"
  static let gemmaRevision = "15fed4eafb456c6fcb2a1165f19ac609670ed14b"

  private static let records = [
    ModelLibraryExternalEvidence(
      role: .asr,
      modelID: ModelLibraryCatalog.parakeetModelID,
      admittedRevision: parakeetRevision,
      metrics: [
        ModelLibraryExternalMetric(
          id: "parakeet-v2-overall-rtfx",
          label: "Overall audio throughput",
          value: "145.8× RTFx"
        ),
        ModelLibraryExternalMetric(
          id: "parakeet-v2-mean-per-file-wer",
          label: "Mean per-file WER",
          value: "2.1%"
        ),
      ],
      context: [
        "FluidAudio v2 benchmark runtime reference",
        "LibriSpeech test-clean (2,620 files)",
        "M4 Pro, 48 GB RAM",
        "macOS 26.0",
        "overall audio: 19,452.5 seconds / 133.4 seconds",
        "command: swift run fluidaudiocli asr-benchmark --max-files all --model-version v2",
        "External result; not measured by Fleck or this exact pinned conversion artifact.",
      ].joined(separator: " · "),
      sources: [
        ModelLibraryExternalSource(
          id: "fluidaudio-benchmark",
          label: "FluidAudio v2 benchmark notes",
          url: URL(string: "https://github.com/FluidInference/FluidAudio/blob/87a39dfe4068fef0f1c69bfe704b2b3ef4fbc5bc/Documentation/Benchmarks.md")!
        )
      ],
      unmeasuredCleanupAccuracyContext: nil
    ),
    ModelLibraryExternalEvidence(
      role: .cleanup,
      modelID: ModelLibraryCatalog.gemmaModelID,
      admittedRevision: gemmaRevision,
      metrics: [
        ModelLibraryExternalMetric(
          id: "gemma-mlx-concurrency-one-aggregate-throughput",
          label: "Aggregate output throughput",
          value: "204.29 output tokens/s"
        )
      ],
      context: [
        "AbstractCore Python MLX continuous-batching benchmark",
        "65,536 output tokens / 320.802923 seconds",
        "Concurrency 1",
        "128 prompts capped at 512 output tokens each",
        "MacBook Pro M4 Max, 128 GB",
        "Aggregate total output throughput, not per-query or decode speed",
        "External result; not measured by Fleck's Swift cleanup pipeline.",
      ].joined(separator: " · "),
      sources: [
        ModelLibraryExternalSource(
          id: "abstractcore-mlx-docs",
          label: "AbstractCore benchmark context",
          url: URL(string: "https://github.com/lpalbou/AbstractCore/blob/cf2fc6c85f3db31df480811d594fc50699049379/docs/concurrency.md#realistic-mlx-concurrency-results-mbp-m4-max-128gb")!
        ),
        ModelLibraryExternalSource(
          id: "abstractcore-mlx-csv",
          label: "Raw MLX concurrency results (CSV)",
          url: URL(string: "https://raw.githubusercontent.com/lpalbou/AbstractCore/cf2fc6c85f3db31df480811d594fc50699049379/docs/assets/mlx_concurrency/mlx_concurrency_summary_20260128_210057.csv")!
        ),
      ],
      unmeasuredCleanupAccuracyContext: "The throughput benchmark did not measure cleanup accuracy."
    ),
  ]

  static func evidence(
    for descriptor: AdmittedModelDescriptor
  ) -> ModelLibraryExternalEvidence? {
    records.first {
      $0.role == descriptor.role
        && $0.modelID == descriptor.modelID
        && $0.admittedRevision == descriptor.revision
    }
  }
}

@MainActor
enum ModelLibraryCatalog {
  static let parakeetModelID = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
  static let gemmaModelID = "mlx-community/gemma-3-1b-it-qat-4bit"

  static func entries(
    speechViewModel: AdmittedModelSettingsViewModel,
    cleanupViewModel: AdmittedModelSettingsViewModel
  ) -> [ModelLibraryEntry] {
    [
      entry(
        for: speechViewModel,
        role: .asr,
        modelID: parakeetModelID,
        provider: .nvidia,
        distributor: "FluidInference",
        symbol: "waveform"
      ),
      entry(
        for: cleanupViewModel,
        role: .cleanup,
        modelID: gemmaModelID,
        provider: .google,
        distributor: "mlx-community",
        symbol: "text.alignleft"
      ),
    ].compactMap { $0 }
  }

  static func providers(in entries: [ModelLibraryEntry]) -> [ModelLibraryProvider] {
    Set(entries.map(\.provider)).sorted {
      $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending
    }
  }

  static func requiresTermsReview(
    for action: AdmittedModelSettingsAction,
    descriptor: AdmittedModelDescriptor
  ) -> Bool {
    (action == .install || action == .update || action == .repair)
      && (descriptor.modelID == gemmaModelID || descriptor.license == "Gemma Terms of Use")
  }

  static func filtered(
    _ entries: [ModelLibraryEntry],
    searchQuery: String,
    provider: String,
    type: ModelLibraryTypeFilter,
    pins: Set<String>,
    ascending: Bool
  ) -> [ModelLibraryEntry] {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return entries
      .filter { entry in
        (provider == "all" || provider == entry.provider.rawValue)
          && (type == .all
            || (type == .voice && entry.descriptor.role == .asr)
            || (type == .cleanup && entry.descriptor.role == .cleanup))
          && (query.isEmpty
            || [entry.title, entry.provider.rawValue, entry.distributor, entry.typeTitle]
              .contains { $0.localizedStandardContains(query) })
      }
      .sorted { left, right in
        let leftIsPinned = pins.contains(left.id)
        let rightIsPinned = pins.contains(right.id)
        if leftIsPinned != rightIsPinned {
          return leftIsPinned
        }
        let comparison = left.title.localizedStandardCompare(right.title)
        if comparison == .orderedSame {
          return left.id < right.id
        }
        return ascending
          ? comparison == .orderedAscending
          : comparison == .orderedDescending
      }
  }

  private static func entry(
    for viewModel: AdmittedModelSettingsViewModel,
    role: AdmittedModelRole,
    modelID: String,
    provider: ModelLibraryProvider,
    distributor: String,
    symbol: String
  ) -> ModelLibraryEntry? {
    let presentation = viewModel.presentation
    guard let descriptor = presentation.descriptor,
          descriptor.role == role,
          descriptor.modelID == modelID else {
      return nil
    }
    return ModelLibraryEntry(
      descriptor: descriptor,
      presentation: presentation,
      viewModel: viewModel,
      title: presentation.modelLabel,
      provider: provider,
      distributor: distributor,
      symbol: symbol
    )
  }
}

enum ModelLibraryLayout {
  static let detailsStackWidth: CGFloat = 1_020

  static func stacksDetails(width: CGFloat, dynamicTypeSize: DynamicTypeSize) -> Bool {
    width < detailsStackWidth || dynamicTypeSize >= .accessibility1
  }
}
