#if os(macOS)
  import Foundation
  import MCP
  import FleckAgentProtocol
  import FleckCore

  enum FleckMCPToolRegistry {
    static let maximumTextBytes = 65_536

    struct Registration {
      let tool: Tool
      let capability: AgentCapability
    }

    static let registrations: [Registration] = [
      registration(
        capability: .listNotes,
        tool: tool(
          "list_shared_notes",
          "List notes explicitly shared with this integration.",
          properties: [:],
          readOnly: true
        )
      ),
      registration(
        capability: .readNotes,
        tool: tool(
          "read_note",
          "Read a shared note, optionally using one-based line windows.",
          properties: [
            "note_id": uuid("Stable note ID."),
            "start_line": positiveInteger("First one-based line to return."),
            "max_lines": positiveInteger("Maximum number of lines to return."),
          ],
          required: ["note_id"],
          readOnly: true
        )
      ),
      registration(
        capability: .writeNotes,
        tool: tool(
          "append_text",
          writeDescription("Append up to 65,536 UTF-8 bytes to a shared note."),
          properties: writeProperties([
            "text": string("Text to append; at most 65,536 UTF-8 bytes.")
          ]),
          required: writeRequired + ["text"]
        )
      ),
      registration(
        capability: .writeNotes,
        tool: tool(
          "insert_text",
          writeDescription(
            "Insert up to 65,536 UTF-8 bytes before a one-based line."
          ),
          properties: writeProperties([
            "before_line": positiveInteger("One-based line before which to insert."),
            "text": string("Text to insert; at most 65,536 UTF-8 bytes."),
          ]),
          required: writeRequired + ["before_line", "text"]
        ),
      ),
      registration(
        capability: .writeNotes,
        tool: tool(
          "replace_lines",
          writeDescription(
            "Replace an inclusive one-based line range with up to 65,536 UTF-8 bytes."
          ),
          properties: writeProperties([
            "start_line": positiveInteger("First one-based line to replace."),
            "end_line": positiveInteger("Last one-based line to replace, inclusive."),
            "expected_text_sha256": string(
              "SHA-256 of the observed line range as 64 lowercase hexadecimal characters."
            ),
            "text": string("Replacement text; at most 65,536 UTF-8 bytes."),
          ]),
          required: writeRequired
            + ["start_line", "end_line", "expected_text_sha256", "text"]
        ),
      ),
      registration(
        capability: .writeNotes,
        tool: tool(
          "delete_lines",
          writeDescription("Delete an inclusive one-based line range."),
          properties: writeProperties([
            "start_line": positiveInteger("First one-based line to delete."),
            "end_line": positiveInteger("Last one-based line to delete, inclusive."),
            "expected_text_sha256": string(
              "SHA-256 of the observed line range as 64 lowercase hexadecimal characters."
            ),
          ]),
          required: writeRequired
            + ["start_line", "end_line", "expected_text_sha256"]
        )
      ),
      registration(
        capability: .readNotes,
        tool: tool(
          "list_tasks",
          "List checklist tasks in a shared note.",
          properties: ["note_id": uuid("Stable note ID.")],
          required: ["note_id"],
          readOnly: true
        )
      ),
      registration(
        capability: .writeNotes,
        tool: tool(
          "add_task",
          writeDescription(
            "Add a checklist task whose text is at most 65,536 UTF-8 bytes."
          ),
          properties: writeProperties([
            "after_task_handle": string(
              "Optional authenticated task handle after which to add the task."
            ),
            "text": string("Task text; at most 65,536 UTF-8 bytes."),
          ]),
          required: writeRequired + ["text"]
        ),
      ),
      registration(
        capability: .writeNotes,
        tool: tool(
          "rename_task",
          writeDescription(
            "Rename a checklist task with text of at most 65,536 UTF-8 bytes."
          ),
          properties: writeProperties([
            "task_handle": string("Authenticated task handle."),
            "text": string("New task text; at most 65,536 UTF-8 bytes."),
          ]),
          required: writeRequired + ["task_handle", "text"]
        ),
      ),
      registration(
        capability: .writeNotes,
        tool: tool(
          "set_task_state",
          writeDescription("Mark a checklist task completed or open."),
          properties: writeProperties([
            "task_handle": string("Authenticated task handle."),
            "completed": ["type": "boolean", "description": "Desired task state."],
          ]),
          required: writeRequired + ["task_handle", "completed"]
        )
      ),
      registration(
        capability: .writeNotes,
        tool: tool(
          "remove_task",
          writeDescription("Remove a checklist task."),
          properties: writeProperties([
            "task_handle": string("Authenticated task handle.")
          ]),
          required: writeRequired + ["task_handle"]
        )
      ),
      registration(
        capability: .readNotes,
        tool: tool(
          "list_agent_activity",
          "List visible integration activity.",
          properties: [:],
          readOnly: true
        )
      ),
      registration(
        capability: .undoChanges,
        tool: tool(
          "undo_agent_change",
          writeDescription("Undo an eligible integration change."),
          properties: [
            "change_id": uuid("Stable activity change ID."),
            "expected_revision": revision,
            "operation_id": operation,
          ],
          required: ["change_id", "expected_revision", "operation_id"]
        )
      ),
    ]

    static let tools: [Tool] = registrations.map(\.tool)

    static func tools(for summary: AgentCapabilitySummary) -> [Tool] {
      registrations
        .filter { summary.availableCapabilities.contains($0.capability) }
        .map(\.tool)
    }

    private static func registration(
      capability: AgentCapability,
      tool: Tool
    ) -> Registration {
      Registration(tool: tool, capability: capability)
    }

    static func command(
      name: String,
      arguments: [String: Value]
    ) throws -> AgentWorkspaceCommand {
      try command(for: CallTool.Parameters(name: name, arguments: arguments))
    }

    static func command(
      for parameters: CallTool.Parameters
    ) throws -> AgentWorkspaceCommand {
      var input = Input(parameters.arguments ?? [:])
      let command: AgentWorkspaceCommand

      switch parameters.name {
      case "list_shared_notes":
        command = .listSharedNotes
      case "read_note":
        command = .readNote(
          request: .init(
            noteID: try input.uuid("note_id"),
            startLine: try input.optionalPositiveInt("start_line"),
            maxLines: try input.optionalPositiveInt("max_lines")
          )
        )
      case "append_text":
        command = .appendText(
          request: .init(
            context: try input.writeContext(),
            text: try input.boundedText("text")
          )
        )
      case "insert_text":
        command = .insertText(
          request: .init(
            context: try input.writeContext(),
            beforeLine: try input.positiveInt("before_line"),
            text: try input.boundedText("text")
          )
        )
      case "replace_lines":
        let context = try input.writeContext()
        let startLine = try input.positiveInt("start_line")
        let endLine = try input.positiveInt("end_line")
        guard endLine >= startLine else { throw invalidPayload() }
        let hash = try input.string("expected_text_sha256")
        guard
          hash.utf8.count == 64,
          hash.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        else {
          throw invalidPayload()
        }
        command = .replaceLines(
          request: .init(
            context: context,
            startLine: startLine,
            endLine: endLine,
            expectedTextSHA256: hash,
            text: try input.boundedText("text")
          )
        )
      case "delete_lines":
        let context = try input.writeContext()
        let startLine = try input.positiveInt("start_line")
        let endLine = try input.positiveInt("end_line")
        guard endLine >= startLine else { throw invalidPayload() }
        let hash = try input.string("expected_text_sha256")
        guard
          hash.utf8.count == 64,
          hash.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        else {
          throw invalidPayload()
        }
        command = .replaceLines(
          request: .init(
            context: context,
            startLine: startLine,
            endLine: endLine,
            expectedTextSHA256: hash,
            text: ""
          )
        )
      case "list_tasks":
        command = .listTasks(request: .init(noteID: try input.uuid("note_id")))
      case "add_task":
        command = .addTask(
          request: .init(
            context: try input.writeContext(),
            afterTaskHandle: try input.optionalString("after_task_handle"),
            text: try input.boundedText("text")
          )
        )
      case "rename_task":
        command = .renameTask(
          request: .init(
            context: try input.writeContext(),
            taskHandle: try input.string("task_handle"),
            text: try input.boundedText("text")
          )
        )
      case "set_task_state":
        command = .setTaskState(
          request: .init(
            context: try input.writeContext(),
            taskHandle: try input.string("task_handle"),
            completed: try input.bool("completed")
          )
        )
      case "remove_task":
        command = .removeTask(
          request: .init(
            context: try input.writeContext(),
            taskHandle: try input.string("task_handle")
          )
        )
      case "list_agent_activity":
        command = .listActivity
      case "undo_agent_change":
        command = .undoChange(
          request: .init(
            changeID: try input.uuid("change_id"),
            expectedRevision: try input.revision(),
            operationID: try input.uuid("operation_id")
          )
        )
      default:
        throw AgentWorkspaceError(code: .invalidOperation)
      }

      guard input.isEmpty else { throw invalidPayload() }
      return command
    }

    static func call(
      _ parameters: CallTool.Parameters,
      client: AgentWorkspaceClient
    ) -> CallTool.Result {
      do {
        let command = try command(for: parameters)
        return try result(for: client.execute(command))
      } catch let error as AgentWorkspaceError {
        return fallbackResult(for: error)
      } catch BridgeCredentialStoreError.credentialNotFound {
        return fallbackResult(
          for: AgentWorkspaceError(
            code: .permissionRevoked,
            recoveryAction: "Reconnect this profile in Fleck."
          )
        )
      } catch {
        return fallbackResult(
          for: AgentWorkspaceError(
            code: .fleckUnavailable,
            recoveryAction: "Open Fleck and try again."
          )
        )
      }
    }

    static func result(
      for response: AgentWorkspaceResponse
    ) throws -> CallTool.Result {
      let encoded = try encode(response)
      let readable = try BridgeOutput.response(response, json: false)
      let structured: Value? = try structuredValue(encoded)
      return CallTool.Result(
        content: textContent(readable.isEmpty ? "No results." : readable, encoded),
        structuredContent: structured,
        isError: false
      )
    }

    static func result(for error: AgentWorkspaceError) throws -> CallTool.Result {
      let encoded = try encode(error)
      let structured: Value? = try structuredValue(encoded)
      return CallTool.Result(
        content: textContent(
          try BridgeOutput.workspaceError(error, json: false),
          encoded
        ),
        structuredContent: structured,
        isError: true
      )
    }

    private static let writeRequired = [
      "note_id", "expected_revision", "operation_id",
    ]

    private static let revision: Value = [
      "type": "integer",
      "minimum": 0,
      "description": "Expected current note revision.",
    ]

    private static let operation: Value = uuid(
      "Unique operation ID; reuse it when retrying the same write."
    )

    private static func tool(
      _ name: String,
      _ description: String,
      properties: [String: Value],
      required: [String] = [],
      readOnly: Bool = false
    ) -> Tool {
      Tool(
        name: name,
        description: description,
        inputSchema: .object([
          "type": "object",
          "properties": .object(properties),
          "required": .array(required.map(Value.string)),
          "additionalProperties": false,
        ]),
        annotations: .init(
          readOnlyHint: readOnly,
          destructiveHint: readOnly ? false : nil,
          idempotentHint: readOnly ? true : nil,
          openWorldHint: false
        ),
        icons: FleckMCPBranding.toolIcons
      )
    }

    private static func writeDescription(_ operationDescription: String) -> String {
      operationDescription
        + " Requires the expected revision and a unique operation ID."
    }

    private static func writeProperties(
      _ additional: [String: Value]
    ) -> [String: Value] {
      [
        "note_id": uuid("Stable note ID."),
        "expected_revision": revision,
        "operation_id": operation,
      ].merging(additional) { _, new in new }
    }

    private static func uuid(_ description: String) -> Value {
      [
        "type": "string",
        "format": "uuid",
        "description": .string(description),
      ]
    }

    private static func string(_ description: String) -> Value {
      ["type": "string", "description": .string(description)]
    }

    private static func positiveInteger(_ description: String) -> Value {
      [
        "type": "integer",
        "minimum": 1,
        "description": .string(description),
      ]
    }

    fileprivate static func invalidPayload() -> AgentWorkspaceError {
      AgentWorkspaceError(code: .invalidPayload)
    }

    private static func textContent(
      _ readable: String,
      _ json: String
    ) -> [Tool.Content] {
      [
        .text(text: readable, annotations: nil, _meta: nil),
        .text(text: json, annotations: nil, _meta: nil),
      ]
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.sortedKeys]
      return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func structuredValue(_ json: String) throws -> Value {
      try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }

    private static func fallbackResult(
      for error: AgentWorkspaceError
    ) -> CallTool.Result {
      (try? result(for: error))
        ?? CallTool.Result(
          content: [
            .text(text: error.code.rawValue, annotations: nil, _meta: nil)
          ],
          structuredContent: .object(["code": .string(error.code.rawValue)]),
          isError: true
        )
    }
  }

  private struct Input {
    private var values: [String: Value]

    init(_ values: [String: Value]) {
      self.values = values
    }

    var isEmpty: Bool { values.isEmpty }

    mutating func writeContext() throws -> AgentWriteContext {
      AgentWriteContext(
        noteID: try uuid("note_id"),
        expectedRevision: try revision(),
        operationID: try uuid("operation_id")
      )
    }

    mutating func revision() throws -> UInt64 {
      let value = try int("expected_revision")
      guard value >= 0 else { throw FleckMCPToolRegistry.invalidPayload() }
      return UInt64(value)
    }

    mutating func positiveInt(_ name: String) throws -> Int {
      let value = try int(name)
      guard value >= 1 else { throw FleckMCPToolRegistry.invalidPayload() }
      return value
    }

    mutating func optionalPositiveInt(_ name: String) throws -> Int? {
      guard values[name] != nil else { return nil }
      return try positiveInt(name)
    }

    mutating func int(_ name: String) throws -> Int {
      guard let value = values.removeValue(forKey: name)?.intValue else {
        throw FleckMCPToolRegistry.invalidPayload()
      }
      return value
    }

    mutating func uuid(_ name: String) throws -> UUID {
      guard
        let value = values.removeValue(forKey: name)?.stringValue,
        let uuid = UUID(uuidString: value)
      else {
        throw FleckMCPToolRegistry.invalidPayload()
      }
      return uuid
    }

    mutating func string(_ name: String) throws -> String {
      guard let value = values.removeValue(forKey: name)?.stringValue else {
        throw FleckMCPToolRegistry.invalidPayload()
      }
      return value
    }

    mutating func optionalString(_ name: String) throws -> String? {
      guard values[name] != nil else { return nil }
      return try string(name)
    }

    mutating func boundedText(_ name: String) throws -> String {
      let value = try string(name)
      guard value.utf8.count <= FleckMCPToolRegistry.maximumTextBytes else {
        throw AgentWorkspaceError(code: .writeTooLarge)
      }
      return value
    }

    mutating func bool(_ name: String) throws -> Bool {
      guard let value = values.removeValue(forKey: name)?.boolValue else {
        throw FleckMCPToolRegistry.invalidPayload()
      }
      return value
    }
  }
#endif
