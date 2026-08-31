---
name: remote-debug-python
description: Set up interactive remote debugging for a Python script running in this sandbox, with VS Code on the host attaching via debugpy over a published port. Give it a script path; it handles the sandbox-side steps (ensure debugpy, start the listener) and tells you the host-side steps (publish the port, attach in VS Code), including writing/updating .vscode/launch.json.
---

# Remote-debug a Python script (sandbox↔host)

Sets up interactive debugging for a Python script that runs **in this
sandbox**, using **VS Code on the host** to set breakpoints and step
through it. The two sides don't share a Python interpreter — only a
published network port connects them — so some steps happen in the
sandbox and some happen on the host. This skill performs the sandbox-side
steps and the `launch.json` setup, and tells the user exactly what to run
on the host.

## Input

The Python script to debug (a path), optionally with arguments. If not
given, ask for it.

## Step 1 — Identify how this project runs Python

Check, in order:
- `pyproject.toml` + `uv.lock` present → the project uses `uv`; run
  scripts as `uv run python ...` from the directory containing
  `pyproject.toml`.
- A `.venv`/`venv` directory or `requirements.txt` → assume a plain venv;
  use that venv's `python` (e.g. `.venv/bin/python`).
- Otherwise, ask the user how they normally run this script.

## Step 2 — Ensure `debugpy` is available (sandbox)

Check if `debugpy` is importable in that environment
(`<python> -c "import debugpy"`). If not, install it as a dev dependency
via the project's own package manager (e.g. `uv add --group dev debugpy`,
or `pip install debugpy` inside the venv) — don't install it globally or
outside the project's normal dependency management.

## Step 3 — Pick a port and start the listener (sandbox)

Default to port `5678`. Check nothing is already listening on it
(`ss -tlnp | grep <port>`); if taken, increment or ask the user.

Start the target script under `debugpy`, bound to `0.0.0.0` (not
`127.0.0.1` — it must be reachable via the published port), waiting for
the host to attach before running:

```bash
<python-run-command> -m debugpy --listen 0.0.0.0:<port> --wait-for-client <script> [args]
```

Run this in the background (it blocks until a client connects) and
confirm it's actually listening before moving on.

## Step 4 — Tell the user the host-side step

The user must run this **on their host**, not inside the sandbox (a `!`
prefix in chat still runs inside the sandbox, not on the real host):

```bash
sbx ports <sandbox-name> --publish <port>:<port>
```

Get `<sandbox-name>` from `$SANDBOX_VM_ID` (or `hostname`) inside the
sandbox — never guess it from a branch or directory name.

## Step 5 — Write or update `.vscode/launch.json`

Add (or update, matching by `name` so re-running this doesn't create
duplicates) an attach configuration:

```json
{
    "name": "Attach to sandbox (debugpy :<port>)",
    "type": "debugpy",
    "request": "attach",
    "connect": { "host": "localhost", "port": <port> },
    "pathMappings": [
        { "localRoot": "${workspaceFolder}", "remoteRoot": "<sandbox absolute path to the workspace root>" }
    ],
    "justMyCode": true
}
```

If the sandbox is in "direct mode" (host and sandbox share a live-mounted
filesystem — check `[ -d /run/sandbox/source ]` is *false*), file
contents are identical on both sides, so `pathMappings` only needs to
translate path *syntax* (e.g. `C:\Users\...\project` on the host vs
`/c/Users/.../project` in the sandbox), not sync content. Get the sandbox
absolute path via `pwd` or the project's git root. If it's unclear how
that maps to the host's own path, ask the user rather than guessing — a
wrong mapping silently breaks breakpoint binding.

## Step 6 — Hand off to the host

Tell the user: open the Run & Debug panel in VS Code on the host, select
`"Attach to sandbox (debugpy :<port>)"`, and start it. The script resumes
once it attaches — set breakpoints before or immediately after.

To debug a different script afterward, repeat from Step 3 with a new (or
the same) port. The `launch.json` entry only needs to change if the port
changes.
