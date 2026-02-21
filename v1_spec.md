# gh worktreex — v1 Spec

## 1. Overview

**Name (working):** `gh worktreex`

**Goal:** Make `git worktree` actually usable for parallel development by automatically applying pre-settings for environments and dependencies (`venv`, `node_modules`, `.env`, `direnv`, etc.) when creating or managing worktrees.

---

## 2. Problem Statement

Native `git worktree` only shares Git-tracked files between worktrees. Every new worktree is missing the untracked project assets that make it runnable:

| Asset | Node.js | Python |
|---|---|---|
| `node_modules/` | ✗ missing | — |
| `.venv/` / `venv/` | — | ✗ missing |
| `.env` / `.env.local` | ✗ missing | ✗ missing |
| Build caches (`.next/`, `.turbo/`, `dist/`) | ✗ missing | — |
| `__pycache__/`, `.pytest_cache/` | — | ✗ missing |

Result: every new worktree feels **half-broken** until the developer manually reconstructs the full environment. This defeats the purpose of parallel worktrees for fast context switching.

---

## 3. Tech Scope (v1)

| Runtime | Detection signal | Assets managed |
|---|---|---|
| **Node.js** | `package.json` present | `node_modules/`, `.env*`, build caches |
| **Python** | `pyproject.toml`, `requirements*.txt`, or `setup.py` present | `.venv/` / `venv/`, `.env*`, `__pycache__` |

> **Out of scope for v1:** Ruby (Gemfile), Rust (Cargo), Docker-compose, Go modules, Java/Gradle.

---

## 4. Goals & Non-Goals

### Goals (v1)
- Detect project type automatically from the repo root.
- On `worktreex new` / `worktreex pr`: provision the new worktree so it is immediately runnable.
- Support both **copy** and **symlink** strategies, configurable per asset type.
- Copy or symlink `.env*` files so secrets are not re-entered.
- Provide a `worktreex sync` command to re-apply provisioning to an existing worktree.
- Provide a `worktreex status` command to show what each worktree is missing.
- Respect a per-repo config file (`.worktreex.yml`) for overrides.

### Non-Goals (v1)
- Managing remote environment secrets (Vault, AWS SSM, etc.).
- Auto-running arbitrary `postinstall` scripts beyond what is defined in config.
- GUI / TUI interface.
- Windows support (bash-first; WSL2 is acceptable).
- Monorepo workspace orchestration (multiple `package.json` in sub-dirs).

---

## 5. CLI Interface

All commands inherit the flags of the existing `gh worktree` base.

```
gh worktreex <command> [flags]

Commands:
  new     <branch>    Create worktree + provision environment
  pr      <number>    Checkout PR in a worktree + provision environment
  sync    [path]      Re-provision an existing worktree (re-link/copy assets)
  status  [path]      Show provisioning status of one or all worktrees
  list                List worktrees with provisioning state indicator
  rm      <path|branch>  Remove worktree (clean up copies/links)
  clean               Remove worktrees for merged branches

Global flags:
  --strategy <link|copy>   Override default provisioning strategy (default: link)
  --no-provision           Skip provisioning when creating a worktree
  --dry-run                Print what would be done without doing it
  --config <file>          Path to config file (default: .worktreex.yml)
  -v, --verbose            Verbose output
```

### 5.1 `new` — create + provision

```sh
gh worktreex new feature/dark-mode
```

Steps executed:
1. Run `git worktree add -b <branch> <path>` (same naming convention as v0).
2. Detect project type(s) in the source worktree.
3. Run the provisioner for each detected type (see §6).
4. Print a summary of what was linked/copied/installed.

### 5.2 `pr` — PR checkout + provision

```sh
gh worktreex pr 42
```

Same as `new` but fetches the PR branch via `gh pr checkout`.

### 5.3 `sync` — re-provision

```sh
gh worktreex sync                  # current directory
gh worktreex sync ../myrepo-pr-42  # explicit path
```

Idempotent: re-applies provisioning. Useful after:
- Running `npm install` in the source worktree (symlink strategy picks it up automatically; copy strategy re-copies).
- Rotating `.env` values.

### 5.4 `status` — check provisioning state

```sh
gh worktreex status
```

Example output:
```
Worktree                          Type     node_modules  .env   .venv   Build cache
~/projects/myapp                  Node.js  ✔ (source)    ✔      —       ✔
~/projects/myapp-feature-dark     Node.js  ✔ linked      ✔ cp   —       ✗ missing
~/projects/myapp-pr-42            Node.js  ✗ missing     ✗      —       —
```

---

## 6. Provisioning Logic

### 6.1 Strategy: link vs. copy

| Strategy | Mechanism | When to use |
|---|---|---|
| `link` (default) | Symlink the asset directory/file from the source worktree | `node_modules/` — safe to share; instant, no disk cost |
| `copy` | `cp -r` the asset | `.env` — avoids accidental shared mutation; small files |

Default per asset (overridable in `.worktreex.yml`):

| Asset | Default strategy |
|---|---|
| `node_modules/` | `link` |
| `.venv/` | `copy` (venvs contain absolute paths; see §6.3) |
| `.env`, `.env.local`, `.env.development` | `copy` |
| `.next/cache`, `.turbo/` | `link` |
| `dist/`, `build/` | skip (let the user build fresh) |

### 6.2 Node.js Provisioner

**Detection:** `package.json` exists in repo root.

**Steps:**

```
1. Resolve source worktree (main worktree root).
2. If node_modules/ exists in source:
     strategy=link  → ln -s <source>/node_modules <new_wt>/node_modules
     strategy=copy  → cp -r <source>/node_modules <new_wt>/node_modules
   Else:
     warn "node_modules not found in source; run npm install in source first."
     (optionally run npm install in the new worktree if --install flag is set)
3. Copy .env* files (see §6.4).
4. If .next/cache exists and strategy allows: link .next/cache.
5. If .turbo/ exists and strategy allows: link .turbo/.
6. Print summary.
```

**Supported package managers** (auto-detected from lockfile):

| Lockfile | Manager |
|---|---|
| `package-lock.json` | npm |
| `yarn.lock` | yarn |
| `pnpm-lock.yaml` | pnpm |
| `bun.lockb` | bun |

If `--install` flag is passed and no `node_modules/` found in source, run the detected package manager's install command inside the new worktree.

### 6.3 Python Provisioner

**Detection:** any of `pyproject.toml`, `requirements.txt`, `requirements*.txt`, `setup.py`.

**Venv handling (why copy, not link):**
Python virtual environments embed absolute paths in activation scripts and interpreter symlinks. A venv created in `/home/user/myapp` will not work correctly when linked at `/home/user/myapp-feature-foo`. Therefore:

- Default: **recreate** the venv in the new worktree using the same Python version.
- Optional: `--venv-strategy copy` — `cp -r` the venv then run `python -m venv --upgrade-deps <new_wt>/.venv` to fix paths (faster than full reinstall, but fragile).

**Steps:**

```
1. Detect venv location: .venv/ or venv/ in source worktree.
2. Detect Python version from:
     .python-version (pyenv), pyproject.toml [tool.python], runtime.txt, else `python3 --version`.
3. Create fresh venv in new worktree:
     python<version> -m venv <new_wt>/.venv
4. Install dependencies:
     if pyproject.toml + [build-system]: pip install -e ".[dev]"  (PEP 517)
     else if requirements*.txt:         pip install -r requirements.txt (+ requirements-dev.txt if present)
5. Copy .env* files (see §6.4).
6. Print summary.
```

> **Note:** Step 4 (pip install) may be slow. A `--no-install` flag skips it, leaving a bare venv.

### 6.4 .env File Handling

Copied (not linked) by default to prevent accidental shared mutation.

Files matched (glob, repo root only in v1):
```
.env
.env.local
.env.development
.env.development.local
.env.test
.env.test.local
.env.production        ← copied but a warning is printed (prod secrets in worktree)
```

Files **never** touched:
```
.env.example
.env.template
.env.sample
```

If the file does not exist in the source worktree, it is silently skipped (no error).

---

## 7. Configuration File — `.worktreex.yml`

Optional file at the repo root. All keys are optional.

```yaml
# .worktreex.yml

# Override provisioning strategy per asset
strategy:
  node_modules: link       # link | copy | skip
  venv: recreate           # recreate | copy | skip
  env_files: copy          # copy | link | skip
  build_cache: link        # link | copy | skip

# Extra directories/files to link or copy
extra:
  - path: .secrets/dev.json
    strategy: copy
  - path: data/fixtures/
    strategy: link

# Run these shell commands after provisioning (in the new worktree's root)
hooks:
  post_provision:
    - echo "Worktree ready at $WORKTREEX_PATH"
    - direnv allow .    # example: allow direnv in the new worktree

# Directories whose absence should be treated as warnings, not errors
optional:
  - .turbo
  - .next/cache

# Which .env files to include / exclude (overrides default glob)
env:
  include:
    - .env
    - .env.local
  exclude:
    - .env.production
```

### 7.1 Environment variables available in hooks

| Variable | Value |
|---|---|
| `WORKTREEX_PATH` | Absolute path to the new worktree |
| `WORKTREEX_BRANCH` | Branch name checked out in the new worktree |
| `WORKTREEX_SOURCE` | Absolute path to the source (main) worktree |
| `WORKTREEX_TYPE` | Detected project type(s), comma-separated (`nodejs,python`) |

---

## 8. Edge Cases & Error Handling

| Scenario | Behavior |
|---|---|
| `node_modules/` missing in source, no `--install` | Print warning; skip; continue with other assets |
| Target worktree already has `node_modules/` | Skip (do not overwrite); print info message |
| Symlink target already exists and is a dead link | Remove stale link, re-create |
| `.env` file missing in source | Silently skip |
| Both `package.json` and `pyproject.toml` present | Run both provisioners |
| Python version not found locally | Abort with clear error; suggest `pyenv install <version>` |
| `--dry-run` | Print all actions with `[dry-run]` prefix; take no filesystem action |
| Source worktree is dirty (uncommitted changes) | No impact; provisioning is independent of working tree state |

---

## 9. File Structure (Extension Repo)

```
gh-worktreex/
├── gh-worktreex              ← main entry point (bash)
├── lib/
│   ├── detect.sh             ← project type detection
│   ├── provision_node.sh     ← Node.js provisioner
│   ├── provision_python.sh   ← Python provisioner
│   ├── provision_env.sh      ← .env file handling
│   ├── config.sh             ← .worktreex.yml parser (using yq or awk)
│   └── hooks.sh              ← post_provision hook runner
├── .worktreex.yml.example    ← template config for users to copy
├── README.md
└── v1_spec.md                ← this file
```

---

## 10. Success Criteria (v1 Done)

- [ ] `gh worktreex new <branch>` creates a worktree that can run `npm start` / `python main.py` without manual intervention on a Node.js / Python project.
- [ ] `gh worktreex pr <number>` does the same for a PR checkout.
- [ ] `gh worktreex sync` is idempotent and safe to run multiple times.
- [ ] `gh worktreex status` correctly reports missing vs. linked vs. copied assets.
- [ ] `.worktreex.yml` overrides are respected for strategy and extra paths.
- [ ] `post_provision` hooks are executed with the correct environment variables.
- [ ] `--dry-run` shows exactly what would happen without side effects.
- [ ] Works on macOS and Linux (bash 4+).
- [ ] No external dependencies beyond `git`, `gh`, `python3`, standard coreutils — except `yq` for YAML parsing (optional; falls back to defaults if absent).

---

## 11. Open Questions

1. **Monorepo support:** Should v1 handle repos where `package.json` lives in `packages/*/` rather than root? (Currently: no — deferred to v2.)
2. **pnpm symlinked `node_modules`:** pnpm uses a content-addressable store; linking `node_modules/` may not work correctly. Should we detect pnpm and run `pnpm install --frozen-lockfile` instead?
3. **direnv integration:** Should `direnv allow .` be run automatically or only via `hooks`?
4. **Venv recreation speed:** For large Python projects, venv recreation is slow. Should we support a `--link-venv` escape hatch (unsafe but fast)?
5. **Config file location:** `.worktreex.yml` at repo root vs. `.github/worktreex.yml` to keep root clean?
