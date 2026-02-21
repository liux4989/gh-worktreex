#!/usr/bin/env bash
# hooks.sh — post_provision hook runner

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

hooks_run_post_provision() {
  local new_wt="$1" branch="$2" source_wt="$3" project_names="$4"

  export WORKTREEX_PATH="$new_wt"
  export WORKTREEX_BRANCH="$branch"
  export WORKTREEX_SOURCE="$source_wt"
  export WORKTREEX_PROJECT_NAMES="$project_names"

  local hooks
  hooks="$(config_get_hooks_post_provision 2>/dev/null)" || return 0

  [[ -z "$hooks" ]] && return 0

  step "Running post_provision hooks..."
  while IFS= read -r hook_cmd; do
    [[ -z "$hook_cmd" ]] && continue
    info "Hook: $hook_cmd"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      echo -e "${YELLOW}[dry-run]${RESET} (in $new_wt) $hook_cmd"
    else
      (cd "$new_wt" && eval "$hook_cmd")
    fi
  done <<< "$hooks"
}
