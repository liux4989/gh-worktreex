#!/usr/bin/env bash
# utils.sh — logging helpers, dry-run wrapper, path resolution

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

die()  { echo -e "${RED}Error:${RESET} $*" >&2; exit 1; }
info() { echo -e "${CYAN}→${RESET} $*"; }
ok()   { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
step() { echo -e "${BLUE}•${RESET} $*"; }

# Dry-run aware command runner
# Usage: run_cmd cmd arg1 arg2 ...
run_cmd() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "${YELLOW}[dry-run]${RESET} $*"
  else
    "$@"
  fi
}

# Resolve path supporting ~/ expansion and making absolute.
# Pure-bash implementation — works on macOS and Linux without GNU coreutils.
resolve_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  # Make absolute
  [[ "$p" != /* ]] && p="$PWD/$p"
  # Normalize . and .. components
  local result="" part
  local IFS="/"
  for part in $p; do
    case "$part" in
      ""|.) ;;
      ..) result="${result%/*}" ;;
      *)  result="$result/$part" ;;
    esac
  done
  echo "${result:-/}"
}

# Check binary available
require_binary() {
  local bin="$1" install_hint="${2:-}"
  command -v "$bin" &>/dev/null || die "'$bin' not found.${install_hint:+ $install_hint}"
}

# Resolve a path emitted by `git worktree list` to an actual filesystem worktree.
# Some repos (notably submodules/worktree hybrids) can surface gitdir paths like
# `.git/modules/<name>` instead of the checkout root.
resolve_git_worktree_path() {
  local p="$1"
  p="$(resolve_path "$p")"

  local top
  top="$(git -C "$p" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top" ]]; then
    resolve_path "$top"
    return
  fi

  local core_wt
  core_wt="$(git --git-dir="$p" config --get core.worktree 2>/dev/null || true)"
  if [[ -n "$core_wt" ]]; then
    if [[ "$core_wt" == /* ]]; then
      resolve_path "$core_wt"
    else
      resolve_path "$p/$core_wt"
    fi
    return
  fi

  echo "$p"
}

# Find the worktree path for a local branch from `git worktree list --porcelain`.
find_worktree_for_branch() {
  local target_branch="$1"
  local wt_path=""

  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        wt_path="${line#worktree }"
        ;;
      branch\ refs/heads/*)
        local b
        b="${line#branch refs/heads/}"
        if [[ "$b" == "$target_branch" ]]; then
          resolve_git_worktree_path "$wt_path"
          return 0
        fi
        ;;
    esac
  done < <(git worktree list --porcelain)

  return 1
}
