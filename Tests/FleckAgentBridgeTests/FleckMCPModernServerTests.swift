import FleckAgentProtocol
import FleckCore
import Darwin
import Foundation
import Logging
import MCP
import Testing

@testable import FleckAgentBridge

@Suite("FleckMCP modern wire")
struct FleckMCPModernServerTests {
  @Test func discoveryIsHandshakeFreeAndAdvertisesOnlyImplementedCapabilities()
    async throws
  {
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { FleckMCPToolRegistry.tools },
      callTool: { _ in try FleckMCPToolRegistry.result(for: .sharedNotes(notes: [])) }
    )
    let response = try #require(
      await dispatcher.response(
        for: request(method: "server/discover", id: "discover-1")
      )
    )
    let envelope = try responseObject(response)
    let result = try #require(envelope["result"] as? [String: Any])
    let capabilities = try #require(result["capabilities"] as? [String: Any])
    let tools = try #require(capabilities["tools"] as? [String: Any])
    let metadata = try #require(result["_meta"] as? [String: Any])
    let serverInfo = try #require(
      metadata["io.modelcontextprotocol/serverInfo"] as? [String: Any]
    )

    #expect(envelope["id"] as? String == "discover-1")
    #expect(result["resultType"] as? String == "complete")
    #expect(result["supportedVersions"] as? [String] == ["2026-07-28"])
    #expect(tools["listChanged"] as? Bool == false)
    #expect(capabilities["events"] == nil)
    #expect(capabilities["extensions"] == nil)
    #expect(capabilities["prompts"] == nil)
    #expect(capabilities["resources"] == nil)
    #expect(result["serverInfo"] == nil)
    #expect(serverInfo["name"] as? String == "fleck")
    #expect(serverInfo["version"] as? String == "1.0.0")
    #expect(result["cacheScope"] as? String == "public")
    #expect(result["ttlMs"] as? Int == 300_000)
  }

  @Test func modernToolsListAndCallUseHandlersAndCompleteResults() async throws {
    let calls = ModernHandlerCalls()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: {
        await calls.record("list")
        return FleckMCPToolRegistry.tools.reversed()
      },
      callTool: { parameters in
        await calls.record("call")
        #expect(parameters.name == "list_shared_notes")
        return try FleckMCPToolRegistry.result(for: .sharedNotes(notes: []))
      }
    )

    let listed = try #require(
      await dispatcher.response(
        for: request(method: "tools/list", id: 1)
      )
    )
    let listEnvelope = try responseObject(listed)
    let listResult = try #require(listEnvelope["result"] as? [String: Any])
    let tools = try #require(listResult["tools"] as? [[String: Any]])
    let toolNames = tools.compactMap { $0["name"] as? String }

    #expect(listResult["resultType"] as? String == "complete")
    #expect(listResult["cacheScope"] as? String == "private")
    #expect(listResult["ttlMs"] as? Int == 0)
    #expect(toolNames == toolNames.sorted())
    #expect(toolNames == FleckMCPToolRegistry.tools.map(\.name).sorted())

    let called = try #require(
      await dispatcher.response(
        for: request(
          method: "tools/call",
          id: "call-1",
          params: [
            "_meta": requestMetadata(),
            "name": "list_shared_notes",
            "arguments": [:] as [String: Any],
          ]
        )
      )
    )
    let callEnvelope = try responseObject(called)
    let callResult = try #require(callEnvelope["result"] as? [String: Any])
    let callMetadata = try #require(callResult["_meta"] as? [String: Any])
    let serverInfo = try #require(
      callMetadata["io.modelcontextprotocol/serverInfo"] as? [String: Any]
    )

    #expect(callResult["resultType"] as? String == "complete")
    #expect(callResult["isError"] as? Bool == false)
    #expect(callResult["content"] is [[String: Any]])
    #expect(serverInfo["name"] as? String == "fleck")
    #expect(await calls.values() == ["list", "call"])
  }

  @Test func metadataIsRequiredAndClientInfoIsValidatedWhenPresent() async throws {
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let malformedMetadata: [Any] = [
      [:] as [String: Any],
      [
        "io.modelcontextprotocol/protocolVersion": "2026-07-28"
      ] as [String: Any],
      [
        "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any]
      ] as [String: Any],
      [
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": ["sampling"] as [String],
      ] as [String: Any],
      [
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any],
        "io.modelcontextprotocol/clientInfo": ["name": 4, "version": "1"],
      ] as [String: Any],
      [
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any],
        "io.modelcontextprotocol/clientInfo": [
          "name": "client",
          "version": "1",
          "title": 4,
        ],
      ] as [String: Any],
      [
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any],
        "io.modelcontextprotocol/clientInfo": [
          "name": "client",
          "version": "1",
          "websiteUrl": "not a uri",
        ],
      ] as [String: Any],
      [
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any],
        "io.modelcontextprotocol/clientInfo": [
          "name": "client",
          "version": "1",
          "title": NSNull(),
        ],
      ] as [String: Any],
    ]

    for metadata in malformedMetadata {
      let response = try #require(
        await dispatcher.response(
          for: request(
            method: "ping",
            id: 7,
            params: ["_meta": metadata]
          )
        )
      )
      #expect(try errorCode(response) == -32602)
    }

    let validClientInfo = requestMetadata().merging(
      [
        "io.modelcontextprotocol/clientInfo": [
          "name": "fixture-client",
          "version": "1.2.3",
          "title": "Fixture Client",
          "icons": [["src": "https://example.invalid/icon.png"]],
          "websiteUrl": "https://example.invalid/",
        ] as [String: Any]
      ]
    ) { _, new in new }
    let valid = try #require(
      await dispatcher.response(
        for: request(method: "ping", id: "valid-client", params: ["_meta": validClientInfo])
      )
    )
    let validResult = try #require(responseObject(valid)["result"] as? [String: Any])
    #expect(validResult["resultType"] as? String == "complete")
  }

  @Test func unsupportedVersionsReturnModernSupportWithoutExecutingHandlers()
    async throws
  {
    let calls = ModernHandlerCalls()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: {
        await calls.record("list")
        return []
      },
      callTool: { _ in
        await calls.record("call")
        return CallTool.Result(content: [], isError: false)
      }
    )
    let metadata = requestMetadata().merging(
      ["io.modelcontextprotocol/protocolVersion": "2025-11-25"]
    ) { _, new in new }
    let response = try #require(
      await dispatcher.response(
        for: request(method: "tools/list", id: 4, params: ["_meta": metadata])
      )
    )
    let envelope = try responseObject(response)
    let error = try #require(envelope["error"] as? [String: Any])
    let data = try #require(error["data"] as? [String: Any])

    #expect(error["code"] as? Int == -32022)
    #expect(data["requested"] as? String == "2025-11-25")
    #expect(data["supported"] as? [String] == ["2026-07-28"])
    #expect(await calls.values().isEmpty)
  }

  @Test func requiredMetadataAndVersionPrecedeMethodLookup() async throws {
    let calls = ModernHandlerCalls()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: {
        await calls.record("list")
        return []
      },
      callTool: { _ in
        await calls.record("call")
        return CallTool.Result(content: [], isError: false)
      }
    )
    let unsupportedMetadata = requestMetadata().merging(
      ["io.modelcontextprotocol/protocolVersion": "2099-01-01"]
    ) { _, new in new }

    let unsupported = try #require(
      await dispatcher.response(
        for: request(
          method: "unknown/method",
          id: 1,
          params: ["_meta": unsupportedMetadata]
        )
      )
    )
    let unsupportedEnvelope = try responseObject(unsupported)
    let unsupportedError = try #require(unsupportedEnvelope["error"] as? [String: Any])
    let unsupportedData = try #require(unsupportedError["data"] as? [String: Any])

    #expect(unsupportedError["code"] as? Int == -32022)
    #expect(unsupportedData["requested"] as? String == "2099-01-01")
    #expect(unsupportedData["supported"] as? [String] == ["2026-07-28"])

    let missingMetadata = try #require(
      await dispatcher.response(
        for: request(method: "unknown/method", id: 2, params: [:])
      )
    )
    #expect(try errorCode(missingMetadata) == -32602)
    #expect(await calls.values().isEmpty)
  }

  @Test func modernJSONRPCErrorsOmitUnavailableIDsAndMatchTheEnvelopeSchema()
    async throws
  {
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let parseError = try #require(
      await dispatcher.response(for: Data("{".utf8))
    )
    let parseEnvelope = try responseObject(parseError)
    let parseDetails = try #require(parseEnvelope["error"] as? [String: Any])

    #expect(Set(parseEnvelope.keys) == ["jsonrpc", "error"])
    #expect(parseEnvelope["jsonrpc"] as? String == "2.0")
    #expect(Set(parseDetails.keys) == ["code", "message"])
    #expect(parseDetails["code"] as? Int == -32700)
    #expect(parseDetails["message"] as? String == "Parse error")

    let invalidID = try #require(
      await dispatcher.response(
        for: request(method: "ping", id: NSNull(), params: ["_meta": requestMetadata()])
      )
    )
    #expect(Set(try responseObject(invalidID).keys) == ["jsonrpc", "error"])

    let unsupportedMetadata = requestMetadata().merging(
      ["io.modelcontextprotocol/protocolVersion": "2099-01-01"]
    ) { _, new in new }
    let versionError = try #require(
      await dispatcher.response(
        for: request(method: "ping", id: 7, params: ["_meta": unsupportedMetadata])
      )
    )
    let versionEnvelope = try responseObject(versionError)
    let versionDetails = try #require(versionEnvelope["error"] as? [String: Any])
    #expect(Set(versionEnvelope.keys) == ["jsonrpc", "id", "error"])
    #expect(versionEnvelope["id"] as? Int == 7)
    #expect(Set(versionDetails.keys) == ["code", "message", "data"])
  }

  @Test func invalidWireMessagesAndParametersUseContentFreeJSONRPCErrors()
    async throws
  {
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let invalid: [(Data, Int)] = [
      (Data(#"{"jsonrpc":"2.0","id":1"#.utf8), -32700),
      (try wire(true), -32600),
      (try wire([["jsonrpc": "2.0", "id": 1, "method": "ping"]]), -32600),
      (try wire(["jsonrpc": "2.0", "id": 1]), -32600),
      (try request(method: "ping", id: NSNull(), params: ["_meta": requestMetadata()]), -32600),
      (
        try request(
          method: "ping", id: NSNumber(value: true), params: ["_meta": requestMetadata()]), -32600
      ),
      (
        try request(
          method: "ping", id: ["private-marker": true], params: ["_meta": requestMetadata()]),
        -32600
      ),
      (
        try request(method: "ping", id: 1, params: ["_meta": requestMetadata()], jsonrpc: "1.0"),
        -32600
      ),
      (try request(method: "ping", id: 1, params: NSNull()), -32602),
      (
        try request(
          method: "tools/call", id: 1,
          params: ["_meta": requestMetadata(), "name": "x", "arguments": ["private-marker"]]),
        -32602
      ),
      (
        try request(
          method: "tools/list", id: 1,
          params: ["_meta": requestMetadata(), "cursor": "private-marker"]), -32602
      ),
      (try request(method: "secret-method", id: 1, params: ["_meta": requestMetadata()]), -32601),
    ]

    for (message, expectedCode) in invalid {
      let response = try #require(await dispatcher.response(for: message))
      #expect(try errorCode(response) == expectedCode)
      #expect(!String(decoding: response, as: UTF8.self).contains("private-marker"))
    }
  }

  @Test func modernRequestsRemainIndependentOfLegacyInitializeTraffic()
    async throws
  {
    let calls = ModernHandlerCalls()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: {
        await calls.record("list")
        return []
      },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let underlying = ModernCapturingTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let received = ModernReceivedMessages()
    let reader = Task {
      do {
        for try await message in await transport.receive() {
          await received.append(message)
        }
      } catch {}
      await received.finish()
    }

    await underlying.push(try request(method: "server/discover", id: "modern-first"))
    await underlying.push(
      try wire([
        "jsonrpc": "2.0",
        "id": 10,
        "method": "initialize",
        "params": [
          "protocolVersion": "2025-11-25",
          "capabilities": [:] as [String: Any],
          "clientInfo": ["name": "legacy", "version": "1"],
        ] as [String: Any],
      ])
    )
    await underlying.push(try wire(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    await underlying.push(try wire(["jsonrpc": "2.0", "id": 11, "method": "tools/list"]))
    await underlying.push(try request(method: "tools/list", id: "modern-after-legacy"))
    await underlying.push(
      try request(
        method: "tools/list",
        id: "malformed-metadata",
        params: ["_meta": ["io.modelcontextprotocol/protocolVersion": "2026-07-28"]]
      )
    )

    await underlying.waitForSentCount(3)
    await received.waitForCount(3)
    let forwarded = await received.messages()
    #expect(forwarded.count == 3)
    #expect(await calls.values() == ["list"])
    let sent = await underlying.sentMessages()
    var responsesByID: [String: Data] = [:]
    for response in sent {
      let envelope = try responseObject(response)
      if let id = envelope["id"] as? String { responsesByID[id] = response }
    }
    #expect(try responseObject(#require(responsesByID["modern-first"]))["result"] is [String: Any])
    #expect(try errorCode(#require(responsesByID["malformed-metadata"])) == -32602)

    await underlying.finishInput()
    await transport.abortDrain()
    await reader.value
  }

  @Test func legacyProgressMetadataAndBatchesReachThePinnedSDK() async throws {
    let calls = ModernHandlerCalls()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let server = await FleckMCPServer.makeServer(
      listTools: { [] },
      callTool: { parameters in
        let progressToken: String?
        if case .string(let token)? = parameters._meta?.progressToken {
          progressToken = token
        } else {
          progressToken = nil
        }
        await calls.record(parameters.name, progressToken: progressToken)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let underlying = ModernCapturingTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: dispatcher
    )
    try await server.start(transport: transport)

    await underlying.push(
      try wire([
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "protocolVersion": "2025-11-25",
          "capabilities": [:] as [String: Any],
          "clientInfo": ["name": "legacy", "version": "1"],
        ] as [String: Any],
      ])
    )
    await underlying.waitForSentCount(1)
    await underlying.push(try wire(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    await underlying.push(
      try wire([
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": [
          "name": "progress-call",
          "_meta": ["progressToken": "legacy-progress"],
        ] as [String: Any],
      ])
    )
    await underlying.waitForSentCount(2)
    #expect(await calls.values() == ["progress-call"])
    #expect(await calls.progressTokens() == ["legacy-progress"])
    await underlying.push(
      try wire([
        [
          "jsonrpc": "2.0",
          "id": 3,
          "method": "tools/call",
          "params": ["name": "batch-one", "arguments": [:] as [String: Any]],
        ],
        [
          "jsonrpc": "2.0",
          "id": 4,
          "method": "tools/call",
          "params": ["name": "batch-two", "arguments": [:] as [String: Any]],
        ],
      ])
    )
    await underlying.waitForSentCount(3)

    let sent = await underlying.sentMessages()
    let batchResponse = try #require(
      JSONSerialization.jsonObject(with: sent[2]) as? [[String: Any]]
    )

    #expect(await calls.values() == ["progress-call", "batch-one", "batch-two"])
    #expect(try responseObject(sent[1])["id"] as? Int == 2)
    #expect(batchResponse.compactMap { $0["id"] as? Int }.sorted() == [3, 4])

    await underlying.finishInput()
    await server.waitUntilCompleted()
    await transport.waitUntilDrained()
    await server.stop()
  }

  @Test func legacyNotificationOnlyBatchesDoNotProduceResponses() async throws {
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let server = await FleckMCPServer.makeServer(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let underlying = ModernCapturingTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: dispatcher
    )
    try await server.start(transport: transport)
    await underlying.push(
      try wire([
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "protocolVersion": "2025-11-25",
          "capabilities": [:] as [String: Any],
          "clientInfo": ["name": "legacy", "version": "1"],
        ] as [String: Any],
      ])
    )
    await underlying.waitForSentCount(1)
    await underlying.push(
      try wire([
        ["jsonrpc": "2.0", "method": "notifications/initialized"],
        [
          "jsonrpc": "2.0",
          "method": "notifications/progress",
          "params": ["progressToken": "synthetic", "progress": 1],
        ],
      ])
    )
    await underlying.push(try wire(["jsonrpc": "2.0", "id": 2, "method": "ping"]))
    await underlying.waitForSentCount(2)
    await underlying.finishInput()
    await server.waitUntilCompleted()
    await transport.waitUntilDrained()
    await server.stop()

    let sent = await underlying.sentMessages()
    #expect(sent.count == 2)
    #expect(try sent.map { try responseObject($0)["id"] as? Int } == [1, 2])
    #expect(await transport.pendingRequestCount == 0)
  }

  @Test func legacyNotificationBatchesCancelOwnedModernRequests() async throws {
    let gate = ModernRequestGate()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in
        await gate.suspend()
        return CallTool.Result(content: [], isError: false)
      }
    )
    let underlying = ModernCapturingTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let received = ModernReceivedMessages()
    let reader = Task {
      do {
        for try await message in await transport.receive() {
          await received.append(message)
        }
      } catch {}
      await received.finish()
    }
    await underlying.push(
      try wire([
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": ["protocolVersion": "2025-11-25"],
      ])
    )
    await received.waitForCount(1)
    try await transport.send(try wire(["jsonrpc": "2.0", "id": 1, "result": [:]]))
    await underlying.push(
      try request(
        method: "tools/call", id: "cancel-batch",
        params: ["_meta": requestMetadata(), "name": "write"]
      )
    )
    await gate.waitUntilStarted()
    let notifications = try wire([
      [
        "jsonrpc": "2.0", "method": "notifications/cancelled",
        "params": ["requestId": "cancel-batch"],
      ],
      ["jsonrpc": "2.0", "method": "notifications/initialized"],
    ])
    await underlying.push(notifications)
    await received.waitForCount(2)
    await transport.waitUntilDrained()
    #expect(await transport.pendingRequestCount == 0)
    #expect(await received.messages().last == notifications)
    await gate.resume()
    await gate.waitUntilCompleted()
    await underlying.finishInput()
    await reader.value
    #expect(await underlying.sentMessages().count == 1)
  }

  @Test func rootModernMarkersCannotBeMaskedByLegacyMetadata() async throws {
    let calls = ModernHandlerCalls()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let server = await FleckMCPServer.makeServer(
      listTools: { [] },
      callTool: { parameters in
        await calls.record(parameters.name)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let underlying = ModernCapturingTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: dispatcher
    )
    try await server.start(transport: transport)
    await underlying.push(
      try wire([
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "protocolVersion": "2025-11-25",
          "capabilities": [:] as [String: Any],
          "clientInfo": ["name": "legacy", "version": "1"],
        ] as [String: Any],
      ])
    )
    await underlying.waitForSentCount(1)
    await underlying.push(try wire(["jsonrpc": "2.0", "method": "notifications/initialized"]))

    let rootMarkers: [[String: Any]] = [
      ["io.modelcontextprotocol/protocolVersion": "2026-07-28"],
      ["io.modelcontextprotocol/clientCapabilities": [:] as [String: Any]],
      ["io.modelcontextprotocol/clientInfo": ["name": "client", "version": "1"]],
    ]
    var expectedIDs: [String] = []
    var nextID = 0
    for marker in rootMarkers {
      for nestedMetadata in [
        [:] as [String: Any],
        ["progressToken": "legacy-progress"] as [String: Any],
      ] {
        let id = "root-marker-\(nextID)"
        expectedIDs.append(id)
        await underlying.push(
          try wire([
            "jsonrpc": "2.0",
            "id": id,
            "method": "tools/call",
            "params": [
              "name": "must-not-run-\(nextID)",
              "arguments": [:] as [String: Any],
              "_meta": nestedMetadata,
            ] as [String: Any],
            "_meta": marker,
          ])
        )
        nextID += 1
      }
    }

    await underlying.push(
      try wire([
        [
          "jsonrpc": "2.0",
          "id": 301,
          "method": "tools/call",
          "params": ["name": "mixed-legacy", "arguments": [:] as [String: Any]],
        ],
        [
          "jsonrpc": "2.0",
          "id": 302,
          "method": "tools/call",
          "params": [
            "name": "mixed-modern",
            "arguments": [:] as [String: Any],
            "_meta": ["progressToken": "legacy-progress"],
          ],
          "_meta": rootMarkers[0],
        ],
      ])
    )
    await underlying.waitForSentCount(8)

    let sent = await underlying.sentMessages()
    for id in expectedIDs {
      let response = try #require(
        sent.first { (try? responseObject($0)["id"] as? String) == id }
      )
      #expect(try errorCode(response) == -32602)
    }
    let mixedEnvelope = sent.compactMap { data -> [String: Any]? in
      guard
        let message = try? JSONSerialization.jsonObject(
          with: data,
          options: [.fragmentsAllowed]
        ) as? [String: Any], message["id"] == nil
      else {
        return nil
      }
      return message
    }.first
    let mixedError = mixedEnvelope?["error"] as? [String: Any]
    #expect(mixedError?["code"] as? Int == -32600)
    #expect(await calls.values().isEmpty)

    await underlying.finishInput()
    await server.waitUntilCompleted()
    await transport.waitUntilDrained()
    await server.stop()
  }

  @Test func legacyBatchesAboveAdmissionLimitAndWithDuplicateIDsAreRejected()
    async throws
  {
    let calls = ModernHandlerCalls()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let server = await FleckMCPServer.makeServer(
      listTools: { [] },
      callTool: { parameters in
        await calls.record(parameters.name)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let underlying = ModernCapturingTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: dispatcher
    )
    try await server.start(transport: transport)
    await underlying.push(
      try wire([
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "protocolVersion": "2025-11-25",
          "capabilities": [:] as [String: Any],
          "clientInfo": ["name": "legacy", "version": "1"],
        ] as [String: Any],
      ])
    )
    await underlying.waitForSentCount(1)
    await underlying.push(try wire(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    await underlying.push(
      try wire(
        (100..<109).map { id in
          [
            "jsonrpc": "2.0",
            "id": id,
            "method": "tools/call",
            "params": ["name": "oversized-\(id)", "arguments": [:] as [String: Any]],
          ] as [String: Any]
        })
    )
    await underlying.waitForSentCount(2)
    await underlying.push(
      try wire([
        [
          "jsonrpc": "2.0",
          "id": 201,
          "method": "tools/call",
          "params": ["name": "duplicate-one", "arguments": [:] as [String: Any]],
        ],
        [
          "jsonrpc": "2.0",
          "id": 201,
          "method": "tools/call",
          "params": ["name": "duplicate-two", "arguments": [:] as [String: Any]],
        ],
      ])
    )
    await underlying.waitForSentCount(3)

    let sent = await underlying.sentMessages()
    let oversized = try #require(
      JSONSerialization.jsonObject(with: sent[1]) as? [[String: Any]]
    )
    let duplicate = try #require(
      JSONSerialization.jsonObject(with: sent[2]) as? [[String: Any]]
    )
    #expect(oversized.compactMap { $0["id"] as? Int }.sorted() == Array(100..<109))
    #expect(oversized.allSatisfy { $0["error"] != nil })
    #expect(duplicate.compactMap { $0["id"] as? Int } == [201])
    #expect(duplicate.allSatisfy { $0["error"] != nil })
    #expect(await calls.values().isEmpty)

    await underlying.finishInput()
    await server.waitUntilCompleted()
    await transport.waitUntilDrained()
    await server.stop()
  }

  @Test func modernBatchesAreRejectedAfterLegacyHandshake() async throws {
    let calls = ModernHandlerCalls()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let server = await FleckMCPServer.makeServer(
      listTools: { [] },
      callTool: { parameters in
        await calls.record(parameters.name)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let underlying = ModernCapturingTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: dispatcher
    )
    try await server.start(transport: transport)

    await underlying.push(
      try wire([
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "protocolVersion": "2025-11-25",
          "capabilities": [:] as [String: Any],
          "clientInfo": ["name": "legacy", "version": "1"],
        ] as [String: Any],
      ])
    )
    await underlying.waitForSentCount(1)
    await underlying.push(try wire(["jsonrpc": "2.0", "method": "notifications/initialized"]))

    let legacyCall: [String: Any] = [
      "jsonrpc": "2.0",
      "id": 2,
      "method": "tools/call",
      "params": ["name": "legacy-call", "arguments": [:] as [String: Any]],
    ]
    let modernCall: [String: Any] = [
      "jsonrpc": "2.0",
      "id": 3,
      "method": "tools/call",
      "params": [
        "_meta": requestMetadata(),
        "name": "modern-call",
        "arguments": [:] as [String: Any],
      ],
    ]
    await underlying.push(try wire([legacyCall, modernCall]))
    await underlying.waitForSentCount(2)

    let firstModernCall: [String: Any] = [
      "jsonrpc": "2.0",
      "id": 4,
      "method": "tools/call",
      "params": [
        "_meta": requestMetadata(),
        "name": "modern-call-one",
        "arguments": [:] as [String: Any],
      ],
    ]
    let secondModernCall: [String: Any] = [
      "jsonrpc": "2.0",
      "id": 5,
      "method": "tools/call",
      "params": [
        "_meta": requestMetadata(),
        "name": "modern-call-two",
        "arguments": [:] as [String: Any],
      ],
    ]
    await underlying.push(try wire([firstModernCall, secondModernCall]))
    await underlying.waitForSentCount(3)

    let sent = await underlying.sentMessages()
    for response in sent.dropFirst() {
      let envelope = try responseObject(response)
      #expect(envelope["id"] == nil)
      #expect(try errorCode(response) == -32600)
    }
    #expect(await calls.values().isEmpty)

    await underlying.finishInput()
    await server.waitUntilCompleted()
    await transport.waitUntilDrained()
    await server.stop()
  }

  @Test func nativePipePreservesBurstFramesWithSlowConsumer() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let transport = FleckMCPBoundedStdioTransport(
      inputDescriptor: input.fileHandleForReading.fileDescriptor,
      outputDescriptor: output.fileHandleForWriting.fileDescriptor
    )
    try await transport.connect()
    let stream = await transport.receive()
    var batch = Data()
    for id in 1...20 {
      batch.append(try request(method: "ping", id: id))
      batch.append(UInt8(ascii: "\n"))
    }
    try input.fileHandleForWriting.write(contentsOf: batch)
    try await Task.sleep(for: .milliseconds(50))

    var iterator = stream.makeAsyncIterator()
    var receivedIDs: [Int] = []
    for _ in 1...20 {
      let message = try #require(try await iterator.next())
      receivedIDs.append(try #require(responseObject(message)["id"] as? Int))
      try await Task.sleep(for: .milliseconds(2))
    }

    input.fileHandleForWriting.closeFile()
    #expect(try await iterator.next() == nil)
    #expect(receivedIDs == Array(1...20))
    await transport.disconnect()
  }

  @Test func nativePipeAdapterAnswersEveryMessageInABurst() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let reader = Task {
      do {
        for try await _ in await transport.receive() {}
        return true
      } catch {
        return false
      }
    }
    let outputReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).readToEnd() ?? Data()
    }
    var batch = Data()
    for id in 1...20 {
      batch.append(try request(method: "ping", id: id))
      batch.append(UInt8(ascii: "\n"))
    }
    try input.fileHandleForWriting.write(contentsOf: batch)
    input.fileHandleForWriting.closeFile()
    let receivedEOF = await reader.value
    await transport.waitUntilDrained()
    await transport.disconnect()
    output.fileHandleForWriting.closeFile()
    let outputData = try await outputReader.value
    let responses = try outputData.split(separator: UInt8(ascii: "\n")).map {
      try responseObject(Data($0))
    }

    #expect(receivedEOF)
    #expect(responses.compactMap { $0["id"] as? Int }.sorted() == Array(1...20))
  }

  @Test func nativePipeCancellationSuppressesAQueuedResponseBeforeItsFirstByte()
    async throws
  {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in
        CallTool.Result(
          content: [
            .text(text: String(repeating: "x", count: 262_144), annotations: nil, _meta: nil)
          ],
          isError: false
        )
      }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let reader = Task {
      do {
        for try await _ in await transport.receive() {}
        return true
      } catch {
        return false
      }
    }
    try input.fileHandleForWriting.write(
      contentsOf: request(
        method: "tools/call",
        id: 3,
        params: ["_meta": requestMetadata(), "name": "large"]
      ) + Data([UInt8(ascii: "\n")])
    )
    try await Task.sleep(for: .milliseconds(150))
    try input.fileHandleForWriting.write(
      contentsOf: request(method: "ping", id: 4) + Data([UInt8(ascii: "\n")])
    )
    for _ in 0..<100 {
      if await transport.activeModernRequestCount == 2 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    try await Task.sleep(for: .milliseconds(100))

    #expect(await transport.activeModernRequestCount == 2)
    #expect(await transport.pendingRequestCount == 2)

    try input.fileHandleForWriting.write(
      contentsOf: wire([
        "jsonrpc": "2.0",
        "method": "notifications/cancelled",
        "params": ["requestId": 4],
      ]) + Data([UInt8(ascii: "\n")])
    )
    try await Task.sleep(for: .milliseconds(100))

    #expect(await transport.activeModernRequestCount == 2)
    #expect(await transport.pendingRequestCount == 2)

    try input.fileHandleForWriting.write(
      contentsOf: wire([
        "jsonrpc": "2.0",
        "method": "notifications/cancelled",
        "params": ["requestId": 4],
      ]) + Data([UInt8(ascii: "\n")])
    )
    try await Task.sleep(for: .milliseconds(100))

    #expect(await transport.activeModernRequestCount == 2)
    #expect(await transport.pendingRequestCount == 2)

    let outputReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).readToEnd() ?? Data()
    }
    input.fileHandleForWriting.closeFile()
    #expect(await reader.value)
    await transport.waitUntilDrained()
    for _ in 0..<500 {
      if await transport.activeModernRequestCount == 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await transport.activeModernRequestCount == 0)
    #expect(await transport.pendingRequestCount == 0)
    await transport.disconnect()
    output.fileHandleForWriting.closeFile()
    let outputData = try await outputReader.value
    let responses = try outputData.split(separator: UInt8(ascii: "\n")).map {
      try responseObject(Data($0))
    }

    #expect(responses.compactMap { $0["id"] as? Int } == [3])
  }

  @Test func nativePipeCancellationDoesNotEnterCancelledAppendTextHandler() async throws {
    let handlerEntries = ModernHandlerEntryStates()
    for id in 1...15 {
      let input = Pipe()
      let output = Pipe()
      defer {
        input.fileHandleForReading.closeFile()
        input.fileHandleForWriting.closeFile()
        output.fileHandleForReading.closeFile()
        output.fileHandleForWriting.closeFile()
      }
      let dispatcher = FleckMCPModernDispatcher(
        listTools: { [] },
        callTool: { parameters in
          let cancelledAtEntry = Task.isCancelled
          _ = try FleckMCPToolRegistry.command(for: parameters)
          await handlerEntries.record(cancelledAtEntry)
          return CallTool.Result(content: [], isError: false)
        }
      )
      let transport = FleckStdioTransport(
        transport: FleckMCPBoundedStdioTransport(
          inputDescriptor: input.fileHandleForReading.fileDescriptor,
          outputDescriptor: output.fileHandleForWriting.fileDescriptor
        ),
        modernDispatcher: dispatcher
      )
      try await transport.connect()
      let reader = Task {
        do {
          for try await _ in await transport.receive() {}
          return true
        } catch {
          return false
        }
      }
      let outputReader = Task.detached {
        try FileHandle(
          fileDescriptor: output.fileHandleForReading.fileDescriptor,
          closeOnDealloc: false
        ).readToEnd() ?? Data()
      }
      var metadata = requestMetadata()
      metadata["com.example/padding"] = String(repeating: "x", count: 900_000)
      var inputData = try request(
        method: "tools/call",
        id: id,
        params: [
          "_meta": metadata,
          "name": "append_text",
          "arguments": [
            "note_id": "00000000-0000-0000-0000-000000000001",
            "expected_revision": 1,
            "operation_id": UUID().uuidString,
            "text": "synthetic-only",
          ] as [String: Any],
        ]
      )
      inputData.append(UInt8(ascii: "\n"))
      inputData.append(
        try wire([
          "jsonrpc": "2.0",
          "method": "notifications/cancelled",
          "params": ["requestId": id],
        ])
      )
      inputData.append(UInt8(ascii: "\n"))
      try input.fileHandleForWriting.write(contentsOf: inputData)
      try await Task.sleep(for: .milliseconds(150))
      input.fileHandleForWriting.closeFile()
      await transport.waitUntilInputEnded()
      await transport.waitUntilDrained()

      #expect(await transport.pendingRequestCount == 0)
      #expect(await transport.receiveStreamIsEnded)
      #expect(await reader.value)
      await transport.disconnect()
      output.fileHandleForWriting.closeFile()
      _ = try await outputReader.value
    }
    #expect(await handlerEntries.values().allSatisfy { !$0 })
  }

  @Test func nativePipeKeepsLargeRegistryResultsInBothProtocolEras() async throws {
    let page = AgentNotePage(
      noteID: UUID(),
      title: "synthetic",
      revision: 1,
      body: String(repeating: "x", count: 400_000),
      startLine: 1,
      endLine: 1,
      totalLineCount: 1,
      nextLine: nil,
      modifiedAt: Date(timeIntervalSince1970: 0)
    )
    let workspace = AgentWorkspaceResponse.note(page: page)
    #expect(try AgentWireFraming.encode(workspace).count <= AgentWireFraming.maximumFrameBytes)
    let result = try FleckMCPToolRegistry.result(for: workspace)

    for legacy in [false, true] {
      let output = try await nativeLargeResultOutput(result: result, legacy: legacy)
      let frames: [Data] = output.split(separator: UInt8(ascii: "\n")).map {
        Data($0)
      }
      let responses = try frames.map(responseObject)
      let call = try #require(
        responses.first { ($0["id"] as? Int) == (legacy ? 2 : 1) }
      )
      let callFrame = try #require(
        frames.first { frame in
          guard let envelope = try? responseObject(frame) else { return false }
          return envelope["id"] as? Int == (legacy ? 2 : 1)
        }
      )
      let callResult = try #require(call["result"] as? [String: Any])
      let content = try #require(callResult["content"] as? [[String: Any]])
      let firstContent = try #require(content.first)
      let text = try #require(firstContent["text"] as? String)

      #expect(
        callFrame.count > FleckMCPModernDispatcher.maximumMessageBytes + 4_096
      )
      #expect(callFrame.count <= FleckMCPModernDispatcher.maximumResponseBytes)
      #expect(text.contains(String(repeating: "x", count: 400_000)))
      if !legacy {
        #expect(callResult["resultType"] as? String == "complete")
      }
    }
  }

  @Test func nativePipeCorrelatesFourLargeLegacyBatchResults() async throws {
    let page = AgentNotePage(
      noteID: UUID(),
      title: "synthetic",
      revision: 1,
      body: String(repeating: "x", count: 400_000),
      startLine: 1,
      endLine: 1,
      totalLineCount: 1,
      nextLine: nil,
      modifiedAt: Date(timeIntervalSince1970: 0)
    )
    let result = try FleckMCPToolRegistry.result(
      for: .note(page: page)
    )
    let output = try await nativeLargeLegacyBatchOutput(result: result, ids: 201...204)
    let frames: [Data] = output.split(separator: UInt8(ascii: "\n")).map { Data($0) }
    let batchFrame = frames.first { frame in
      guard let responses = try? JSONSerialization.jsonObject(with: frame) as? [[String: Any]]
      else { return false }
      return responses.compactMap { $0["id"] as? Int }.sorted() == Array(201...204)
    }
    #expect(batchFrame != nil)
    if let batchFrame,
      let responses = try? JSONSerialization.jsonObject(with: batchFrame) as? [[String: Any]]
    {
      #expect(responses.compactMap { $0["id"] as? Int }.sorted() == Array(201...204))
      #expect(responses.allSatisfy { $0["error"] == nil })
      #expect(batchFrame.count > FleckMCPModernDispatcher.maximumResponseBytes)
      #expect(batchFrame.count <= FleckMCPModernDispatcher.maximumResponseBytes * 4 + 16_384)
    }
  }

  @Test func modernConcurrencyRemainsBoundedWhileResponsesAreBlocked() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in
        CallTool.Result(
          content: [
            .text(text: String(repeating: "x", count: 100_000), annotations: nil, _meta: nil)
          ],
          isError: false
        )
      }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let reader = Task {
      do {
        for try await _ in await transport.receive() {}
      } catch {}
    }
    var batch = Data()
    for id in 1...9 {
      batch.append(
        try request(
          method: "tools/call",
          id: id,
          params: ["_meta": requestMetadata(), "name": "large"]
        )
      )
      batch.append(UInt8(ascii: "\n"))
    }
    try input.fileHandleForWriting.write(contentsOf: batch)
    try await Task.sleep(for: .milliseconds(100))

    #expect(await transport.activeModernRequestCount == 8)
    #expect(await transport.pendingRequestCount == 8)

    let outputReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).readToEnd() ?? Data()
    }
    for _ in 0..<500 {
      if await transport.pendingRequestCount == 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await transport.pendingRequestCount == 0)
    input.fileHandleForWriting.closeFile()
    await reader.value
    await transport.waitUntilDrained()
    await transport.disconnect()
    output.fileHandleForWriting.closeFile()
    let responses = try await outputReader.value.split(separator: UInt8(ascii: "\n")).map {
      try responseObject(Data($0))
    }

    #expect(responses.compactMap { $0["id"] as? Int }.sorted() == Array(1...9))
    #expect(responses.allSatisfy { $0["error"] == nil })
  }

  @Test func nativePipeReadsCancellationAndEOFDuringAdmissionSaturation()
    async throws
  {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let gate = ModernMultiRequestGate()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { parameters in
        await gate.suspend(parameters.name)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let received = ModernReceivedMessages()
    let reader = Task {
      do {
        for try await message in await transport.receive() {
          await received.append(message)
        }
      } catch {}
      await received.finish()
    }

    var requests = Data()
    for id in 1...8 {
      requests.append(
        try request(
          method: "tools/call",
          id: id,
          params: [
            "_meta": requestMetadata(),
            "name": "held-\(id)",
            "arguments": [:] as [String: Any],
          ]
        )
      )
      requests.append(UInt8(ascii: "\n"))
    }
    try input.fileHandleForWriting.write(contentsOf: requests)
    await gate.waitUntilStarted(8)

    var queuedAndCancelled = try request(
      method: "tools/call",
      id: 9,
      params: [
        "_meta": requestMetadata(),
        "name": "must-not-start",
        "arguments": [:] as [String: Any],
      ]
    )
    queuedAndCancelled.append(UInt8(ascii: "\n"))
    try input.fileHandleForWriting.write(contentsOf: queuedAndCancelled)
    for _ in 0..<100 {
      if await transport.queuedFrameCount == 1 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await transport.queuedFrameCount == 1)
    try await Task.sleep(for: .milliseconds(100))

    var delayedCancellation = try wire([
      "jsonrpc": "2.0",
      "method": "notifications/cancelled",
      "params": ["requestId": 9],
    ])
    delayedCancellation.append(UInt8(ascii: "\n"))
    try input.fileHandleForWriting.write(contentsOf: delayedCancellation)
    for _ in 0..<100 {
      if await transport.queuedFrameCount == 0 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await transport.queuedFrameCount == 0)

    var interleavedCancellations = Data()
    for id in 1...8 {
      interleavedCancellations.append(
        try wire([
          "jsonrpc": "2.0",
          "method": "notifications/cancelled",
          "params": ["requestId": id],
        ])
      )
      interleavedCancellations.append(UInt8(ascii: "\n"))
    }
    try input.fileHandleForWriting.write(contentsOf: interleavedCancellations)
    input.fileHandleForWriting.closeFile()

    for _ in 0..<150 {
      if await received.isFinished { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let eofObservedBeforeReleasingHandlers = await received.isFinished
    let pendingAfterEOF = await transport.pendingRequestCount
    let activeAfterEOF = await transport.activeModernRequestCount
    let startedBeforeRelease = await gate.startedNames()

    await gate.releaseAll()
    await reader.value
    await transport.waitUntilDrained()
    await transport.disconnect()

    #expect(eofObservedBeforeReleasingHandlers)
    #expect(pendingAfterEOF == 0)
    #expect(activeAfterEOF == 0)
    #expect(startedBeforeRelease.count == 8)
    #expect(!startedBeforeRelease.contains("must-not-start"))
  }

  @Test func nativePipeLegacySaturationUsesOneEOFDeadline() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let outputReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).readToEnd() ?? Data()
    }
    let gate = ModernMultiRequestGate()
    let server = await FleckMCPServer.makeServer(
      listTools: { [] },
      callTool: { parameters in
        await gate.suspend(parameters.name)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: FleckMCPModernDispatcher(
        listTools: { [] },
        callTool: { _ in CallTool.Result(content: [], isError: false) }
      )
    )
    try await server.start(transport: transport)
    let serverWait = Task { await server.waitUntilCompleted() }

    var messages = try wire([
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "params": [
        "protocolVersion": "2025-11-25",
        "capabilities": [:] as [String: Any],
        "clientInfo": ["name": "legacy", "version": "1"],
      ] as [String: Any],
    ])
    messages.append(UInt8(ascii: "\n"))
    messages.append(try wire(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    messages.append(UInt8(ascii: "\n"))
    for id in 2...9 {
      messages.append(
        try request(
          method: "tools/call",
          id: id,
          params: ["name": "held-\(id)", "arguments": [:] as [String: Any]]
        )
      )
      messages.append(UInt8(ascii: "\n"))
    }
    try input.fileHandleForWriting.write(contentsOf: messages)
    await gate.waitUntilStarted(8)
    try input.fileHandleForWriting.write(
      contentsOf: request(
        method: "tools/call",
        id: 10,
        params: ["name": "ninth-queued", "arguments": [:] as [String: Any]]
      ) + Data([UInt8(ascii: "\n")])
    )
    for _ in 0..<100 {
      if await transport.queuedFrameCount == 1 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await transport.activeRequestIDCount == 8)
    #expect(await transport.queuedFrameCount == 1)

    input.fileHandleForWriting.closeFile()
    await transport.waitUntilInputEnded()
    let eofObservedAt = ContinuousClock.now
    try await Task.sleep(for: .milliseconds(500))
    let drainStartedAt = ContinuousClock.now
    await transport.waitUntilDrained()
    let drainDuration = drainStartedAt.duration(to: .now)
    let eofToDrainDuration = eofObservedAt.duration(to: .now)
    let startedBeforeRelease = await gate.startedNames()
    var outputFailure: String?
    do {
      try await transport.throwOutputFailureIfAny()
    } catch {
      outputFailure = String(describing: error)
    }

    #expect(drainDuration < .seconds(2.9))
    #expect(eofToDrainDuration < .seconds(3.4))
    #expect(outputFailure != nil)
    #expect(startedBeforeRelease.count == 8)
    #expect(!startedBeforeRelease.contains("ninth-queued"))
    #expect(await transport.pendingRequestCount == 0)
    #expect(await transport.activeRequestIDCount == 0)
    #expect(await transport.activeModernRequestCount == 0)
    #expect(await transport.queuedFrameCount == 0)
    #expect(await transport.requestOwnerCount == 0)
    #expect(await transport.pendingOutputByteCount == 0)
    #expect(await transport.outputOperationCount == 0)
    #expect(await transport.rejectionOutputCount == 0)
    #expect(await transport.receiveStreamIsEnded)

    await serverWait.value
    await gate.releaseAll()
    await gate.waitUntilCompleted(8)
    await server.stop()
    output.fileHandleForWriting.closeFile()
    _ = try await outputReader.value
  }

  @Test func eofDeadlineClearsBlockedOutputOperations() async throws {
    let underlying = ModernBlockingOutputTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: FleckMCPModernDispatcher(
        listTools: { [] },
        callTool: { _ in CallTool.Result(content: [], isError: false) }
      )
    )
    try await transport.connect()
    let received = ModernReceivedMessages()
    let reader = Task {
      do {
        for try await message in await transport.receive() {
          await received.append(message)
        }
      } catch {}
      await received.finish()
    }

    await underlying.push(
      try request(
        method: "tools/call",
        id: 1,
        params: [
          "_meta": requestMetadata(),
          "name": "blocked-output",
          "arguments": [:] as [String: Any],
        ]
      )
    )
    await underlying.waitUntilSendStarted(1)
    #expect(await transport.outputOperationCount == 1)
    #expect(await transport.pendingOutputByteCount > 0)

    await underlying.finishInput()
    await transport.waitUntilInputEnded()
    try await Task.sleep(for: .milliseconds(500))
    let drainStartedAt = ContinuousClock.now
    await transport.waitUntilDrained()
    let drainDuration = drainStartedAt.duration(to: .now)

    #expect(drainDuration < .seconds(2.9))
    #expect(await transport.pendingRequestCount == 0)
    #expect(await transport.requestOwnerCount == 0)
    #expect(await transport.pendingOutputByteCount == 0)
    #expect(await transport.outputOperationCount == 0)
    #expect(await transport.rejectionOutputCount == 0)
    #expect(await transport.receiveStreamIsEnded)
    #expect(await received.isFinished)

    var outputFailure: String?
    do {
      try await transport.throwOutputFailureIfAny()
    } catch {
      outputFailure = String(describing: error)
    }
    #expect(outputFailure != nil)

    await reader.value
    await transport.disconnect()
  }

  @Test func nativePipeEOFDrainsMixedLegacyAndModernWork() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let outputReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).readToEnd() ?? Data()
    }
    let legacyGate = ModernMultiRequestGate()
    let modernGate = ModernMultiRequestGate()
    let server = await FleckMCPServer.makeServer(
      listTools: { [] },
      callTool: { parameters in
        await legacyGate.suspend(parameters.name)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: FleckMCPModernDispatcher(
        listTools: { [] },
        callTool: { parameters in
          await modernGate.suspend(parameters.name)
          return CallTool.Result(content: [], isError: false)
        }
      )
    )
    try await server.start(transport: transport)
    let serverCompletion = ModernReceivedMessages()
    let serverWait = Task {
      await server.waitUntilCompleted()
      await serverCompletion.finish()
    }

    var messages = try wire([
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "params": [
        "protocolVersion": "2025-11-25",
        "capabilities": [:] as [String: Any],
        "clientInfo": ["name": "legacy", "version": "1"],
      ] as [String: Any],
    ])
    messages.append(UInt8(ascii: "\n"))
    messages.append(try wire(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    messages.append(UInt8(ascii: "\n"))
    for id in 2...5 {
      messages.append(
        try request(
          method: "tools/call",
          id: id,
          params: ["name": "legacy-\(id)", "arguments": [:] as [String: Any]]
        )
      )
      messages.append(UInt8(ascii: "\n"))
    }
    for id in 6...9 {
      messages.append(
        try request(
          method: "tools/call",
          id: id,
          params: [
            "_meta": requestMetadata(),
            "name": "modern-\(id)",
            "arguments": [:] as [String: Any],
          ]
        )
      )
      messages.append(UInt8(ascii: "\n"))
    }
    try input.fileHandleForWriting.write(contentsOf: messages)
    await legacyGate.waitUntilStarted(4)
    await modernGate.waitUntilStarted(4)

    var queued = try request(
      method: "tools/call",
      id: 10,
      params: ["name": "queued-legacy", "arguments": [:] as [String: Any]]
    )
    queued.append(UInt8(ascii: "\n"))
    queued.append(
      try request(
        method: "tools/call",
        id: 11,
        params: [
          "_meta": requestMetadata(),
          "name": "queued-modern",
          "arguments": [:] as [String: Any],
        ]
      )
    )
    queued.append(UInt8(ascii: "\n"))
    try input.fileHandleForWriting.write(contentsOf: queued)
    for _ in 0..<100 {
      if await transport.queuedFrameCount == 2 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await transport.queuedFrameCount == 2)

    input.fileHandleForWriting.closeFile()
    await transport.waitUntilInputEnded()
    await legacyGate.waitUntilStarted(5)
    await modernGate.waitUntilStarted(5)
    await transport.waitUntilDrained()

    #expect(await serverCompletion.isFinished)
    #expect(await transport.pendingRequestCount == 0)
    #expect(await transport.activeRequestIDCount == 0)
    #expect(await transport.activeModernRequestCount == 0)
    #expect(await transport.queuedFrameCount == 0)
    #expect(await transport.requestOwnerCount == 0)
    #expect(await transport.receiveStreamIsEnded)

    await legacyGate.releaseAll()
    await modernGate.releaseAll()
    await legacyGate.waitUntilCompleted(5)
    await modernGate.waitUntilCompleted(5)
    await serverWait.value
    await server.stop()
    output.fileHandleForWriting.closeFile()
    _ = try await outputReader.value
  }

  @Test func nativePipeEOFDrainsFullQueueOfGatedModernRequests() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let outputReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).readToEnd() ?? Data()
    }
    let gate = ModernMultiRequestGate()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { parameters in
        await gate.suspend(parameters.name)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let reader = Task {
      do {
        for try await _ in await transport.receive() {}
      } catch {}
    }
    var requests = Data()
    for id in 1...40 {
      requests.append(
        try request(
          method: "tools/call",
          id: id,
          params: [
            "_meta": requestMetadata(),
            "name": "gated-\(id)",
            "arguments": [:] as [String: Any],
          ]
        )
      )
      requests.append(UInt8(ascii: "\n"))
    }
    try input.fileHandleForWriting.write(contentsOf: requests)
    await gate.waitUntilStarted(8)
    for _ in 0..<200 {
      if await transport.queuedFrameCount == 32 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await transport.activeRequestIDCount == 8)
    #expect(await transport.queuedFrameCount == 32)
    #expect(await transport.queuedRequestIDCount == 32)

    input.fileHandleForWriting.closeFile()
    await transport.waitUntilInputEnded()
    let drainStartedAt = ContinuousClock.now
    await transport.waitUntilDrained()
    let drainDuration = drainStartedAt.duration(to: .now)
    let startedBeforeRelease = await gate.startedNames()

    #expect(drainDuration < .seconds(3))
    #expect(startedBeforeRelease.count == 40)
    #expect(await transport.pendingRequestCount == 0)
    #expect(await transport.activeRequestIDCount == 0)
    #expect(await transport.activeModernRequestCount == 0)
    #expect(await transport.queuedFrameCount == 0)
    #expect(await transport.requestOwnerCount == 0)
    #expect(await transport.pendingOutputByteCount == 0)
    #expect(await transport.receiveStreamIsEnded)

    await gate.releaseAll()
    await gate.waitUntilCompleted(40)
    await reader.value
    await transport.disconnect()
    output.fileHandleForWriting.closeFile()
    let outputData = try await outputReader.value
    #expect(outputData.isEmpty)
  }

  @Test func nativePipeRejectsCancelledIDReuseAndStillObservesEOF() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let outputReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).readToEnd() ?? Data()
    }
    let gate = ModernMultiRequestGate()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { parameters in
        await gate.suspend(parameters.name)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let received = ModernReceivedMessages()
    let reader = Task {
      do {
        for try await message in await transport.receive() {
          await received.append(message)
        }
      } catch {}
      await received.finish()
    }
    try input.fileHandleForWriting.write(
      contentsOf: request(
        method: "tools/call",
        id: 1,
        params: [
          "_meta": requestMetadata(),
          "name": "held-one",
          "arguments": [:] as [String: Any],
        ]
      ) + Data([UInt8(ascii: "\n")])
    )
    await gate.waitUntilStarted(1)

    var controlAndReuse = try wire([
      "jsonrpc": "2.0",
      "method": "notifications/cancelled",
      "params": ["requestId": 1],
    ])
    controlAndReuse.append(UInt8(ascii: "\n"))
    controlAndReuse.append(try request(method: "ping", id: 1))
    controlAndReuse.append(UInt8(ascii: "\n"))
    try input.fileHandleForWriting.write(contentsOf: controlAndReuse)
    input.fileHandleForWriting.closeFile()

    for _ in 0..<150 {
      if await received.isFinished { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let eofObservedBeforeReleasingHandler = await received.isFinished
    let pendingAfterEOF = await transport.pendingRequestCount
    let activeAfterEOF = await transport.activeModernRequestCount

    await gate.releaseAll()
    await reader.value
    await transport.waitUntilDrained()
    await transport.disconnect()
    output.fileHandleForWriting.closeFile()
    let responseData = try await outputReader.value
    let responses = try responseData.split(separator: UInt8(ascii: "\n")).map {
      try responseObject(Data($0))
    }

    #expect(eofObservedBeforeReleasingHandler)
    #expect(pendingAfterEOF == 0)
    #expect(activeAfterEOF == 0)
    #expect(responses.count == 1)
    let reuseError = responses.first?["error"] as? [String: Any]
    #expect(reuseError?["code"] as? Int == -32600)
  }

  @Test func nativePipeCancellationSkipsQueuedOutputWhileReceivingMoreWork()
    async throws
  {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let firstByteReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).read(upToCount: 1) ?? Data()
    }
    let gate = ModernMultiRequestGate()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { parameters in
        if parameters.name == "first-large" {
          return CallTool.Result(
            content: [
              .text(text: String(repeating: "x", count: 2_000_000), annotations: nil, _meta: nil)
            ],
            isError: false
          )
        }
        await gate.suspend(parameters.name)
        return CallTool.Result(content: [], isError: false)
      }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let received = ModernReceivedMessages()
    let reader = Task {
      do {
        for try await message in await transport.receive() {
          await received.append(message)
        }
      } catch {}
      await received.finish()
    }
    try input.fileHandleForWriting.write(
      contentsOf: request(
        method: "tools/call",
        id: 1,
        params: [
          "_meta": requestMetadata(),
          "name": "first-large",
          "arguments": [:] as [String: Any],
        ]
      ) + Data([UInt8(ascii: "\n")])
    )
    let firstByte = try await firstByteReader.value
    #expect(!firstByte.isEmpty)

    var queuedCalls = Data()
    for id in 2...8 {
      queuedCalls.append(
        try request(
          method: "tools/call",
          id: id,
          params: [
            "_meta": requestMetadata(),
            "name": "held-\(id)",
            "arguments": [:] as [String: Any],
          ]
        )
      )
      queuedCalls.append(UInt8(ascii: "\n"))
    }
    try input.fileHandleForWriting.write(contentsOf: queuedCalls)
    await gate.waitUntilStarted(7)
    for id in 2...8 {
      await gate.release("held-\(id)")
      try await Task.sleep(for: .milliseconds(40))
    }
    try await Task.sleep(for: .milliseconds(100))

    var moreWorkAndCancellation = try request(method: "ping", id: 9)
    moreWorkAndCancellation.append(UInt8(ascii: "\n"))
    moreWorkAndCancellation.append(
      try wire([
        "jsonrpc": "2.0",
        "method": "notifications/cancelled",
        "params": ["requestId": 8],
      ])
    )
    moreWorkAndCancellation.append(UInt8(ascii: "\n"))
    try input.fileHandleForWriting.write(contentsOf: moreWorkAndCancellation)
    try await Task.sleep(for: .milliseconds(100))

    let outputReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).readToEnd() ?? Data()
    }
    for _ in 0..<500 {
      if await transport.pendingRequestCount == 0 { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let allResponsesDelivered = await transport.pendingRequestCount == 0
    input.fileHandleForWriting.closeFile()
    await reader.value
    await transport.waitUntilDrained()
    await transport.disconnect()
    output.fileHandleForWriting.closeFile()
    var outputData = firstByte
    outputData.append(try await outputReader.value)
    let responses = try outputData.split(separator: UInt8(ascii: "\n")).map {
      try responseObject(Data($0))
    }

    #expect(allResponsesDelivered)
    #expect(responses.compactMap { $0["id"] as? Int }.sorted() == Array(1...7) + [9])
  }

  @Test func eofKeepsARequestActiveUntilItsBlockedResponseIsFinished() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in
        CallTool.Result(
          content: [
            .text(text: String(repeating: "x", count: 512_000), annotations: nil, _meta: nil)
          ],
          isError: false
        )
      }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let reader = Task {
      do {
        for try await _ in await transport.receive() {}
        return true
      } catch {
        return false
      }
    }
    try input.fileHandleForWriting.write(
      contentsOf: request(
        method: "tools/call",
        id: 1,
        params: ["_meta": requestMetadata(), "name": "large"]
      ) + Data([UInt8(ascii: "\n")])
    )
    input.fileHandleForWriting.closeFile()
    let receivedEOF = await reader.value
    try await Task.sleep(for: .milliseconds(200))
    let pendingAfterEOF = await transport.pendingRequestCount
    let activeAfterEOF = await transport.activeModernRequestCount
    let drainStartedAt = ContinuousClock.now
    await transport.waitUntilDrained()
    let drainDuration = drainStartedAt.duration(to: .now)
    var outputFailure: String?
    do {
      try await transport.throwOutputFailureIfAny()
    } catch {
      outputFailure = String(describing: error)
    }

    await transport.disconnect()

    #expect(receivedEOF)
    #expect(pendingAfterEOF == 1)
    #expect(activeAfterEOF == 1)
    #expect(drainDuration < .seconds(4))
    #expect(outputFailure != nil)
  }

  @Test func cancellationAfterPartialNativeWritePreservesFollowingFrame()
    async throws
  {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let transport = FleckMCPBoundedStdioTransport(
      inputDescriptor: input.fileHandleForReading.fileDescriptor,
      outputDescriptor: output.fileHandleForWriting.fileDescriptor
    )
    try await transport.connect()
    let first = try wire([
      "jsonrpc": "2.0",
      "id": 1,
      "result": ["data": String(repeating: "x", count: 512_000)],
    ])
    let sending = Task {
      do {
        try await transport.send(first)
        return "sent"
      } catch {
        return String(describing: error)
      }
    }
    let firstByteReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).read(upToCount: 1) ?? Data()
    }
    let firstByte = try await firstByteReader.value
    #expect(!firstByte.isEmpty)
    sending.cancel()
    let outputReader = Task.detached {
      try FileHandle(
        fileDescriptor: output.fileHandleForReading.fileDescriptor,
        closeOnDealloc: false
      ).readToEnd() ?? Data()
    }
    #expect(await sending.value == "sent")
    try await transport.send(
      wire(["jsonrpc": "2.0", "id": 2, "result": ["resultType": "complete"]])
    )
    await transport.disconnect()
    output.fileHandleForWriting.closeFile()
    var outputData = firstByte
    outputData.append(try await outputReader.value)
    let frames = try outputData.split(separator: UInt8(ascii: "\n")).map {
      try responseObject(Data($0))
    }

    #expect(frames.compactMap { $0["id"] as? Int } == [1, 2])
  }

  @Test func boundedStdioClosedReaderReturnsEPIPEWithoutSignalling() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let outputDescriptor = output.fileHandleForWriting.fileDescriptor
    let transport = FleckMCPBoundedStdioTransport(
      inputDescriptor: input.fileHandleForReading.fileDescriptor,
      outputDescriptor: outputDescriptor
    )
    try await transport.connect()
    #expect(fcntl(outputDescriptor, F_GETNOSIGPIPE) == 1)
    output.fileHandleForReading.closeFile()
    do {
      try await transport.send(Data(#"{"jsonrpc":"2.0","id":1,"result":{}}"#.utf8))
      Issue.record("Expected a closed pipe write to fail")
    } catch {
      #expect(String(describing: error) == "systemCall(\(EPIPE))")
    }
    #expect(await transport.pendingOutputSendCount == 0)
    await transport.disconnect()
  }

  @Test func boundedStdioTransportFramesInputAndOutput() async throws {
    let input = Pipe()
    let output = Pipe()
    defer {
      input.fileHandleForReading.closeFile()
      input.fileHandleForWriting.closeFile()
      output.fileHandleForReading.closeFile()
      output.fileHandleForWriting.closeFile()
    }
    let transport = FleckMCPBoundedStdioTransport(
      inputDescriptor: input.fileHandleForReading.fileDescriptor,
      outputDescriptor: output.fileHandleForWriting.fileDescriptor
    )
    try await transport.connect()
    let stream = await transport.receive()
    var iterator = stream.makeAsyncIterator()
    let inbound = try request(method: "ping", id: 1)
    var inboundLine = inbound
    inboundLine.append(UInt8(ascii: "\n"))
    try input.fileHandleForWriting.write(contentsOf: inboundLine)

    #expect(try await iterator.next() == inbound)

    let outbound = Data(#"{"jsonrpc":"2.0","id":1,"result":{}}"#.utf8)
    try await transport.send(outbound)
    var expectedOutput = outbound
    expectedOutput.append(UInt8(ascii: "\n"))
    #expect(try output.fileHandleForReading.read(upToCount: expectedOutput.count) == expectedOutput)

    input.fileHandleForWriting.closeFile()
    #expect(try await iterator.next() == nil)
    await transport.disconnect()
  }

  @Test func cancellationSuppressesModernResponseAndReleasesDrain() async throws {
    let gate = ModernRequestGate()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in
        await gate.suspend()
        return CallTool.Result(content: [], isError: false)
      }
    )
    let underlying = ModernCapturingTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let received = ModernReceivedMessages()
    let reader = Task {
      do {
        for try await message in await transport.receive() {
          await received.append(message)
        }
      } catch {}
      await received.finish()
    }

    await underlying.push(
      try request(
        method: "tools/call",
        id: "cancel-me",
        params: [
          "_meta": requestMetadata(),
          "name": "write",
          "arguments": [:] as [String: Any],
        ]
      )
    )
    await gate.waitUntilStarted()
    await underlying.push(
      try wire([
        "jsonrpc": "2.0",
        "method": "notifications/cancelled",
        "params": ["requestId": "cancel-me"],
      ])
    )
    await transport.waitUntilDrained()
    #expect(await transport.pendingRequestCount == 0)
    #expect(await underlying.sentMessages().isEmpty)

    await gate.resume()
    await gate.waitUntilCompleted()
    for _ in 0..<100 {
      if await transport.activeModernRequestCount == 0 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await transport.activeModernRequestCount == 0)
    #expect(await underlying.sentMessages().isEmpty)

    await underlying.finishInput()
    await reader.value
  }

  @Test func preCancelledModernRequestsDoNotEnterToolHandlers() async throws {
    let calls = ModernHandlerCalls()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: {
        await calls.record("list")
        return []
      },
      callTool: { _ in
        await calls.record("call")
        return CallTool.Result(content: [], isError: false)
      }
    )
    let listGate = ModernRequestGate()
    let listRequest = try request(method: "tools/list", id: "cancelled-list")
    let listTask = Task {
      await listGate.suspend()
      return await dispatcher.response(for: listRequest)
    }
    await listGate.waitUntilStarted()
    listTask.cancel()
    await listGate.resume()
    #expect(await listTask.value == nil)
    #expect(await calls.values().isEmpty)

    let callGate = ModernRequestGate()
    let callRequest = try request(
      method: "tools/call",
      id: "cancelled-call",
      params: [
        "_meta": requestMetadata(),
        "name": "append_text",
        "arguments": [
          "note_id": "00000000-0000-0000-0000-000000000001",
          "expected_revision": 1,
          "operation_id": UUID().uuidString,
          "text": "synthetic-only",
        ] as [String: Any],
      ]
    )
    let callTask = Task {
      await callGate.suspend()
      return await dispatcher.response(for: callRequest)
    }
    await callGate.waitUntilStarted()
    callTask.cancel()
    await callGate.resume()
    #expect(await callTask.value == nil)
    #expect(await calls.values().isEmpty)
  }

  @Test func eofDoesNotWaitForAnUncooperativeModernHandler() async throws {
    let gate = ModernRequestGate()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in
        await gate.suspend()
        return CallTool.Result(content: [], isError: false)
      }
    )
    let underlying = ModernCapturingTransport()
    let transport = FleckStdioTransport(
      transport: underlying,
      modernDispatcher: dispatcher
    )
    try await transport.connect()
    let received = ModernReceivedMessages()
    let reader = Task {
      do {
        for try await message in await transport.receive() {
          await received.append(message)
        }
      } catch {}
      await received.finish()
    }

    await underlying.push(
      try request(
        method: "tools/call",
        id: "eof-call",
        params: [
          "_meta": requestMetadata(),
          "name": "write",
          "arguments": [:] as [String: Any],
        ]
      )
    )
    await gate.waitUntilStarted()
    await underlying.finishInput()
    for _ in 0..<100 {
      if await received.isFinished { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let drainedPromptly = await received.isFinished
    for _ in 0..<100 {
      if await transport.activeModernRequestCount == 0 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    let activeTasksAfterEOF = await transport.activeModernRequestCount

    await gate.resume()
    await gate.waitUntilCompleted()
    await transport.abortDrain()
    await reader.value

    #expect(drainedPromptly)
    #expect(activeTasksAfterEOF == 0)
    #expect(await underlying.sentMessages().isEmpty)
  }
}

private actor ModernHandlerCalls {
  private var recorded: [String] = []
  private var recordedProgressTokens: [String?] = []

  func record(_ call: String, progressToken: String? = nil) {
    recorded.append(call)
    recordedProgressTokens.append(progressToken)
  }

  func values() -> [String] { recorded }
  func progressTokens() -> [String?] { recordedProgressTokens }
}

private actor ModernHandlerEntryStates {
  private var cancelledEntries: [Bool] = []

  func record(_ cancelled: Bool) {
    cancelledEntries.append(cancelled)
  }

  func values() -> [Bool] { cancelledEntries }
}

private actor ModernCapturingTransport: Transport {
  nonisolated let logger = Logger(label: "fleck.mcp.modern.test")

  private let input: AsyncThrowingStream<Data, Error>
  private let inputContinuation: AsyncThrowingStream<Data, Error>.Continuation
  private var sent: [Data] = []
  private var sentWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init() {
    var continuation: AsyncThrowingStream<Data, Error>.Continuation!
    input = AsyncThrowingStream { continuation = $0 }
    inputContinuation = continuation
  }

  func connect() {}

  func disconnect() {
    inputContinuation.finish()
  }

  func send(_ data: Data) throws {
    sent.append(data)
    var waiting: [CheckedContinuation<Void, Never>] = []
    sentWaiters.removeAll { waiter in
      guard sent.count >= waiter.0 else { return false }
      waiting.append(waiter.1)
      return true
    }
    for waiter in waiting { waiter.resume() }
  }

  func receive() -> AsyncThrowingStream<Data, Error> { input }

  func push(_ data: Data) {
    inputContinuation.yield(data)
  }

  func finishInput() {
    inputContinuation.finish()
  }

  func sentMessages() -> [Data] { sent }

  func waitForSentCount(_ count: Int) async {
    guard sent.count < count else { return }
    await withCheckedContinuation { sentWaiters.append((count, $0)) }
  }
}

private actor ModernBlockingOutputTransport: Transport {
  nonisolated let logger = Logger(label: "fleck.mcp.blocking-output.test")

  private let input: AsyncThrowingStream<Data, Error>
  private let inputContinuation: AsyncThrowingStream<Data, Error>.Continuation
  private var sendCount = 0
  private var outputWaiters: [CheckedContinuation<Void, Error>] = []
  private var sendStartWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init() {
    var continuation: AsyncThrowingStream<Data, Error>.Continuation!
    input = AsyncThrowingStream { continuation = $0 }
    inputContinuation = continuation
  }

  func connect() {}

  func disconnect() {
    inputContinuation.finish()
    let waiters = outputWaiters
    outputWaiters.removeAll()
    for waiter in waiters { waiter.resume(throwing: CancellationError()) }
  }

  func send(_ data: Data) async throws {
    sendCount += 1
    var ready: [CheckedContinuation<Void, Never>] = []
    sendStartWaiters.removeAll { waiter in
      guard sendCount >= waiter.0 else { return false }
      ready.append(waiter.1)
      return true
    }
    for waiter in ready { waiter.resume() }
    try await withCheckedThrowingContinuation { outputWaiters.append($0) }
  }

  func receive() -> AsyncThrowingStream<Data, Error> { input }

  func push(_ data: Data) {
    inputContinuation.yield(data)
  }

  func finishInput() { inputContinuation.finish() }

  func waitUntilSendStarted(_ count: Int) async {
    guard sendCount < count else { return }
    await withCheckedContinuation { sendStartWaiters.append((count, $0)) }
  }
}

private actor ModernReceivedMessages {
  private var received: [Data] = []
  private var finished = false
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

  func append(_ message: Data) {
    received.append(message)
    var ready: [CheckedContinuation<Void, Never>] = []
    waiters.removeAll { waiter in
      guard received.count >= waiter.0 else { return false }
      ready.append(waiter.1)
      return true
    }
    for waiter in ready { waiter.resume() }
  }

  func finish() { finished = true }

  func messages() -> [Data] { received }

  var isFinished: Bool { finished }

  func waitForCount(_ count: Int) async {
    guard received.count < count else { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }
}

private actor ModernRequestGate {
  private var started = false
  private var completed = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var completionWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func suspend() async {
    started = true
    for waiter in startWaiters { waiter.resume() }
    startWaiters.removeAll()
    await withCheckedContinuation { releaseContinuation = $0 }
    completed = true
    for waiter in completionWaiters { waiter.resume() }
    completionWaiters.removeAll()
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func resume() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }

  func waitUntilCompleted() async {
    guard !completed else { return }
    await withCheckedContinuation { completionWaiters.append($0) }
  }
}

private actor ModernMultiRequestGate {
  private var names: [String] = []
  private var completedNames: [String] = []
  private var releaseContinuations: [String: CheckedContinuation<Void, Never>] = [:]
  private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var completionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  func suspend(_ name: String) async {
    names.append(name)
    var ready: [CheckedContinuation<Void, Never>] = []
    startWaiters.removeAll { waiter in
      guard names.count >= waiter.0 else { return false }
      ready.append(waiter.1)
      return true
    }
    for waiter in ready { waiter.resume() }
    await withCheckedContinuation { releaseContinuations[name] = $0 }
    completedNames.append(name)
    var completed: [CheckedContinuation<Void, Never>] = []
    completionWaiters.removeAll { waiter in
      guard completedNames.count >= waiter.0 else { return false }
      completed.append(waiter.1)
      return true
    }
    for waiter in completed { waiter.resume() }
  }

  func waitUntilStarted(_ count: Int) async {
    guard names.count < count else { return }
    await withCheckedContinuation { startWaiters.append((count, $0)) }
  }

  func waitUntilCompleted(_ count: Int) async {
    guard completedNames.count < count else { return }
    await withCheckedContinuation { completionWaiters.append((count, $0)) }
  }

  func startedNames() -> [String] { names }

  func release(_ name: String) {
    releaseContinuations.removeValue(forKey: name)?.resume()
  }

  func releaseAll() {
    let continuations = Array(releaseContinuations.values)
    releaseContinuations.removeAll()
    for continuation in continuations { continuation.resume() }
  }
}

private func request(
  method: String,
  id: Any,
  params: Any? = nil,
  jsonrpc: String = "2.0"
) throws -> Data {
  var object: [String: Any] = ["jsonrpc": jsonrpc, "id": id, "method": method]
  object["params"] = params ?? ["_meta": requestMetadata()]
  return try wire(object)
}

private func requestMetadata() -> [String: Any] {
  [
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any],
  ]
}

private func wire(_ value: Any) throws -> Data {
  try JSONSerialization.data(
    withJSONObject: value,
    options: [.fragmentsAllowed, .sortedKeys]
  )
}

private func responseObject(_ response: Data) throws -> [String: Any] {
  try #require(
    JSONSerialization.jsonObject(with: response, options: [.fragmentsAllowed])
      as? [String: Any]
  )
}

private func errorCode(_ response: Data) throws -> Int {
  let envelope = try responseObject(response)
  let error = try #require(envelope["error"] as? [String: Any])
  return try #require(error["code"] as? Int)
}

private func nativeLargeResultOutput(
  result: CallTool.Result,
  legacy: Bool
) async throws -> Data {
  let input = Pipe()
  let output = Pipe()
  defer {
    input.fileHandleForReading.closeFile()
    input.fileHandleForWriting.closeFile()
    output.fileHandleForReading.closeFile()
    output.fileHandleForWriting.closeFile()
  }
  let outputReader = Task.detached {
    try FileHandle(
      fileDescriptor: output.fileHandleForReading.fileDescriptor,
      closeOnDealloc: false
    ).readToEnd() ?? Data()
  }
  let dispatcher = FleckMCPModernDispatcher(
    listTools: { [] },
    callTool: { _ in result }
  )

  if legacy {
    let server = await FleckMCPServer.makeServer(
      listTools: { [] },
      callTool: { _ in result }
    )
    let transport = FleckStdioTransport(
      transport: FleckMCPBoundedStdioTransport(
        inputDescriptor: input.fileHandleForReading.fileDescriptor,
        outputDescriptor: output.fileHandleForWriting.fileDescriptor
      ),
      modernDispatcher: dispatcher
    )
    try await server.start(transport: transport)
    var batch = Data()
    batch.append(
      try wire([
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "protocolVersion": "2025-11-25",
          "capabilities": [:] as [String: Any],
          "clientInfo": ["name": "legacy", "version": "1"],
        ] as [String: Any],
      ])
    )
    batch.append(UInt8(ascii: "\n"))
    batch.append(try wire(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    batch.append(UInt8(ascii: "\n"))
    batch.append(
      try wire([
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": ["name": "read_note", "arguments": [:] as [String: Any]],
      ])
    )
    batch.append(UInt8(ascii: "\n"))
    try input.fileHandleForWriting.write(contentsOf: batch)
    input.fileHandleForWriting.closeFile()
    await server.waitUntilCompleted()
    await transport.waitUntilDrained()
    await server.stop()
  } else {
    let transport = FleckMCPBoundedStdioTransport(
      inputDescriptor: input.fileHandleForReading.fileDescriptor,
      outputDescriptor: output.fileHandleForWriting.fileDescriptor
    )
    try await transport.connect()
    let reader = Task {
      do {
        for try await message in await transport.receive() {
          if let response = await dispatcher.response(for: message) {
            try await transport.send(response)
          }
        }
        return nil as String?
      } catch {
        return String(describing: error)
      }
    }
    try input.fileHandleForWriting.write(
      contentsOf: request(
        method: "tools/call",
        id: 1,
        params: [
          "_meta": requestMetadata(),
          "name": "read_note",
          "arguments": [:] as [String: Any],
        ]
      ) + Data([UInt8(ascii: "\n")])
    )
    input.fileHandleForWriting.closeFile()
    let error = await reader.value
    #expect(error == nil)
    await transport.disconnect()
  }

  output.fileHandleForWriting.closeFile()
  return try await outputReader.value
}

private func nativeLargeLegacyBatchOutput(
  result: CallTool.Result,
  ids: ClosedRange<Int>
) async throws -> Data {
  let input = Pipe()
  let output = Pipe()
  defer {
    input.fileHandleForReading.closeFile()
    input.fileHandleForWriting.closeFile()
    output.fileHandleForReading.closeFile()
    output.fileHandleForWriting.closeFile()
  }
  let outputReader = Task.detached {
    try FileHandle(
      fileDescriptor: output.fileHandleForReading.fileDescriptor,
      closeOnDealloc: false
    ).readToEnd() ?? Data()
  }
  let server = await FleckMCPServer.makeServer(
    listTools: { [] },
    callTool: { _ in result }
  )
  let transport = FleckStdioTransport(
    transport: FleckMCPBoundedStdioTransport(
      inputDescriptor: input.fileHandleForReading.fileDescriptor,
      outputDescriptor: output.fileHandleForWriting.fileDescriptor
    ),
    modernDispatcher: FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in result }
    )
  )
  try await server.start(transport: transport)
  var messages = Data()
  messages.append(
    try wire([
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "params": [
        "protocolVersion": "2025-11-25",
        "capabilities": [:] as [String: Any],
        "clientInfo": ["name": "legacy", "version": "1"],
      ] as [String: Any],
    ])
  )
  messages.append(UInt8(ascii: "\n"))
  messages.append(try wire(["jsonrpc": "2.0", "method": "notifications/initialized"]))
  messages.append(UInt8(ascii: "\n"))
  messages.append(
    try wire(
      ids.map { id in
        [
          "jsonrpc": "2.0",
          "id": id,
          "method": "tools/call",
          "params": ["name": "read_note", "arguments": [:] as [String: Any]],
        ] as [String: Any]
      })
  )
  messages.append(UInt8(ascii: "\n"))
  try input.fileHandleForWriting.write(contentsOf: messages)
  input.fileHandleForWriting.closeFile()
  await server.waitUntilCompleted()
  await transport.waitUntilDrained()
  await server.stop()
  output.fileHandleForWriting.closeFile()
  return try await outputReader.value
}
