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
  let acceptedBaseJSON = #"""
    {
      "entries" : [
        {
          "aliases" : [
            "alpha"
          ],
          "id" : "00000000-0000-0000-0000-000000000001",
          "isEnabled" : true,
          "isPriority" : false,
          "localeIdentifier" : "en-US",
          "origin" : "manual",
          "preferredForm" : "Alpha",
          "usage" : {
            "useCount" : 0
          }
        },
        {
          "aliases" : [

          ],
          "id" : "00000000-0000-0000-0000-000000000002",
          "isEnabled" : true,
          "isPriority" : false,
          "localeIdentifier" : "en-US",
          "origin" : "manual",
          "preferredForm" : "zeta",
          "usage" : {
            "useCount" : 0
          }
        }
      ],
      "schemaVersion" : 1,
      "suggestions" : [

      ]
    }
    """#
  #expect(data == Data(acceptedBaseJSON.utf8))
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
  let acceptedBaseCSV =
    "id,preferredForm,aliases,localeIdentifier,isPriority,isEnabled,origin,useCount,lastUsedAt\r\n"
    + "00000000-0000-0000-0000-000000000007,\"Fleck,\nApp\",\"[\"\"fleck, app\"\",\"\"小 明\"\"]\",zh-CN,true,false,suggested,7,2023-11-14T22:13:20.000Z\r\n"
  #expect(csv == acceptedBaseCSV)
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

@Test func personalDictionaryV2CodecEmitsExactCanonicalBytesAcrossInputOrder() throws {
  let laterEntry = PersonalDictionaryEntry(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    preferredForm: "小/明",
    aliases: ["second", "First\nline"],
    localeIdentifier: "zh-CN",
    isPriority: true,
    isEnabled: false,
    origin: .suggested,
    usage: .init(
      useCount: 7,
      lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000.001953125)
    )
  )
  let earlierEntry = dictionaryCodecEntry(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    preferredForm: "Fleck"
  )
  let laterSuggestion = PersonalDictionarySuggestion(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
    preferredForm: "Beta",
    observedForms: ["b", "bee"],
    localeIdentifier: "en-US",
    observationCount: 2,
    lastObservedAt: Date(timeIntervalSince1970: 1_700_000_001)
  )
  let earlierSuggestion = PersonalDictionarySuggestion(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
    preferredForm: "Alpha",
    observedForms: ["A/one"],
    localeIdentifier: "fr-CA",
    observationCount: 1,
    lastObservedAt: Date(timeIntervalSince1970: 1_700_000_002)
  )
  let reversed = PersonalDictionarySnapshotV2(
    revision: 9,
    entries: [laterEntry, earlierEntry],
    suggestions: [laterSuggestion, earlierSuggestion]
  )
  let sorted = PersonalDictionarySnapshotV2(
    revision: 9,
    entries: [earlierEntry, laterEntry],
    suggestions: [earlierSuggestion, laterSuggestion]
  )
  let expected = #"{"entries":[{"aliases":[],"id":"00000000-0000-0000-0000-000000000001","isEnabled":true,"isPriority":false,"localeIdentifier":"en-US","origin":"manual","preferredForm":"Fleck","usage":{"useCount":0}},{"aliases":["second","First\nline"],"id":"00000000-0000-0000-0000-000000000002","isEnabled":false,"isPriority":true,"localeIdentifier":"zh-CN","origin":"suggested","preferredForm":"小/明","usage":{"lastUsedAt":"2023-11-14T22:13:20.001953125Z","useCount":7}}],"revision":9,"schemaVersion":2,"suggestions":[{"id":"00000000-0000-0000-0000-000000000011","lastObservedAt":"2023-11-14T22:13:22.000000000Z","localeIdentifier":"fr-CA","observationCount":1,"observedForms":["A/one"],"preferredForm":"Alpha"},{"id":"00000000-0000-0000-0000-000000000012","lastObservedAt":"2023-11-14T22:13:21.000000000Z","localeIdentifier":"en-US","observationCount":2,"observedForms":["b","bee"],"preferredForm":"Beta"}]}"#

  #expect(try PersonalDictionaryCodec.encodeCanonicalJSON(reversed) == Data(expected.utf8))
  #expect(try PersonalDictionaryCodec.encodeCanonicalJSON(sorted) == Data(expected.utf8))

  let edgeSnapshot = PersonalDictionarySnapshotV2(
    entries: [
      PersonalDictionaryEntry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        preferredForm: "Edge",
        usage: .init(lastUsedAt: Date(timeIntervalSince1970: -0.001953125))
      )
    ],
    suggestions: [
      PersonalDictionarySuggestion(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
        preferredForm: "Edge",
        observedForms: ["edge"],
        observationCount: 1,
        lastObservedAt: Date(timeIntervalSinceReferenceDate: 0.9999999996)
      )
    ]
  )
  let edgeExpected = #"{"entries":[{"aliases":[],"id":"00000000-0000-0000-0000-000000000003","isEnabled":true,"isPriority":false,"localeIdentifier":"en-US","origin":"manual","preferredForm":"Edge","usage":{"lastUsedAt":"1969-12-31T23:59:59.998046875Z","useCount":0}}],"revision":0,"schemaVersion":2,"suggestions":[{"id":"00000000-0000-0000-0000-000000000013","lastObservedAt":"2001-01-01T00:00:01.000000000Z","localeIdentifier":"en-US","observationCount":1,"observedForms":["edge"],"preferredForm":"Edge"}]}"#
  #expect(try PersonalDictionaryCodec.encodeCanonicalJSON(edgeSnapshot) == Data(edgeExpected.utf8))
  #expect(
    try PersonalDictionaryCodec.encodeCanonicalJSON(
      PersonalDictionaryCodec.decodeCandidateJSON(Data(edgeExpected.utf8))
    ) == Data(edgeExpected.utf8)
  )
}

@Test func personalDictionaryV2CodecDecodesCanonicalV1AsRevisionOneCandidate() throws {
  let canonicalV1 = #"""
    {
      "entries" : [
        {
          "aliases" : [
            "FLECK"
          ],
          "id" : "00000000-0000-0000-0000-000000000021",
          "isEnabled" : true,
          "isPriority" : false,
          "localeIdentifier" : "xx-ZZ",
          "origin" : "manual",
          "preferredForm" : "Fleck",
          "usage" : {
            "lastUsedAt" : "2023-11-14T22:13:20Z",
            "useCount" : 3
          }
        }
      ],
      "schemaVersion" : 1,
      "suggestions" : [
        {
          "id" : "00000000-0000-0000-0000-000000000022",
          "lastObservedAt" : "2023-11-14T22:13:21Z",
          "localeIdentifier" : "und-X-private",
          "observationCount" : 2,
          "observedForms" : [
            "fleck",
            "Flek"
          ],
          "preferredForm" : "Fleck"
        }
      ]
    }
    """#

  let candidate = try PersonalDictionaryCodec.decodeCandidateJSON(Data(canonicalV1.utf8))

  #expect(candidate.schemaVersion == 2)
  #expect(candidate.revision == 1)
  #expect(candidate.entries.first?.localeIdentifier == "xx-ZZ")
  #expect(candidate.entries.first?.aliases == ["FLECK"])
  #expect(candidate.suggestions.first?.localeIdentifier == "und-X-private")
  #expect(candidate.suggestions.first?.observedForms == ["fleck", "Flek"])
  #expect(throws: PersonalDictionaryCodecError.invalidJSON) {
    try PersonalDictionaryCodec.decodePublishedJSON(Data(canonicalV1.utf8))
  }
}

@Test func personalDictionaryV2CodecDecodesCanonicalV2WithoutChangingRevision() throws {
  let canonicalV2 = #"{"entries":[{"aliases":["second","First"],"id":"00000000-0000-0000-0000-000000000031","isEnabled":false,"isPriority":true,"localeIdentifier":"en-GB","origin":"suggested","preferredForm":"Fleck","usage":{"lastUsedAt":"2023-11-14T22:13:20.001953125Z","useCount":4}}],"revision":42,"schemaVersion":2,"suggestions":[{"id":"00000000-0000-0000-0000-000000000032","lastObservedAt":"2023-11-14T22:13:21.000000000Z","localeIdentifier":"en-GB","observationCount":2,"observedForms":["second","First"],"preferredForm":"Fleck"}]}"#

  let candidate = try PersonalDictionaryCodec.decodeCandidateJSON(Data(canonicalV2.utf8))

  #expect(candidate.revision == 42)
  #expect(candidate.entries.first?.aliases == ["second", "First"])
  #expect(candidate.suggestions.first?.observedForms == ["second", "First"])
  #expect(try PersonalDictionaryCodec.encodeCanonicalJSON(candidate) == Data(canonicalV2.utf8))
}

@Test func personalDictionaryV2CodecRejectsDuplicateUnknownMissingAndNullFields() {
  let entry = #"{"aliases":[],"id":"00000000-0000-0000-0000-000000000041","isEnabled":true,"isPriority":false,"localeIdentifier":"en-US","origin":"manual","preferredForm":"Fleck","usage":{"useCount":0}}"#
  let suggestion = #"{"id":"00000000-0000-0000-0000-000000000042","lastObservedAt":"2023-11-14T22:13:20.000000000Z","localeIdentifier":"en-US","observationCount":1,"observedForms":["Flek"],"preferredForm":"Fleck"}"#

  let invalidJSON = [
    #"{"entries":[],"revision":0,"schemaVersion":2,"\u0073chemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[],"extra":false,"revision":0,"schemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[],"revision":0,"schemaVersion":2}"#,
    #"{"entries":null,"revision":0,"schemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[\#(entry.dropLast()),"extra":false}],"revision":0,"schemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[\#(entry.replacingOccurrences(of: "\"aliases\":[],", with: ""))],"revision":0,"schemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[\#(entry.replacingOccurrences(of: "\"aliases\":[]", with: "\"aliases\":null"))],"revision":0,"schemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[\#(entry.replacingOccurrences(of: "{\"useCount\":0}", with: "{\"lastUsedAt\":null,\"useCount\":0}"))],"revision":0,"schemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[],"revision":0,"schemaVersion":2,"suggestions":[\#(suggestion.dropLast()),"extra":false}]}"#,
    #"{"entries":[],"revision":0,"schemaVersion":2,"suggestions":[\#(suggestion.replacingOccurrences(of: "\"observedForms\":[\"Flek\"],", with: ""))]}"#,
    #"{"entries":[],"revision":0,"schemaVersion":2,"suggestions":[\#(suggestion.replacingOccurrences(of: "\"observedForms\":[\"Flek\"]", with: "\"observedForms\":null"))]}"#,
  ]

  for json in invalidJSON {
    #expect(throws: PersonalDictionaryCodecError.invalidJSON) {
      try PersonalDictionaryCodec.decodeCandidateJSON(Data(json.utf8))
    }
  }
}

@Test func personalDictionaryV2CodecRejectsInvalidUTF8AndInvalidJSONScalarTypes() {
  let entry = #"{"aliases":[],"id":"00000000-0000-0000-0000-000000000051","isEnabled":true,"isPriority":false,"localeIdentifier":"en-US","origin":"manual","preferredForm":"Fleck","usage":{"useCount":0}}"#
  let suggestion = #"{"id":"00000000-0000-0000-0000-000000000052","lastObservedAt":"2023-11-14T22:13:20.000000000Z","localeIdentifier":"en-US","observationCount":1,"observedForms":["Flek"],"preferredForm":"Fleck"}"#
  let invalidData = [
    Data([0xFF]),
    Data(#"{"entries":[],"revision":0,"schemaVersion":true,"suggestions":[]}"#.utf8),
    Data(#"{"entries":[],"revision":0.0,"schemaVersion":2,"suggestions":[]}"#.utf8),
    Data(#"{"entries":{},"revision":0,"schemaVersion":2,"suggestions":[]}"#.utf8),
    Data(#"{"entries":[\#(entry.replacingOccurrences(of: "\"aliases\":[]", with: "\"aliases\":[true]"))],"revision":0,"schemaVersion":2,"suggestions":[]}"#.utf8),
    Data(#"{"entries":[\#(entry.replacingOccurrences(of: "\"isEnabled\":true", with: "\"isEnabled\":1"))],"revision":0,"schemaVersion":2,"suggestions":[]}"#.utf8),
    Data(#"{"entries":[\#(entry.replacingOccurrences(of: "\"useCount\":0", with: "\"useCount\":false"))],"revision":0,"schemaVersion":2,"suggestions":[]}"#.utf8),
    Data(#"{"entries":[],"revision":0,"schemaVersion":2,"suggestions":[\#(suggestion.replacingOccurrences(of: "\"lastObservedAt\":\"2023-11-14T22:13:20.000000000Z\"", with: "\"lastObservedAt\":0"))]}"#.utf8),
    Data(#"{"entries":[],"revision":0,"schemaVersion":2,"suggestions":[\#(suggestion.replacingOccurrences(of: "\"observationCount\":1", with: "\"observationCount\":1e0"))]}"#.utf8),
    Data(#"{"entries":[],"revision":0,"schemaVersion":2,"suggestions":[\#(suggestion.replacingOccurrences(of: "\"observedForms\":[\"Flek\"]", with: "\"observedForms\":[1]"))]}"#.utf8),
  ]

  for data in invalidData {
    #expect(throws: PersonalDictionaryCodecError.invalidJSON) {
      try PersonalDictionaryCodec.decodeCandidateJSON(data)
    }
  }
}

@Test func personalDictionaryV2CodecRejectsNoncanonicalWhitespaceKeyUUIDDateAndArrayOrder() throws {
  let firstEntry = #"{"aliases":["z","a"],"id":"00000000-0000-0000-0000-00000000006a","isEnabled":true,"isPriority":false,"localeIdentifier":"en-US","origin":"manual","preferredForm":"F/leck","usage":{"lastUsedAt":"2023-11-14T22:13:20.000000000Z","useCount":1}}"#
  let reorderedFirstEntry = #"{"id":"00000000-0000-0000-0000-00000000006a","aliases":["z","a"],"isEnabled":true,"isPriority":false,"localeIdentifier":"en-US","origin":"manual","preferredForm":"F/leck","usage":{"lastUsedAt":"2023-11-14T22:13:20.000000000Z","useCount":1}}"#
  let secondEntry = #"{"aliases":[],"id":"00000000-0000-0000-0000-00000000006b","isEnabled":true,"isPriority":false,"localeIdentifier":"en-US","origin":"manual","preferredForm":"Second","usage":{"useCount":0}}"#
  let firstSuggestion = #"{"id":"00000000-0000-0000-0000-00000000006c","lastObservedAt":"2023-11-14T22:13:21.000000000Z","localeIdentifier":"en-US","observationCount":2,"observedForms":["z","a"],"preferredForm":"Fleck"}"#
  let secondSuggestion = #"{"id":"00000000-0000-0000-0000-00000000006d","lastObservedAt":"2023-11-14T22:13:22.000000000Z","localeIdentifier":"en-US","observationCount":1,"observedForms":["Second"],"preferredForm":"Second"}"#
  let canonical = #"{"entries":[\#(firstEntry),\#(secondEntry)],"revision":0,"schemaVersion":2,"suggestions":[\#(firstSuggestion),\#(secondSuggestion)]}"#

  let candidate = try PersonalDictionaryCodec.decodeCandidateJSON(Data(canonical.utf8))
  #expect(candidate.revision == 0)
  #expect(candidate.entries.first?.aliases == ["z", "a"])
  #expect(candidate.suggestions.first?.observedForms == ["z", "a"])

  let noncanonical = [
    " " + canonical,
    canonical.replacingOccurrences(of: #""entries""#, with: #""\u0065ntries""#),
    #"{"entries":[\#(reorderedFirstEntry),\#(secondEntry)],"revision":0,"schemaVersion":2,"suggestions":[\#(firstSuggestion),\#(secondSuggestion)]}"#,
    canonical.replacingOccurrences(of: "00000000006a", with: "00000000006A"),
    canonical.replacingOccurrences(of: "F/leck", with: #"F\/leck"#),
    canonical.replacingOccurrences(of: "2023-11-14T22:13:20.000000000Z", with: "2023-11-14T22:13:20.000Z"),
    canonical.replacingOccurrences(of: "2023-11-14T22:13:20.000000000Z", with: "2023-02-30T22:13:20.000000000Z"),
    canonical.replacingOccurrences(of: "2023-11-14T22:13:20.000000000Z", with: "2023-11-14T22:13:20.000000001Z"),
    canonical.replacingOccurrences(of: "2023-11-14T22:13:21.000000000Z", with: "2023-11-14T17:13:21.000000000-05:00"),
    #"{"entries":[\#(secondEntry),\#(firstEntry)],"revision":0,"schemaVersion":2,"suggestions":[\#(firstSuggestion),\#(secondSuggestion)]}"#,
    #"{"entries":[\#(firstEntry),\#(secondEntry)],"revision":0,"schemaVersion":2,"suggestions":[\#(secondSuggestion),\#(firstSuggestion)]}"#,
  ]

  for json in noncanonical {
    #expect(throws: PersonalDictionaryCodecError.invalidJSON) {
      try PersonalDictionaryCodec.decodeCandidateJSON(Data(json.utf8))
    }
  }
}

@Test func personalDictionaryV2CodecRejectsInvalidAndFutureSnapshots() throws {
  let id = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
  let validEntry = dictionaryCodecEntry(id: id, preferredForm: "Fleck")

  #expect(throws: PersonalDictionaryCodecError.invalidSnapshot) {
    try PersonalDictionaryCodec.encodeCanonicalJSON(
      PersonalDictionarySnapshotV2(entries: [validEntry, validEntry])
    )
  }
  #expect(throws: PersonalDictionaryCodecError.invalidSnapshot) {
    try PersonalDictionaryCodec.encodeCanonicalJSON(
      PersonalDictionarySnapshotV2(
        entries: [dictionaryCodecEntry(id: id, preferredForm: " ")]
      )
    )
  }
  #expect(throws: PersonalDictionaryCodecError.unsupportedSchemaVersion) {
    try PersonalDictionaryCodec.encodeCanonicalJSON(
      PersonalDictionarySnapshotV2(schemaVersion: 3)
    )
  }

  let infiniteUsage = PersonalDictionaryEntry(
    id: id,
    preferredForm: "Fleck",
    usage: .init(lastUsedAt: Date(timeIntervalSinceReferenceDate: .infinity))
  )
  #expect(throws: PersonalDictionaryCodecError.invalidSnapshot) {
    try PersonalDictionaryCodec.encodeCanonicalJSON(
      PersonalDictionarySnapshotV2(entries: [infiniteUsage])
    )
  }
  let nonfiniteSuggestion = PersonalDictionarySuggestion(
    preferredForm: "Fleck",
    observedForms: ["Flek"],
    observationCount: 1,
    lastObservedAt: Date(timeIntervalSinceReferenceDate: .nan)
  )
  #expect(throws: PersonalDictionaryCodecError.invalidSnapshot) {
    try PersonalDictionaryCodec.encodeCanonicalJSON(
      PersonalDictionarySnapshotV2(suggestions: [nonfiniteSuggestion])
    )
  }

  let entry = #"{"aliases":[],"id":"00000000-0000-0000-0000-000000000071","isEnabled":true,"isPriority":false,"localeIdentifier":"en-US","origin":"manual","preferredForm":"Fleck","usage":{"useCount":0}}"#
  let invalidSnapshots = [
    #"{"entries":[\#(entry),\#(entry)],"revision":0,"schemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[\#(entry.replacingOccurrences(of: "\"preferredForm\":\"Fleck\"", with: "\"preferredForm\":\"\""))],"revision":0,"schemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[\#(entry.replacingOccurrences(of: "\"useCount\":0", with: "\"useCount\":1000001"))],"revision":0,"schemaVersion":2,"suggestions":[]}"#,
  ]
  for json in invalidSnapshots {
    #expect(throws: PersonalDictionaryCodecError.invalidSnapshot) {
      try PersonalDictionaryCodec.decodeCandidateJSON(Data(json.utf8))
    }
  }

  #expect(throws: PersonalDictionaryCodecError.unsupportedSchemaVersion) {
    try PersonalDictionaryCodec.decodeCandidateJSON(
      Data(#"{"entries":[],"revision":0,"schemaVersion":3,"suggestions":[]}"#.utf8)
    )
  }
  for json in [
    #"{"entries":[],"revision":18446744073709551616,"schemaVersion":2,"suggestions":[]}"#,
    #"{"entries":[],"revision":0,"schemaVersion":9223372036854775808,"suggestions":[]}"#,
    #"{"entries":[\#(entry.replacingOccurrences(of: "\"useCount\":0", with: "\"useCount\":9223372036854775808"))],"revision":0,"schemaVersion":2,"suggestions":[]}"#,
  ] {
    #expect(throws: PersonalDictionaryCodecError.invalidJSON) {
      try PersonalDictionaryCodec.decodeCandidateJSON(Data(json.utf8))
    }
  }

  let revisionZero = PersonalDictionarySnapshotV2(entries: [validEntry])
  let revisionZeroData = try PersonalDictionaryCodec.encodeCanonicalJSON(revisionZero)
  #expect(try PersonalDictionaryCodec.decodeCandidateJSON(revisionZeroData).revision == 0)
}

@Test func personalDictionaryV2CodecEnforcesInclusiveSixtyFourKiBByteLimit() throws {
  let emptyPreferredFormJSON = #"{"entries":[{"aliases":[],"id":"00000000-0000-0000-0000-000000000081","isEnabled":true,"isPriority":false,"localeIdentifier":"en-US","origin":"manual","preferredForm":"","usage":{"useCount":0}}],"revision":0,"schemaVersion":2,"suggestions":[]}"#
  #expect(emptyPreferredFormJSON.utf8.count == 243)

  let exactPreferredForm = String(repeating: "x", count: 65_536 - 243)
  let exactJSON = emptyPreferredFormJSON.replacingOccurrences(
    of: #""preferredForm":"""#,
    with: #""preferredForm":"\#(exactPreferredForm)""#
  )
  let exactData = Data(exactJSON.utf8)
  #expect(exactData.count == 65_536)

  let exactCandidate = try PersonalDictionaryCodec.decodeCandidateJSON(exactData)
  #expect(exactCandidate.entries.first?.preferredForm.utf8.count == 65_536 - 243)
  #expect(try PersonalDictionaryCodec.encodeCanonicalJSON(exactCandidate) == exactData)

  var oversizedData = exactData
  oversizedData.append(0x20)
  #expect(oversizedData.count == 65_537)
  #expect(throws: PersonalDictionaryCodecError.jsonByteLimitExceeded) {
    try PersonalDictionaryCodec.decodeCandidateJSON(oversizedData)
  }

  let oversizedSnapshot = PersonalDictionarySnapshotV2(
    entries: [
      dictionaryCodecEntry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
        preferredForm: exactPreferredForm + "x"
      )
    ]
  )
  #expect(throws: PersonalDictionaryCodecError.jsonByteLimitExceeded) {
    try PersonalDictionaryCodec.encodeCanonicalJSON(oversizedSnapshot)
  }
}

@Test func personalDictionaryV2CodecTransferEnvelopeIsCanonicalStrictAndBounded() throws {
  let snapshot = PersonalDictionarySnapshotV2(
    revision: 7,
    entries: [
      dictionaryCodecEntry(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000091")!,
        preferredForm: "Fleck"
      )
    ]
  )
  let compiled = try CompiledPersonalDictionary.compile(snapshot)
  let exportedAt = Date(timeIntervalSince1970: 1_700_000_000)
  let data = try PersonalDictionaryCodec.encodeCanonicalTransfer(
    snapshot: snapshot,
    compiled: compiled,
    exportedAt: exportedAt
  )
  let decoded = try PersonalDictionaryCodec.decodeCanonicalTransfer(data)

  #expect(decoded.snapshot == snapshot)
  #expect(decoded.exportedAt == exportedAt)
  #expect(decoded.contentDigest == compiled.contentDigest)
  #expect(decoded.byteCount == (try PersonalDictionaryCodec.encodeCanonicalJSON(snapshot)).count)
  #expect(try PersonalDictionaryCodec.encodeCanonicalTransfer(decoded) == data)

  let string = try #require(String(data: data, encoding: .utf8))
  #expect(
    string.hasPrefix(
      "{\"byteCount\":\(decoded.byteCount),\"compilerPolicyRevision\":1,\"contentDigest\":"
    )
  )
  #expect(string.contains("\"localeIdentifier\":\"en-US\",\"snapshot\":{\"entries\":"))
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
