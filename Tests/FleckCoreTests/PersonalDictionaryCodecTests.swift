import Foundation
import Testing

@testable import FleckCore

@Test func personalDictionaryJSONRoundTripIsStrictAndStable() throws {
  let second = dictionaryCodecEntry(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    preferredForm: "zeta"
  )
  let first = dictionaryCodecEntry(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    preferredForm: "Alpha",
    aliases: ["alpha"]
  )
  let snapshot = PersonalDictionarySnapshot(entries: [second, first])

  let data = try PersonalDictionaryCodec.encodeJSON(snapshot)
  #expect(data == (try PersonalDictionaryCodec.encodeJSON(snapshot)))
  #expect(try PersonalDictionaryCodec.decodeJSON(data).entries.map(\.id) == [first.id, second.id])

  let extraField = Data(
    "{\"entries\":[],\"schemaVersion\":1,\"suggestions\":[],\"extra\":true}".utf8
  )
  #expect(throws: PersonalDictionaryCodecError.invalidJSON) {
    try PersonalDictionaryCodec.decodeJSON(extraField)
  }
}

@Test func personalDictionaryJSONRejectsUnknownNestedKeys() throws {
  let entryID = "00000000-0000-0000-0000-000000000011"
  let suggestionID = "00000000-0000-0000-0000-000000000012"
  let entry = "\"id\":\"\(entryID)\",\"preferredForm\":\"Fleck\",\"aliases\":[],\"localeIdentifier\":\"en-US\",\"isPriority\":false,\"isEnabled\":true,\"origin\":\"manual\",\"usage\":{\"useCount\":0}"
  let suggestion = "\"id\":\"\(suggestionID)\",\"preferredForm\":\"Fleck\",\"observedForms\":[],\"localeIdentifier\":\"en-US\",\"observationCount\":0,\"lastObservedAt\":\"2023-11-14T22:13:20Z\""

  let unknownEntryKey = Data(
    "{\"schemaVersion\":1,\"entries\":[{\(entry),\"unexpected\":true}],\"suggestions\":[]}".utf8
  )
  let unknownUsageKey = Data(
    "{\"schemaVersion\":1,\"entries\":[{\(entry.replacingOccurrences(of: "\"usage\":{\"useCount\":0}", with: "\"usage\":{\"useCount\":0,\"unexpected\":true}"))}],\"suggestions\":[]}".utf8
  )
  let unknownSuggestionKey = Data(
    "{\"schemaVersion\":1,\"entries\":[],\"suggestions\":[{\(suggestion),\"unexpected\":true}]}".utf8
  )

  for data in [unknownEntryKey, unknownUsageKey, unknownSuggestionKey] {
    #expect(throws: PersonalDictionaryCodecError.invalidJSON) {
      try PersonalDictionaryCodec.decodeJSON(data)
    }
  }
}

@Test func personalDictionaryCSVPreservesQuotedMultilineAndMultilingualFields() throws {
  let entry = PersonalDictionaryEntry(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
    preferredForm: "Fleck,\nApp",
    aliases: ["fleck, app", "小 明"],
    localeIdentifier: "zh-CN",
    isPriority: true,
    isEnabled: false,
    origin: .suggested,
    usage: .init(
      useCount: 7,
      lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  )

  let csv = try PersonalDictionaryCodec.exportCSV([entry])
  #expect(csv.hasPrefix("id,preferredForm,aliases,localeIdentifier,isPriority,isEnabled,origin,useCount,lastUsedAt\r\n"))
  #expect(try PersonalDictionaryCodec.importCSV(csv) == [entry])
}

@Test func personalDictionaryCSVRejectsMalformedRowsHeadersAndDuplicateIDs() throws {
  let header = "id,preferredForm,aliases,localeIdentifier,isPriority,isEnabled,origin,useCount,lastUsedAt\r\n"
  #expect(throws: PersonalDictionaryCodecError.malformedCSV) {
    try PersonalDictionaryCodec.importCSV(header + "\"unterminated")
  }
  #expect(throws: PersonalDictionaryCodecError.invalidHeader) {
    try PersonalDictionaryCodec.importCSV("id,preferredForm\r\n")
  }

  let id = "00000000-0000-0000-0000-000000000008"
  let row = "\(id),Fleck,[],en-US,true,true,manual,0,"
  #expect(throws: PersonalDictionaryCodecError.duplicateEntryID) {
    try PersonalDictionaryCodec.importCSV(header + row + "\r\n" + row + "\r\n")
  }
}

private func dictionaryCodecEntry(
  id: UUID,
  preferredForm: String,
  aliases: [String] = []
) -> PersonalDictionaryEntry {
  PersonalDictionaryEntry(
    id: id,
    preferredForm: preferredForm,
    aliases: aliases,
    localeIdentifier: "en-US",
    isPriority: false,
    isEnabled: true,
    origin: .manual,
    usage: .init()
  )
}
