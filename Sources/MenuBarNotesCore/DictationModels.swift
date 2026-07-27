import Foundation

public enum CleanDictationFeatures {
  #if CLEAN_DICTATION_ENHANCED_CANDIDATE
    public static let enhancedLocalCandidateEnabled = true
  #else
    public static let enhancedLocalCandidateEnabled = false
  #endif
}

public enum DictationMode: String, Codable, Sendable {
  case focused
  case smartCapture
}

public enum DictationSpeechEngine: String, Codable, CaseIterable, Sendable {
  case standard
  case enhancedLocal
}

public enum DictationCleanupOutcome: String, Codable, Sendable {
  case pending
  case cleaned
  case usedRaw
  case failed
}

public enum DictationInsertionOutcome: String, Codable, Sendable {
  case pending
  case saved
  case unsaved
  case cancelled
}

public struct DictationShortcut: Codable, Equatable, Sendable {
  public var keyCode: UInt32?
  public var carbonModifiers: UInt32
  public var isEnabled: Bool { keyCode != nil && carbonModifiers != 0 }

  public init(keyCode: UInt32? = nil, carbonModifiers: UInt32 = 0) {
    self.keyCode = keyCode
    self.carbonModifiers = carbonModifiers
  }
}

public struct DictationDestination: Codable, Equatable, Sendable {
  public let noteID: UUID
  public let title: String

  public init(noteID: UUID, title: String) {
    self.noteID = noteID
    self.title = title
  }
}

public struct DictationHistoryRecord: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let mode: DictationMode
  public let engine: DictationSpeechEngine
  public let startedAt: Date
  public var completedAt: Date
  public var rawTranscript: String
  public var cleanedTranscript: String?
  public var cleanupOutcome: DictationCleanupOutcome
  public var destination: DictationDestination?
  public var insertionOutcome: DictationInsertionOutcome

  public init(
    id: UUID,
    mode: DictationMode,
    engine: DictationSpeechEngine,
    startedAt: Date,
    completedAt: Date,
    rawTranscript: String,
    cleanedTranscript: String? = nil,
    cleanupOutcome: DictationCleanupOutcome,
    destination: DictationDestination? = nil,
    insertionOutcome: DictationInsertionOutcome
  ) {
    self.id = id
    self.mode = mode
    self.engine = engine
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.rawTranscript = rawTranscript
    self.cleanedTranscript = cleanedTranscript
    self.cleanupOutcome = cleanupOutcome
    self.destination = destination
    self.insertionOutcome = insertionOutcome
  }
}

public struct DictationInsertionReceipt: Equatable, Sendable {
  public let captureID: UUID
  public let noteID: UUID
  public let insertedSuffix: String

  public init(captureID: UUID, noteID: UUID, insertedSuffix: String) {
    self.captureID = captureID
    self.noteID = noteID
    self.insertedSuffix = insertedSuffix
  }
}

enum DictationFailure: Error, Equatable {
  case unavailable
  case permissionDenied
  case noSpeech
  case transcriptionFailed
  case saveFailed
  case interrupted
}
