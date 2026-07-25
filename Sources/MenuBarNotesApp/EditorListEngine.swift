#if os(macOS)
  import Foundation

  enum EditorListFamily: Equatable {
    case bullets
    case numbers
  }

  enum EditorBulletStyle: Equatable {
    case disc
    case circle
    case square
    case dash
  }

  enum EditorNumberStyle: Equatable {
    case decimal
    case alphabetic
    case roman
  }

  enum EditorListStyle: Equatable {
    case bullet(EditorBulletStyle)
    case number(EditorNumberStyle)
    case checklist

    static let bullets = Self.bullet(.disc)
    static let numbers = Self.number(.decimal)
  }

  struct ParsedEditorListLine: Equatable {
    let depth: Int
    let style: EditorListStyle
    let content: String
    let isChecklistComplete: Bool
    let ordinal: Int?
  }

  enum EditorListEngine {
    private static let indentation = "    "

    static func automaticBullet(depth: Int) -> EditorBulletStyle {
      [.disc, .circle, .square][max(0, depth) % 3]
    }

    static func automaticNumber(depth: Int) -> EditorNumberStyle {
      [.decimal, .alphabetic, .roman][max(0, depth) % 3]
    }

    static func parse(_ line: String) -> ParsedEditorListLine? {
      let spaceCount = line.prefix(while: { $0 == " " }).count
      guard spaceCount.isMultiple(of: indentation.count) else { return nil }

      let remainder = line.dropFirst(spaceCount)
      guard let separator = remainder.firstIndex(of: " ") else { return nil }
      let marker = String(remainder[..<separator])
      let content = String(remainder[remainder.index(after: separator)...])
      let depth = spaceCount / indentation.count

      if let bullet = bulletStyle(for: marker) {
        return ParsedEditorListLine(
          depth: depth,
          style: .bullet(bullet),
          content: content,
          isChecklistComplete: false,
          ordinal: nil
        )
      }

      if marker == "○" || marker == "●" {
        return ParsedEditorListLine(
          depth: depth,
          style: .checklist,
          content: content,
          isChecklistComplete: marker == "●",
          ordinal: nil
        )
      }

      guard marker.hasSuffix(".") || marker.hasSuffix(")") else { return nil }
      let token = String(marker.dropLast())
      if let number = Int(token), number > 0 {
        return ParsedEditorListLine(
          depth: depth,
          style: .number(.decimal),
          content: content,
          isChecklistComplete: false,
          ordinal: number
        )
      }
      guard marker.hasSuffix(".") else { return nil }
      if let number = romanValue(token) {
        return ParsedEditorListLine(
          depth: depth,
          style: .number(.roman),
          content: content,
          isChecklistComplete: false,
          ordinal: number
        )
      }
      if let number = alphabeticValue(token) {
        return ParsedEditorListLine(
          depth: depth,
          style: .number(.alphabetic),
          content: content,
          isChecklistComplete: false,
          ordinal: number
        )
      }
      return nil
    }

    static func toggle(style: EditorListStyle, in text: String) -> String {
      let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      let populated = lines.filter { !$0.isEmpty }
      let removesMarkers =
        !populated.isEmpty
        && populated.allSatisfy { parse($0)?.style == style }
      var ordinals: [Int: Int] = [:]

      return lines.map { line in
        guard !line.isEmpty else { return line }
        if let parsed = parse(line) {
          let indent = String(repeating: indentation, count: parsed.depth)
          if removesMarkers { return indent + parsed.content }
          let ordinal = nextOrdinal(for: style, depth: parsed.depth, ordinals: &ordinals)
          return indent + marker(for: style, ordinal: ordinal) + " " + parsed.content
        }

        let spaceCount = line.prefix(while: { $0 == " " }).count
        let depth = spaceCount / indentation.count
        let indent = String(line.prefix(spaceCount))
        let content = String(line.dropFirst(spaceCount))
        let ordinal = nextOrdinal(for: style, depth: depth, ordinals: &ordinals)
        return indent + marker(for: style, ordinal: ordinal) + " " + content
      }.joined(separator: "\n")
    }

    static func continuation(after line: String) -> String? {
      guard let parsed = parse(line), !parsed.content.isEmpty else { return nil }
      let indent = String(repeating: indentation, count: parsed.depth)
      switch parsed.style {
      case .bullet, .checklist:
        return indent + marker(
          for: parsed.style,
          ordinal: parsed.ordinal ?? 1,
          checklistComplete: false
        ) + " "
      case .number:
        return indent + marker(for: parsed.style, ordinal: (parsed.ordinal ?? 0) + 1) + " "
      }
    }

    static func indent(_ text: String, removing: Bool) -> String {
      text.split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .map { indentLine($0, removing: removing) }
        .joined(separator: "\n")
    }

    static func normalizeTypedPrefix(_ prefix: String) -> String? {
      let spaceCount = prefix.prefix(while: { $0 == " " }).count
      let indent = String(prefix.prefix(spaceCount))
      switch String(prefix.dropFirst(spaceCount)) {
      case "- ", "* ", "+ ":
        return indent + "• "
      case "1. ", "1) ":
        return indent + "1. "
      case "[] ", "[ ] ":
        return indent + "○ "
      default:
        return nil
      }
    }

    static func toggleChecklist(_ line: String) -> String {
      guard let parsed = parse(line), parsed.style == .checklist else { return line }
      let indent = String(repeating: indentation, count: parsed.depth)
      return indent + (parsed.isChecklistComplete ? "○ " : "● ") + parsed.content
    }

    private static func indentLine(_ line: String, removing: Bool) -> String {
      guard !line.isEmpty else { return line }
      guard let parsed = parse(line) else {
        if removing {
          return line.hasPrefix(indentation) ? String(line.dropFirst(indentation.count)) : line
        }
        return indentation + line
      }

      let newDepth = removing ? max(0, parsed.depth - 1) : parsed.depth + 1
      guard newDepth != parsed.depth else { return line }
      let style: EditorListStyle
      switch parsed.style {
      case .bullet:
        style = .bullet(automaticBullet(depth: newDepth))
      case .number:
        style = .number(automaticNumber(depth: newDepth))
      case .checklist:
        style = .checklist
      }
      let indent = String(repeating: indentation, count: newDepth)
      return indent
        + marker(
          for: style,
          ordinal: 1,
          checklistComplete: parsed.isChecklistComplete
        )
        + " " + parsed.content
    }

    private static func bulletStyle(for marker: String) -> EditorBulletStyle? {
      switch marker {
      case "•", "-", "*", "+": return .disc
      case "◦": return .circle
      case "▪": return .square
      case "–": return .dash
      default: return nil
      }
    }

    private static func nextOrdinal(
      for style: EditorListStyle,
      depth: Int,
      ordinals: inout [Int: Int]
    ) -> Int {
      guard case .number = style else { return 1 }
      let next = (ordinals[depth] ?? 0) + 1
      ordinals[depth] = next
      return next
    }

    private static func marker(
      for style: EditorListStyle,
      ordinal: Int,
      checklistComplete: Bool = false
    ) -> String {
      switch style {
      case .bullet(.disc): return "•"
      case .bullet(.circle): return "◦"
      case .bullet(.square): return "▪"
      case .bullet(.dash): return "–"
      case .number(.decimal): return "\(ordinal)."
      case .number(.alphabetic): return alphabeticMarker(ordinal) + "."
      case .number(.roman): return romanMarker(ordinal) + "."
      case .checklist: return checklistComplete ? "●" : "○"
      }
    }

    private static func alphabeticMarker(_ value: Int) -> String {
      var value = max(1, value)
      var result = ""
      while value > 0 {
        value -= 1
        let scalar = UnicodeScalar(97 + (value % 26))!
        result.insert(Character(scalar), at: result.startIndex)
        value /= 26
      }
      return result
    }

    private static func alphabeticValue(_ token: String) -> Int? {
      guard (1...2).contains(token.count),
        token.allSatisfy({ $0 >= "a" && $0 <= "z" })
      else { return nil }
      return token.reduce(0) { value, character in
        value * 26 + Int(character.asciiValue! - Character("a").asciiValue!) + 1
      }
    }

    private static func romanMarker(_ value: Int) -> String {
      var remaining = max(1, value)
      var result = ""
      for (number, symbol) in [
        (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"),
        (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
        (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
      ] {
        while remaining >= number {
          result += symbol
          remaining -= number
        }
      }
      return result
    }

    private static func romanValue(_ token: String) -> Int? {
      let values: [Character: Int] = [
        "i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000,
      ]
      guard !token.isEmpty, token.allSatisfy({ values[$0] != nil }) else { return nil }
      var total = 0
      var previous = 0
      for character in token.reversed() {
        let value = values[character]!
        total += value < previous ? -value : value
        previous = value
      }
      return romanMarker(total) == token ? total : nil
    }
  }
#endif
