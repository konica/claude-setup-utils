---
name: setup-python-venv
description: Use when running, installing, or adding Python packages for any project in this sandbox, when creating a virtual environment, or when a venv fails with "failed to symlink ... Operation not permitted (os error 1)" on a /c/... mounted path.
---

# Python venvs in this sandbox

Project directories live on a mounted drive (`/c/...`) that refuses symlink
creation. Any venv created inside the project fails:

```
error: failed to symlink file from /usr/bin/python3.14 to
/c/.../project/.venv/bin/python: Operation not permitted (os error 1)
```

Home (`/home/agent`) allows symlinks. So: **the venv always lives at
`~/.venvs/<project-name>`, never in the project.**

## Rules

1. **`uv` is the only Python package manager.** `uv add`, `uv sync`,
   `uv run`, `uv lock`. Never `pip install`, `python -m venv`, `poetry`,
   `conda`, or `virtualenv` for a project's dependencies.
2. **Never create `.venv` in the project.** It fails, and a half-created
   `.venv/` left behind confuses later runs — delete it if you find one.
3. **Prefix `UV_PROJECT_ENVIRONMENT` on every uv command.** Each Bash call
   is a fresh shell, so `export` does not survive to the next command.
4. **Never set `UV_PROJECT_ENVIRONMENT` globally** (shell profile,
   `/etc/sandbox-persistent.sh`). It holds one value and would silently
   point every other project at the wrong venv.

## Quick reference

`<name>` = `[project].name` from `pyproject.toml`, else the project
directory's basename.

```bash
V="$HOME/.venvs/<name>"

uv init                              # only if no pyproject.toml yet
UV_PROJECT_ENVIRONMENT="$V" uv sync              # create/update the venv
UV_PROJECT_ENVIRONMENT="$V" uv add requests      # runtime dependency
UV_PROJECT_ENVIRONMENT="$V" uv add --group dev pytest
UV_PROJECT_ENVIRONMENT="$V" uv run pytest        # run anything
```

`uv sync` creates `~/.venvs/<name>` on first use — no `mkdir` needed. Let
`uv add` edit `pyproject.toml` and `uv.lock`; never hand-edit the lock.

## Verify

```bash
UV_PROJECT_ENVIRONMENT="$HOME/.venvs/<name>" \
  uv run python -c "import sys; print(sys.prefix)"
```

Must print `/home/agent/.venvs/<name>`. Anything under the project path
means the prefix was dropped.

## VS Code (only if the project has `.vscode/`)

Set `python.defaultInterpreterPath` in `.vscode/settings.json` to
`${userHome}/.venvs/<name>/bin/python` so the editor and `uv run` agree.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| `failed to symlink ... os error 1` | prefix omitted, so uv targeted `./.venv` | re-run with `UV_PROJECT_ENVIRONMENT` |
| `sys.prefix` is the project dir | same | delete the stray `.venv/`, re-run |
| Second command lands in the wrong venv | relied on `export` persisting | prefix every command |
| `ModuleNotFoundError` after `pip install` | installed outside the uv venv | `uv add <pkg>`, then `uv sync` |
