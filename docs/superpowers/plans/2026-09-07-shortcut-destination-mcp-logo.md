# Shortcut, destination clarity, and Fleck MCP logo

Status, 8 September: Packets 1–3 accepted locally at f76b109, f20af54 and c9e642b with fresh Sol ship reviews; original verification passed 334 combined tests plus 47 availability tests. After Keychain access was allowed, the c9e642b relocated helper authenticated and exposed exact canonical icons with unchanged contracts on all four profile-visible tools. Native follow-up exposed a retained-menu drop-handler lifecycle defect. Corrective commit 1a5025e removes one premature detach and bounds two existing source checks to the FolderNavigator declaration; 51 parent drag tests pass. Official enhanced packaging passed from clean detached 1a5025e with arm64, strict signatures, exact relocation bytes and no model weights. Corrected candidate: .build/shortcut-batch-reopen/Fleck.app. Actual native menu-first → pin → close → same-menu reopen/release now passes, including a second saved before/after replay; pinned drag also passes, preserving selection and all nine fixture identities. Fresh corrective Sol review returned ship for exact commit 1a5025e, package evidence and native replay. After Keychain approval, the exact corrected relocated helper completed authenticated tools/list and a disposable note read from /tmp (exit 0). All four profile-visible tools retain every non-icon field and embed the exact canonical PNG. The Keychain/authentication gate is closed. Actual Codex rendering remains unverified because Computer Use denied app access. The accepted running app remains separate and unchanged. Evidence: .build/evidence/shortcut-destination-mcp/final-package-and-qa.md. Short logo design: ../specs/2026-09-07-fleck-mcp-logo-design.md.
Requested batch: shortcut discovery/permission recovery, destination clarity, custom Fleck logo in the external MCP client. Cleanup quality was not reported as a problem and is excluded. Broader onboarding education is deferred.

## Grounding and scope

Inspected accepted local candidate `15159fb` on `codex/activity-toolbar-sizing` in `/Users/harryjin/Fleck/.worktrees/editor-three-bug-fixes` and the task **Add Fleck logo to MCP** (`01a07c57-73e2-7fa1-8b53-06d11d7e9ca2`). That task investigated metadata and made no implementation claim. The friend's exact build remains unknown.

Existing behavior:
- Right Option is the default configurable modifier. Hold and double-tap gestures already exist.
- SettingsView has Enable Input Monitoring, and DictationRuntime.recoverModifierMonitoring returns a direct privacy-pane action if retry remains unauthorized. Onboarding currently advances after a permission attempt; this batch does not redesign that flow.
- Focused-editor capture inserts into the editor. Smart Capture routes and safely falls back to Inbox. A saved-capture chooser already exists for ambiguity, but ordinary Inbox fallback does not get that chooser.
- The idle capsule has no visible shortcut text and announces “Fleck dictation ready” even though that generic wording does not establish modifier permission readiness.
- Fleck registers a bare MCP server. The common Tool factory supplies no icons. The pinned SDK supports Tool.icons and Server.Info.icons, but Server.init does not expose server icons; do not assume setting server metadata is a one-line supported API.

Prefer improvements in the existing dictation entry points and saved-result UI over a new onboarding tour, new window, mode settings, or router rewrite. Use native controls, readable labels, light/dark appearance, keyboard access and restrained status transitions. Preserve the accepted drag, Activity and toolbar behavior.

## Batch execution and ownership

At implementation start, inspect AGENTS.md, current branch/status, remote ancestry and concurrent tasks. Preserve the accepted local candidate; do not replace it with an older main or silently integrate unrelated work. Prepare a focused branch whose base includes the accepted candidate. No push, PR, merge, model installation or client configuration replacement is authorized by this plan.

Keep the active Codex-native subagent lane. Before each packet, provide its worker the five-part specification: objective/success, exact ownership, required changes/non-goals, commands/evidence, authority/handoff. Use the active permitted implementer configuration; no Terra. Workers are not alone in the repository and must preserve concurrent edits. Packets 1 and 2 share runtime/capsule files, so run sequentially. Keep packet 3 sequential too for a single easy-to-audit batch. Parent verifies each diff and obtains a fresh Sol High ship verdict before dependent work. Corrections return to the same worker. Use focused local commits, not a PR per commit.

## Packet 1 — discoverable shortcut and direct permission recovery

Objective: a user can find the configured dictation key and reach Input Monitoring without searching Settings.

Proposed UI:
- Add a compact, accessible dictation status/help row adjacent to the existing microphone entry in menu and pinned Notes hosts. Ready copy: “Hold Right Option to dictate,” using the actual configured modifier. Secondary help can explain double-tap hands-free; it must not replace the primary hold instruction.
- Missing-permission copy: “Enable Input Monitoring to use Right Option.” Primary button: “Open Input Monitoring.” Detail: “Turn on Fleck, then return here.” Keep the microphone entry available when its own permissions permit it.
- The button uses existing monitoring recovery to request/register access, then opens the existing privacy-pane URL if access remains unavailable. Reuse monitoring/recovery state; avoid a separate permission state machine. Recheck on application activation and show readiness only after monitoring actually runs. Distinguish permission denial from monitor-start failure; the latter gets Retry.
- Do not open System Settings automatically at startup, on a failed invisible keypress, or repeatedly after denial. Do not advertise the global key as ready when it cannot be received.
- Update the capsule accessibility readiness copy from the same state. Keep the idle pill compact; the visible instruction belongs in the Notes host, not a permanently expanded pill.

Owned paths: Sources/FleckApp/NotesPanel.swift, FleckApp.swift, DictationSettingsPresentation.swift, DictationCapsule.swift; Tests/FleckAppTests/DictationSettingsTests.swift, DictationAvailabilityTests.swift, GlobalHoldShortcutTests.swift. Add a focused presentation test file only if these existing suites lack the right home. Expand ownership explicitly if tracing locates the actual toolbar renderer elsewhere; no speculative edits.

Steps:
1. Write failing behavioral tests for unauthorized, failed, running and configured-key changes; verify denial never becomes Ready and the direct action targets Privacy_ListenEvent.
2. Run the focused tests and record the intended failure.
3. Implement the shared presentation/action wiring using existing recovery and activation refresh.
4. Rerun focused tests; exercise menu and pinned hosts at narrow/wide widths, keyboard activation, denied permission and return-from-Settings refresh. Verify the physical modifier on a consented test setup; do not reset the user's TCC database.
5. Parent diff check, fresh review and focused local commit.

Command: `swift test --no-parallel --filter 'DictationSettings|DictationAvailability|GlobalHoldShortcut'`. Require a nonzero completed count. A mocked permission result does not establish actual macOS permission recovery.

## Packet 2 — clear destination and useful Inbox fallback

Objective: users understand how to dictate into an existing note and can explicitly place a fallback capture without repeating it.

Proposed UI and behavior:
- Beside the same dictation entry, explain “Click in this note to dictate here.” Once capture starts, show the actual captured context: “Dictating into <note>” for focused capture, or “Smart Capture” for global capture. Bind this to the capture snapshot, not whatever note becomes selected later.
- Smart Capture help: “Say a specific note title to help Fleck choose. If it cannot find a clear match, it saves to Inbox.” Use a distinctive example such as Travel plans. Do not imply generic titles always route or that cleanup controls the destination.
- On normal Inbox fallback, show “Saved to Inbox” with “No clear destination” and an explicit Choose note action. Reuse the existing receipt-backed correction flow to move only this saved capture. Offer active writable notes, including generic-title notes for explicit selection; automatic routing eligibility must not filter manual choices.
- Preserve the existing ambiguity suggestions. Include Keep in Inbox; dismissed choice leaves the successful save intact. If the existing menu would become unwieldy, use an existing searchable note picker if available; do not build a new picker framework.
- Show folder context for duplicate titles, exclude Trash/deleted targets, and revalidate note identity at selection. Reject stale capture actions, duplicate clicks and unsafe edits to the saved source. Preserve existing atomic rollback, cancellation and history behavior.
- Do not generalize this to automatic rerouting, every past capture, transcript rewriting, or changed routing confidence thresholds. An already resolved non-Inbox capture keeps its current behavior in this batch.

Owned paths: Sources/FleckApp/NotesPanel.swift, FleckApp.swift, DictationCapsule.swift, DictationCoordinator.swift; Tests/FleckAppTests/DictationCoordinatorTests.swift, DictationCapsuleVisualCaptureTests.swift and affected existing presentation tests. Preflight ownership extension: DictationInterfaces.swift and AppState.swift may add optional presentation-only folder context to active destination candidates, without changing semantic context or routing eligibility; AppStateDictationTests.swift may verify this real candidate context. No speech engine, cleaner, Vocabulary, model selection, or routing algorithm changes.

Steps:
1. Trace chooseDestination and saved receipt validation before extending fallback eligibility. Write red tests for normal Inbox fallback offering manual choice, focused capture bypassing routing, and exact destination snapshot across focus changes.
2. Add tests for explicit generic-title destination, duplicate titles with folder context, deleted note, altered source receipt, repeated click, stale capture, cancellation and Keep in Inbox. Assert one insertion and no loss/duplication.
3. Extend the existing saved-capture chooser lifecycle minimally. Do not weaken receipt checks to make a test pass.
4. Run `swift test --no-parallel --filter 'DictationCoordinator|DictationCapsule|DictationSettings|GlobalHoldShortcut|AppStateDictation'` and inspect completed counts. The existing AppState receipt tests cover real source edits, repeated moves and atomic rollback.
5. Native fixture: click editor then dictate; global capture without a clear destination; choose an existing note; verify the original capture moves exactly once and result/history name the correct note. Exercise unavailable routing and duplicate/generic titles. Capture real-microphone proof separately from injected transcript tests.
6. Parent verification, fresh ship review and local commit.

## Packet 3 — Fleck logo in MCP integrations

Objective: advertise the existing custom Fleck mark to MCP clients and verify it in the exact Codex tool-call surface requested by the user. This is external integration branding, not the in-app MCP Activity indicator.

Approach:
- Reuse `website/public/fleck-mark.png`; inspect it before preparing a compact PNG derivative. Preserve its identity. Check small-size legibility against light and dark backgrounds.
- Add a single shared metadata value through the existing common Tool factory using MCP-native `icons`, image/png and correct dimensions. Prefer a compact embedded PNG data URI so the bridge works offline and from any directory, without fetching a website or relying on a developer path.
- Keep the asset representation small and deterministic. A checked-in compact encoded constant avoids a new SwiftPM bridge resource bundle and packaging changes; if a bundled resource is chosen instead, explicitly include its bundle in every bridge packaging/install path and test relocation. Select the smaller reliable option after measuring the existing mark.
- Do not patch dependency checkout files or replace protocol initialize handlers just to add serverInfo.icons. Tool icons are supported by the current SDK. Server-level icons are only added if a supported public API is established without dependency migration.
- Preserve tool names, schemas, annotations, capability filtering, credentials, profile IDs and stdio framing. No decorative image blocks in tool results.

Owned paths: Sources/FleckAgentBridge/FleckMCPToolRegistry.swift; optional new Sources/FleckAgentBridge/FleckMCPBranding.swift; Tests/FleckAgentBridgeTests/FleckMCPToolRegistryTests.swift and FleckMCPServerTests.swift. Existing canonical mark is read-only. Package.swift/build scripts enter ownership only if the reviewed resource approach requires them.

Steps:
1. Red test: all advertised tools carry the same valid PNG icon; decode the data and verify nonempty valid image/dimensions. Compare tools before/after to ensure all non-icon contract fields remain unchanged for each capability profile.
2. Add minimal icon metadata; test tools/list serialization and ordinary tool invocation with an older/icon-ignoring client path.
3. Run `swift test --no-parallel --filter 'FleckMCPToolRegistry|FleckMCPServer'` and `swift build --product fleck-agent`.
4. Verify packaged helper output from a relocated app, independent of source cwd. Connect a disposable profile and inspect the raw tools/list response.
5. Refresh/reconnect the client, then make a read-only Fleck call and inspect the exact Codex row in light/dark appearance. Coordinate any Codex restart so it does not interrupt active tasks. Metadata success is not visual success.
6. If Codex ignores MCP-native icons, report that result. The separate task suggested a plugin wrapper as a fallback, but that is a separate scope decision: do not silently install a plugin, duplicate the server or replace the user's configuration. The logo remains visually unaccepted until the target client actually displays it.
7. Parent verification, fresh review and local commit; record protocol and client results separately.

Protocol reference: https://modelcontextprotocol.io/specification/2025-11-25/schema — Tool and Implementation have optional icons; rendering is client-dependent. The local pinned Swift SDK confirms Icon and Tool support. No guarantee is made about a specific Codex activity row.

## Final batch verification and handoff

- Run the combined affected tests once after integration and check `git diff --check`.
- Build the enhanced package through `bash scripts/build-parakeet-test-app.sh`; preserve any running candidate before replacement. Verify exact app/helper paths, arm64 architecture, strict signatures and model-weight exclusion.
- Exercise real menu/pinned UI, keyboard permissions, focused/global destinations and MCP branding using disposable notes/profile. Smoke-check accepted Activity dismissal, compact toolbar and tab dragging.
- Require fresh final Sol ship review of the complete diff and evidence. A client that ignores icons or an untested physical permission flow remains an explicit unresolved acceptance item.
- Update the Fleck note through MCP at each meaningful checkpoint: these three current priorities first, then completed work, then the broad backlog. Keep cleanup pipeline notes as reference, not a reported defect in this batch.
- Deliver one local tested candidate with focused commits. External publication remains unapproved. The user has authorized implementation of all three packets; proceed sequentially through their verification and review gates.
