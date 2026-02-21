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

# Resolve path supporting ~/ expansion and making absolute
resolve_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  echo "$(realpath -m "$p")"
}

# Check binary available
require_binary() {
  local bin="$1" install_hint="${2:-}"
  command -v "$bin" &>/dev/null || die "'$bin' not found.${install_hint:+ $install_hint}"
}
