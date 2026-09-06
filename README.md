# claude-setup

Reproduces a Claude Code plugin/agent setup on a fresh machine: 3 plugin
marketplaces, 15 enabled plugins, one hand-written user-level agent
(`application-architect`), and two kinds of user-level skill — portable ones
that install anywhere, and sandbox-only ones.

## Prerequisites

`dispatch-issues.sh` and `triage-lint.sh` need `git`, `gh` (authenticated),
and `jq` on PATH; `bootstrap.sh`/`.ps1` need `git` and an already-installed
`claude` CLI. Reproduce the first three with:

```bash
ansible-playbook ansible/playbook.yml --ask-become-pass
```

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

Both scripts install the same marketplaces, plugins, agent, and portable
skills. Safe to re-run — every step is a no-op if already satisfied, and skill
installs overwrite in place rather than nesting.

## Portable skills

`skills/` also holds skills that work on any machine Claude Code runs on:

- `dispatching-github-issues` — works a GitHub backlog with coding agents. It
  reads the issues at run time and derives the order from each ticket's
  `Depends on #N` line, then gives every dispatchable ticket its own worktree,
  branch, and attachable background session (`claude attach <id>`) so you can
  steer the work; `--land` turns a finished session into a pushed branch and a
  PR. Needs `gh` (authenticated), `git`, `jq`, and `claude` on PATH. The
  dispatcher is a bash script, so on a Windows host run it from Git Bash or
  WSL.
- `provisioning-with-ansible` — prompts writing/updating an `ansible/`
  playbook whenever a host-level package, runtime, or CLI tool is installed
  to get a project's dev environment working (anything outside its
  Dockerfile, docker-compose.yml, venv/requirements, or package.json), so the
  install is reproducible instead of a one-off command or a stale README
  note.

Both `bootstrap.sh` and `bootstrap.ps1` install these unconditionally, into
`~/.claude/skills/`. To add another, drop it in `skills/<name>/` and add the
name to `PORTABLE_SKILLS` in `bootstrap.sh` and `$PortableSkills` in
`bootstrap.ps1`.

## Sandbox-only skills

The rest of `skills/` is specific to the Claude Code sandbox VM:

- `setup-python-venv` — keeps Python venvs at `~/.venvs/<project>`, because the
  `/c/...` virtiofs mounts reject symlink creation and any in-project `.venv`
  fails to build.
- `remote-debug-python` — attaches VS Code on the host to a `debugpy` listener
  in the sandbox, via `sbx ports ... --publish`.

`bootstrap.sh` installs these into `~/.claude/skills/` **only when it detects
the sandbox** (`IS_SANDBOX=1`, or `/etc/sandbox-persistent.sh` present); on a
host it prints a skip line and installs nothing. Override the detection with
`FORCE_SANDBOX=1` or `FORCE_SANDBOX=0`.

`bootstrap.ps1` never installs them: it targets the Windows host, where the
Linux sandbox paths those skills encode would be wrong advice.

## What this does NOT cover

- Project-level custom skills (e.g. `.claude/skills/` in a specific repo) —
  those travel with `git clone` of that repo, as long as they're committed.
- Cosmetic `settings.json` keys (model, theme, statusline, etc.).

See `docs/superpowers/specs/2026-08-06-claude-setup-bootstrap-design.md` for
the full design rationale.
