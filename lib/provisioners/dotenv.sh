#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../utils.sh"

# Files never touched
readonly DOTENV_PROTECTED=(".env.example" ".env.template" ".env.sample")

_is_protected() {
  local f="$(basename "$1")"
  for p in "${DOTENV_PROTECTED[@]}"; do [[ "$f" == "$p" ]] && return 0; done
  return 1
}

provision_dotenv() {
  local new_wt="$1" proj_root="$2" mode="$3" example_file="$4" shared_path="$5" base_wt="$6"
  local new_proj="$new_wt/$proj_root"
  local dest="$new_proj/.env"

  case "$mode" in
    copy_example)
      if [[ -z "$example_file" ]]; then
        warn "dotenv copy_example: no example_file configured — skipping"
        return 0
      fi
      local src="$new_proj/$example_file"
      if [[ ! -f "$src" ]]; then
        warn "dotenv example file not found: $src — skipping"
        return 0
      fi
      run_cmd cp "$src" "$dest"
      ok ".env copied from $example_file"
      warn "Remember to fill in real values in $dest"
      ;;

    copy)
      local base_env="$base_wt/$proj_root/.env"
      if [[ ! -f "$base_env" ]]; then
        warn "Base .env not found at $base_env — skipping"
        return 0
      fi
      if [[ "$(resolve_path "$base_env")" == "$(resolve_path "$dest")" ]]; then
        step ".env already points at base worktree file — skipping copy"
        return 0
      fi
      run_cmd cp "$base_env" "$dest"
      ok ".env copied from base worktree"
      ;;

    shared_parent)
      if [[ -z "$shared_path" ]]; then
        die "dotenv shared_parent: shared_path not configured for project"
      fi
      # Resolve path relative to new worktree project root
      local resolved
      if [[ "$shared_path" == ~* || "$shared_path" == /* ]]; then
        resolved="$(resolve_path "$shared_path")"
      else
        resolved="$(resolve_path "$new_proj/$shared_path")"
      fi
      if [[ ! -e "$resolved" ]]; then
        warn "Shared .env path not found: $resolved — skipping"
        return 0
      fi
      [[ -L "$dest" || -e "$dest" ]] && run_cmd rm "$dest"
      run_cmd ln -s "$resolved" "$dest"
      ok ".env → $resolved"
      ;;

    skip|"")
      step "dotenv: skip"
      ;;

    *)
      die "Unknown dotenv mode: $mode"
      ;;
  esac
}
