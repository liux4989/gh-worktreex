#!/usr/bin/env bash
set -euo pipefail

INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$INIT_DIR/utils.sh"

cmd_init() {
  local yes_mode=0 force_mode=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y)   yes_mode=1 ;;
      --force|-f) force_mode=1 ;;
      *) die "Unknown flag: $1" ;;
    esac
    shift
  done

  require_binary jq "Install with: brew install jq  (macOS) or apt-get install jq  (Linux)"

  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"
  local config_file="$repo_root/.github/worktreex.json"

  # Check existing config
  if [[ -f "$config_file" && "$force_mode" == "0" ]]; then
    die "Config already exists: $config_file\nUse --force to overwrite."
  fi
  if [[ -f "$config_file" && "$force_mode" == "1" ]]; then
    cp "$config_file" "${config_file}.bak"
    info "Backed up existing config to ${config_file}.bak"
  fi

  mkdir -p "$repo_root/.github"

  info "Scanning repo..."

  # ── Scan for projects ──────────────────────────────────────────────────────
  local -a found_projects=()  # each entry: "name:root:type" where type = node|python|both

  # Find package.json files (excluding node_modules and .git)
  local pkg_jsons=()
  while IFS= read -r f; do
    pkg_jsons+=("$f")
  done < <(find "$repo_root" -name "package.json" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/dist/*" \
    -not -path "*/.*/*" \
    2>/dev/null | sort)

  # Find python project files
  local py_files=()
  while IFS= read -r f; do
    py_files+=("$f")
  done < <(find "$repo_root" \
    \( -name "pyproject.toml" -o -name "requirements.txt" -o -name "requirements*.txt" -o -name "Pipfile" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/.venv/*" \
    -not -path "*/.*/*" \
    2>/dev/null | sort)

  # Collect node project roots
  local -a node_roots=()
  if [[ ${#pkg_jsons[@]} -gt 0 ]]; then
    for pkg in "${pkg_jsons[@]}"; do
      local proj_dir
      proj_dir="$(dirname "$pkg")"
      local rel_root
      rel_root="${proj_dir#$repo_root/}"
      [[ "$proj_dir" == "$repo_root" ]] && rel_root="."
      node_roots+=("$rel_root")
      info "  Found: $rel_root  (package.json)"
    done
  fi

  # Collect python project roots
  local -a py_roots=()
  if [[ ${#py_files[@]} -gt 0 ]]; then
    for pf in "${py_files[@]}"; do
      local proj_dir
      proj_dir="$(dirname "$pf")"
      local rel_root
      rel_root="${proj_dir#$repo_root/}"
      [[ "$proj_dir" == "$repo_root" ]] && rel_root="."
      # Avoid duplicates
      local already=0
      if [[ ${#py_roots[@]} -gt 0 ]]; then
        for existing in "${py_roots[@]}"; do [[ "$existing" == "$rel_root" ]] && already=1; done
      fi
      [[ "$already" == "0" ]] && py_roots+=("$rel_root")
      info "  Found: $rel_root  ($(basename "$pf"))"
    done
  fi

  # Detect direnv
  local has_direnv=0
  if [[ -f "$repo_root/.envrc" ]] || command -v direnv &>/dev/null; then
    info "  Found: .envrc  (direnv)"
    has_direnv=1
  fi

  # Detect AI agent assets to carry across worktrees
  local -a found_agent_assets=()
  local -a agent_asset_candidates=(
    "AGENTS.md"
    "Agents.md"
    ".claude"
    ".agents"
    ".agents/skills"
    ".codex/skills"
  )
  local agent_asset
  for agent_asset in "${agent_asset_candidates[@]}"; do
    if [[ -e "$repo_root/$agent_asset" || -L "$repo_root/$agent_asset" ]]; then
      found_agent_assets+=("$agent_asset")
      info "  Found: $agent_asset  (AI agent asset)"
    fi
  done

  # ── Detect package manager ─────────────────────────────────────────────────
  detect_pkg_manager() {
    local proj_dir="$1"
    local root_dir="$repo_root"
    if [[ -f "$proj_dir/pnpm-lock.yaml" || -f "$proj_dir/pnpm-workspace.yaml" \
       || -f "$root_dir/pnpm-lock.yaml" || -f "$root_dir/pnpm-workspace.yaml" ]]; then echo "pnpm"
    elif [[ -f "$proj_dir/bun.lockb" || -f "$root_dir/bun.lockb" ]]; then echo "bun"
    elif [[ -f "$proj_dir/yarn.lock" || -f "$root_dir/yarn.lock" ]]; then echo "yarn"
    elif [[ -f "$proj_dir/package-lock.json" || -f "$root_dir/package-lock.json" ]]; then echo "npm"
    else echo "npm"
    fi
  }

  # ── Prompt helper ─────────────────────────────────────────────────────────
  prompt_with_default() {
    local question="$1" default="$2" hint="${3:-}"
    if [[ "$yes_mode" == "1" ]]; then
      echo "$default"
      return
    fi
    local answer
    if [[ -n "$hint" ]]; then
      echo "$question" >&2
      read -r -p "    $hint (default: $default): " answer
    else
      read -r -p "$question (default: $default): " answer
    fi
    echo "${answer:-$default}"
  }

  prompt_choice() {
    local question="$1" choices="$2" default="$3" tip="${4:-}"
    if [[ "$yes_mode" == "1" ]]; then
      echo "$default"
      return
    fi
    # Build indexed option list
    local IFS='/'
    local -a opts=()
    local default_idx=1 idx=0
    for opt in $choices; do
      idx=$((idx + 1))
      opts+=("$opt")
      [[ "$opt" == "$default" ]] && default_idx=$idx
    done
    echo "$question:" >&2
    [[ -n "$tip" ]] && echo "    💡 $tip" >&2
    for i in "${!opts[@]}"; do
      local num=$((i + 1))
      if [[ "${opts[$i]}" == "$default" ]]; then
        echo "    $num) ${opts[$i]} (default)" >&2
      else
        echo "    $num) ${opts[$i]}" >&2
      fi
    done
    local answer
    read -r -p "    Enter choice [1-${#opts[@]}, default=$default_idx]: " answer
    if [[ -z "$answer" ]]; then
      echo "$default"
    elif [[ "$answer" =~ ^[0-9]+$ && "$answer" -ge 1 && "$answer" -le "${#opts[@]}" ]]; then
      echo "${opts[$((answer - 1))]}"
    else
      echo "$answer"
    fi
  }

  # ── Build projects JSON ────────────────────────────────────────────────────
  local projects_json="[]"
  local repo_name
  repo_name="$(basename "$repo_root")"

  # Process node projects
  local processed_roots=" "  # space-delimited list for bash 3.2 compat
  if [[ ${#node_roots[@]} -gt 0 ]]; then
  for rel_root in "${node_roots[@]}"; do
    [[ -z "$rel_root" ]] && continue
    local proj_dir="$repo_root/$rel_root"
    [[ "$rel_root" == "." ]] && proj_dir="$repo_root"

    local proj_name
    if [[ "$rel_root" == "." ]]; then
      proj_name="$repo_name"
    else
      proj_name="$(basename "$rel_root")"
    fi

    echo ""
    info "Configure project \"$proj_name\" ($rel_root):"

    local pm
    pm="$(detect_pkg_manager "$proj_dir")"
    pm="$(prompt_choice "  Package manager" "npm/pnpm/yarn/bun" "$pm")"

    # pnpm always gets per_worktree
    local default_node_mode="symlink_modules"
    if [[ "$pm" == "pnpm" ]]; then
      default_node_mode="per_worktree"
    fi

    local node_mode
    node_mode="$(prompt_choice "  Node mode" "symlink_modules/per_worktree" "$default_node_mode" \
      "symlink_modules: share node_modules via symlink (saves disk). per_worktree: separate install per worktree (required for pnpm).")"

    local default_install_cmd="$pm install"
    if [[ "$pm" == "pnpm" ]]; then
      default_install_cmd="pnpm install --frozen-lockfile"
    fi
    local install_cmd
    install_cmd="$(prompt_with_default "  Install command" "$default_install_cmd" "Command to install dependencies")"

    local dot_mode
    dot_mode="$(prompt_choice "  Dotenv mode" "copy_example/copy/shared_parent/skip" "skip" \
      "copy_example: copy .env.example to .env. copy: copy .env from main worktree. shared_parent: symlink from parent dir. skip: no .env handling.")"

    local dot_example="" dot_shared=""
    if [[ "$dot_mode" == "copy_example" ]]; then
      dot_example="$(prompt_with_default "  Example file" ".env.example" "Path to .env template file")"
    elif [[ "$dot_mode" == "shared_parent" ]]; then
      dot_shared="$(prompt_with_default "  Shared env path" "../.env.shared" "Path to shared .env file")"
    fi

    # Build project JSON
    local proj_json
    proj_json="$(jq -n \
      --arg name "$proj_name" \
      --arg root "$rel_root" \
      --arg node_mode "$node_mode" \
      --arg install_cmd "$install_cmd" \
      --arg dot_mode "$dot_mode" \
      --arg dot_example "$dot_example" \
      --arg dot_shared "$dot_shared" \
      '{
        name: $name,
        root: $root,
        node: {
          mode: $node_mode,
          install_cmd: $install_cmd
        },
        dotenv: (if $dot_mode != "skip" and $dot_mode != "" then
          {mode: $dot_mode}
          + (if $dot_example != "" then {example_file: $dot_example} else {} end)
          + (if $dot_shared != "" then {shared_path: $dot_shared} else {} end)
        else {mode: "skip"} end)
      }'
    )"

    projects_json="$(echo "$projects_json" | jq --argjson proj "$proj_json" '. += [$proj]')"
    processed_roots="$processed_roots$rel_root "
  done
  fi  # end node_roots loop

  # Process python projects (skip already-processed roots)
  if [[ ${#py_roots[@]} -gt 0 ]]; then
  for rel_root in "${py_roots[@]}"; do
    [[ -z "$rel_root" ]] && continue
    [[ "$processed_roots" == *" $rel_root "* ]] && continue  # already done as node proj

    local proj_dir="$repo_root/$rel_root"
    [[ "$rel_root" == "." ]] && proj_dir="$repo_root"

    local proj_name
    if [[ "$rel_root" == "." ]]; then proj_name="$repo_name"
    else proj_name="$(basename "$rel_root")"
    fi

    echo ""
    info "Configure project \"$proj_name\" ($rel_root):"

    local py_mode
    py_mode="$(prompt_choice "  Python mode" "shared_venv/per_worktree" "shared_venv" \
      "shared_venv: all worktrees share one virtualenv (saves disk). per_worktree: each worktree gets its own venv.")"

    # Detect Python package manager
    local default_py_pm="pip"
    if [[ -f "$proj_dir/uv.lock" || -f "$repo_root/uv.lock" ]]; then
      default_py_pm="uv"
    elif [[ -f "$proj_dir/poetry.lock" || -f "$repo_root/poetry.lock" ]]; then
      default_py_pm="poetry"
    elif [[ -f "$proj_dir/Pipfile.lock" || -f "$repo_root/Pipfile.lock" ]]; then
      default_py_pm="pipenv"
    fi
    local py_pm
    py_pm="$(prompt_choice "  Python package manager" "pip/uv/poetry/pipenv" "$default_py_pm")"

    local py_path="" py_reqs=""
    if [[ "$py_mode" == "shared_venv" ]]; then
      py_path="$(prompt_with_default "  Shared venv path" "~/.venvs/${repo_name}-${proj_name}" "Path to shared virtualenv directory")"
    fi

    # Auto-detect install command / requirements
    local default_install_cmd="" default_reqs=""
    case "$py_pm" in
      uv)
        default_install_cmd="uv sync"
        default_reqs="pyproject.toml"
        ;;
      poetry)
        default_install_cmd="poetry install"
        default_reqs="pyproject.toml"
        ;;
      pipenv)
        default_install_cmd="pipenv install"
        default_reqs="Pipfile"
        ;;
      *)
        default_install_cmd="pip install -r requirements.txt"
        default_reqs="requirements.txt"
        [[ -f "$proj_dir/requirements/base.txt" ]] && default_reqs="requirements/base.txt"
        ;;
    esac
    local py_install_cmd
    py_install_cmd="$(prompt_with_default "  Install command" "$default_install_cmd" "Command to install dependencies")"
    py_reqs="$(prompt_with_default "  Dependencies file" "$default_reqs" "Path to dependency definition file")"

    local dot_mode
    dot_mode="$(prompt_choice "  Dotenv mode" "copy_example/copy/shared_parent/skip" "skip" \
      "copy_example: copy .env.example to .env. copy: copy .env from main worktree. shared_parent: symlink from parent dir. skip: no .env handling.")"
    local dot_example="" dot_shared=""
    if [[ "$dot_mode" == "copy_example" ]]; then
      dot_example="$(prompt_with_default "  Example file" ".env.example" "Path to .env template file")"
    elif [[ "$dot_mode" == "shared_parent" ]]; then
      dot_shared="$(prompt_with_default "  Shared env path" "../.env.shared" "Path to shared .env file")"
    fi

    local proj_json
    proj_json="$(jq -n \
      --arg name "$proj_name" \
      --arg root "$rel_root" \
      --arg py_pm "$py_pm" \
      --arg py_mode "$py_mode" \
      --arg py_path "$py_path" \
      --arg py_reqs "$py_reqs" \
      --arg py_install_cmd "$py_install_cmd" \
      --arg dot_mode "$dot_mode" \
      --arg dot_example "$dot_example" \
      --arg dot_shared "$dot_shared" \
      '{
        name: $name,
        root: $root,
        python: {mode: $py_mode, package_manager: $py_pm, install_cmd: $py_install_cmd}
          + (if $py_path != "" then {path: $py_path} else {} end)
          + (if $py_reqs != "" then {requirements: $py_reqs} else {} end),
        dotenv: (if $dot_mode != "skip" and $dot_mode != "" then
          {mode: $dot_mode}
          + (if $dot_example != "" then {example_file: $dot_example} else {} end)
          + (if $dot_shared != "" then {shared_path: $dot_shared} else {} end)
        else {mode: "skip"} end)
      }'
    )"
    projects_json="$(echo "$projects_json" | jq --argjson proj "$proj_json" '. += [$proj]')"
  done
  fi  # end py_roots loop

  # If no projects found at all
  if [[ "$(echo "$projects_json" | jq 'length')" == "0" ]]; then
    warn "No projects auto-detected. You can manually edit $config_file after creation."
    local proj_name
    proj_name="$(prompt_with_default "Project name" "$repo_name" "Name for this project")"
    projects_json="[$(jq -n --arg name "$proj_name" '{name: $name, root: "."}')]"
  fi

  # ── Default base branch ───────────────────────────────────────────────────
  echo ""
  local default_base
  # detect main or master
  if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    default_base="main"
  elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    default_base="master"
  else
    default_base="main"
  fi
  default_base="$(prompt_with_default "Default base branch" "$default_base" "Branch name used as base for new worktrees")"

  # ── direnv ────────────────────────────────────────────────────────────────
  local direnv_json="null"
  if [[ "$has_direnv" == "1" ]]; then
    local enable_direnv="n"
    if [[ "$yes_mode" == "1" ]]; then
      enable_direnv="y"
    else
      read -r -p "$(echo -e "\ndirenv detected. Enable direnv integration? [Y/n]: ")" enable_direnv
      enable_direnv="${enable_direnv:-y}"
    fi
    if [[ "$enable_direnv" =~ ^[Yy]$ ]]; then
      local default_tmpl='source_env_if_present .env'
      direnv_json="$(jq -n \
        --arg tmpl "$default_tmpl" \
        '{enabled: true, template: [$tmpl]}'
      )"
    fi
  fi

  # ── AI agent assets ───────────────────────────────────────────────────────
  local agent_json="null"
  if [[ ${#found_agent_assets[@]} -gt 0 ]]; then
    local enable_agent_assets="n"
    if [[ "$yes_mode" == "1" ]]; then
      enable_agent_assets="y"
    else
      read -r -p "$(echo -e "\nAI agent files detected. Provision them in new worktrees? [Y/n]: ")" enable_agent_assets
      enable_agent_assets="${enable_agent_assets:-y}"
    fi

    if [[ "$enable_agent_assets" =~ ^[Yy]$ ]]; then
      local agent_mode
      agent_mode="$(prompt_choice "  AI asset mode" "symlink/copy" "symlink" \
        "symlink keeps one shared source of truth. copy creates independent per-worktree files.")"

      local agent_paths_json
      agent_paths_json="$(jq -n --args "${found_agent_assets[@]}" '$ARGS.positional')"
      agent_json="$(jq -n \
        --arg mode "$agent_mode" \
        --argjson paths "$agent_paths_json" \
        '{enabled: true, mode: $mode, paths: $paths}'
      )"
    fi
  fi

  # ── Build final config ────────────────────────────────────────────────────
  local config_json
  config_json="$(jq -n \
    --arg default_base "$default_base" \
    --argjson projects "$projects_json" \
    --argjson direnv_block "$direnv_json" \
    --argjson agent_block "$agent_json" \
    '{
      version: 1,
      default_base: $default_base,
      projects: $projects,
      hooks: {post_provision: []}
    }
    + (if $direnv_block != null then {direnv: $direnv_block} else {} end)
    + (if $agent_block != null then {agent: $agent_block} else {} end)'
  )"

  # ── Write config ──────────────────────────────────────────────────────────
  echo "$config_json" | jq '.' > "$config_file"
  echo ""
  ok "Writing $config_file"
  ok "Done. Commit .github/worktreex.json to share this config with your team."
  echo -e "   Next: ${BOLD}gh worktreex new <branch>${RESET}"
}
