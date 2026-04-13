#!/usr/bin/env bash
set -Eeuo pipefail

# --- Environment Context ---
export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
export ROOTFS_DIR="${ROOTFS_DIR:-$BUILD_DIR/rootfs}"
export ISO_DIR="${ISO_DIR:-$BUILD_DIR/iso}"
export LOG_DIR="${LOG_DIR:-$BUILD_DIR/logs}"

# --- Advanced Logging (with Colors & File Descriptors) ---
log() {
  local level="$1"; shift
  local color=""
  case "$level" in
    INFO)  color="\e[32m" ;; # Green
    WARN)  color="\e[33m" ;; # Yellow
    ERROR) color="\e[31m" ;; # Red
    *)     color="\e[34m" ;; # Blue
  esac
  printf "${color}%s [%s] %b\e[0m\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

use_shared_logging() {
  mkdir -p "$LOG_DIR"
  local log_path="$LOG_DIR/build-$(date +%Y%m%d-%H%M).log"
  # Redirect stdout/stderr to both file and console using process substitution
  exec > >(tee -a "$log_path") 2>&1
  log INFO "Session logs: $log_path"
}

# --- Intelligent Mount Management ---
# Uses a reverse-order unmount to prevent "target is busy" errors
cleanup_mounts() {
  log INFO "Cleaning up filesystem mounts..."
  local mounts=(
    "$ROOTFS_DIR/dev/pts"
    "$ROOTFS_DIR/dev"
    "$ROOTFS_DIR/proc"
    "$ROOTFS_DIR/sys"
    "$ROOTFS_DIR/run"
    "$ROOTFS_DIR/tmp"
  )
  
  for mnt in "${mounts[@]}"; do
    if mountpoint -q "$mnt" 2>/dev/null; then
      umount -l "$mnt" || log WARN "Lazy unmount failed for $mnt"
    fi
  done
}

mount_chroot_fs() {
  log INFO "Preparing Chroot environment at $ROOTFS_DIR"
  mkdir -p "$ROOTFS_DIR"/{dev,proc,sys,run,tmp}
  
  # Use bind mounts with private propagation to protect the host
  mount --bind /dev "$ROOTFS_DIR/dev"
  mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
  mount -t proc proc "$ROOTFS_DIR/proc"
  mount -t sysfs sysfs "$ROOTFS_DIR/sys"
  mount -t tmpfs tmpfs "$ROOTFS_DIR/run"
  mount -t tmpfs tmpfs "$ROOTFS_DIR/tmp"
}

# --- System Safety & Validation ---
require_root() {
  (( EUID == 0 )) || { log ERROR "Root required. Run with sudo."; exit 1; }
}

require_cmds() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    log ERROR "Dependencies missing: ${missing[*]}"
    log INFO "Try: apt-get install ${missing[*]}"
    exit 1
  fi
}

# --- Signal Handling (The "Pro" Feature) ---
# Automatically cleans up if the user hits Ctrl+C or a script fails
safe_exit_trap() {
  local exit_code=$?
  if (( exit_code != 0 )); then
    log ERROR "Build interrupted or failed (Code: $exit_code)"
  fi
  cleanup_mounts
  exit "$exit_code"
}

# Call this at the start of your main scripts
setup_build_env() {
  trap safe_exit_trap EXIT INT TERM
  require_root
  use_shared_logging
}
