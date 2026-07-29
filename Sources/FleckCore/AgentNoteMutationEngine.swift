import CryptoKit
import Foundation

public enum AgentNoteMutationEngine {
  public static func append(
    text: String,
    to body: String,
    maximumBytes: Int = 65_536
  ) throws -> AgentMutationDraft {
    let text = normalize(text)
    let insertion = body.isEmpty ? text : "\n\n" + text
    try validatePayload(insertion, maximumBytes: maximumBytes)

    return draft(
      replacing: NSRange(location: body.utf16.count, length: 0),
      with: insertion,
      in: body
    )
  }

  public static func insert(
    text: String,
    beforeLine: Int,
    in body: String,
    maximumBytes: Int = 65_536
  ) throws -> AgentMutationDraft {
    let text = normalize(text)

    if body.isEmpty {
      guard beforeLine == 1 else { throw invalidPayload() }
      try validatePayload(text, maximumBytes: maximumBytes)
      return draft(
        replacing: NSRange(location: 0, length: 0),
        with: text,
        in: body
      )
    }

    let lines = lineRanges(in: body)
    guard beforeLine >= 1, beforeLine <= lines.count + 1 else {
      throw invalidPayload()
    }
    if beforeLine == lines.count + 1 {
      let insertion = "\n" + text
      try validatePayload(insertion, maximumBytes: maximumBytes)
      return draft(
        replacing: NSRange(location: body.utf16.count, length: 0),
        with: insertion,
        in: body
      )
    }

    let insertion = text + "\n"
    try validatePayload(insertion, maximumBytes: maximumBytes)
    return draft(
      replacing: NSRange(
        location: lines[beforeLine - 1].location,
        length: 0
      ),
      with: insertion,
      in: body
    )
  }

  public static func replaceLines(
    in body: String,
    startLine: Int,
    endLine: Int,
    expectedTextSHA256: String,
    replacement: String,
    maximumBytes: Int = 65_536
  ) throws -> AgentMutationDraft {
    let replacement = normalize(replacement)
    try validatePayload(replacement, maximumBytes: maximumBytes)
    let lines =
      body.isEmpty
      ? [NSRange(location: 0, length: 0)]
      : lineRanges(in: body)
    guard
      startLine >= 1,
      endLine >= startLine,
      endLine <= lines.count
    else {
      throw invalidPayload()
    }

    let first = lines[startLine - 1]
    let last = lines[endLine - 1]
    let range = NSRange(
      location: first.location,
      length: NSMaxRange(last) - first.location
    )
    let observed = (body as NSString).substring(with: range)
    guard sha256(observed) == expectedTextSHA256 else {
      throw invalidPayload()
    }

    return draft(replacing: range, with: replacement, in: body)
  }

  public static func tasks(in body: String) -> [AgentParsedTask] {
    guard !body.isEmpty else { return [] }
    let source = body as NSString

    return lineRanges(in: body).enumerated().compactMap { index, range in
      parseTask(source.substring(with: range), line: index + 1)
    }
  }

  public static func addTask(
    text: String,
    after task: AgentParsedTask?,
    in body: String,
    maximumBytes: Int = 65_536
  ) throws -> AgentMutationDraft {
    let text = try normalizedTaskText(text, maximumBytes: maximumBytes)
    let indentation: String
    let range: NSRange
    let insertion: String
    let newLine: Int

    if let task {
      let task = try currentTask(matching: task, in: body)
      let lines = lineRanges(in: body)
      indentation = task.indentation
      newLine = task.line + 1
      if task.line < lines.count {
        range = NSRange(
          location: lines[task.line].location,
          length: 0
        )
        insertion = indentation + "○ " + text + "\n"
      } else {
        range = NSRange(location: body.utf16.count, length: 0)
        insertion = "\n" + indentation + "○ " + text
      }
    } else {
      indentation = ""
      newLine = body.isEmpty ? 1 : lineRanges(in: body).count + 1
      range = NSRange(location: body.utf16.count, length: 0)
      insertion = (body.isEmpty ? "" : "\n") + "○ " + text
    }

    try validatePayload(insertion, maximumBytes: maximumBytes)
    let mutation = draft(replacing: range, with: insertion, in: body)
    let updatedTask = tasks(in: mutation.body).first { $0.line == newLine }
    return AgentMutationDraft(
      body: mutation.body,
      patch: mutation.patch,
      updatedTask: updatedTask
    )
  }

  public static func renameTask(
    _ task: AgentParsedTask,
    text: String,
    in body: String,
    maximumBytes: Int = 65_536
  ) throws -> AgentMutationDraft {
    let text = try normalizedTaskText(text, maximumBytes: maximumBytes)
    let task = try currentTask(matching: task, in: body)
    let lineRange = lineRanges(in: body)[task.line - 1]
    let contentOffset = (task.indentation + "○ ").utf16.count
    let range = NSRange(
      location: lineRange.location + contentOffset,
      length: task.text.utf16.count
    )
    let mutation = draft(replacing: range, with: text, in: body)
    let updatedTask = tasks(in: mutation.body).first { $0.line == task.line }

    return AgentMutationDraft(
      body: mutation.body,
      patch: mutation.patch,
      updatedTask: updatedTask
    )
  }

  public static func setTaskState(
    _ task: AgentParsedTask,
    completed: Bool,
    in body: String
  ) throws -> AgentMutationDraft {
    let task = try currentTask(matching: task, in: body)
    let lineRange = lineRanges(in: body)[task.line - 1]
    let range = NSRange(
      location: lineRange.location + task.indentation.utf16.count,
      length: 1
    )
    let mutation = draft(
      replacing: range,
      with: completed ? "●" : "○",
      in: body
    )
    let updatedTask = tasks(in: mutation.body).first { $0.line == task.line }

    return AgentMutationDraft(
      body: mutation.body,
      patch: mutation.patch,
      updatedTask: updatedTask
    )
  }

  public static func removeTask(
    _ task: AgentParsedTask,
    in body: String
  ) throws -> AgentMutationDraft {
    let task = try currentTask(matching: task, in: body)
    let lines = lineRanges(in: body)
    let line = lines[task.line - 1]
    let range: NSRange

    if lines.count == 1 {
      range = line
    } else if task.line < lines.count {
      range = NSRange(
        location: line.location,
        length: lines[task.line].location - line.location
      )
    } else {
      let previousLine = lines[task.line - 2]
      let delimiterStart = NSMaxRange(previousLine)
      range = NSRange(
        location: delimiterStart,
        length: NSMaxRange(line) - delimiterStart
      )
    }

    return draft(replacing: range, with: "", in: body)
  }

  private static func normalize(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }

  private static func validatePayload(
    _ text: String,
    maximumBytes: Int
  ) throws {
    guard text.utf8.count <= maximumBytes else {
      throw AgentWorkspaceError(code: .writeTooLarge)
    }
  }

  private static func normalizedTaskText(
    _ text: String,
    maximumBytes: Int
  ) throws -> String {
    let text = normalize(text)
    try validatePayload(text, maximumBytes: maximumBytes)
    guard !text.contains("\n") else { throw invalidPayload() }
    return text
  }

  private static func currentTask(
    matching expected: AgentParsedTask,
    in body: String
  ) throws -> AgentParsedTask {
    guard let task = tasks(in: body).first(where: { $0 == expected }) else {
      throw invalidPayload()
    }
    return task
  }

  private static func parseTask(
    _ line: String,
    line lineNumber: Int
  ) -> AgentParsedTask? {
    let spaceCount = line.prefix(while: { $0 == " " }).count
    guard spaceCount.isMultiple(of: 4) else { return nil }
    let indentation = String(repeating: " ", count: spaceCount)
    let content = line.dropFirst(spaceCount)
    let completed: Bool
    if content.hasPrefix("○ ") {
      completed = false
    } else if content.hasPrefix("● ") {
      completed = true
    } else {
      return nil
    }

    return AgentParsedTask(
      line: lineNumber,
      indentation: indentation,
      completed: completed,
      text: String(content.dropFirst(2))
    )
  }

  private static func lineRanges(in body: String) -> [NSRange] {
    let source = body as NSString
    guard source.length > 0 else {
      return [NSRange(location: 0, length: 0)]
    }
    var ranges: [NSRange] = []
    var start = 0

    while true {
      var cursor = start
      while
        cursor < source.length,
        source.character(at: cursor) != 10,
        source.character(at: cursor) != 13
      {
        cursor += 1
      }
      if cursor == source.length {
        ranges.append(
          NSRange(location: start, length: source.length - start)
        )
        break
      }
      ranges.append(
        NSRange(location: start, length: cursor - start)
      )
      if
        source.character(at: cursor) == 13,
        cursor + 1 < source.length,
        source.character(at: cursor + 1) == 10
      {
        cursor += 1
      }
      start = cursor + 1
      if start == source.length {
        ranges.append(NSRange(location: start, length: 0))
        break
      }
    }
    return ranges
  }

  private static func draft(
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

  private static func sha256(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func invalidPayload() -> AgentWorkspaceError {
    AgentWorkspaceError(code: .invalidPayload)
  }
}
