import Foundation

public struct AgentEventJSONSchema: Codable, Equatable, Sendable {
  public let type: String
  public let description: String?
  public let properties: [String: AgentEventJSONSchemaProperty]?
  public let required: [String]?
  public let additionalProperties: Bool?
  public let oneOf: [AgentEventJSONSchema]?

  public init(
    type: String,
    description: String? = nil,
    properties: [String: AgentEventJSONSchemaProperty]? = nil,
    required: [String]? = nil,
    additionalProperties: Bool? = nil,
    oneOf: [AgentEventJSONSchema]? = nil
  ) {
    self.type = type
    self.description = description
    self.properties = properties
    self.required = required
    self.additionalProperties = additionalProperties
    self.oneOf = oneOf
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case description
    case properties
    case required
    case additionalProperties
    case oneOf
  }
}

public struct AgentEventJSONSchemaProperty: Codable, Equatable, Sendable {
  public let type: String
  public let format: String?
  public let items: AgentEventJSONSchemaItem?
  public let enumValues: [String]?
  public let uniqueItems: Bool?
  public let minItems: Int?
  public let maxItems: Int?
  public let minimum: Int?

  public init(
    type: String,
    format: String? = nil,
    items: AgentEventJSONSchemaItem? = nil,
    enumValues: [String]? = nil,
    uniqueItems: Bool? = nil,
    minItems: Int? = nil,
    maxItems: Int? = nil,
    minimum: Int? = nil
  ) {
    self.type = type
    self.format = format
    self.items = items
    self.enumValues = enumValues
    self.uniqueItems = uniqueItems
    self.minItems = minItems
    self.maxItems = maxItems
    self.minimum = minimum
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case format
    case items
    case enumValues = "enum"
    case uniqueItems
    case minItems
    case maxItems
    case minimum
  }
}

public struct AgentEventJSONSchemaItem: Codable, Equatable, Sendable {
  public let type: String
  public let enumValues: [String]?

  public init(type: String, enumValues: [String]? = nil) {
    self.type = type
    self.enumValues = enumValues
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case enumValues = "enum"
  }
}

public struct AgentEventDescriptor: Codable, Equatable, Sendable {
  public let name: AgentEventName
  public let description: String
  public let inputSchema: AgentEventJSONSchema
  public let payloadSchema: AgentEventJSONSchema
}

public enum AgentEventCatalog {
  public static let events: [AgentEventDescriptor] = {
    let noteScope = AgentEventJSONSchema(
      type: "object",
      properties: ["note_id": uuidSchema],
      required: ["note_id"],
      additionalProperties: false
    )
    let folderScope = AgentEventJSONSchema(
      type: "object",
      properties: ["folder_id": uuidSchema],
      required: ["folder_id"],
      additionalProperties: false
    )
    let scope = AgentEventJSONSchema(
      type: "object",
      description: "Select one note or one explicitly granted folder.",
      properties: ["folder_id": uuidSchema, "note_id": uuidSchema],
      additionalProperties: false,
      oneOf: [noteScope, folderScope]
    )
    let commonProperties = [
      "note_id": uuidSchema,
      "revision": AgentEventJSONSchemaProperty(type: "integer", minimum: 0),
      "origin": AgentEventJSONSchemaProperty(type: "string", enumValues: ["local"]),
    ]
    let createdSchema = AgentEventJSONSchema(
      type: "object",
      properties: commonProperties,
      required: ["note_id", "revision", "origin"],
      additionalProperties: false
    )
    let updatedSchema = AgentEventJSONSchema(
      type: "object",
      properties: commonProperties.merging([
        "changed_fields": AgentEventJSONSchemaProperty(
          type: "array",
          items: AgentEventJSONSchemaItem(
            type: "string",
            enumValues: AgentEventChangedField.allCases.map(\.rawValue).sorted()
          ),
          uniqueItems: true,
          minItems: 1,
          maxItems: AgentEventChangedField.allCases.count
        )
      ]) { _, new in new },
      required: ["note_id", "revision", "changed_fields", "origin"],
      additionalProperties: false
    )
    let taskChangedSchema = AgentEventJSONSchema(
      type: "object",
      properties: commonProperties.merging([
        "completion_transition": AgentEventJSONSchemaProperty(
          type: "string",
          enumValues: AgentTaskCompletionTransition.allCases.map(\.rawValue).sorted()
        )
      ]) { _, new in new },
      required: ["note_id", "revision", "completion_transition", "origin"],
      additionalProperties: false
    )

    return [
      AgentEventDescriptor(
        name: .noteCreated,
        description:
          "A new authorized note was created. Call read_note to retrieve its current content.",
        inputSchema: scope,
        payloadSchema: createdSchema
      ),
      AgentEventDescriptor(
        name: .noteUpdated,
        description: "An authorized note changed. Call read_note for its current content.",
        inputSchema: scope,
        payloadSchema: updatedSchema
      ),
      AgentEventDescriptor(
        name: .taskStateChanged,
        description:
          "A checklist completion changed. Call list_tasks for current task state and handles.",
        inputSchema: scope,
        payloadSchema: taskChangedSchema
      ),
    ]
  }()

  public static func serializedData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(events)
  }

  private static let uuidSchema = AgentEventJSONSchemaProperty(type: "string", format: "uuid")
}
