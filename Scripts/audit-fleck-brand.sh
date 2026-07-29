#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

legacy_brand='mo''tes'
migration_marker="${legacy_brand}-to-fleck-v1"
legacy_module='MenuBar''Notes'
allowed_files='^(Sources/FleckCore/FleckProductMigration\.swift|Sources/FleckApp/AgentBridgeInstaller\.swift|Sources/FleckApp/AgentCredentialSecurity\.swift|Sources/FleckApp/EnhancedModelManager\.swift|Sources/FleckAgentBridge/BridgeCredentialStore\.swift|Tests/FleckCoreTests/FleckProductMigrationTests\.swift|Tests/FleckAppTests/AgentBridgeInstallerTests\.swift|Tests/FleckAppTests/AgentProfileStoreTests\.swift|Tests/FleckAppTests/AgentTaskHandleCodecTests\.swift|Tests/FleckAppTests/EnhancedModelManagerTests\.swift|Tests/FleckAgentBridgeTests/BridgeCredentialStoreTests\.swift)$'
failures=0

while IFS=: read -r file line_number content; do
  if [[ "$file" =~ ^docs/superpowers/(specs|plans)/ ]]; then
    continue
  fi
  if [[ "$file" =~ $allowed_files ]] \
    && {
      printf '%s\n' "$content" | grep -Eiq 'legacy|compatibility' \
        || [[ "$content" == *"$migration_marker"* ]]
    }; then
    continue
  fi
  printf 'Legacy product identity: %s:%s:%s\n' "$file" "$line_number" "$content" >&2
  failures=1
done < <(
  git grep -n -i "$legacy_brand" -- \
    ':!docs/superpowers/specs/**' \
    ':!docs/superpowers/plans/**' \
    ':!.superpowers/**' \
    ':!Package.resolved' \
    ':!**/Package.resolved' || true
)

while IFS=: read -r file line_number content; do
  if [[ "$file" == "Sources/FleckCore/FleckProductMigration.swift" ]] \
    && [[ "$content" == *"legacyDirectoryName = \"$legacy_module\""* ]]; then
    continue
  fi
  printf 'Legacy module identity: %s:%s:%s\n' "$file" "$line_number" "$content" >&2
  failures=1
done < <(
  git grep -n "$legacy_module" -- \
    ':!docs/superpowers/specs/**' \
    ':!docs/superpowers/plans/**' \
    ':!.superpowers/**' || true
)

exit "$failures"
