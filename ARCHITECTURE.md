# Fleck architecture

Fleck is a native Swift package whose ordinary app remains useful without an
account, cloud service, model download, or browser runtime. The architecture
keeps portable note state separate from macOS presentation and narrows every
optional integration at an explicit boundary.

## Design constraints

- **Native and simple:** use AppKit, SwiftUI, Foundation, and the macOS text
  system before adding a dependency or replacing platform behavior.
- **Local-first:** ordinary notes and settings live in the user's Application
  Support directory. Core note use has no server dependency.
- **Truthful persistence:** mutations become visible through one state owner and
  are saved with atomic replacement and recovery data.
- **Bounded integration:** dictation and agent access fail closed or fall back to
  a safe local result rather than broadening access.
- **Accessible and efficient:** keyboard use, VoiceOver, Reduce Motion, contrast,
  idle CPU, memory pressure, and thermal state are architectural inputs.

## Package boundaries

| Target | Responsibility |
| --- | --- |
| `FleckCore` | Note and workspace models, mutations, Markdown operations, preferences, persistence, recovery, import/export, dictation history, and agent activity. |
| `FleckAgentProtocol` | Versioned request/response types, endpoint conventions, and framed local IPC. |
| `FleckApp` | macOS lifecycle, menu-bar and pinned-window scenes, AppKit editor, onboarding, settings, dictation, and the in-app agent service. |
| `FleckAgentBridge` | Separately packaged `fleck-agent` MCP/CLI process, Keychain credential lookup, and Unix-socket client. |
| `FleckModelEvaluation` / `FleckModelEvaluator` | Deterministic evaluation records and a command-line evaluator for local-model candidates. |
| `FleckCaptureLab` | Developer tooling for controlled visual capture; it is not part of the core note path. |

`FleckCore` has no UI dependency. `FleckAgentProtocol` depends on core value
types. The app and bridge meet across the protocol rather than importing each
other.

## Application composition

```text
MenuBarExtra / pinned window / Settings
                  |
            AppState + services
         /          |           \
 native editor   LocalStore   dictation runtime
                                  |
                        on-device speech/cleanup

local MCP client or CLI
          |
     fleck-agent
          |
 private same-user Unix socket
          |
 capability authority -> AppState mutation -> LocalStore
```

`AppState` owns the live workspace and coordinates saves, recovery, Trash,
transfer, search, file references, and agent mutations. SwiftUI presents the app
shell, while the editor wraps a real `NSTextView` so selection, input methods,
undo, spelling, and accessibility continue to use the macOS text system.

## Storage boundary

Fleck stores readable Markdown note bodies, optional RTF sidecars, and JSON
workspace and preference data under the user's Application Support directory.
`LocalStore` serializes access, debounces normal saves, uses atomic replacement,
and retains a previous-generation snapshot for recovery.

This design improves inspectability and crash recovery; it is not encryption.
Software already running as the same macOS user can operate within that user's
authority. Secrets used by the Agent Connector belong in Keychain, not note
files or preferences.

## Dictation boundary

The ordinary path is:

```text
global hold shortcut or focused editor
  -> Apple on-device speech recognition
  -> personal-dictionary resolution
  -> optional bounded cleanup
  -> focused insertion or Smart Capture routing
  -> AppState save + local history
```

Standard speech requires Apple's on-device recognition and has no cloud
fallback. On macOS 26, the ordinary graph can use the system Foundation Models
runtime for cleanup and routing when it is available. Cleanup is checked against
the captured text; unavailable or rejected cleanup keeps the safer text. An
unknown or ambiguous Smart Capture destination saves to Inbox.

The Enhanced Local graph is compile-time isolated. Setting
`FLECK_ENHANCED_CANDIDATE=1` adds the candidate package and enables
`CLEAN_DICTATION_ENHANCED_CANDIDATE` only for debug builds and tests. Candidate
Parakeet speech, Gemma cleanup/routing, model manifests, installation state, and
resource residency therefore cannot silently enter an ordinary release build.
These paths are experimental and have separate legal, model-integrity,
performance, and distribution gates.

Audio buffers are transient. Dictation history stores text and outcome metadata,
not recorded audio. Test and diagnostic evidence must use synthetic content and
must be sanitized before it leaves the test machine.

## Agent workspace boundary

The Agent Connector is off until a user creates a profile and grants
capabilities. Profiles can receive `notes.list`, `notes.read`, `notes.write`, and
`changes.undo`, plus explicit note grants or an explicitly confirmed folder
grant that may include future notes.

The bridge exposes a static registry of 13 MCP tools, filtered for every request
by the profile's current capabilities. Mutations carry expected revisions and
caller-owned operation IDs so stale or uncertain writes do not silently
overwrite newer work or duplicate an operation. Activity and eligible Undo
records return through the same state owner.

Communication uses a private `AF_UNIX` socket with same-user peer checks; there
is no HTTP listener, cloud relay, or internet-facing port. Credentials are held
in Keychain. Unknown, private, and unauthorized targets intentionally share a
safe absence response so callers cannot use errors to enumerate notes.

This is a cooperative local-client boundary. It limits accidental or
over-broad access by configured clients, but it cannot defend against malicious
software already executing as the same user.

## Dependencies and optional graphs

The ordinary package pins the Model Context Protocol Swift SDK. Its transitive
Swift packages are recorded in `Package.resolved`. The Enhanced candidate adds a
separate local package and reviewed pins only when explicitly selected.

Keep dependency additions rare. A new dependency must have a concrete runtime
or maintenance benefit, compatible licensing, a reviewed immutable resolution,
and no unnecessary effect on the ordinary app's size, network behavior, or idle
resources.

Current delivery state and next gates belong in
[Implementation status](IMPLEMENTATION_STATUS.md), not in this architecture
document. Test commands and evidence expectations belong in
[Testing](TESTING.md).
