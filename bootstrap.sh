#!/usr/bin/env bash
# Reproduces this Claude Code setup (marketplaces, plugins, custom agent, and
# sandbox-only skills) on a fresh machine.
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

# Skills that work anywhere Claude Code does. They encode no sandbox paths, so
# they install on a host machine too.
PORTABLE_SKILLS=(
  "creating-up-down-scripts"
  "dispatching-github-issues"
  "provisioning-with-ansible"
)

# Skills that only make sense inside the Claude Code sandbox VM: they encode
# sandbox-specific paths (/home/agent/.venvs, the /c/... virtiofs mounts) and
# sandbox<->host tooling (sbx ports, $SANDBOX_VM_ID). Skipped on a host machine.
SANDBOX_SKILLS=(
  "remote-debug-python"
  "setup-python-venv"
)

# FORCE_SANDBOX=1/0 overrides detection (useful for testing both branches).
is_sandbox() {
  if [[ -n "${FORCE_SANDBOX:-}" ]]; then
    [[ "${FORCE_SANDBOX}" == "1" ]]
    return
  fi
  [[ "${IS_SANDBOX:-}" == "1" || -f /etc/sandbox-persistent.sh ]]
}

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

install_skill() {
  local skill=$1
  # Copy contents, not the directory, so re-runs overwrite instead of nesting.
  mkdir -p "${HOME}/.claude/skills/${skill}"
  cp -R "${SCRIPT_DIR}/skills/${skill}/." "${HOME}/.claude/skills/${skill}/"
  # Skills that ship a script are invoked as `bash <script>`, but keep the
  # executable bit so they can also be run directly.
  find "${HOME}/.claude/skills/${skill}" -name '*.sh' -exec chmod +x {} +
}

for skill in "${PORTABLE_SKILLS[@]}"; do
  echo "== skill: ${skill} =="
  install_skill "${skill}"
done

if is_sandbox; then
  for skill in "${SANDBOX_SKILLS[@]}"; do
    echo "== sandbox skill: ${skill} =="
    install_skill "${skill}"
  done
else
  echo "== sandbox skills: skipped (not running in the sandbox) =="
fi

echo "Done."
