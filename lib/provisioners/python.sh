#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../utils.sh"

provision_python() {
  local new_wt="$1" proj_root="$2" mode="$3" venv_path="$4" requirements="$5" base_wt="$6"
  local new_proj="$new_wt/$proj_root"

  case "$mode" in
    shared_venv)
      local shared_path
      shared_path="$(resolve_path "${venv_path:-~/.venvs/worktreex-default}")"

      if [[ ! -d "$shared_path" ]]; then
        info "Creating shared venv at $shared_path"
        run_cmd python3 -m venv "$shared_path"
        if [[ -n "$requirements" && -f "$new_proj/$requirements" ]]; then
          run_cmd "$shared_path/bin/pip" install -r "$new_proj/$requirements"
        elif [[ -n "$requirements" && -f "$base_wt/$proj_root/$requirements" ]]; then
          run_cmd "$shared_path/bin/pip" install -r "$base_wt/$proj_root/$requirements"
        fi
      fi

      local venv_link="$new_proj/.venv"
      if [[ -L "$venv_link" && "$(readlink "$venv_link")" == "$shared_path" ]]; then
        step ".venv symlink already correct — skipping"
      else
        [[ -L "$venv_link" || -e "$venv_link" ]] && run_cmd rm -rf "$venv_link"
        run_cmd ln -s "$shared_path" "$venv_link"
        ok ".venv → $shared_path"
      fi
      ;;

    per_worktree)
      # Detect python version
      local python_bin="python3"
      local py_ver_file="$new_proj/.python-version"
      [[ ! -f "$py_ver_file" ]] && py_ver_file="$base_wt/$proj_root/.python-version"

      if [[ -f "$py_ver_file" ]]; then
        local py_ver
        py_ver="$(cat "$py_ver_file" | tr -d '[:space:]')"
        if command -v "python${py_ver}" &>/dev/null; then
          python_bin="python${py_ver}"
        elif command -v "python3" &>/dev/null; then
          python_bin="python3"
          warn "python${py_ver} not found, using python3"
        else
          die "Python $py_ver not found. Try: pyenv install $py_ver"
        fi
      fi

      local venv_dir="$new_proj/.venv"
      info "Creating venv at $venv_dir with $python_bin"
      run_cmd "$python_bin" -m venv "$venv_dir"

      # Install deps
      local has_build_system=0
      if [[ -f "$new_proj/pyproject.toml" ]] && grep -q '\[build-system\]' "$new_proj/pyproject.toml" 2>/dev/null; then
        has_build_system=1
      fi

      if [[ "$has_build_system" == "1" ]]; then
        run_cmd "$venv_dir/bin/pip" install -e ".[dev]" --quiet
      elif [[ -n "$requirements" && -f "$new_proj/$requirements" ]]; then
        run_cmd "$venv_dir/bin/pip" install -r "$new_proj/$requirements" --quiet
      fi
      ok ".venv created at $venv_dir"
      ;;

    *)
      die "Unknown python mode: $mode"
      ;;
  esac
}
