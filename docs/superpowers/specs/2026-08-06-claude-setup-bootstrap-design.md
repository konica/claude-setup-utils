# claude-setup: reproducing a Claude Code plugin/agent setup on a fresh sandbox

Date: 2026-08-06

## Problem

The Claude Code setup in use (3 plugin marketplaces, 15 enabled plugins, 1
hand-written user-level agent) only exists as local state under `~/.claude/`.
A fresh sandbox starts with none of it. The goal is a way to reproduce that
setup on a new sandbox without hand-editing JSON, and without reaching for a
general-purpose config-management tool (Ansible) for what is actually a
handful of files and CLI calls.

Project-level custom skills (`.claude/skills/` inside `work_sample`) are out
of scope here — they already travel with `git clone` once committed. The
only gap found there (`extract-design-system` being untracked) is fixed
directly in that repo, not through this tooling.

## Approach

Drive the setup entirely through `claude`'s own CLI verbs
(`plugin marketplace add`, `plugin install`) rather than hand-editing
`~/.claude/settings.json`. Those commands are the documented, version-stable
way to register marketplaces and plugins; hand-editing the JSON would depend
on undocumented internal reconciliation behavior.

## Components

- **`bootstrap.sh`** — idempotent, non-interactive. Adds the 3 marketplaces,
  installs the 15 plugins by `plugin@marketplace` id, then copies the
  checked-in custom agent into `~/.claude/agents/`.
- **`agents/application-architect.md`** — verbatim copy of the hand-written
  user-level agent that isn't part of any plugin and would otherwise be lost.
- **`README.md`** — the one-command usage: `git clone <repo> && cd claude-setup && ./bootstrap.sh`.

## Data flow

Fresh sandbox → clone this repo → run `bootstrap.sh` → the `claude` CLI
writes `~/.claude/settings.json` and populates the marketplace/plugin caches
itself → script copies the custom agent file → Claude Code has an identical
plugin/agent setup to the source machine.

## Error handling

`bootstrap.sh` runs under `set -euo pipefail`: any failed `marketplace add`
or `install` call aborts the script with a visible non-zero exit rather than
continuing silently. Because every step is a no-op when already satisfied,
re-running the whole script after fixing a problem is always safe — there is
no partial-state cleanup to reason about.

## Testing

The script is verified by running it on a machine that already has the
target state installed (this sandbox): every `marketplace add` and
`install` call should be a no-op and the script should exit 0. That proves
the command syntax is correct against the real, currently-installed CLI
version, which is the only thing worth verifying for a script this size —
there's no separate test harness.

## Explicit non-goals

- Cosmetic `settings.json` keys (`model`, `theme`, `statusLine`, `tui`,
  `defaultMode`, permission-bypass flags) are not reproduced. They weren't
  part of the original ask ("plugins, skills, agents") and can be added to
  `bootstrap.sh` later the same way if wanted.
- `work_sample`'s `.claude/settings.local.json` permission allowlist is not
  reproduced — it reads as local debugging scratch, not a durable setup
  decision.
- Not pushed to GitHub; this repo is local-only for now, per request.
