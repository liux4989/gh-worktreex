#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../utils.sh"

provision_agent_assets() {
  local new_wt="$1" base_wt="$2" mode="$3"
  shift 3

  if [[ $# -eq 0 ]]; then
    step "agent assets: no configured paths"
    return 0
  fi

  for rel_path in "$@"; do
    [[ -z "$rel_path" ]] && continue

    local src="$base_wt/$rel_path"
    local dst="$new_wt/$rel_path"

    if [[ "$src" == "$dst" ]]; then
      step "AI asset already in base worktree: $rel_path"
      continue
    fi

    if [[ ! -e "$src" && ! -L "$src" ]]; then
      warn "AI agent asset missing in base worktree: $src — skipping"
      continue
    fi

    run_cmd mkdir -p "$(dirname "$dst")"

    case "$mode" in
      symlink)
        if [[ -L "$dst" ]]; then
          local cur_target
          cur_target="$(readlink "$dst")"
          if [[ "$cur_target" == "$src" ]]; then
            step "AI asset already linked: $rel_path"
            continue
          fi
          run_cmd rm "$dst"
        elif [[ -e "$dst" ]]; then
          run_cmd rm -rf "$dst"
        fi

        run_cmd ln -s "$src" "$dst"
        ok "AI asset linked: $rel_path"
        ;;

      copy)
        [[ -L "$dst" || -e "$dst" ]] && run_cmd rm -rf "$dst"
        run_cmd cp -R "$src" "$dst"
        ok "AI asset copied: $rel_path"
        ;;

      *)
        die "Unknown AI agent asset mode: $mode"
        ;;
    esac
  done
}
