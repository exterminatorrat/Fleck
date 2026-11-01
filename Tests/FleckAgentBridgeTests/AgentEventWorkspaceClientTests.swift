import FleckAgentProtocol
import FleckCore
import Foundation
import Testing

@testable import FleckAgentBridge

@Suite("Agent event workspace client")
struct AgentEventWorkspaceClientTests {
  @Test func eachEventCommandLoadsTheProfileCredentialAndUsesV2IPC() throws {
    let profileID = UUID(uuidString: "00000000-0000-4000-8000-000000000601")!
    let recorder = EventWorkspaceClientRecorder()
    let client = AgentWorkspaceClient(
      profileID: profileID,
      loadCredential: { _ in recorder.nextCredential() },
      send: { request in
        recorder.record(request)
        return .capabilities(
          summary: AgentCapabilitySummary(grantRevision: 1, availableCapabilities: [])
        )
      }
    )
    let commands = [
      #"{"listEvents":{}}"#,
      #"{"prepareEventSubscription":{"request":{"event":"note.updated","scope":{"note_id":"00000000-0000-4000-8000-000000000602"},"callbackURL":"https://example.test/hook","signingSecret":"whsec_\#(Data(repeating: 0x61, count: 24).base64EncodedString())","ttl":{"default":{}}}}}"#,
      #"{"removeEventSubscription":{"request":{"event":"note.updated","scope":{"note_id":"00000000-0000-4000-8000-000000000602"},"callbackURL":"https://example.test/hook"}}}"#,
    ]

    for json in commands {
      let command = try? JSONDecoder().decode(AgentWorkspaceCommand.self, from: Data(json.utf8))
      #expect(command != nil)
      guard let command else { continue }
      _ = try client.execute(command)
    }

    let requests = recorder.requests()
    #expect(recorder.credentialCount() == 3)
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { $0.profileID == profileID && $0.protocolVersion == 2 })
    #expect(Set(requests.map(\.credentialBase64)).count == 3)
  }
}

private final class EventWorkspaceClientRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var counter = 0
  private var recordedRequests: [AgentWireRequest] = []

  func nextCredential() -> String {
    lock.withLock {
      counter += 1
      return "credential-\(counter)"
    }
  }

  func record(_ request: AgentWireRequest) {
    lock.withLock { recordedRequests.append(request) }
  }

  func credentialCount() -> Int {
    lock.withLock { counter }
  }

  func requests() -> [AgentWireRequest] {
    lock.withLock { recordedRequests }
  }
}
