#if os(macOS)
  import FleckCore
  import FleckMCPFixtureSupport
  import Foundation
  import Testing
  import os

  @testable import FleckAgentBridge
  @testable import FleckApp

  @Suite(.serialized)
  struct AgentEventMonitoringRuntimeTests {
    @Test @MainActor func staleOwnerSummaryCannotApproveUnseenRecreatedSubscription() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let workspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let first = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          requestedTTLSeconds: 60,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        let summaries = try await fixture.runtime.ownerSummaries(workspace: workspace)
        let original = try #require(summaries.first { $0.id == first.subscriptionID })
        let originalGeneration = try #require(original.consentGenerationID)
        fixture.clock.advance(by: 60)
        let expired = try await fixture.subscriptionStore.pruneExpired(now: fixture.clock.now())
        #expect(expired.map(\.subscriptionID) == [first.subscriptionID])
        let second = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          requestedTTLSeconds: 60,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        let recreated = try #require(
          await fixture.subscriptionStore.currentSubscription(id: second.subscriptionID)
        )
        #expect(second.subscriptionID == first.subscriptionID)
        #expect(second.revision == first.revision)
        #expect(recreated.deliveryControl?.generationID != originalGeneration)

        await #expect(throws: AgentWorkspaceError(code: .revisionConflict)) {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: original.id,
            enabled: true,
            allowsAutomaticRenewal: true,
            workspaceProvider: { workspace },
            expectedConsentGenerationID: originalGeneration
          )
        }

        #expect(
          try await fixture.subscriptionStore.currentSubscription(id: second.subscriptionID)
            == recreated
        )
        #expect(recreated.deliveryControl?.enabled == false)
        #expect(recreated.deliveryControl?.allowsAutomaticRenewal == false)
        #expect(await fixture.callbackExchange.requestCount() == 0)
        #expect(await fixture.applicationExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func appCommandWaitsForOwnerApprovalAndReturnsVerifiedReceipt() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let appState = fixture.makeAppState()
        await appState.waitUntilInitialLoad()
        let commandService = AgentCommandService(
          state: appState,
          profileStore: fixture.profileStore,
          activityStore: fixture.activityStore,
          capabilityAuthority: fixture.authority,
          eventRuntime: fixture.runtime
        )
        let command = AgentWorkspaceCommand.prepareEventSubscription(
          request: AgentEventSubscriptionRequest(
            event: .noteUpdated,
            scope: .note(noteID: fixture.note.id),
            callbackURL: fixture.callbackURL,
            signingSecret: fixture.signingSecret,
            ttl: .standard
          )
        )
        let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL
        )
        let commandTask = Task {
          try await commandService.execute(
            profileID: fixture.profileID,
            credential: fixture.provisioning.credential,
            command: command
          )
        }

        var commandStage = "creating the pending subscription"
        let pendingSubscription = try await fixture.waitForSubscription(id: subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: subscriptionID,
          revision: pendingSubscription.revision
        )
        let catalogCommand = try JSONDecoder().decode(
          AgentWorkspaceCommand.self,
          from: Data(#"{"listEvents":{}}"#.utf8)
        )
        let catalogResponse = try await commandService.execute(
          profileID: fixture.profileID,
          credential: fixture.provisioning.credential,
          command: catalogCommand
        )
        guard case .events(let events) = catalogResponse else {
          Issue.record("Expected a queued event-list command to complete during owner approval.")
          return
        }
        #expect(!events.isEmpty)
        let workspace = appState.workspace
        let secondReceipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteCreated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: "https://second.runtime.example.test/events",
          signingSecret: fixture.signingSecret,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        await appState.refreshAgentEventMonitoring()
        #expect(appState.agentEventSubscriptions.count == 2)
        #expect(
          appState.agentEventSubscriptions.first(where: { $0.id == subscriptionID })?.state
            == .awaitingApproval
        )
        #expect(
          appState.agentEventSubscriptions.first(where: { $0.id == secondReceipt.subscriptionID })?
            .state == .unavailable
        )
        #expect(await fixture.callbackExchange.requestCount() == 0)

        commandStage = "waiting for owner approval"
        await appState.setAgentEventMonitoring(
          subscriptionID: subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: true,
          expectedConsentGenerationID: pendingSubscription.deliveryControl?.generationID
        )
        commandStage = "returning the owner-approved verified receipt"
        let response: AgentWorkspaceResponse
        do {
          response = try await commandTask.value
        } catch {
          if let workspaceError = error as? AgentWorkspaceError,
            workspaceError.code == .internalSaveFailure
          {
            let stored = try? await fixture.subscriptionStore.currentSubscription(
              id: subscriptionID
            )
            let callbackRequests = await fixture.callbackExchange.requestCount()
            let verificationURL = fixture.rootURL
              .appendingPathComponent("events", isDirectory: true)
              .appendingPathComponent("verification.json")
            let verificationDocument = (try? JSONSerialization.jsonObject(
              with: Data(contentsOf: verificationURL)
            )) as? [String: Any]
            let intentCount = (verificationDocument?["intents"] as? [[String: Any]])?.count ?? -1
            let proofCount = (verificationDocument?["proofs"] as? [[String: Any]])?.count ?? -1
            let diagnostic: String =
              "Test-only command stage \(commandStage): ownerControlEnabled="
                + "\(stored?.deliveryControl?.enabled == true), callbackRequests=\(callbackRequests), "
                + "persistedIntents=\(intentCount), persistedProofs=\(proofCount)."
            Issue.record(Comment(rawValue: diagnostic))
          }
          throw error
        }
        guard case .verifiedEventSubscription(let receipt) = response else {
          Issue.record("A pending subscription must not be returned as success.")
          return
        }
        #expect(receipt.subscriptionID == subscriptionID)
        #expect(receipt.refreshBefore > fixture.clock.now())
        #expect(await fixture.callbackExchange.requestCount() == 1)

        await appState.refreshAgentEventMonitoring()
        #expect(
          appState.agentEventSubscriptions.first(where: { $0.id == subscriptionID })?.state
            == .enabled
        )
        #expect(
          appState.agentEventSubscriptions.first(where: { $0.id == subscriptionID })?
            .allowsAutomaticRenewal == true
        )

        var changedWorkspace = appState.workspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title += " updated"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        appState.workspace = changedWorkspace
        try await appState.saveNow().value

        let deliveredBodies = await fixture.waitForApplicationBodies(count: 1)
        let deliveredBody = try #require(deliveredBodies.first)
        let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: deliveredBody)
        #expect(envelope.name == .noteUpdated)
        #expect(envelope.eventID.isEmpty == false)
        #expect(await fixture.applicationExchange.requestCount() == 1)
        let receiptAt = try await fixture.waitForReceiptAt(
          subscriptionID: subscriptionID,
          workspace: appState.workspace
        )
        #expect(receiptAt == fixture.clock.now())
        await appState.refreshAgentEventMonitoring()
        #expect(
          appState.agentEventSubscriptions.first(where: { $0.id == subscriptionID })?
            .lastReceiptAt == receiptAt
        )

        await appState.setAgentNotePrivate(noteID: fixture.note.id, isPrivate: true)
        #expect(
          appState.agentEventSubscriptions.first(where: { $0.id == subscriptionID })?.state
            == .unavailable
        )
        var privateWorkspace = appState.workspace
        var privateNote = try #require(privateWorkspace.notes.first)
        privateNote.title += " while private"
        privateNote.revision += 1
        privateNote.modifiedAt = fixture.clock.now().addingTimeInterval(2)
        privateWorkspace.notes[0] = privateNote
        appState.workspace = privateWorkspace
        try await appState.saveNow().value
        try await Task.sleep(for: .seconds(2.2))
        #expect(await fixture.applicationExchange.requestCount() == 1)

        fixture.clock.advance(by: 172_800)
        try await fixture.profileStore.revoke(profileID: fixture.profileID)
        await appState.setAgentEventMonitoring(
          subscriptionID: subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false
        )
        let stored = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        #expect(stored.deliveryControl?.enabled == false)
        #expect(
          appState.agentEventSubscriptions.first(where: { $0.id == subscriptionID })?.state
            == .expired
        )
        #expect(
          (try fixture.outboxStore.load()).entries.allSatisfy { $0.body == nil }
        )

        var secondWorkspace = appState.workspace
        var secondNote = try #require(secondWorkspace.notes.first)
        secondNote.title += " after pause"
        secondNote.revision += 1
        secondNote.modifiedAt = fixture.clock.now().addingTimeInterval(2)
        secondWorkspace.notes[0] = secondNote
        appState.workspace = secondWorkspace
        try await appState.saveNow().value
        try await Task.sleep(for: .seconds(2.2))
        #expect(await fixture.applicationExchange.requestCount() == 1)
        await appState.removeAgentEventMonitoringSubscription(subscriptionID: subscriptionID)
        #expect(try await fixture.subscriptionStore.currentSubscription(id: subscriptionID) == nil)
      }
    }

    @Test @MainActor
    func mcpEventSubscriptionCrossesIsolatedIPCAndHonorsOwnerApprovalAndRevocation()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture(
        approvalWaitLimit: .seconds(120)
      ) { fixture in
        let appState = fixture.makeAppState()
        await appState.waitUntilInitialLoad()
        let commandService = AgentCommandService(
          state: appState,
          profileStore: fixture.profileStore,
          activityStore: fixture.activityStore,
          capabilityAuthority: fixture.authority,
          eventRuntime: fixture.runtime
        )
        let socketFixture = try makeAgentEventIPCSocketFixture()
        defer { socketFixture.removeDirectoryIfUnchanged() }
        let endpointURL = socketFixture.endpointURL
        let server = AgentIPCServer(
          endpointURL: endpointURL,
          executeWithDisposition: { profileID, credential, command in
            try await commandService.executeForIPC(
              profileID: profileID,
              credential: credential,
              command: command
            )
          }
        )
        defer { server.stop() }
        try server.start()

        let profileID = fixture.profileID
        let credentialBase64 = fixture.provisioning.credential.base64EncodedString()
        let client = AgentWorkspaceClient(
          profileID: profileID,
          loadCredential: { _ in credentialBase64 },
          send: { request in
            try AgentIPCClient(endpointURL: endpointURL, launch: {}).send(request)
          }
        )
        let dispatcher = FleckMCPModernDispatcher(
          listTools: { FleckMCPToolRegistry.tools(for: try client.capabilities()) },
          callTool: { parameters in FleckMCPToolRegistry.call(parameters, client: client) },
          eventCommand: { command in try client.execute(command) },
          eventAvailability: {
            guard case .events(let events) = try? client.execute(.listEvents) else {
              return false
            }
            return !events.isEmpty
          }
        )
        let metadata: [String: Any] = [
          "io.modelcontextprotocol/protocolVersion":
            FleckMCPModernDispatcher.modernProtocolVersion,
          "io.modelcontextprotocol/clientCapabilities": [:] as [String: Any],
        ]
        func request(method: String, params: [String: Any]) throws -> Data {
          try JSONSerialization.data(
            withJSONObject: [
              "jsonrpc": "2.0",
              "id": UUID().uuidString,
              "method": method,
              "params": params,
            ],
            options: [.sortedKeys]
          )
        }

        let discoveryRequest = try request(
          method: "server/discover",
          params: ["_meta": metadata]
        )
        let discoveryData = try #require(
          await Task.detached {
            await dispatcher.response(for: discoveryRequest)
          }.value
        )
        let discovery = try #require(
          JSONSerialization.jsonObject(with: discoveryData) as? [String: Any]
        )
        let discoveryResult = try #require(discovery["result"] as? [String: Any])
        let capabilities = try #require(discoveryResult["capabilities"] as? [String: Any])
        #expect(capabilities["events"] != nil)

        let scope = try #require(
          JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AgentEventScope.note(noteID: fixture.note.id))
          ) as? [String: Any]
        )
        let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
          profileID: profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL
        )
        let subscribeRequest = try request(
          method: "events/subscribe",
          params: [
            "_meta": metadata,
            "name": AgentEventName.noteUpdated.rawValue,
            "arguments": scope,
            "delivery": [
              "mode": "webhook",
              "url": fixture.callbackURL,
              "secret": fixture.signingSecret,
            ],
          ]
        )
        let subscribeTask = Task.detached {
          await dispatcher.response(for: subscribeRequest)
        }
        defer { subscribeTask.cancel() }
        let pending = try await fixture.waitForSubscription(id: subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: subscriptionID,
          revision: pending.revision
        )
        #expect(pending.deliveryControl?.enabled == false)
        await appState.refreshAgentEventMonitoring()
        #expect(
          appState.agentEventSubscriptions.first(where: { $0.id == subscriptionID })?.state
            == .awaitingApproval
        )
        #expect(await fixture.callbackExchange.requestCount() == 0)
        #expect(await fixture.applicationExchange.requestCount() == 0)

        await appState.setAgentEventMonitoring(
          subscriptionID: subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: true,
          expectedConsentGenerationID: pending.deliveryControl?.generationID
        )
        let subscribeData = try #require(await subscribeTask.value)
        let subscribeResponse = try #require(
          JSONSerialization.jsonObject(with: subscribeData) as? [String: Any]
        )
        let subscribeResult = try #require(subscribeResponse["result"] as? [String: Any])
        #expect(subscribeResult["resultType"] as? String == "complete")
        #expect(subscribeResult["id"] as? String == subscriptionID)
        #expect(await fixture.callbackExchange.requestCount() == 1)

        var changedWorkspace = appState.workspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title += " MCP IPC delivery"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        appState.workspace = changedWorkspace
        try await appState.saveNow().value
        let deliveredBodies = await fixture.waitForApplicationBodies(count: 1)
        let deliveredBody = try #require(deliveredBodies.first)
        let deliveredEnvelope = try JSONDecoder().decode(
          AgentEventEnvelope.self,
          from: deliveredBody
        )
        #expect(deliveredEnvelope.name == .noteUpdated)
        #expect(await fixture.applicationExchange.requestCount() == 1)

        let cancelledCallbackURL = fixture.callbackURL + "/cancelled"
        let cancelledSubscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
          profileID: profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: cancelledCallbackURL
        )
        let cancelledSubscribeRequest = try request(
          method: "events/subscribe",
          params: [
            "_meta": metadata,
            "name": AgentEventName.noteUpdated.rawValue,
            "arguments": scope,
            "delivery": [
              "mode": "webhook",
              "url": cancelledCallbackURL,
              "secret": fixture.signingSecret,
            ],
          ]
        )
        let cancelledRequestCompletion = RuntimeTestAsyncGate()
        let cancelledSubscribeTask = Task.detached {
          let response = await dispatcher.response(for: cancelledSubscribeRequest)
          await cancelledRequestCompletion.release()
          return response
        }
        defer { cancelledSubscribeTask.cancel() }
        let cancelledPending = try await fixture.waitForSubscription(
          id: cancelledSubscriptionID
        )
        let cancellationPendingProgress = try await fixture.waitForPreparedResponseFence(
          id: cancelledSubscriptionID,
          revision: cancelledPending.revision
        )
        #expect(cancelledPending.deliveryControl?.enabled == false)
        #expect(
          cancellationPendingProgress.preparedResponseFence?.disposition == .awaitingResponse
        )
        let callbackCountBeforeCancellation = await fixture.callbackExchange.requestCount()
        let applicationCountBeforeCancellation = await fixture.applicationExchange.requestCount()

        cancelledSubscribeTask.cancel()
        var cancellationCompleted = false
        var cancelledProgress: AgentEventOutboxProgress?
        for _ in 0..<500 {
          cancellationCompleted = await cancelledRequestCompletion.hasReleased()
          cancelledProgress = try fixture.outboxStore.load().progress.first(where: {
            $0.profileID == profileID && $0.subscriptionID == cancelledSubscriptionID
          })
          if cancellationCompleted,
            cancelledProgress?.preparedResponseFence?.disposition == .failedResponse
          {
            break
          }
          try await Task.sleep(for: .milliseconds(10))
        }
        #expect(cancellationCompleted, "The cancelled MCP request must finish within five seconds.")
        #expect(
          cancelledProgress?.preparedResponseFence?.disposition == .failedResponse,
          "Cancelling the IPC request must fail its prepared-response fence."
        )
        if !cancellationCompleted {
          server.stop()
        }
        #expect(await cancelledSubscribeTask.value == nil)

        let cancelledSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: cancelledSubscriptionID)
        )
        let cancelledControl = try #require(cancelledSubscription.deliveryControl)
        let cancelledBinding = verificationBinding(for: cancelledSubscription)
        let cancelledFinalProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == profileID && $0.subscriptionID == cancelledSubscriptionID
          })
        )
        #expect(!cancelledControl.enabled)
        #expect(cancelledFinalProgress.status == .discarded)
        #expect(cancelledFinalProgress.nonDeliveryDisposition == .ownerPaused)
        #expect(cancelledFinalProgress.preparedResponseFence?.binding == cancelledBinding)
        #expect(cancelledFinalProgress.preparedResponseFence?.disposition == .failedResponse)
        #expect(!fixture.outboxService.admitsDelivery(
          binding: cancelledBinding,
          ownerDeliveryControl: cancelledControl
        ))
        #expect(try fixture.verificationStore.currentProof(for: cancelledBinding) == nil)
        #expect(await fixture.callbackExchange.requestCount() == callbackCountBeforeCancellation)
        #expect(await fixture.applicationExchange.requestCount() == applicationCountBeforeCancellation)

        try await fixture.profileStore.revoke(profileID: profileID)
        var revokedWorkspace = appState.workspace
        var revokedNote = try #require(revokedWorkspace.notes.first)
        revokedNote.title += " after profile revocation"
        revokedNote.revision += 1
        revokedNote.modifiedAt = fixture.clock.now().addingTimeInterval(2)
        revokedWorkspace.notes[0] = revokedNote
        appState.workspace = revokedWorkspace
        try await appState.saveNow().value

        var revokedProgress: AgentEventOutboxProgress?
        for _ in 0..<500 {
          revokedProgress = try fixture.outboxStore.load().progress.first(where: {
            $0.profileID == profileID && $0.subscriptionID == subscriptionID
          })
          if revokedProgress?.nonDeliveryDisposition == .profileRevoked { break }
          try await Task.sleep(for: .milliseconds(10))
        }
        #expect(revokedProgress?.status == .discarded)
        #expect(revokedProgress?.nonDeliveryDisposition == .profileRevoked)
        #expect(await fixture.applicationExchange.requestCount() == 1)
        await appState.removeAgentEventMonitoringSubscription(subscriptionID: subscriptionID)
      }
    }

    @Test @MainActor
    func preparedOwnerApprovalRequiresCurrentOutboxReadiness() async throws {
      let registrationGate = RuntimeTestAsyncGate()
      defer { Task { await registrationGate.release() } }
      try await withAgentEventMonitoringRuntimeFixture(
        afterSubscriptionCreationGate: registrationGate
      ) { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        defer { command.task.cancel() }
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        await registrationGate.waitUntilEntered()

        let beforeRegistration = try await fixture.runtime.ownerSummaries(workspace: state.workspace)
        #expect(
          beforeRegistration.first(where: { $0.id == command.subscriptionID })?.state
            == .unavailable
        )
        await #expect(throws: AgentEventOutboxError.registrationRequired) {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: command.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { await state.workspace }
          )
        }
        #expect(
          try await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl?.enabled == false
        )

        await registrationGate.release()
        let readyProgress = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        #expect(readyProgress.requiresPreparedResponseFence)
        let readyOutboxData = try Data(contentsOf: fixture.outboxStore.fileURL)
        let currentSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let binding = verificationBinding(for: currentSubscription)
        let disabledControl = try #require(currentSubscription.deliveryControl)
        #expect(!disabledControl.enabled)

        for fault in RuntimeTestPreparedReadinessFault.allCases {
          try setPreparedReadinessFault(
            fault,
            fixture: fixture,
            subscriptionID: command.subscriptionID
          )
          let unavailable = try await fixture.runtime.ownerSummaries(workspace: state.workspace)
          #expect(
            unavailable.first(where: { $0.id == command.subscriptionID })?.state == .unavailable
          )
          let expectedError: AgentEventOutboxError
          switch fault {
          case .missingProgress:
            expectedError = .registrationRequired
          case .unreadableRegistry:
            expectedError = .storageFailure
          default:
            expectedError = .sourceChanged
          }
          await #expect(throws: expectedError) {
            try await fixture.runtime.setOwnerDeliveryConsent(
              subscriptionID: command.subscriptionID,
              enabled: true,
              allowsAutomaticRenewal: false,
              workspaceProvider: { await state.workspace }
            )
          }
          let unchanged = try #require(
            await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
          )
          #expect(unchanged.deliveryControl == disabledControl)
          let unchangedControl = try #require(unchanged.deliveryControl)
          #expect(!unchangedControl.enabled)
          #expect(!fixture.outboxService.admitsDelivery(
            binding: binding,
            ownerDeliveryControl: disabledControl
          ))
          #expect(await fixture.callbackExchange.requestCount() == 0)
          #expect(try fixture.verificationStore.currentProof(for: binding) == nil)

          try readyOutboxData.write(to: fixture.outboxStore.fileURL, options: .atomic)
          let restored = try await fixture.runtime.ownerSummaries(workspace: state.workspace)
          #expect(
            restored.first(where: { $0.id == command.subscriptionID })?.state == .awaitingApproval
          )
        }

        let readySummary = try await fixture.runtime.ownerSummaries(workspace: state.workspace)
        #expect(
          readySummary.first(where: { $0.id == command.subscriptionID })?.state
            == .awaitingApproval
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let response = try await command.task.value
        guard case .verifiedEventSubscription = response else {
          Issue.record("A ready prepared subscription must complete after owner approval.")
          return
        }
        #expect(await fixture.callbackExchange.requestCount() == 1)
        #expect(try fixture.verificationStore.currentProof(for: binding) != nil)
      }
    }

    @Test @MainActor
    func failedOverlappingPreparationPreservesCurrentOwnerApprovalOrigin() async throws {
      let registrationGate = RuntimeTestAsyncGate()
      defer { Task { await registrationGate.release() } }
      try await withAgentEventMonitoringRuntimeFixture(
        afterSubscriptionCreationGate: registrationGate
      ) { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let current = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: current.subscriptionID)
        let binding = verificationBinding(for: pending)
        await registrationGate.waitUntilEntered()

        let failed = startPrepareEventSubscriptionCommand(
          fixture: fixture,
          state: state,
          signingSecret: "invalid"
        )
        guard case .failure = await failed.task.result else {
          Issue.record("The overlapping preparation with an invalid secret must fail.")
          return
        }
        let unchanged = try #require(
          await fixture.subscriptionStore.currentSubscription(id: current.subscriptionID)
        )
        #expect(verificationBinding(for: unchanged) == verificationBinding(for: pending))
        #expect(unchanged.deliveryControl?.enabled == false)
        await #expect(throws: AgentEventOutboxError.registrationRequired) {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: current.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { await state.workspace }
          )
        }
        let stillDisabled = try #require(
          await fixture.subscriptionStore.currentSubscription(id: current.subscriptionID)
        )
        #expect(stillDisabled.deliveryControl == unchanged.deliveryControl)
        #expect(await fixture.callbackExchange.requestCount() == 0)
        #expect(try fixture.verificationStore.currentProof(for: binding) == nil)

        await registrationGate.release()
        _ = try await fixture.waitForPreparedResponseFence(
          id: current.subscriptionID,
          revision: pending.revision
        )
        let ready = try await fixture.runtime.ownerSummaries(workspace: state.workspace)
        #expect(ready.first(where: { $0.id == current.subscriptionID })?.state == .awaitingApproval)
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: current.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let response = try await current.task.value
        guard case .verifiedEventSubscription = response else {
          Issue.record("The surviving preparation must complete after owner approval.")
          return
        }
        #expect(await fixture.callbackExchange.requestCount() == 1)
      }
    }

    @Test @MainActor
    func failedOverlappingPreparationCannotInvalidateCurrentOwnerApproval() async throws {
      enum Signal: Sendable, Equatable {
        case providerGateEntered
        case currentCompleted
        case failedAttemptCompleted
        case deadline
        case cancelled
      }

      let approvalWaitLimit: Duration = .seconds(5)
      let signalInbox = RuntimeTestSignalInbox<Signal>()
      let signalIterator = signalInbox
      let signalContinuation = signalInbox
      defer { signalContinuation.finish() }
      let providerGate = RuntimeTestAsyncGate(onEntry: {
        signalContinuation.yield(.providerGateEntered)
      })
      try await withAgentEventMonitoringRuntimeFixture(
        approvalWaitLimit: approvalWaitLimit
      ) { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let current = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let currentWatcher = Task {
          _ = await current.task.result
          signalContinuation.yield(.currentCompleted)
        }
        var failedAttempt: Task<AgentEventMonitoringVerificationObservation, Error>?
        var failedAttemptWatcher: Task<Void, Never>?
        var deadlineTask: Task<Void, Never>?
        var responseDisposition: (@Sendable (Bool) async -> Void)?
        var responseDispositionSettled = false

        @MainActor
        func requireSignal(
          _ expected: Signal,
          failedAttempt: Task<AgentEventMonitoringVerificationObservation, Error>?
        ) async throws {
          let signal = await withTaskCancellationHandler {
            await signalIterator.next()
          } onCancel: {
            signalContinuation.yield(.cancelled)
          }
          guard let signal else { throw CancellationError() }
          try Task.checkCancellation()
          guard signal != expected else { return }
          switch signal {
          case .currentCompleted:
            if case .failure(let error) = await current.task.result { throw error }
            Issue.record("The current request completed before the held overlap reached its gate.")
            throw RuntimeTestError.invalidFixture
          case .failedAttemptCompleted:
            if let failedAttempt,
              case .failure(let error) = await failedAttempt.result
            {
              throw error
            }
            Issue.record("The held overlap completed before its workspace-provider gate.")
            throw RuntimeTestError.invalidFixture
          case .deadline:
            Issue.record("The held-overlap gate did not enter within the fixture approval duration.")
            throw RuntimeTestError.timeout
          case .cancelled:
            throw CancellationError()
          default:
            Issue.record("The held-overlap handshake received an unexpected event.")
            throw RuntimeTestError.invalidFixture
          }
        }

        do {
          let pending = try await fixture.waitForSubscription(id: current.subscriptionID)
          let binding = verificationBinding(for: pending)
          let prearmed = try await fixture.waitForPreparedResponseFence(
            id: current.subscriptionID,
            revision: pending.revision
          )
          let oldFence = try #require(prearmed.preparedResponseFence)
          let deadline = Task {
            do {
              try await Task.sleep(for: approvalWaitLimit)
            } catch {
              return
            }
            signalContinuation.yield(.deadline)
          }
          deadlineTask = deadline
          let failedTask = Task {
            try await fixture.runtime.prepareAndVerifySubscription(
              profileID: fixture.profileID,
              event: .noteUpdated,
              scope: .note(noteID: fixture.note.id),
              callbackURL: fixture.callbackURL,
              signingSecret: fixture.signingSecret,
              requestedTTLSeconds: nil,
              expectedGrantRevision: pending.grantRevision,
              expectedTemporaryExclusionGeneration: fixture.authority
                .temporaryExclusionGeneration,
              workspaceProvider: {
                await providerGate.pause()
                throw AgentWorkspaceError(code: .invalidOperation)
              }
            )
          }
          failedAttempt = failedTask
          failedAttemptWatcher = Task {
            _ = await failedTask.result
            signalContinuation.yield(.failedAttemptCompleted)
          }
          try await requireSignal(.providerGateEntered, failedAttempt: failedTask)
          let stillCurrentBeforeApproval = try #require(
            await fixture.subscriptionStore.currentSubscription(id: current.subscriptionID)
          )
          #expect(verificationBinding(for: stillCurrentBeforeApproval) == binding)
          #expect(stillCurrentBeforeApproval.revision == pending.revision)
          #expect(stillCurrentBeforeApproval.deliveryControl?.enabled == false)
          #expect(await fixture.callbackExchange.requestCount() == 0)

          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: current.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { await state.workspace }
          )
          try Task.checkCancellation()
          try await requireSignal(.currentCompleted, failedAttempt: failedTask)
          let execution = try await current.task.value
          responseDisposition = execution.responseDisposition
          guard case .verifiedEventSubscription = execution.response,
            let disposition = responseDisposition
          else {
            Issue.record(
              "The positively bound current preparation must survive the unbound overlap."
            )
            throw RuntimeTestError.invalidFixture
          }
          let approved = try #require(
            await fixture.subscriptionStore.currentSubscription(id: current.subscriptionID)
          )
          let approvedControl = try #require(approved.deliveryControl)
          let approvedFence = try #require(
            fixture.outboxStore.load().progress.first(where: {
              $0.profileID == fixture.profileID && $0.subscriptionID == current.subscriptionID
            })?.preparedResponseFence
          )
          #expect(approvedControl.enabled)
          #expect(approvedFence.binding == binding)
          #expect(approvedFence.ownerControlGenerationID == approvedControl.generationID)
          #expect(approvedFence.originIntentID == oldFence.originIntentID)
          #expect(await fixture.callbackExchange.requestCount() == 1)

          await providerGate.release()
          try await requireSignal(.failedAttemptCompleted, failedAttempt: failedTask)
          guard case .failure(let error) = await failedTask.result,
            let workspaceError = error as? AgentWorkspaceError,
            workspaceError.code == .capabilityDenied
          else {
            Issue.record(
              "The held overlapping provider must fail before replacing the current subscription."
            )
            throw RuntimeTestError.invalidFixture
          }
          await failedAttemptWatcher?.value
          deadline.cancel()
          await deadline.value
          let unchanged = try #require(
            await fixture.subscriptionStore.currentSubscription(id: current.subscriptionID)
          )
          #expect(verificationBinding(for: unchanged) == binding)
          #expect(unchanged.revision == pending.revision)
          #expect(unchanged.deliveryControl == approvedControl)
          #expect(
            try fixture.outboxStore.load().progress.first(where: {
              $0.profileID == fixture.profileID && $0.subscriptionID == current.subscriptionID
            })?.preparedResponseFence == approvedFence
          )
          #expect(try fixture.verificationStore.currentProof(for: binding) != nil)
          await disposition(true)
          responseDispositionSettled = true
          responseDisposition = nil
          #expect(
            try fixture.outboxStore.load().progress.first(where: {
              $0.profileID == fixture.profileID && $0.subscriptionID == current.subscriptionID
            })?.preparedResponseFence == nil
          )
          #expect(await fixture.callbackExchange.requestCount() == 1)
          await currentWatcher.value
          signalContinuation.finish()
        } catch {
          current.task.cancel()
          failedAttempt?.cancel()
          await providerGate.release()
          let currentResult = await current.task.result
          _ = await failedAttempt?.result
          await currentWatcher.value
          await failedAttemptWatcher?.value
          if let deadlineTask {
            deadlineTask.cancel()
            await deadlineTask.value
          }
          if !responseDispositionSettled {
            if responseDisposition == nil,
              case .success(let execution) = currentResult
            {
              responseDisposition = execution.responseDisposition
            }
            await responseDisposition?(false)
          }
          signalContinuation.finish()
          throw error
        }
      }
    }

    @Test @MainActor
    func explicitInitialApprovalWaitsForItsOwnProducerCompletion() async throws {
      enum Signal: Sendable, Equatable {
        case beforeWaitEntered
        case setterRegistrationEntered
        case ownerWaiterRegistered
        case commandCompleted(afterSetterRegistrationRelease: Bool)
        case setterCompleted(afterRegistrationRelease: Bool)
        case deadline
        case cancelled
      }

      let approvalWaitLimit: Duration = .seconds(5)
      for allowsAutomaticRenewal in [false, true] {
        let signalInbox = RuntimeTestSignalInbox<Signal>()
        let signalIterator = signalInbox
        let signalContinuation = signalInbox
        let beforeOwnerWaitGate = RuntimeTestAsyncGate(onEntry: {
          signalContinuation.yield(.beforeWaitEntered)
        })
        let setterRegistrationGate = RuntimeTestAsyncGate(onEntry: {
          signalContinuation.yield(.setterRegistrationEntered)
        })
        let observationHook = AgentEventMonitoringRuntimeTestObservation(
          beforeInitialOwnerWait: { await beforeOwnerWaitGate.pause() },
          ownerWaiterRegistered: { signalContinuation.yield(.ownerWaiterRegistered) }
        )
        do {
          try await withAgentEventMonitoringRuntimeFixture(
            approvalWaitLimit: approvalWaitLimit,
            approvalObservationHook: observationHook
          ) { fixture in
            let state = RuntimeTestWorkspaceState(
              workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
            )
            let current = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
            let responseWatcher = Task {
              _ = await current.task.result
              signalContinuation.yield(
                .commandCompleted(
                  afterSetterRegistrationRelease: await setterRegistrationGate.hasReleased()
                )
              )
            }
            let deadlineTask = Task {
              do {
                try await Task.sleep(for: approvalWaitLimit)
              } catch {
                return
              }
              signalContinuation.yield(.deadline)
            }
            var explicitApproval: Task<Void, Error>?
            var setterWatcher: Task<Void, Never>?
            var responseDisposition: (@Sendable (Bool) async -> Void)?
            var responseDispositionSettled = false

            @MainActor
            func readSignal() async throws -> Signal {
              let signal = await withTaskCancellationHandler {
                await signalIterator.next()
              } onCancel: {
                signalContinuation.yield(.cancelled)
              }
              guard let signal else { throw CancellationError() }
              try Task.checkCancellation()
              return signal
            }

            @MainActor
            func requireSignal(_ expected: Signal) async throws {
              let signal = try await readSignal()
              guard signal != expected else { return }
              switch signal {
              case .commandCompleted:
                if case .failure(let error) = await current.task.result { throw error }
                Issue.record("The prepared request completed before its expected approval handshake.")
                throw RuntimeTestError.invalidFixture
              case .setterCompleted:
                if let explicitApproval,
                  case .failure(let error) = await explicitApproval.result
                {
                  throw error
                }
                Issue.record("The owner setter completed before its registration gate entered.")
                throw RuntimeTestError.invalidFixture
              case .deadline:
                Issue.record("The approval handshake exceeded the fixture's five-second duration.")
                throw RuntimeTestError.timeout
              case .cancelled:
                throw CancellationError()
              default:
                Issue.record("The approval handshake received an unexpected event.")
                throw RuntimeTestError.invalidFixture
              }
            }

            @MainActor
            func requireSuccessfulTerminalSignals() async throws {
              var commandCompleted = false
              var setterCompleted = false
              while !commandCompleted || !setterCompleted {
                switch try await readSignal() {
                case .commandCompleted(let afterSetterRegistrationRelease):
                  guard afterSetterRegistrationRelease else {
                    Issue.record("The prepared response completed before setter registration resumed.")
                    throw RuntimeTestError.invalidFixture
                  }
                  commandCompleted = true
                case .setterCompleted(let afterRegistrationRelease):
                  guard afterRegistrationRelease else {
                    Issue.record("The owner setter completed before its registration gate resumed.")
                    throw RuntimeTestError.invalidFixture
                  }
                  setterCompleted = true
                case .deadline:
                  Issue.record("The approval handshake exceeded the fixture's five-second duration.")
                  throw RuntimeTestError.timeout
                case .cancelled:
                  throw CancellationError()
                default:
                  Issue.record("The prepared response terminal handshake received an unexpected event.")
                  throw RuntimeTestError.invalidFixture
                }
              }
            }

            do {
              try await requireSignal(.beforeWaitEntered)
              let pending = try #require(
                await fixture.subscriptionStore.currentSubscription(id: current.subscriptionID)
              )
              let binding = verificationBinding(for: pending)
              let prearmControl = try #require(pending.deliveryControl)
              #expect(prearmControl.binding == binding)
              #expect(!prearmControl.enabled)
              #expect(!prearmControl.allowsAutomaticRenewal)
              let prearmedFence = try #require(
                fixture.outboxStore.load().progress.first(where: {
                  $0.profileID == fixture.profileID && $0.subscriptionID == current.subscriptionID
                })?.preparedResponseFence
              )
              #expect(prearmedFence.binding == binding)
              #expect(prearmedFence.ownerControlGenerationID == prearmControl.generationID)

              await fixture.snapshotReaderGate.pauseNextRead(until: setterRegistrationGate)
              let approval = Task {
                try await fixture.runtime.setOwnerDeliveryConsent(
                  subscriptionID: current.subscriptionID,
                  enabled: true,
                  allowsAutomaticRenewal: allowsAutomaticRenewal,
                  workspaceProvider: { await state.workspace }
                )
              }
              explicitApproval = approval
              setterWatcher = Task {
                _ = await approval.result
                signalContinuation.yield(
                  .setterCompleted(
                    afterRegistrationRelease: await setterRegistrationGate.hasReleased()
                  )
                )
              }
              try await requireSignal(.setterRegistrationEntered)
              let persisted = try #require(
                await fixture.subscriptionStore.currentSubscription(id: current.subscriptionID)
              )
              let persistedControl = try #require(persisted.deliveryControl)
              #expect(verificationBinding(for: persisted) == binding)
              #expect(persistedControl.binding == binding)
              #expect(persistedControl.enabled)
              #expect(persistedControl.allowsAutomaticRenewal == allowsAutomaticRenewal)
              #expect(persistedControl.generationID != prearmControl.generationID)
              #expect(
                fixture.subscriptionStore.isCurrentOwnerDeliveryControl(
                  binding: binding,
                  control: persistedControl
                )
              )
              let persistedFence = try #require(
                fixture.outboxStore.load().progress.first(where: {
                  $0.profileID == fixture.profileID && $0.subscriptionID == current.subscriptionID
                })?.preparedResponseFence
              )
              #expect(persistedFence.binding == binding)
              #expect(persistedFence.ownerControlGenerationID == persistedControl.generationID)

              await beforeOwnerWaitGate.release()
              try await requireSignal(.ownerWaiterRegistered)
              #expect(await fixture.callbackExchange.requestCount() == 0)
              #expect(await fixture.applicationExchange.requestCount() == 0)

              await setterRegistrationGate.release()
              try Task.checkCancellation()
              try await requireSuccessfulTerminalSignals()
              deadlineTask.cancel()
              await deadlineTask.value
              try await approval.value
              let execution = try await current.task.value
              responseDisposition = execution.responseDisposition
              guard case .verifiedEventSubscription = execution.response,
                let disposition = responseDisposition
              else {
                Issue.record("The explicit approval must complete the prepared request.")
                throw RuntimeTestError.invalidFixture
              }
              let approved = try #require(
                await fixture.subscriptionStore.currentSubscription(id: current.subscriptionID)
              )
              let approvedControl = try #require(approved.deliveryControl)
              let approvedFence = try #require(
                fixture.outboxStore.load().progress.first(where: {
                  $0.profileID == fixture.profileID && $0.subscriptionID == current.subscriptionID
                })?.preparedResponseFence
              )
              #expect(approvedControl == persistedControl)
              #expect(approvedFence.binding == binding)
              #expect(approvedFence.ownerControlGenerationID == approvedControl.generationID)
              #expect(approvedFence.originIntentID == prearmedFence.originIntentID)
              #expect(await fixture.callbackExchange.requestCount() == 1)
              #expect(await fixture.applicationExchange.requestCount() == 0)
              await disposition(true)
              responseDispositionSettled = true
              responseDisposition = nil
              #expect(
                try fixture.outboxStore.load().progress.first(where: {
                  $0.profileID == fixture.profileID && $0.subscriptionID == current.subscriptionID
                })?.preparedResponseFence == nil
              )
              await responseWatcher.value
              await setterWatcher?.value
              signalContinuation.finish()
            } catch {
              current.task.cancel()
              explicitApproval?.cancel()
              await beforeOwnerWaitGate.release()
              await setterRegistrationGate.release()
              let currentResult = await current.task.result
              _ = await explicitApproval?.result
              await responseWatcher.value
              await setterWatcher?.value
              deadlineTask.cancel()
              await deadlineTask.value
              if !responseDispositionSettled {
                if responseDisposition == nil,
                  case .success(let execution) = currentResult
                {
                  responseDisposition = execution.responseDisposition
                }
                await responseDisposition?(false)
              }
              signalContinuation.finish()
              throw error
            }
          }
        } catch {
          signalContinuation.finish()
          throw error
        }
      }
    }

    @Test @MainActor
    func completedInitialPhaseCannotRebindFailedFenceToIndependentOwnerGeneration() async throws {
      enum Signal: Sendable, Equatable {
        case beforeWaitEntered
        case commandCompleted(afterWaitGateRelease: Bool)
        case deadline
        case cancelled
      }

      let approvalWaitLimit: Duration = .seconds(5)
      let signalInbox = RuntimeTestSignalInbox<Signal>()
      let signalIterator = signalInbox
      let signalContinuation = signalInbox
      defer { signalContinuation.finish() }
      let beforeOwnerWaitGate = RuntimeTestAsyncGate(onEntry: {
        signalContinuation.yield(.beforeWaitEntered)
      })
      let observationHook = AgentEventMonitoringRuntimeTestObservation(
        beforeInitialOwnerWait: { await beforeOwnerWaitGate.pause() },
        ownerWaiterRegistered: {}
      )

      try await withAgentEventMonitoringRuntimeFixture(
        approvalWaitLimit: approvalWaitLimit,
        approvalObservationHook: observationHook
      ) { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let setupRuntime = fixture.makeReopenedRuntime()
        var setupRuntimeStopped = false
        let setupService = AgentCommandService(
          state: state,
          profileStore: fixture.profileStore,
          activityStore: fixture.activityStore,
          capabilityAuthority: fixture.authority,
          eventRuntime: setupRuntime,
          now: { fixture.clock.now() }
        )
        let setupCommand = AgentWorkspaceCommand.prepareEventSubscription(
          request: AgentEventSubscriptionRequest(
            event: .noteUpdated,
            scope: .note(noteID: fixture.note.id),
            callbackURL: fixture.callbackURL,
            signingSecret: fixture.signingSecret,
            ttl: .standard
          )
        )
        let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL
        )
        let setupTask = Task {
          try await setupService.execute(
            profileID: fixture.profileID,
            credential: fixture.provisioning.credential,
            command: setupCommand
          )
        }
        var currentTask: Task<AgentEventMonitoringVerificationObservation, Error>?
        var commandWatcher: Task<Void, Never>?
        var deadlineTask: Task<Void, Never>?
        var responseLease: AgentEventResponseLease?
        var responseLeaseSettled = false

        @MainActor
        func readSignal() async throws -> Signal {
          let signal = await withTaskCancellationHandler {
            await signalIterator.next()
          } onCancel: {
            signalContinuation.yield(.cancelled)
          }
          guard let signal else { throw CancellationError() }
          try Task.checkCancellation()
          return signal
        }

        @MainActor
        func requireSignal(
          _ expected: Signal,
          commandTask: Task<AgentEventMonitoringVerificationObservation, Error>?
        ) async throws {
          let signal = try await readSignal()
          guard signal != expected else { return }
          switch signal {
          case .commandCompleted:
            if let commandTask, case .failure(let error) = await commandTask.result {
              throw error
            }
            Issue.record("The carried request completed before its expected wait-gate handshake.")
            throw RuntimeTestError.invalidFixture
          case .deadline:
            Issue.record("The carried-request handshake exceeded the fixture's five-second duration.")
            throw RuntimeTestError.timeout
          case .cancelled:
            throw CancellationError()
          default:
            Issue.record("The carried-request handshake received an unexpected event.")
            throw RuntimeTestError.invalidFixture
          }
        }

        do {
          let setupPending = try await fixture.waitForSubscription(id: subscriptionID)
          _ = try await fixture.waitForPreparedResponseFence(
            id: subscriptionID,
            revision: setupPending.revision,
            observingRuntime: setupRuntime
          )
          try await setupRuntime.setOwnerDeliveryConsent(
            subscriptionID: subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: true,
            workspaceProvider: { await state.workspace }
          )
          guard case .verifiedEventSubscription = try await setupTask.value else {
            Issue.record("The initial prepared request must establish renewable owner control.")
            throw RuntimeTestError.invalidFixture
          }
          await setupRuntime.stop()
          setupRuntimeStopped = true
          let initialSubscription = try #require(
            await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
          )
          let initialControl = try #require(initialSubscription.deliveryControl)
          #expect(initialControl.enabled)
          #expect(initialControl.allowsAutomaticRenewal)

          let callbackCountBeforeR1 = await fixture.callbackExchange.requestCount()
          let applicationCountBeforeR1 = await fixture.applicationExchange.requestCount()
          let deadline = Task {
            do {
              try await Task.sleep(for: approvalWaitLimit)
            } catch {
              return
            }
            signalContinuation.yield(.deadline)
          }
          deadlineTask = deadline
          let carriedTask = Task {
            try await fixture.runtime.prepareAndVerifySubscription(
              profileID: fixture.profileID,
              event: .noteUpdated,
              scope: .note(noteID: fixture.note.id),
              callbackURL: fixture.callbackURL,
              signingSecret: fixture.signingSecret,
              requestedTTLSeconds: nil,
              expectedGrantRevision: setupPending.grantRevision,
              expectedTemporaryExclusionGeneration: fixture.authority
                .temporaryExclusionGeneration,
              workspaceProvider: { await state.workspace }
            )
          }
          currentTask = carriedTask
          commandWatcher = Task {
            _ = await carriedTask.result
            signalContinuation.yield(
              .commandCompleted(afterWaitGateRelease: await beforeOwnerWaitGate.hasReleased())
            )
          }
          try await requireSignal(.beforeWaitEntered, commandTask: carriedTask)
          let pending = try #require(
            await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
          )
          let binding = verificationBinding(for: pending)
          let carriedControl = try #require(pending.deliveryControl)
          #expect(carriedControl.binding == binding)
          #expect(carriedControl.enabled)
          #expect(carriedControl.allowsAutomaticRenewal)
          let prearmedFence = try #require(
            fixture.outboxStore.load().progress.first(where: {
              $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
            })?.preparedResponseFence
          )
          #expect(prearmedFence.binding == binding)
          #expect(prearmedFence.ownerControlGenerationID == carriedControl.generationID)
          #expect(prearmedFence.disposition == .awaitingResponse)

          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: subscriptionID,
            enabled: false,
            allowsAutomaticRenewal: false,
            workspaceProvider: nil
          )
          let paused = try #require(
            await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
          )
          let pausedControl = try #require(paused.deliveryControl)
          #expect(verificationBinding(for: paused) == binding)
          #expect(!pausedControl.enabled)
          #expect(pausedControl.generationID != carriedControl.generationID)

          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { await state.workspace }
          )
          let independent = try #require(
            await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
          )
          let independentControl = try #require(independent.deliveryControl)
          #expect(verificationBinding(for: independent) == binding)
          #expect(independentControl.enabled)
          #expect(!independentControl.allowsAutomaticRenewal)
          #expect(independentControl.generationID != pausedControl.generationID)
          #expect(independentControl.generationID != carriedControl.generationID)
          #expect(
            fixture.subscriptionStore.isCurrentOwnerDeliveryControl(
              binding: binding,
              control: independentControl
            )
          )

          let failedFenceBeforeRelease = try #require(
            fixture.outboxStore.load().progress.first(where: {
              $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
            })?.preparedResponseFence
          )
          var expectedFailedFence = prearmedFence
          expectedFailedFence.disposition = .failedResponse
          #expect(failedFenceBeforeRelease == expectedFailedFence)
          #expect(
            fixture.outboxService.admitsDelivery(
              binding: binding,
              ownerDeliveryControl: independentControl
            )
          )
          let outboxBytesBeforeRelease = try Data(contentsOf: fixture.outboxStore.fileURL)

          await beforeOwnerWaitGate.release()
          try await requireSignal(
            .commandCompleted(afterWaitGateRelease: true),
            commandTask: carriedTask
          )
          deadline.cancel()
          await deadline.value
          let carriedResult = await carriedTask.result
          switch carriedResult {
          case .failure(let error):
            #expect((error as? AgentEventOutboxError) == .sourceChanged)
          case .success(let observation):
            responseLease = observation.responseLease
            Issue.record("The obsolete failed G1 fence must reject R1 before response success.")
          }
          let current = try #require(
            await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
          )
          #expect(current == independent)
          #expect(current.deliveryControl == independentControl)
          let failedFenceAfterRelease = try #require(
            fixture.outboxStore.load().progress.first(where: {
              $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
            })?.preparedResponseFence
          )
          #expect(failedFenceAfterRelease == failedFenceBeforeRelease)
          #expect(try Data(contentsOf: fixture.outboxStore.fileURL) == outboxBytesBeforeRelease)
          #expect(
            fixture.outboxService.admitsDelivery(
              binding: binding,
              ownerDeliveryControl: independentControl
            )
          )
          #expect(await fixture.callbackExchange.requestCount() == callbackCountBeforeR1)
          #expect(await fixture.applicationExchange.requestCount() == applicationCountBeforeR1)
          if let responseLease {
            await responseLease.complete(delivered: false)
            responseLeaseSettled = true
          }
          await commandWatcher?.value
          signalContinuation.finish()
        } catch {
          setupTask.cancel()
          currentTask?.cancel()
          await beforeOwnerWaitGate.release()
          if !setupRuntimeStopped {
            await setupRuntime.stop()
          }
          _ = await setupTask.result
          let currentResult = await currentTask?.result
          await commandWatcher?.value
          if let deadlineTask {
            deadlineTask.cancel()
            await deadlineTask.value
          }
          if !responseLeaseSettled {
            if responseLease == nil,
              case .some(.success(let observation)) = currentResult
            {
              responseLease = observation.responseLease
            }
            await responseLease?.complete(delivered: false)
            responseLeaseSettled = true
          }
          signalContinuation.finish()
          throw error
        }
      }
    }

    @Test @MainActor func runtimeOnlyProductionShapeListsEventsAndRejectsUnavailableCatalog()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let runtimeOnlyService = AgentCommandService(
          state: state,
          profileStore: fixture.profileStore,
          activityStore: fixture.activityStore,
          capabilityAuthority: fixture.authority,
          eventRuntime: fixture.runtime
        )
        let response = try await runtimeOnlyService.execute(
          profileID: fixture.profileID,
          credential: fixture.provisioning.credential,
          command: .listEvents
        )
        guard case .events(let events) = response else {
          Issue.record("The runtime-only production dependency shape must list events.")
          return
        }
        #expect(events.contains(where: { $0.name == .noteUpdated }))

        let unconfiguredService = AgentCommandService(
          state: state,
          profileStore: fixture.profileStore,
          activityStore: fixture.activityStore,
          capabilityAuthority: fixture.authority
        )
        var unavailable = false
        do {
          _ = try await unconfiguredService.execute(
            profileID: fixture.profileID,
            credential: fixture.provisioning.credential,
            command: .listEvents
          )
        } catch let error as AgentWorkspaceError {
          unavailable = error.code == .invalidOperation
        }
        #expect(unavailable)

        let current = try #require(
          try await fixture.capabilityStore.currentState().profiles[fixture.profileID]
        )
        _ = try await fixture.capabilityStore.replaceProfile(
          AgentProfileCapabilities(
            profileID: fixture.profileID,
            grantRevision: current.grantRevision + 1,
            allowedCapabilities: current.allowedCapabilities,
            grants: current.grants,
            allowsEventObservation: false
          ),
          expectedGrantRevision: current.grantRevision
        )
        var denied = false
        do {
          _ = try await runtimeOnlyService.execute(
            profileID: fixture.profileID,
            credential: fixture.provisioning.credential,
            command: .listEvents
          )
        } catch let error as AgentWorkspaceError {
          denied = error.code == .capabilityDenied
        }
        #expect(denied)
      }
    }

    @Test @MainActor func otherProfileReadAndUnsubscribeProgressWhileApprovalWaits()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let service = AgentCommandService(
          state: state,
          profileStore: fixture.profileStore,
          activityStore: fixture.activityStore,
          capabilityAuthority: fixture.authority,
          eventRuntime: fixture.runtime
        )
        let prepareCommand = AgentWorkspaceCommand.prepareEventSubscription(
          request: AgentEventSubscriptionRequest(
            event: .noteUpdated,
            scope: .note(noteID: fixture.note.id),
            callbackURL: fixture.callbackURL,
            signingSecret: fixture.signingSecret
          )
        )
        let pendingSubscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL
        )
        let pendingTask = Task {
          try await service.execute(
            profileID: fixture.profileID,
            credential: fixture.provisioning.credential,
            command: prepareCommand
          )
        }
        let pendingSubscription = try await fixture.waitForSubscription(id: pendingSubscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: pendingSubscriptionID,
          revision: pendingSubscription.revision
        )

        let otherProfile = try await fixture.profileStore.create(name: "Second runtime profile")
        _ = try await fixture.capabilityStore.registerEmptyProfile(otherProfile.profile.id)
        _ = try await fixture.capabilityStore.replaceProfile(
          AgentProfileCapabilities(
            profileID: otherProfile.profile.id,
            grantRevision: 1,
            allowedCapabilities: [.listNotes, .readNotes],
            grants: [
              AgentResourceGrant(
                scope: .note(noteID: fixture.note.id),
                authority: .read
              )
            ],
            allowsEventObservation: true
          ),
          expectedGrantRevision: 0
        )
        let otherCallbackURL = "https://other.runtime.example.test/events"
        let otherReceipt = try await fixture.subscriptionService.createPending(
          profileID: otherProfile.profile.id,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: otherCallbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { await state.workspace }
        )

        let readResponse = try await service.execute(
          profileID: otherProfile.profile.id,
          credential: otherProfile.credential,
          command: .listSharedNotes
        )
        guard case .sharedNotes(let notes) = readResponse else {
          Issue.record("Expected another profile's workspace read to complete during approval.")
          return
        }
        #expect(notes.map(\.noteID) == [fixture.note.id])

        let removeResponse = try await service.execute(
          profileID: otherProfile.profile.id,
          credential: otherProfile.credential,
          command: .removeEventSubscription(
            request: AgentEventUnsubscribeRequest(
              event: .noteUpdated,
              scope: .note(noteID: fixture.note.id),
              callbackURL: otherCallbackURL
            )
          )
        )
        #expect(removeResponse == .eventUnsubscribed)
        #expect(
          try await fixture.subscriptionStore.currentSubscription(
            id: otherReceipt.subscriptionID
          ) == nil
        )
        #expect(
          try await fixture.subscriptionStore.currentSubscription(
            id: pendingSubscriptionID
          ) != nil
        )
        #expect(await fixture.callbackExchange.requestCount() == 0)

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: pendingSubscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let response = try await pendingTask.value
        guard case .verifiedEventSubscription = response else {
          Issue.record("The original profile's approved subscription should complete.")
          return
        }
      }
    }

    @Test @MainActor func ownerApprovalTimeoutLeavesSubscriptionDisabled() async throws {
      try await withAgentEventMonitoringRuntimeFixture(approvalWaitLimit: .milliseconds(40)) {
        fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(
            notes: [fixture.note],
            selectedNoteID: fixture.note.id
          )
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)

        await expectCommandFailure(command.task)

        let stored = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        #expect(stored.deliveryControl?.enabled == false)
        #expect(await fixture.callbackExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func staleGrantMismatchLeavesNewerSubscriptionGenerationUntouched()
      async throws
    {
      let gate = RuntimeTestAsyncGate()
      defer { Task { await gate.release() } }
      try await withAgentEventMonitoringRuntimeFixture(
        afterSubscriptionCreationGate: gate
      ) { fixture in
        let workspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let capabilities = try #require(
          try await fixture.capabilityStore.currentState().profiles[fixture.profileID]
        )
        let oldGrantRevision = capabilities.grantRevision - 1
        let originalRequest = Task {
          do {
            _ = try await fixture.runtime.prepareAndVerifySubscription(
              profileID: fixture.profileID,
              event: .noteUpdated,
              scope: .note(noteID: fixture.note.id),
              callbackURL: fixture.callbackURL,
              signingSecret: fixture.signingSecret,
              requestedTTLSeconds: nil,
              expectedGrantRevision: oldGrantRevision,
              expectedTemporaryExclusionGeneration: fixture.authority
                .temporaryExclusionGeneration,
              workspaceProvider: { workspace }
            )
            return false
          } catch let error as AgentWorkspaceError {
            return error.code == .capabilityDenied
          } catch {
            return false
          }
        }
        await gate.waitUntilEntered()
        let firstGeneration = try #require(
          await fixture.subscriptionStore.currentSubscription(
            id: AgentEventSubscriptionIdentity.subscriptionID(
              profileID: fixture.profileID,
              event: .noteUpdated,
              scope: .note(noteID: fixture.note.id),
              callbackURL: fixture.callbackURL
            )
          )
        )
        #expect(firstGeneration.revision == 1)
        #expect(firstGeneration.grantRevision == capabilities.grantRevision)

        let newerReceipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        #expect(newerReceipt.revision == firstGeneration.revision + 1)
        #expect(newerReceipt.grantRevision == capabilities.grantRevision)
        _ = try await fixture.monitoringService.anchorAndVerifyPendingSubscription(
          profileID: fixture.profileID,
          subscriptionID: newerReceipt.subscriptionID,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: newerReceipt.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )

        let snapshot = try await fixture.localStore.loadSnapshot()
        var changedWorkspace = snapshot.workspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title += " preserved outbox body"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        _ = try fixture.localStore.snapshotWriter.save(
          workspace: changedWorkspace,
          preferences: snapshot.preferences,
          generation: snapshot.generation + 1
        )
        try await fixture.outboxService.capturePending(
          profileID: fixture.profileID,
          subscriptionID: newerReceipt.subscriptionID,
          now: fixture.clock.now()
        )

        let subscriptionBeforeRelease = try #require(
          await fixture.subscriptionStore.currentSubscription(id: newerReceipt.subscriptionID)
        )
        let binding = verificationBinding(for: subscriptionBeforeRelease)
        let proofBeforeRelease = try #require(
          try fixture.verificationStore.currentProof(for: binding)
        )
        let signingKeyService = "com.harryjin.fleck.agent-event-signing-keys"
        let keyBeforeRelease = try #require(
          try fixture.secretStore.read(
            service: signingKeyService,
            account: subscriptionBeforeRelease.signingKeyReference
          )
        )
        let outboxBeforeRelease = try Data(contentsOf: fixture.outboxStore.fileURL)
        let outboxStateBeforeRelease = try fixture.outboxStore.load()
        let cleanupBeforeRelease = try await fixture.subscriptionStore
          .pendingSigningKeyCleanupReferences()
        #expect(subscriptionBeforeRelease.deliveryControl?.enabled == true)
        #expect(outboxStateBeforeRelease.entries.count == 1)
        #expect(cleanupBeforeRelease.isEmpty)

        await gate.release()
        #expect(await originalRequest.value)

        let subscriptionAfterRelease = try #require(
          await fixture.subscriptionStore.currentSubscription(id: newerReceipt.subscriptionID)
        )
        #expect(subscriptionAfterRelease == subscriptionBeforeRelease)
        #expect(
          subscriptionAfterRelease.deliveryControl == subscriptionBeforeRelease.deliveryControl)
        #expect(
          try fixture.secretStore.read(
            service: signingKeyService,
            account: subscriptionAfterRelease.signingKeyReference
          ) == keyBeforeRelease
        )
        #expect(
          try fixture.verificationStore.currentProof(for: binding) == proofBeforeRelease
        )
        #expect(try Data(contentsOf: fixture.outboxStore.fileURL) == outboxBeforeRelease)
        #expect(try fixture.outboxStore.load() == outboxStateBeforeRelease)
        #expect(
          try await fixture.subscriptionStore.pendingSigningKeyCleanupReferences()
            == cleanupBeforeRelease
        )
      }
    }

    @Test @MainActor func cancellingOwnerApprovalDoesNotVerifyOrEnableSubscription() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(
            notes: [fixture.note],
            selectedNoteID: fixture.note.id
          )
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        _ = try await fixture.waitForSubscription(id: command.subscriptionID)

        command.task.cancel()
        await expectCommandFailure(command.task)

        let stored = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        #expect(stored.deliveryControl?.enabled == false)
        #expect(await fixture.callbackExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func preSendPauseCancelsBeforeFakeContactOrOwnedProof() async throws {
      try await assertPreContactCancellation(removing: false)
    }

    @Test @MainActor func preSendRemoveCancelsBeforeFakeContactOrOwnedProof() async throws {
      try await assertPreContactCancellation(removing: true)
    }

    @MainActor
    private func assertPreContactCancellation(removing: Bool) async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let gate = RuntimeTestAsyncGate()
        defer { Task { await gate.release() } }
        await fixture.callbackExchange.blockNextRequest(until: gate)
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        let workspace = state.workspace
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()
        let approved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let binding = verificationBinding(for: approved)

        if removing {
          try await fixture.runtime.removeSubscription(
            subscriptionID: command.subscriptionID
          )
        } else {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: command.subscriptionID,
            enabled: false,
            allowsAutomaticRenewal: false,
            workspaceProvider: nil
          )
        }
        await gate.release()
        await expectCommandFailure(command.task)

        #expect(await fixture.callbackExchange.requestCount() == 0)
        #expect(try fixture.verificationStore.currentProof(for: binding) == nil)
        let current = try await fixture.subscriptionStore.currentSubscription(
          id: command.subscriptionID
        )
        if removing {
          #expect(current == nil)
        } else {
          #expect(current?.deliveryControl?.enabled == false)
        }
      }
    }

    @Test @MainActor func cancellationDoesNotDisableANewerOwnerGeneration() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let gate = RuntimeTestAsyncGate()
        defer { Task { await gate.release() } }
        await fixture.callbackExchange.blockNextResponse(until: gate)
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )

        let workspace = state.workspace
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()
        let initiallyApproved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let initiallyApprovedControl = try #require(initiallyApproved.deliveryControl)

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let renewedSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let renewedControl = try #require(renewedSubscription.deliveryControl)
        #expect(renewedControl.enabled)
        #expect(renewedControl.generationID != initiallyApprovedControl.generationID)

        command.task.cancel()
        await gate.release()
        await expectCommandFailure(command.task)

        let finalSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        #expect(finalSubscription.deliveryControl == renewedControl)
        #expect(
          try await fixture.verificationStore.currentProof(
            for: verificationBinding(for: finalSubscription)
          ) == nil
        )
      }
    }

    @Test @MainActor func failedPreparedResponsePreservesNewerOwnerGeneration() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let service = AgentCommandService(
          state: state,
          profileStore: fixture.profileStore,
          activityStore: fixture.activityStore,
          capabilityAuthority: fixture.authority,
          eventRuntime: fixture.runtime
        )
        let command = AgentWorkspaceCommand.prepareEventSubscription(
          request: AgentEventSubscriptionRequest(
            event: .noteUpdated,
            scope: .note(noteID: fixture.note.id),
            callbackURL: fixture.callbackURL,
            signingSecret: fixture.signingSecret
          )
        )
        let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL
        )
        let executionTask = Task {
          try await service.executeForIPC(
            profileID: fixture.profileID,
            credential: fixture.provisioning.credential,
            command: command
          )
        }
        let pending = try await fixture.waitForSubscription(id: subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let execution = try await executionTask.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("Expected the verified response to retain its transport lease.")
          return
        }
        let verifiedSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let verifiedControl = try #require(verifiedSubscription.deliveryControl)
        let binding = verificationBinding(for: verifiedSubscription)

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: nil
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let newerControl = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)?.deliveryControl
        )
        #expect(newerControl.enabled)
        #expect(newerControl.generationID != verifiedControl.generationID)
        let pendingFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.preparedResponseFence
        )
        #expect(pendingFence.disposition == .failedResponse)
        #expect(fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: newerControl
        ))

        await fixture.runtime.stop()
        await responseDisposition(false)

        let finalSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        #expect(finalSubscription.deliveryControl == newerControl)
        #expect(
          try fixture.verificationStore.currentProof(
            for: verificationBinding(for: finalSubscription)
          ) == nil
        )
        let failedFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.preparedResponseFence
        )
        #expect(failedFence.binding == binding)
        #expect(failedFence.ownerControlGenerationID == verifiedControl.generationID)
        #expect(failedFence.disposition == .failedResponse)
        #expect(!fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: verifiedControl
        ))
        #expect(fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: newerControl
        ))
      }
    }

    @Test @MainActor func failedAutoRenewalPrearmDoesNotAdmitTheNewBinding() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let firstReceipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id) },
          now: fixture.clock.now()
        )
        let first = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstReceipt.subscriptionID)
        )
        let firstControl = try #require(first.deliveryControl)
        try await fixture.outboxService.registerPending(
          profileID: fixture.profileID,
          subscriptionID: firstReceipt.subscriptionID,
          now: fixture.clock.now(),
          ownerDeliveryControl: firstControl
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstReceipt.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: true,
          workspaceProvider: { Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id) }
        )

        let refreshedReceipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id) },
          now: fixture.clock.now()
        )
        let refreshed = try #require(
          await fixture.subscriptionStore.currentSubscription(id: refreshedReceipt.subscriptionID)
        )
        let refreshedControl = try #require(refreshed.deliveryControl)
        #expect(refreshed.revision > first.revision)
        #expect(refreshedControl.enabled)
        #expect(refreshedControl.allowsAutomaticRenewal)
        fixture.outboxFileWriter.failAfterSuccessfulWrites()

        var armFailed = false
        do {
          try await fixture.outboxService.registerPending(
            profileID: fixture.profileID,
            subscriptionID: refreshedReceipt.subscriptionID,
            now: fixture.clock.now(),
            ownerDeliveryControl: refreshedControl,
            preparedResponseOriginID: UUID()
          )
        } catch {
          armFailed = true
        }
        #expect(armFailed)
        let oldProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID
              && $0.subscriptionID == refreshedReceipt.subscriptionID
          })
        )
        #expect(oldProgress.subscriptionRevision == first.revision)
        #expect(oldProgress.preparedResponseFence == nil)

        var staleCaptureRejected = false
        do {
          try await fixture.outboxService.capturePending(
            profileID: fixture.profileID,
            subscriptionID: refreshedReceipt.subscriptionID,
            now: fixture.clock.now()
          )
        } catch let error as AgentEventOutboxError {
          staleCaptureRejected = error == .sourceChanged
        }
        #expect(staleCaptureRejected)

        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start {
          Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == 0)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()
      }
    }

    @Test @MainActor func pausedSubscriptionPrearmsFenceBeforeOwnerReapproval() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let workspace = state.workspace
        let firstCommand = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pendingSubscription = try await fixture.waitForSubscription(
          id: firstCommand.subscriptionID
        )
        _ = try await fixture.waitForPreparedResponseFence(
          id: firstCommand.subscriptionID,
          revision: pendingSubscription.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstCommand.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let firstExecution = try await firstCommand.task.value
        guard case .verifiedEventSubscription = firstExecution.response,
          let firstResponseDisposition = firstExecution.responseDisposition
        else {
          Issue.record("Expected the first prepared response to retain its disposition callback.")
          return
        }
        await firstResponseDisposition(true)
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstCommand.subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: nil
        )
        let paused = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstCommand.subscriptionID)
        )
        #expect(paused.deliveryControl?.enabled == false)

        let secondCommand = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        var refreshed: AgentEventPendingSubscription?
        for _ in 0..<500 {
          if let current = try await fixture.subscriptionStore.currentSubscription(
            id: secondCommand.subscriptionID
          ), current.revision > paused.revision {
            refreshed = current
            break
          }
          try await Task.sleep(for: .milliseconds(10))
        }
        let pending = try #require(refreshed)
        _ = try await fixture.waitForPreparedResponseFence(
          id: secondCommand.subscriptionID,
          revision: pending.revision,
          expectedOwnerState: .paused
        )
        var prearmed: AgentEventOutboxProgress?
        for _ in 0..<500 {
          if let current = try? fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID
              && $0.subscriptionID == secondCommand.subscriptionID
              && $0.subscriptionRevision == pending.revision
              && $0.preparedResponseFence != nil
          }) {
            prearmed = current
            break
          }
          try await Task.sleep(for: .milliseconds(10))
        }
        let fence = try #require(prearmed?.preparedResponseFence)
        let pendingControl = try #require(pending.deliveryControl)
        #expect(prearmed?.status == .discarded)
        #expect(fence.binding == verificationBinding(for: pending))
        #expect(!fixture.outboxService.admitsDelivery(
          binding: verificationBinding(for: pending),
          ownerDeliveryControl: pendingControl
        ))

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: secondCommand.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let secondExecution = try await secondCommand.task.value
        guard case .verifiedEventSubscription = secondExecution.response,
          let secondResponseDisposition = secondExecution.responseDisposition
        else {
          Issue.record("Expected the reapproved response to retain its disposition callback.")
          return
        }
        let approved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: secondCommand.subscriptionID)
        )
        let approvedControl = try #require(approved.deliveryControl)
        #expect(approvedControl.enabled)
        #expect(!fixture.outboxService.admitsDelivery(
          binding: verificationBinding(for: approved),
          ownerDeliveryControl: approvedControl
        ))
        await fixture.runtime.stop()
        await secondResponseDisposition(true)
        #expect(
          try fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == secondCommand.subscriptionID
          })?.preparedResponseFence == nil
        )
      }
    }

    @Test @MainActor
    func completedApprovalAllowsPausedReapprovalWhileResponseLeaseIsOutstanding() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let workspace = state.workspace
        let firstCommand = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: firstCommand.subscriptionID)
        let pendingControl = try #require(pending.deliveryControl)
        let prepared = try await fixture.waitForPreparedResponseFence(
          id: firstCommand.subscriptionID,
          revision: pending.revision
        )
        #expect(!pendingControl.enabled)
        #expect(
          prepared.preparedResponseFence?.ownerControlGenerationID == pendingControl.generationID
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstCommand.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let execution = try await firstCommand.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("Expected the initial approval to retain its response lease.")
          return
        }
        let approved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstCommand.subscriptionID)
        )
        let initialControl = try #require(approved.deliveryControl)
        let binding = verificationBinding(for: approved)
        #expect(initialControl.enabled)
        #expect(initialControl.generationID != pendingControl.generationID)
        #expect(prepared.preparedResponseFence?.binding == binding)
        #expect(
          prepared.preparedResponseFence?.ownerControlGenerationID == pendingControl.generationID
        )
        let committedFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstCommand.subscriptionID
          })?.preparedResponseFence
        )
        #expect(committedFence.binding == binding)
        #expect(committedFence.ownerControlGenerationID == initialControl.generationID)
        #expect(
          committedFence.originIntentID == prepared.preparedResponseFence?.originIntentID
        )

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstCommand.subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: nil
        )
        let paused = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstCommand.subscriptionID)
        )
        let pausedSummary = try await fixture.runtime.ownerSummaries(workspace: nil)
        #expect(
          pausedSummary.first(where: { $0.id == firstCommand.subscriptionID })?.state == .paused
        )
        #expect(paused.deliveryControl?.enabled == false)
        let pausedProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstCommand.subscriptionID
          })
        )
        #expect(pausedProgress.nonDeliveryDisposition == .ownerPaused)
        #expect(pausedProgress.preparedResponseFence?.binding == binding)
        #expect(
          pausedProgress.preparedResponseFence?.ownerControlGenerationID == initialControl.generationID
        )

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstCommand.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let reapproved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstCommand.subscriptionID)
        )
        let reapprovedControl = try #require(reapproved.deliveryControl)
        let reapprovedProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstCommand.subscriptionID
          })
        )
        #expect(reapprovedControl.enabled)
        #expect(reapprovedControl.generationID != initialControl.generationID)
        #expect(reapprovedProgress.preparedResponseFence?.binding == binding)
        #expect(
          reapprovedProgress.preparedResponseFence?.originIntentID
            == prepared.preparedResponseFence?.originIntentID
        )
        #expect(
          reapprovedProgress.preparedResponseFence?.ownerControlGenerationID
            == initialControl.generationID
        )

        await responseDisposition(true)
        let completedResponseProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstCommand.subscriptionID
          })
        )
        #expect(completedResponseProgress.preparedResponseFence?.binding == binding)
        #expect(
          completedResponseProgress.preparedResponseFence?.ownerControlGenerationID
            == initialControl.generationID
        )
      }
    }

    @Test @MainActor
    func carriedRenewalCompletesBeforePausedReapprovalWhileResponseLeaseIsOutstanding()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let workspace = state.workspace
        let firstReceipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        let first = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstReceipt.subscriptionID)
        )
        let firstControl = try #require(first.deliveryControl)
        try await fixture.outboxService.registerPending(
          profileID: fixture.profileID,
          subscriptionID: firstReceipt.subscriptionID,
          now: fixture.clock.now(),
          ownerDeliveryControl: firstControl
        )
        let legacyApproval = try await fixture.runtime.ownerSummaries(workspace: workspace)
        #expect(
          legacyApproval.first(where: { $0.id == firstReceipt.subscriptionID })?.state
            == .awaitingApproval
        )
        let markerlessProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstReceipt.subscriptionID
          })
        )
        #expect(!markerlessProgress.requiresPreparedResponseFence)
        #expect(markerlessProgress.preparedResponseFence == nil)

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstReceipt.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: true,
          workspaceProvider: { workspace }
        )
        let legacyApproved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstReceipt.subscriptionID)
        )
        let legacyApprovedControl = try #require(legacyApproved.deliveryControl)
        #expect(legacyApprovedControl.enabled)
        #expect(legacyApprovedControl.generationID != firstControl.generationID)
        #expect(legacyApprovedControl.allowsAutomaticRenewal)
        let markerlessApprovedProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstReceipt.subscriptionID
          })
        )
        #expect(markerlessApprovedProgress.status == .pending)
        #expect(markerlessApprovedProgress.nonDeliveryDisposition == nil)
        #expect(!markerlessApprovedProgress.requiresPreparedResponseFence)
        #expect(markerlessApprovedProgress.preparedResponseFence == nil)

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstReceipt.subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: nil
        )
        let legacyPaused = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstReceipt.subscriptionID)
        )
        let legacyPausedControl = try #require(legacyPaused.deliveryControl)
        #expect(!legacyPausedControl.enabled)
        #expect(legacyPausedControl.generationID != legacyApprovedControl.generationID)
        #expect(
          try await fixture.runtime.ownerSummaries(workspace: nil).first(where: {
            $0.id == firstReceipt.subscriptionID
          })?.state == .paused
        )
        let markerlessPausedProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstReceipt.subscriptionID
          })
        )
        #expect(markerlessPausedProgress.status == .discarded)
        #expect(markerlessPausedProgress.nonDeliveryDisposition == .ownerPaused)
        #expect(!markerlessPausedProgress.requiresPreparedResponseFence)
        #expect(markerlessPausedProgress.preparedResponseFence == nil)

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstReceipt.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: true,
          workspaceProvider: { workspace }
        )
        let legacyResumed = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstReceipt.subscriptionID)
        )
        let legacyResumedControl = try #require(legacyResumed.deliveryControl)
        #expect(legacyResumedControl.enabled)
        #expect(legacyResumedControl.generationID != legacyPausedControl.generationID)
        #expect(legacyResumedControl.allowsAutomaticRenewal)
        let markerlessResumedProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstReceipt.subscriptionID
          })
        )
        #expect(markerlessResumedProgress.status == .pending)
        #expect(markerlessResumedProgress.nonDeliveryDisposition == nil)
        #expect(!markerlessResumedProgress.requiresPreparedResponseFence)
        #expect(markerlessResumedProgress.preparedResponseFence == nil)
        #expect(
          try fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstReceipt.subscriptionID
          })?.preparedResponseFence == nil
        )

        let verificationGate = RuntimeTestAsyncGate()
        defer { Task { await verificationGate.release() } }
        await fixture.callbackExchange.blockNextRequest(until: verificationGate)
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(
          id: command.subscriptionID,
          afterRevision: first.revision
        )
        let prearmed = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision,
          expectedOwnerState: .unavailable
        )
        await verificationGate.waitUntilEntered()
        let renewed = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let renewedControl = try #require(renewed.deliveryControl)
        let binding = verificationBinding(for: renewed)
        let prearmedFence = try #require(prearmed.preparedResponseFence)
        #expect(renewed.revision > first.revision)
        #expect(renewedControl.enabled)
        #expect(renewedControl.allowsAutomaticRenewal)
        #expect(prearmedFence.binding == binding)
        #expect(prearmedFence.ownerControlGenerationID == renewedControl.generationID)
        #expect(
          try fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence?.originIntentID == prearmedFence.originIntentID
        )
        let renewedSummary = try await fixture.runtime.ownerSummaries(workspace: workspace)
        #expect(
          renewedSummary.first(where: { $0.id == command.subscriptionID })?.state
            == .awaitingVerification
        )

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: nil
        )
        let paused = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let pausedControl = try #require(paused.deliveryControl)
        #expect(!pausedControl.enabled)
        #expect(pausedControl.generationID != renewedControl.generationID)
        #expect(
          try await fixture.runtime.ownerSummaries(workspace: nil).first(where: {
            $0.id == command.subscriptionID
          })?.state == .paused
        )

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let reapproved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let reapprovedControl = try #require(reapproved.deliveryControl)
        let retainedFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        var expectedRetainedFence = prearmedFence
        expectedRetainedFence.disposition = .failedResponse
        #expect(reapprovedControl.enabled)
        #expect(reapprovedControl.generationID != pausedControl.generationID)
        #expect(retainedFence == expectedRetainedFence)
        #expect(fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: reapprovedControl
        ))

        await verificationGate.release()
        await #expect(throws: CancellationError.self) { try await command.task.value }
        #expect(await fixture.callbackExchange.requestCount() == 0)
        let afterFailedCallback = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        #expect(afterFailedCallback.revision == renewed.revision)
        #expect(verificationBinding(for: afterFailedCallback) == binding)
        #expect(afterFailedCallback.deliveryControl == reapprovedControl)
        let afterFailureFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(afterFailureFence == expectedRetainedFence)
        #expect(await fixture.applicationExchange.requestCount() == 0)
      }
    }

    @Test @MainActor
    func unregisteredLegacyApprovalRequiresFreshPreparedSetup() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let workspace = state.workspace
        let firstReceipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        let unregistered = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstReceipt.subscriptionID)
        )
        let unregisteredControl = try #require(unregistered.deliveryControl)
        #expect(
          try fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == firstReceipt.subscriptionID
          }) == nil
        )

        let reopenedRuntime = fixture.makeReopenedRuntime()
        let unavailable = try await reopenedRuntime.ownerSummaries(workspace: nil)
        #expect(
          unavailable.first(where: { $0.id == firstReceipt.subscriptionID })?.state == .unavailable
        )
        await #expect(throws: AgentEventOutboxError.registrationRequired) {
          try await reopenedRuntime.setOwnerDeliveryConsent(
            subscriptionID: firstReceipt.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { workspace }
          )
        }
        #expect(
          try await fixture.subscriptionStore.currentSubscription(id: firstReceipt.subscriptionID)?
            .deliveryControl == unregisteredControl
        )

        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let prepared = try await fixture.waitForSubscription(
          id: command.subscriptionID,
          afterRevision: unregistered.revision
        )
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: prepared.revision
        )
        #expect(
          try await fixture.runtime.ownerSummaries(workspace: workspace).first(where: {
            $0.id == command.subscriptionID
          })?.state == .awaitingApproval
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let execution = try await command.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("A fresh prepared setup should recover the unregistered subscription.")
          return
        }
        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        #expect(current.revision > unregistered.revision)
        #expect(current.deliveryControl?.enabled == true)
        await responseDisposition(true)
      }
    }

    @Test @MainActor
    func nilContextManualRecoveryRequiresVerifiedPausedTupleAndOlderFence() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let workspace = state.workspace
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        let initialProgress = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        let initialControl = try #require(pending.deliveryControl)
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let execution = try await command.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("The initial prepared subscription should retain its response lease.")
          return
        }
        let approved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let approvedControl = try #require(approved.deliveryControl)
        let binding = verificationBinding(for: approved)
        let originalFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(originalFence.ownerControlGenerationID == approvedControl.generationID)
        #expect(originalFence.ownerControlGenerationID != initialControl.generationID)
        #expect(originalFence.originIntentID == initialProgress.preparedResponseFence?.originIntentID)

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: nil
        )
        let paused = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let pausedControl = try #require(paused.deliveryControl)
        #expect(!pausedControl.enabled)
        #expect(pausedControl.generationID != approvedControl.generationID)
        await fixture.runtime.stop()
        let reopenedRuntime = fixture.makeReopenedRuntime()
        let validOutboxData = try Data(contentsOf: fixture.outboxStore.fileURL)

        for fault in RuntimeTestNilMemoryRecoveryFault.allCases {
          switch fault {
          case .missingProgress:
            try setPreparedReadinessFault(
              .missingProgress,
              fixture: fixture,
              subscriptionID: command.subscriptionID
            )
          case .staleBinding:
            try setPreparedReadinessFault(
              .staleBinding,
              fixture: fixture,
              subscriptionID: command.subscriptionID
            )
          case .staleSubscriptionRevision:
            try setPreparedReadinessFault(
              .staleSubscriptionRevision,
              fixture: fixture,
              subscriptionID: command.subscriptionID
            )
          case .staleGrantRevision:
            try setPreparedReadinessFault(
              .staleGrantRevision,
              fixture: fixture,
              subscriptionID: command.subscriptionID
            )
          case .sameCurrentGeneration:
            try fixture.outboxStore.update { outbox in
              guard let index = outbox.progress.firstIndex(where: {
                $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
              }), let fence = outbox.progress[index].preparedResponseFence else {
                throw RuntimeTestError.invalidFixture
              }
              outbox.progress[index].preparedResponseFence = AgentEventOutboxPreparedResponseFence(
                binding: fence.binding,
                ownerControlGenerationID: pausedControl.generationID,
                originIntentID: fence.originIntentID,
                disposition: fence.disposition
              )
            }
          case .missingRequiredMarker:
            var document = try #require(
              try JSONSerialization.jsonObject(with: validOutboxData) as? [String: Any]
            )
            var progressRows = try #require(document["progress"] as? [[String: Any]])
            let progressIndices = progressRows.indices.filter {
              progressRows[$0]["subscriptionID"] as? String == command.subscriptionID
            }
            guard progressIndices.count == 1, let progressIndex = progressIndices.first else {
              throw RuntimeTestError.invalidFixture
            }
            progressRows[progressIndex]["requiresPreparedResponseFence"] = true
            progressRows[progressIndex].removeValue(forKey: "preparedResponseFence")
            document["progress"] = progressRows
            try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
              .write(to: fixture.outboxStore.fileURL, options: .atomic)
          case .unreadableRegistry:
            try setPreparedReadinessFault(
              .unreadableRegistry,
              fixture: fixture,
              subscriptionID: command.subscriptionID
            )
          case .ambiguousProgress:
            let document = try #require(
              try JSONSerialization.jsonObject(with: validOutboxData) as? [String: Any]
            )
            var ambiguousDocument = document
            var progressRows = try #require(document["progress"] as? [[String: Any]])
            progressRows.append(try #require(progressRows.first))
            ambiguousDocument["progress"] = progressRows
            try JSONSerialization.data(
              withJSONObject: ambiguousDocument,
              options: [.sortedKeys]
            ).write(to: fixture.outboxStore.fileURL, options: .atomic)
          case .knownPausedCapacity, .knownPausedHistory:
            try fixture.outboxStore.update { outbox in
              guard let index = outbox.progress.firstIndex(where: {
                $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
              }) else {
                throw RuntimeTestError.invalidFixture
              }
              switch fault {
              case .knownPausedCapacity:
                outbox.progress[index].status = .pausedCapacity
              case .knownPausedHistory:
                outbox.progress[index].status = .pausedHistory
              default:
                throw RuntimeTestError.invalidFixture
              }
              outbox.progress[index].nonDeliveryDisposition = nil
              outbox.progress[index].preparedResponseFence = nil
              outbox.progress[index].requiresPreparedResponseFence = false
            }
          }

          let unavailable = try await reopenedRuntime.ownerSummaries(workspace: nil)
          let expectedState: AgentEventOwnerState
          switch fault {
          case .knownPausedCapacity:
            expectedState = .pausedCapacity
          case .knownPausedHistory:
            expectedState = .pausedHistory
          default:
            expectedState = .unavailable
          }
          #expect(
            unavailable.first(where: { $0.id == command.subscriptionID })?.state == expectedState
          )
          let expectedError: AgentEventOutboxError
          switch fault {
          case .missingProgress:
            expectedError = .registrationRequired
          case .unreadableRegistry, .ambiguousProgress, .missingRequiredMarker:
            expectedError = .storageFailure
          default:
            expectedError = .sourceChanged
          }
          await #expect(throws: expectedError) {
            try await reopenedRuntime.setOwnerDeliveryConsent(
              subscriptionID: command.subscriptionID,
              enabled: true,
              allowsAutomaticRenewal: false,
              workspaceProvider: { workspace }
            )
          }
          #expect(
            try await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
              .deliveryControl == pausedControl
          )
          try validOutboxData.write(to: fixture.outboxStore.fileURL, options: .atomic)
          #expect(
            try await reopenedRuntime.ownerSummaries(workspace: nil).first(where: {
              $0.id == command.subscriptionID
            })?.state == .paused
          )
        }

        try setPreparedReadinessFault(
          .failedDisposition,
          fixture: fixture,
          subscriptionID: command.subscriptionID
        )
        let failedOldFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(failedOldFence.binding == binding)
        #expect(failedOldFence.ownerControlGenerationID == approvedControl.generationID)
        #expect(failedOldFence.disposition == .failedResponse)
        try await reopenedRuntime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let reapproved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let reapprovedControl = try #require(reapproved.deliveryControl)
        let retainedFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(reapprovedControl.enabled)
        #expect(reapprovedControl.generationID != pausedControl.generationID)
        #expect(retainedFence == failedOldFence)
        #expect(fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: reapprovedControl
        ))
        #expect(
          try await reopenedRuntime.ownerSummaries(workspace: workspace).first(where: {
            $0.id == command.subscriptionID
          })?.state == .enabled
        )

        await responseDisposition(true)
        #expect(
          try #require(
            fixture.outboxStore.load().progress.first(where: {
              $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
            })?.preparedResponseFence
          ) == failedOldFence
        )
        #expect(
          try await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl == reapprovedControl
        )
        await reopenedRuntime.stop()
      }
    }

    @Test @MainActor
    func staleAndWrongOriginPausedProgressCannotExposePreparedRefresh() async throws {
      let registrationGate = RuntimeTestAsyncGate()
      defer { Task { await registrationGate.release() } }
      try await withAgentEventMonitoringRuntimeFixture(
        afterSubscriptionCreationGate: registrationGate
      ) { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let workspace = state.workspace
        let firstReceipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        let firstSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: firstReceipt.subscriptionID)
        )
        let firstControl = try #require(firstSubscription.deliveryControl)
        try await fixture.outboxService.registerPending(
          profileID: fixture.profileID,
          subscriptionID: firstReceipt.subscriptionID,
          now: fixture.clock.now(),
          ownerDeliveryControl: firstControl
        )
        try fixture.outboxService.discardPendingBodies(
          profileID: fixture.profileID,
          subscriptionID: firstReceipt.subscriptionID,
          disposition: .ownerPaused
        )
        let firstSummary = try await fixture.runtime.ownerSummaries(workspace: nil)
        #expect(
          firstSummary.first(where: { $0.id == firstReceipt.subscriptionID })?.state == .paused
        )

        let refreshedCommand = startPreparedEventSubscriptionIPCCommand(
          fixture: fixture,
          state: state
        )
        let refreshed = try await fixture.waitForSubscription(
          id: refreshedCommand.subscriptionID,
          afterRevision: firstSubscription.revision
        )
        await registrationGate.waitUntilEntered()
        let beforeRegistration = try await fixture.runtime.ownerSummaries(workspace: state.workspace)
        #expect(
          beforeRegistration.first(where: { $0.id == refreshedCommand.subscriptionID })?.state
            == .unavailable
        )
        await #expect(throws: AgentEventOutboxError.sourceChanged) {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: refreshedCommand.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { workspace }
          )
        }
        let stillDisabled = try #require(
          await fixture.subscriptionStore.currentSubscription(
            id: refreshedCommand.subscriptionID
          )
        )
        #expect(stillDisabled.deliveryControl?.enabled == false)
        var stalePausedWaitTimedOut = false
        do {
          _ = try await fixture.waitForPreparedResponseFence(
            id: refreshedCommand.subscriptionID,
            revision: refreshed.revision,
            expectedOwnerState: .paused,
            pollCount: 1
          )
        } catch RuntimeTestError.timeout {
          stalePausedWaitTimedOut = true
        }
        #expect(stalePausedWaitTimedOut)

        await registrationGate.release()
        let readyProgress = try await fixture.waitForPreparedResponseFence(
          id: refreshedCommand.subscriptionID,
          revision: refreshed.revision,
          expectedOwnerState: .paused
        )
        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(
            id: refreshedCommand.subscriptionID
          )
        )
        let currentBinding = verificationBinding(for: current)
        let currentControl = try #require(current.deliveryControl)
        let fence = try #require(readyProgress.preparedResponseFence)
        #expect(fence.binding == currentBinding)
        #expect(fence.ownerControlGenerationID == currentControl.generationID)

        let wrongOriginID = UUID()
        try fixture.outboxStore.update { outbox in
          guard let index = outbox.progress.firstIndex(where: {
            $0.profileID == fixture.profileID
              && $0.subscriptionID == refreshedCommand.subscriptionID
              && $0.subscriptionRevision == refreshed.revision
          }), let currentFence = outbox.progress[index].preparedResponseFence else {
            throw RuntimeTestError.invalidFixture
          }
          outbox.progress[index].status = .discarded
          outbox.progress[index].nonDeliveryDisposition = .ownerPaused
          outbox.progress[index].preparedResponseFence = AgentEventOutboxPreparedResponseFence(
            binding: currentFence.binding,
            ownerControlGenerationID: currentFence.ownerControlGenerationID,
            originIntentID: wrongOriginID,
            disposition: currentFence.disposition
          )
        }
        let wrongOriginSummary = try await fixture.runtime.ownerSummaries(workspace: nil)
        #expect(
          wrongOriginSummary.first(where: { $0.id == refreshedCommand.subscriptionID })?.state
            == .unavailable
        )
        await #expect(throws: AgentEventOutboxError.sourceChanged) {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: refreshedCommand.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { workspace }
          )
        }
        var wrongOriginPausedWaitTimedOut = false
        do {
          _ = try await fixture.waitForPreparedResponseFence(
            id: refreshedCommand.subscriptionID,
            revision: refreshed.revision,
            expectedOwnerState: .paused,
            pollCount: 1
          )
        } catch RuntimeTestError.timeout {
          wrongOriginPausedWaitTimedOut = true
        }
        #expect(wrongOriginPausedWaitTimedOut)
        refreshedCommand.task.cancel()
        await expectCommandFailure(refreshedCommand.task)
      }
    }

    @Test @MainActor func cancelledOrTimedOutApprovalCannotCommitCapturedOwnerOrigin() async throws {
      for shouldTimeout in [false, true] {
        try await withAgentEventMonitoringRuntimeFixture(
          approvalWaitLimit: shouldTimeout ? .seconds(1) : .seconds(5)
        ) { fixture in
          let gate = RuntimeTestAsyncGate()
          defer { Task { await gate.release() } }
          let state = RuntimeTestWorkspaceState(
            workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
          )
          let workspace = state.workspace
          let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
          let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
          _ = try await fixture.waitForPreparedResponseFence(
            id: command.subscriptionID,
            revision: pending.revision
          )
          let capturedControl = try #require(pending.deliveryControl)
          #expect(!capturedControl.enabled)

          let ownerTask = Task {
            try await fixture.runtime.setOwnerDeliveryConsent(
              subscriptionID: command.subscriptionID,
              enabled: true,
              allowsAutomaticRenewal: false,
              workspaceProvider: {
                await gate.pause()
                return workspace
              }
            )
          }
          await gate.waitUntilEntered()

          let commandResult: Result<AgentIPCServer.ExecutionResult, Error>
          if shouldTimeout {
            commandResult = await command.task.result
          } else {
            command.task.cancel()
            commandResult = await command.task.result
          }
          if case .success = commandResult {
            Issue.record("The owner request must not outlive its preparation.")
          }

          await gate.release()
          var staleApprovalRejected = false
          do {
            try await ownerTask.value
          } catch {
            staleApprovalRejected = true
          }
          #expect(staleApprovalRejected)

          let current = try #require(
            await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
          )
          let invalidatedControl = try #require(current.deliveryControl)
          #expect(!invalidatedControl.enabled)
          #expect(invalidatedControl.generationID == capturedControl.generationID)
          #expect(!fixture.outboxService.admitsDelivery(
            binding: verificationBinding(for: current),
            ownerDeliveryControl: invalidatedControl
          ))
          let progress = try #require(
            fixture.outboxStore.load().progress.first(where: {
              $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
            })
          )
          #expect(progress.status == .discarded)
          #expect(progress.preparedResponseFence?.disposition == .failedResponse)
          #expect(
            progress.preparedResponseFence?.ownerControlGenerationID
              == capturedControl.generationID
          )
          #expect(await fixture.callbackExchange.requestCount() == 0)
          #expect(await fixture.applicationExchange.requestCount() == 0)

          let reopenedRuntime = fixture.makeReopenedRuntime()
          await reopenedRuntime.start { workspace }
          try await Task.sleep(for: .milliseconds(50))
          #expect(await fixture.callbackExchange.requestCount() == 0)
          #expect(await fixture.applicationExchange.requestCount() == 0)
          await reopenedRuntime.stop()
        }
      }
    }

    @Test @MainActor func prospectiveOwnerGenerationCASRejectsReuseAndStaleControl()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let workspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let subscriptionID = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: workspace
        )
        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let binding = verificationBinding(for: current)
        let currentControl = try #require(current.deliveryControl)

        let reusedGeneration = try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
          binding: binding,
          expectedGenerationID: currentControl.generationID,
          eligible: true,
          prospectiveGenerationID: currentControl.generationID
        )
        #expect(reusedGeneration == nil)

        let staleGeneration = UUID()
        let conflictedGeneration = UUID()
        let staleControl = try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
          binding: binding,
          expectedGenerationID: staleGeneration,
          eligible: true,
          prospectiveGenerationID: conflictedGeneration
        )
        #expect(staleControl == nil)

        let selectedGeneration = UUID()
        let selectedControl = try #require(
          try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
            binding: binding,
            expectedGenerationID: currentControl.generationID,
            eligible: false,
            prospectiveGenerationID: selectedGeneration
          )
        )
        #expect(selectedControl.generationID == selectedGeneration)
        #expect(!selectedControl.enabled)
      }
    }

    @Test @MainActor func failedProspectiveFenceArmCannotPersistOwnerONGeneration() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        let initialProgress = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        let initialControl = try #require(pending.deliveryControl)
        let initialFence = try #require(initialProgress.preparedResponseFence)
        let callbackCount = await fixture.callbackExchange.requestCount()
        fixture.outboxFileWriter.failAfterSuccessfulWrites()

        var approvalFailed = false
        do {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: command.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { await state.workspace }
          )
        } catch {
          approvalFailed = true
        }
        #expect(approvalFailed)

        let afterFailure = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let persistedControl = try #require(afterFailure.deliveryControl)
        #expect(persistedControl == initialControl)
        #expect(!persistedControl.enabled)
        let retainedFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(retainedFence == initialFence)

        command.task.cancel()
        await expectCommandFailure(command.task)
        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == callbackCount)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()
      }
    }

    @Test @MainActor func prospectiveFenceDeniesPendingEventUntilPreparedResponseWrites()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let initialWorkspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let subscriptionID = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: initialWorkspace
        )
        var changedWorkspace = initialWorkspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title = "Pending prospective-fence event"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        _ = try await fixture.localStore.save(
          workspace: changedWorkspace,
          preferences: .init(),
          generation: 2
        )
        try await fixture.outboxService.capturePending(
          profileID: fixture.profileID,
          subscriptionID: subscriptionID,
          now: fixture.clock.now()
        )
        fixture.clock.advance(by: 2)
        #expect(
          try fixture.outboxStore.load().entries.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.body != nil
        )

        let original = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let state = RuntimeTestWorkspaceState(workspace: changedWorkspace)
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(
          id: subscriptionID,
          afterRevision: original.revision
        )
        _ = try await fixture.waitForPreparedResponseFence(
          id: subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let execution = try await command.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("Expected the prepared response to retain its disposition callback.")
          return
        }

        let approved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let binding = verificationBinding(for: approved)
        let ownerControl = try #require(approved.deliveryControl)
        let proof = try #require(try fixture.verificationStore.currentProof(for: binding))
        let fence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.preparedResponseFence
        )
        #expect(fence.binding == binding)
        #expect(fence.ownerControlGenerationID == ownerControl.generationID)
        #expect(fence.originIntentID == proof.originIntentID)
        #expect(fence.disposition == .awaitingResponse)
        #expect(!fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: ownerControl
        ))

        let ledgerService = AgentEventDeliveryLedgerService(
          outboxStore: fixture.outboxStore,
          subscriptionStore: fixture.subscriptionStore,
          ledgerStore: fixture.ledgerStore
        )
        let reservation = try #require(
          try await ledgerService.reserveNext(
            profileID: fixture.profileID,
            subscriptionID: subscriptionID
          )
        )
        let attempt = try await ledgerService.observe(reservation)
        let authorizationService = AgentEventDeliveryAuthorizationService(
          authority: fixture.authority,
          profileStore: fixture.profileStore,
          subscriptionStore: fixture.subscriptionStore,
          verificationStore: fixture.verificationStore,
          outboxStore: fixture.outboxStore,
          ledgerStore: fixture.ledgerStore,
          now: { fixture.clock.now() }
        )
        #expect(await authorizationService.observeEligibility(
          for: attempt,
          workspaceProvider: { await state.workspace }
        ) == nil)
        let finalObservation = AgentEventDeliveryEligibilityObservation(
          profileID: binding.profileID,
          subscriptionID: binding.subscriptionID,
          eventID: reservation.eventID,
          reservationID: reservation.id,
          ledgerGenerationID: reservation.bindingGenerationID,
          ownerControlGenerationID: ownerControl.generationID,
          proofGenerationID: proof.originIntentID,
          expectedTemporaryExclusionGeneration: authorizationService
            .temporaryExclusionGeneration
        )
        let finalAuthorizationIsCurrent = await authorizationService.isCurrent(
          finalObservation,
          for: attempt,
          workspaceProvider: { await state.workspace }
        )
        #expect(!finalAuthorizationIsCurrent)

        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()
        await responseDisposition(true)
        #expect(
          try fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.preparedResponseFence == nil
        )
        #expect(try fixture.verificationStore.currentProof(for: binding) == proof)
        let releasedAuthorization = await authorizationService.observeEligibility(
          for: attempt,
          workspaceProvider: { await state.workspace }
        )
        #expect(releasedAuthorization == finalObservation)

        let outboxURL = fixture.outboxStore.fileURL
        var document = try #require(
          try JSONSerialization.jsonObject(with: Data(contentsOf: outboxURL)) as? [String: Any]
        )
        var progress = try #require(document["progress"] as? [[String: Any]])
        let progressIndex = try #require(progress.firstIndex(where: {
          $0["subscriptionID"] as? String == subscriptionID
        }))
        progress[progressIndex]["requiresPreparedResponseFence"] = true
        progress[progressIndex].removeValue(forKey: "preparedResponseFence")
        document["progress"] = progress
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
          .write(to: outboxURL, options: .atomic)

        var missingFenceMarkerRejected = false
        do {
          _ = try fixture.outboxStore.load()
        } catch let error as AgentEventOutboxError {
          missingFenceMarkerRejected = error == .storageFailure
        }
        #expect(missingFenceMarkerRejected)
        #expect(await authorizationService.observeEligibility(
          for: attempt,
          workspaceProvider: { await state.workspace }
        ) == nil)
        let finalAuthorizationAcceptsMissingFence = await authorizationService.isCurrent(
          finalObservation,
          for: attempt,
          workspaceProvider: { await state.workspace }
        )
        #expect(!finalAuthorizationAcceptsMissingFence)
      }
    }

    @Test @MainActor func cancellationDuringProspectiveOwnerGenerationCASFailsFenceAcrossRestart()
      async throws
    {
      try await assertProspectiveGenerationFenceAfterR1Termination(timesOut: false)
    }

    @Test @MainActor func approvalTimeoutDuringProspectiveOwnerGenerationCASFailsFenceAcrossRestart()
      async throws
    {
      try await assertProspectiveGenerationFenceAfterR1Termination(timesOut: true)
    }

    @Test @MainActor
    func preCASOwnerCancellationAndR1OFFWriteFailureKeepAutoRenewedGenerationFencedAcrossRestart()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let initialWorkspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let subscriptionID = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: initialWorkspace
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: true,
          workspaceProvider: { initialWorkspace }
        )
        let predecessor = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let predecessorControl = try #require(predecessor.deliveryControl)
        #expect(predecessorControl.enabled)
        #expect(predecessorControl.allowsAutomaticRenewal)

        let renewal = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { initialWorkspace },
          now: fixture.clock.now()
        )
        let renewed = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let ownerControl = try #require(renewed.deliveryControl)
        #expect(renewed.revision == renewal.revision)
        #expect(renewed.revision > predecessor.revision)
        #expect(ownerControl.generationID != predecessorControl.generationID)
        #expect(ownerControl.enabled)
        #expect(ownerControl.allowsAutomaticRenewal)

        let binding = verificationBinding(for: renewed)
        let requestOriginID = UUID()
        let proof = try await fixture.monitoringService.anchorAndVerifyPendingSubscription(
          profileID: fixture.profileID,
          subscriptionID: subscriptionID,
          workspaceProvider: { initialWorkspace },
          ownerDeliveryControl: ownerControl,
          requestOriginID: requestOriginID,
          now: fixture.clock.now()
        )
        #expect(proof.originIntentID == requestOriginID)

        var changedWorkspace = initialWorkspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title = "Pending event during auto-renewed owner response"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        let state = RuntimeTestWorkspaceState(workspace: changedWorkspace)
        _ = try await fixture.localStore.save(
          workspace: changedWorkspace,
          preferences: .init(),
          generation: 2
        )
        fixture.clock.advance(by: 2)
        try await fixture.outboxService.capturePending(
          profileID: fixture.profileID,
          subscriptionID: subscriptionID,
          now: fixture.clock.now()
        )
        let pendingBody = try #require(
          try fixture.outboxStore.load().entries.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.body
        )

        let preparedProof = try await fixture.monitoringService.anchorAndVerifyPendingSubscription(
          profileID: fixture.profileID,
          subscriptionID: subscriptionID,
          workspaceProvider: { await state.workspace },
          ownerDeliveryControl: ownerControl,
          requestOriginID: requestOriginID,
          preparedResponseOriginID: requestOriginID,
          now: fixture.clock.now()
        )
        let preparedFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.preparedResponseFence
        )
        #expect(preparedFence.binding == binding)
        #expect(preparedFence.ownerControlGenerationID == ownerControl.generationID)
        #expect(preparedFence.originIntentID == requestOriginID)
        #expect(preparedFence.disposition == .awaitingResponse)
        #expect(preparedProof.originIntentID == requestOriginID)
        #expect(
          try fixture.outboxStore.load().entries.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.body == pendingBody
        )

        let ledgerService = AgentEventDeliveryLedgerService(
          outboxStore: fixture.outboxStore,
          subscriptionStore: fixture.subscriptionStore,
          ledgerStore: fixture.ledgerStore
        )
        let reservation = try #require(
          try await ledgerService.reserveNext(
            profileID: fixture.profileID,
            subscriptionID: subscriptionID
          )
        )
        let attempt = try await ledgerService.observe(reservation)
        let authorizationService = AgentEventDeliveryAuthorizationService(
          authority: fixture.authority,
          profileStore: fixture.profileStore,
          subscriptionStore: fixture.subscriptionStore,
          verificationStore: fixture.verificationStore,
          outboxStore: fixture.outboxStore,
          ledgerStore: fixture.ledgerStore,
          now: { fixture.clock.now() }
        )

        let prospectiveGenerationID = UUID()
        let prospectiveFenceWriteGate = fixture.outboxFileWriter.pauseNextWrite()
        let outboxService = fixture.outboxService
        let subscriptionStore = fixture.subscriptionStore
        let ownerTask = Task.detached {
          do {
            try outboxService.armProspectivePreparedResponseFence(
              binding: binding,
              expectedOwnerDeliveryControl: ownerControl,
              prospectiveGenerationID: prospectiveGenerationID,
              originIntentID: requestOriginID
            )
            try Task.checkCancellation()
            guard try await subscriptionStore.setOwnerDeliveryEligibility(
              binding: binding,
              expectedGenerationID: ownerControl.generationID,
              eligible: true,
              allowsAutomaticRenewal: true,
              prospectiveGenerationID: prospectiveGenerationID
            ) != nil else {
              throw AgentEventOutboxError.sourceChanged
            }
          } catch {
            try? outboxService.failProspectivePreparedResponseFence(
              binding: binding,
              prospectiveGenerationID: prospectiveGenerationID,
              originIntentID: requestOriginID
            )
            throw error
          }
        }
        defer {
          prospectiveFenceWriteGate.release()
          ownerTask.cancel()
        }
        let reachedProspectiveFenceWrite = await prospectiveFenceWriteGate.waitUntilEntered()
        #expect(reachedProspectiveFenceWrite)
        ownerTask.cancel()
        prospectiveFenceWriteGate.release()
        let ownerResult = await ownerTask.result
        if case .success = ownerResult {
          Issue.record("A pre-CAS owner cancellation must stop the prospective generation.")
        }

        let currentBeforeR1Cleanup = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let prospectiveFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.preparedResponseFence
        )
        #expect(currentBeforeR1Cleanup.deliveryControl == ownerControl)
        #expect(prospectiveFence.binding == binding)
        #expect(prospectiveFence.ownerControlGenerationID == prospectiveGenerationID)
        #expect(prospectiveFence.originIntentID == requestOriginID)
        #expect(prospectiveFence.disposition == .awaitingResponse)
        #expect(!fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: ownerControl
        ))
        #expect(await authorizationService.observeEligibility(
          for: attempt,
          workspaceProvider: { await state.workspace }
        ) == nil)
        let finalObservation = AgentEventDeliveryEligibilityObservation(
          profileID: binding.profileID,
          subscriptionID: binding.subscriptionID,
          eventID: reservation.eventID,
          reservationID: reservation.id,
          ledgerGenerationID: reservation.bindingGenerationID,
          ownerControlGenerationID: ownerControl.generationID,
          proofGenerationID: proof.originIntentID,
          expectedTemporaryExclusionGeneration: authorizationService
            .temporaryExclusionGeneration
        )
        let finalAuthorizationIsCurrent = await authorizationService.isCurrent(
          finalObservation,
          for: attempt,
          workspaceProvider: { await state.workspace }
        )
        #expect(!finalAuthorizationIsCurrent)

        try fixture.outboxService.failPreparedResponseFence(
          binding: binding,
          ownerDeliveryControl: ownerControl,
          originIntentID: requestOriginID
        )
        try fixture.verificationStore.removeProof(
          for: binding,
          generatedBy: requestOriginID
        )
        fixture.subscriptionFileWriter.failAfterSuccessfulWrites()
        var ownerOFFWriteFailed = false
        do {
          _ = try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
            binding: binding,
            expectedGenerationID: ownerControl.generationID,
            eligible: false
          )
        } catch {
          ownerOFFWriteFailed = true
        }
        #expect(ownerOFFWriteFailed)

        let currentAfterR1Cleanup = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let progressAfterR1Cleanup = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })
        )
        #expect(currentAfterR1Cleanup.deliveryControl == ownerControl)
        #expect(currentAfterR1Cleanup.deliveryControl?.enabled == true)
        #expect(currentAfterR1Cleanup.deliveryControl?.allowsAutomaticRenewal == true)
        #expect(progressAfterR1Cleanup.status == .pending)
        #expect(progressAfterR1Cleanup.requiresPreparedResponseFence)
        #expect(progressAfterR1Cleanup.preparedResponseFence == prospectiveFence)
        #expect(
          try fixture.outboxStore.load().entries.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.body != nil
        )
        #expect(!fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: ownerControl
        ))

        let callbackCount = await fixture.callbackExchange.requestCount()
        let applicationCount = await fixture.applicationExchange.requestCount()
        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == callbackCount)
        #expect(await fixture.applicationExchange.requestCount() == applicationCount)
        await reopenedRuntime.stop()
      }
    }

    @MainActor
    private func assertProspectiveGenerationFenceAfterR1Termination(
      timesOut: Bool
    ) async throws {
      try await withAgentEventMonitoringRuntimeFixture(
        approvalWaitLimit: timesOut ? .seconds(1) : .seconds(5)
      ) { fixture in
        let initialWorkspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let subscriptionID = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: initialWorkspace
        )
        var changedWorkspace = initialWorkspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title = "Pending event at prospective owner-generation CAS"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        _ = try await fixture.localStore.save(
          workspace: changedWorkspace,
          preferences: .init(),
          generation: 2
        )
        try await fixture.outboxService.capturePending(
          profileID: fixture.profileID,
          subscriptionID: subscriptionID,
          now: fixture.clock.now()
        )
        fixture.clock.advance(by: 2)
        #expect(
          try fixture.outboxStore.load().entries.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.body != nil
        )

        let original = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let state = RuntimeTestWorkspaceState(workspace: changedWorkspace)
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        defer { command.task.cancel() }
        let pending = try await fixture.waitForSubscription(
          id: subscriptionID,
          afterRevision: original.revision
        )
        let initialProgress = try await fixture.waitForPreparedResponseFence(
          id: subscriptionID,
          revision: pending.revision
        )
        try await Task.sleep(for: .milliseconds(50))
        let initialControl = try #require(pending.deliveryControl)
        let initialFence = try #require(initialProgress.preparedResponseFence)
        let callbackCount = await fixture.callbackExchange.requestCount()
        let subscriptionURL = fixture.rootURL
          .appendingPathComponent("events", isDirectory: true)
          .appendingPathComponent("subscriptions.json")
        let subscriptionBytesBeforeCAS = try Data(contentsOf: subscriptionURL)
        let prospectiveFenceWriteGate = fixture.outboxFileWriter.pauseNextWrite()
        let storeWriteGate = fixture.subscriptionFileWriter.pauseNextWrite()
        let ownerTask = Task {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: command.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { await state.workspace }
          )
        }
        defer {
          prospectiveFenceWriteGate.release()
          storeWriteGate.release()
          ownerTask.cancel()
        }

        let reachedFenceWrite = await prospectiveFenceWriteGate.waitUntilEntered()
        #expect(reachedFenceWrite)
        prospectiveFenceWriteGate.release()
        let reachedOnCAS = await storeWriteGate.waitUntilEntered()
        #expect(reachedOnCAS)
        let fencedBeforeONCAS = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(fencedBeforeONCAS.binding == initialFence.binding)
        #expect(fencedBeforeONCAS.originIntentID == initialFence.originIntentID)
        #expect(fencedBeforeONCAS.ownerControlGenerationID != initialControl.generationID)
        #expect(fencedBeforeONCAS.disposition == .awaitingResponse)
        #expect(try Data(contentsOf: subscriptionURL) == subscriptionBytesBeforeCAS)

        if timesOut {
          try await Task.sleep(for: .milliseconds(1_200))
        } else {
          command.task.cancel()
          ownerTask.cancel()
        }
        prospectiveFenceWriteGate.release()
        storeWriteGate.release()

        let commandResult = await command.task.result
        if case .success = commandResult {
          Issue.record("R1 cancellation or owner-approval timeout must fail the prepared response.")
        }
        let ownerResult = await ownerTask.result
        if case .success = ownerResult {
          Issue.record("R1 cancellation or timeout during the ON CAS must fail owner approval.")
        }

        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let currentControl = try #require(current.deliveryControl)
        let currentFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(currentControl.enabled)
        #expect(currentControl.generationID != initialControl.generationID)
        #expect(currentFence.binding == verificationBinding(for: current))
        #expect(currentFence.originIntentID == initialFence.originIntentID)
        #expect(currentFence.ownerControlGenerationID == currentControl.generationID)
        #expect(currentFence.disposition == .failedResponse)
        #expect(!fixture.outboxService.admitsDelivery(
          binding: verificationBinding(for: current),
          ownerDeliveryControl: currentControl
        ))
        #expect(await fixture.callbackExchange.requestCount() == callbackCount)

        let ledgerService = AgentEventDeliveryLedgerService(
          outboxStore: fixture.outboxStore,
          subscriptionStore: fixture.subscriptionStore,
          ledgerStore: fixture.ledgerStore
        )
        let reservation = try #require(
          try await ledgerService.reserveNext(
            profileID: fixture.profileID,
            subscriptionID: command.subscriptionID
          )
        )
        let attempt = try await ledgerService.observe(reservation)
        let authorizationService = AgentEventDeliveryAuthorizationService(
          authority: fixture.authority,
          profileStore: fixture.profileStore,
          subscriptionStore: fixture.subscriptionStore,
          verificationStore: fixture.verificationStore,
          outboxStore: fixture.outboxStore,
          ledgerStore: fixture.ledgerStore,
          now: { fixture.clock.now() }
        )
        #expect(await authorizationService.observeEligibility(
          for: attempt,
          workspaceProvider: { await state.workspace }
        ) == nil)
        let finalObservation = AgentEventDeliveryEligibilityObservation(
          profileID: currentFence.binding.profileID,
          subscriptionID: currentFence.binding.subscriptionID,
          eventID: reservation.eventID,
          reservationID: reservation.id,
          ledgerGenerationID: reservation.bindingGenerationID,
          ownerControlGenerationID: currentControl.generationID,
          proofGenerationID: currentFence.originIntentID,
          expectedTemporaryExclusionGeneration: authorizationService
            .temporaryExclusionGeneration
        )
        let finalAuthorizationIsCurrent = await authorizationService.isCurrent(
          finalObservation,
          for: attempt,
          workspaceProvider: { await state.workspace }
        )
        #expect(!finalAuthorizationIsCurrent)

        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == callbackCount)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()
      }
    }

    @Test @MainActor func failedOwnerApprovalFenceAdvanceKeepsNewGenerationBlocked() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let initial = try await fixture.waitForSubscription(id: command.subscriptionID)
        let binding = verificationBinding(for: initial)
        let initialProgress = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: initial.revision
        )
        let originalFence = try #require(initialProgress.preparedResponseFence)
        var changedWorkspace = state.workspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title = "Registration failure after prospective fence arm"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        _ = try await fixture.localStore.save(
          workspace: changedWorkspace,
          preferences: .init(),
          generation: 2
        )
        state.replaceWorkspace(changedWorkspace)
        await fixture.snapshotReaderGate.failOnce(afterSequence: 0)
        let callbackCount = await fixture.callbackExchange.requestCount()

        var registrationFailed = false
        do {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: command.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { await state.workspace }
          )
        } catch {
          registrationFailed = true
        }
        #expect(registrationFailed)
        #expect(await fixture.snapshotReaderGate.injectedFailureCount() == 1)
        let renewed = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let renewedControl = try #require(renewed.deliveryControl)
        #expect(renewedControl.enabled)
        #expect(renewedControl.generationID != originalFence.ownerControlGenerationID)
        #expect(originalFence.disposition == .awaitingResponse)

        command.task.cancel()
        await expectCommandFailure(command.task)
        let retainedFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(retainedFence.binding == binding)
        #expect(retainedFence.ownerControlGenerationID == renewedControl.generationID)
        #expect(retainedFence.originIntentID == originalFence.originIntentID)
        #expect(retainedFence.disposition == .failedResponse)
        #expect(!fixture.outboxService.admitsDelivery(
          binding: verificationBinding(for: renewed),
          ownerDeliveryControl: renewedControl
        ))

        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == callbackCount)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()
      }
    }

    @Test @MainActor func failedOutboxCleanupFenceSurvivesRuntimeRestart() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let execution = try await command.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("Expected the prepared response to retain its disposition callback.")
          return
        }
        let beforeWrites = fixture.outboxFileWriter.successfulWriteCount()
        fixture.outboxFileWriter.failAfterSuccessfulWrites(1)
        await responseDisposition(false)

        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        #expect(current.deliveryControl?.enabled == false)
        #expect(fixture.outboxFileWriter.successfulWriteCount() == beforeWrites + 1)
        let progress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })
        )
        #expect(progress.preparedResponseFence?.disposition == .failedResponse)

        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == 1)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()
      }
    }

    @Test @MainActor func failedOwnerOffPersistenceFenceSurvivesRuntimeRestart() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let execution = try await command.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("Expected the prepared response to retain its disposition callback.")
          return
        }
        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let binding = verificationBinding(for: current)
        let ownerControl = try #require(current.deliveryControl)
        let callbackCount = await fixture.callbackExchange.requestCount()
        fixture.subscriptionFileWriter.failAfterSuccessfulWrites()
        await responseDisposition(false)

        let afterFailure = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        #expect(afterFailure.deliveryControl == ownerControl)
        #expect(afterFailure.deliveryControl?.enabled == true)
        #expect(try fixture.verificationStore.currentProof(for: binding) == nil)
        #expect(!fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: ownerControl
        ))
        let failedFence = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(failedFence.disposition == .failedResponse)
        #expect(failedFence.ownerControlGenerationID == ownerControl.generationID)

        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == callbackCount)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()
      }
    }

    @Test @MainActor func failedProofRemovalKeepsPendingDeliveryDeniedUntilPreparedR2Writes()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let initialWorkspace = Workspace(
          notes: [fixture.note],
          selectedNoteID: fixture.note.id
        )
        let subscriptionID = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: initialWorkspace
        )
        var changedWorkspace = initialWorkspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title = "Pending proof-removal failure event"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        _ = try await fixture.localStore.save(
          workspace: changedWorkspace,
          preferences: .init(),
          generation: 2
        )
        try await fixture.outboxService.capturePending(
          profileID: fixture.profileID,
          subscriptionID: subscriptionID,
          now: fixture.clock.now()
        )
        #expect(
          try fixture.outboxStore.load().entries.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.body != nil
        )

        let initialSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let state = RuntimeTestWorkspaceState(workspace: changedWorkspace)
        let firstCommand = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let firstPending = try await fixture.waitForSubscription(
          id: subscriptionID,
          afterRevision: initialSubscription.revision
        )
        _ = try await fixture.waitForPreparedResponseFence(
          id: subscriptionID,
          revision: firstPending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let firstExecution = try await firstCommand.task.value
        guard case .verifiedEventSubscription = firstExecution.response,
          let firstResponseDisposition = firstExecution.responseDisposition
        else {
          Issue.record("Expected the first prepared response to retain its disposition callback.")
          return
        }
        let firstSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let firstBinding = verificationBinding(for: firstSubscription)
        let firstControl = try #require(firstSubscription.deliveryControl)
        let committedProof = try #require(
          try fixture.verificationStore.currentProof(for: firstBinding)
        )
        fixture.verificationFileWriter.failAfterSuccessfulWrites()
        fixture.subscriptionFileWriter.failAfterSuccessfulWrites()
        await firstResponseDisposition(false)

        let failedSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        #expect(failedSubscription.deliveryControl == firstControl)
        #expect(failedSubscription.deliveryControl?.enabled == true)
        #expect(try fixture.verificationStore.currentProof(for: firstBinding) == committedProof)
        let failedProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })
        )
        #expect(failedProgress.status == .pending)
        #expect(failedProgress.requiresPreparedResponseFence)
        #expect(failedProgress.preparedResponseFence?.disposition == .failedResponse)
        #expect(
          failedProgress.preparedResponseFence?.ownerControlGenerationID
            == firstControl.generationID
        )
        #expect(
          try fixture.outboxStore.load().entries.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })?.body != nil
        )
        #expect(!fixture.outboxService.admitsDelivery(
          binding: firstBinding,
          ownerDeliveryControl: firstControl
        ))

        let ledgerService = AgentEventDeliveryLedgerService(
          outboxStore: fixture.outboxStore,
          subscriptionStore: fixture.subscriptionStore,
          ledgerStore: fixture.ledgerStore
        )
        let reservation = try #require(
          try await ledgerService.reserveNext(
            profileID: fixture.profileID,
            subscriptionID: subscriptionID
          )
        )
        let attempt = try await ledgerService.observe(reservation)
        let authorizationService = AgentEventDeliveryAuthorizationService(
          authority: fixture.authority,
          profileStore: fixture.profileStore,
          subscriptionStore: fixture.subscriptionStore,
          verificationStore: fixture.verificationStore,
          outboxStore: fixture.outboxStore,
          ledgerStore: fixture.ledgerStore,
          now: { fixture.clock.now() }
        )
        #expect(await authorizationService.observeEligibility(
          for: attempt,
          workspaceProvider: { await state.workspace }
        ) == nil)
        let finalObservation = AgentEventDeliveryEligibilityObservation(
          profileID: firstBinding.profileID,
          subscriptionID: firstBinding.subscriptionID,
          eventID: reservation.eventID,
          reservationID: reservation.id,
          ledgerGenerationID: reservation.bindingGenerationID,
          ownerControlGenerationID: firstControl.generationID,
          proofGenerationID: committedProof.originIntentID,
          expectedTemporaryExclusionGeneration: authorizationService
            .temporaryExclusionGeneration
        )
        let finalAuthorizationRemainsCurrent = await authorizationService.isCurrent(
          finalObservation,
          for: attempt,
          workspaceProvider: { await state.workspace }
        )
        #expect(!finalAuthorizationRemainsCurrent)
        let cancelledReservation = try await ledgerService.cancel(reservation)
        #expect(cancelledReservation.status == .retryWaiting)
        #expect(cancelledReservation.failureCategory == .cancelled)

        let callbackCount = await fixture.callbackExchange.requestCount()
        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == callbackCount)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()

        let secondCommand = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let secondPending = try await fixture.waitForSubscription(
          id: subscriptionID,
          afterRevision: firstPending.revision
        )
        _ = try await fixture.waitForPreparedResponseFence(
          id: subscriptionID,
          revision: secondPending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let secondExecution = try await secondCommand.task.value
        guard case .verifiedEventSubscription = secondExecution.response,
          let secondResponseDisposition = secondExecution.responseDisposition
        else {
          Issue.record("Expected the explicit R2 response to retain its disposition callback.")
          return
        }
        await secondResponseDisposition(true)
        let releasedSubscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
        )
        let releasedBinding = verificationBinding(for: releasedSubscription)
        let releasedControl = try #require(releasedSubscription.deliveryControl)
        let releasedProgress = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
          })
        )
        #expect(releasedControl.enabled)
        #expect(releasedProgress.preparedResponseFence == nil)
        #expect(!releasedProgress.requiresPreparedResponseFence)
        #expect(fixture.outboxService.admitsDelivery(
          binding: releasedBinding,
          ownerDeliveryControl: releasedControl
        ))

        await fixture.runtime.start { await state.workspace }
        let bodies = await fixture.waitForApplicationBodies(count: 1)
        #expect(bodies.count == 1)
        #expect(await fixture.applicationExchange.requestCount() == 1)
        if let body = bodies.first {
          #expect(try JSONDecoder().decode(AgentEventEnvelope.self, from: body).name == .noteUpdated)
        }
      }
    }

    @Test @MainActor func staleR1ResponseLeaseDoesNotBlockNewerR2Drain() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let workspace = state.workspace
        let firstCommand = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let firstPending = try await fixture.waitForSubscription(id: firstCommand.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: firstCommand.subscriptionID,
          revision: firstPending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: firstCommand.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let firstExecution = try await firstCommand.task.value
        guard case .verifiedEventSubscription = firstExecution.response,
          let firstResponseDisposition = firstExecution.responseDisposition
        else {
          Issue.record("Expected R1 to retain its response lease while R2 is prepared.")
          return
        }
        let firstBinding = verificationBinding(for: firstPending)

        let secondCommand = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let secondPending = try await fixture.waitForSubscription(
          id: secondCommand.subscriptionID,
          afterRevision: firstPending.revision
        )
        _ = try await fixture.waitForPreparedResponseFence(
          id: secondCommand.subscriptionID,
          revision: secondPending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: secondCommand.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let secondExecution = try await secondCommand.task.value
        guard case .verifiedEventSubscription = secondExecution.response,
          let secondResponseDisposition = secondExecution.responseDisposition
        else {
          Issue.record("Expected R2 to retain its response lease through full response write.")
          return
        }
        await secondResponseDisposition(true)
        let approved = try #require(
          await fixture.subscriptionStore.currentSubscription(id: secondCommand.subscriptionID)
        )
        let approvedBinding = verificationBinding(for: approved)
        let approvedControl = try #require(approved.deliveryControl)
        #expect(approvedBinding != firstBinding)
        #expect(fixture.outboxService.admitsDelivery(
          binding: approvedBinding,
          ownerDeliveryControl: approvedControl
        ))

        var changedWorkspace = workspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title = "R2 drain while R1 response remains stale"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        _ = try await fixture.localStore.save(
          workspace: changedWorkspace,
          preferences: .init(),
          generation: 2
        )
        state.replaceWorkspace(changedWorkspace)
        await fixture.runtime.start { await state.workspace }
        let bodies = await fixture.waitForApplicationBodies(count: 1)
        #expect(bodies.count == 1)
        #expect(await fixture.applicationExchange.requestCount() == 1)

        await firstResponseDisposition(false)
        let afterStaleR1Release = try #require(
          await fixture.subscriptionStore.currentSubscription(id: secondCommand.subscriptionID)
        )
        #expect(afterStaleR1Release.deliveryControl == approvedControl)
        #expect(fixture.outboxService.admitsDelivery(
          binding: approvedBinding,
          ownerDeliveryControl: approvedControl
        ))
        await fixture.runtime.stop()
      }
    }

    @Test @MainActor func failedFenceClearAfterWrittenResponseRemainsFailClosed() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let execution = try await command.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("Expected the prepared response to retain its disposition callback.")
          return
        }
        let before = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        fixture.outboxFileWriter.failAfterSuccessfulWrites()
        await responseDisposition(true)
        let after = try #require(
          fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence
        )
        #expect(after == before)
        #expect(after.disposition == .awaitingResponse)

        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == 1)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()
      }
    }

    @Test @MainActor func missingRequiredResponseFenceFailsClosedAfterRestart() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let execution = try await command.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("Expected the prepared response to retain its disposition callback.")
          return
        }
        let subscription = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let binding = verificationBinding(for: subscription)
        let control = try #require(subscription.deliveryControl)
        var document = try #require(
          try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.outboxStore.fileURL))
            as? [String: Any]
        )
        var progress = try #require(document["progress"] as? [[String: Any]])
        var row = try #require(progress.first)
        row.removeValue(forKey: "preparedResponseFence")
        progress[0] = row
        document["progress"] = progress
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
          .write(to: fixture.outboxStore.fileURL, options: .atomic)

        #expect(throws: AgentEventOutboxError.storageFailure) {
          try fixture.outboxStore.load()
        }
        #expect(!fixture.outboxService.admitsDelivery(
          binding: binding,
          ownerDeliveryControl: control
        ))

        let reopenedRuntime = fixture.makeReopenedRuntime()
        await reopenedRuntime.start { await state.workspace }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.callbackExchange.requestCount() == 1)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await reopenedRuntime.stop()
        await responseDisposition(false)
      }
    }

    @Test @MainActor func successfulPreparedResponseClearsItsFenceExactlyOnce() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { await state.workspace }
        )
        let execution = try await command.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("Expected the prepared response to retain its disposition callback.")
          return
        }
        let beforeWrites = fixture.outboxFileWriter.successfulWriteCount()
        await fixture.runtime.stop()
        await responseDisposition(true)
        let clearedWrites = fixture.outboxFileWriter.successfulWriteCount()
        #expect(clearedWrites == beforeWrites + 1)
        #expect(
          try fixture.outboxStore.load().progress.first(where: {
            $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
          })?.preparedResponseFence == nil
        )

        await responseDisposition(true)
        #expect(fixture.outboxFileWriter.successfulWriteCount() == clearedWrites)
      }
    }

    @Test @MainActor func oldPreparedResponseCannotClearNewerBindingProgress() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPreparedEventSubscriptionIPCCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: true,
          workspaceProvider: { await state.workspace }
        )
        let execution = try await command.task.value
        guard case .verifiedEventSubscription = execution.response,
          let responseDisposition = execution.responseDisposition
        else {
          Issue.record("Expected the prepared response to retain its disposition callback.")
          return
        }
        let first = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let secondReceipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { await state.workspace },
          now: fixture.clock.now()
        )
        let second = try #require(
          await fixture.subscriptionStore.currentSubscription(id: secondReceipt.subscriptionID)
        )
        let secondControl = try #require(second.deliveryControl)
        let secondOriginID = UUID()
        try await fixture.outboxService.registerPending(
          profileID: fixture.profileID,
          subscriptionID: secondReceipt.subscriptionID,
          now: fixture.clock.now(),
          ownerDeliveryControl: secondControl,
          preparedResponseOriginID: secondOriginID
        )
        let before = try fixture.outboxStore.load()
        let secondProgress = try #require(before.progress.first(where: {
          $0.profileID == fixture.profileID && $0.subscriptionID == command.subscriptionID
        }))
        #expect(second.revision > first.revision)
        #expect(secondControl.enabled)
        #expect(secondProgress.subscriptionRevision == second.revision)
        #expect(secondProgress.preparedResponseFence?.originIntentID == secondOriginID)

        await fixture.runtime.stop()
        await responseDisposition(true)
        #expect(try fixture.outboxStore.load() == before)
      }
    }

    @Test @MainActor func renewedProofAndOffOnAbaInvalidateVerifiedResponse() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        var failureStage = "starting the prepare command"
        var completed = false
        defer {
          if !completed {
            Issue.record("Renewal/ABA fixture threw during stage: \(failureStage).")
          }
        }
        let gate = RuntimeTestAsyncGate()
        defer { Task { await gate.release() } }
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id),
          refreshGate: gate
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        failureStage = "waiting for the pending subscription"
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        let workspace = state.workspace
        failureStage = "enabling the original owner control"
        do {
          try await fixture.runtime.setOwnerDeliveryConsent(
            subscriptionID: command.subscriptionID,
            enabled: true,
            allowsAutomaticRenewal: false,
            workspaceProvider: { workspace }
          )
        } catch let error as AgentEventOutboxError {
          Issue.record(
            """
            Owner-control enable failed in outbox registration (sourceChanged: \(error == .sourceChanged)).
            """
          )
          throw error
        }
        await gate.waitUntilEntered()

        failureStage = "reading the current subscription"
        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        let currentControl = try #require(current.deliveryControl)
        let binding = verificationBinding(for: current)
        failureStage = "reading the previous proof"
        let previousProof = try #require(
          try await fixture.verificationStore.currentProof(for: binding)
        )
        failureStage = "removing the previous proof"
        try await fixture.verificationStore.removeProof(
          for: binding,
          generatedBy: previousProof.originIntentID
        )
        fixture.clock.advance(by: 601)
        #expect(current.expiresAt > fixture.clock.now())
        failureStage = "renewing the proof"
        let renewedProof = try await fixture.monitoringService.anchorAndVerifyPendingSubscription(
          profileID: fixture.profileID,
          subscriptionID: command.subscriptionID,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        #expect(renewedProof.binding == binding)
        #expect(renewedProof.originIntentID != previousProof.originIntentID)

        failureStage = "turning owner delivery off"
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: nil
        )
        failureStage = "checking the disabled owner control"
        let disabled = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl
        )
        #expect(!disabled.enabled)
        failureStage = "turning owner delivery back on"
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        failureStage = "checking the replacement owner control"
        let reenabled = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl
        )
        #expect(reenabled.enabled)
        #expect(reenabled.generationID != currentControl.generationID)

        await gate.release()
        failureStage = "checking the in-flight command result"
        await expectCommandFailure(command.task)
        #expect(await fixture.callbackExchange.requestCount() == 2)
        completed = true
      }
    }

    @Test @MainActor func ownerControlChangesDuringCallbackVerificationRejectOldApproval()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let gate = RuntimeTestAsyncGate()
        await fixture.callbackExchange.blockNextResponse(until: gate)
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )

        let workspace = state.workspace
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()
        let approvedControl = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: nil
        )
        let disabledControl = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl
        )
        #expect(!disabledControl.enabled)
        #expect(await fixture.applicationExchange.requestCount() == 0)

        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let reenabledControl = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl
        )
        #expect(reenabledControl.enabled)
        #expect(reenabledControl.generationID != approvedControl.generationID)

        await gate.release()
        await expectCommandFailure(command.task)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)
        )
        #expect(
          try await fixture.verificationStore.currentProof(for: verificationBinding(for: current))
            == nil
        )
      }
    }

    @Test @MainActor func ownerControlChangesDuringPostVerificationScopeCheckRejectOldApproval()
      async throws
    {
      let gate = RuntimeTestAsyncGate()
      try await withAgentEventMonitoringRuntimeFixture(
        scopeAuthorizationGate: gate,
        scopeAuthorizationGateOnCall: 2
      ) { fixture in
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        let workspace = state.workspace
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()

        let approvedControl = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: false,
          allowsAutomaticRenewal: false,
          workspaceProvider: nil
        )
        let disabledControl = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl
        )
        #expect(!disabledControl.enabled)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        let reenabledControl = try #require(
          await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID)?
            .deliveryControl
        )
        #expect(reenabledControl.enabled)
        #expect(reenabledControl.generationID != approvedControl.generationID)

        await gate.release()
        await expectCommandFailure(command.task)
        #expect(await fixture.applicationExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func removalDuringResponseRefreshInvalidatesVerifiedResponse() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let gate = RuntimeTestAsyncGate()
        defer { Task { await gate.release() } }
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id),
          refreshGate: gate
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        let workspace = state.workspace
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()

        try await fixture.runtime.removeSubscription(subscriptionID: command.subscriptionID)
        await gate.release()
        await expectCommandFailure(command.task)

        #expect(
          try await fixture.subscriptionStore.currentSubscription(id: command.subscriptionID) == nil
        )
      }
    }

    @Test @MainActor func ordinaryWorkspaceEditDoesNotInvalidateVerifiedResponse() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let gate = RuntimeTestAsyncGate()
        defer { Task { await gate.release() } }
        let state = RuntimeTestWorkspaceState(
          workspace: Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id),
          refreshGate: gate
        )
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        let workspace = state.workspace
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()

        var editedWorkspace = state.workspace
        var editedNote = try #require(editedWorkspace.notes.first)
        editedNote.title += " edited while response refresh waits"
        editedNote.revision += 1
        editedWorkspace.notes[0] = editedNote
        state.replaceWorkspace(editedWorkspace)
        await gate.release()

        let response = try await command.task.value
        guard case .verifiedEventSubscription(let receipt) = response else {
          Issue.record("An ordinary workspace edit must not invalidate the verified receipt.")
          return
        }
        #expect(receipt.subscriptionID == command.subscriptionID)
      }
    }

    @Test @MainActor func movingNoteOutOfInheritedGrantDuringResponseRefreshFailsClosed()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let workspace = try await workspaceUnderFutureFolderGrant(fixture: fixture)
        let gate = RuntimeTestAsyncGate()
        defer { Task { await gate.release() } }
        let state = RuntimeTestWorkspaceState(workspace: workspace, refreshGate: gate)
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()

        var movedWorkspace = state.workspace
        movedWorkspace.notes[0].folderID = nil
        state.replaceWorkspace(movedWorkspace)
        await gate.release()
        await expectCommandFailure(command.task)
        #expect(await fixture.applicationExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func deletingRequestedNoteDuringResponseRefreshFailsClosed() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let gate = RuntimeTestAsyncGate()
        defer { Task { await gate.release() } }
        let workspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let state = RuntimeTestWorkspaceState(workspace: workspace, refreshGate: gate)
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()

        state.replaceWorkspace(Workspace(notes: [], selectedNoteID: nil))
        await gate.release()
        await expectCommandFailure(command.task)
        #expect(await fixture.applicationExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func deletingRequestedFolderDuringResponseRefreshFailsClosed() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let gate = RuntimeTestAsyncGate()
        defer { Task { await gate.release() } }
        let workspace = try await workspaceUnderFutureFolderGrant(fixture: fixture)
        let folderID = try #require(workspace.folders.first?.id)
        let scope = AgentEventScope.folder(folderID: folderID)
        let state = RuntimeTestWorkspaceState(workspace: workspace, refreshGate: gate)
        let command = startPrepareEventSubscriptionCommand(
          fixture: fixture,
          state: state,
          scope: scope
        )
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()

        state.replaceWorkspace(Workspace(notes: [], selectedNoteID: nil))
        await gate.release()
        await expectCommandFailure(command.task)
        #expect(await fixture.applicationExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func scopeMembershipChangeDuringFinalAuthorizationFailsClosed()
      async throws
    {
      let gate = RuntimeTestAsyncGate()
      try await withAgentEventMonitoringRuntimeFixture(
        scopeAuthorizationGate: gate,
        scopeAuthorizationGateOnCall: 3
      ) { fixture in
        let workspace = try await workspaceUnderFutureFolderGrant(fixture: fixture)
        let state = RuntimeTestWorkspaceState(workspace: workspace)
        let command = startPrepareEventSubscriptionCommand(fixture: fixture, state: state)
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()

        var movedWorkspace = state.workspace
        movedWorkspace.notes[0].folderID = nil
        state.replaceWorkspace(movedWorkspace)
        await gate.release()
        await expectCommandFailure(command.task)
        #expect(await fixture.applicationExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func scopeMembershipChangeAfterFinalAuthorizationReturnFailsClosed()
      async throws
    {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let workspace = try await workspaceUnderFutureFolderGrant(fixture: fixture)
        let gate = RuntimeTestAsyncGate()
        defer { Task { await gate.release() } }
        let state = RuntimeTestWorkspaceState(workspace: workspace)
        let capabilityAuthority = RuntimeTestCapabilityAuthority(
          authority: fixture.authority,
          assertionGate: gate,
          pauseOnAssertion: 2
        )
        let command = startPrepareEventSubscriptionCommand(
          fixture: fixture,
          state: state,
          capabilityAuthority: capabilityAuthority
        )
        let pending = try await fixture.waitForSubscription(id: command.subscriptionID)
        _ = try await fixture.waitForPreparedResponseFence(
          id: command.subscriptionID,
          revision: pending.revision
        )
        try await fixture.runtime.setOwnerDeliveryConsent(
          subscriptionID: command.subscriptionID,
          enabled: true,
          allowsAutomaticRenewal: false,
          workspaceProvider: { workspace }
        )
        await gate.waitUntilEntered()

        var movedWorkspace = state.workspace
        movedWorkspace.notes[0].folderID = nil
        state.replaceWorkspace(movedWorkspace)
        await gate.release()
        await expectCommandFailure(command.task)
        #expect(await fixture.applicationExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func disabledSubscriptionOverlapRetiresOnRuntimeWake() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let workspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let receipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        let previousReference = UUID().uuidString.lowercased()
        let keyStore = AgentEventSigningKeyStore(secretStore: fixture.secretStore)
        try keyStore.store(
          secretData: Data(repeating: 0x55, count: 32),
          reference: previousReference
        )
        let subscriptionURL = fixture.rootURL.appendingPathComponent(
          "events",
          isDirectory: true
        ).appendingPathComponent("subscriptions.json")
        var document = try #require(
          JSONSerialization.jsonObject(with: Data(contentsOf: subscriptionURL)) as? [String: Any]
        )
        var subscriptions = try #require(document["subscriptions"] as? [[String: Any]])
        subscriptions[0]["previousSigningKey"] = [
          "reference": previousReference,
          "startedAt": fixture.clock.now().timeIntervalSinceReferenceDate,
          "expiresAt": fixture.clock.now().addingTimeInterval(60).timeIntervalSinceReferenceDate,
        ]
        document["subscriptions"] = subscriptions
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
          .write(to: subscriptionURL, options: .atomic)

        await fixture.runtime.start(workspaceProvider: { workspace })
        fixture.clock.advance(by: 61)
        fixture.runtime.workspaceDidCommit()
        for _ in 0..<100 {
          if try await fixture.subscriptionStore.currentSubscription(id: receipt.subscriptionID)?
            .previousSigningKey == nil
          {
            break
          }
          try await Task.sleep(for: .milliseconds(10))
        }

        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(id: receipt.subscriptionID)
        )
        #expect(current.previousSigningKey == nil)
        #expect(try await fixture.subscriptionStore.isSigningKeyReferenced(previousReference) == false)
        let retiredSecret = try? keyStore.validatedSecretData(reference: previousReference)
        #expect(retiredSecret == nil)
        #expect(await fixture.callbackExchange.requestCount() == 0)
        #expect(await fixture.applicationExchange.requestCount() == 0)
        await fixture.runtime.stop()
      }
    }

    @Test @MainActor func scopeAuthorityPauseRetiresDisabledOverlapImmediately() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let workspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let receipt = try await fixture.subscriptionService.createPending(
          profileID: fixture.profileID,
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          callbackURL: fixture.callbackURL,
          signingSecret: fixture.signingSecret,
          workspaceProvider: { workspace },
          now: fixture.clock.now()
        )
        let previousReference = UUID().uuidString.lowercased()
        let keyStore = AgentEventSigningKeyStore(secretStore: fixture.secretStore)
        try keyStore.store(
          secretData: Data(repeating: 0x55, count: 32),
          reference: previousReference
        )
        let subscriptionURL = fixture.rootURL.appendingPathComponent(
          "events",
          isDirectory: true
        ).appendingPathComponent("subscriptions.json")
        var document = try #require(
          JSONSerialization.jsonObject(with: Data(contentsOf: subscriptionURL)) as? [String: Any]
        )
        var subscriptions = try #require(document["subscriptions"] as? [[String: Any]])
        subscriptions[0]["previousSigningKey"] = [
          "reference": previousReference,
          "startedAt": fixture.clock.now().timeIntervalSinceReferenceDate,
          "expiresAt": fixture.clock.now().addingTimeInterval(60).timeIntervalSinceReferenceDate,
        ]
        document["subscriptions"] = subscriptions
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
          .write(to: subscriptionURL, options: .atomic)

        try await fixture.runtime.pauseSubscriptions(
          profileIDs: [],
          noteIDs: [fixture.note.id],
          disposition: .scopeMembershipChanged
        )

        let current = try #require(
          await fixture.subscriptionStore.currentSubscription(id: receipt.subscriptionID)
        )
        #expect(current.previousSigningKey == nil)
        #expect(
          try await fixture.subscriptionStore.isSigningKeyReferenced(previousReference) == false
        )
        #expect((try? keyStore.validatedSecretData(reference: previousReference)) == nil)
        #expect(await fixture.callbackExchange.requestCount() == 0)
        #expect(await fixture.applicationExchange.requestCount() == 0)
      }
    }

    @Test @MainActor func restartedRuntimeReplaysCommittedEventWithoutManualSender() async throws {
      let fixture = try await AgentEventMonitoringRuntimeFixture.make()
      let restartedRuntime = fixture.makeReopenedRuntime()
      do {
        let workspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        _ = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: workspace
        )
        await fixture.runtime.start(workspaceProvider: { workspace })
        await fixture.runtime.stop()

        var changedWorkspace = workspace
        var changedNote = try #require(changedWorkspace.notes.first)
        changedNote.title = "Restarted runtime private title"
        changedNote.body = "Restarted runtime private body"
        changedNote.revision += 1
        changedNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        changedWorkspace.notes[0] = changedNote
        _ = try await fixture.localStore.save(
          workspace: changedWorkspace,
          preferences: .init(),
          generation: 2
        )

        let appState = fixture.makeAppState(using: restartedRuntime)
        await appState.waitUntilInitialLoad()
        let bodies = await fixture.waitForApplicationBodies(count: 1)
        let body = try #require(bodies.first)
        let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: body)
        let bodyText = String(decoding: body, as: UTF8.self)
        #expect(envelope.name == .noteUpdated)
        #expect(bodies.count == 1)
        #expect(!bodyText.contains(changedNote.title))
        #expect(!bodyText.contains(changedNote.body))

        await restartedRuntime.stop()
        await fixture.runtime.stop()
        fixture.remove()
      } catch {
        await restartedRuntime.stop()
        await fixture.runtime.stop()
        fixture.remove()
        throw error
      }
    }

    @Test @MainActor func committedChangesAreAutomaticallyDrainedAfterRateLimit() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let appState = fixture.makeAppState()
        await appState.waitUntilInitialLoad()
        let workspace = appState.workspace
        let subscriptionID = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: workspace
        )
        var firstWorkspace = appState.workspace
        var firstNote = try #require(firstWorkspace.notes.first)
        firstNote.title = "Automatic event first"
        firstNote.revision += 1
        firstNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
        firstWorkspace.notes[0] = firstNote
        appState.workspace = firstWorkspace
        try await appState.saveNow().value
        let firstBodies = await fixture.waitForApplicationBodies(count: 1)
        #expect(firstBodies.count == 1)

        var outboxEntries = try fixture.outboxStore.load().entries
        for _ in 0..<500 where !outboxEntries.isEmpty {
          try await Task.sleep(for: .milliseconds(10))
          outboxEntries = try fixture.outboxStore.load().entries
        }
        #expect(outboxEntries.isEmpty)

        var secondWorkspace = appState.workspace
        var secondNote = try #require(secondWorkspace.notes.first)
        secondNote.title = "Automatic event second"
        secondNote.revision += 1
        secondNote.modifiedAt = fixture.clock.now().addingTimeInterval(2)
        secondWorkspace.notes[0] = secondNote
        appState.workspace = secondWorkspace
        try await appState.saveNow().value
        try await Task.sleep(for: .milliseconds(50))
        #expect(await fixture.applicationExchange.requestCount() == 1)

        let bodies = await fixture.waitForApplicationBodies(count: 2)
        let applicationRequestCount = await fixture.applicationExchange.requestCount()
        if bodies.count != 2 || applicationRequestCount != 2 {
          let outbox = try? fixture.outboxStore.load()
          let progressSummary =
            outbox?.progress.first(where: {
              $0.subscriptionID == subscriptionID
            }).map {
              "anchor=\(String(describing: $0.anchor)) "
                + "capturedThrough=\(String(describing: $0.capturedThrough)) "
                + "status=\($0.status.rawValue) "
                + "disposition=\(String(describing: $0.nonDeliveryDisposition?.rawValue))"
            } ?? "missing"
          let entrySummary =
            outbox?.entries.filter {
              $0.subscriptionID == subscriptionID
            }.map { entry in
              "eventID=\(entry.eventID) "
                + "position=\(entry.sourcePosition.epoch.uuidString):\(entry.sourcePosition.sequence) "
                + "status=\(entry.status.rawValue) bodyBytes=\(entry.body?.count ?? 0)"
            }.joined(separator: "; ") ?? "unavailable"
          let journalSummary: String
          if let snapshot = try? await fixture.localStore.loadSnapshot(),
            let journal = snapshot.agentEventJournal
          {
            let records = journal.records.map { record in
              "sequence=\(record.sequence) eventID=\(record.eventID) "
                + "event=\(String(describing: record.eventName)) "
                + "provenance=\(String(describing: record.provenance))"
            }.joined(separator: "; ")
            journalSummary =
              "lastSequence=\(journal.lastSequence) historyFloor=\(journal.historyFloor) "
              + "records=\(records)"
          } else {
            journalSummary = "unavailable"
          }
          let callbackRequestCount = await fixture.callbackExchange.requestCount()
          var ledgerSummary = "unavailable"
          var proofExpirationSummary = "unavailable"
          var deliveryControlSummary = "unavailable"
          if let subscription = try? await fixture.subscriptionStore.currentSubscription(
            id: subscriptionID
          ) {
            let binding = verificationBinding(for: subscription)
            let records = (try? fixture.ledgerStore.records(for: binding)) ?? []
            ledgerSummary = records.map { record in
              "eventID=\(record.eventID) status=\(record.status.rawValue) "
                + "lease=\(String(describing: record.leaseDeadline)) "
                + "nextEligible=\(String(describing: record.nextEligibleAt))"
            }.joined(separator: "; ")
            let proof = try? fixture.verificationStore.currentProof(for: binding)
            proofExpirationSummary = String(describing: proof?.expiresAt)
            deliveryControlSummary =
              "generation=\(String(describing: subscription.deliveryControl?.generationID)) "
              + "enabled=\(String(describing: subscription.deliveryControl?.enabled))"
          }
          print(
            """
            Runtime second-save failure diagnostic:
              bodies=\(bodies.count) applicationRequests=\(applicationRequestCount)
              callbackRequests=\(callbackRequestCount)
              progress=\(progressSummary)
              entries=\(entrySummary)
              journal=\(journalSummary)
              ledger=\(ledgerSummary)
              proofExpiresAt=\(proofExpirationSummary)
              deliveryControl=\(deliveryControlSummary)
            """
          )
        }
        #expect(bodies.count == 2)

        #expect(await fixture.applicationExchange.requestCount() == 2)
      }
    }

    @Test @MainActor func runtimeConsumesEnabledCaptureCoalescingPolicy() async throws {
      try await withAgentEventMonitoringRuntimeFixture(coalescesNoteUpdateBursts: true) {
        fixture in
        let workspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
        let subscriptionID = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: workspace
        )

        var first = fixture.note
        first.title = "Runtime burst title"
        first.revision = 2
        fixture.clock.advance(by: 1)
        first.modifiedAt = fixture.clock.now()
        _ = try await fixture.localStore.save(
          workspace: Workspace(notes: [first], selectedNoteID: first.id),
          preferences: .init(),
          generation: 2
        )

        var latest = first
        latest.body = "Runtime burst body"
        latest.revision = 3
        fixture.clock.advance(by: 1)
        latest.modifiedAt = fixture.clock.now()
        _ = try await fixture.localStore.save(
          workspace: Workspace(notes: [latest], selectedNoteID: latest.id),
          preferences: .init(),
          generation: 3
        )
        let journal = try #require(
          try await fixture.localStore.loadSnapshot().agentEventJournal
        )
        let latestRecord = try #require(journal.records.last)

        let latestWorkspace = Workspace(notes: [latest], selectedNoteID: latest.id)
        await fixture.runtime.start(workspaceProvider: { latestWorkspace })
        let bodies = await fixture.waitForApplicationBodies(count: 1)
        #expect(bodies.count == 1)
        if let body = bodies.first {
          let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: body)
          #expect(envelope.eventID == latestRecord.eventID.uuidString.lowercased())
          if case .noteUpdated(let noteID, let revision, let changedFields, _) = envelope.data {
            #expect(noteID == fixture.note.id)
            #expect(revision == latest.revision)
            #expect(changedFields == [.body, .title])
          } else {
            Issue.record("Runtime capture must coalesce only note.updated events.")
          }
        }
        #expect(await fixture.applicationExchange.requestCount() == 1)
        let progress = try #require(
          try fixture.outboxStore.load().progress.first(where: {
            $0.subscriptionID == subscriptionID
          })
        )
        #expect(progress.capturedThrough?.sequence == latestRecord.sequence)
      }
    }

    @Test @MainActor func transientCaptureReadFailureRetriesWithFrozenWallClock() async throws {
      try await withAgentEventMonitoringRuntimeFixture { fixture in
        let appState = fixture.makeAppState()
        await appState.waitUntilInitialLoad()
        let frozenNow = fixture.clock.now()
        let subscriptionID = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: appState.workspace
        )
        let progress = try #require(
          try fixture.outboxStore.load().progress.first {
            $0.subscriptionID == subscriptionID
          }
        )
        let capturedThrough = try #require(progress.capturedThrough)
        await fixture.snapshotReaderGate.failOnce(afterSequence: capturedThrough.sequence)

        var workspace = appState.workspace
        var note = try #require(workspace.notes.first)
        note.title = "Transient capture retry"
        note.revision += 1
        note.modifiedAt = frozenNow.addingTimeInterval(1)
        workspace.notes[0] = note
        appState.workspace = workspace
        try await appState.saveNow().value

        let bodies = await fixture.waitForApplicationBodies(count: 1)
        #expect(await fixture.snapshotReaderGate.injectedFailureCount() == 1)
        #expect(fixture.clock.now() == frozenNow)
        #expect(bodies.count == 1)
        if let body = bodies.first {
          let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: body)
          #expect(envelope.name == .noteUpdated)
        }
        #expect(await fixture.applicationExchange.requestCount() == 1)
      }
    }

    @Test @MainActor func fairRuntimeBurstRetriesWithoutEchoingWorkspaceContent() async throws {
      try await withAgentEventMonitoringRuntimeFixture(applicationStatuses: [503, 204, 204]) {
        fixture in
        let appState = fixture.makeAppState()
        await appState.waitUntilInitialLoad()
        let secondNote = Note(
          id: UUID(),
          title: "Second runtime note",
          body: "Second private body",
          createdAt: fixture.clock.now(),
          modifiedAt: fixture.clock.now(),
          agentAccess: true,
          revision: 1
        )
        var workspace = appState.workspace
        workspace.notes.append(secondNote)
        workspace.selectedNoteID = secondNote.id
        appState.workspace = workspace
        try await appState.saveNow().value

        let capabilityState = try await fixture.capabilityStore.currentState()
        let currentCapabilities = try #require(capabilityState.profiles[fixture.profileID])
        var grants = currentCapabilities.grants
        grants.append(AgentResourceGrant(scope: .note(noteID: secondNote.id), authority: .read))
        _ = try await fixture.capabilityStore.replaceProfile(
          AgentProfileCapabilities(
            profileID: fixture.profileID,
            grantRevision: currentCapabilities.grantRevision + 1,
            allowedCapabilities: currentCapabilities.allowedCapabilities,
            grants: grants,
            allowsEventObservation: currentCapabilities.allowsEventObservation
          ),
          expectedGrantRevision: currentCapabilities.grantRevision
        )
        let subscriptionWorkspace = appState.workspace
        _ = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: fixture.note.id),
          workspace: subscriptionWorkspace
        )
        _ = try await fixture.enableSubscription(
          event: .noteUpdated,
          scope: .note(noteID: secondNote.id),
          workspace: subscriptionWorkspace
        )

        var changedWorkspace = appState.workspace
        for noteID in [fixture.note.id, secondNote.id] {
          guard let index = changedWorkspace.notes.firstIndex(where: { $0.id == noteID }) else {
            throw RuntimeTestError.invalidFixture
          }
          changedWorkspace.notes[index].title += " private changed title"
          changedWorkspace.notes[index].body += " private changed body"
          changedWorkspace.notes[index].revision += 1
          changedWorkspace.notes[index].modifiedAt = fixture.clock.now().addingTimeInterval(1)
        }
        appState.workspace = changedWorkspace
        try await appState.saveNow().value
        let firstTwoBodies = await fixture.waitForApplicationBodies(count: 2)
        #expect(firstTwoBodies.count >= 2)

        fixture.clock.advance(by: 5)
        fixture.runtime.workspaceDidCommit()
        let bodies = await fixture.waitForApplicationBodies(count: 3)
        let envelopes = try bodies.prefix(3).map {
          try JSONDecoder().decode(AgentEventEnvelope.self, from: $0)
        }
        #expect(bodies.count == 3)
        #expect(envelopes[0] == envelopes[2])
        #expect(envelopes[0].eventID != envelopes[1].eventID)
        #expect(
          Set(envelopes.prefix(2).compactMap { Self.noteID(in: $0) })
            == Set([fixture.note.id, secondNote.id])
        )
        #expect(
          bodies.prefix(3).allSatisfy {
            let text = String(decoding: $0, as: UTF8.self)
            return !text.contains("private changed title")
              && !text.contains("private changed body")
              && !text.contains("Second private body")
          }
        )
      }
    }

    @Test @MainActor func receiptReleasesCapacityPausedOutboxProgress() async throws {
      try await assertCapacityPausedOutboxResumes(
        responseStatus: 204,
        expectedLedgerStatus: .receipt
      )
    }

    @Test @MainActor func ownerSummariesPreserveCapacityAndHistoryPauseStates() async throws {
      for (progressStatus, ownerState) in [
        (AgentEventOutboxProgressStatus.pausedCapacity, AgentEventOwnerState.pausedCapacity),
        (AgentEventOutboxProgressStatus.pausedHistory, AgentEventOwnerState.pausedHistory),
      ] {
        try await withAgentEventMonitoringRuntimeFixture { fixture in
          let workspace = Workspace(notes: [fixture.note], selectedNoteID: fixture.note.id)
          let subscriptionID = try await fixture.enableSubscription(
            event: .noteUpdated,
            scope: .note(noteID: fixture.note.id),
            workspace: workspace
          )
          try fixture.outboxStore.update { state in
            guard
              let index = state.progress.firstIndex(where: {
                $0.subscriptionID == subscriptionID
              })
            else {
              throw RuntimeTestError.invalidFixture
            }
            state.progress[index].status = progressStatus
          }

          let summary = try #require(
            try await fixture.runtime.ownerSummaries(workspace: workspace)
              .first(where: { $0.id == subscriptionID })
          )
          #expect(summary.state == ownerState)
        }
      }
    }

    @Test @MainActor func terminalResponseReleasesCapacityPausedOutboxProgress() async throws {
      try await assertCapacityPausedOutboxResumes(
        responseStatus: 410,
        expectedLedgerStatus: .terminal
      )
    }

    private static func noteID(in envelope: AgentEventEnvelope) -> UUID? {
      switch envelope.data {
      case .noteCreated(let noteID, _, _), .noteUpdated(let noteID, _, _, _),
        .taskStateChanged(let noteID, _, _, _):
        return noteID
      }
    }
  }

  @MainActor
  private func assertCapacityPausedOutboxResumes(
    responseStatus: Int,
    expectedLedgerStatus: AgentEventDeliveryLedgerRecordStatus
  ) async throws {
    try await withAgentEventMonitoringRuntimeFixture(applicationStatuses: [responseStatus]) {
      fixture in
      let appState = fixture.makeAppState()
      await appState.waitUntilInitialLoad()
      let workspace = appState.workspace
      let subscriptionID = try await fixture.enableSubscription(
        event: .noteUpdated,
        scope: .note(noteID: fixture.note.id),
        workspace: workspace
      )
      let gate = RuntimeTestAsyncGate()
      defer { Task { await gate.release() } }
      await fixture.applicationExchange.blockNextResponse(until: gate)

      var changedWorkspace = appState.workspace
      var changedNote = try #require(changedWorkspace.notes.first)
      changedNote.title += " completion releases capacity"
      changedNote.revision += 1
      changedWorkspace.notes[0] = changedNote
      appState.workspace = changedWorkspace
      try await appState.saveNow().value
      await gate.waitUntilEntered()

      try fixture.outboxStore.update { state in
        guard
          let index = state.progress.firstIndex(where: {
            $0.subscriptionID == subscriptionID
          })
        else {
          throw RuntimeTestError.invalidFixture
        }
        state.progress[index].status = .pausedCapacity
      }
      await gate.release()

      var resumedProgress: AgentEventOutboxProgress?
      for _ in 0..<500 {
        let state = try fixture.outboxStore.load()
        resumedProgress = state.progress.first(where: {
          $0.subscriptionID == subscriptionID
        })
        if state.entries.isEmpty, resumedProgress?.status == .pending { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(resumedProgress?.status == .pending)
      #expect(try fixture.outboxStore.load().entries.isEmpty)
      let subscription = try #require(
        await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
      )
      let records = try fixture.ledgerStore.records(for: verificationBinding(for: subscription))
      #expect(records.first?.status == expectedLedgerStatus)
    }
  }

  @MainActor
  private func withAgentEventMonitoringRuntimeFixture<Value>(
    approvalWaitLimit: Duration = .seconds(5),
    applicationStatuses: [Int] = [],
    coalescesNoteUpdateBursts: Bool = false,
    scopeAuthorizationGate: RuntimeTestAsyncGate? = nil,
    scopeAuthorizationGateOnCall: Int = 2,
    afterSubscriptionCreationGate: RuntimeTestAsyncGate? = nil,
    approvalObservationHook: AgentEventMonitoringRuntimeTestObservation? = nil,
    _ operation: (AgentEventMonitoringRuntimeFixture) async throws -> Value
  ) async throws -> Value {
    let fixture = try await AgentEventMonitoringRuntimeFixture.make(
      approvalWaitLimit: approvalWaitLimit,
      applicationStatuses: applicationStatuses,
      coalescesNoteUpdateBursts: coalescesNoteUpdateBursts,
      scopeAuthorizationGate: scopeAuthorizationGate,
      scopeAuthorizationGateOnCall: scopeAuthorizationGateOnCall,
      afterSubscriptionCreationGate: afterSubscriptionCreationGate,
      approvalObservationHook: approvalObservationHook
    )
    do {
      let result = try await operation(fixture)
      await fixture.runtime.stop()
      fixture.remove()
      return result
    } catch {
      await fixture.runtime.stop()
      fixture.remove()
      throw error
    }
  }

  @MainActor
  private func startPrepareEventSubscriptionCommand(
    fixture: AgentEventMonitoringRuntimeFixture,
    state: RuntimeTestWorkspaceState,
    scope: AgentEventScope? = nil,
    signingSecret: String? = nil,
    capabilityAuthority: (any AgentCapabilityAuthorizing)? = nil
  ) -> (subscriptionID: String, task: Task<AgentWorkspaceResponse, Error>) {
    let service = AgentCommandService(
      state: state,
      profileStore: fixture.profileStore,
      activityStore: fixture.activityStore,
      capabilityAuthority: capabilityAuthority ?? fixture.authority,
      eventRuntime: fixture.runtime,
      now: { fixture.clock.now() }
    )
    let requestedScope = scope ?? .note(noteID: fixture.note.id)
    let command = AgentWorkspaceCommand.prepareEventSubscription(
      request: AgentEventSubscriptionRequest(
        event: .noteUpdated,
        scope: requestedScope,
        callbackURL: fixture.callbackURL,
        signingSecret: signingSecret ?? fixture.signingSecret,
        ttl: .standard
      )
    )
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: fixture.profileID,
      event: .noteUpdated,
      scope: requestedScope,
      callbackURL: fixture.callbackURL
    )
    let task = Task {
      try await service.execute(
        profileID: fixture.profileID,
        credential: fixture.provisioning.credential,
        command: command
      )
    }
    return (subscriptionID, task)
  }

  @MainActor
  private func startPreparedEventSubscriptionIPCCommand(
    fixture: AgentEventMonitoringRuntimeFixture,
    state: RuntimeTestWorkspaceState
  ) -> (subscriptionID: String, task: Task<AgentIPCServer.ExecutionResult, Error>) {
    let service = AgentCommandService(
      state: state,
      profileStore: fixture.profileStore,
      activityStore: fixture.activityStore,
      capabilityAuthority: fixture.authority,
      eventRuntime: fixture.runtime,
      now: { fixture.clock.now() }
    )
    let command = AgentWorkspaceCommand.prepareEventSubscription(
      request: AgentEventSubscriptionRequest(
        event: .noteUpdated,
        scope: .note(noteID: fixture.note.id),
        callbackURL: fixture.callbackURL,
        signingSecret: fixture.signingSecret,
        ttl: .standard
      )
    )
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: fixture.profileID,
      event: .noteUpdated,
      scope: .note(noteID: fixture.note.id),
      callbackURL: fixture.callbackURL
    )
    let task = Task {
      try await service.executeForIPC(
        profileID: fixture.profileID,
        credential: fixture.provisioning.credential,
        command: command
      )
    }
    return (subscriptionID, task)
  }

  private func verificationBinding(
    for subscription: AgentEventPendingSubscription
  ) -> AgentEventCallbackVerificationBinding {
    AgentEventCallbackVerificationBinding(
      profileID: subscription.profileID,
      subscriptionID: subscription.subscriptionID,
      subscriptionRevision: subscription.revision,
      grantRevision: subscription.grantRevision,
      signingKeyReference: subscription.signingKeyReference
    )
  }

  @MainActor
  private func setPreparedReadinessFault(
    _ fault: RuntimeTestPreparedReadinessFault,
    fixture: AgentEventMonitoringRuntimeFixture,
    subscriptionID: String
  ) throws {
    if fault == .unreadableRegistry {
      try Data("{".utf8).write(to: fixture.outboxStore.fileURL, options: .atomic)
      return
    }
    try fixture.outboxStore.update { outbox in
      guard let index = outbox.progress.firstIndex(where: {
        $0.profileID == fixture.profileID && $0.subscriptionID == subscriptionID
      }) else {
        throw RuntimeTestError.invalidFixture
      }
      if fault == .missingProgress {
        outbox.progress.remove(at: index)
        return
      }
      guard let fence = outbox.progress[index].preparedResponseFence else {
        throw RuntimeTestError.invalidFixture
      }
      var progress = outbox.progress[index]
      switch fault {
      case .missingProgress, .unreadableRegistry:
        throw RuntimeTestError.invalidFixture
      case .staleBinding:
        progress.preparedResponseFence = AgentEventOutboxPreparedResponseFence(
          binding: AgentEventCallbackVerificationBinding(
            profileID: fence.binding.profileID,
            subscriptionID: fence.binding.subscriptionID,
            subscriptionRevision: fence.binding.subscriptionRevision,
            grantRevision: fence.binding.grantRevision,
            signingKeyReference: "stale-\(fence.binding.signingKeyReference)"
          ),
          ownerControlGenerationID: fence.ownerControlGenerationID,
          originIntentID: fence.originIntentID,
          disposition: fence.disposition
        )
      case .staleSubscriptionRevision:
        let revision = progress.subscriptionRevision + 1
        progress.subscriptionRevision = revision
        progress.preparedResponseFence = AgentEventOutboxPreparedResponseFence(
          binding: AgentEventCallbackVerificationBinding(
            profileID: fence.binding.profileID,
            subscriptionID: fence.binding.subscriptionID,
            subscriptionRevision: revision,
            grantRevision: progress.grantRevision,
            signingKeyReference: fence.binding.signingKeyReference
          ),
          ownerControlGenerationID: fence.ownerControlGenerationID,
          originIntentID: fence.originIntentID,
          disposition: fence.disposition
        )
      case .staleGrantRevision:
        let grantRevision = progress.grantRevision + 1
        progress = AgentEventOutboxProgress(
          profileID: progress.profileID,
          subscriptionID: progress.subscriptionID,
          subscriptionRevision: progress.subscriptionRevision,
          grantRevision: grantRevision,
          anchor: progress.anchor,
          capturedThrough: progress.capturedThrough,
          status: progress.status,
          nonDeliveryDisposition: progress.nonDeliveryDisposition,
          preparedResponseFence: AgentEventOutboxPreparedResponseFence(
            binding: AgentEventCallbackVerificationBinding(
              profileID: fence.binding.profileID,
              subscriptionID: fence.binding.subscriptionID,
              subscriptionRevision: fence.binding.subscriptionRevision,
              grantRevision: grantRevision,
              signingKeyReference: fence.binding.signingKeyReference
            ),
            ownerControlGenerationID: fence.ownerControlGenerationID,
            originIntentID: fence.originIntentID,
            disposition: fence.disposition
          ),
          requiresPreparedResponseFence: progress.requiresPreparedResponseFence
        )
      case .staleOwnerGeneration:
        progress.preparedResponseFence = AgentEventOutboxPreparedResponseFence(
          binding: fence.binding,
          ownerControlGenerationID: distinctUUID(from: fence.ownerControlGenerationID),
          originIntentID: fence.originIntentID,
          disposition: fence.disposition
        )
      case .staleOrigin:
        progress.preparedResponseFence = AgentEventOutboxPreparedResponseFence(
          binding: fence.binding,
          ownerControlGenerationID: fence.ownerControlGenerationID,
          originIntentID: distinctUUID(from: fence.originIntentID),
          disposition: fence.disposition
        )
      case .failedDisposition:
        progress.preparedResponseFence = AgentEventOutboxPreparedResponseFence(
          binding: fence.binding,
          ownerControlGenerationID: fence.ownerControlGenerationID,
          originIntentID: fence.originIntentID,
          disposition: .failedResponse
        )
      case .missingRequiredMarker:
        progress.preparedResponseFence = nil
        progress.requiresPreparedResponseFence = false
      }
      outbox.progress[index] = progress
    }
  }

  private func distinctUUID(from value: UUID) -> UUID {
    var bytes = value.uuid
    bytes.0 ^= 1
    return UUID(uuid: bytes)
  }

  private func workspaceUnderFutureFolderGrant(
    fixture: AgentEventMonitoringRuntimeFixture
  ) async throws -> Workspace {
    let folder = try Folder(id: UUID(), name: "Synthetic inherited scope")
    var note = fixture.note
    note.folderID = folder.id
    let workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [folder])
    _ = try await fixture.localStore.save(
      workspace: workspace,
      preferences: .init(),
      generation: 2
    )
    let current = try #require(
      try await fixture.capabilityStore.currentState().profiles[fixture.profileID]
    )
    _ = try await fixture.capabilityStore.replaceProfile(
      AgentProfileCapabilities(
        profileID: fixture.profileID,
        grantRevision: current.grantRevision + 1,
        allowedCapabilities: [.readNotes],
        grants: [
          AgentResourceGrant(
            scope: .folderIncludingFutureNotes(folderID: folder.id),
            authority: .read
          )
        ],
        allowsEventObservation: true
      ),
      expectedGrantRevision: current.grantRevision
    )
    return workspace
  }

  @MainActor
  private func expectCommandFailure<Success: Sendable>(_ task: Task<Success, Error>) async {
    guard case .failure = await task.result else {
      Issue.record("The command must fail after its approval state is invalidated.")
      return
    }
  }

  @MainActor
  private final class RuntimeTestWorkspaceState: AgentWorkspaceStateAccess {
    private var workspaceValue: Workspace
    private let refreshGate: RuntimeTestAsyncGate?
    var persistenceGeneration: UInt64 = 1
    var preferences = AppPreferences()
    var isAgentWorkspaceAvailable = true
    var agentCommitProofs: [AgentWorkspaceCommitProof] = []

    init(workspace: Workspace, refreshGate: RuntimeTestAsyncGate? = nil) {
      workspaceValue = workspace
      self.refreshGate = refreshGate
    }

    var workspace: Workspace { workspaceValue }

    func refreshAgentEventMonitoring() async {
      await refreshGate?.pause()
    }

    func flushPendingPersistenceForAgent() async throws {}

    func commitAgentWorkspace(
      _ workspace: Workspace,
      expectedGeneration: UInt64,
      commitProof: AgentWorkspaceCommitProof
    ) throws {
      workspaceValue = workspace
      persistenceGeneration = expectedGeneration + 1
      agentCommitProofs.append(commitProof)
    }

    func publishAgentFeedback(_ feedback: AgentChangeFeedback) {}
    func publishAgentRequestEvent(_ event: AgentRequestEvent) {}

    func replaceWorkspace(_ workspace: Workspace) {
      workspaceValue = workspace
      persistenceGeneration += 1
    }
  }

  private struct AgentEventMonitoringRuntimeFixture {
    let rootURL: URL
    let ownedRoot: OwnedMCPFixtureRoot
    let localStore: LocalStore
    let secretStore: RuntimeTestSecretStore
    let randomBytes: RuntimeTestRandomBytes
    let profileStore: AgentProfileStore
    let provisioning: AgentProfileProvisioning
    let capabilityStore: AgentCapabilityStore
    let authority: AgentCapabilityAuthority
    let activityStore: AgentActivityStore
    let subscriptionService: AgentEventSubscriptionService
    let subscriptionStore: AgentEventSubscriptionStore
    let subscriptionFileWriter: RuntimeTestOutboxFileWriter
    let verificationStore: AgentEventCallbackVerificationStore
    let verificationFileWriter: RuntimeTestOutboxFileWriter
    let outboxService: AgentEventOutboxService
    let outboxStore: AgentEventOutboxStore
    let outboxFileWriter: RuntimeTestOutboxFileWriter
    let ledgerStore: AgentEventDeliveryLedgerStore
    let monitoringService: AgentEventMonitoringService
    let runtime: AgentEventMonitoringRuntime
    let callbackExchange: RuntimeTestCallbackExchange
    let applicationExchange: RuntimeTestApplicationExchange
    let clock: RuntimeTestClock
    let snapshotReaderGate: RuntimeTestSnapshotReaderGate
    let note: Note
    let callbackURL = "https://runtime.example.test/events"
    let signingSecretData = Data(repeating: 0x4a, count: 32)

    var profileID: UUID { provisioning.profile.id }
    var signingSecret: String { "whsec_\(signingSecretData.base64EncodedString())" }

    static func make(
      approvalWaitLimit: Duration = .seconds(5),
      applicationStatuses: [Int] = [],
      coalescesNoteUpdateBursts: Bool = false,
      scopeAuthorizationGate: RuntimeTestAsyncGate? = nil,
      scopeAuthorizationGateOnCall: Int = 2,
      afterSubscriptionCreationGate: RuntimeTestAsyncGate? = nil,
      approvalObservationHook: AgentEventMonitoringRuntimeTestObservation? = nil
    ) async throws -> AgentEventMonitoringRuntimeFixture {
      let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventMonitoringRuntime)
      var ownershipTransferred = false
      defer {
        if !ownershipTransferred {
          do {
            try ownedRoot.cleanup()
          } catch {
            Issue.record("Runtime fixture construction cleanup failed: \(error)")
          }
        }
      }
      let rootURL = ownedRoot.url

      let clock = RuntimeTestClock()
      let snapshotReaderGate = RuntimeTestSnapshotReaderGate()
      let secretStore = RuntimeTestSecretStore()
      let randomBytes = RuntimeTestRandomBytes()
      let note = Note(
        id: UUID(),
        title: "Runtime test note",
        body: "Synthetic content only",
        createdAt: clock.now(),
        modifiedAt: clock.now(),
        agentAccess: true,
        revision: 1
      )
      let workspace = Workspace(notes: [note], selectedNoteID: note.id)
      let localStore = LocalStore(
        rootURL: rootURL.appendingPathComponent("workspace", isDirectory: true),
        now: { clock.now() }
      )
      _ = try await localStore.save(workspace: workspace, preferences: .init(), generation: 1)

      let profileStore = AgentProfileStore(
        profilesURL: rootURL.appendingPathComponent("profiles.json"),
        secretStore: secretStore,
        randomBytes: randomBytes,
        now: { clock.now() }
      )
      let provisioning = try await profileStore.create(name: "Synthetic monitoring test")
      let capabilityStore = AgentCapabilityStore(
        capabilitiesURL: rootURL.appendingPathComponent("capabilities.json"),
        previousCapabilitiesURL: rootURL.appendingPathComponent("capabilities.previous.json")
      )
      let initialState = try await capabilityStore.loadOrMigrate(
        activeProfileIDs: [provisioning.profile.id],
        workspace: workspace
      )
      guard let initialProfile = initialState.profiles[provisioning.profile.id] else {
        throw RuntimeTestError.invalidFixture
      }
      _ = try await capabilityStore.replaceProfile(
        AgentProfileCapabilities(
          profileID: provisioning.profile.id,
          grantRevision: initialProfile.grantRevision + 1,
          allowedCapabilities: [.readNotes],
          grants: [AgentResourceGrant(scope: .note(noteID: note.id), authority: .read)],
          allowsEventObservation: true
        ),
        expectedGrantRevision: initialProfile.grantRevision
      )

      let authority = AgentCapabilityAuthority(store: capabilityStore)
      let directory = rootURL.appendingPathComponent("events", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let subscriptionFileWriter = RuntimeTestOutboxFileWriter()
      let subscriptionStore = AgentEventSubscriptionStore(
        fileURL: directory.appendingPathComponent("subscriptions.json"),
        fileWriter: { data, url in try subscriptionFileWriter.write(data, to: url) }
      )
      let verificationFileWriter = RuntimeTestOutboxFileWriter()
      let verificationStore = AgentEventCallbackVerificationStore(
        fileURL: directory.appendingPathComponent("verification.json"),
        now: { clock.now() },
        fileWriter: { data, url in try verificationFileWriter.write(data, to: url) }
      )
      let outboxFileWriter = RuntimeTestOutboxFileWriter()
      let outboxStore = AgentEventOutboxStore(
        fileURL: directory.appendingPathComponent("outbox.json"),
        fileWriter: { data, url in try outboxFileWriter.write(data, to: url) }
      )
      let ledgerStore = AgentEventDeliveryLedgerStore(
        fileURL: directory.appendingPathComponent("delivery-ledger.json"),
        now: { clock.now() },
        jitterBasisPoints: { 0 }
      )
      let signingKeyStore = AgentEventSigningKeyStore(secretStore: secretStore)
      let subscriptionService = AgentEventSubscriptionService(
        authority: authority,
        store: subscriptionStore,
        signingKeyStore: signingKeyStore,
        clock: { clock.now() }
      )
      let outboxService = AgentEventOutboxService(
        store: outboxStore,
        localStore: localStore,
        profileStore: profileStore,
        subscriptionStore: subscriptionStore,
        authority: authority,
        snapshotReader: {
          try await snapshotReaderGate.readSnapshot(from: localStore)
        },
        coalescesNoteUpdateBursts: coalescesNoteUpdateBursts
      )
      let callbackExchange = RuntimeTestCallbackExchange(
        callbackURL: "https://runtime.example.test/events"
      )
      let applicationExchange = RuntimeTestApplicationExchange(
        callbackURL: "https://runtime.example.test/events",
        statuses: applicationStatuses
      )
      let callbackVerificationService = AgentEventCallbackVerificationService(
        authority: authority,
        profileStore: profileStore,
        subscriptionStore: subscriptionStore,
        signingKeyStore: signingKeyStore,
        verificationStore: verificationStore,
        randomBytes: randomBytes,
        now: { clock.now() },
        exchange: { url, headers, body in
          try await callbackExchange.exchange(url, headers, body)
        }
      )
      let deliveryLedgerService = AgentEventDeliveryLedgerService(
        outboxStore: outboxStore,
        subscriptionStore: subscriptionStore,
        ledgerStore: ledgerStore
      )
      let authorizationService = AgentEventDeliveryAuthorizationService(
        authority: authority,
        profileStore: profileStore,
        subscriptionStore: subscriptionStore,
        verificationStore: verificationStore,
        outboxStore: outboxStore,
        ledgerStore: ledgerStore,
        now: { clock.now() }
      )
      let deliverySender = AgentEventDeliverySender(
        ledgerService: deliveryLedgerService,
        authorizationService: authorizationService,
        subscriptionStore: subscriptionStore,
        signingKeyStore: signingKeyStore,
        now: { clock.now() },
        exchange: { url, headers, body in
          try await applicationExchange.exchange(url, headers, body)
        }
      )
      let monitoringService = AgentEventMonitoringService(
        authority: authority,
        outboxService: outboxService,
        callbackVerificationService: callbackVerificationService,
        deliveryLedgerService: deliveryLedgerService,
        deliverySender: deliverySender
      )
      let scopeAuthorization: (@Sendable (UUID, AgentEventScope, Workspace) async throws -> UInt64)?
      if let scopeAuthorizationGate {
        let gatedAuthorizer = RuntimeTestScopeAuthorizer(
          authority: authority,
          gate: scopeAuthorizationGate,
          pauseOnCall: scopeAuthorizationGateOnCall
        )
        scopeAuthorization = { profileID, scope, workspace in
          try await gatedAuthorizer.authorize(
            profileID: profileID,
            scope: scope,
            workspace: workspace
          )
        }
      } else {
        scopeAuthorization = nil
      }
      let runtime = AgentEventMonitoringRuntime(
        subscriptionService: subscriptionService,
        subscriptionStore: subscriptionStore,
        monitoringService: monitoringService,
        callbackVerificationStore: verificationStore,
        outboxService: outboxService,
        outboxStore: outboxStore,
        deliveryLedgerStore: ledgerStore,
        profileStore: profileStore,
        authority: authority,
        now: { clock.now() },
        approvalWaitLimit: approvalWaitLimit,
        scopeAuthorization: scopeAuthorization,
        afterSubscriptionCreation: {
          await afterSubscriptionCreationGate?.pause()
        },
        approvalObservationHook: approvalObservationHook
      )
      let fixture = AgentEventMonitoringRuntimeFixture(
        rootURL: rootURL,
        ownedRoot: ownedRoot,
        localStore: localStore,
        secretStore: secretStore,
        randomBytes: randomBytes,
        profileStore: profileStore,
        provisioning: provisioning,
        capabilityStore: capabilityStore,
        authority: authority,
        activityStore: AgentActivityStore(rootURL: rootURL.appendingPathComponent("activity")),
        subscriptionService: subscriptionService,
        subscriptionStore: subscriptionStore,
        subscriptionFileWriter: subscriptionFileWriter,
        verificationStore: verificationStore,
        verificationFileWriter: verificationFileWriter,
        outboxService: outboxService,
        outboxStore: outboxStore,
        outboxFileWriter: outboxFileWriter,
        ledgerStore: ledgerStore,
        monitoringService: monitoringService,
        runtime: runtime,
        callbackExchange: callbackExchange,
        applicationExchange: applicationExchange,
        clock: clock,
        snapshotReaderGate: snapshotReaderGate,
        note: note
      )
      ownershipTransferred = true
      return fixture
    }

    @MainActor
    func makeReopenedRuntime() -> AgentEventMonitoringRuntime {
      let directory = rootURL.appendingPathComponent("events", isDirectory: true)
      let subscriptionStore = AgentEventSubscriptionStore(
        fileURL: directory.appendingPathComponent("subscriptions.json"),
        fileWriter: { data, url in try subscriptionFileWriter.write(data, to: url) }
      )
      let verificationStore = AgentEventCallbackVerificationStore(
        fileURL: directory.appendingPathComponent("verification.json"),
        now: { clock.now() },
        fileWriter: { data, url in try verificationFileWriter.write(data, to: url) }
      )
      let outboxStore = AgentEventOutboxStore(
        fileURL: directory.appendingPathComponent("outbox.json"),
        fileWriter: { data, url in try outboxFileWriter.write(data, to: url) }
      )
      let ledgerStore = AgentEventDeliveryLedgerStore(
        fileURL: directory.appendingPathComponent("delivery-ledger.json"),
        now: { clock.now() },
        jitterBasisPoints: { 0 }
      )
      let signingKeyStore = AgentEventSigningKeyStore(secretStore: secretStore)
      let subscriptionService = AgentEventSubscriptionService(
        authority: authority,
        store: subscriptionStore,
        signingKeyStore: signingKeyStore,
        clock: { clock.now() }
      )
      let outboxService = AgentEventOutboxService(
        store: outboxStore,
        localStore: localStore,
        profileStore: profileStore,
        subscriptionStore: subscriptionStore,
        authority: authority
      )
      let callbackVerificationService = AgentEventCallbackVerificationService(
        authority: authority,
        profileStore: profileStore,
        subscriptionStore: subscriptionStore,
        signingKeyStore: signingKeyStore,
        verificationStore: verificationStore,
        randomBytes: randomBytes,
        now: { clock.now() },
        exchange: { url, headers, body in
          try await callbackExchange.exchange(url, headers, body)
        }
      )
      let deliveryLedgerService = AgentEventDeliveryLedgerService(
        outboxStore: outboxStore,
        subscriptionStore: subscriptionStore,
        ledgerStore: ledgerStore
      )
      let authorizationService = AgentEventDeliveryAuthorizationService(
        authority: authority,
        profileStore: profileStore,
        subscriptionStore: subscriptionStore,
        verificationStore: verificationStore,
        outboxStore: outboxStore,
        ledgerStore: ledgerStore,
        now: { clock.now() }
      )
      let deliverySender = AgentEventDeliverySender(
        ledgerService: deliveryLedgerService,
        authorizationService: authorizationService,
        subscriptionStore: subscriptionStore,
        signingKeyStore: signingKeyStore,
        now: { clock.now() },
        exchange: { url, headers, body in
          try await applicationExchange.exchange(url, headers, body)
        }
      )
      let monitoringService = AgentEventMonitoringService(
        authority: authority,
        outboxService: outboxService,
        callbackVerificationService: callbackVerificationService,
        deliveryLedgerService: deliveryLedgerService,
        deliverySender: deliverySender
      )
      return AgentEventMonitoringRuntime(
        subscriptionService: subscriptionService,
        subscriptionStore: subscriptionStore,
        monitoringService: monitoringService,
        callbackVerificationStore: verificationStore,
        outboxService: outboxService,
        outboxStore: outboxStore,
        deliveryLedgerStore: ledgerStore,
        profileStore: profileStore,
        authority: authority,
        now: { clock.now() },
        approvalWaitLimit: .seconds(5)
      )
    }

    @MainActor
    func makeAppState(
      using runtime: AgentEventMonitoringRuntime? = nil
    ) -> AppState {
      AppState(
        store: localStore,
        agentProfileStore: profileStore,
        agentActivityStore: activityStore,
        agentCapabilityStore: capabilityStore,
        agentCapabilityAuthority: authority,
        agentEventMonitoringRuntime: runtime ?? self.runtime
      )
    }

    func enableSubscription(
      event: AgentEventName,
      scope: AgentEventScope,
      workspace: Workspace
    ) async throws -> String {
      let receipt = try await subscriptionService.createPending(
        profileID: profileID,
        event: event,
        scope: scope,
        callbackURL: callbackURL,
        signingSecret: signingSecret,
        workspaceProvider: { workspace },
        now: clock.now()
      )
      _ = try await monitoringService.anchorAndVerifyPendingSubscription(
        profileID: profileID,
        subscriptionID: receipt.subscriptionID,
        workspaceProvider: { workspace },
        now: clock.now()
      )
      try await runtime.setOwnerDeliveryConsent(
        subscriptionID: receipt.subscriptionID,
        enabled: true,
        allowsAutomaticRenewal: false,
        workspaceProvider: { workspace }
      )
      return receipt.subscriptionID
    }

    func waitForSubscription(id: String) async throws -> AgentEventPendingSubscription {
      for _ in 0..<500 {
        if let subscription = try await subscriptionStore.currentSubscription(id: id) {
          return subscription
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      throw RuntimeTestError.timeout
    }

    func waitForSubscription(
      id: String,
      afterRevision revision: UInt64
    ) async throws -> AgentEventPendingSubscription {
      for _ in 0..<500 {
        if let subscription = try await subscriptionStore.currentSubscription(id: id),
          subscription.revision > revision
        {
          return subscription
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      throw RuntimeTestError.timeout
    }

    func waitForPreparedResponseFence(
      id: String,
      revision: UInt64,
      expectedOwnerState: AgentEventOwnerState = .awaitingApproval,
      pollCount: Int = 500,
      observingRuntime: AgentEventMonitoringRuntime? = nil
    ) async throws -> AgentEventOutboxProgress {
      let observer = observingRuntime ?? runtime
      for _ in 0..<pollCount {
        if let subscription = try await subscriptionStore.currentSubscription(id: id),
          subscription.revision == revision,
          let control = subscription.deliveryControl,
          let progress = try? outboxStore.load().progress.first(where: {
            $0.profileID == profileID
              && $0.subscriptionID == id
              && $0.subscriptionRevision == revision
          }),
          progress.grantRevision == subscription.grantRevision,
          progress.requiresPreparedResponseFence,
          let fence = progress.preparedResponseFence,
          fence.binding == verificationBinding(for: subscription),
          fence.ownerControlGenerationID == control.generationID,
          fence.disposition == .awaitingResponse,
          let summaries = try? await observer.ownerSummaries(workspace: nil),
          summaries.first(where: { $0.id == id })?.state == expectedOwnerState
        {
          return progress
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      throw RuntimeTestError.timeout
    }

    func waitForApplicationBodies(count: Int) async -> [Data] {
      for _ in 0..<500 {
        let bodies = await applicationExchange.bodies()
        if bodies.count >= count { return bodies }
        try? await Task.sleep(for: .milliseconds(10))
      }
      return await applicationExchange.bodies()
    }

    func waitForReceiptAt(subscriptionID: String, workspace: Workspace) async throws -> Date {
      for _ in 0..<500 {
        if let summaries = try? await runtime.ownerSummaries(workspace: workspace),
          let receiptAt = summaries.first(where: { $0.id == subscriptionID })?.lastReceiptAt
        {
          return receiptAt
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      throw RuntimeTestError.timeout
    }

    func remove() {
      do {
        try ownedRoot.cleanup()
      } catch {
        Issue.record("Runtime fixture cleanup failed: \(error)")
      }
    }
  }

  private struct RuntimeTestVerificationRequest: Decodable {
    let type: String
    let challenge: String
  }

  private struct RuntimeTestVerificationResponse: Encodable {
    let challenge: String
  }

  private enum RuntimeTestError: Error {
    case invalidFixture
    case timeout
    case invalidExchange
    case transientSnapshotReadFailure
    case injectedOutboxWriteFailure
  }

  private enum RuntimeTestPreparedReadinessFault: CaseIterable, Equatable {
    case missingProgress
    case staleBinding
    case staleSubscriptionRevision
    case staleGrantRevision
    case staleOwnerGeneration
    case staleOrigin
    case failedDisposition
    case unreadableRegistry
    case missingRequiredMarker
  }

  private enum RuntimeTestNilMemoryRecoveryFault: CaseIterable {
    case missingProgress
    case staleBinding
    case staleSubscriptionRevision
    case staleGrantRevision
    case sameCurrentGeneration
    case missingRequiredMarker
    case unreadableRegistry
    case ambiguousProgress
    case knownPausedCapacity
    case knownPausedHistory
  }

  private final class RuntimeTestSynchronousWriteGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var didEnter = false
    private var released = false

    func pause() {
      condition.lock()
      didEnter = true
      condition.broadcast()
      while !released {
        condition.wait()
      }
      condition.unlock()
    }

    func waitUntilEntered() async -> Bool {
      await Task.detached {
        self.waitUntilEnteredBlocking()
      }.value
    }

    func release() {
      condition.lock()
      released = true
      condition.broadcast()
      condition.unlock()
    }

    private func waitUntilEnteredBlocking() -> Bool {
      condition.lock()
      let deadline = Date().addingTimeInterval(5)
      while !didEnter && condition.wait(until: deadline) {}
      let entered = didEnter
      condition.unlock()
      return entered
    }
  }

  private final class RuntimeTestOutboxFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var successfulWrites = 0
    private var remainingSuccessfulWritesBeforeFailure: Int?
    private var nextWriteGate: RuntimeTestSynchronousWriteGate?

    func pauseNextWrite() -> RuntimeTestSynchronousWriteGate {
      let gate = RuntimeTestSynchronousWriteGate()
      lock.withLock {
        nextWriteGate = gate
      }
      return gate
    }

    func failAfterSuccessfulWrites(_ count: Int = 0) {
      lock.withLock {
        remainingSuccessfulWritesBeforeFailure = count
      }
    }

    func successfulWriteCount() -> Int {
      lock.withLock { successfulWrites }
    }

    func write(_ data: Data, to url: URL) throws {
      let writeGate = lock.withLock { () -> RuntimeTestSynchronousWriteGate? in
        defer { nextWriteGate = nil }
        return nextWriteGate
      }
      writeGate?.pause()
      let shouldFail = lock.withLock { () -> Bool in
        guard let remainingSuccessfulWritesBeforeFailure else { return false }
        if remainingSuccessfulWritesBeforeFailure == 0 {
          self.remainingSuccessfulWritesBeforeFailure = nil
          return true
        }
        self.remainingSuccessfulWritesBeforeFailure = remainingSuccessfulWritesBeforeFailure - 1
        return false
      }
      guard !shouldFail else { throw RuntimeTestError.injectedOutboxWriteFailure }
      try data.write(to: url, options: .atomic)
      lock.withLock {
        successfulWrites += 1
      }
    }
  }

  private actor RuntimeTestCallbackExchange {
    private let callbackURL: String
    private var totalRequests = 0
    private var nextRequestGate: RuntimeTestAsyncGate?
    private var nextResponseGate: RuntimeTestAsyncGate?

    init(callbackURL: String) {
      self.callbackURL = callbackURL
    }

    func requestCount() -> Int { totalRequests }

    func blockNextResponse(until gate: RuntimeTestAsyncGate) {
      nextResponseGate = gate
    }

    func blockNextRequest(until gate: RuntimeTestAsyncGate) {
      nextRequestGate = gate
    }

    func exchange(
      _ callbackURL: String,
      _ headers: [AgentEventHTTPHeader],
      _ body: Data
    ) async throws -> AgentEventHTTPResponse {
      guard callbackURL == self.callbackURL,
        let request = try? JSONDecoder().decode(RuntimeTestVerificationRequest.self, from: body),
        request.type == "verification",
        !request.challenge.isEmpty
      else {
        throw RuntimeTestError.invalidExchange
      }
      let requestGate = nextRequestGate
      nextRequestGate = nil
      await requestGate?.pause()
      try Task.checkCancellation()
      totalRequests += 1
      let responseGate = nextResponseGate
      nextResponseGate = nil
      await responseGate?.pause()
      let response = try JSONEncoder().encode(
        RuntimeTestVerificationResponse(challenge: request.challenge)
      )
      return AgentEventHTTPResponse(statusCode: 200, body: response)
    }
  }

  private actor RuntimeTestApplicationExchange {
    private let callbackURL: String
    private var receivedBodies: [Data] = []
    private var statuses: [Int]
    private var nextResponseGate: RuntimeTestAsyncGate?

    init(callbackURL: String, statuses: [Int] = []) {
      self.callbackURL = callbackURL
      self.statuses = statuses
    }

    func requestCount() -> Int { receivedBodies.count }

    func bodies() -> [Data] { receivedBodies }

    func blockNextResponse(until gate: RuntimeTestAsyncGate) {
      nextResponseGate = gate
    }

    func exchange(
      _ callbackURL: String,
      _ headers: [AgentEventHTTPHeader],
      _ body: Data
    ) async throws -> AgentEventHTTPResponse {
      guard callbackURL == self.callbackURL,
        let envelope = try? JSONDecoder().decode(AgentEventEnvelope.self, from: body),
        envelope.cursor == nil
      else {
        throw RuntimeTestError.invalidExchange
      }
      receivedBodies.append(body)
      let statusCode = statuses.isEmpty ? 204 : statuses.removeFirst()
      let responseGate = nextResponseGate
      nextResponseGate = nil
      await responseGate?.pause()
      return AgentEventHTTPResponse(statusCode: statusCode, body: Data())
    }
  }

  private actor RuntimeTestAsyncGate {
    private var isEntered = false
    private var isReleased = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private let onEntry: (@Sendable () -> Void)?

    init(onEntry: (@Sendable () -> Void)? = nil) {
      self.onEntry = onEntry
    }

    func pause() async {
      let firstEntry = !isEntered
      isEntered = true
      if firstEntry { onEntry?() }
      enteredContinuation?.resume()
      enteredContinuation = nil
      guard !isReleased else { return }
      await withCheckedContinuation { continuation in
        releaseContinuation = continuation
      }
    }

    func waitUntilEntered() async {
      guard !isEntered else { return }
      await withCheckedContinuation { continuation in
        enteredContinuation = continuation
      }
    }

    func hasEntered() -> Bool { isEntered }
    func hasReleased() -> Bool { isReleased }

    func release() {
      isReleased = true
      releaseContinuation?.resume()
      releaseContinuation = nil
    }
  }

  private actor RuntimeTestScopeAuthorizer {
    private let authority: AgentCapabilityAuthority
    private let gate: RuntimeTestAsyncGate
    private let pauseOnCall: Int
    private var callCount = 0

    init(
      authority: AgentCapabilityAuthority,
      gate: RuntimeTestAsyncGate,
      pauseOnCall: Int
    ) {
      self.authority = authority
      self.gate = gate
      self.pauseOnCall = pauseOnCall
    }

    func authorize(
      profileID: UUID,
      scope: AgentEventScope,
      workspace: Workspace
    ) async throws -> UInt64 {
      let revision = try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: scope,
        workspace: workspace
      )
      callCount += 1
      if callCount == pauseOnCall {
        await gate.pause()
      }
      return revision
    }
  }

  private final class RuntimeTestCapabilityAuthority:
    AgentCapabilityAuthorizing,
    @unchecked Sendable
  {
    private let authority: AgentCapabilityAuthority
    private let assertionGate: RuntimeTestAsyncGate
    private let pauseOnAssertion: Int
    private let lock = NSLock()
    private var assertionCount = 0

    var temporaryExclusionGeneration: UUID? {
      authority.temporaryExclusionGeneration
    }

    init(
      authority: AgentCapabilityAuthority,
      assertionGate: RuntimeTestAsyncGate,
      pauseOnAssertion: Int
    ) {
      self.authority = authority
      self.assertionGate = assertionGate
      self.pauseOnAssertion = pauseOnAssertion
    }

    func snapshot(
      profileID: UUID,
      workspace: Workspace
    ) async throws -> AgentAuthorizationSnapshot {
      try await authority.snapshot(profileID: profileID, workspace: workspace)
    }

    func assertCurrent(profileID: UUID, grantRevision: UInt64) async throws {
      let shouldPause = lock.withLock {
        assertionCount += 1
        return assertionCount == pauseOnAssertion
      }
      if shouldPause { await assertionGate.pause() }
      try await authority.assertCurrent(profileID: profileID, grantRevision: grantRevision)
    }
  }

  private actor RuntimeTestSnapshotReaderGate {
    private var failingAfterSequence: UInt64?
    private var failureCount = 0
    private var nextReadGate: RuntimeTestAsyncGate?

    func failOnce(afterSequence sequence: UInt64) {
      failingAfterSequence = sequence
    }

    func pauseNextRead(until gate: RuntimeTestAsyncGate) {
      nextReadGate = gate
    }

    func readSnapshot(from localStore: LocalStore) async throws -> LocalStoreSnapshot {
      let snapshot = try await localStore.loadSnapshot()
      let nextReadGate = self.nextReadGate
      self.nextReadGate = nil
      await nextReadGate?.pause()
      guard let failingAfterSequence,
        let journal = snapshot.agentEventJournal,
        journal.lastSequence > failingAfterSequence
      else {
        return snapshot
      }
      self.failingAfterSequence = nil
      failureCount += 1
      throw RuntimeTestError.transientSnapshotReadFailure
    }

    func injectedFailureCount() -> Int { failureCount }
  }

  private final class RuntimeTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)

    func now() -> Date {
      lock.lock()
      defer { lock.unlock() }
      return value
    }

    func advance(by interval: TimeInterval) {
      lock.lock()
      defer { lock.unlock() }
      value = value.addingTimeInterval(interval)
    }
  }

  private final class RuntimeTestSecretStore: AgentSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func read(service: String, account: String) throws -> Data? {
      lock.lock()
      defer { lock.unlock() }
      return values["\(service)\u{0}\(account)"]
    }

    func write(_ data: Data, service: String, account: String) throws {
      lock.lock()
      defer { lock.unlock() }
      values["\(service)\u{0}\(account)"] = data
    }

    func delete(service: String, account: String) throws {
      lock.lock()
      defer { lock.unlock() }
      values.removeValue(forKey: "\(service)\u{0}\(account)")
    }
  }

  private final class RuntimeTestRandomBytes: AgentRandomBytesProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var nextByte: UInt8 = 0

    func randomBytes(count: Int) throws -> Data {
      lock.lock()
      defer { lock.unlock() }
      nextByte &+= 1
      return Data(repeating: nextByte, count: count)
    }
  }

  private final class RuntimeTestSignalInbox<Signal: Sendable>: Sendable {
    private struct ActiveRead: Sendable {
      let token: UUID
      var isRegistered: Bool
      var isCancelled: Bool
      var isClaimed: Bool
      var continuation: CheckedContinuation<Signal?, Never>?
    }

    private struct State: Sendable {
      var signals: [Signal] = []
      var isFinished = false
      var activeRead: ActiveRead?
    }

    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    func yield(_ signal: Signal) {
      let continuation = lock.withLock { state -> CheckedContinuation<Signal?, Never>? in
        guard !state.isFinished else { return nil }
        guard var activeRead = state.activeRead,
          activeRead.isRegistered,
          !activeRead.isClaimed,
          let continuation = activeRead.continuation
        else {
          state.signals.append(signal)
          return nil
        }
        activeRead.continuation = nil
        activeRead.isClaimed = true
        state.activeRead = activeRead
        return continuation
      }
      continuation?.resume(returning: signal)
    }

    func finish() {
      let continuation = lock.withLock { state -> CheckedContinuation<Signal?, Never>? in
        guard !state.isFinished else { return nil }
        state.isFinished = true
        guard state.signals.isEmpty,
          var activeRead = state.activeRead,
          activeRead.isRegistered,
          !activeRead.isClaimed,
          let continuation = activeRead.continuation
        else { return nil }
        activeRead.continuation = nil
        activeRead.isClaimed = true
        state.activeRead = activeRead
        return continuation
      }
      continuation?.resume(returning: nil)
    }

    func next() async -> Signal? {
      let token = UUID()
      lock.withLock { state in
        guard case .none = state.activeRead else {
          preconditionFailure("RuntimeTestSignalInbox supports one active read.")
        }
        state.activeRead = ActiveRead(
          token: token,
          isRegistered: false,
          isCancelled: false,
          isClaimed: false,
          continuation: nil
        )
      }

      let signal = await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<Signal?, Never>) in
          let immediate: Signal?? = lock.withLock { state in
            guard var activeRead = state.activeRead,
              activeRead.token == token,
              !activeRead.isClaimed
            else {
              preconditionFailure("RuntimeTestSignalInbox lost its active read token.")
            }
            activeRead.isRegistered = true
            if Task.isCancelled { activeRead.isCancelled = true }
            if activeRead.isCancelled {
              activeRead.isClaimed = true
              state.activeRead = activeRead
              return .some(nil)
            }
            if !state.signals.isEmpty {
              let signal = state.signals.removeFirst()
              activeRead.isClaimed = true
              state.activeRead = activeRead
              return .some(.some(signal))
            }
            if state.isFinished {
              activeRead.isClaimed = true
              state.activeRead = activeRead
              return .some(nil)
            }
            activeRead.continuation = continuation
            state.activeRead = activeRead
            return nil
          }
          if let immediate { continuation.resume(returning: immediate) }
        }
      } onCancel: {
        cancelRead(token)
      }

      lock.withLock { state in
        guard let activeRead = state.activeRead,
          activeRead.token == token,
          activeRead.isRegistered,
          activeRead.isClaimed
        else {
          preconditionFailure("RuntimeTestSignalInbox completed an unclaimed read.")
        }
        state.activeRead = nil
      }
      return signal
    }

    private func cancelRead(_ token: UUID) {
      let continuation = lock.withLock { state -> CheckedContinuation<Signal?, Never>? in
        guard var activeRead = state.activeRead,
          activeRead.token == token,
          !activeRead.isClaimed
        else { return nil }
        activeRead.isCancelled = true
        guard activeRead.isRegistered, let continuation = activeRead.continuation else {
          state.activeRead = activeRead
          return nil
        }
        activeRead.continuation = nil
        activeRead.isClaimed = true
        state.activeRead = activeRead
        return continuation
      }
      continuation?.resume(returning: nil)
    }
  }
#endif
