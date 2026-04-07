#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
LOG_DIR="${LOG_DIR:-$BUILD_DIR/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log}"

usage() {
  cat <<USAGE
Hyper OS ISO build orchestrator

Usage:
  sudo ./build.sh

Outputs:
  ./hyperos.iso

Environment overrides:
  DEBIAN_SUITE, DEBIAN_MIRROR, ARCH, HOSTNAME, USERNAME,
  HYPER_PASSWORD, ROOT_PASSWORD, ISO_NAME, BUILD_DIR, ROOTFS_DIR, ISO_DIR, LOG_FILE
USAGE
}

log() {
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2"
}

require_root() {
  [[ "$EUID" -eq 0 ]] || {
    log ERROR "Run as root: sudo ./build.sh"
    exit 1
  }
}

run_step() {
  local name="$1"
  local script="$2"

  log INFO "Starting: $name"
  LOG_FILE="$LOG_FILE" "$script"
  log INFO "Completed: $name"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  require_root
  mkdir -p "$LOG_DIR"

  run_step "build root filesystem" "$SCRIPTS_DIR/build-rootfs.sh"
  run_step "configure system" "$SCRIPTS_DIR/configure-system.sh"
  run_step "build ISO" "$SCRIPTS_DIR/build-iso.sh"

  log INFO "Build finished successfully"
  log INFO "Artifact: ${ISO_PATH:-$ROOT_DIR/${ISO_NAME:-hyperos.iso}}"
  log INFO "Log file: $LOG_FILE"
}

main "$@"
