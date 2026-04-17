#!/usr/bin/env bash
set -Eeuo pipefail

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
readonly ARCH="x86_64"
readonly WORK_DIR="work"
readonly OUT_DIR="out"

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
# Logging
# =========================
log()   { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

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
  [[ $EUID -eq 0 ]] || error "Run as root."
}

prepare_dirs() {
  mkdir -p "$WORK_DIR" "$OUT_DIR"
}

clean() {
  log "Cleaning build directories..."
  rm -rf "$WORK_DIR" "$OUT_DIR"
}

# =========================
# Build
# =========================
build_iso() {
  log "Starting mkarchiso build..."

  mkarchiso \
    -v \
    -w "$WORK_DIR" \
    -o "$OUT_DIR" \
    .

  log "ISO build complete."

  local iso_file
  iso_file=$(find "$OUT_DIR" -name "*.iso" | head -n1)

  [[ -f "$iso_file" ]] || error "ISO not found after build."

  log "Generated ISO: $iso_file"

  sha256sum "$iso_file" > "$iso_file.sha256"
  log "Checksum generated."
}

# =========================
# CLI
# =========================
usage() {
  echo "Usage: $0 [build|clean|rebuild]"
}

main() {
  local cmd="${1:-build}"

  check_root
  check_dependencies

  case "$cmd" in
    build)
      prepare_dirs
      build_iso
      ;;
    clean)
      clean
      ;;
    rebuild)
      clean
      prepare_dirs
      build_iso
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
