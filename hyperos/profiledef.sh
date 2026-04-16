#!/usr/bin/env bash
set -euo pipefail

# =========================
# Core Metadata
# =========================
readonly ISO_NAME="hyperos"
readonly ISO_VERSION="$(date +%Y.%m.%d)"
readonly ISO_LABEL="HYPEROS_$(date +%Y%m)"
readonly ISO_PUBLISHER="Hyper OS <https://example.com>"
readonly ISO_APPLICATION="Hyper OS Live"

# =========================
# Build Configuration
# =========================
readonly INSTALL_DIR="arch"
readonly ARCH="x86_64"
readonly BUILD_MODES=('iso')

readonly BOOT_MODES=(
  'bios.syslinux.mbr'
  'bios.syslinux.eltorito'
  'uefi-ia32.systemd-boot.esp'
  'uefi-x64.systemd-boot.esp'
  'uefi-ia32.systemd-boot.eltorito'
  'uefi-x64.systemd-boot.eltorito'
)

# =========================
# Pacman & RootFS
# =========================
readonly PACMAN_CONF="pacman.conf"
readonly AIROOTFS_IMAGE_TYPE="squashfs"
readonly AIROOTFS_IMAGE_OPTS=(
  -comp zstd
  -Xcompression-level 18
)

# =========================
# File Permissions
# =========================
declare -A FILE_PERMISSIONS=(
  ["/etc/shadow"]="0:0:400"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/usr/local/bin/hyper-firstboot"]="0:0:755"
)

# =========================
# Logging Utilities
# =========================
log() {
  echo -e "\033[1;34m[INFO]\033[0m $*"
}

warn() {
  echo -e "\033[1;33m[WARN]\033[0m $*" >&2
}

error() {
  echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
  exit 1
}

# =========================
# Validation
# =========================
check_dependencies() {
  local deps=(mkarchiso pacman)
  for dep in "${deps[@]}"; do
    command -v "$dep" >/dev/null 2>&1 || error "Missing dependency: $dep"
  done
}

check_root() {
  [[ $EUID -eq 0 ]] || error "Run this script as root."
}

# =========================
# Main Entry
# =========================
main() {
  log "Starting Hyper OS build process..."
  
  check_root
  check_dependencies

  log "ISO Name: $ISO_NAME"
  log "Version: $ISO_VERSION"
  log "Architecture: $ARCH"

  # Future: hook mkarchiso here
  # mkarchiso -v -w work -o out .

  log "Build environment validated. Ready to proceed."
}

main "$@"
