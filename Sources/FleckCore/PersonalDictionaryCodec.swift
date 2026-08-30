import Foundation

public enum PersonalDictionaryCodecError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidJSON
  case jsonByteLimitExceeded
  case unsupportedSchemaVersion
  case invalidSnapshot
  case malformedCSV
  case invalidHeader
  case invalidRow
  case duplicateEntryID

  public var description: String {
    switch self {
    case .invalidJSON: "invalidJSON"
    case .jsonByteLimitExceeded: "jsonByteLimitExceeded"
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
  private static let jsonByteLimit = 64 * 1024

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

  public static func encodeCanonicalJSON(
    _ snapshot: PersonalDictionarySnapshotV2
  ) throws -> Data {
    guard snapshot.schemaVersion == PersonalDictionarySnapshotV2.currentSchemaVersion else {
      throw PersonalDictionaryCodecError.unsupportedSchemaVersion
    }
    guard snapshot.validationIssues.isEmpty else {
      throw PersonalDictionaryCodecError.invalidSnapshot
    }

    let entries = snapshot.entries.sorted { canonicalUUID($0.id) < canonicalUUID($1.id) }
    let suggestions = snapshot.suggestions.sorted { canonicalUUID($0.id) < canonicalUUID($1.id) }
    var json = "{\"entries\":["
    for (index, entry) in entries.enumerated() {
      if index > 0 { json += "," }
      json += try canonicalEntryJSON(entry)
    }
    json += "],\"revision\":\(snapshot.revision),\"schemaVersion\":2,\"suggestions\":["
    for (index, suggestion) in suggestions.enumerated() {
      if index > 0 { json += "," }
      json += try canonicalSuggestionJSON(suggestion)
    }
    json += "]}"

    let data = Data(json.utf8)
    guard data.count <= jsonByteLimit else {
      throw PersonalDictionaryCodecError.jsonByteLimitExceeded
    }
    return data
  }

  public static func decodeCandidateJSON(
    _ data: Data
  ) throws -> PersonalDictionarySnapshotV2 {
    guard data.count <= jsonByteLimit else {
      throw PersonalDictionaryCodecError.jsonByteLimitExceeded
    }

    let root: StrictJSONValue
    do {
      var parser = try StrictJSONParser(data: data)
      root = try parser.parse()
    } catch {
      throw PersonalDictionaryCodecError.invalidJSON
    }
    guard case .object(let fields) = root,
      case .number(let schemaToken)? = fields["schemaVersion"],
      let schemaVersion = strictInteger(schemaToken)
    else {
      throw PersonalDictionaryCodecError.invalidJSON
    }

    switch schemaVersion {
    case PersonalDictionarySnapshot.currentSchemaVersion:
      let snapshot = try decodeJSON(data)
      guard try encodeJSON(snapshot) == data else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
      do {
        return try PersonalDictionarySnapshotV2.migrationCandidate(fromV1: snapshot)
      } catch {
        throw PersonalDictionaryCodecError.invalidSnapshot
      }
    case PersonalDictionarySnapshotV2.currentSchemaVersion:
      let snapshot = try decodeSnapshotV2(root)
      guard try encodeCanonicalJSON(snapshot) == data else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
      return snapshot
    default:
      throw PersonalDictionaryCodecError.unsupportedSchemaVersion
    }
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

  private static func decodeSnapshotV2(
    _ value: StrictJSONValue
  ) throws -> PersonalDictionarySnapshotV2 {
    guard case .object(let fields) = value,
      Set(fields.keys) == ["entries", "revision", "schemaVersion", "suggestions"],
      let revisionValue = fields["revision"],
      let revision = strictUInt64(revisionValue),
      case .array(let entryValues)? = fields["entries"],
      case .array(let suggestionValues)? = fields["suggestions"]
    else {
      throw PersonalDictionaryCodecError.invalidJSON
    }

    let snapshot = PersonalDictionarySnapshotV2(
      revision: revision,
      entries: try entryValues.map(decodeEntryV2),
      suggestions: try suggestionValues.map(decodeSuggestionV2)
    )
    guard snapshot.validationIssues.isEmpty else {
      throw PersonalDictionaryCodecError.invalidSnapshot
    }
    return snapshot
  }

  private static func decodeEntryV2(_ value: StrictJSONValue) throws -> PersonalDictionaryEntry {
    guard case .object(let fields) = value,
      Set(fields.keys) == [
        "aliases", "id", "isEnabled", "isPriority", "localeIdentifier", "origin",
        "preferredForm", "usage",
      ],
      let aliasesValue = fields["aliases"],
      let aliases = strictStringArray(aliasesValue),
      let idValue = fields["id"],
      let id = strictUUID(idValue),
      case .bool(let isEnabled)? = fields["isEnabled"],
      case .bool(let isPriority)? = fields["isPriority"],
      case .string(let localeIdentifier)? = fields["localeIdentifier"],
      case .string(let originValue)? = fields["origin"],
      let origin = PersonalDictionaryOrigin(rawValue: originValue),
      case .string(let preferredForm)? = fields["preferredForm"],
      let usageValue = fields["usage"]
    else {
      throw PersonalDictionaryCodecError.invalidJSON
    }

    return PersonalDictionaryEntry(
      id: id,
      preferredForm: preferredForm,
      aliases: aliases,
      localeIdentifier: localeIdentifier,
      isPriority: isPriority,
      isEnabled: isEnabled,
      origin: origin,
      usage: try decodeUsageV2(usageValue)
    )
  }

  private static func decodeUsageV2(_ value: StrictJSONValue) throws -> PersonalDictionaryUsage {
    guard case .object(let fields) = value,
      Set(fields.keys) == ["useCount"] || Set(fields.keys) == ["lastUsedAt", "useCount"],
      let useCountValue = fields["useCount"],
      let useCount = strictInt(useCountValue)
    else {
      throw PersonalDictionaryCodecError.invalidJSON
    }

    let lastUsedAt: Date?
    if let dateValue = fields["lastUsedAt"] {
      guard let date = strictDate(dateValue) else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
      lastUsedAt = date
    } else {
      lastUsedAt = nil
    }
    return PersonalDictionaryUsage(useCount: useCount, lastUsedAt: lastUsedAt)
  }

  private static func decodeSuggestionV2(
    _ value: StrictJSONValue
  ) throws -> PersonalDictionarySuggestion {
    guard case .object(let fields) = value,
      Set(fields.keys) == [
        "id", "lastObservedAt", "localeIdentifier", "observationCount", "observedForms",
        "preferredForm",
      ],
      let idValue = fields["id"],
      let id = strictUUID(idValue),
      let dateValue = fields["lastObservedAt"],
      let lastObservedAt = strictDate(dateValue),
      case .string(let localeIdentifier)? = fields["localeIdentifier"],
      let countValue = fields["observationCount"],
      let observationCount = strictInt(countValue),
      let observedFormsValue = fields["observedForms"],
      let observedForms = strictStringArray(observedFormsValue),
      case .string(let preferredForm)? = fields["preferredForm"]
    else {
      throw PersonalDictionaryCodecError.invalidJSON
    }

    return PersonalDictionarySuggestion(
      id: id,
      preferredForm: preferredForm,
      observedForms: observedForms,
      localeIdentifier: localeIdentifier,
      observationCount: observationCount,
      lastObservedAt: lastObservedAt
    )
  }

  private static func strictStringArray(_ value: StrictJSONValue) -> [String]? {
    guard case .array(let values) = value else { return nil }
    var strings: [String] = []
    strings.reserveCapacity(values.count)
    for value in values {
      guard case .string(let string) = value else { return nil }
      strings.append(string)
    }
    return strings
  }

  private static func strictUUID(_ value: StrictJSONValue) -> UUID? {
    guard case .string(let string) = value,
      let id = UUID(uuidString: string),
      canonicalUUID(id) == string
    else { return nil }
    return id
  }

  private static func strictDate(_ value: StrictJSONValue) -> Date? {
    guard case .string(let string) = value else { return nil }
    let bytes = Array(string.utf8)
    guard bytes.count == 30,
      bytes[4] == 0x2D, bytes[7] == 0x2D, bytes[10] == 0x54,
      bytes[13] == 0x3A, bytes[16] == 0x3A, bytes[19] == 0x2E, bytes[29] == 0x5A,
      let year = parseDecimal(bytes, in: 0..<4),
      let month = parseDecimal(bytes, in: 5..<7),
      let day = parseDecimal(bytes, in: 8..<10),
      let hour = parseDecimal(bytes, in: 11..<13),
      let minute = parseDecimal(bytes, in: 14..<16),
      let second = parseDecimal(bytes, in: 17..<19),
      let nanosecond = parseDecimal(bytes, in: 20..<29),
      (1...9999).contains(year),
      (1...12).contains(month),
      (1...31).contains(day),
      (0...23).contains(hour),
      (0...59).contains(minute),
      (0...59).contains(second)
    else { return nil }

    let calendar = utcGregorianCalendar()
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    guard let wholeSecondDate = calendar.date(from: components) else { return nil }
    let verified = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: wholeSecondDate
    )
    guard verified.year == year, verified.month == month, verified.day == day,
      verified.hour == hour, verified.minute == minute, verified.second == second
    else { return nil }

    let interval = wholeSecondDate.timeIntervalSinceReferenceDate
      + Double(nanosecond) / 1_000_000_000
    let date = Date(timeIntervalSinceReferenceDate: interval)
    guard let canonical = try? canonicalDateString(date), canonical == string else { return nil }
    return date
  }

  private static func parseDecimal(_ bytes: [UInt8], in range: Range<Int>) -> Int? {
    var value = 0
    for index in range {
      let byte = bytes[index]
      guard (0x30...0x39).contains(byte) else { return nil }
      value = value * 10 + Int(byte - 0x30)
    }
    return value
  }

  private static func strictInt(_ value: StrictJSONValue) -> Int? {
    guard case .number(let token) = value,
      let result = Int(token),
      token == String(result)
    else { return nil }
    return result
  }

  private static func strictUInt64(_ value: StrictJSONValue) -> UInt64? {
    guard case .number(let token) = value,
      let result = UInt64(token),
      token == String(result)
    else { return nil }
    return result
  }

  private static func canonicalEntryJSON(_ entry: PersonalDictionaryEntry) throws -> String {
    var json = "{\"aliases\":\(canonicalStringArrayJSON(entry.aliases))"
    json += ",\"id\":\(canonicalStringJSON(canonicalUUID(entry.id)))"
    json += ",\"isEnabled\":\(entry.isEnabled ? "true" : "false")"
    json += ",\"isPriority\":\(entry.isPriority ? "true" : "false")"
    json += ",\"localeIdentifier\":\(canonicalStringJSON(entry.localeIdentifier))"
    json += ",\"origin\":\(canonicalStringJSON(entry.origin.rawValue))"
    json += ",\"preferredForm\":\(canonicalStringJSON(entry.preferredForm))"
    json += ",\"usage\":{"
    if let lastUsedAt = entry.usage.lastUsedAt {
      json += "\"lastUsedAt\":\(canonicalStringJSON(try canonicalDateString(lastUsedAt))),"
    }
    json += "\"useCount\":\(entry.usage.useCount)}}"
    return json
  }

  private static func canonicalSuggestionJSON(
    _ suggestion: PersonalDictionarySuggestion
  ) throws -> String {
    var json = "{\"id\":\(canonicalStringJSON(canonicalUUID(suggestion.id)))"
    json += ",\"lastObservedAt\":\(canonicalStringJSON(try canonicalDateString(suggestion.lastObservedAt)))"
    json += ",\"localeIdentifier\":\(canonicalStringJSON(suggestion.localeIdentifier))"
    json += ",\"observationCount\":\(suggestion.observationCount)"
    json += ",\"observedForms\":\(canonicalStringArrayJSON(suggestion.observedForms))"
    json += ",\"preferredForm\":\(canonicalStringJSON(suggestion.preferredForm))}"
    return json
  }

  private static func canonicalStringArrayJSON(_ values: [String]) -> String {
    "[" + values.map(canonicalStringJSON).joined(separator: ",") + "]"
  }

  private static func canonicalStringJSON(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 0x08: result += "\\b"
      case 0x09: result += "\\t"
      case 0x0A: result += "\\n"
      case 0x0C: result += "\\f"
      case 0x0D: result += "\\r"
      case 0x22: result += "\\\""
      case 0x5C: result += "\\\\"
      case 0..<0x20: result += String(format: "\\u%04x", scalar.value)
      default: result.unicodeScalars.append(scalar)
      }
    }
    result += "\""
    return result
  }

  private static func canonicalUUID(_ id: UUID) -> String {
    id.uuidString.lowercased()
  }

  private static func canonicalDateString(_ date: Date) throws -> String {
    let interval = date.timeIntervalSinceReferenceDate
    guard interval.isFinite else {
      throw PersonalDictionaryCodecError.invalidSnapshot
    }

    let flooredSeconds = interval.rounded(.down)
    guard var wholeSeconds = Int64(exactly: flooredSeconds),
      var nanoseconds = Int64(exactly: ((interval - flooredSeconds) * 1_000_000_000).rounded()),
      (0...1_000_000_000).contains(nanoseconds)
    else {
      throw PersonalDictionaryCodecError.invalidSnapshot
    }
    if nanoseconds == 1_000_000_000 {
      let result = wholeSeconds.addingReportingOverflow(1)
      guard !result.overflow else { throw PersonalDictionaryCodecError.invalidSnapshot }
      wholeSeconds = result.partialValue
      nanoseconds = 0
    }

    let calendar = utcGregorianCalendar()
    let wholeSecondDate = Date(timeIntervalSinceReferenceDate: Double(wholeSeconds))
    let components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: wholeSecondDate
    )
    guard let year = components.year, (1...9999).contains(year),
      let month = components.month, let day = components.day,
      let hour = components.hour, let minute = components.minute, let second = components.second
    else {
      throw PersonalDictionaryCodecError.invalidSnapshot
    }
    return "\(paddedDecimal(year, width: 4))-\(paddedDecimal(month, width: 2))"
      + "-\(paddedDecimal(day, width: 2))T\(paddedDecimal(hour, width: 2))"
      + ":\(paddedDecimal(minute, width: 2)):\(paddedDecimal(second, width: 2))"
      + ".\(paddedDecimal(Int(nanoseconds), width: 9))Z"
  }

  private static func utcGregorianCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private static func paddedDecimal(_ value: Int, width: Int) -> String {
    let decimal = String(value)
    return String(repeating: "0", count: width - decimal.count) + decimal
  }

  private static func strictInteger(_ token: String) -> Int? {
    guard let value = Int(token), token == String(value) else { return nil }
    return value
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

private enum StrictJSONValue {
  case object([String: StrictJSONValue])
  case array([StrictJSONValue])
  case string(String)
  case number(String)
  case bool(Bool)
  case null
}

private struct StrictJSONParser {
  private let scalars: [Unicode.Scalar]
  private var index = 0

  init(data: Data) throws {
    guard let text = String(data: data, encoding: .utf8) else {
      throw PersonalDictionaryCodecError.invalidJSON
    }
    scalars = Array(text.unicodeScalars)
  }

  mutating func parse() throws -> StrictJSONValue {
    skipWhitespace()
    let value = try parseValue(depth: 0)
    skipWhitespace()
    guard index == scalars.count else { throw PersonalDictionaryCodecError.invalidJSON }
    return value
  }

  private mutating func parseValue(depth: Int) throws -> StrictJSONValue {
    guard let scalar = current else { throw PersonalDictionaryCodecError.invalidJSON }
    switch scalar {
    case "{": return try parseObject(depth: depth)
    case "[": return try parseArray(depth: depth)
    case "\"": return .string(try parseString())
    case "t": try consume("true"); return .bool(true)
    case "f": try consume("false"); return .bool(false)
    case "n": try consume("null"); return .null
    case "-", "0"..."9": return .number(try parseNumber())
    default: throw PersonalDictionaryCodecError.invalidJSON
    }
  }

  private mutating func parseObject(depth: Int) throws -> StrictJSONValue {
    guard depth < 32 else { throw PersonalDictionaryCodecError.invalidJSON }
    try consume("{")
    skipWhitespace()
    if consumeIf("}") { return .object([:]) }

    var fields: [String: StrictJSONValue] = [:]
    while true {
      guard current == "\"" else { throw PersonalDictionaryCodecError.invalidJSON }
      let key = try parseString()
      guard fields[key] == nil else { throw PersonalDictionaryCodecError.invalidJSON }
      skipWhitespace()
      try consume(":")
      skipWhitespace()
      fields[key] = try parseValue(depth: depth + 1)
      skipWhitespace()
      if consumeIf("}") { return .object(fields) }
      try consume(",")
      skipWhitespace()
    }
  }

  private mutating func parseArray(depth: Int) throws -> StrictJSONValue {
    guard depth < 32 else { throw PersonalDictionaryCodecError.invalidJSON }
    try consume("[")
    skipWhitespace()
    if consumeIf("]") { return .array([]) }

    var values: [StrictJSONValue] = []
    while true {
      values.append(try parseValue(depth: depth + 1))
      skipWhitespace()
      if consumeIf("]") { return .array(values) }
      try consume(",")
      skipWhitespace()
    }
  }

  private mutating func parseString() throws -> String {
    try consume("\"")
    var result = ""
    while let scalar = current {
      index += 1
      if scalar == "\"" { return result }
      if scalar == "\\" {
        guard let escape = current else { throw PersonalDictionaryCodecError.invalidJSON }
        index += 1
        switch escape {
        case "\"": result += "\""
        case "\\": result += "\\"
        case "/": result += "/"
        case "b": result += "\u{08}"
        case "f": result += "\u{0C}"
        case "n": result += "\n"
        case "r": result += "\r"
        case "t": result += "\t"
        case "u":
          let first = try parseHexQuad()
          let value: UInt32
          if (0xD800...0xDBFF).contains(first) {
            try consume("\\u")
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else {
              throw PersonalDictionaryCodecError.invalidJSON
            }
            value = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
          } else {
            guard !(0xDC00...0xDFFF).contains(first) else {
              throw PersonalDictionaryCodecError.invalidJSON
            }
            value = first
          }
          guard let decoded = Unicode.Scalar(value) else {
            throw PersonalDictionaryCodecError.invalidJSON
          }
          result.unicodeScalars.append(decoded)
        default: throw PersonalDictionaryCodecError.invalidJSON
        }
      } else {
        guard scalar.value >= 0x20 else { throw PersonalDictionaryCodecError.invalidJSON }
        result.unicodeScalars.append(scalar)
      }
    }
    throw PersonalDictionaryCodecError.invalidJSON
  }

  private mutating func parseHexQuad() throws -> UInt32 {
    var value: UInt32 = 0
    for _ in 0..<4 {
      guard let scalar = current, let digit = hexDigit(scalar) else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
      value = value * 16 + digit
      index += 1
    }
    return value
  }

  private func hexDigit(_ scalar: Unicode.Scalar) -> UInt32? {
    switch scalar.value {
    case 0x30...0x39: scalar.value - 0x30
    case 0x41...0x46: scalar.value - 0x41 + 10
    case 0x61...0x66: scalar.value - 0x61 + 10
    default: nil
    }
  }

  private mutating func parseNumber() throws -> String {
    let start = index
    _ = consumeIf("-")
    guard let scalar = current else { throw PersonalDictionaryCodecError.invalidJSON }
    if scalar == "0" {
      index += 1
      if let next = current, ("0"..."9").contains(next) {
        throw PersonalDictionaryCodecError.invalidJSON
      }
    } else {
      guard ("1"..."9").contains(scalar) else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
      repeat { index += 1 } while current.map { ("0"..."9").contains($0) } == true
    }
    if consumeIf(".") {
      guard current.map({ ("0"..."9").contains($0) }) == true else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
      repeat { index += 1 } while current.map { ("0"..."9").contains($0) } == true
    }
    if current == "e" || current == "E" {
      index += 1
      if current == "+" || current == "-" { index += 1 }
      guard current.map({ ("0"..."9").contains($0) }) == true else {
        throw PersonalDictionaryCodecError.invalidJSON
      }
      repeat { index += 1 } while current.map { ("0"..."9").contains($0) } == true
    }
    return String(String.UnicodeScalarView(scalars[start..<index]))
  }

  private mutating func skipWhitespace() {
    while let scalar = current, scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
      index += 1
    }
  }

  private mutating func consume(_ literal: String) throws {
    for scalar in literal.unicodeScalars {
      guard current == scalar else { throw PersonalDictionaryCodecError.invalidJSON }
      index += 1
    }
  }

  private mutating func consumeIf(_ scalar: Unicode.Scalar) -> Bool {
    guard current == scalar else { return false }
    index += 1
    return true
  }

  private var current: Unicode.Scalar? {
    index < scalars.count ? scalars[index] : nil
  }
}
