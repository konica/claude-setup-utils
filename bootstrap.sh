#!/usr/bin/env bash
# Reproduces this Claude Code setup (marketplaces, plugins, custom agent) on a fresh sandbox.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MARKETPLACES=(
  "anthropics/claude-plugins-official"
  "VoltAgent/awesome-claude-code-subagents"
  "wshobson/agents"
)

PLUGINS=(
  "superpowers@claude-plugins-official"
  "mattpocock-skills@claude-plugins-official"
  "code-review@claude-plugins-official"
  "pr-review-toolkit@claude-plugins-official"
  "frontend-design@claude-plugins-official"
  "voltagent-research@voltagent-subagents"
  "voltagent-biz@voltagent-subagents"
  "voltagent-infra@voltagent-subagents"
  "voltagent-dev-exp@voltagent-subagents"
  "voltagent-core-dev@voltagent-subagents"
  "startup-business-analyst@claude-code-workflows"
  "content-marketing@claude-code-workflows"
  "business-analytics@claude-code-workflows"
  "database-design@claude-code-workflows"
  "comprehensive-review@claude-code-workflows"
)

for repo in "${MARKETPLACES[@]}"; do
  echo "== marketplace: ${repo} =="
  claude plugin marketplace add "${repo}"
done

for plugin in "${PLUGINS[@]}"; do
  echo "== plugin: ${plugin} =="
  claude plugin install "${plugin}"
done

echo "== custom agent: application-architect =="
mkdir -p "${HOME}/.claude/agents"
cp "${SCRIPT_DIR}/agents/application-architect.md" "${HOME}/.claude/agents/application-architect.md"

echo "Done."
