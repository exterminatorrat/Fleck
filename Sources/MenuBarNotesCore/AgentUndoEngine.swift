import Foundation

public enum AgentUndoEngine {
  public static func inverting(
    _ patch: AgentTextPatch,
    in body: String
  ) throws -> String {
    let body = body
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let exactRange = NSRange(
      location: patch.range.location,
      length: patch.afterText.utf16.count
    )
    if matches(patch, at: exactRange, in: body) {
      return replacing(exactRange, with: patch.beforeText, in: body)
    }

    let candidates = candidateRanges(for: patch.afterText, in: body)
      .filter { matches(patch, at: $0, in: body) }
    guard candidates.count == 1, let range = candidates.first else {
      throw AgentWorkspaceError(code: .unsafeUndo)
    }
    return replacing(range, with: patch.beforeText, in: body)
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

  private static func replacing(
    _ range: NSRange,
    with replacement: String,
    in body: String
  ) -> String {
    (body as NSString).replacingCharacters(in: range, with: replacement)
  }

  private static func exactlyEqual(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf16.elementsEqual(rhs.utf16)
  }
}
