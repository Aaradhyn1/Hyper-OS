#!/usr/bin/env bash
# Hyper OS Raspberry Pi Advanced Build Engine
set -Eeuo pipefail

# --- Configuration & Environment ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/configs/rpi4_hyper_defconfig}"
BUILDROOT_DIR="${BUILDROOT_DIR:-$ROOT_DIR/buildroot}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/out/rpi4}"
DL_DIR="${DL_DIR:-$ROOT_DIR/dl}"
CCACHE_DIR="${CCACHE_DIR:-$ROOT_DIR/.ccache}"
OVERLAY_DIR="$ROOT_DIR/board/hyper-os/overlay"
POST_BUILD_SCRIPT="$ROOT_DIR/board/hyper-os/post-build.sh"

# Performance Tuning
JOBS=$(nproc)
export BR2_DL_DIR="$DL_DIR"
export BR2_CCACHE_DIR="$CCACHE_DIR"

log() { printf "\e[38;5;154m[HYPER-CI] [%s] %s\e[0m\n" "$(date '+%T')" "$1"; }

# --- Build Engine ---

prepare_env() {
    log "Synchronizing build dependencies..."
    mkdir -p "$DL_DIR" "$CCACHE_DIR" "$OUTPUT_DIR"
    
    # Advanced: Auto-clone Buildroot if missing
    if [ ! -d "$BUILDROOT_DIR/.git" ]; then
        log "Buildroot source missing. Cloning stable LTS branch..."
        git clone --depth 1 --branch 2023.11.x https://github.com "$BUILDROOT_DIR"
    fi
}

apply_customizations() {
    log "Injecting Hyper OS overlays and patches..."
    # Ensure post-build script is executable
    [[ -f "$POST_BUILD_SCRIPT" ]] && chmod +x "$POST_BUILD_SCRIPT"
    
    # Logic to sync custom kernel patches if they exist
    if [ -d "$ROOT_DIR/patches/linux" ]; then
        log "Custom kernel patches detected. Mapping to Buildroot..."
        # This assumes your defconfig points to this directory
    fi
}

execute_pipeline() {
    log "Generating configuration from: $(basename "$CONFIG_FILE")"
    
    # O= allows building outside the source tree to keep it clean
    make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR" BR2_DEFCONFIG="$CONFIG_FILE" defconfig

    log "Building toolchain and system image ($JOBS threads)..."
    # use 'flock' to prevent concurrent builds in the same output dir
    flock "$OUTPUT_DIR/.build.lock" make -C "$OUTPUT_DIR" BR2_JLEVEL="$JOBS" all
}

generate_telemetry() {
    log "Post-build Analysis..."
    # Generate a graph of build times for each package
    make -C "$OUTPUT_DIR" graph-build
    # Generate a size map to see what's bloating the rootfs
    make -C "$OUTPUT_DIR" graph-size
    
    mv "$OUTPUT_DIR/graphs"/*.pdf "$ROOT_DIR/out/analysis/" 2>/dev/null || true
}

# --- Runtime ---

main() {
    # Check for required tools
    local REQS=(make gcc g++ unzip bc python3)
    for tool in "${REQS[@]}"; do
        command -v "$tool" >/dev/null || { log "ERROR: $tool is missing"; exit 1; }
    done

    prepare_env
    apply_customizations
    execute_pipeline
    generate_telemetry
    
    log "Deployment-ready image: $OUTPUT_DIR/images/sdcard.img"
}

main "$@"
