---
name: setup-npm-packages
description: Use when running `npm install` (or `npm run <script>`) in any Node.js/npm project in this sandbox, or when it fails with "EPERM: operation not permitted, symlink ... node_modules/.bin/...", is extremely slow, or fails with "ENOENT: no such file or directory, uv_cwd", on a /c/... mounted path.
---

# npm installs in this sandbox

Project directories can live on a bind-mounted filesystem (`/c/...`, a
Windows-hosted volume mounted into this Linux sandbox) that refuses to
create filesystem symlinks. npm normally symlinks every dependency's CLI
into `node_modules/.bin/`, so `npm install` fails outright:

```
npm ERR! code EPERM
npm ERR! syscall symlink
npm ERR! Error: EPERM: operation not permitted, symlink '../eslint/bin/eslint.js' -> '.../node_modules/.bin/eslint'
```

## Rules

1. **Disable bin-link symlinks, don't fight them.** Add an `.npmrc` next
   to `package.json`:
   ```
   bin-links=false
   ```
   npm then skips `node_modules/.bin/*` entirely — nothing there to hit
   EPERM.
2. **Stop relying on `.bin` in `package.json` scripts.** A script that
   calls a devDependency by bare name (`"next dev"`, `"eslint ."`)
   resolved that name through `node_modules/.bin/`, which no longer
   exists. Rewrite each one to run the tool's real entry file with
   `node` directly:
   ```json
   "dev": "node node_modules/next/dist/bin/next dev",
   "lint": "node node_modules/eslint/bin/eslint.js ."
   ```
   Find the entry file from the package's own `bin` field:
   ```bash
   node -p "require('eslint/package.json').bin"   # { eslint: './bin/eslint.js' }
   ```
   A plain string `bin` (instead of an object) *is* the path itself.
3. **This only stops npm's own `.bin` symlinking** — not a dependency's
   install/postinstall script making its own symlinks, and not pnpm or
   Yarn PnP, which symlink far more than `.bin`. If a project can't
   switch to plain npm, use Rule 4 instead.
4. **Unusably slow installs, or `ENOENT ... uv_cwd`, mean
   `node_modules` is fighting the mount, not just the symlinks.**
   Install and run from a copy of the project on non-mounted storage
   (e.g. `$HOME`) instead — same fix in spirit as this sandbox's Python
   venvs living outside the project (`setup-python-venv`). A stale
   `uv_cwd` handle alone often clears just by `cd`-ing out and back in
   (or a fresh shell) before retrying.

## Quick reference

```bash
cd <project>
printf 'bin-links=false\n' >> .npmrc   # once per project
npm install                            # no more EPERM on node_modules/.bin
```
Then apply Rule 2 to any script naming a devDependency's CLI directly.

## Verify

```bash
find node_modules -type l   # nothing printed = zero symlinks anywhere
npm run <script>            # still runs cleanly
```

## Common mistakes

| Symptom | Fix |
|---|---|
| `npm run dev` (etc.) says command not found after adding `bin-links=false` | script still calls the bare name — apply Rule 2 |
| Install takes many minutes / seems to hang | install from a copy on non-mounted storage (Rule 4) |
| pnpm/Yarn PnP install still fails after `bin-links=false` | those symlink far more than `.bin` — switch to npm, or use Rule 4 |
