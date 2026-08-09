# claude-setup

Reproduces a Claude Code plugin/agent setup on a fresh sandbox: 3 plugin
marketplaces, 15 enabled plugins, and one hand-written user-level agent
(`application-architect`).

## Usage

macOS / Linux:

```bash
git clone <this-repo> claude-setup
cd claude-setup
./bootstrap.sh
```

Windows (PowerShell):

```powershell
git clone <this-repo> claude-setup
cd claude-setup
# If scripts are blocked, allow this one for the current process only:
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\bootstrap.ps1
```

Both scripts do the same thing. Safe to re-run — every step is a no-op if
already satisfied.

## What this does NOT cover

- Project-level custom skills (e.g. `.claude/skills/` in a specific repo) —
  those travel with `git clone` of that repo, as long as they're committed.
- Cosmetic `settings.json` keys (model, theme, statusline, etc.).

See `docs/superpowers/specs/2026-08-06-claude-setup-bootstrap-design.md` for
the full design rationale.
