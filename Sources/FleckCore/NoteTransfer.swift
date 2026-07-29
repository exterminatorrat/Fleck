import Foundation

public enum NoteExportFormat: String, CaseIterable, Sendable {
  case plainText = "txt"
  case markdown = "md"
  case richText = "rtf"
}

public struct NoteExport: Equatable, Sendable {
  public var suggestedFilename: String
  public var contentType: String
  public var data: Data

  public init(note: Note, format: NoteExportFormat) {
    let basename = Self.safeFilename(note.displayTitle)
    suggestedFilename = "\(basename).\(format.rawValue)"
    switch format {
    case .plainText:
      contentType = "text/plain"
      data = Data(note.body.utf8)
    case .markdown:
      contentType = "text/markdown"
      data = Data(note.body.utf8)
    case .richText:
      contentType = "application/rtf"
      data = note.richTextRTF ?? Data(Self.rtf(note.body).utf8)
    }
  }

  private static func safeFilename(_ value: String) -> String {
    let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
    let cleaned = value.components(separatedBy: forbidden).joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return String((cleaned.isEmpty ? "Untitled" : cleaned).prefix(80))
  }

  private static func rtf(_ value: String) -> String {
    var output = "{\\rtf1\\ansi\\deff0\n"
    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 10: output += "\\par\n"
      case 92, 123, 125: output += "\\\(Character(scalar))"
      case 0...127: output.unicodeScalars.append(scalar)
      default:
        for codeUnit in String(scalar).utf16 {
          let signed = Int16(bitPattern: codeUnit)
          output += "\\u\(signed)?"
        }
      }
    }
    return output + "}"
  }
}

public enum NoteImport {
  public static func note(from data: Data, filename: String, date: Date = Date()) throws -> Note {
    guard let body = String(data: data, encoding: .utf8) else {
      throw ImportError.invalidUTF8
    }
    let title = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    return Note(
      title: title.isEmpty ? "Untitled" : title, body: body, createdAt: date, modifiedAt: date)
  }

  public enum ImportError: Error, Equatable { case invalidUTF8 }
}
