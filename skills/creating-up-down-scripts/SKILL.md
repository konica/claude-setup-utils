---
name: creating-up-down-scripts
description: Use when starting an app locally takes several commands across multiple directories or terminals, when a README's dev setup is a hand-followed checklist, when onboarding a developer means "run these six things in order", or when asked for a one-command way to start and stop a project.
---

# Creating up/down scripts

## Overview

A developer should start any app the same way in every repo: `./up`. And stop it
with `./down`. Everything else — which package manager, which ports, how many
processes, whether Postgres is a container — is the script's problem, not theirs.

**The test:** a new developer clones the repo and runs one command. If they must
read the README to get the app serving, the scripts aren't done.

## When to use

- Dev setup spans more than one command, directory, or terminal
- The README has a numbered "Running in dev" section
- Onboarding repeatedly hits the same trap (a `.env` that nothing loads, a
  migration nobody ran, a container left running from yesterday)
- Someone asks for "a script to start everything"

**Not for:** a genuinely single-command app (`npm run dev` and nothing else) —
adding `./up` on top is a wrapper that earns nothing. And not for production
deploys; these scripts are local-only and may cut corners production can't.

**Related:** the `run` skill launches an app ad hoc to check a change. This skill
creates the durable entrypoints a repo keeps.

## The contract

Write exactly two executable files. They are the whole interface.

**`./up`**
1. Checks prerequisites and fails naming the missing thing *and* its fix.
2. Starts everything: containers, migrations, every process.
3. Is idempotent — safe to run twice, or when half the stack is already up.
4. Blocks until the app actually answers, then exits 0.
5. Prints the URLs and where the logs are. Nothing else to memorise.

**`./down`**
1. Stops exactly what `up` started.
2. Preserves data by default. Destroys volumes only under an explicit
   `--clean` flag.
3. Succeeds when nothing is running.

If `up` needs an argument to do the normal thing, it isn't done.

## Non-negotiables

**Derive at run time; never hardcode.** Container names come from
`docker compose ps -q`, not typed in. Ports come from the env or the compose
file. A script with a service name baked in breaks the moment someone renames
something, and silently.

**Wait for readiness, never `sleep`.** Poll the real health endpoint until it
answers, with a timeout. A fixed `sleep 5` is either a slow lie or a fast one.
`docker compose up -d --wait` already does this for containers with healthchecks.

**Track process groups, not wrapper PIDs; never `pkill -f`.** `npm`, `uv run`,
`yarn` and `poetry run` exec or exit, so the pid you captured is a corpse while
the server it launched keeps serving — `up` then starts a duplicate and `down`
leaves it behind. Start with `setsid` and record the process group id, then
signal the group. Pattern-killing takes down the developer's other work.

**Trust your process, not the port.** Before accepting that a service is ready,
check *your* process is still alive. Otherwise a server from another project on
the same port satisfies the health check and `up` exits 0 announcing an app that
never started. Check liveness *before* the URL, every iteration.

**Probe both loopback stacks.** Dev servers bind inconsistently — in one real
project the API was IPv4-only and the web server IPv6-only. A probe of only
`127.0.0.1` reports "free" for a port that is taken, and the conflict surfaces
later as a lie instead of an error.

**Bind where the client is, not loopback.** Dev servers default to `127.0.0.1`,
which is correct only while the browser runs on the same machine. When it does
not — a container, a VM, WSL, a remote dev box, a sandbox — the request arrives
on an external interface and a loopback socket accepts nothing there. The
failure is silent and expensive: the port forward reports success, `curl
localhost` *from inside* returns 200, the page never loads, and nothing in the
output points at the binding. Derive the address from the environment rather
than hardcoding either answer:

```sh
# Substitute whatever marker identifies your remote environment; inside a
# Claude Code sandbox it is SANDBOX_VM_ID.
: "${BIND_HOST:=${SANDBOX_VM_ID:+0.0.0.0}}"   # client elsewhere → all interfaces
: "${BIND_HOST:=127.0.0.1}"                   # client local     → off the LAN
```

An explicit `BIND_HOST` still wins, and on a plain laptop nothing changes. Pass
it to *every* server the script starts — `uvicorn --host`, `vite --host`,
`next dev --hostname`, `rails s -b` — not just the one you happened to test.

Binding is only half of it; the forward is the other. That is a command on the
*other* machine, which the script cannot run, so print the exact one (in a
Claude Code sandbox: `sbx ports <id> --publish 5173:5173/tcp`). Keep the port
number identical on both sides — origin and base-URL settings are built from
those numbers, so remapping them breaks CORS and the API base URL.

**Load config the app won't.** If the app reads only `os.environ`, `up` sources
`.env` itself. This trap costs an hour every time.

**Fail loudly, early, actionably.** `missing env: DATABASE_URL — set it in .env
(see .env.example)` beats a stack trace from inside a worker.

**Add no new tooling.** POSIX-ish bash. If the repo already has `make`, `just`,
or npm scripts, add `up`/`down` targets *there* rather than a parallel system.

**A task runner is a front door, not a home.** When someone asks for Make (or
just/npm scripts) where none exists, add it — `make` listing every target is
real discoverability — but have it *delegate* to the scripts. Recipes cannot
hold this logic well: every `$` doubles, each line runs in its own subshell
without `.ONESHELL`, and the multi-line readiness helpers become escaping
puzzles. Make's actual value, the dependency graph, goes unused on phony
targets. One implementation, two front doors. Reject a runner from the wrong
ecosystem outright — Gradle for a Python/TypeScript repo means a JDK, a wrapper
and daemon startup to shell out to `docker compose`.

**Name the command the developer typed.** A footer saying `stop ./down` is wrong
when they ran `make up` from the repo root. `make` exports `MAKELEVEL`, so
branch on it and print `make down` or `./down` accordingly.

**Then delete the instructions.** The README's setup section collapses to
`./up`. Leaving both means they drift, and the stale one wins.

## Quick reference

| Need | Do |
| --- | --- |
| Container readiness | `docker compose up -d --wait` |
| HTTP readiness | poll `curl -fsS "$url"` until timeout |
| DB readiness | the image's own check (`pg_isready`), via compose healthcheck |
| Background process | `nohup … &` + pidfile + logfile under a gitignored state dir |
| Stop one process | `kill "$(cat pidfile)"` after `kill -0` liveness check |
| Port already busy | report the port and say `./down` — don't silently pick another |
| Reachable from another machine | bind `0.0.0.0`, then forward the port from that side |
| Checking that binding | `curl --noproxy '*' "http://$(hostname -I \| awk '{print $1}'):PORT"` |
| Reset the world | `./down --clean` |

## Implementation

Adapt [template-up](template-up) and [template-down](template-down). The helper
functions are the same in every project; only the marked service sections
change. Keep both under ~80 lines — past that, the scripts have become the thing
you need a README for.

State (`pids`, `logs`) lives in one gitignored directory, conventionally `.dev/`.

## Common mistakes

| Mistake | What happens |
| --- | --- |
| `sleep 10` instead of polling | Passes on a fast machine, fails in CI, and nobody knows why |
| Recording the `npm`/`uv run` wrapper's pid | Wrapper exits, pidfile points at a corpse; `up` duplicates the process, `down` orphans it |
| Health check with no liveness check | Another project's server on that port answers; `up` exits 0 and prints a URL for an app that never started |
| Probing only `127.0.0.1` | IPv6-only dev server reads as "port free"; the bind then fails after you already claimed success |
| Leaving servers on loopback when the client is elsewhere | The port forward succeeds and the browser still gets nothing, while everything checked from inside says the app is healthy |
| Binding only the service you tested | The page loads from the other machine, then every API call it makes fails |
| Testing reachability while a proxy is set | `curl` sends the machine's own IP through `$http_proxy` and hangs — indistinguishable from a binding failure, so a working setup reads as broken. Use `--noproxy '*'` |
| `pkill -f uvicorn` | Kills the app the developer was debugging in another window |
| Hardcoded container name | Silently no-ops after a rename; `down` leaves things running |
| `down` removes volumes by default | Someone loses their local data once, then stops trusting `down` |
| `up` that only works from a clean slate | Second run fails on "port in use"; developer reboots instead |
| Exiting 0 before the app answers | Scripts "succeed", the browser shows a connection refused |
| Keeping the README steps too | The two drift; the stale one is followed |
| Reimplementing the logic inside make recipes | Same shell, every `$` doubled, one subshell per line; now two implementations to keep in step |
| Hint that names a path the caller can't use | `stop ./down` after `make up` from the repo root sends them to a file that isn't there |

## Verify before shipping

Do not claim these work until all six pass:

1. `./up` from a clean state → app answers at the printed URL.
2. `./up` **again** → succeeds, does not duplicate processes.
3. `./down` → nothing left; `docker compose ps` empty, no stray PIDs.
4. `./down` again → still exits 0.
5. `./up` after `./down` → app answers again, data still there.
6. If the client is on another machine, **every** service answers on the
   external interface, not just on loopback:
   ```bash
   ip=$(hostname -I | awk '{print $1}')
   curl --noproxy '*' -sS -o /dev/null -w '%{http_code}\n' "http://$ip:$PORT"
   ```
   `--noproxy` is not optional wherever `$http_proxy` is set: without it curl
   routes this machine's own address through the proxy and hangs, so a correct
   setup looks broken. Read the signal — a loopback-bound server refuses in
   ~0 ms, a proxy artefact times out. When in doubt check the binding itself:
   `/proc/net/tcp` shows `00000000` for `0.0.0.0` and `0100007F` for
   `127.0.0.1`.

Run them. Step 2 and step 4 are the ones that actually fail; step 6 is the one
nobody discovers until someone tries to open the app from another machine.
