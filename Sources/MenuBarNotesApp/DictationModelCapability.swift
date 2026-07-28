#if os(macOS)
  import Combine

  #if CLEAN_DICTATION_ENHANCED_CANDIDATE
    typealias DictationModelCapability = EnhancedModelManager
  #else
    @MainActor
    final class DictationModelCapability: ObservableObject {
      var isReady: Bool { false }
    }
  #endif
#endif
