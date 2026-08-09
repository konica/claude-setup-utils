# Reproduces this Claude Code setup (marketplaces, plugins, custom agent) on a fresh Windows sandbox.
#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$Marketplaces = @(
  'anthropics/claude-plugins-official'
  'VoltAgent/awesome-claude-code-subagents'
  'wshobson/agents'
)

$Plugins = @(
  'superpowers@claude-plugins-official'
  'mattpocock-skills@claude-plugins-official'
  'code-review@claude-plugins-official'
  'pr-review-toolkit@claude-plugins-official'
  'frontend-design@claude-plugins-official'
  'voltagent-research@voltagent-subagents'
  'voltagent-biz@voltagent-subagents'
  'voltagent-infra@voltagent-subagents'
  'voltagent-dev-exp@voltagent-subagents'
  'voltagent-core-dev@voltagent-subagents'
  'startup-business-analyst@claude-code-workflows'
  'content-marketing@claude-code-workflows'
  'business-analytics@claude-code-workflows'
  'database-design@claude-code-workflows'
  'comprehensive-review@claude-code-workflows'
)

# Resolve the claude CLI (claude.cmd / claude.exe on Windows).
$Claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $Claude) {
  Write-Error "claude CLI not found on PATH. Install Claude Code first: https://docs.claude.com/claude-code"
  exit 1
}

foreach ($repo in $Marketplaces) {
  Write-Host "== marketplace: $repo =="
  & claude plugin marketplace add $repo
  if ($LASTEXITCODE -ne 0) { throw "Failed to add marketplace: $repo" }
}

foreach ($plugin in $Plugins) {
  Write-Host "== plugin: $plugin =="
  & claude plugin install $plugin
  if ($LASTEXITCODE -ne 0) { throw "Failed to install plugin: $plugin" }
}

Write-Host "== custom agent: application-architect =="
$AgentsDir = Join-Path $env:USERPROFILE '.claude\agents'
New-Item -ItemType Directory -Force -Path $AgentsDir | Out-Null
Copy-Item -Path (Join-Path $ScriptDir 'agents\application-architect.md') `
          -Destination (Join-Path $AgentsDir 'application-architect.md') -Force

Write-Host "Done."
