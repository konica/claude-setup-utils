---
name: dispatching-github-issues
description: Use when a GitHub backlog should be worked by coding agents rather than by hand — handing tickets to agents, working several issues at once, steering an agent that is mid-ticket, or working out which tickets can proceed in parallel right now.
---

# Dispatching GitHub Issues

## Overview

One ticket, one agent, one worktree, one branch, one PR. `dispatch-issues.sh`
(next to this file) reads the backlog from GitHub at run time and derives the
order from the tickets themselves, so no issue number is ever written down and
tickets added later are picked up on the next run.

**One invocation dispatches one wave, and stops.** A wave is every ticket that
is unblocked right now; they all run in parallel. A ticket whose blocker has
not been **merged into the trunk** is not in this wave. Merge the wave's PRs,
then run it again for the next one — there is no automatic wave 2.

Each ticket gets its **own attachable session**, named `issue-<n>-<slug>`, so
you can watch an agent work and steer it toward a goal the ticket doesn't spell
out. Each session opens its own PR when it finishes.

## When to use

- Several specified tickets are waiting and a human would work them one by one.
- Someone asks to "dispatch the tickets" or "run the backlog in parallel".
- You need to know which tickets *could* proceed in parallel right now.

**Not for:** a single ticket (just work it); tickets too vague to hand off
(triage first).

Requires `gh` (authenticated), `git`, `jq`, `claude`. Run it from inside the
target checkout.

## The loop

`$SKILL` is this skill's directory.

```bash
bash "$SKILL/dispatch-issues.sh" --dry-run   # 1. read this wave's plan first
bash "$SKILL/dispatch-issues.sh"             # 2. launch a session per ticket
claude attach <id>                           # 3. steer any of them, any time
bash "$SKILL/dispatch-issues.sh" --status    # 4. who is working; their PRs
#                                              5. review and MERGE those PRs
bash "$SKILL/dispatch-issues.sh"             # 6. again, for the next wave
```

Step 2 prints the attach command for every session it started. Sessions stay
alive after finishing a turn, so you can attach, redirect, and let the agent
keep going. Each pushes its branch and opens its own PR when done; `--land` is
only the fallback for one that didn't.

Step 5 is a human's job and the script will not do it. Until those PRs are on
the trunk, the tickets they block are not dispatchable, and step 6 will say so.

| Flag | Use |
| --- | --- |
| `-n, --dry-run` | print this wave's plan, change nothing |
| `--status` | each dispatched ticket: session, state, commits, PR |
| `--land` | fallback: push + PR for a session that didn't; refuses ones mid-turn |
| `-j, --jobs N` | how many tickets run in parallel in the wave (default 3) |
| `-l, --label L` | restrict to triaged tickets, e.g. `ready-for-agent` |
| `--worktree-root D` | worktrees on a local filesystem (see Mistakes) |
| `--mode print` | headless agents instead: run to completion, land, still one wave |
| `--stack` | don't wait for merges; stack dependents on blocker branches |
| `--dep-words RE` | phrases introducing a blocker, if the tracker differs |

`--help` for the rest; `reference.md` for the full guide.

## How the ordering works

Dispatchable = **open**, has any labels you asked for, **unassigned**, **no
branch yet**, **every blocker landed**. Blockers come from the issue body
(`Depends on #3, #4`, `Blocked by: #3`) and from GitHub's native dependencies;
both are held to the same rule.

A blocker has **landed** when its issue is closed, its PR is merged, or its
branch is already an ancestor of the trunk. A branch that merely carries
commits does not count — that is the change: wave 2 is written against code
that survived review, not against a branch someone may still rewrite.

Since no blocker can land while the script runs, one invocation is always
exactly one wave. Everything else is listed as waiting and left alone.

`--stack` restores the old rule (blocker clears on first commit, dependents
branch off `agent/issue-<blocker>`, PRs merge bottom-up) when you would rather
not wait for review.

A dispatchable ticket has one deliverable, names its tests, declares blockers
on a `Depends on #N` line, and says what to do when an assumption fails ("if X
fails, stop and report"). Without that, agents guess.

## Common mistakes

| Mistake | What happens |
| --- | --- |
| Skipping `--dry-run` | You learn the graph was wrong after 12 agents ran |
| Dispatching untriaged tickets | Agents invent the spec; use `--label` |
| Expecting a second wave to go out on its own | It won't. Merge this wave's PRs, then run the script again |
| Re-running before merging | Correct and harmless: it reports the same tickets still waiting, and dispatches nothing |
| Worktrees on a mounted path (`/c/...`, network shares) | Agents hit `fatal: Unable to read current working directory`; pass `--worktree-root "$HOME/dispatch-worktrees"`. The script probes and warns |
| `--force` on assigned tickets | You dispatch on top of a human's work |
| Judging a ticket without reading its session | An agent that stopped and reported is a useful result, not a failure |

`--status` reports `working`, `done`, or `gone` per session, plus its PR state
and URL — merging those is what releases the next wave. After `--land`, a
ticket reads `landed`, `no-changes`, or `still working`. Per-run logs and the
exact prompt sent live in `.dispatch/<timestamp>/`.
