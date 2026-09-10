# Activate the verified Fleck MCP candidate

## Short plan
1. Verify the candidate, current app and configured connector; retain rollback copies.
2. Activate the existing candidate and update the canonical connector with Fleck's guarded installer, preserving the profile and Codex configuration.
3. Verify a fresh connection through that exact configuration, compare tool contracts and logo bytes, and record the remaining client refresh/visual check.

## Result
The verified 1a5025e candidate is running from `.build/shortcut-batch-reopen/Fleck.app`. Its executable SHA-256 is `0a945c0270b8f409658659af67908afc28e11c93e90c150b109971fe18c5552d`; the installed connector exactly matches the bundled helper at `8ece8bf52c38665ee29c87f0f02006d9bb6cd7fdb42d9fa671135f09ea56bac9`. Strict signature verification passed.

The existing Settings screen offers only Refresh Status for a receipt-valid installed helper and does not detect the newer bundled helper. Activation therefore used a disposable driver invoking the unchanged production `AgentBridgeInstaller.install()` transaction, including its ownership checks, rollback and receipt handling. No profile reprovisioning, token rotation, product rebuild or source change occurred. The candidate's absent version key correctly resolves to the existing `development` fallback. This Settings upgrade-discovery gap remains a separate follow-up.

Parent verification used Codex's existing command and profile from `/tmp`: before was 13 tools with zero icons; after is 13 tools with exact canonical PNG icons. Every non-icon tool field is unchanged; the real Fleck project-note read passed and the helper exited successfully. Codex configuration is byte-identical. The current task's existing MCP connection also still reads successfully.

Existing Codex task helper processes were preserved because their individual task ownership is ambiguous. No reconnect API is exposed by the available tools or installed `codex mcp` commands, and Computer Use explicitly denies Codex access. The fresh configured-client check passed; current-task metadata refresh and actual light/dark rendering are not claimed. Restart Codex before repeating the visual check so its helper connections load the installed binary.

Evidence and exact rollback manifests: `.build/evidence/activate-mcp/`. The previous app remains at `.build/parakeet-test/Fleck.app`. Fresh independent Sol operational review returned ship for activation, installer integrity and protocol evidence. No GitHub publication.
