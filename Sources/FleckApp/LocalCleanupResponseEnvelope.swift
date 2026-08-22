import Foundation

struct LocalCleanupResponseEnvelope: Sendable {
  static func extract(
    from data: Data,
    maximumInputBytes: Int,
    maximumOutputCharacters: Int
  ) -> String? {
    guard maximumInputBytes >= 0,
          maximumOutputCharacters >= 0,
          data.count <= maximumInputBytes,
          String(data: data, encoding: .utf8) != nil else { return nil }

    var parser = Parser(bytes: Array(data))
    guard let candidate = parser.parse() else { return nil }
    guard !candidate.isEmpty,
          !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          candidate.count <= maximumOutputCharacters else { return nil }
    return candidate
  }

  private struct Parser {
    let bytes: [UInt8]
    var index = 0

    mutating func parse() -> String? {
      skipWhitespace()
      guard consume(0x7B) else { return nil }
      skipWhitespace()

      var keys = Set<String>()
      var candidate: String?
      while true {
        guard let key = parseString(), keys.insert(key).inserted, key == "text" else {
          return nil
        }
        skipWhitespace()
        guard consume(0x3A) else { return nil }
        skipWhitespace()
        guard let value = parseString() else { return nil }
        candidate = value
        skipWhitespace()

        if consume(0x7D) { break }
        guard consume(0x2C) else { return nil }
        skipWhitespace()
      }

      skipWhitespace()
      guard index == bytes.count, keys.count == 1, keys.contains("text") else {
        return nil
      }
      return candidate
    }

    mutating private func parseString() -> String? {
      guard consume(0x22) else { return nil }
      var result = String()

      while index < bytes.count {
        switch bytes[index] {
        case 0x22:
          index += 1
          return result
        case 0x5C:
          index += 1
          guard index < bytes.count else { return nil }
          switch bytes[index] {
          case 0x22:
            result.append("\"")
            index += 1
          case 0x5C:
            result.append("\\")
            index += 1
          case 0x2F:
            result.append("/")
            index += 1
          case 0x62:
            result.append("\u{8}")
            index += 1
          case 0x66:
            result.append("\u{c}")
            index += 1
          case 0x6E:
            result.append("\n")
            index += 1
          case 0x72:
            result.append("\r")
            index += 1
          case 0x74:
            result.append("\t")
            index += 1
          case 0x75:
            index += 1
            guard let scalar = parseUnicodeScalar() else { return nil }
            result.unicodeScalars.append(scalar)
          default:
            return nil
          }
        case 0x00...0x1F:
          return nil
        default:
          let start = index
          index += 1
          while index < bytes.count, bytes[index] >= 0x80 {
            index += 1
          }
          guard let raw = String(bytes: bytes[start..<index], encoding: .utf8) else {
            return nil
          }
          result.append(contentsOf: raw)
        }
      }
      return nil
    }

    mutating private func parseUnicodeScalar() -> UnicodeScalar? {
      guard let high = readHexQuad() else { return nil }
      if (0xD800...0xDBFF).contains(high) {
        guard index + 1 < bytes.count, bytes[index] == 0x5C, bytes[index + 1] == 0x75 else {
          return nil
        }
        index += 2
        guard let low = readHexQuad(), (0xDC00...0xDFFF).contains(low) else {
          return nil
        }
        let value = 0x10000 + (UInt32(high) - 0xD800) * 0x400
          + (UInt32(low) - 0xDC00)
        return UnicodeScalar(value)
      }
      guard !(0xDC00...0xDFFF).contains(high) else { return nil }
      return UnicodeScalar(UInt32(high))
    }

    mutating private func readHexQuad() -> UInt16? {
      guard index + 4 <= bytes.count else { return nil }
      var value: UInt16 = 0
      for _ in 0..<4 {
        guard let digit = hexValue(bytes[index]) else { return nil }
        value = value * 16 + UInt16(digit)
        index += 1
      }
      return value
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
      switch byte {
      case 0x30...0x39: return byte - 0x30
      case 0x41...0x46: return byte - 0x41 + 10
      case 0x61...0x66: return byte - 0x61 + 10
      default: return nil
      }
    }

    mutating private func consume(_ byte: UInt8) -> Bool {
      guard index < bytes.count, bytes[index] == byte else { return false }
      index += 1
      return true
    }

    mutating private func skipWhitespace() {
      while index < bytes.count {
        switch bytes[index] {
        case 0x20, 0x09, 0x0A, 0x0D:
          index += 1
        default:
          return
        }
      }
    }
  }
}
