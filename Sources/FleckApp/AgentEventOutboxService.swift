import FleckCore
import Foundation

enum AgentEventOwnerApprovalReadinessMode: Sendable {
  case prepared(originIntentID: UUID)
  case independent
  case legacy
}

enum AgentEventOwnerApprovalReadinessState: Sendable {
  case awaitingApproval
  case ownerPaused
  case pausedCapacity
  case pausedHistory
}

struct AgentEventOutboxService: Sendable {
  private enum CaptureDecision {
    case skip(AgentEventOutboxNonDeliveryDisposition?)
    case duplicate
    case body(Data)
    case capacity
  }

  private struct CaptureCandidate {
    let position: AgentEventOutboxPosition
    let eventID: String
    let noteID: UUID
    let revision: UInt64
    let occurredAt: Date
    let eventName: AgentEventName
    let changedFields: [AgentEventChangedField]?
    let decision: CaptureDecision
  }

  private struct NoteUpdateBurst {
    let first: CaptureCandidate
    var latest: CaptureCandidate
    var changedFields: Set<AgentEventChangedField>
    var sourceRecordCount = 1
  }

  private let store: AgentEventOutboxStore
  private let snapshotReader: @Sendable () async throws -> LocalStoreSnapshot
  private let profileStore: AgentProfileStore
  private let subscriptionStore: AgentEventSubscriptionStore
  private let authority: AgentCapabilityAuthority
  private let coalescesNoteUpdateBursts: Bool
  private static let maximumCoalescedSourceRecords = 32

  private func advancingPreparedResponseFence(
    _ current: AgentEventOutboxPreparedResponseFence,
    to requested: AgentEventOutboxPreparedResponseFence
  ) throws -> AgentEventOutboxPreparedResponseFence {
    guard current.binding == requested.binding else {
      throw AgentEventOutboxError.sourceChanged
    }
    if current.originIntentID == requested.originIntentID {
      guard current.disposition == .failedResponse else { return requested }
      var failedFence = current
      failedFence.ownerControlGenerationID = requested.ownerControlGenerationID
      return failedFence
    }
    guard current.disposition == .failedResponse else {
      throw AgentEventOutboxError.sourceChanged
    }
    return requested
  }

  init(
    store: AgentEventOutboxStore,
    localStore: LocalStore,
    profileStore: AgentProfileStore,
    subscriptionStore: AgentEventSubscriptionStore,
    authority: AgentCapabilityAuthority,
    snapshotReader: (@Sendable () async throws -> LocalStoreSnapshot)? = nil,
    coalescesNoteUpdateBursts: Bool = false
  ) {
    self.store = store
    self.snapshotReader = snapshotReader ?? { try await localStore.loadSnapshot() }
    self.profileStore = profileStore
    self.subscriptionStore = subscriptionStore
    self.authority = authority
    self.coalescesNoteUpdateBursts = coalescesNoteUpdateBursts
  }

  func armProspectivePreparedResponseFence(
    binding: AgentEventCallbackVerificationBinding,
    expectedOwnerDeliveryControl: AgentEventDeliveryControl,
    prospectiveGenerationID: UUID,
    originIntentID: UUID
  ) throws {
    guard
      expectedOwnerDeliveryControl.binding == binding,
      expectedOwnerDeliveryControl.generationID != prospectiveGenerationID,
      subscriptionStore.isCurrentOwnerDeliveryControl(
        binding: binding,
        control: expectedOwnerDeliveryControl
      )
    else {
      throw AgentEventOutboxError.sourceChanged
    }
    let requestedFence = AgentEventOutboxPreparedResponseFence(
      binding: binding,
      ownerControlGenerationID: prospectiveGenerationID,
      originIntentID: originIntentID
    )
    try store.update { state in
      guard let index = state.progress.firstIndex(where: {
        $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
      }) else {
        throw AgentEventOutboxError.registrationRequired
      }
      let progress = state.progress[index]
      guard
        progress.subscriptionRevision == binding.subscriptionRevision,
        progress.grantRevision == binding.grantRevision,
        progress.requiresPreparedResponseFence == (progress.preparedResponseFence != nil)
      else {
        throw AgentEventOutboxError.sourceChanged
      }
      if let currentFence = progress.preparedResponseFence {
        guard currentFence.binding == binding,
          currentFence.ownerControlGenerationID != prospectiveGenerationID
        else {
          throw AgentEventOutboxError.sourceChanged
        }
        if currentFence.originIntentID == originIntentID {
          guard currentFence.ownerControlGenerationID == expectedOwnerDeliveryControl.generationID,
            currentFence.disposition == .awaitingResponse
          else {
            throw AgentEventOutboxError.sourceChanged
          }
        } else {
          guard currentFence.disposition == .failedResponse else {
            throw AgentEventOutboxError.sourceChanged
          }
        }
      } else if progress.requiresPreparedResponseFence {
        throw AgentEventOutboxError.storageFailure
      }
      state.progress[index].preparedResponseFence = requestedFence
      state.progress[index].requiresPreparedResponseFence = true
    }
    guard
      let persistedProgress = try store.load().progress.first(where: {
        $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
      }),
      persistedProgress.subscriptionRevision == binding.subscriptionRevision,
      persistedProgress.grantRevision == binding.grantRevision,
      persistedProgress.requiresPreparedResponseFence,
      persistedProgress.preparedResponseFence == requestedFence,
      subscriptionStore.isCurrentOwnerDeliveryControl(
        binding: binding,
        control: expectedOwnerDeliveryControl
      )
    else {
      throw AgentEventOutboxError.storageFailure
    }
  }

  func failProspectivePreparedResponseFence(
    binding: AgentEventCallbackVerificationBinding,
    prospectiveGenerationID: UUID,
    originIntentID: UUID
  ) throws {
    guard subscriptionStore.isCurrentOwnerDeliveryControl(
      binding: binding,
      generationID: prospectiveGenerationID
    ) else {
      return
    }
    var didFail = false
    try store.update { state in
      guard
        let index = state.progress.firstIndex(where: {
          $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
        }),
        state.progress[index].subscriptionRevision == binding.subscriptionRevision,
        state.progress[index].grantRevision == binding.grantRevision,
        state.progress[index].requiresPreparedResponseFence,
        var fence = state.progress[index].preparedResponseFence,
        fence.binding == binding,
        fence.ownerControlGenerationID == prospectiveGenerationID,
        fence.originIntentID == originIntentID,
        fence.disposition == .awaitingResponse
      else {
        return
      }
      fence.disposition = .failedResponse
      state.progress[index].preparedResponseFence = fence
      didFail = true
    }
    guard didFail else { return }
    guard
      let persistedFence = try store.load().progress.first(where: {
        $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
      })?.preparedResponseFence,
      persistedFence.binding == binding,
      persistedFence.ownerControlGenerationID == prospectiveGenerationID,
      persistedFence.originIntentID == originIntentID,
      persistedFence.disposition == .failedResponse
    else {
      throw AgentEventOutboxError.storageFailure
    }
  }

  func registerPending(
    profileID: UUID,
    subscriptionID: String,
    now: Date = Date(),
    ownerDeliveryControl: AgentEventDeliveryControl? = nil,
    preparedResponseOriginID: UUID? = nil
  ) async throws {
    let expectedTemporaryExclusionGeneration = authority.temporaryExclusionGeneration
    guard Self.isValidSubscriptionID(subscriptionID) else {
      throw AgentEventOutboxError.registrationRequired
    }
    let previousState = try store.load()
    let previousProgress = previousState.progress.first {
      $0.profileID == profileID && $0.subscriptionID == subscriptionID
    }
    let profiles = try await profileStore.activeProfiles()
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard profiles.contains(where: { $0.id == profileID && !$0.isRevoked }) else {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
    let subscription = try await subscriptionStore.currentSubscription(id: subscriptionID)
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard
      let subscription,
      subscription.profileID == profileID,
      subscription.status == .pending,
      subscription.expiresAt > now
    else {
      throw AgentEventOutboxError.registrationRequired
    }

    let snapshot = try await snapshotReader()
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    let grantRevision = try await authority.authorizeEventObservation(
      profileID: profileID,
      scope: subscription.scope,
      workspace: snapshot.workspace
    )
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard grantRevision == subscription.grantRevision else {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
    let authorization = try await authority.snapshot(
      profileID: profileID,
      workspace: snapshot.workspace
    )
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard authorization.profileID == profileID, authorization.grantRevision == grantRevision else {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }

    let latestProfiles = try await profileStore.activeProfiles()
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard latestProfiles.contains(where: { $0.id == profileID && !$0.isRevoked }) else {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
    let latestSubscription = try await subscriptionStore.currentSubscription(id: subscriptionID)
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard
      let latestSubscription,
      Self.sameTarget(subscription, latestSubscription),
      latestSubscription.expiresAt > now
    else {
      throw AgentEventOutboxError.sourceChanged
    }
    try await authority.assertEventObservationCurrent(
      profileID: profileID,
      grantRevision: grantRevision,
      scope: latestSubscription.scope,
      workspace: snapshot.workspace
    )
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)

    let finalSnapshot = try await snapshotReader()
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard finalSnapshot == snapshot else {
      throw AgentEventOutboxError.sourceChanged
    }
    let latestBinding =
      AgentEventCallbackVerificationBinding(
        profileID: latestSubscription.profileID,
        subscriptionID: latestSubscription.subscriptionID,
        subscriptionRevision: latestSubscription.revision,
        grantRevision: latestSubscription.grantRevision,
        signingKeyReference: latestSubscription.signingKeyReference
      )
    let ownerDeliveryControlIsCurrent =
      ownerDeliveryControl.map { control in
        control.binding == latestBinding
          && latestSubscription.deliveryControl == control
          && subscriptionStore.isCurrentOwnerDeliveryControl(
            binding: latestBinding,
            control: control
          )
      } ?? false
    let ownerControlIsCurrent = ownerDeliveryControl?.enabled == true
      && ownerDeliveryControlIsCurrent
    let requestedResponseFence: AgentEventOutboxPreparedResponseFence?
    if let preparedResponseOriginID {
      guard let ownerDeliveryControl, ownerDeliveryControlIsCurrent else {
        throw AgentEventOutboxError.sourceChanged
      }
      requestedResponseFence = AgentEventOutboxPreparedResponseFence(
        binding: latestBinding,
        ownerControlGenerationID: ownerDeliveryControl.generationID,
        originIntentID: preparedResponseOriginID
      )
    } else {
      requestedResponseFence = nil
    }
    let anchor: AgentEventOutboxPosition?
    let status: AgentEventOutboxProgressStatus
    if snapshot.source == .root, let journal = snapshot.agentEventJournal {
      anchor = AgentEventOutboxPosition(epoch: journal.epoch, sequence: journal.lastSequence)
      status = .pending
    } else if snapshot.source == .recovery {
      anchor = nil
      status = .pausedHistory
    } else {
      anchor = nil
      status = .pausedUnavailable
    }
    try store.update { state in
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      let index = state.progress.firstIndex {
        $0.profileID == profileID && $0.subscriptionID == subscriptionID
      }
      if let index {
        if let previousProgress, previousProgress.status == .discarded {
          guard state.progress[index] == previousProgress else {
            throw AgentEventOutboxError.sourceChanged
          }
          guard subscriptionStore.isCurrentSubscription(expected: latestSubscription) else {
            throw AgentEventOutboxError.sourceChanged
          }
          guard previousProgress.nonDeliveryDisposition != nil,
            state.entries.filter({
              $0.profileID == profileID && $0.subscriptionID == subscriptionID
            }).allSatisfy({ $0.body == nil && $0.status == .notDelivered })
          else {
            throw AgentEventOutboxError.sourceChanged
          }
          let previousFence = previousProgress.preparedResponseFence
          let responseFence: AgentEventOutboxPreparedResponseFence?
          if let requestedResponseFence {
            if let previousFence, previousFence.binding == latestBinding {
              responseFence = try advancingPreparedResponseFence(
                previousFence,
                to: requestedResponseFence
              )
            } else {
              responseFence = requestedResponseFence
            }
          } else {
            if var previousFence, previousFence.binding == latestBinding,
              previousFence.disposition == .awaitingResponse,
              let ownerDeliveryControl,
              previousFence.ownerControlGenerationID != ownerDeliveryControl.generationID
            {
              previousFence.disposition = .failedResponse
              responseFence = previousFence
            } else {
              responseFence = previousFence.flatMap { $0.binding == latestBinding ? $0 : nil }
            }
          }
          guard let ownerDeliveryControl else { return }
          if !ownerControlIsCurrent {
            guard requestedResponseFence != nil, ownerDeliveryControlIsCurrent,
              let nonDeliveryDisposition = previousProgress.nonDeliveryDisposition
            else {
              throw AgentEventOutboxError.sourceChanged
            }
            state.progress[index] = AgentEventOutboxProgress(
              profileID: profileID,
              subscriptionID: subscriptionID,
              subscriptionRevision: latestSubscription.revision,
              grantRevision: grantRevision,
              anchor: previousProgress.anchor,
              capturedThrough: previousProgress.capturedThrough,
              status: .discarded,
              nonDeliveryDisposition: nonDeliveryDisposition,
              preparedResponseFence: responseFence,
              requiresPreparedResponseFence: responseFence != nil
            )
            return
          }
          guard subscriptionStore.isCurrentOwnerDeliveryControl(
            binding: latestBinding,
            control: ownerDeliveryControl
          ) else {
            throw AgentEventOutboxError.sourceChanged
          }
          state.entries.removeAll {
            $0.profileID == profileID && $0.subscriptionID == subscriptionID
          }
          state.progress[index] = AgentEventOutboxProgress(
            profileID: profileID,
            subscriptionID: subscriptionID,
            subscriptionRevision: latestSubscription.revision,
            grantRevision: grantRevision,
            anchor: anchor,
            capturedThrough: anchor,
            status: status,
            nonDeliveryDisposition: nil,
            preparedResponseFence: responseFence,
            requiresPreparedResponseFence: responseFence != nil
          )
          return
        }
        guard state.progress[index].grantRevision == grantRevision else { return }
        guard subscriptionStore.isCurrentSubscription(expected: latestSubscription) else {
          throw AgentEventOutboxError.sourceChanged
        }
        if let ownerDeliveryControl {
          guard
            subscriptionStore.isCurrentOwnerDeliveryControl(
              binding: latestBinding,
              control: ownerDeliveryControl
            )
          else {
            throw AgentEventOutboxError.sourceChanged
          }
        }
        guard state.progress[index].subscriptionRevision <= latestSubscription.revision else {
          throw AgentEventOutboxError.sourceChanged
        }
        if state.progress[index].status != .pending {
          if let requestedResponseFence {
            if let currentFence = state.progress[index].preparedResponseFence,
              currentFence.binding == latestBinding
            {
              state.progress[index].preparedResponseFence = try advancingPreparedResponseFence(
                currentFence,
                to: requestedResponseFence
              )
            } else {
              state.progress[index].preparedResponseFence = requestedResponseFence
            }
          } else if var currentFence = state.progress[index].preparedResponseFence,
            currentFence.binding == latestBinding,
            currentFence.disposition == .awaitingResponse,
            let ownerDeliveryControl,
            currentFence.ownerControlGenerationID != ownerDeliveryControl.generationID
          {
            currentFence.disposition = .failedResponse
            state.progress[index].preparedResponseFence = currentFence
          }
          if state.progress[index].subscriptionRevision < latestSubscription.revision {
            state.progress[index].subscriptionRevision = latestSubscription.revision
          }
          state.progress[index].requiresPreparedResponseFence =
            state.progress[index].preparedResponseFence != nil
          return
        }
        if state.progress[index].subscriptionRevision < latestSubscription.revision {
          if let requestedResponseFence {
            if let currentFence = state.progress[index].preparedResponseFence,
              currentFence.binding == latestBinding
            {
              state.progress[index].preparedResponseFence = try advancingPreparedResponseFence(
                currentFence,
                to: requestedResponseFence
              )
            } else {
              state.progress[index].preparedResponseFence = requestedResponseFence
            }
          } else if state.progress[index].preparedResponseFence?.binding != latestBinding {
            state.progress[index].preparedResponseFence = nil
          }
          state.progress[index].subscriptionRevision = latestSubscription.revision
        } else if let requestedResponseFence {
          if let currentFence = state.progress[index].preparedResponseFence {
            guard currentFence.binding == latestBinding else {
              throw AgentEventOutboxError.sourceChanged
            }
            state.progress[index].preparedResponseFence = try advancingPreparedResponseFence(
              currentFence,
              to: requestedResponseFence
            )
          } else {
            state.progress[index].preparedResponseFence = requestedResponseFence
          }
        } else if state.progress[index].preparedResponseFence?.binding != latestBinding {
          state.progress[index].preparedResponseFence = nil
        } else if var currentFence = state.progress[index].preparedResponseFence,
          currentFence.disposition == .awaitingResponse,
          let ownerDeliveryControl,
          currentFence.ownerControlGenerationID != ownerDeliveryControl.generationID
        {
          currentFence.disposition = .failedResponse
          state.progress[index].preparedResponseFence = currentFence
        }
        state.progress[index].requiresPreparedResponseFence =
          state.progress[index].preparedResponseFence != nil
        return
      }
      guard previousProgress == nil else {
        throw AgentEventOutboxError.sourceChanged
      }
      guard state.progress.count < 128 else {
        throw AgentEventOutboxError.capacityExceeded
      }
      guard subscriptionStore.isCurrentSubscription(expected: latestSubscription) else {
        throw AgentEventOutboxError.sourceChanged
      }
      if let ownerDeliveryControl {
        guard
          subscriptionStore.isCurrentOwnerDeliveryControl(
            binding: latestBinding,
            control: ownerDeliveryControl
          )
        else {
          throw AgentEventOutboxError.sourceChanged
        }
      }
      state.progress.append(
        AgentEventOutboxProgress(
          profileID: profileID,
          subscriptionID: subscriptionID,
          subscriptionRevision: latestSubscription.revision,
          grantRevision: grantRevision,
          anchor: anchor,
          capturedThrough: anchor,
          status: status,
          nonDeliveryDisposition: nil,
          preparedResponseFence: requestedResponseFence,
          requiresPreparedResponseFence: requestedResponseFence != nil
        )
      )
    }
    if let requestedResponseFence {
      guard
        let ownerDeliveryControl,
        let persistedProgress = try store.load().progress.first(where: {
          $0.profileID == profileID && $0.subscriptionID == subscriptionID
        }),
        persistedProgress.subscriptionRevision == latestBinding.subscriptionRevision,
        persistedProgress.grantRevision == latestBinding.grantRevision,
        persistedProgress.preparedResponseFence?.binding == latestBinding,
        persistedProgress.preparedResponseFence?.ownerControlGenerationID
          == requestedResponseFence.ownerControlGenerationID,
        persistedProgress.preparedResponseFence?.originIntentID == preparedResponseOriginID,
        persistedProgress.preparedResponseFence?.disposition == .awaitingResponse,
        subscriptionStore.isCurrentSubscription(expected: latestSubscription),
        subscriptionStore.isCurrentOwnerDeliveryControl(
          binding: latestBinding,
          control: ownerDeliveryControl
        )
      else {
        throw AgentEventOutboxError.storageFailure
      }
    }
  }

  func hasPreparedResponseFence(
    binding: AgentEventCallbackVerificationBinding,
    ownerDeliveryControl: AgentEventDeliveryControl,
    originIntentID: UUID
  ) -> Bool {
    (try? requirePreparedResponseFence(
      binding: binding,
      ownerDeliveryControl: ownerDeliveryControl,
      originIntentID: originIntentID
    )) != nil
  }

  @discardableResult
  func requireOwnerApprovalReadiness(
    binding: AgentEventCallbackVerificationBinding,
    ownerDeliveryControl: AgentEventDeliveryControl,
    mode: AgentEventOwnerApprovalReadinessMode
  ) throws -> AgentEventOwnerApprovalReadinessState {
    guard
      ownerDeliveryControl.binding == binding,
      subscriptionStore.isCurrentOwnerDeliveryControl(
        binding: binding,
        control: ownerDeliveryControl
      )
    else {
      throw AgentEventOutboxError.sourceChanged
    }
    let outbox = try store.load()
    let matchingProgress = outbox.progress.filter {
      $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
    }
    guard matchingProgress.count == 1 else {
      throw matchingProgress.isEmpty
        ? AgentEventOutboxError.registrationRequired
        : AgentEventOutboxError.sourceChanged
    }
    let progress = matchingProgress[0]
    guard
      progress.subscriptionRevision == binding.subscriptionRevision,
      progress.grantRevision == binding.grantRevision
    else {
      throw AgentEventOutboxError.sourceChanged
    }
    guard progress.requiresPreparedResponseFence == (progress.preparedResponseFence != nil) else {
      throw AgentEventOutboxError.sourceChanged
    }
    switch mode {
    case .prepared(let originIntentID):
      guard progress.requiresPreparedResponseFence else {
        throw AgentEventOutboxError.sourceChanged
      }
      try requirePreparedResponseFence(
        binding: binding,
        ownerDeliveryControl: ownerDeliveryControl,
        originIntentID: originIntentID
      )
      switch progress.status {
      case .pending:
        guard progress.nonDeliveryDisposition == nil else {
          throw AgentEventOutboxError.sourceChanged
        }
        return .awaitingApproval
      case .discarded:
        guard progress.nonDeliveryDisposition == .ownerPaused else {
          throw AgentEventOutboxError.sourceChanged
        }
        return .ownerPaused
      case .pausedCapacity, .pausedHistory, .pausedUnavailable:
        throw AgentEventOutboxError.sourceChanged
      }
    case .independent:
      if ownerDeliveryControl.enabled {
        guard progress.status != .discarded, progress.nonDeliveryDisposition == nil else {
          throw AgentEventOutboxError.sourceChanged
        }
        if let fence = progress.preparedResponseFence {
          guard fence.binding == binding else {
            throw AgentEventOutboxError.sourceChanged
          }
        }
        switch progress.status {
        case .pending:
          return .awaitingApproval
        case .pausedCapacity:
          return .pausedCapacity
        case .pausedHistory:
          return .pausedHistory
        case .pausedUnavailable, .discarded:
          throw AgentEventOutboxError.sourceChanged
        }
      } else {
        guard progress.status == .discarded,
          progress.nonDeliveryDisposition == .ownerPaused,
          progress.preparedResponseFence?.ownerControlGenerationID
            != ownerDeliveryControl.generationID
        else {
          throw AgentEventOutboxError.sourceChanged
        }
      }
      if let fence = progress.preparedResponseFence {
        guard fence.binding == binding else {
          throw AgentEventOutboxError.sourceChanged
        }
      }
      return .ownerPaused
    case .legacy:
      if progress.nonDeliveryDisposition == .ownerPaused {
        guard progress.status == .discarded, !ownerDeliveryControl.enabled else {
          throw AgentEventOutboxError.sourceChanged
        }
        if let fence = progress.preparedResponseFence {
          guard fence.binding == binding,
            fence.ownerControlGenerationID != ownerDeliveryControl.generationID
          else {
            throw AgentEventOutboxError.sourceChanged
          }
        }
        return .ownerPaused
      }
      guard progress.nonDeliveryDisposition == nil else {
        throw AgentEventOutboxError.sourceChanged
      }
      if let fence = progress.preparedResponseFence {
        guard ownerDeliveryControl.enabled,
          fence.binding == binding,
          fence.ownerControlGenerationID != ownerDeliveryControl.generationID
        else {
          throw AgentEventOutboxError.sourceChanged
        }
      }
      switch progress.status {
      case .pending:
        return .awaitingApproval
      case .pausedCapacity:
        return .pausedCapacity
      case .pausedHistory:
        return .pausedHistory
      case .pausedUnavailable, .discarded:
        throw AgentEventOutboxError.sourceChanged
      }
    }
  }

  func requirePreparedResponseFence(
    binding: AgentEventCallbackVerificationBinding,
    ownerDeliveryControl: AgentEventDeliveryControl,
    originIntentID: UUID
  ) throws {
    guard ownerDeliveryControl.binding == binding else {
      throw AgentEventOutboxError.sourceChanged
    }
    let outbox = try store.load()
    guard let progress = outbox.progress.first(where: {
      $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
    }) else {
      throw AgentEventOutboxError.registrationRequired
    }
    guard
      progress.subscriptionRevision == binding.subscriptionRevision,
      progress.grantRevision == binding.grantRevision,
      progress.requiresPreparedResponseFence,
      let fence = progress.preparedResponseFence
    else {
      throw AgentEventOutboxError.sourceChanged
    }
    guard fence.binding == binding
      && fence.ownerControlGenerationID == ownerDeliveryControl.generationID
      && fence.originIntentID == originIntentID
      && fence.disposition == .awaitingResponse
    else {
      throw AgentEventOutboxError.sourceChanged
    }
  }

  func admitsDelivery(
    binding: AgentEventCallbackVerificationBinding,
    ownerDeliveryControl: AgentEventDeliveryControl
  ) -> Bool {
    guard
      ownerDeliveryControl.enabled,
      ownerDeliveryControl.binding == binding,
      let progress = try? store.load().progress.first(where: {
        $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
      }),
      progress.subscriptionRevision == binding.subscriptionRevision,
      progress.grantRevision == binding.grantRevision,
      progress.requiresPreparedResponseFence == (progress.preparedResponseFence != nil)
    else {
      return false
    }
    return progress.preparedResponseFence?.blocksDelivery(for: ownerDeliveryControl) != true
  }

  func failPreparedResponseFence(
    binding: AgentEventCallbackVerificationBinding,
    ownerDeliveryControl: AgentEventDeliveryControl,
    originIntentID: UUID
  ) throws {
    guard ownerDeliveryControl.binding == binding else {
      throw AgentEventOutboxError.sourceChanged
    }
    guard subscriptionStore.isCurrentOwnerDeliveryControl(
      binding: binding,
      control: ownerDeliveryControl
    ) else {
      return
    }
    try store.update { state in
      guard
        let index = state.progress.firstIndex(where: {
          $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
        }),
        state.progress[index].subscriptionRevision == binding.subscriptionRevision,
        state.progress[index].grantRevision == binding.grantRevision,
        var fence = state.progress[index].preparedResponseFence,
        fence.binding == binding,
        fence.ownerControlGenerationID == ownerDeliveryControl.generationID,
        fence.originIntentID == originIntentID
      else {
        return
      }
      fence.disposition = .failedResponse
      state.progress[index].preparedResponseFence = fence
    }
  }

  @discardableResult
  func clearPreparedResponseFence(
    binding: AgentEventCallbackVerificationBinding,
    ownerDeliveryControl: AgentEventDeliveryControl,
    originIntentID: UUID
  ) throws -> Bool {
    guard ownerDeliveryControl.binding == binding,
      ownerDeliveryControl.enabled,
      subscriptionStore.isCurrentOwnerDeliveryControl(
        binding: binding,
        control: ownerDeliveryControl
      )
    else {
      return false
    }
    var didClear = false
    try store.update { state in
      guard
        let index = state.progress.firstIndex(where: {
          $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
        }),
        state.progress[index].subscriptionRevision == binding.subscriptionRevision,
        state.progress[index].grantRevision == binding.grantRevision,
        let fence = state.progress[index].preparedResponseFence,
        fence.binding == binding,
        fence.ownerControlGenerationID == ownerDeliveryControl.generationID,
        fence.originIntentID == originIntentID,
        fence.disposition == .awaitingResponse
      else {
        return
      }
      state.progress[index].preparedResponseFence = nil
      state.progress[index].requiresPreparedResponseFence = false
      didClear = true
    }
    guard didClear else { return false }
    guard
      let persistedProgress = try store.load().progress.first(where: {
        $0.profileID == binding.profileID && $0.subscriptionID == binding.subscriptionID
      }),
      persistedProgress.preparedResponseFence?.binding != binding
        || persistedProgress.preparedResponseFence?.ownerControlGenerationID
          != ownerDeliveryControl.generationID
        || persistedProgress.preparedResponseFence?.originIntentID != originIntentID
        || persistedProgress.preparedResponseFence?.disposition != .awaitingResponse
    else {
      throw AgentEventOutboxError.storageFailure
    }
    return true
  }

  func capturePending(
    profileID: UUID,
    subscriptionID: String,
    now: Date = Date()
  ) async throws {
    let expectedTemporaryExclusionGeneration = authority.temporaryExclusionGeneration
    guard Self.isValidSubscriptionID(subscriptionID) else {
      throw AgentEventOutboxError.registrationRequired
    }
    let initialState = try store.load()
    guard
      let initialProgress = initialState.progress.first(where: {
        $0.profileID == profileID && $0.subscriptionID == subscriptionID
      })
    else {
      throw AgentEventOutboxError.registrationRequired
    }
    guard initialProgress.status != .discarded else { return }
    let shouldCapture = initialProgress.status == .pending
    guard
      !shouldCapture
        || (initialProgress.anchor != nil && initialProgress.capturedThrough != nil)
    else {
      throw AgentEventOutboxError.storageFailure
    }

    let profiles = try await profileStore.activeProfiles()
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard profiles.contains(where: { $0.id == profileID && !$0.isRevoked }) else {
      try discard(initialProgress, disposition: .profileRevoked)
      return
    }
    let subscription = try await subscriptionStore.currentSubscription(id: subscriptionID)
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard let subscription else {
      try discard(initialProgress, disposition: .subscriptionRemoved)
      return
    }
    guard
      subscription.profileID == profileID,
      subscription.subscriptionID == subscriptionID,
      subscription.status == .pending
    else {
      try discard(initialProgress, disposition: .subscriptionRemoved)
      return
    }
    guard subscription.revision == initialProgress.subscriptionRevision else {
      throw AgentEventOutboxError.sourceChanged
    }
    if let fence = initialProgress.preparedResponseFence {
      guard let control = subscription.deliveryControl,
        !fence.blocksDelivery(for: control)
      else {
        throw AgentEventOutboxError.sourceChanged
      }
    }
    guard subscription.expiresAt > now else {
      try discard(initialProgress, disposition: .expired)
      return
    }
    guard subscription.grantRevision == initialProgress.grantRevision else {
      try discard(initialProgress, disposition: .permissionChanged)
      return
    }

    let snapshot = try await snapshotReader()
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    let authorization: AgentAuthorizationSnapshot
    do {
      authorization = try await currentAuthorization(
        profileID: profileID,
        grantRevision: initialProgress.grantRevision,
        scope: subscription.scope,
        workspace: snapshot.workspace,
        allowsPartialFolderRead: !shouldCapture,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration
      )
    } catch let error as AgentWorkspaceError where error.code == .capabilityDenied {
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      try discard(initialProgress, disposition: .permissionChanged)
      return
    }
    var pauseStatus: AgentEventOutboxProgressStatus?
    var candidateBatches: [[CaptureCandidate]] = []
    if shouldCapture {
      guard let anchor = initialProgress.anchor,
        let capturedThrough = initialProgress.capturedThrough
      else {
        throw AgentEventOutboxError.storageFailure
      }
      if snapshot.source != .root {
        pauseStatus = snapshot.source == .recovery ? .pausedHistory : .pausedUnavailable
      } else if let journal = snapshot.agentEventJournal {
        if journal.epoch == anchor.epoch,
          capturedThrough.epoch == journal.epoch,
          capturedThrough.sequence <= journal.lastSequence,
          let nextExpectedSequence = Self.safeNextSequence(capturedThrough.sequence),
          journal.historyFloor <= nextExpectedSequence
        {
          let knownEventIDs = Set(
            initialState.entries
              .filter {
                $0.profileID == profileID && $0.subscriptionID == subscriptionID
              }
              .map(\.eventID)
          )
          let sourceCandidates = try journal.records
            .filter { $0.sequence > capturedThrough.sequence }
            .map { record in
              let position = AgentEventOutboxPosition(
                epoch: journal.epoch,
                sequence: record.sequence
              )
              guard record.eventName == subscription.event, record.provenance == .local else {
                return CaptureCandidate(
                  position: position,
                  eventID: record.eventID.uuidString.lowercased(),
                  noteID: record.noteID,
                  revision: record.revision,
                  occurredAt: record.occurredAt,
                  eventName: record.eventName,
                  changedFields: record.changedFields,
                  decision: .skip(nil)
                )
              }
              guard
                Self.isAuthorizedEventNote(
                  record.noteID,
                  scope: subscription.scope,
                  workspace: snapshot.workspace,
                  authorization: authorization
                )
              else {
                let disposition: AgentEventOutboxNonDeliveryDisposition =
                  Self.isInScope(
                    record.noteID,
                    scope: subscription.scope,
                    workspace: snapshot.workspace
                  )
                  ? .noteNoLongerAuthorized
                  : .scopeMembershipChanged
                return CaptureCandidate(
                  position: position,
                  eventID: record.eventID.uuidString.lowercased(),
                  noteID: record.noteID,
                  revision: record.revision,
                  occurredAt: record.occurredAt,
                  eventName: record.eventName,
                  changedFields: record.changedFields,
                  decision: .skip(disposition)
                )
              }
              let eventID = record.eventID.uuidString.lowercased()
              guard !knownEventIDs.contains(eventID) else {
                return CaptureCandidate(
                  position: position,
                  eventID: eventID,
                  noteID: record.noteID,
                  revision: record.revision,
                  occurredAt: record.occurredAt,
                  eventName: record.eventName,
                  changedFields: record.changedFields,
                  decision: .duplicate
                )
              }
              let body = try Self.serializedBody(for: record)
              return CaptureCandidate(
                position: position,
                eventID: eventID,
                noteID: record.noteID,
                revision: record.revision,
                occurredAt: record.occurredAt,
                eventName: record.eventName,
                changedFields: record.changedFields,
                decision: body.count < 1_024 ? .body(body) : .capacity
              )
            }
          if coalescesNoteUpdateBursts {
            candidateBatches = try Self.coalescedCaptureBatches(sourceCandidates)
          } else {
            candidateBatches = sourceCandidates.map { [$0] }
          }
        } else {
          pauseStatus = .pausedHistory
        }
      } else {
        pauseStatus = .pausedUnavailable
      }
    }

    let latestProfiles = try await profileStore.activeProfiles()
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard latestProfiles.contains(where: { $0.id == profileID && !$0.isRevoked }) else {
      try discard(initialProgress, disposition: .profileRevoked)
      return
    }
    let latestSubscription = try await subscriptionStore.currentSubscription(id: subscriptionID)
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard let latestSubscription else {
      try discard(initialProgress, disposition: .subscriptionRemoved)
      return
    }
    guard
      latestSubscription.profileID == profileID,
      latestSubscription.subscriptionID == subscriptionID,
      latestSubscription.status == .pending
    else {
      try discard(initialProgress, disposition: .subscriptionRemoved)
      return
    }
    guard latestSubscription.revision == initialProgress.subscriptionRevision else {
      throw AgentEventOutboxError.sourceChanged
    }
    guard latestSubscription.expiresAt > now else {
      try discard(initialProgress, disposition: .expired)
      return
    }
    guard latestSubscription.grantRevision == initialProgress.grantRevision else {
      try discard(initialProgress, disposition: .permissionChanged)
      return
    }
    guard Self.sameTarget(subscription, latestSubscription) else {
      throw AgentEventOutboxError.sourceChanged
    }
    let latestAuthorization: AgentAuthorizationSnapshot
    do {
      latestAuthorization = try await currentAuthorization(
        profileID: profileID,
        grantRevision: initialProgress.grantRevision,
        scope: latestSubscription.scope,
        workspace: snapshot.workspace,
        allowsPartialFolderRead: !shouldCapture,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration
      )
    } catch let error as AgentWorkspaceError where error.code == .capabilityDenied {
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      try discard(initialProgress, disposition: .permissionChanged)
      return
    }
    let finalSnapshot = try await snapshotReader()
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard finalSnapshot == snapshot else {
      throw AgentEventOutboxError.sourceChanged
    }

    try store.update { state in
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      guard
        let progressIndex = state.progress.firstIndex(where: {
          $0.profileID == profileID && $0.subscriptionID == subscriptionID
        }),
        state.progress[progressIndex] == initialProgress
      else {
        throw AgentEventOutboxError.sourceChanged
      }
      if let fence = initialProgress.preparedResponseFence {
        guard let control = latestSubscription.deliveryControl,
          !fence.blocksDelivery(for: control)
        else {
          throw AgentEventOutboxError.sourceChanged
        }
      }
      state.progress[progressIndex].subscriptionRevision = latestSubscription.revision
      for entryIndex in state.entries.indices
      where
        state.entries[entryIndex].profileID == profileID
        && state.entries[entryIndex].subscriptionID == subscriptionID
        && state.entries[entryIndex].status == .awaitingVerification
      {
        guard let body = state.entries[entryIndex].body,
          let envelope = try? JSONDecoder().decode(AgentEventEnvelope.self, from: body)
        else {
          throw AgentEventOutboxError.storageFailure
        }
        let noteID = Self.eventNoteID(envelope.data)
        guard
          Self.isAuthorizedEventNote(
            noteID,
            scope: latestSubscription.scope,
            workspace: snapshot.workspace,
            authorization: latestAuthorization
          )
        else {
          let disposition =
            Self.isInScope(
              noteID,
              scope: latestSubscription.scope,
              workspace: snapshot.workspace
            )
            ? AgentEventOutboxNonDeliveryDisposition.noteNoLongerAuthorized
            : .scopeMembershipChanged
          state.entries[entryIndex].body = nil
          state.entries[entryIndex].status = .notDelivered
          state.entries[entryIndex].nonDeliveryDisposition = disposition
          state.progress[progressIndex].nonDeliveryDisposition = disposition
          continue
        }
      }

      guard shouldCapture else { return }
      if let pauseStatus {
        state.progress[progressIndex].status = pauseStatus
        return
      }

      for batch in candidateBatches {
        let previousPosition = state.progress[progressIndex].capturedThrough
        let previousDisposition = state.progress[progressIndex].nonDeliveryDisposition
        let firstNewEntryIndex = state.entries.count
        var capacityExceeded = false
        for candidate in batch {
          switch candidate.decision {
          case .skip(let disposition):
            if let disposition {
              state.progress[progressIndex].nonDeliveryDisposition = disposition
            }
            state.progress[progressIndex].capturedThrough = candidate.position
          case .duplicate:
            state.progress[progressIndex].capturedThrough = candidate.position
          case .capacity:
            capacityExceeded = true
          case .body(let body):
            let entryKeyExists = state.entries.contains {
              $0.profileID == profileID
                && $0.subscriptionID == subscriptionID
                && $0.eventID == candidate.eventID
            }
            if entryKeyExists {
              state.progress[progressIndex].capturedThrough = candidate.position
              continue
            }
            state.entries.append(
              AgentEventOutboxEntry(
                profileID: profileID,
                subscriptionID: subscriptionID,
                eventID: candidate.eventID,
                sourcePosition: candidate.position,
                body: body,
                status: .awaitingVerification,
                nonDeliveryDisposition: nil
              )
            )
            state.progress[progressIndex].capturedThrough = candidate.position
            do {
              try AgentEventOutboxStore.validateForWrite(state)
            } catch AgentEventOutboxError.capacityExceeded {
              capacityExceeded = true
            }
          }
          if capacityExceeded { break }
        }
        guard capacityExceeded else { continue }
        state.entries.removeSubrange(firstNewEntryIndex..<state.entries.count)
        state.progress[progressIndex].capturedThrough = previousPosition
        state.progress[progressIndex].nonDeliveryDisposition = previousDisposition
        state.progress[progressIndex].status = .pausedCapacity
        return
      }
    }
  }

  func discardPendingBodies(
    profileID: UUID,
    subscriptionID: String,
    disposition: AgentEventOutboxNonDeliveryDisposition,
    expectedCancellationBinding: AgentEventCallbackVerificationBinding? = nil,
    expectedCancellationControl: AgentEventDeliveryControl? = nil
  ) throws {
    let cancellationFence: (
      binding: AgentEventCallbackVerificationBinding,
      control: AgentEventDeliveryControl
    )?
    switch (expectedCancellationBinding, expectedCancellationControl) {
    case (nil, nil):
      cancellationFence = nil
    case (let binding?, let control?):
      guard
        binding.profileID == profileID,
        binding.subscriptionID == subscriptionID,
        control.binding == binding,
        !control.enabled
      else {
        throw AgentEventOutboxError.sourceChanged
      }
      cancellationFence = (binding, control)
    default:
      throw AgentEventOutboxError.sourceChanged
    }
    let initialState = try store.load()
    guard
      let expected = initialState.progress.first(where: {
        $0.profileID == profileID && $0.subscriptionID == subscriptionID
      })
    else {
      return
    }
    try store.update { state in
      guard
        let index = state.progress.firstIndex(where: {
          $0.profileID == profileID && $0.subscriptionID == subscriptionID
        }),
        state.progress[index] == expected
      else {
        throw AgentEventOutboxError.sourceChanged
      }
      if let cancellationFence {
        guard
          expected.profileID == cancellationFence.binding.profileID,
          expected.subscriptionID == cancellationFence.binding.subscriptionID,
          expected.subscriptionRevision == cancellationFence.binding.subscriptionRevision,
          expected.grantRevision == cancellationFence.binding.grantRevision,
          subscriptionStore.isCurrentOwnerDeliveryControl(
            binding: cancellationFence.binding,
            control: cancellationFence.control
          )
        else {
          throw AgentEventOutboxError.sourceChanged
        }
      }
      state.progress[index].status = .discarded
      state.progress[index].nonDeliveryDisposition = disposition
      for entryIndex in state.entries.indices
      where
        state.entries[entryIndex].profileID == profileID
        && state.entries[entryIndex].subscriptionID == subscriptionID
        && state.entries[entryIndex].status == .awaitingVerification
      {
        state.entries[entryIndex].body = nil
        state.entries[entryIndex].status = .notDelivered
        state.entries[entryIndex].nonDeliveryDisposition = disposition
      }
    }
  }

  func releaseCompletedRecords(
    _ records: [AgentEventDeliveryLedgerRecord]
  ) async throws {
    let completed = records.filter {
      switch $0.status {
      case .receipt, .terminal, .expired, .exhausted, .superseded:
        true
      case .reserved, .retryWaiting, .paused:
        false
      }
    }
    for record in completed {
      guard
        let subscription = try await subscriptionStore.currentSubscription(
          id: record.binding.subscriptionID
        ),
        AgentEventCallbackVerificationBinding(
          profileID: subscription.profileID,
          subscriptionID: subscription.subscriptionID,
          subscriptionRevision: subscription.revision,
          grantRevision: subscription.grantRevision,
          signingKeyReference: subscription.signingKeyReference
        ) == record.binding
      else {
        continue
      }
      try store.update { state in
        guard
          let progressIndex = state.progress.firstIndex(where: {
            $0.profileID == record.binding.profileID
              && $0.subscriptionID == record.binding.subscriptionID
              && $0.subscriptionRevision == record.binding.subscriptionRevision
              && $0.grantRevision == record.binding.grantRevision
          }),
          state.progress[progressIndex].status == .pending
            || state.progress[progressIndex].status == .pausedCapacity,
          let entry = state.entries.first(where: {
            $0.profileID == record.binding.profileID
              && $0.subscriptionID == record.binding.subscriptionID
              && $0.eventID == record.eventID
              && $0.sourcePosition == record.sourcePosition
              && $0.status == .awaitingVerification
              && $0.body != nil
          })
        else {
          return
        }
        state.entries.removeAll {
          $0.profileID == entry.profileID
            && $0.subscriptionID == entry.subscriptionID
            && $0.eventID == entry.eventID
            && $0.sourcePosition == entry.sourcePosition
        }
        if state.progress[progressIndex].status == .pausedCapacity {
          state.progress[progressIndex].status = .pending
        }
      }
    }
  }

  private func currentAuthorization(
    profileID: UUID,
    grantRevision: UInt64,
    scope: AgentEventScope,
    workspace: Workspace,
    allowsPartialFolderRead: Bool,
    expectedTemporaryExclusionGeneration: UUID?
  ) async throws -> AgentAuthorizationSnapshot {
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    let authorization = try await authority.snapshot(profileID: profileID, workspace: workspace)
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard
      authorization.profileID == profileID,
      authorization.grantRevision == grantRevision
    else {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
    do {
      let currentRevision = try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: scope,
        workspace: workspace
      )
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      guard currentRevision == grantRevision else {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }
    } catch let error as AgentWorkspaceError where error.code == .capabilityDenied {
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      guard allowsPartialFolderRead, case .folder(let folderID) = scope else {
        throw error
      }
      let state = try await authority.store.currentState()
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      guard
        let profile = state.profiles[profileID],
        profile.profileID == profileID,
        profile.grantRevision == grantRevision,
        profile.allowedCapabilities.contains(.readNotes),
        profile.allowsEventObservation,
        workspace.folders.contains(where: { $0.id == folderID }),
        profile.grants.contains(where: { grant in
          guard case .folderIncludingFutureNotes(let grantedFolderID) = grant.scope
          else { return false }
          return grantedFolderID == folderID && grant.authority.allows(.read)
        })
      else {
        throw error
      }
    }
    return authorization
  }

  private func requireTemporaryExclusionGeneration(_ expected: UUID?) throws {
    guard authority.temporaryExclusionGeneration == expected else {
      throw AgentEventOutboxError.sourceChanged
    }
  }

  private func discard(
    _ expected: AgentEventOutboxProgress,
    disposition: AgentEventOutboxNonDeliveryDisposition
  ) throws {
    try store.update { state in
      guard
        let index = state.progress.firstIndex(where: {
          $0.profileID == expected.profileID
            && $0.subscriptionID == expected.subscriptionID
        }),
        state.progress[index] == expected
      else {
        throw AgentEventOutboxError.sourceChanged
      }
      state.progress[index].status = .discarded
      state.progress[index].nonDeliveryDisposition = disposition
      for entryIndex in state.entries.indices
      where
        state.entries[entryIndex].profileID == expected.profileID
        && state.entries[entryIndex].subscriptionID == expected.subscriptionID
        && state.entries[entryIndex].status == .awaitingVerification
      {
        state.entries[entryIndex].body = nil
        state.entries[entryIndex].status = .notDelivered
        state.entries[entryIndex].nonDeliveryDisposition = disposition
      }
    }
  }

  private static func sameTarget(
    _ lhs: AgentEventPendingSubscription,
    _ rhs: AgentEventPendingSubscription
  ) -> Bool {
    lhs.subscriptionID == rhs.subscriptionID
      && lhs.profileID == rhs.profileID
      && lhs.event == rhs.event
      && lhs.scope == rhs.scope
      && lhs.grantRevision == rhs.grantRevision
      && lhs.revision == rhs.revision
      && lhs.expiresAt == rhs.expiresAt
      && rhs.status == .pending
  }

  private static func isAuthorizedEventNote(
    _ noteID: UUID,
    scope: AgentEventScope,
    workspace: Workspace,
    authorization: AgentAuthorizationSnapshot
  ) -> Bool {
    guard
      authorization.readableNoteIDs.contains(noteID),
      let note = workspace.notes.first(where: { $0.id == noteID })
    else {
      return false
    }
    switch scope {
    case .note(let selectedNoteID):
      return selectedNoteID == noteID
    case .folder(let selectedFolderID):
      return note.folderID == selectedFolderID
    }
  }

  private static func isInScope(
    _ noteID: UUID,
    scope: AgentEventScope,
    workspace: Workspace
  ) -> Bool {
    guard let note = workspace.notes.first(where: { $0.id == noteID }) else { return false }
    switch scope {
    case .note(let selectedNoteID):
      return selectedNoteID == noteID
    case .folder(let selectedFolderID):
      return note.folderID == selectedFolderID
    }
  }

  private static func serializedBody(for record: AgentEventJournalRecord) throws -> Data {
    let data: AgentEventData
    switch record.eventName {
    case .noteCreated:
      data = .noteCreated(noteID: record.noteID, revision: record.revision, origin: .local)
    case .noteUpdated:
      guard let changedFields = record.changedFields else {
        throw AgentEventOutboxError.storageFailure
      }
      data = .noteUpdated(
        noteID: record.noteID,
        revision: record.revision,
        changedFields: changedFields,
        origin: .local
      )
    case .taskStateChanged:
      guard let transition = record.completionTransition else {
        throw AgentEventOutboxError.storageFailure
      }
      data = .taskStateChanged(
        noteID: record.noteID,
        revision: record.revision,
        transition: transition,
        origin: .local
      )
    }
    return try serializedBody(
      eventID: record.eventID.uuidString.lowercased(),
      name: record.eventName,
      occurredAt: record.occurredAt,
      data: data
    )
  }

  private static func serializedBody(
    eventID: String,
    name: AgentEventName,
    occurredAt: Date,
    data: AgentEventData
  ) throws -> Data {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let envelope = try AgentEventEnvelope(
      eventID: eventID,
      name: name,
      timestamp: formatter.string(from: occurredAt),
      data: data,
      cursor: nil
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(envelope)
  }

  private static func coalesceNoteUpdateBursts(
    _ candidates: [CaptureCandidate]
  ) throws -> [CaptureCandidate] {
    var coalesced: [CaptureCandidate] = []
    var bursts: [UUID: NoteUpdateBurst] = [:]
    for candidate in candidates {
      guard candidate.eventName == .noteUpdated,
        case .body = candidate.decision,
        let fields = candidate.changedFields
      else {
        try flush(&bursts, to: &coalesced)
        coalesced.append(candidate)
        continue
      }

      if var burst = bursts[candidate.noteID] {
        let elapsed = candidate.occurredAt.timeIntervalSince(burst.first.occurredAt)
        if burst.sourceRecordCount < Self.maximumCoalescedSourceRecords,
          candidate.occurredAt >= burst.first.occurredAt,
          elapsed <= 2
        {
          burst.latest = candidate
          burst.changedFields.formUnion(fields)
          burst.sourceRecordCount += 1
          bursts[candidate.noteID] = burst
          continue
        }
        coalesced.append(try finalized(burst))
      }

      bursts[candidate.noteID] = NoteUpdateBurst(
        first: candidate,
        latest: candidate,
        changedFields: Set(fields)
      )
    }
    try flush(&bursts, to: &coalesced)
    coalesced.sort { $0.position.sequence < $1.position.sequence }
    return coalesced
  }

  private static func coalescedCaptureBatches(
    _ candidates: [CaptureCandidate]
  ) throws -> [[CaptureCandidate]] {
    var batches: [[CaptureCandidate]] = []
    var startIndex = 0
    while startIndex < candidates.count {
      let endIndex = min(startIndex + Self.maximumCoalescedSourceRecords, candidates.count)
      batches.append(
        try coalesceNoteUpdateBursts(Array(candidates[startIndex..<endIndex]))
      )
      startIndex = endIndex
    }
    return batches
  }

  private static func flush(
    _ bursts: inout [UUID: NoteUpdateBurst],
    to candidates: inout [CaptureCandidate]
  ) throws {
    candidates.append(contentsOf: try bursts.values.map(finalized))
    bursts.removeAll()
  }

  private static func finalized(_ burst: NoteUpdateBurst) throws -> CaptureCandidate {
    guard burst.sourceRecordCount > 1 else { return burst.latest }
    let latest = burst.latest
    let changedFields = burst.changedFields.sorted { $0.rawValue < $1.rawValue }
    let body = try serializedBody(
      eventID: latest.eventID,
      name: .noteUpdated,
      occurredAt: latest.occurredAt,
      data: .noteUpdated(
        noteID: latest.noteID,
        revision: latest.revision,
        changedFields: changedFields,
        origin: .local
      )
    )
    return CaptureCandidate(
      position: latest.position,
      eventID: latest.eventID,
      noteID: latest.noteID,
      revision: latest.revision,
      occurredAt: latest.occurredAt,
      eventName: .noteUpdated,
      changedFields: changedFields,
      decision: .body(body)
    )
  }

  private static func eventNoteID(_ data: AgentEventData) -> UUID {
    switch data {
    case .noteCreated(let noteID, _, _), .noteUpdated(let noteID, _, _, _),
      .taskStateChanged(let noteID, _, _, _):
      return noteID
    }
  }

  private static func isValidSubscriptionID(_ value: String) -> Bool {
    value.hasPrefix("evt_")
      && value.utf8.count == 68
      && value.utf8.dropFirst(4).allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }

  private static func safeNextSequence(_ value: UInt64) -> UInt64? {
    let (next, overflow) = value.addingReportingOverflow(1)
    guard !overflow else { return nil }
    return next
  }
}
