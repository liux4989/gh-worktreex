#!/usr/bin/env bash
# config.sh — parse .github/worktreex.json using jq

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

config_load() {
  require_binary jq "Install with: brew install jq (macOS) or apt install jq (Linux)"
  [[ -f "$CONFIG_FILE" ]] || die "Config not found at $CONFIG_FILE. Run: gh worktreex init"
  local version
  version="$(jq -r '.version // empty' "$CONFIG_FILE")"
  [[ "$version" == "1" ]] || die "Unsupported config version '${version:-missing}'. Expected: 1"
}

config_get_default_base() {
  jq -r '.default_base // "main"' "$CONFIG_FILE"
}

config_get_projects() {
  jq -r '[.projects[].name] | join(" ")' "$CONFIG_FILE"
}

config_get_project_root() {
  local name="$1"
  jq -r --arg n "$name" '.projects[] | select(.name==$n) | .root' "$CONFIG_FILE"
}

# Node helpers — project-level overrides env.node defaults

config_get_node_mode() {
  local name="$1"
  jq -r --arg n "$name" '
    (.projects[] | select(.name==$n) | .node.mode)
    // .env.node.mode
    // "symlink_modules"
  ' "$CONFIG_FILE"
}

config_get_node_install_cmd() {
  local name="$1"
  local pm
  pm="$(config_get_node_pm "$name")"
  jq -r --arg n "$name" --arg default_cmd "${pm:-npm} install" '
    (.projects[] | select(.name==$n) | .node.install_cmd)
    // .env.node.install_cmd
    // $default_cmd
  ' "$CONFIG_FILE"
}

config_get_node_pm() {
  local name="$1"
  jq -r --arg n "$name" '
    (.projects[] | select(.name==$n) | .node.package_manager)
    // .env.node.package_manager
    // "npm"
  ' "$CONFIG_FILE"
}

# Python helpers

config_get_python_mode() {
  local name="$1"
  jq -r --arg n "$name" '
    .projects[] | select(.name==$n) | .python.mode // empty
  ' "$CONFIG_FILE"
}

config_get_python_path() {
  local name="$1"
  local raw
  raw="$(jq -r --arg n "$name" '
    .projects[] | select(.name==$n) | .python.path // empty
  ' "$CONFIG_FILE")"
  [[ -n "$raw" ]] && resolve_path "$raw" || echo ""
}

config_get_python_requirements() {
  local name="$1"
  jq -r --arg n "$name" '
    .projects[] | select(.name==$n) | .python.requirements // empty
  ' "$CONFIG_FILE"
}

# Dotenv helpers

config_get_dotenv_mode() {
  local name="$1"
  jq -r --arg n "$name" '
    (.projects[] | select(.name==$n) | .dotenv.mode) // "skip"
  ' "$CONFIG_FILE"
}

config_get_dotenv_example_file() {
  local name="$1"
  jq -r --arg n "$name" '
    .projects[] | select(.name==$n) | .dotenv.example_file // empty
  ' "$CONFIG_FILE"
}

config_get_dotenv_shared_path() {
  local name="$1"
  jq -r --arg n "$name" '
    .projects[] | select(.name==$n) | .dotenv.shared_path // empty
  ' "$CONFIG_FILE"
}

# Direnv helpers

config_get_direnv_enabled() {
  jq -r '.direnv.enabled // "false"' "$CONFIG_FILE"
}

config_get_direnv_template() {
  jq -r '(.direnv.template // []) | join("\n")' "$CONFIG_FILE"
}

# AI agent asset helpers

config_get_agent_enabled() {
  jq -r '.agent.enabled // "false"' "$CONFIG_FILE"
}

config_get_agent_mode() {
  jq -r '.agent.mode // "symlink"' "$CONFIG_FILE"
}

config_get_agent_paths() {
  jq -r '(.agent.paths // [])[]' "$CONFIG_FILE"
}

# Hooks

config_get_hooks_post_provision() {
  jq -r '(.hooks.post_provision // []) | .[]' "$CONFIG_FILE"
}

# Type-check helpers (return 0/1 for use in conditionals)

config_has_node() {
  local name="$1"
  jq -e --arg n "$name" '.projects[] | select(.name==$n) | .node' "$CONFIG_FILE" >/dev/null 2>&1
}

config_has_python() {
  local name="$1"
  jq -e --arg n "$name" '.projects[] | select(.name==$n) | .python' "$CONFIG_FILE" >/dev/null 2>&1
}

config_has_dotenv() {
  local name="$1"
  jq -e --arg n "$name" '.projects[] | select(.name==$n) | .dotenv' "$CONFIG_FILE" >/dev/null 2>&1
}

config_has_agent_assets() {
  jq -e '(.agent.enabled // false) == true and ((.agent.paths // []) | length > 0)' "$CONFIG_FILE" >/dev/null 2>&1
}
