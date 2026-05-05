#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[gaming-validate] %s\n' "$*"; }

check_cmd() {
  local cmd=$1
  if command -v "$cmd" >/dev/null 2>&1; then
    log "ok: $cmd"
  else
    log "missing: $cmd"
    return 1
  fi
}

main() {
  local fail=0

  check_cmd vulkaninfo || fail=1
  check_cmd glxinfo || fail=1
  check_cmd wine || fail=1
  check_cmd winetricks || fail=1
  check_cmd steam || fail=1
  check_cmd lutris || fail=1
  check_cmd gamemoderun || fail=1
  check_cmd mangohud || fail=1

  if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary | sed -n '1,25p' || fail=1
  fi

  if command -v glxinfo >/dev/null 2>&1; then
    glxinfo -B | sed -n '1,20p' || fail=1
  fi

  if command -v wine >/dev/null 2>&1; then
    WINEDEBUG=-all wine --version || fail=1
  fi

  if [[ $fail -ne 0 ]]; then
    log "validation failed"
    exit 1
  fi

  log "validation passed"
}

main "$@"
