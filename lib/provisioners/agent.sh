#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../utils.sh"

provision_agent_assets() {
  local new_wt="$1" base_wt="$2" mode="$3"
  shift 3

  local -a paths=()
  local -a excludes=()
  local in_excludes=0
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--exclude" ]]; then
      in_excludes=1
      continue
    fi
    if [[ "$in_excludes" == "1" ]]; then
      excludes+=("$arg")
    else
      paths+=("$arg")
    fi
  done

  if [[ ${#paths[@]} -eq 0 ]]; then
    step "agent assets: no configured paths"
    return 0
  fi

  _exclude_exact() {
    local rel="$1"
    local ex
    for ex in "${excludes[@]}"; do
      [[ "$ex" == "$rel" ]] && return 0
    done
    return 1
  }

  _exclude_under() {
    local rel="$1"
    local ex
    for ex in "${excludes[@]}"; do
      [[ "$ex" == "$rel" || "$ex" == "$rel/"* ]] && return 0
    done
    return 1
  }

  for rel_path in "${paths[@]}"; do
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

    if _exclude_exact "$rel_path"; then
      step "AI asset excluded: $rel_path"
      continue
    fi

    run_cmd mkdir -p "$(dirname "$dst")"

    local effective_mode="$mode"
    if [[ "$mode" == "symlink" && -d "$src" ]] && _exclude_under "$rel_path"; then
      warn "AI asset excludes require copy mode for '$rel_path' — copying instead of symlinking"
      effective_mode="copy"
    fi

    case "$effective_mode" in
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
        if [[ -d "$src" && ${#excludes[@]} -gt 0 ]]; then
          local ex
          for ex in "${excludes[@]}"; do
            if [[ "$ex" == "$rel_path" || "$ex" == "$rel_path/"* ]]; then
              local ex_rel="${ex#$rel_path/}"
              [[ "$ex" == "$rel_path" ]] && continue
              run_cmd rm -rf "$dst/$ex_rel" 2>/dev/null || true
            fi
          done
        fi
        ok "AI asset copied: $rel_path"
        ;;

      *)
        die "Unknown AI agent asset mode: $mode"
        ;;
    esac
  done
}
