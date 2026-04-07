#!/usr/bin/env bash
# Shared helpers for Hyper-OS ISO build scripts.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOT_DIR/rootfs}"
ISO_DIR="${ISO_DIR:-$ROOT_DIR/iso}"
ISO_NAME="${ISO_NAME:-hyperos.iso}"
ISO_PATH="${ISO_PATH:-$ROOT_DIR/$ISO_NAME}"
LOG_DIR="${LOG_DIR:-$BUILD_DIR/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log}"

log() {
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2"
}

ensure_log_file() {
  mkdir -p "$LOG_DIR"
  touch "$LOG_FILE"
}

use_shared_logging() {
  ensure_log_file
  exec > >(tee -a "$LOG_FILE") 2>&1
  log INFO "Logging to $LOG_FILE"
}

die() {
  log ERROR "$1"
  exit 1
}

require_root() {
  [[ "$EUID" -eq 0 ]] || die "This script must run as root. Use: sudo <script>"
}

require_cmds() {
  local missing=0
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log ERROR "Missing required command: $cmd"
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] || die "Install missing dependencies and retry"
}

cleanup_mounts() {
  local mount_path
  for mount_path in "$ROOTFS_DIR/dev/pts" "$ROOTFS_DIR/dev" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys"; do
    if mountpoint -q "$mount_path" 2>/dev/null; then
      umount -lf "$mount_path" || true
      log INFO "Unmounted $mount_path"
    fi
  done
}

mount_chroot_fs() {
  mount --bind /dev "$ROOTFS_DIR/dev"
  mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
  mount -t proc proc "$ROOTFS_DIR/proc"
  mount -t sysfs sysfs "$ROOTFS_DIR/sys"
}
