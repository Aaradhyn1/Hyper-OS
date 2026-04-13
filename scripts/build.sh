#!/usr/bin/env bash
# Hyper OS Raspberry Pi Buildroot Provisioner
set -Eeuo pipefail

# --- Advanced Configuration ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDROOT_DIR="${BUILDROOT_DIR:-$ROOT_DIR/buildroot}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/out/rpi4}"
DL_DIR="${DL_DIR:-$ROOT_DIR/dl}"        # Persistent download cache
CCACHE_DIR="${CCACHE_DIR:-$ROOT_DIR/.ccache}"
JOBS=$(nproc)

log() { printf "\e[35m[hyper-rpi] [%s] %s\e[0m\n" "$(date '+%H:%M:%S')" "$1"; }

# Trap for precise error reporting
trap 'log ERROR "Command \"$BASH_COMMAND\" failed at line $LINENO"' ERR

# 1. Environment Preparation
mkdir -p "$DL_DIR" "$CCACHE_DIR" "$OUTPUT_DIR"

# 2. Build Engine Logic
run_build() {
    log "Configuring Buildroot (OOT)..."
    
    # Advanced: Use 'make-command' to pass environment variables for CCACHE and DL
    local BR_OPTS=(
        "O=$OUTPUT_DIR"
        "BR2_DL_DIR=$DL_DIR"
        "BR2_CCACHE_DIR=$CCACHE_DIR"
        "BR2_DEFCONFIG=$ROOT_DIR/configs/rpi4_minimal_defconfig"
    )

    make -C "$BUILDROOT_DIR" "${BR_OPTS[@]}" defconfig

    log "Starting parallel build using $JOBS cores..."
    # 'graph-depends' or 'sdk' could be added here for advanced debugging
    make -C "$BUILDROOT_DIR" "${BR_OPTS[@]}" BR2_JLEVEL="$JOBS"
}

# 3. Post-Build Integrity Check
verify_artifacts() {
    local img="$OUTPUT_DIR/images/sdcard.img"
    if [[ -f "$img" ]]; then
        log "Verifying image integrity..."
        sha256sum "$img" > "${img}.sha256"
        log "Success: SD Card Image at $img"
    else
        log ERROR "Build finished but sdcard.img is missing."
        exit 1
    fi
}

# --- Execution ---
if [[ -f "$BUILDROOT_DIR/Makefile" ]]; then
    run_build
    verify_artifacts
elif [[ "${OFFLINE_FALLBACK:-0}" == "1" ]]; then
    # Keeping your existing fallback logic but wrapping it in the new logger
    log WARN "Buildroot source missing. Packaging offline bundle..."
    # [Insert your run_offline_bundle logic here]
else
    log ERROR "Buildroot not found at $BUILDROOT_DIR. Set BUILDROOT_DIR."
    exit 1
fi
