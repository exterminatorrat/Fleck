import Foundation

public enum AgentUndoEngine {
  public static func inverting(
    _ patch: AgentTextPatch,
    in body: String
  ) throws -> String {
    try draft(inverting: patch, in: body).body
  }

  public static func draft(
    inverting patch: AgentTextPatch,
    in body: String
  ) throws -> AgentMutationDraft {
    let range = try resolvedRange(for: patch, in: body)
    return inverseDraft(
      replacing: range,
      with: patch.beforeText,
      in: body
    )
  }

  private static func resolvedRange(
    for patch: AgentTextPatch,
    in body: String
  ) throws -> NSRange {
    if patch.range.location == 0,
      patch.range.length == patch.beforeText.utf16.count,
      !patch.beforeText.isEmpty,
      patch.afterText.isEmpty,
      patch.prefixContext.isEmpty,
      patch.suffixContext.isEmpty
    {
      guard body.isEmpty else {
        throw AgentWorkspaceError(code: .unsafeUndo)
      }
      return NSRange(location: 0, length: 0)
    }

    let exactRange = NSRange(
      location: patch.range.location,
      length: patch.afterText.utf16.count
    )
    if matches(patch, at: exactRange, in: body) {
      return exactRange
    }

    let candidates = candidateRanges(for: patch.afterText, in: body)
      .filter { matches(patch, at: $0, in: body) }
    guard candidates.count == 1, let range = candidates.first else {
      throw AgentWorkspaceError(code: .unsafeUndo)
    }
    return range
  }

  private static func candidateRanges(
    for text: String,
    in body: String
  ) -> [NSRange] {
    if text.isEmpty {
      return body.indices.map {
        NSRange($0..<$0, in: body)
      } + [NSRange(location: body.utf16.count, length: 0)]
    }

    let source = body as NSString
    var ranges: [NSRange] = []
    var location = 0
    while location <= source.length - text.utf16.count {
      let match = source.range(
        of: text,
        options: .literal,
        range: NSRange(
          location: location,
          length: source.length - location
        )
      )
      guard match.location != NSNotFound else { break }
      ranges.append(match)
      location = match.location + 1
    }
    return ranges
  }

  private static func matches(
    _ patch: AgentTextPatch,
    at range: NSRange,
    in body: String
  ) -> Bool {
    let source = body as NSString
    guard
      range.location != NSNotFound,
      range.location >= 0,
      range.length >= 0,
      NSMaxRange(range) <= source.length,
      exactlyEqual(source.substring(with: range), patch.afterText)
    else {
      return false
    }

    let prefixLength = patch.prefixContext.utf16.count
    let suffixLength = patch.suffixContext.utf16.count
    guard
      range.location >= prefixLength,
      source.length - NSMaxRange(range) >= suffixLength
    else {
      return false
    }
    let prefix = source.substring(
      with: NSRange(
        location: range.location - prefixLength,
        length: prefixLength
      )
    )
    let suffix = source.substring(
      with: NSRange(
        location: NSMaxRange(range),
        length: suffixLength
      )
    )
    return exactlyEqual(prefix, patch.prefixContext)
      && exactlyEqual(suffix, patch.suffixContext)
  }

  private static func inverseDraft(
    replacing range: NSRange,
    with replacement: String,
    in body: String
  ) -> AgentMutationDraft {
    let source = body as NSString
    let prefix = source.substring(
      with: NSRange(location: 0, length: range.location)
    )
    let suffixStart = NSMaxRange(range)
    let suffix = source.substring(
      with: NSRange(
        location: suffixStart,
        length: source.length - suffixStart
      )
    )
    let patch = AgentTextPatch(
      beforeText: source.substring(with: range),
      afterText: replacement,
      range: range,
      prefixContext: String(prefix.suffix(32)),
      suffixContext: String(suffix.prefix(32))
    )

    return AgentMutationDraft(
      body: source.replacingCharacters(in: range, with: replacement),
      patch: patch
    )
  }

  private static func exactlyEqual(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf16.elementsEqual(rhs.utf16)
  }
}
