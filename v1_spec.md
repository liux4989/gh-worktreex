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

### Why auto-detection is not enough

An approach that auto-detects project type on every `worktree add` has a critical flaw: **it cannot know the developer's intent**. The same repo may have multiple sub-projects with different runtimes, different package managers, different venv strategies, and different env-file policies. Heuristics diverge across monorepos, nested workspaces, and mixed stacks.

**The config file is the single source of truth.** Run `init` once; every subsequent `worktree add` reads the config and does exactly what was declared — no guessing, no false-positives.

---

## 3. Tech Scope (v1)

| Runtime | Config key | Assets managed |
|---|---|---|
| **Node.js** | `node` | `node_modules/`, `.env*`, build caches |
| **Python** | `python` | `.venv/`, `.env*` |
| **direnv** | `direnv` | `.envrc` templating + `direnv allow` |

> **Out of scope for v1:** Ruby (Gemfile), Rust (Cargo), Go modules, Java/Gradle, Docker-compose.
> **Monorepo support** is a first-class v1 concern via the `projects[]` array (see §7).

---

## 4. Goals & Non-Goals

### Goals (v1)
- **One-time setup via `init`**: scan the repo, scaffold `.worktreex.yml`, let the user declare intent once.
- **Config as single source of truth**: provisioners read only the config; no scattered detection on every `worktree add`.
- **Monorepo-aware**: `projects[]` lets each sub-project declare its own node/python/dotenv strategy.
- On `worktreex new` / `worktreex pr`: provision every declared project so the worktree is immediately runnable.
- `worktreex sync` to re-apply provisioning to an existing worktree (idempotent).
- `worktreex status` to show per-project provisioning state across all worktrees.
- direnv integration: write `.envrc` from a template and run `direnv allow`.

### Non-Goals (v1)
- Managing remote environment secrets (Vault, AWS SSM, etc.).
- GUI / TUI interface.
- Windows support (bash-first; WSL2 acceptable).
- Auto-detection of project type without `init` having been run first.

---

## 5. CLI Interface

```
gh worktreex <command> [flags]

Commands:
  init                 Scaffold .worktreex.yml in the main worktree (run once)
  new   <branch>       Create worktree + provision all declared projects
  pr    <number>       Checkout PR in a worktree + provision all declared projects
  sync  [path]         Re-provision an existing worktree from config
  status               Show per-project provisioning state across all worktrees
  list                 List worktrees with provisioning summary
  rm    <path|branch>  Remove worktree and clean up copies/links
  clean                Remove worktrees for merged branches

Global flags:
  --no-provision       Skip provisioning when creating a worktree
  --dry-run            Print what would be done; take no filesystem action
  --config <file>      Path to config (default: <repo-root>/.worktreex.yml)
  -v, --verbose        Verbose output
```

---

### 5.1 `init` — scaffold config (run once per repo)

```sh
gh worktreex init
gh worktreex init --yes   # accept all suggested defaults non-interactively
```

**Purpose:** Create `.worktreex.yml` in the main worktree root. This is the only command that touches project-structure detection; all other commands read the resulting config.

**Steps executed:**

```
1. Abort if .worktreex.yml already exists (unless --force).
2. Scan repo for signals to suggest project entries:
     package.json / pnpm-workspace.yaml  → suggest node project(s)
     pyproject.toml / requirements*.txt  → suggest python project(s)
     .envrc / direnv installed           → suggest direnv block
3. For each detected signal, prompt the user:
     - Project root (relative path)
     - Node mode: symlink_modules | per_worktree
     - Package manager (auto-detected from lockfile, confirmable)
     - Python mode: shared_venv | per_worktree
     - Dotenv mode: copy_example | copy | shared_parent | skip
4. Ask for repo-wide defaults (base_worktree, direnv template).
5. Write .worktreex.yml.
6. Print next steps:
     "Run 'gh worktreex new <branch>' to create your first provisioned worktree."
```

**Flags:**

| Flag | Description |
|---|---|
| `--yes` | Accept all detected defaults without prompting |
| `--force` | Overwrite existing `.worktreex.yml` |

> After `init`, **commit `.worktreex.yml`** to the repo so all team members share the same provisioning config.

---

### 5.2 `new` — create + provision

```sh
gh worktreex new feature/dark-mode
```

Steps executed:
1. Load and validate `.worktreex.yml` (abort with clear error if missing — suggest `init`).
2. Run `git worktree add -b <branch> <path>`.
3. For each entry in `projects[]`, run its declared provisioner (see §6).
4. If `direnv.enabled`, write `.envrc` from template and run `direnv allow <path>`.
5. Run `hooks.post_provision` commands.
6. Print per-project provisioning summary.

### 5.3 `pr` — PR checkout + provision

```sh
gh worktreex pr 42
```

Same as `new` but fetches the PR branch via `gh pr checkout`. Worktree placed at `../myrepo-pr-42`.

### 5.4 `sync` — re-provision

```sh
gh worktreex sync                  # re-provision current directory
gh worktreex sync ../myrepo-pr-42  # explicit worktree path
```

Idempotent. Useful after:
- Running `pnpm install` in the base worktree (symlink mode picks it up automatically; `per_worktree` mode re-runs install).
- Rotating `.env` values.
- Changing the config and wanting existing worktrees to reflect updates.

### 5.5 `status` — provisioning state

```sh
gh worktreex status
```

Example output:
```
Worktree: ~/projects/myapp  (base)
  web   [apps/web]    node_modules ✔ source   .env ✔ source
  api   [apps/api]    .venv        ✔ source   .env ✔ source

Worktree: ~/projects/myapp-feature-dark
  web   [apps/web]    node_modules ✔ linked   .env ✔ copied
  api   [apps/api]    .venv        ✔ shared   .env ✔ shared_parent

Worktree: ~/projects/myapp-pr-42
  web   [apps/web]    node_modules ✗ missing  .env ✗ missing
  api   [apps/api]    .venv        ✔ shared   .env ✔ shared_parent
```

---

## 6. Provisioning Logic

All provisioners receive their parameters **exclusively from the parsed config**. There is no runtime detection of project type; the user declared everything during `init`.

### 6.1 Node.js Provisioner

Triggered when a project entry contains a `node:` block.

#### Modes

| Mode | Mechanism | Trade-offs |
|---|---|---|
| `symlink_modules` | `ln -s <base_wt>/<root>/node_modules <new_wt>/<root>/node_modules` | Instant, zero disk cost; all worktrees share the same install. **Not recommended for pnpm.** |
| `per_worktree` | Run `install_cmd` inside the new worktree's project root | Fully isolated. Fast for pnpm (hardlinks from store); slower for npm/yarn. |

**`symlink_modules` steps:**
```
1. Resolve base worktree path from config (default_base → branch → fs path).
2. Check <base>/<root>/node_modules exists; warn if absent.
3. If <new_wt>/<root>/node_modules already exists:
     - Correct symlink to target → skip (already done).
     - Stale or dead symlink, or plain directory → remove and re-link.
4. ln -s <base>/<root>/node_modules <new_wt>/<root>/node_modules
```

**`per_worktree` steps:**
```
1. cd <new_wt>/<root>
2. Run install_cmd (e.g. "pnpm install --frozen-lockfile")
```

> **pnpm default — `per_worktree` with `--frozen-lockfile`:**
> pnpm maintains a global content-addressable store (`~/.pnpm-store`) and hardlinks package files into each `node_modules/`. Running `pnpm install --frozen-lockfile` in a new worktree is therefore nearly instant (no network, no re-extraction) and produces a fully isolated, correct `node_modules/` with its own virtual store (`.pnpm/`) scoped to that worktree. Symlinking pnpm's `node_modules/` across worktrees is **unsafe**: the virtual store (`.pnpm/`) contains worktree-relative symlinks that break when the path changes. `init` automatically sets `mode: per_worktree` and `install_cmd: pnpm install --frozen-lockfile` whenever `pnpm-lock.yaml` is detected.

#### Build cache

If `build_cache` key is present under a project's `node:` block, the named directories are symlinked from the base worktree. Built-in default: `[".next/cache", ".turbo"]`. Silently skipped if a directory is absent in the base.

---

### 6.2 Python Provisioner

Triggered when a project entry contains a `python:` block.

#### Modes

| Mode | Mechanism | Trade-offs |
|---|---|---|
| `shared_venv` | All worktrees use a single venv at a stable `path` outside the repo | Instant; dep changes in one branch affect all worktrees |
| `per_worktree` | Create a fresh venv at `<new_wt>/<root>/.venv` and install deps | Fully isolated; slow (pip install on every new worktree) |

**`shared_venv` steps:**
```
1. If <path> (~/.venvs/myproj-api) does not exist:
     python3 -m venv <path>
     <path>/bin/pip install -r <base>/<root>/<requirements>
2. Create convenience symlink: <new_wt>/<root>/.venv → <path>
3. Optionally inject venv activation into .envrc (if direnv enabled).
```

**`per_worktree` steps:**
```
1. Detect Python version:
     .python-version (pyenv) → pyproject.toml [tool.python] → python3 --version
2. python<ver> -m venv <new_wt>/<root>/.venv
3. <new_wt>/<root>/.venv/bin/pip install -r <requirements>
   or: pip install -e ".[dev]"  (if pyproject.toml with [build-system])
```

> **Why not symlink the venv?** Venvs embed absolute paths in activation scripts and interpreter symlinks. A venv at `/repo/.venv` breaks when linked to `/repo-branch/.venv`. `shared_venv` avoids this by keeping the venv at a stable external path (`~/.venvs/`).

---

### 6.3 dotenv Provisioner

Triggered when a project entry contains a `dotenv:` block.

#### Modes

| Mode | Mechanism |
|---|---|
| `copy_example` | Copy `example_file` (e.g. `.env.example`) → `<new_wt>/<root>/.env` |
| `copy` | Copy actual `.env` from base worktree into the new worktree |
| `shared_parent` | `ln -s <resolved_shared_path> <new_wt>/<root>/.env` |
| `skip` | Do nothing |

**`copy_example` note:** Destination `.env` is populated with placeholder values. A reminder is printed to fill in real values.

**`shared_parent` note:** `shared_path` supports `~/` and `../` relative to the new worktree's project root. Useful for secrets shared across all worktrees of the same repo.

Files **never** touched (regardless of mode):
```
.env.example    .env.template    .env.sample
```

---

### 6.4 direnv Provisioner

Triggered by a top-level `direnv:` block in the config. Applied repo-wide (not per-project).

**Steps:**
```
1. Check 'direnv' binary is available; warn and skip if not.
2. Write <new_wt>/.envrc from the template string.
   Template variables:
     {{WORKTREE_PATH}}   absolute path of the new worktree
     {{BRANCH}}          branch name
     {{BASE_PATH}}       absolute path of the base worktree
3. direnv allow <new_wt>
```

---

## 7. Configuration File — `.worktreex.yml`

Created by `init`, lives at the **repo root of the main worktree**, committed to version control.

```yaml
version: 1

# Branch name of the base (source) worktree
default_base: main

# ── Repo-wide defaults ────────────────────────────────────────────────────────
env:
  node:
    mode: symlink_modules   # symlink_modules | per_worktree
    base_worktree: main     # which worktree's node_modules to symlink from
    package_manager: pnpm   # npm | yarn | pnpm | bun (auto-detected if omitted)
    install_cmd: pnpm install

direnv:
  enabled: true
  template: |
    layout python ~/.venvs/myproj
    if [ -f ../.env.shared ]; then
      export $(cat ../.env.shared | xargs)
    fi

# ── Per-project declarations ──────────────────────────────────────────────────
projects:
  - name: web
    root: apps/web               # relative to repo root; "." for root-level projects
    node:
      mode: symlink_modules      # inherits repo-wide default if omitted
      install_cmd: pnpm install --filter web
    dotenv:
      mode: copy_example         # copy_example | copy | shared_parent | skip
      example_file: .env.example

  - name: api
    root: apps/api
    python:
      mode: shared_venv          # shared_venv | per_worktree
      path: ~/.venvs/myproj-api  # required when mode is shared_venv
      requirements: requirements.txt
    dotenv:
      mode: shared_parent
      shared_path: ../../../.env.api.shared   # relative to new worktree's project root

  - name: ui
    root: packages/ui
    node:
      mode: per_worktree         # override repo-wide default; run install fresh

# ── Lifecycle hooks ───────────────────────────────────────────────────────────
hooks:
  post_provision:
    - echo "Worktree ready: $WORKTREEX_PATH (branch: $WORKTREEX_BRANCH)"
```

### 7.1 Schema Reference

#### Top-level keys

| Key | Type | Required | Description |
|---|---|---|---|
| `version` | int | ✔ | Schema version. Must be `1`. |
| `default_base` | string | | Branch name of the base worktree. Default: `main`. |
| `env.node` | object | | Repo-wide Node.js defaults (overridable per project). |
| `direnv` | object | | direnv integration settings. |
| `projects` | array | ✔ | List of project declarations. |
| `hooks` | object | | Lifecycle hooks. |

#### `env.node` keys

| Key | Type | Default | Description |
|---|---|---|---|
| `mode` | string | `symlink_modules` ¹ | Default Node.js provisioning mode. |
| `base_worktree` | string | `main` | Which worktree's `node_modules` to symlink from (only used by `symlink_modules`). |
| `package_manager` | string | auto | `npm` / `yarn` / `pnpm` / `bun`. Auto-detected from lockfile by `init`. |
| `install_cmd` | string | `<pm> install` ² | Install command used when mode is `per_worktree`. |

> ¹ **pnpm exception:** when `package_manager: pnpm` is set (or auto-detected), `init` writes `mode: per_worktree` regardless of the repo-wide default. `symlink_modules` is never set automatically for pnpm.
> ² **pnpm exception:** `init` sets `install_cmd: pnpm install --frozen-lockfile` for pnpm projects. The `--frozen-lockfile` flag prevents lockfile mutation in worktree branches, and the install is fast because pnpm hardlinks packages from `~/.pnpm-store`.

#### `direnv` keys

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Write `.envrc` and run `direnv allow` after provisioning. |
| `template` | string | | Multi-line `.envrc` body. Supports `{{WORKTREE_PATH}}`, `{{BRANCH}}`, `{{BASE_PATH}}`. |

#### `projects[]` keys

| Key | Type | Required | Description |
|---|---|---|---|
| `name` | string | ✔ | Human-readable project name (used in status output). |
| `root` | string | ✔ | Path relative to repo root. Use `"."` for repo-root projects. |
| `node` | object | | Node.js provisioning config for this project. |
| `python` | object | | Python provisioning config for this project. |
| `dotenv` | object | | dotenv provisioning config for this project. |

#### `projects[].node` keys

| Key | Type | Default | Description |
|---|---|---|---|
| `mode` | string | *repo default* | `symlink_modules` or `per_worktree`. |
| `install_cmd` | string | *repo default* | Command to run when mode is `per_worktree`. |
| `build_cache` | string[] | `[".next/cache", ".turbo"]` | Dirs to symlink from base worktree. |

#### `projects[].python` keys

| Key | Type | Required | Description |
|---|---|---|---|
| `mode` | string | | `shared_venv` or `per_worktree`. |
| `path` | string | if `shared_venv` | Absolute path to the shared venv (supports `~/`). |
| `requirements` | string | | Requirements file, relative to project root. |

#### `projects[].dotenv` keys

| Key | Type | Required | Description |
|---|---|---|---|
| `mode` | string | `skip` | `copy_example`, `copy`, `shared_parent`, or `skip`. |
| `example_file` | string | if `copy_example` | Source template, relative to project root. |
| `shared_path` | string | if `shared_parent` | Path to the shared `.env` (supports `../`, `~/`). |

#### `hooks` keys

| Key | Type | Description |
|---|---|---|
| `post_provision` | string[] | Shell commands run in new worktree root after all provisioners finish. |

### 7.2 Environment variables available in hooks

| Variable | Value |
|---|---|
| `WORKTREEX_PATH` | Absolute path to the new worktree |
| `WORKTREEX_BRANCH` | Branch name checked out in the new worktree |
| `WORKTREEX_SOURCE` | Absolute path to the base (main) worktree |
| `WORKTREEX_PROJECT_NAMES` | Space-separated list of provisioned project names |

### 7.3 Config resolution order (per project, per key)

```
project-level value  →  env.<runtime> repo-wide default  →  built-in hardcoded default
```

---

## 8. `init` Interactive Flow (detail)

```
$ gh worktreex init

✔ Scanning repo...
  Found: apps/web      (package.json, pnpm-lock.yaml)
  Found: apps/api      (pyproject.toml, requirements.txt)
  Found: packages/ui   (package.json)
  Found: .envrc        (direnv)

Configure project "web" (apps/web):
  Node mode [symlink_modules/per_worktree]: symlink_modules
  Package manager [pnpm]: pnpm
  Dotenv mode [copy_example/copy/shared_parent/skip]: copy_example
  Example file [.env.example]: .env.example

Configure project "api" (apps/api):
  Python mode [shared_venv/per_worktree]: shared_venv
  Shared venv path [~/.venvs/myproj-api]: ~/.venvs/myproj-api
  Requirements file [requirements.txt]: requirements.txt
  Dotenv mode [copy_example/copy/shared_parent/skip]: shared_parent
  Shared env path: ../../../.env.api.shared

Configure project "ui" (packages/ui):
  Node mode [symlink_modules/per_worktree]: per_worktree
  Dotenv mode [copy_example/copy/shared_parent/skip]: skip

direnv detected. Enable direnv integration? [Y/n]: Y
  .envrc template (Enter to use default):

✔ Writing .worktreex.yml
✔ Done. Commit .worktreex.yml to share this config with your team.
   Next: gh worktreex new <branch>
```

---

## 9. Edge Cases & Error Handling

| Scenario | Behavior |
|---|---|
| `.worktreex.yml` missing on `new`/`pr`/`sync` | Abort: `"Config not found. Run: gh worktreex init"` |
| `version` field missing or unsupported | Abort with schema version error |
| `node_modules/` absent in base, mode `symlink_modules` | Warn; skip this project; continue others |
| Target asset already correctly provisioned | Skip silently |
| Target has stale or dead symlink | Remove and re-provision |
| `shared_venv` path does not exist | Create it; install deps |
| `per_worktree` python, version not found locally | Abort: `"Python <ver> not found. Try: pyenv install <ver>"` |
| `copy_example` and `example_file` absent | Warn and skip |
| `shared_parent` and `shared_path` absent from config | Abort project provisioning with config validation error |
| `direnv` not installed, `enabled: true` | Warn and skip direnv step; continue |
| Both `node` and `python` blocks in one project entry | Both provisioners run sequentially |
| `--dry-run` | Prefix all output with `[dry-run]`; no filesystem changes |
| `--no-provision` | Skip all provisioners; only run `git worktree add` |
| Source worktree is dirty | No impact; provisioning reads filesystem, not git index |

---

## 10. File Structure (Extension Repo)

```
gh-worktreex/
├── gh-worktreex                  ← main entry point (bash); command dispatcher
├── lib/
│   ├── config.sh                 ← parse .worktreex.yml → shell variables (via yq)
│   ├── init.sh                   ← interactive init wizard + config writer
│   ├── provision.sh              ← orchestrator: iterate projects[], call provisioners
│   ├── provisioners/
│   │   ├── node.sh               ← symlink_modules / per_worktree logic
│   │   ├── python.sh             ← shared_venv / per_worktree logic
│   │   ├── dotenv.sh             ← copy_example / copy / shared_parent logic
│   │   └── direnv.sh             ← .envrc template rendering + direnv allow
│   ├── hooks.sh                  ← post_provision hook runner
│   └── utils.sh                  ← logging helpers, dry-run wrapper, path resolution
├── .worktreex.yml.example        ← annotated reference config for users
├── README.md
└── v1_spec.md                    ← this file
```

**Key design principle:** `provision.sh` is the only file that knows about `projects[]`. Individual provisioner scripts in `provisioners/` receive parameters as arguments or env vars — they have no knowledge of config structure and are independently testable.

---

## 11. Success Criteria (v1 Done)

- [ ] `gh worktreex init` produces a valid `.worktreex.yml` for a Node.js monorepo.
- [ ] `gh worktreex init` produces a valid `.worktreex.yml` for a Python project.
- [ ] `gh worktreex init --yes` runs non-interactively with sensible defaults.
- [ ] `gh worktreex new <branch>` creates a worktree where every declared project is immediately runnable (no manual `npm install` / `pip install`).
- [ ] `gh worktreex pr <number>` does the same for a PR checkout.
- [ ] `gh worktreex sync` is idempotent and safe to run multiple times.
- [ ] `gh worktreex status` correctly shows per-project provisioning state across all worktrees.
- [ ] `post_provision` hooks execute with correct env vars.
- [ ] `--dry-run` shows exactly what would happen with no side effects.
- [ ] All three dotenv modes (`copy_example`, `copy`, `shared_parent`) work correctly.
- [ ] Both Node.js modes (`symlink_modules`, `per_worktree`) work correctly.
- [ ] Both Python modes (`shared_venv`, `per_worktree`) work correctly.
- [ ] direnv integration writes `.envrc` from template and runs `direnv allow`.
- [ ] Works on macOS and Linux (bash 4+).
- [ ] No required deps beyond `git`, `gh`, `python3`, coreutils — `yq` required for config parsing (clearly documented).

---

## 12. Open Questions

1. **`yq` as hard dependency:** Cleanest YAML parser available in bash. Alternatives: bundle a minimal awk-based parser (fragile) or switch to JSON config (loses familiarity). Recommendation: require `yq`, print a clear install message when absent.
2. ~~**pnpm with `symlink_modules`**~~ **Resolved:** pnpm defaults to `per_worktree` + `pnpm install --frozen-lockfile`. Symlinking pnpm's `node_modules/` is unsafe because its virtual store (`.pnpm/`) contains worktree-relative paths. `init` auto-sets `mode: per_worktree` and `install_cmd: pnpm install --frozen-lockfile` on pnpm detection. This is fast due to hardlinking from `~/.pnpm-store`.
3. **`init --force` backup:** Should overwriting an existing config also write a `.worktreex.yml.bak` to prevent accidental loss?
4. **Config location:** `.worktreex.yml` at repo root is discoverable. `.github/worktreex.yml` is cleaner for repos with strict root conventions. Support both locations with root taking precedence?
5. **`sync` scope:** Should `sync` re-provision all worktrees or only the specified one? Current decision: one worktree at a time (safer, explicit).
6. **Stale shared venv:** If `shared_venv` is used and `requirements.txt` changes on a new branch, the shared venv is mutated for all worktrees. Should `sync` detect a changed requirements file and warn the user?
