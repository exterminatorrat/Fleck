struct DictationInferenceScheduler: Sendable {
  func canStart(
    _ requested: DictationInferencePriority,
    while running: DictationInferencePriority?
  ) -> Bool {
    guard let running else { return true }
    return requested >= running
  }
}

enum DictationInferencePriority: Int, Comparable, Sendable {
  case optionalPolish = 0
  case cleanup = 1
  case finalASR = 2
  case liveASR = 3

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
