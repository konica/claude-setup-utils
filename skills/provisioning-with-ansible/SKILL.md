---
name: provisioning-with-ansible
description: Use when installing any system-level package, runtime, or CLI tool to get a project's dev environment working — anything outside what's already declared in the Dockerfile, docker-compose.yml, a Python venv/requirements file, or package.json.
---

# Provisioning with Ansible

## Overview

Dockerfiles, docker-compose, and language dependency files (venv/requirements.txt, package.json) capture *in-container* or *in-language* dependencies. Host-level tools a developer's machine needs — a CLI, a system package, a language runtime like Node.js — fall outside all of those. When you install one, write it into the repo's Ansible playbook so the next person (or agent) can reproduce your environment with one command instead of hunting through chat history or a stale README note.

## When to use

- About to run `apt-get install`, `brew install`, `apk add`, an installer script, `nvm install`, or similar to fix a dev-environment error.
- The tool isn't already declared in this repo's Dockerfile / docker-compose.yml / requirements.txt / pyproject.toml / package.json.
- Symptoms: "`X: command not found`", "you'll also need Y to run the dev server", "the setup script needs Z first".

**Not for:** anything the project's existing Dockerfile, docker-compose, venv, or package manager lockfile can already install — add it there instead of duplicating it in Ansible.

## The rule

Installing the tool and moving on isn't enough — a missing command reappears in the next clone or the next contributor's machine. Writing a README sentence isn't enough either — a note doesn't get re-run. As the same change that fixes the immediate error, add or update a task in the repo's Ansible playbook that installs the tool.

| Excuse | Reality |
|---|---|
| "Quick fix, no need for process" | A task takes two minutes; the alternative is the next person hitting the identical error. |
| "I'll note it in the README" | Notes aren't executed. The environment still doesn't reproduce the tool. |
| "There's no `ansible/` directory yet" | Create it — see layout below. Absence isn't permission to skip. |

## Playbook layout

```
ansible/
  playbook.yml      # single playbook, hosts: localhost, connection: local
```

One file, a flat `tasks:` list, one task (or small group) per tool with a comment naming what needs it. Don't introduce `roles/` or inventory files for a single-host dev setup — that's for multi-host production provisioning, not this.

```yaml
- name: Provision local dev environment
  hosts: localhost
  connection: local
  become: true
  tasks:
    - name: Install graphviz (needed by the ERD export script)
      ansible.builtin.package:
        name: graphviz
        state: present
```

If the project already has a different `ansible/` structure, follow that instead of imposing this one.

A fleshed-out starter covering every row below — including the Python one —
lives at `template/ansible/playbook.yml`. Copy it to `ansible/playbook.yml` in
the target project and edit from there.

## Quick reference

| Need | Module | Notes |
|---|---|---|
| OS package (apt/dnf/apk/brew) | `ansible.builtin.package` | Cross-distro; drop to `apt`/`homebrew` directly only for options `package` lacks (PPAs, etc.) |
| Add a repo/PPA first | `ansible.builtin.apt_repository` | Task before the package task |
| Download a binary/installer | `ansible.builtin.get_url` + `file` mode | Pin a version/URL — don't `curl \| sh` |
| Node/npm global tool | `community.general.npm` | `global: true` |
| One-off command | `ansible.builtin.command` / `shell` | Always add `creates:` or a `when:` guard — without one it reruns every time |
| Python CLI tool / project venv | `community.general.pipx` (install the tool) + `command: uv sync` (`creates:` the venv's python) | Never `pip install` a global tool. Inside the Claude Code sandbox, see the setup-python-venv skill — the venv path there is `~/.venvs/<project>`, not in-project |

## How to run it

```bash
ansible-playbook ansible/playbook.yml --ask-become-pass
```

Ansible itself is the one exception to "declare everything" — install it however is normal for the OS, since it's the tool that installs everything else.

## Common mistakes

- **Installing and moving on** without touching `ansible/playbook.yml` — do it as the same change, not a follow-up.
- **Writing prose instead of a task** — a README line documents the requirement but doesn't reproduce it.
- **Non-idempotent shell tasks** — a bare `shell: install.sh` reinstalls on every run. Use `package`/`get_url`/`creates:` so a second run is a no-op.
- **Duplicating what Docker/venv already covers** — if `pip`/`npm`/the Dockerfile can install it, it belongs there, not in Ansible.
