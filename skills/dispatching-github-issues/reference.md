# Dispatching tickets

`dispatch-issues.sh` hands open GitHub issues to headless Claude Code
agents — one agent, one worktree, one branch, one PR per ticket — running every
ticket that is unblocked right now at the same time.

**One invocation dispatches one wave, and stops.** A ticket blocked by another
is not dispatched until that blocker's PR is **merged into the trunk**. So the
rhythm is: dispatch a wave, review and merge its PRs, run the script again.
There is no automatic wave 2 — merging is a human decision, and wave 2 is
written against whatever review left on the trunk.

Nothing about the ticket set is baked into the script. It reads the issues from
GitHub on every run, so tickets added after it was written are picked up with
no edit, and no issue number is ever written down anywhere.

Run it from inside the checkout you want the work to happen in. `SKILL` below
stands for this skill's directory.

## What makes a ticket ready

A ticket is dispatchable when all of these hold:

- it is **open**, and carries every `--label` you asked for;
- every one of its **blockers has landed on the trunk**;
- it is **unassigned** (an assignee means a human took it — use `--force` to
  override);
- **no branch exists** for it yet, locally or on `origin`.

Blockers come from two places, and both are held to the same rule:

1. **The issue body** — any line containing `Depends on #3, #4` or
   `Blocked by: #3`, up to the sentence's end. The recognised phrases default to
   `depends on|blocked by|requires|needs` and are configurable with
   `--dep-words`, since trackers word this differently.
2. **GitHub's native issue dependencies**, when set. Turn this off with
   `--no-native-deps`.

A blocker has **landed** when its issue is closed, or its PR is merged, or its
branch is already an ancestor of the trunk. The PR is checked first because
GitHub deletes the branch on merge, and a deleted branch is an ancestor of
nothing. Nothing else clears a blocker — a branch that merely carries commits
does not, which is the whole point: the code wave 2 builds on is the code that
survived review.

Because a blocker cannot land while the script is running, one invocation
dispatches exactly one wave. Everything still blocked is listed under
"Later waves" and left alone.

## Two modes

**Session mode (the default)** gives each ticket an attachable Claude Code
session, named `issue-<n>-<slug>` so a wave is readable in `claude agents`: the
script prepares the worktree, launches `claude --bg` inside it, prints the
`claude attach <id>` command, and exits. The agents keep working while you
watch or steer any of them, and **each one pushes its branch and opens its own
PR** when it is done. `--land` is the fallback for a session that did not.

`--status` shows what each session is doing (`working`, `done`, `gone`), how
many commits its branch carries, and the state and URL of its PR — which is
what you need, since merging those PRs is what releases the next wave. `--land`
refuses a session that is mid-turn, so it is safe to run at any time; a ticket
that already has a PR is left alone because `gh pr view` finds it.

**Print mode** (`--mode print`) is the headless alternative: each agent runs to
completion with no session to attach to, and its work is landed as soon as it
finishes. It dispatches one wave too, and stops.

## How parallelism works

Every ticket that is ready goes out at once, `--jobs` of them running at a
time (default 3). They are independent by construction — a ticket with an
unmerged blocker is not in this wave — so they never share a branch and never
need to be merged into one another. Each branches from the trunk, and each PR
targets the trunk.

When the wave is done: review its PRs, merge them, run the script again. The
tickets those PRs were blocking become ready at that point, and not before.

### `--stack`, for when you cannot wait

`--stack` restores the older, faster, riskier rule: a blocker clears as soon as
its **branch carries commits**, and the dependent ticket is branched from
`agent/issue-<blocker>` rather than the trunk, with its PR targeting that
branch. You get the whole graph dispatched in far fewer rounds, and a stack of
PRs that must be merged bottom-up — but wave 2 is then written against code
that review has not seen. With several blockers the first is the base and the
rest are merged in; a merge conflict fails that ticket rather than guessing.

Check the shape of a run before committing to it:

```bash
"$SKILL/dispatch-issues.sh" --dry-run
```

## Running it

```bash
# Every unblocked ticket, three agents at a time
"$SKILL/dispatch-issues.sh" --jobs 3

# Only tickets your triage marks as agent-ready
"$SKILL/dispatch-issues.sh" --label ready-for-agent

# Specific tickets
"$SKILL/dispatch-issues.sh" 41 42
```

`--help` lists every flag. The ones that matter most:

| Flag                 | Why                                                       |
| -------------------- | --------------------------------------------------------- |
| `-j, --jobs N`       | concurrent agents (default 3)                              |
| `-n, --dry-run`      | print this wave's plan, change nothing                     |
| `--stack`            | don't wait for a merge; stack dependents on blockers       |
| `-m, --model NAME`   | model for the agents                                       |
| `--timeout SECS`     | kill an agent that won't finish                            |
| `--no-agent-pr`      | agents only commit; `--land` opens the PRs                 |
| `--no-pr`            | push branches, skip pull requests                          |
| `--no-push`          | keep everything local (implies `--no-pr`)                  |
| `--agent-cmd CMD`    | print mode only: run CMD instead of `claude`               |
| `--mode MODE`        | `session` (default, attachable) or `print` (headless)      |
| `--status`           | session, state, commits and PR per dispatched ticket       |
| `--land`             | fallback: push and open the PR a session did not           |
| `-r, --repo O/N`     | target repository, when `gh` cannot infer it               |
| `--dep-words RE`     | phrases that introduce a blocker in an issue body          |
| `--worktree-root D`  | put worktrees somewhere other than the repo                |

## What each agent gets

A prompt whose first line is `issue-<n>: <title>`, followed by the issue body
and a working agreement: read whatever agent instructions the repository
carries (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, a `docs/` guide),
implement only this ticket, write and run the tests the ticket names, commit on
the branch, then **push it and open its own PR** against the trunk with a
`Closes #<n>` body. Agents are told not to merge, not to switch branches, and
not to touch another ticket's branch — a human merges the PR, and that merge is
what releases the tickets waiting on it. They are also told to stop and report
rather than guess when a ticket is under-specified, which is what a ticket that
gates other work needs them to do.

The session is named `issue-<n>-<slug>` explicitly, so `claude agents` reads as
the wave; the first prompt line is the fallback name.

With `--no-agent-pr` the agent stops at the commit and `--land` publishes, which
is the old contract.

Override the template with `--prompt-file`; placeholders are `{{NUMBER}}`,
`{{TITLE}}`, `{{BODY}}`, `{{BRANCH}}`, `{{BASE}}`, `{{REPO}}`, and
`{{PUBLISH}}` for the push-and-PR clause.

## After a ticket

Agents open their own PRs. Landing (either `--land`, or automatically at the
end of a print-mode ticket) is the safety net: it commits anything the agent
left uncommitted, pushes `agent/issue-<n>`, opens the `Closes #<n>` PR if there
isn't one already, and comments the PR link on the issue. The issue is assigned
to you when the ticket is first dispatched, which is also what stops a second
run from dispatching it twice.

Tickets still waiting on a blocker show as `NEXT WAVE` in the print-mode
summary. That is the expected state, not a failure, and it does not affect the
exit code — merge this wave and run the script again.

Everything lands under `.dispatch/<timestamp>/`: `logs/issue-<n>.log` has the
full agent transcript, `prompts/issue-<n>.md` the exact prompt sent. The
directory is gitignored. Worktrees stay at
`.claude/worktrees/dispatch/issue-<n>` in the target repo unless you pass
`--cleanup`.

The exit code is 0 when every ticket dispatched in this wave succeeded.
Tickets held back for a later wave do not make it non-zero.

## Known environment quirk: worktrees on a mounted filesystem

On some mounted paths (a `/c/...` host mount in a sandbox, network shares), a
process that writes a file
into its own working directory can no longer read that directory back:
`getcwd()` fails and git reports

```
fatal: Unable to read current working directory
```

Agents run `write a file, then git add` constantly, so this matters. The script
probes the worktree root at startup and warns when it lands on such a
filesystem. The fix is to put the worktrees on a local path:

```bash
"$SKILL/dispatch-issues.sh" --worktree-root "$HOME/dispatch-worktrees"
```

The dispatcher's own git calls are unaffected — they all use `git -C <path>`,
which never consults the working directory.
