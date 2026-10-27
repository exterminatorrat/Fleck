import FleckCore
import Foundation
import MCP
import Testing

@testable import FleckAgentBridge

@Suite("Agent event modern wire server")
struct AgentEventWireServerTests {
  @Test func eventMethodsStayUnavailableWithoutHandlersAndNeverAdvertiseEvents() async throws {
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )

    for method in ["events/list", "events/subscribe", "events/unsubscribe"] {
      let response = try #require(
        await dispatcher.response(
          for: eventRequest(method: method, id: method, params: validParams(method))
        )
      )
      #expect(
        try eventErrorCode(response) == -32014,
        "\(method): \(String(decoding: response, as: UTF8.self))"
      )
      #expect(try eventErrorFeature(response) == "eventsActivation")
    }

    let discovery = try #require(
      await dispatcher.response(for: eventRequest(method: "server/discover", id: "discovery"))
    )
    let root = try #require(JSONSerialization.jsonObject(with: discovery) as? [String: Any])
    let result = try #require(root["result"] as? [String: Any])
    let capabilities = try #require(result["capabilities"] as? [String: Any])
    #expect(capabilities["events"] == nil)
    #expect(result["cacheScope"] as? String == "public")
  }

  @Test func discoveryUsesOnlyValidatedNonemptyEventCatalog() async throws {
    final class MutableAvailability: @unchecked Sendable {
      private let lock = NSLock()
      private var available = false

      func set(_ available: Bool) {
        lock.lock()
        defer { lock.unlock() }
        self.available = available
      }

      func current() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return available
      }
    }

    func validatedCatalog(_ events: [AgentEventDescriptor]) throws -> AgentWorkspaceResponse {
      let encoded = try JSONEncoder().encode(AgentWorkspaceResponse.events(events: events))
      let decoded = try JSONDecoder().decode(AgentWorkspaceResponse.self, from: encoded)
      guard case .events = decoded else { throw AgentWorkspaceError(code: .invalidOperation) }
      return decoded
    }

    let enabledCatalog = try validatedCatalog(
      AgentEventCatalog.events(noteScopeAvailable: true, folderScopeAvailable: false)
    )
    let disabledCatalog = try validatedCatalog([])
    let availability = MutableAvailability()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) },
      eventCommand: { _ in availability.current() ? enabledCatalog : disabledCatalog },
      eventAvailability: { availability.current() }
    )

    func discoveryResult(_ id: String) async throws -> [String: Any] {
      let response = try #require(
        await dispatcher.response(for: eventRequest(method: "server/discover", id: id))
      )
      let root = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
      return try #require(root["result"] as? [String: Any])
    }

    let unavailableResult = try await discoveryResult("catalog-unavailable")
    let unavailableCapabilities = try #require(
      unavailableResult["capabilities"] as? [String: Any]
    )
    #expect(unavailableCapabilities["events"] == nil)
    #expect(unavailableResult["cacheScope"] as? String == "private")
    #expect(unavailableResult["ttlMs"] as? Int == 0)

    availability.set(true)
    let enabledResult = try await discoveryResult("catalog-enabled")
    let enabledCapabilities = try #require(enabledResult["capabilities"] as? [String: Any])
    #expect(enabledCapabilities["events"] is [String: Any])
    #expect(enabledResult["cacheScope"] as? String == "private")
    #expect(enabledResult["ttlMs"] as? Int == 0)

    availability.set(false)
    let revokedResult = try await discoveryResult("catalog-revoked")
    let revokedCapabilities = try #require(revokedResult["capabilities"] as? [String: Any])
    #expect(revokedCapabilities["events"] == nil)
    #expect(revokedResult["cacheScope"] as? String == "private")
    #expect(revokedResult["ttlMs"] as? Int == 0)

    let handlerOnly = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) },
      eventCommand: { _ in .events(events: []) }
    )
    let handlerOnlyDiscovery = try #require(
      await handlerOnly.response(
        for: eventRequest(method: "server/discover", id: "catalog-handler-only")
      )
    )
    let handlerOnlyRoot = try #require(
      JSONSerialization.jsonObject(with: handlerOnlyDiscovery) as? [String: Any]
    )
    let handlerOnlyResult = try #require(handlerOnlyRoot["result"] as? [String: Any])
    #expect(handlerOnlyResult["cacheScope"] as? String == "private")
    #expect(handlerOnlyResult["ttlMs"] as? Int == 0)

    let availabilityOnly = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) },
      eventAvailability: { false }
    )
    let availabilityOnlyDiscovery = try #require(
      await availabilityOnly.response(
        for: eventRequest(method: "server/discover", id: "catalog-availability-only")
      )
    )
    let availabilityOnlyRoot = try #require(
      JSONSerialization.jsonObject(with: availabilityOnlyDiscovery) as? [String: Any]
    )
    let availabilityOnlyResult = try #require(availabilityOnlyRoot["result"] as? [String: Any])
    #expect(availabilityOnlyResult["cacheScope"] as? String == "private")
    #expect(availabilityOnlyResult["ttlMs"] as? Int == 0)
  }

  @Test func eventParametersAreStrictAndSensitiveValuesAreNotEchoed() async throws {
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    let invalidParams = [
      (
        "events/list",
        ["_meta": eventMetadata(), "unexpected": true] as [String: Any],
        -32602
      ),
      (
        "events/list",
        ["_meta": eventMetadata(), "cursor": "private-cursor"] as [String: Any],
        -32014
      ),
      (
        "events/list",
        ["_meta": eventMetadata(), "cursor": true] as [String: Any],
        -32602
      ),
      (
        "events/subscribe",
        [
          "_meta": eventMetadata(),
          "name": "unknown.event",
          "arguments": [:] as [String: Any],
          "delivery": [
            "mode": "webhook", "url": "https://private.test/hook", "secret": "private-secret",
          ],
        ] as [String: Any],
        -32011
      ),
      (
        "events/subscribe",
        [
          "_meta": eventMetadata(),
          "name": "note.updated",
          "arguments": ["note_id": "00000000-0000-4000-8000-000000000501"],
          "delivery": [
            "mode": "poll", "url": "https://private.test/hook", "secret": "private-secret",
          ],
        ] as [String: Any],
        -32014
      ),
      (
        "events/subscribe",
        [
          "_meta": eventMetadata(),
          "name": "note.updated",
          "arguments": ["note_id": "00000000-0000-4000-8000-000000000501"],
          "delivery": [
            "mode": "webhook", "url": "https://private.test/hook", "secret": "private-secret",
          ],
          "cursor": false,
        ] as [String: Any],
        -32602
      ),
      (
        "events/subscribe",
        [
          "_meta": eventMetadata(),
          "name": "note.updated",
          "arguments": ["note_id": "00000000-0000-4000-8000-000000000501"],
          "delivery": [
            "mode": "webhook", "url": "https://private.test/hook", "secret": "private-secret",
          ],
          "ttlMs": true,
        ] as [String: Any],
        -32602
      ),
      (
        "events/subscribe",
        [
          "_meta": eventMetadata(),
          "name": "note.updated",
          "arguments": ["note_id": "00000000-0000-4000-8000-000000000501"],
          "delivery": [
            "mode": "webhook", "url": "https://private.test/hook", "secret": "private-secret",
          ],
          "ttlMs": -1,
        ] as [String: Any],
        -32602
      ),
      (
        "events/subscribe",
        [
          "_meta": eventMetadata(),
          "name": "note.updated",
          "arguments": ["note_id": "00000000-0000-4000-8000-000000000501"],
          "delivery": [
            "mode": "webhook", "url": "https://private.test/hook", "secret": "private-secret",
          ],
          "ttlMs": 1.5,
        ] as [String: Any],
        -32602
      ),
      (
        "events/subscribe",
        [
          "_meta": eventMetadata(),
          "name": "note.updated",
          "arguments": ["note_id": "00000000-0000-4000-8000-000000000501"],
          "delivery": [
            "mode": "webhook", "url": "https://private.test/hook", "secret": "private-secret",
          ],
          "maxAgeMs": true,
        ] as [String: Any],
        -32602
      ),
      (
        "events/subscribe",
        [
          "_meta": eventMetadata(),
          "name": "note.updated",
          "arguments": ["note_id": "00000000-0000-4000-8000-000000000501"],
          "delivery": [
            "mode": "webhook", "url": "https://private.test/hook", "secret": "private-secret",
          ],
          "cursor": "private-cursor",
        ] as [String: Any],
        -32014
      ),
    ]

    for (method, params, expectedCode) in invalidParams {
      let response = try #require(
        await dispatcher.response(
          for: eventRequest(method: method, id: UUID().uuidString, params: params)
        )
      )
      #expect(try eventErrorCode(response) == expectedCode)
      let text = String(decoding: response, as: UTF8.self)
      #expect(!text.contains("private-secret"))
      #expect(!text.contains("private.test"))
      #expect(!text.contains("private-cursor"))
    }
  }

  @Test func wellFormedUnsupportedEventFeaturesHaveDistinctSanitizedErrors() async throws {
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) }
    )
    var paginationParams = validParams("events/list")
    paginationParams["cursor"] = "private-pagination-cursor"
    var deliveryParams = validParams("events/subscribe")
    var delivery = try #require(deliveryParams["delivery"] as? [String: Any])
    delivery["mode"] = "poll"
    deliveryParams["delivery"] = delivery
    var replayCursorParams = validParams("events/subscribe")
    replayCursorParams["cursor"] = "private-replay-cursor"
    var replayAgeParams = validParams("events/subscribe")
    replayAgeParams["cursor"] = "private-replay-cursor"
    replayAgeParams["maxAgeMs"] = 60_000
    let cases: [(String, [String: Any], String)] = [
      ("events/list", paginationParams, "pagination"),
      ("events/subscribe", deliveryParams, "delivery"),
      ("events/subscribe", replayCursorParams, "replay"),
      ("events/subscribe", replayAgeParams, "replay"),
    ]

    for (method, params, feature) in cases {
      let response = try #require(
        await dispatcher.response(
          for: eventRequest(method: method, id: method, params: params)
        )
      )
      #expect(try eventErrorCode(response) == -32014)
      #expect(try eventErrorFeature(response) == feature)
      let text = String(decoding: response, as: UTF8.self)
      #expect(!text.contains("private-pagination-cursor"))
      #expect(!text.contains("private-replay-cursor"))
      #expect(!text.contains("private.test"))
    }
  }

  @Test func replayAgeWithoutCursorIsRejectedBeforeEnteringEventHandlers() async throws {
    let recorder = EventCommandRecorder()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) },
      eventCommand: { try recorder.execute($0) }
    )
    for age in [0, 60_000] {
      for omitCursor in [false, true] {
        var params = validParams("events/subscribe")
        if omitCursor { params.removeValue(forKey: "cursor") }
        params["maxAgeMs"] = age
        let response = try #require(
          await dispatcher.response(
            for: eventRequest(method: "events/subscribe", id: "replay-age", params: params)
          )
        )
        #expect(try eventErrorCode(response) == -32014)
        #expect(try eventErrorFeature(response) == "replay")
      }
    }
    #expect(recorder.commands().isEmpty)
  }

  @Test func eventWorkspaceFailuresUseSanitizedProtocolCategories() async throws {
    let cases: [(AgentWorkspaceErrorCode, Int, String?)] = [
      (.permissionRevoked, -32012, nil),
      (.capabilityDenied, -32012, nil),
      (.noteNotFound, -32012, nil),
      (.writeTooLarge, -32013, nil),
      (.invalidPayload, -32602, nil),
      (.invalidOperation, -32014, "eventsActivation"),
      (.fleckUnavailable, -32014, "eventsActivation"),
      (.internalSaveFailure, -32603, nil),
    ]

    for (workspaceCode, expectedCode, expectedFeature) in cases {
      let dispatcher = FleckMCPModernDispatcher(
        listTools: { [] },
        callTool: { _ in CallTool.Result(content: [], isError: false) },
        eventCommand: { _ in throw AgentWorkspaceError(code: workspaceCode) }
      )
      let response = try #require(
        await dispatcher.response(
          for: eventRequest(
            method: "events/subscribe",
            id: workspaceCode.rawValue,
            params: validParams("events/subscribe")
          )
        )
      )
      #expect(try eventErrorCode(response) == expectedCode)
      #expect(try eventErrorFeature(response) == expectedFeature)
      let text = String(decoding: response, as: UTF8.self)
      #expect(!text.contains("whsec_"))
      #expect(!text.contains("example.test"))
      #expect(!text.contains("00000000-0000-4000-8000-000000000501"))
    }
  }

  @Test func callbackEndpointAndRotationFailuresUseBoundedProtocolDetails() async throws {
    let callbackFailures: [(AgentWorkspaceEventFailure.Reason, Int)] = [
      (.challengeFailed, -32015),
      (.timedOut, -32015),
      (.connectionFailed, -32015),
      (.signingKeyRotationInProgress, -32013),
    ]

    for (reason, expectedCode) in callbackFailures {
      let error = reason == .signingKeyRotationInProgress
        ? AgentWorkspaceError.signingKeyRotationInProgress(retryAfterMs: 90_000)
        : AgentWorkspaceError.callbackEndpointFailure(reason: reason)
      let dispatcher = FleckMCPModernDispatcher(
        listTools: { [] },
        callTool: { _ in CallTool.Result(content: [], isError: false) },
        eventCommand: { _ in throw error }
      )
      let response = try #require(
        await dispatcher.response(
          for: eventRequest(
            method: "events/subscribe",
            id: reason.rawValue,
            params: validParams("events/subscribe")
          )
        )
      )
      let root = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
      let details = try #require(root["error"] as? [String: Any])
      let data = try #require(details["data"] as? [String: Any])

      #expect(details["code"] as? Int == expectedCode)
      #expect(data["reason"] as? String == reason.rawValue)
      if reason == .signingKeyRotationInProgress {
        #expect(data["retryAfterMs"] as? Int == 60_000)
      } else {
        #expect(Set(data.keys) == ["reason"])
      }
      let text = String(decoding: response, as: UTF8.self)
      #expect(!text.contains("whsec_"))
      #expect(!text.contains("example.test"))
    }
  }

  @Test func cancelledEventMethodsDoNotEnterHandlersOrEmitResponses() async throws {
    for method in ["events/list", "events/subscribe", "events/unsubscribe"] {
      let recorder = EventCommandRecorder()
      let dispatcher = FleckMCPModernDispatcher(
        listTools: { [] },
        callTool: { _ in CallTool.Result(content: [], isError: false) },
        eventCommand: { try recorder.execute($0) }
      )
      let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await dispatcher.response(
          for: eventRequest(
            method: method,
            id: method,
            params: validParams(method)
          )
        )
      }

      #expect(await task.value == nil)
      #expect(recorder.commands().isEmpty)
    }
  }

  @Test func modernEventMethodsUseAuthenticatedCommandsWithoutClaimingActivation() async throws {
    let recorder = EventCommandRecorder()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) },
      eventCommand: { try recorder.execute($0) }
    )

    let listed = try #require(
      await dispatcher.response(
        for: eventRequest(
          method: "events/list", id: "event-list", params: validParams("events/list"))
      )
    )
    let listRoot = try #require(JSONSerialization.jsonObject(with: listed) as? [String: Any])
    let listResult = try #require(listRoot["result"] as? [String: Any])
    let listedEvents = try #require(listResult["events"] as? [[String: Any]])
    #expect(listResult["resultType"] as? String == "complete")
    #expect(listResult["cacheScope"] as? String == "private")
    #expect(listResult["ttlMs"] as? Int == 0)
    #expect(listedEvents.count == AgentEventCatalog.events.count)
    #expect(listedEvents.allSatisfy { $0["delivery"] as? [String] == ["webhook"] })

    let subscriptionParams = validParams("events/subscribe")
    let subscribed = try #require(
      await dispatcher.response(
        for: eventRequest(
          method: "events/subscribe", id: "event-subscribe", params: subscriptionParams)
      )
    )
    #expect(try eventErrorCode(subscribed) == -32014)
    let subscriptionText = String(decoding: subscribed, as: UTF8.self)
    #expect(!subscriptionText.contains("private-secret"))
    #expect(!subscriptionText.contains("example.test"))
    #expect(!subscriptionText.contains("evt_"))

    var minimumTTLParams = validParams("events/subscribe")
    minimumTTLParams["ttlMs"] = 0
    let minimumTTL = try #require(
      await dispatcher.response(
        for: eventRequest(
          method: "events/subscribe", id: "event-subscribe-min", params: minimumTTLParams)
      )
    )
    #expect(try eventErrorCode(minimumTTL) == -32014)

    var maximumTTLParams = validParams("events/subscribe")
    maximumTTLParams["ttlMs"] = 604_800_001
    let maximumTTL = try #require(
      await dispatcher.response(
        for: eventRequest(
          method: "events/subscribe", id: "event-subscribe-max", params: maximumTTLParams)
      )
    )
    #expect(try eventErrorCode(maximumTTL) == -32014)

    var defaultTTLParams = validParams("events/subscribe")
    defaultTTLParams.removeValue(forKey: "ttlMs")
    let defaultTTL = try #require(
      await dispatcher.response(
        for: eventRequest(
          method: "events/subscribe", id: "event-subscribe-default", params: defaultTTLParams)
      )
    )
    #expect(try eventErrorCode(defaultTTL) == -32014)

    let removed = try #require(
      await dispatcher.response(
        for: eventRequest(
          method: "events/unsubscribe",
          id: "event-unsubscribe",
          params: validParams("events/unsubscribe")
        )
      )
    )
    let removeRoot = try #require(JSONSerialization.jsonObject(with: removed) as? [String: Any])
    let removeResult = try #require(removeRoot["result"] as? [String: Any])
    #expect(removeResult["resultType"] as? String == "complete")

    let commands = recorder.commands()
    #expect(commands.count == 6)
    #expect(commands[0] == .listEvents)
    guard case .prepareEventSubscription(let subscription) = commands[1] else {
      Issue.record("Expected a typed authenticated subscription command.")
      return
    }
    #expect(subscription.event == .noteUpdated)
    #expect(
      subscription.scope
        == .note(
          noteID: UUID(
            uuidString: "00000000-0000-4000-8000-000000000501"
          )!))
    #expect(subscription.callbackURL == "https://example.test/hook")
    #expect(subscription.ttl == .milliseconds(604_800_000))
    guard case .prepareEventSubscription(let minimumSubscription) = commands[2] else {
      Issue.record("Expected a typed command with the minimum clamped TTL.")
      return
    }
    #expect(minimumSubscription.ttl == .milliseconds(60_000))
    guard case .prepareEventSubscription(let maximumSubscription) = commands[3] else {
      Issue.record("Expected a typed command with the maximum clamped TTL.")
      return
    }
    #expect(maximumSubscription.ttl == .milliseconds(604_800_000))
    guard case .prepareEventSubscription(let defaultSubscription) = commands[4] else {
      Issue.record("Expected a typed command with the default TTL.")
      return
    }
    #expect(defaultSubscription.ttl == .standard)
    guard case .removeEventSubscription(let removal) = commands[5] else {
      Issue.record("Expected a typed authenticated removal command.")
      return
    }
    #expect(removal.event == .noteUpdated)
    #expect(removal.callbackURL == "https://example.test/hook")
  }

  @Test func unsubscribeUsesOnlyOriginalEventKeyAndRejectsSubscriptionIDs() async throws {
    let recorder = EventCommandRecorder()
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) },
      eventCommand: { try recorder.execute($0) }
    )
    let valid = try #require(
      await dispatcher.response(
        for: eventRequest(
          method: "events/unsubscribe",
          id: "unsubscribe-url-only",
          params: validParams("events/unsubscribe")
        )
      )
    )
    let validRoot = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    #expect(validRoot["error"] == nil)
    #expect(validRoot["result"] is [String: Any])
    guard case .removeEventSubscription(let removed) = recorder.commands().last else {
      Issue.record("Expected unsubscribe to resolve by event key and callback URL.")
      return
    }
    #expect(removed.callbackURL == "https://example.test/hook")

    var documentedParams = validParams("events/unsubscribe")
    var documentedDelivery = try #require(documentedParams["delivery"] as? [String: Any])
    documentedDelivery["mode"] = "webhook"
    documentedParams["delivery"] = documentedDelivery
    for id in ["unsubscribe-webhook", "unsubscribe-webhook-repeat"] {
      let response = try #require(
        await dispatcher.response(
          for: eventRequest(
            method: "events/unsubscribe",
            id: id,
            params: documentedParams
          )
        )
      )
      let root = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
      #expect(root["error"] == nil)
      #expect(root["result"] is [String: Any])
    }
    guard case .removeEventSubscription(let documentedRemoval) = recorder.commands().last else {
      Issue.record("Expected the documented webhook unsubscribe to resolve by callback URL.")
      return
    }
    #expect(documentedRemoval.callbackURL == "https://example.test/hook")
    let acceptedCount = recorder.commands().count

    var extraMode = validParams("events/unsubscribe")
    var modeDelivery = try #require(extraMode["delivery"] as? [String: Any])
    modeDelivery["mode"] = "poll"
    extraMode["delivery"] = modeDelivery
    var extraSecret = validParams("events/unsubscribe")
    var secretDelivery = try #require(extraSecret["delivery"] as? [String: Any])
    secretDelivery["secret"] = "private-secret"
    extraSecret["delivery"] = secretDelivery
    var extraID = validParams("events/unsubscribe")
    extraID["subscriptionId"] = "evt_private-subscription"
    var deliveryID = validParams("events/unsubscribe")
    var idDelivery = try #require(deliveryID["delivery"] as? [String: Any])
    idDelivery["id"] = "evt_private-subscription"
    deliveryID["delivery"] = idDelivery
    var unknownDeliveryKey = validParams("events/unsubscribe")
    var unknownDelivery = try #require(unknownDeliveryKey["delivery"] as? [String: Any])
    unknownDelivery["unexpected"] = true
    unknownDeliveryKey["delivery"] = unknownDelivery
    var extraUppercaseID = validParams("events/unsubscribe")
    extraUppercaseID["subscriptionID"] = "evt_private-subscription"
    let invalidParams = [extraMode, extraSecret, extraID, deliveryID, unknownDeliveryKey, extraUppercaseID]

    for params in invalidParams {
      let response = try #require(
        await dispatcher.response(
          for: eventRequest(
            method: "events/unsubscribe",
            id: "unsubscribe-invalid",
            params: params
          )
        )
      )
      #expect(try eventErrorCode(response) == -32602)
    }
    #expect(recorder.commands().count == acceptedCount)
  }

  @Test func subscribeReturnsCompleteOnlyForVerifiedReceipt() async throws {
    let refreshBefore = Date(timeIntervalSince1970: 1_800_000_000)
    let receipt = AgentEventVerifiedSubscriptionReceipt(
      subscriptionID: "evt_" + String(repeating: "b", count: 64),
      refreshBefore: refreshBefore,
      revision: 2,
      grantRevision: 3
    )
    let recorder = EventCommandRecorder(verifiedReceipt: receipt)
    let dispatcher = FleckMCPModernDispatcher(
      listTools: { [] },
      callTool: { _ in CallTool.Result(content: [], isError: false) },
      eventCommand: { try recorder.execute($0) },
      eventAvailability: { true }
    )

    let response = try #require(
      await dispatcher.response(
        for: eventRequest(
          method: "events/subscribe",
          id: "verified-subscribe",
          params: validParams("events/subscribe")
        )
      )
    )
    let root = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
    let result = try #require(root["result"] as? [String: Any])
    #expect(result["resultType"] as? String == "complete")
    #expect(result["id"] as? String == receipt.subscriptionID)
    #expect(
      result["refreshBefore"] as? String == ISO8601DateFormatter().string(from: refreshBefore)
    )
    #expect(result["cursor"] is NSNull)
    #expect(result["truncated"] as? Bool == false)
    #expect(recorder.commands().count == 1)
  }
}

private final class EventCommandRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedCommands: [AgentWorkspaceCommand] = []
  private let verifiedReceipt: AgentEventVerifiedSubscriptionReceipt?

  init(verifiedReceipt: AgentEventVerifiedSubscriptionReceipt? = nil) {
    self.verifiedReceipt = verifiedReceipt
  }

  func execute(_ command: AgentWorkspaceCommand) throws -> AgentWorkspaceResponse {
    lock.withLock { recordedCommands.append(command) }
    switch command {
    case .listEvents:
      return .events(events: AgentEventCatalog.events)
    case .prepareEventSubscription:
      if let verifiedReceipt {
        return .verifiedEventSubscription(receipt: verifiedReceipt)
      }
      return .pendingEventSubscription(
        receipt: AgentEventPendingReceipt(
          subscriptionID: "evt_" + String(repeating: "a", count: 64),
          expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
          revision: 1,
          grantRevision: 2
        )
      )
    case .removeEventSubscription:
      return .eventUnsubscribed
    default:
      throw AgentWorkspaceError(code: .invalidOperation)
    }
  }

  func commands() -> [AgentWorkspaceCommand] {
    lock.withLock { recordedCommands }
  }
}

private func validParams(_ method: String) -> [String: Any] {
  var params: [String: Any] = ["_meta": eventMetadata()]
  switch method {
  case "events/list":
    return params
  case "events/subscribe":
    params["name"] = "note.updated"
    params["arguments"] = ["note_id": "00000000-0000-4000-8000-000000000501"]
    params["delivery"] = [
      "mode": "webhook",
      "url": "https://example.test/hook",
      "secret": "whsec_" + Data(repeating: 0x42, count: 24).base64EncodedString(),
    ]
    params["cursor"] = NSNull()
    params["ttlMs"] = NSNull()
    return params
  default:
    params["name"] = "note.updated"
    params["arguments"] = ["note_id": "00000000-0000-4000-8000-000000000501"]
    params["delivery"] = ["url": "https://example.test/hook"]
    return params
  }
}

private func eventRequest(
  method: String,
  id: String,
  params: [String: Any]? = nil
) -> Data {
  let defaultParams: [String: Any] = ["_meta": eventMetadata()]
  let request: [String: Any] = [
    "jsonrpc": "2.0",
    "id": id,
    "method": method,
    "params": params ?? defaultParams,
  ]
  return (try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])) ?? Data()
}

private func eventMetadata() -> [String: Any] {
  [
    "io.modelcontextprotocol/protocolVersion": FleckMCPModernDispatcher.modernProtocolVersion,
    "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any],
  ]
}

private func eventErrorCode(_ response: Data) throws -> Int {
  let root = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
  let error = try #require(root["error"] as? [String: Any])
  return try #require(error["code"] as? Int)
}

private func eventErrorFeature(_ response: Data) throws -> String? {
  let root = try #require(JSONSerialization.jsonObject(with: response) as? [String: Any])
  let error = try #require(root["error"] as? [String: Any])
  let data = error["data"] as? [String: Any]
  return data?["feature"] as? String
}
