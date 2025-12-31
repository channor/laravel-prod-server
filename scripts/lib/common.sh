#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"
SKIP_ROOT_CHECK="${SKIP_ROOT_CHECK:-false}"

log() {
  local level="$1"; shift
  printf '[%s] %s\n' "$level" "$*"
}

die() {
  log "ERROR" "$*"
  exit 1
}

require_root() {
  if [[ "$SKIP_ROOT_CHECK" == "true" ]]; then
    return 0
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    die "This script must be run as root (use sudo). Set SKIP_ROOT_CHECK=true to bypass in dry runs."
  fi
}

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY-RUN] %s\n' "$*"
  else
    eval "$@"
  fi
}

ensure_package() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    log "INFO" "$pkg already installed"
    return
  fi
  run_cmd "apt-get install -y $pkg"
}

generate_password() {
  openssl rand -base64 24
}

ensure_directory() {
  local path="$1"
  local owner="$2"
  local mode="$3"
  if [[ ! -d "$path" ]]; then
    run_cmd "mkdir -p '$path'"
  fi
  run_cmd "chown -R '$owner' '$path'"
  run_cmd "chmod $mode '$path'"
}

append_unique_line() {
  local line="$1"
  local file="$2"
  if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
    return
  fi
  run_cmd "echo '$line' >> '$file'"
}
