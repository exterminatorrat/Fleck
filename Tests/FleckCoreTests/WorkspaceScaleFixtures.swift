import Foundation

@testable import FleckCore

enum WorkspaceScaleFixtures {
  static let supportedCounts = [10, 100, 1_000]

  static func notes(count: Int) -> [Note] {
    precondition(supportedCounts.contains(count))

    return (0..<count).map { index in
      let variant = index % 10
      let title: String
      let body: String
      let richTextRTF: Data?

      switch variant {
      case 0:
        title = "Café Fixture \(index)"
        body = "Synthetic fixture café résumé line \(index)\nSecond line • punctuation!"
        richTextRTF = nil
      case 1:
        title = "NAÏVE Fixture \(index)"
        body = "Synthetic fixture naïve façade — data \(index)"
        richTextRTF = nil
      case 2:
        title = "Punctuation / Fixture #\(index)!"
        body = "Synthetic fixture [brackets] {braces} (parentheses); line \(index)."
        richTextRTF = nil
      case 3:
        title = ""
        body = "Untitled Fixture Header \(index)\nSynthetic fixture body line \(index)\nThird line."
        richTextRTF = nil
      case 4, 5:
        title = "Duplicate Fixture"
        body = "Synthetic fixture duplicate body \(index)"
        richTextRTF = nil
      case 6:
        title = "RTF Fixture \(index)"
        body = "Synthetic fixture formatted body \(index)"
        richTextRTF = Data("{\\rtf1\\ansi\\b Synthetic fixture \(index)}".utf8)
      case 7:
        title = "Unicode 東京 Fixture \(index)"
        body = "Synthetic fixture emoji 👩‍💻 \(index)"
        richTextRTF = nil
      case 8:
        title = "Case Fixture \(index)"
        body = "Synthetic fixture CASE token \(index)"
        richTextRTF = nil
      default:
        title = "Multiline Fixture \(index)"
        body = "Synthetic fixture first line \(index)\r\nsecond line\tvalue"
        richTextRTF = nil
      }

      let createdAt = Date(timeIntervalSince1970: 1_800_000_000 + Double(index))
      let modifiedAt = Date(timeIntervalSince1970: 1_800_100_000 + Double(index))
      return Note(
        id: id(for: index),
        title: title,
        body: body,
        richTextRTF: richTextRTF,
        createdAt: createdAt,
        modifiedAt: modifiedAt
      )
    }
  }

  private static func id(for index: Int) -> UUID {
    let value = UInt64(index)
    return UUID(
      uuid: (
        0xF1,
        0xEC,
        0x6B,
        0x00,
        0xA1,
        0x00,
        0x40,
        0x00,
        0x80,
        0x00,
        0x00,
        0x00,
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
        0x00
      )
    )
  }
}
