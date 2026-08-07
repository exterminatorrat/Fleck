import Foundation

public enum PersonalDictionaryCodecError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidJSON
  case unsupportedSchemaVersion
  case invalidSnapshot
  case malformedCSV
  case invalidHeader
  case invalidRow
  case duplicateEntryID

  public var description: String {
    switch self {
    case .invalidJSON: "invalidJSON"
    case .unsupportedSchemaVersion: "unsupportedSchemaVersion"
    case .invalidSnapshot: "invalidSnapshot"
    case .malformedCSV: "malformedCSV"
    case .invalidHeader: "invalidHeader"
    case .invalidRow: "invalidRow"
    case .duplicateEntryID: "duplicateEntryID"
    }
  }
}

public enum PersonalDictionaryCodec {
  public static let csvHeader = [
    "id",
    "preferredForm",
    "aliases",
    "localeIdentifier",
    "isPriority",
    "isEnabled",
    "origin",
    "useCount",
    "lastUsedAt",
  ]

  public static func encodeJSON(_ snapshot: PersonalDictionarySnapshot) throws -> Data {
    try validate(snapshot)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(sorted(snapshot))
  }

  public static func decodeJSON(_ data: Data) throws -> PersonalDictionarySnapshot {
    guard let object = try? JSONSerialization.jsonObject(with: data) else {
      throw PersonalDictionaryCodecError.invalidJSON
    }
    try validateJSONEnvelope(object)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot: PersonalDictionarySnapshot
    do {
      snapshot = try decoder.decode(PersonalDictionarySnapshot.self, from: data)
    } catch {
      throw PersonalDictionaryCodecError.invalidJSON
    }
    try validate(snapshot)
    return sorted(snapshot)
  }

  public static func encode(_ snapshot: PersonalDictionarySnapshot) throws -> Data {
    try encodeJSON(snapshot)
  }

  public static func decode(_ data: Data) throws -> PersonalDictionarySnapshot {
    try decodeJSON(data)
  }

  public static func exportCSV(_ entries: [PersonalDictionaryEntry]) throws -> String {
    let snapshot = PersonalDictionarySnapshot(entries: entries)
    try validate(snapshot)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let dateFormatter = makeDateFormatter()
    var output = csvHeader.joined(separator: ",") + "\r\n"
    for entry in sorted(snapshot).entries {
      let aliases = String(decoding: try encoder.encode(entry.aliases), as: UTF8.self)
      let fields = [
        entry.id.uuidString.lowercased(),
        entry.preferredForm,
        aliases,
        entry.localeIdentifier,
        entry.isPriority ? "true" : "false",
        entry.isEnabled ? "true" : "false",
        entry.origin.rawValue,
        String(entry.usage.useCount),
        entry.usage.lastUsedAt.map(dateFormatter.string) ?? "",
      ]
      output += fields.map(escapeCSVField).joined(separator: ",") + "\r\n"
    }
    return output
  }

  public static func encodeCSV(_ entries: [PersonalDictionaryEntry]) throws -> String {
    try exportCSV(entries)
  }

  public static func importCSV(_ csv: String) throws -> [PersonalDictionaryEntry] {
    let rows = try parseCSV(csv)
    guard let header = rows.first, header == csvHeader else {
      throw PersonalDictionaryCodecError.invalidHeader
    }
    let dateFormatter = makeDateFormatter()
    var entries: [PersonalDictionaryEntry] = []
    var ids = Set<UUID>()
    for fields in rows.dropFirst() {
      guard fields.count == csvHeader.count,
        let id = UUID(uuidString: fields[0]),
        let isPriority = parseBool(fields[4]),
        let isEnabled = parseBool(fields[5]),
        let origin = PersonalDictionaryOrigin(rawValue: fields[6]),
        let useCount = Int(fields[7])
      else { throw PersonalDictionaryCodecError.invalidRow }
      guard ids.insert(id).inserted else {
        throw PersonalDictionaryCodecError.duplicateEntryID
      }

      let aliases: [String]
      do {
        aliases = try JSONDecoder().decode([String].self, from: Data(fields[2].utf8))
      } catch {
        throw PersonalDictionaryCodecError.invalidRow
      }
      let lastUsedAt: Date?
      if fields[8].isEmpty {
        lastUsedAt = nil
      } else {
        guard let date = dateFormatter.date(from: fields[8]) else {
          throw PersonalDictionaryCodecError.invalidRow
        }
        lastUsedAt = date
      }
      entries.append(
        PersonalDictionaryEntry(
          id: id,
          preferredForm: fields[1],
          aliases: aliases,
          localeIdentifier: fields[3],
          isPriority: isPriority,
          isEnabled: isEnabled,
          origin: origin,
          usage: .init(useCount: useCount, lastUsedAt: lastUsedAt)
        )
      )
    }
    let snapshot = PersonalDictionarySnapshot(entries: entries)
    try validate(snapshot)
    return sorted(snapshot).entries
  }

  public static func decodeCSV(_ csv: String) throws -> [PersonalDictionaryEntry] {
    try importCSV(csv)
  }

  static func sorted(_ snapshot: PersonalDictionarySnapshot) -> PersonalDictionarySnapshot {
    PersonalDictionarySnapshot(
      schemaVersion: snapshot.schemaVersion,
      entries: snapshot.entries.sorted { $0.id.uuidString < $1.id.uuidString },
      suggestions: snapshot.suggestions.sorted { $0.id.uuidString < $1.id.uuidString }
    )
  }

  private static func validate(_ snapshot: PersonalDictionarySnapshot) throws {
    guard snapshot.schemaVersion == PersonalDictionarySnapshot.currentSchemaVersion else {
      throw PersonalDictionaryCodecError.unsupportedSchemaVersion
    }
    guard snapshot.validationIssues.isEmpty else {
      throw PersonalDictionaryCodecError.invalidSnapshot
    }
  }

  private static func validateJSONEnvelope(_ object: Any) throws {
    let rootKeys: Set<String> = ["schemaVersion", "entries", "suggestions"]
    let entryKeys: Set<String> = [
      "id",
      "preferredForm",
      "aliases",
      "localeIdentifier",
      "isPriority",
      "isEnabled",
      "origin",
      "usage",
    ]
    let usageKeysWithoutDate: Set<String> = ["useCount"]
    let usageKeysWithDate: Set<String> = ["useCount", "lastUsedAt"]
    let suggestionKeys: Set<String> = [
      "id",
      "preferredForm",
      "observedForms",
      "localeIdentifier",
      "observationCount",
      "lastObservedAt",
    ]

    guard let root = object as? [String: Any],
      Set(root.keys) == rootKeys,
      let entries = root["entries"] as? [Any],
      let suggestions = root["suggestions"] as? [Any]
    else {
      throw PersonalDictionaryCodecError.invalidJSON
    }

    for value in entries {
      guard let entry = value as? [String: Any],
        Set(entry.keys) == entryKeys,
        let usage = entry["usage"] as? [String: Any]
      else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
      guard Set(usage.keys) == usageKeysWithoutDate
        || Set(usage.keys) == usageKeysWithDate
      else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
    }

    for value in suggestions {
      guard let suggestion = value as? [String: Any],
        Set(suggestion.keys) == suggestionKeys
      else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
    }
  }

  private static func parseBool(_ value: String) -> Bool? {
    switch value {
    case "true": true
    case "false": false
    default: nil
    }
  }

  private static func makeDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  private static func escapeCSVField(_ field: String) -> String {
    guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" })
    else { return field }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  private static func parseCSV(_ csv: String) throws -> [[String]] {
    var rows: [[String]] = []
    var fields: [String] = []
    var field = ""
    var inQuotes = false
    var justClosedQuote = false
    let characters = Array(csv)
    var index = 0

    func finishField() {
      fields.append(field)
      field.removeAll(keepingCapacity: true)
      justClosedQuote = false
    }

    func finishRow() {
      finishField()
      rows.append(fields)
      fields.removeAll(keepingCapacity: true)
    }

    while index < characters.count {
      let character = characters[index]
      if inQuotes {
        if character == "\"" {
          if index + 1 < characters.count, characters[index + 1] == "\"" {
            field.append("\"")
            index += 2
          } else {
            inQuotes = false
            justClosedQuote = true
            index += 1
          }
        } else {
          field.append(character)
          index += 1
        }
        continue
      }

      if justClosedQuote {
        if character == "," {
          finishField()
          index += 1
        } else if character == "\r\n" {
          finishRow()
          index += 1
        } else if character == "\r",
          index + 1 < characters.count,
          characters[index + 1] == "\n"
        {
          finishRow()
          index += 2
        } else if character == "\n" {
          finishRow()
          index += 1
        } else {
          throw PersonalDictionaryCodecError.malformedCSV
        }
        continue
      }

      if character == "\"" {
        guard field.isEmpty else { throw PersonalDictionaryCodecError.malformedCSV }
        inQuotes = true
        index += 1
      } else if character == "," {
        finishField()
        index += 1
      } else if character == "\r\n" {
        finishRow()
        index += 1
      } else if character == "\r" {
        guard index + 1 < characters.count, characters[index + 1] == "\n" else {
          throw PersonalDictionaryCodecError.malformedCSV
        }
        finishRow()
        index += 2
      } else if character == "\n" {
        finishRow()
        index += 1
      } else {
        field.append(character)
        index += 1
      }
    }

    guard !inQuotes else { throw PersonalDictionaryCodecError.malformedCSV }
    if justClosedQuote || !field.isEmpty || !fields.isEmpty {
      finishRow()
    }
    return rows
  }
}
