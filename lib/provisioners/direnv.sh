#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../utils.sh"

provision_direnv() {
  local new_wt="$1" branch="$2" base_wt="$3" template="$4"

  if ! command -v direnv &>/dev/null; then
    warn "direnv not installed — skipping direnv provisioning"
    return 0
  fi

  local envrc="$new_wt/.envrc"

  # Substitute template variables
  local content="$template"
  content="${content//\{\{WORKTREE_PATH\}\}/$new_wt}"
  content="${content//\{\{BRANCH\}\}/$branch}"
  content="${content//\{\{BASE_PATH\}\}/$base_wt}"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "${YELLOW}[dry-run]${RESET} Would write $envrc:"
    echo "$content"
    echo -e "${YELLOW}[dry-run]${RESET} direnv allow $new_wt"
  else
    echo "$content" > "$envrc"
    direnv allow "$new_wt"
    ok ".envrc written and allowed"
  fi
}
