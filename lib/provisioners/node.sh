#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../utils.sh"

provision_node() {
  local new_wt="$1" proj_root="$2" mode="$3" install_cmd="$4" node_pm="$5" base_wt="$6"
  shift 6
  local -a build_cache_dirs
  if [[ $# -eq 0 ]]; then
    build_cache_dirs=(".next/cache" ".turbo")
  else
    build_cache_dirs=("$@")
  fi

  local new_proj="$new_wt/$proj_root"

  [[ "${VERBOSE:-0}" == "1" ]] && info "provision_node: new_wt=$new_wt proj_root=$proj_root mode=$mode node_pm=$node_pm base_wt=$base_wt"

  case "$mode" in
    symlink_modules)
      local base_proj="$base_wt/$proj_root"
      local base_nm="$base_proj/node_modules"
      local new_nm="$new_proj/node_modules"

      [[ "${VERBOSE:-0}" == "1" ]] && info "provision_node: base_nm=$base_nm new_nm=$new_nm"

      if [[ ! -d "$base_nm" ]]; then
        warn "node_modules not found at $base_nm — falling back to install"
        info "Running: $install_cmd (in $new_proj)"
        if run_cmd bash -c "cd '$new_proj' && $install_cmd"; then
          ok "node_modules installed in $new_proj (fallback)"
        else
          warn "Fallback install failed in $new_proj — skipping node provisioning for this project"
        fi
        return 0
      fi

      if [[ -L "$new_nm" ]]; then
        local cur_target
        cur_target="$(readlink "$new_nm")"
        if [[ "$cur_target" == "$base_nm" ]]; then
          step "node_modules already correctly linked — skipping"
          return 0
        else
          warn "Stale symlink at $new_nm — relinking"
          run_cmd rm "$new_nm"
        fi
      elif [[ -e "$new_nm" ]]; then
        warn "Existing node_modules at $new_nm — removing and relinking"
        run_cmd rm -rf "$new_nm"
      fi

      run_cmd ln -s "$base_nm" "$new_nm"
      ok "node_modules linked: $new_nm → $base_nm"

      # Build cache symlinks
      for cache_dir in "${build_cache_dirs[@]}"; do
        local base_cache="$base_proj/$cache_dir"
        local new_cache="$new_proj/$cache_dir"
        [[ ! -d "$base_cache" ]] && continue
        [[ -L "$new_cache" ]] && continue
        run_cmd mkdir -p "$(dirname "$new_cache")"
        run_cmd ln -s "$base_cache" "$new_cache"
        step "Linked build cache: $cache_dir"
      done
      ;;

    per_worktree)
      # For pnpm workspaces, install from the worktree root so the lockfile
      # and workspace config are discovered.
      local install_dir="$new_proj"
      if [[ "$node_pm" == "pnpm" ]] && [[ -f "$new_wt/pnpm-workspace.yaml" || -f "$new_wt/pnpm-lock.yaml" ]]; then
        install_dir="$new_wt"
      fi
      info "Running: $install_cmd (in $install_dir)"
      run_cmd bash -c "cd '$install_dir' && $install_cmd"
      ok "node_modules installed in $new_proj"
      ;;

    *)
      die "Unknown node mode: $mode"
      ;;
  esac
}
