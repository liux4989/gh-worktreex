#!/usr/bin/env bash
set -euo pipefail
PROVISION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PROVISION_DIR/utils.sh"
source "$PROVISION_DIR/config.sh"
source "$PROVISION_DIR/provisioners/node.sh"
source "$PROVISION_DIR/provisioners/python.sh"
source "$PROVISION_DIR/provisioners/dotenv.sh"
source "$PROVISION_DIR/provisioners/direnv.sh"
source "$PROVISION_DIR/provisioners/agent.sh"
source "$PROVISION_DIR/hooks.sh"

provision_worktree() {
  local new_wt="$1"
  local branch="$2"
  local base_wt="${3:-}"

  config_load  # validates config

  # Determine base worktree path if not given
  if [[ -z "$base_wt" ]]; then
    local default_base
    default_base="$(config_get_default_base)"
    # Find the worktree with that branch
    base_wt="$(git worktree list --porcelain | awk -v b="refs/heads/$default_base" '/^worktree /{p=$2} $0=="branch "b{print p; exit}')"
    [[ -z "$base_wt" ]] && base_wt="$(git rev-parse --show-toplevel)"
  fi

  local projects provisioned_names=""
  projects="$(config_get_projects)"

  for proj_name in $projects; do
    local proj_root
    proj_root="$(config_get_project_root "$proj_name")"

    step "Provisioning project: $proj_name [$proj_root]"

    local did_something=0

    # Node provisioner
    if config_has_node "$proj_name"; then
      local node_mode install_cmd
      node_mode="$(config_get_node_mode "$proj_name")"
      install_cmd="$(config_get_node_install_cmd "$proj_name")"
      provision_node "$new_wt" "$proj_root" "$node_mode" "$install_cmd" "$base_wt"
      did_something=1
    fi

    # Python provisioner
    if config_has_python "$proj_name"; then
      local py_mode py_path py_reqs
      py_mode="$(config_get_python_mode "$proj_name")"
      py_path="$(config_get_python_path "$proj_name")"
      py_reqs="$(config_get_python_requirements "$proj_name")"
      provision_python "$new_wt" "$proj_root" "$py_mode" "${py_path:-}" "${py_reqs:-}" "$base_wt"
      did_something=1
    fi

    # Dotenv provisioner
    if config_has_dotenv "$proj_name"; then
      local dot_mode dot_example dot_shared
      dot_mode="$(config_get_dotenv_mode "$proj_name")"
      dot_example="$(config_get_dotenv_example_file "$proj_name")"
      dot_shared="$(config_get_dotenv_shared_path "$proj_name")"
      provision_dotenv "$new_wt" "$proj_root" "$dot_mode" "${dot_example:-}" "${dot_shared:-}" "$base_wt"
      did_something=1
    fi

    provisioned_names="$provisioned_names $proj_name"
  done

  # direnv provisioner (repo-wide)
  if [[ "$(config_get_direnv_enabled)" == "true" ]]; then
    local tmpl
    tmpl="$(config_get_direnv_template)"
    provision_direnv "$new_wt" "$branch" "$base_wt" "$tmpl"
  fi

  # AI agent assets provisioner (repo-wide)
  if config_has_agent_assets; then
    local agent_mode
    local -a agent_paths=()
    local -a agent_excludes=()
    agent_mode="$(config_get_agent_mode)"
    while IFS= read -r p; do
      [[ -n "$p" ]] && agent_paths+=("$p")
    done < <(config_get_agent_paths)
    while IFS= read -r e; do
      [[ -n "$e" ]] && agent_excludes+=("$e")
    done < <(config_get_agent_excludes)

    provision_agent_assets "$new_wt" "$base_wt" "$agent_mode" "${agent_paths[@]}" --exclude "${agent_excludes[@]}"
  fi

  # Post-provision hooks
  hooks_run_post_provision "$new_wt" "$branch" "$base_wt" "${provisioned_names# }"

  ok "Provisioning complete for: $new_wt"
}
