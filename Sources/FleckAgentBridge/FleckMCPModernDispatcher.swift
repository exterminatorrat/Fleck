#if os(macOS)
  import CoreFoundation
  import Foundation
  import FleckCore
  import MCP

  struct FleckMCPWireID: Hashable, Sendable {
    private enum Value: Hashable, Sendable {
      case string(String)
      case number(String)
    }

    private let value: Value

    private init(_ value: Value) {
      self.value = value
    }

    static func parse(_ rawValue: Any?) -> Self? {
      if let number = rawValue as? NSNumber,
        CFGetTypeID(number) == CFBooleanGetTypeID()
      {
        return nil
      }
      if let value = rawValue as? String {
        return Self(.string(value))
      }
      guard let number = rawValue as? NSNumber else {
        return nil
      }
      return Self(.number(number.stringValue))
    }

    var jsonValue: Any {
      switch value {
      case .string(let value): value
      case .number(let value):
        (try? JSONSerialization.jsonObject(
          with: Data(value.utf8),
          options: [.fragmentsAllowed]
        )) ?? NSNull()
      }
    }
  }

  struct FleckMCPModernDispatcher: Sendable {
    typealias ToolListHandler = FleckMCPServer.ToolListHandler
    typealias ToolHandler = FleckMCPServer.ToolHandler
    typealias EventCommandHandler =
      @Sendable (AgentWorkspaceCommand) throws -> AgentWorkspaceResponse
    typealias EventAvailabilityHandler = @Sendable () -> Bool

    private enum EventCommandFailure: Error {
      case unavailable
      case workspace(AgentWorkspaceError)
      case unexpected
    }

    static let modernProtocolVersion = "2026-07-28"
    static let maximumMessageBytes = 1_048_576
    static let maximumResponseBytes = maximumMessageBytes * 4 + 16_384
    static let maximumConcurrentRequests = 8
    static let maximumBatchResponseBytes = maximumResponseBytes * maximumConcurrentRequests + 16_384

    private static let protocolVersionKey =
      "io.modelcontextprotocol/protocolVersion"
    private static let clientCapabilitiesKey =
      "io.modelcontextprotocol/clientCapabilities"
    private static let clientInfoKey = "io.modelcontextprotocol/clientInfo"
    private static let serverInfoKey = "io.modelcontextprotocol/serverInfo"
    private static let supportedMethods: Set<String> = [
      "server/discover",
      "ping",
      "tools/list",
      "tools/call",
      "events/list",
      "events/subscribe",
      "events/unsubscribe",
    ]

    private let listTools: ToolListHandler
    private let callTool: ToolHandler
    private let eventCommand: EventCommandHandler?
    private let eventAvailability: EventAvailabilityHandler?
    private let hasEventConfiguration: Bool

    init(
      listTools: @escaping ToolListHandler,
      callTool: @escaping ToolHandler,
      eventCommand: EventCommandHandler? = nil,
      eventAvailability: EventAvailabilityHandler? = nil
    ) {
      self.listTools = listTools
      self.callTool = callTool
      self.eventCommand = eventCommand
      self.eventAvailability = eventAvailability
      hasEventConfiguration = eventCommand != nil || eventAvailability != nil
    }

    func response(for data: Data) async -> Data? {
      guard data.count <= Self.maximumMessageBytes else {
        return Self.errorResponse(id: nil, code: -32600, message: "Invalid Request")
      }

      let message: Any
      do {
        message = try JSONSerialization.jsonObject(
          with: data,
          options: [.fragmentsAllowed]
        )
      } catch {
        return Self.errorResponse(id: nil, code: -32700, message: "Parse error")
      }

      guard let request = message as? [String: Any],
        request["jsonrpc"] as? String == "2.0",
        let method = request["method"] as? String
      else {
        return Self.errorResponse(id: nil, code: -32600, message: "Invalid Request")
      }
      guard request.keys.contains("id") else { return nil }
      guard let requestID = FleckMCPWireID.parse(request["id"]) else {
        return Self.errorResponse(id: nil, code: -32600, message: "Invalid Request")
      }
      guard let params = request["params"] as? [String: Any],
        let metadata = params["_meta"] as? [String: Any],
        let requestedVersion = metadata[Self.protocolVersionKey] as? String,
        metadata[Self.clientCapabilitiesKey] is [String: Any],
        Self.hasValidClientInfo(metadata)
      else {
        return Self.errorResponse(
          id: requestID,
          code: -32602,
          message: "Invalid params"
        )
      }
      guard requestedVersion == Self.modernProtocolVersion else {
        return Self.errorResponse(
          id: requestID,
          code: -32022,
          message: "Unsupported protocol version",
          data: [
            "requested": requestedVersion,
            "supported": [Self.modernProtocolVersion],
          ]
        )
      }
      guard Self.supportedMethods.contains(method) else {
        return Self.errorResponse(
          id: requestID,
          code: -32601,
          message: "Method not found"
        )
      }

      do {
        switch method {
        case "server/discover":
          guard Set(params.keys) == ["_meta"] else {
            return Self.errorResponse(
              id: requestID,
              code: -32602,
              message: "Invalid params"
            )
          }
          var capabilities: [String: Any] = ["tools": ["listChanged": false]]
          if eventCommand != nil && (eventAvailability?() ?? false) {
            capabilities["events"] = ["listChanged": false]
          }
          return Self.successResponse(
            id: requestID,
            result: [
              "resultType": "complete",
              "supportedVersions": [Self.modernProtocolVersion],
              "capabilities": capabilities,
              "_meta": Self.serverMetadata,
              "ttlMs": hasEventConfiguration ? 0 : 300_000,
              "cacheScope": hasEventConfiguration ? "private" : "public",
            ]
          )

        case "ping":
          guard Set(params.keys) == ["_meta"] else {
            return Self.errorResponse(
              id: requestID,
              code: -32602,
              message: "Invalid params"
            )
          }
          return Self.successResponse(
            id: requestID,
            result: [
              "resultType": "complete",
              "_meta": Self.serverMetadata,
            ]
          )

        case "tools/list":
          guard Set(params.keys) == ["_meta"] else {
            return Self.errorResponse(
              id: requestID,
              code: -32602,
              message: "Invalid params"
            )
          }
          try Task.checkCancellation()
          let tools = try await listTools()
          let encodedTools =
            try Self.jsonObject(
              for: tools.sorted { $0.name < $1.name }
            ) as? [[String: Any]]
          guard let encodedTools else {
            return Self.errorResponse(
              id: requestID,
              code: -32603,
              message: "Internal error"
            )
          }
          return Self.successResponse(
            id: requestID,
            result: [
              "resultType": "complete",
              "tools": encodedTools,
              "_meta": Self.serverMetadata,
              "ttlMs": 0,
              "cacheScope": "private",
            ]
          )

        case "tools/call":
          guard Set(params.keys).isSubset(of: ["_meta", "name", "arguments"]),
            let name = params["name"] as? String
          else {
            return Self.errorResponse(
              id: requestID,
              code: -32602,
              message: "Invalid params"
            )
          }
          let arguments: [String: Value]
          if let rawArguments = params["arguments"] {
            guard let object = rawArguments as? [String: Any] else {
              return Self.errorResponse(
                id: requestID,
                code: -32602,
                message: "Invalid params"
              )
            }
            let encoded = try JSONSerialization.data(
              withJSONObject: object,
              options: [.sortedKeys]
            )
            arguments = try JSONDecoder().decode(
              [String: Value].self,
              from: encoded
            )
          } else {
            arguments = [:]
          }
          try Task.checkCancellation()
          let result = try await callTool(
            CallTool.Parameters(name: name, arguments: arguments)
          )
          guard var encodedResult = try Self.jsonObject(for: result) as? [String: Any]
          else {
            return Self.errorResponse(
              id: requestID,
              code: -32603,
              message: "Internal error"
            )
          }
          encodedResult["resultType"] = "complete"
          encodedResult["_meta"] = Self.serverMetadata
          return Self.successResponse(id: requestID, result: encodedResult)

        case "events/list":
          guard Set(params.keys).isSubset(of: ["_meta", "cursor"]) else {
            return Self.invalidParamsResponse(id: requestID)
          }
          if let cursor = params["cursor"], !(cursor is NSNull) {
            guard cursor is String else {
              return Self.invalidParamsResponse(id: requestID)
            }
            return Self.unsupportedEventResponse(id: requestID, feature: "pagination")
          }
          try Task.checkCancellation()
          let response = try executeEventCommand(.listEvents)
          guard case .events(let events) = response else {
            return Self.internalErrorResponse(id: requestID)
          }
          var encodedEvents: [[String: Any]] = []
          for event in events {
            guard var encodedEvent = try Self.jsonObject(for: event) as? [String: Any] else {
              return Self.internalErrorResponse(id: requestID)
            }
            encodedEvent["delivery"] = ["webhook"]
            encodedEvents.append(encodedEvent)
          }
          return Self.successResponse(
            id: requestID,
            result: [
              "resultType": "complete",
              "events": encodedEvents,
              "_meta": Self.serverMetadata,
              "ttlMs": 0,
              "cacheScope": "private",
            ]
          )

        case "events/subscribe":
          guard
            Set(params.keys).isSubset(of: [
              "_meta", "name", "arguments", "delivery", "cursor", "ttlMs", "maxAgeMs",
            ]),
            let name = params["name"] as? String,
            let arguments = params["arguments"],
            let delivery = params["delivery"] as? [String: Any],
            Set(delivery.keys) == ["mode", "url", "secret"],
            let mode = delivery["mode"] as? String,
            let callbackURL = delivery["url"] as? String,
            let signingSecret = delivery["secret"] as? String
          else {
            return Self.invalidParamsResponse(id: requestID)
          }
          guard let event = AgentEventName(rawValue: name) else {
            return Self.errorResponse(id: requestID, code: -32011, message: "Unknown event name")
          }
          guard mode == "webhook" else {
            return Self.unsupportedEventResponse(id: requestID, feature: "delivery")
          }
          guard let scope = Self.eventScope(from: arguments) else {
            return Self.invalidParamsResponse(id: requestID)
          }
          if let cursor = params["cursor"], !(cursor is NSNull) {
            guard cursor is String else {
              return Self.invalidParamsResponse(id: requestID)
            }
            return Self.unsupportedEventResponse(id: requestID, feature: "replay")
          }
          if let maxAgeMs = params["maxAgeMs"] {
            guard Self.nonnegativeInteger(maxAgeMs) != nil else {
              return Self.invalidParamsResponse(id: requestID)
            }
            return Self.unsupportedEventResponse(id: requestID, feature: "replay")
          }
          let ttl: AgentEventSubscriptionTTL
          if let requestedTTL = params["ttlMs"] {
            if requestedTTL is NSNull {
              ttl = .milliseconds(604_800_000)
            } else {
              guard let milliseconds = Self.nonnegativeInteger(requestedTTL) else {
                return Self.invalidParamsResponse(id: requestID)
              }
              ttl = .milliseconds(min(max(milliseconds, 60_000), 604_800_000))
            }
          } else {
            ttl = .standard
          }
          let command = AgentWorkspaceCommand.prepareEventSubscription(
            request: AgentEventSubscriptionRequest(
              event: event,
              scope: scope,
              callbackURL: callbackURL,
              signingSecret: signingSecret,
              ttl: ttl
            )
          )
          guard (try? JSONEncoder().encode(command)) != nil else {
            return Self.invalidParamsResponse(id: requestID)
          }
          try Task.checkCancellation()
          let response = try executeEventCommand(command)
          guard case .verifiedEventSubscription(let receipt) = response else {
            if case .pendingEventSubscription = response {
              return Self.unsupportedEventResponse(id: requestID)
            }
            return Self.internalErrorResponse(id: requestID)
          }
          return Self.successResponse(
            id: requestID,
            result: [
              "resultType": "complete",
              "id": receipt.subscriptionID,
              "refreshBefore": ISO8601DateFormatter().string(from: receipt.refreshBefore),
              "cursor": NSNull(),
              "truncated": false,
              "_meta": Self.serverMetadata,
            ]
          )

        case "events/unsubscribe":
          guard
            Set(params.keys).isSubset(of: ["_meta", "name", "arguments", "delivery"]),
            let name = params["name"] as? String,
            let arguments = params["arguments"],
            let delivery = params["delivery"] as? [String: Any],
            (Set(delivery.keys) == ["url"] || Set(delivery.keys) == ["mode", "url"]),
            let callbackURL = delivery["url"] as? String
          else {
            return Self.invalidParamsResponse(id: requestID)
          }
          if delivery.keys.contains("mode"), delivery["mode"] as? String != "webhook" {
            return Self.invalidParamsResponse(id: requestID)
          }
          guard let event = AgentEventName(rawValue: name) else {
            return Self.errorResponse(id: requestID, code: -32011, message: "Unknown event name")
          }
          guard let scope = Self.eventScope(from: arguments) else {
            return Self.invalidParamsResponse(id: requestID)
          }
          let command = AgentWorkspaceCommand.removeEventSubscription(
            request: AgentEventUnsubscribeRequest(
              event: event,
              scope: scope,
              callbackURL: callbackURL
            )
          )
          guard (try? JSONEncoder().encode(command)) != nil else {
            return Self.invalidParamsResponse(id: requestID)
          }
          try Task.checkCancellation()
          guard case .eventUnsubscribed = try executeEventCommand(command) else {
            return Self.internalErrorResponse(id: requestID)
          }
          return Self.successResponse(
            id: requestID,
            result: [
              "resultType": "complete",
              "_meta": Self.serverMetadata,
            ]
          )

        default:
          return Self.errorResponse(
            id: requestID,
            code: -32601,
            message: "Method not found"
          )
        }
      } catch is CancellationError {
        return nil
      } catch let failure as EventCommandFailure {
        return Self.eventCommandFailureResponse(id: requestID, failure: failure)
      } catch {
        return Self.errorResponse(
          id: requestID,
          code: -32603,
          message: "Internal error"
        )
      }
    }

    static func route(
      _ data: Data,
      legacyInitialized: Bool
    ) -> Route {
      guard data.count <= maximumMessageBytes,
        let message = try? JSONSerialization.jsonObject(
          with: data,
          options: [.fragmentsAllowed]
        )
      else {
        return .modern
      }
      if legacyInitialized, let batch = message as? [[String: Any]] {
        if batch.contains(where: { Self.hasModernMetadata(in: $0) }) {
          return .modern
        }
        let requestIDs = batch.compactMap { item -> FleckMCPWireID? in
          guard item["jsonrpc"] as? String == "2.0",
            item["method"] is String,
            item.keys.contains("id")
          else {
            return nil
          }
          return FleckMCPWireID.parse(item["id"])
        }
        if !requestIDs.isEmpty { return .legacy(requestIDs, startsLegacySession: false) }
        if !batch.isEmpty,
          batch.allSatisfy({
            $0["jsonrpc"] as? String == "2.0"
              && $0["method"] is String
              && !$0.keys.contains("id")
          })
        {
          return .legacy([], startsLegacySession: false)
        }
      }
      guard let object = message as? [String: Any],
        object["jsonrpc"] as? String == "2.0",
        let method = object["method"] as? String
      else {
        return .modern
      }

      guard object.keys.contains("id") else {
        let cancellationID = (object["params"] as? [String: Any])
          .flatMap { FleckMCPWireID.parse($0["requestId"]) }
        if method == "notifications/cancelled" {
          return .notification(
            forwardToLegacy: legacyInitialized,
            cancellationID: cancellationID
          )
        }
        return .notification(
          forwardToLegacy: legacyInitialized,
          cancellationID: nil
        )
      }

      guard let requestID = FleckMCPWireID.parse(object["id"]) else {
        return .modern
      }
      let params = object["params"] as? [String: Any]
      let hasModernMetadata = Self.hasModernMetadata(in: object)
      if method == "initialize", !hasModernMetadata {
        let startsLegacySession =
          params != nil
          && (params?["protocolVersion"] == nil || params?["protocolVersion"] is String)
        return .legacy([requestID], startsLegacySession: startsLegacySession)
      }
      if method == "server/discover" || hasModernMetadata || !legacyInitialized {
        return .modern
      }
      return .legacy([requestID], startsLegacySession: false)
    }

    private func executeEventCommand(
      _ command: AgentWorkspaceCommand
    ) throws -> AgentWorkspaceResponse {
      guard let eventCommand else { throw EventCommandFailure.unavailable }
      do {
        return try eventCommand(command)
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as AgentWorkspaceError {
        throw EventCommandFailure.workspace(error)
      } catch {
        throw EventCommandFailure.unexpected
      }
    }

    private static func eventScope(from value: Any) -> AgentEventScope? {
      guard let object = value as? [String: Any],
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      else {
        return nil
      }
      return try? JSONDecoder().decode(AgentEventScope.self, from: data)
    }

    private static func nonnegativeInteger(_ value: Any) -> Int? {
      guard let number = value as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID(),
        !["f", "d"].contains(String(cString: number.objCType)),
        let integer = Int(number.stringValue),
        integer >= 0
      else {
        return nil
      }
      return integer
    }

    private static func invalidParamsResponse(id: FleckMCPWireID) -> Data {
      errorResponse(id: id, code: -32602, message: "Invalid params")
    }

    private static func unsupportedEventResponse(
      id: FleckMCPWireID,
      feature: String = "eventsActivation"
    ) -> Data {
      errorResponse(
        id: id,
        code: -32014,
        message: "Event feature is unavailable",
        data: ["feature": feature]
      )
    }

    private static func internalErrorResponse(id: FleckMCPWireID) -> Data {
      errorResponse(id: id, code: -32603, message: "Internal error")
    }

    private static func eventCommandFailureResponse(
      id: FleckMCPWireID,
      failure: EventCommandFailure
    ) -> Data {
      switch failure {
      case .unavailable:
        return unsupportedEventResponse(id: id)
      case .unexpected:
        return internalErrorResponse(id: id)
      case .workspace(let error):
        guard error.isSupported(wireVersion: 2) else {
          return internalErrorResponse(id: id)
        }
        switch error.code {
        case .invalidPayload:
          return invalidParamsResponse(id: id)
        case .permissionRevoked, .capabilityDenied, .noteNotFound:
          return errorResponse(id: id, code: -32012, message: "Permission denied")
        case .writeTooLarge:
          if error.eventFailure?.reason == .signingKeyRotationInProgress,
            let retryAfterMs = error.eventFailure?.retryAfterMs
          {
            return errorResponse(
              id: id,
              code: -32013,
              message: "Signing key rotation in progress",
              data: [
                "reason": AgentWorkspaceEventFailure.Reason.signingKeyRotationInProgress.rawValue,
                "retryAfterMs": retryAfterMs,
              ]
            )
          }
          return errorResponse(id: id, code: -32013, message: "Event capacity exceeded")
        case .internalSaveFailure:
          guard let eventFailure = error.eventFailure else {
            return internalErrorResponse(id: id)
          }
          return errorResponse(
            id: id,
            code: -32015,
            message: "Callback endpoint verification failed",
            data: ["reason": eventFailure.reason.rawValue]
          )
        case .invalidOperation, .fleckUnavailable:
          return unsupportedEventResponse(id: id)
        case .revisionConflict, .taskHandleExpired, .unsafeUndo, .responseTooLarge,
          .protocolVersionUnsupported:
          return internalErrorResponse(id: id)
        }
      }
    }

    enum Route: Sendable {
      case modern
      case legacy([FleckMCPWireID], startsLegacySession: Bool)
      case notification(forwardToLegacy: Bool, cancellationID: FleckMCPWireID?)
    }

    private static func hasModernMetadata(in request: [String: Any]) -> Bool {
      let params = request["params"] as? [String: Any]
      let reservedKeys = [protocolVersionKey, clientCapabilitiesKey, clientInfoKey]
      return [params?["_meta"] as? [String: Any], request["_meta"] as? [String: Any]]
        .contains { metadata in
          reservedKeys.contains { metadata?.keys.contains($0) == true }
        }
    }

    static func errorResponse(
      id: FleckMCPWireID?,
      code: Int,
      message: String,
      data: [String: Any]? = nil
    ) -> Data {
      var error: [String: Any] = ["code": code, "message": message]
      if let data { error["data"] = data }
      var response: [String: Any] = ["jsonrpc": "2.0", "error": error]
      if let id { response["id"] = id.jsonValue }
      return (try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]))
        ?? Data(#"{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal error"}}"#.utf8)
    }

    private static var serverMetadata: [String: Any] {
      [
        serverInfoKey: [
          "name": FleckMCPServer.name,
          "version": FleckMCPServer.version,
        ]
      ]
    }

    private static func successResponse(
      id: FleckMCPWireID,
      result: [String: Any]
    ) -> Data {
      (try? JSONSerialization.data(
        withJSONObject: [
          "jsonrpc": "2.0",
          "id": id.jsonValue,
          "result": result,
        ],
        options: [.sortedKeys]
      )) ?? errorResponse(id: id, code: -32603, message: "Internal error")
    }

    private static func jsonObject<T: Encodable>(for value: T) throws -> Any {
      let data = try JSONEncoder().encode(value)
      return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func hasValidClientInfo(_ metadata: [String: Any]) -> Bool {
      guard metadata.keys.contains(clientInfoKey) else { return true }
      guard let info = metadata[clientInfoKey] as? [String: Any],
        info["name"] is String,
        info["version"] is String
      else {
        return false
      }

      for key in ["title", "description"] where info.keys.contains(key) {
        guard info[key] is String else { return false }
      }
      if info.keys.contains("websiteUrl") {
        guard let websiteURL = info["websiteUrl"] as? String,
          Self.isURI(websiteURL)
        else {
          return false
        }
      }
      guard info.keys.contains("icons") else { return true }
      guard let icons = info["icons"] as? [[String: Any]] else { return false }
      for icon in icons {
        guard let source = icon["src"] as? String, Self.isURI(source) else {
          return false
        }
        if icon.keys.contains("mimeType"), !(icon["mimeType"] is String) {
          return false
        }
        if icon.keys.contains("sizes"), !(icon["sizes"] is [String]) {
          return false
        }
        if icon.keys.contains("theme") {
          guard let theme = icon["theme"] as? String,
            ["light", "dark"].contains(theme)
          else {
            return false
          }
        }
      }
      return true
    }

    private static func isURI(_ value: String) -> Bool {
      URLComponents(string: value)?.scheme != nil
    }
  }
#endif
