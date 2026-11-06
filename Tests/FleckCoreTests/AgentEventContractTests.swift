import Foundation
import Testing

@testable import FleckCore

struct AgentEventContractTests {
  @Test func catalogIsOrderedStrictAndWithinItsByteBudget() throws {
    let expectedNames = [
      "note.created",
      "note.updated",
      "task.state_changed",
    ]
    #expect(AgentEventCatalog.events.map(\.name.rawValue) == expectedNames)

    let first = try AgentEventCatalog.serializedData()
    let second = try AgentEventCatalog.serializedData()
    #expect(first == second)
    #expect(first.count <= 4_096)

    for descriptor in AgentEventCatalog.events {
      #expect(descriptor.inputSchema.additionalProperties == false)
      #expect(
        Set(descriptor.inputSchema.properties?.keys.map { $0 } ?? []) == ["note_id", "folder_id"])
      #expect(descriptor.inputSchema.oneOf?.count == 2)
      #expect(descriptor.payloadSchema.additionalProperties == false)
      #expect(descriptor.inputSchema.oneOf?.compactMap(\.required) == [["note_id"], ["folder_id"]])
      let expectedPayloadKeys: Set<String> =
        switch descriptor.name {
        case .noteCreated: ["note_id", "revision", "origin"]
        case .noteUpdated: ["note_id", "revision", "origin", "changed_fields"]
        case .taskStateChanged: ["note_id", "revision", "origin", "completion_transition"]
        }
      #expect(
        Set(descriptor.payloadSchema.properties?.keys.map { $0 } ?? []) == expectedPayloadKeys)
      #expect(Set(descriptor.payloadSchema.required ?? []) == expectedPayloadKeys)
      let followUp = descriptor.name == .taskStateChanged ? "list_tasks" : "read_note"
      #expect(descriptor.description.contains(followUp))
    }
  }

  @Test func scopeRequiresExactlyOneCanonicalUUID() throws {
    let noteID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let noteJSON = Data(#"{"note_id":"00000000-0000-4000-8000-000000000001"}"#.utf8)
    #expect(try JSONDecoder().decode(AgentEventScope.self, from: noteJSON) == .note(noteID: noteID))

    let folderAndNoteJSON = Data(
      #"{"note_id":"00000000-0000-4000-8000-000000000001","folder_id":"00000000-0000-4000-8000-000000000002"}"#
        .utf8
    )
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(AgentEventScope.self, from: folderAndNoteJSON)
    }

    let extraKeyJSON = Data(
      #"{"note_id":"00000000-0000-4000-8000-000000000001","all":true}"#.utf8
    )
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(AgentEventScope.self, from: extraKeyJSON)
    }

    let nonCanonicalUUIDJSON = Data(#"{"note_id":"{00000000-0000-4000-8000-000000000001}"}"#.utf8)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(AgentEventScope.self, from: nonCanonicalUUIDJSON)
    }
  }

  @Test func eventEnvelopesAreMetadataOnlyStrictAndCompact() throws {
    let noteID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let events = [
      try AgentEventEnvelope(
        eventID: String(repeating: "a", count: 64),
        name: .noteCreated,
        timestamp: "2026-09-30T12:00:00Z",
        data: .noteCreated(noteID: noteID, revision: 7, origin: .local),
        cursor: nil
      ),
      try AgentEventEnvelope(
        eventID: String(repeating: "b", count: 64),
        name: .noteUpdated,
        timestamp: "2026-09-30T12:00:00Z",
        data: .noteUpdated(
          noteID: noteID,
          revision: 7,
          changedFields: [.body, .title],
          origin: .local
        ),
        cursor: nil
      ),
      try AgentEventEnvelope(
        eventID: String(repeating: "c", count: 64),
        name: .taskStateChanged,
        timestamp: "2026-09-30T12:00:00Z",
        data: .taskStateChanged(
          noteID: noteID,
          revision: 7,
          transition: .incompleteToComplete,
          origin: .local
        ),
        cursor: nil
      ),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    for event in events {
      let bytes = try encoder.encode(event)
      #expect(bytes.count < 1_024)
      #expect(try JSONDecoder().decode(AgentEventEnvelope.self, from: bytes) == event)
      let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
      #expect(Set(object.keys) == ["cursor", "data", "eventId", "name", "timestamp"])
      let data = try #require(object["data"] as? [String: Any])
      let expectedDataKeys: Set<String> =
        switch event.name {
        case .noteCreated: ["note_id", "revision", "origin"]
        case .noteUpdated: ["note_id", "revision", "origin", "changed_fields"]
        case .taskStateChanged: ["note_id", "revision", "origin", "completion_transition"]
        }
      #expect(Set(data.keys) == expectedDataKeys)
      #expect(!String(decoding: bytes, as: UTF8.self).contains("private note body"))
      #expect(!String(decoding: bytes, as: UTF8.self).contains("task text"))
    }

    let maximumEnvelope = try AgentEventEnvelope(
      eventID: String(repeating: "e", count: 128),
      name: .noteUpdated,
      timestamp: "2026-09-30T12:00:00.123456789+05:30",
      data: .noteUpdated(
        noteID: noteID,
        revision: UInt64.max,
        changedFields: AgentEventChangedField.allCases,
        origin: .local
      ),
      cursor: String(repeating: "\\", count: 256)
    )
    #expect(try encoder.encode(maximumEnvelope).count < 1_024)
  }

  @Test func eventNameMustMatchItsStrictPayloadShape() throws {
    let noteID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    #expect(throws: DecodingError.self) {
      _ = try AgentEventEnvelope(
        eventID: "event-1",
        name: .noteCreated,
        timestamp: "2026-09-30T12:00:00Z",
        data: .noteUpdated(
          noteID: noteID,
          revision: 7,
          changedFields: [.body],
          origin: .local
        ),
        cursor: nil
      )
    }

    let malformedData = Data(
      #"{"note_id":"00000000-0000-4000-8000-000000000001","revision":7,"origin":"local","title":"private"}"#
        .utf8
    )
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(AgentEventData.self, from: malformedData)
    }

    #expect(throws: DecodingError.self) {
      _ = try AgentEventEnvelope(
        eventID: "event-2",
        name: .noteUpdated,
        timestamp: "2026-09-30T12:00:00Z",
        data: .noteUpdated(
          noteID: noteID,
          revision: 7,
          changedFields: [.body, .body],
          origin: .local
        ),
        cursor: nil
      )
    }

    let timestampWithTrailingContent = Data(
      #"{"eventId":"event-3","name":"note.created","timestamp":"2026-09-30T12:00:00Z private note body","data":{"note_id":"00000000-0000-4000-8000-000000000001","revision":7,"origin":"local"},"cursor":null}"#
        .utf8
    )
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(AgentEventEnvelope.self, from: timestampWithTrailingContent)
    }

    let oversizedTimestamp = Data(
      ("{\"eventId\":\"event-4\",\"name\":\"note.created\",\"timestamp\":\"2026-09-30T12:00:00Z"
        + String(repeating: "x", count: 4_096)
        + "\",\"data\":{\"note_id\":\"00000000-0000-4000-8000-000000000001\",\"revision\":7,\"origin\":\"local\"},\"cursor\":null}")
        .utf8
    )
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(AgentEventEnvelope.self, from: oversizedTimestamp)
    }
  }

  @Test func timestampsRejectInvalidCalendarTimeAndOffsetComponents() throws {
    let noteID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    for timestamp in [
      "2024-02-29T23:59:59Z",
      "2026-09-30T12:00:00.123456789+05:30",
      "2026-09-30T12:00:00-14:00",
      "2026-09-30T12:00:00+14:00",
    ] {
      _ = try AgentEventEnvelope(
        eventID: "valid-timestamp",
        name: .noteCreated,
        timestamp: timestamp,
        data: .noteCreated(noteID: noteID, revision: 1, origin: .local),
        cursor: nil
      )
    }

    let invalidTimestamps = [
      "2026-02-30T12:00:00Z",
      "2026-09-30T12:00:00+24:00",
      "2026-09-30T12:00:00+05:99",
      "2026-13-01T12:00:00Z",
      "2026-09-30T12:00:60Z",
      "2026-09-30T24:00:00Z",
      "2026-09-30T12:60:00Z",
      "2025-02-29T12:00:00Z",
    ]

    for (index, timestamp) in invalidTimestamps.enumerated() {
      #expect(throws: DecodingError.self) {
        _ = try AgentEventEnvelope(
          eventID: "timestamp-\(index)",
          name: .noteCreated,
          timestamp: timestamp,
          data: .noteCreated(noteID: noteID, revision: 1, origin: .local),
          cursor: nil
        )
      }
    }
  }
}
