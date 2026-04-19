#!/usr/bin/env bash
# Hyper OS mkarchiso Pipeline (Production Grade)
set -Eeuo pipefail
trap 'echo "[HyperISO] ERROR at line $LINENO"; exit 1' ERR

# =========================
# Core Metadata
# =========================
readonly ISO_NAME="hyperos"
readonly ISO_VERSION="$(date +%Y.%m.%d)"
readonly ISO_LABEL="HYPEROS_$(date +%Y%m)"
readonly ISO_PUBLISHER="Hyper OS <https://example.com>"
readonly ISO_APPLICATION="Hyper OS Live"

# =========================
# Build Config
# =========================
readonly ARCH="x86_64"
readonly WORK_DIR="${WORK_DIR:-work}"
readonly OUT_DIR="${OUT_DIR:-out}"
readonly PROFILE_DIR="${PROFILE_DIR:-.}"

readonly PACMAN_CONF="${PACMAN_CONF:-pacman.conf}"
readonly LOG_FILE="$OUT_DIR/build.log"

# =========================
# Performance
# =========================
readonly JOBS="${JOBS:-$(nproc)}"
export MAKEFLAGS="-j$JOBS"

# =========================
# Logging
# =========================
log()   { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
error() { printf "\033[1;31m[FATAL]\033[0m %s\n" "$*" >&2; exit 1; }

# =========================
# Validation
# =========================
check_root() {
  [[ $EUID -eq 0 ]] || error "Run as root."
}

check_dependencies() {
  local deps=(mkarchiso pacman sha256sum find tee)
  for dep in "${deps[@]}"; do
    command -v "$dep" >/dev/null 2>&1 || error "Missing dependency: $dep"
  done
}

check_profile() {
  [[ -f "$PROFILE_DIR/profiledef.sh" ]] || error "Invalid profile: profiledef.sh missing"
}

# =========================
# Directory Setup
# =========================
prepare_dirs() {
  mkdir -p "$WORK_DIR" "$OUT_DIR"
}

clean() {
  log "Cleaning build directories..."
  rm -rf "$WORK_DIR" "$OUT_DIR"
}

# =========================
# ISO Build
# =========================
build_iso() {
  log "Starting mkarchiso build..."

  mkarchiso \
    -v \
    -C "$PACMAN_CONF" \
    -w "$WORK_DIR" \
    -o "$OUT_DIR" \
    "$PROFILE_DIR" \
    2>&1 | tee "$LOG_FILE"

  log "Build completed."

  local iso_file
  iso_file=$(find "$OUT_DIR" -maxdepth 1 -type f -name "*.iso" | sort | tail -n1 || true)

  [[ -n "$iso_file" ]] || error "ISO not found."

  log "Generated ISO: $iso_file"

  sha256sum "$iso_file" > "$iso_file.sha256"
  log "Checksum generated."

  verify_iso "$iso_file"
}

# =========================
# Verification
# =========================
verify_iso() {
  local iso="$1"

  log "Verifying ISO integrity..."

  # Check ISO readability
  file "$iso" | grep -qi "ISO 9660" || error "Invalid ISO format"

  # Boot record check (basic)
  if command -v xorriso >/dev/null; then
    xorriso -indev "$iso" -report_el_torito plain | grep -qi "boot" \
      || warn "Boot record not detected"
  fi

  log "ISO verification passed."
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
  check_profile

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
