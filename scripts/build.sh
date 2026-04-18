#!/usr/bin/env bash
# Hyper OS Raspberry Pi Build Engine (Final)
set -Eeuo pipefail


# Paths & Config

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/configs/rpi4_hyper_defconfig}"

BUILDROOT_DIR="${BUILDROOT_DIR:-$ROOT_DIR/buildroot}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/out/rpi4}"
DL_DIR="${DL_DIR:-$ROOT_DIR/dl}"
CCACHE_DIR="${CCACHE_DIR:-$ROOT_DIR/.ccache}"
ANALYSIS_DIR="$ROOT_DIR/out/analysis"

OVERLAY_DIR="$ROOT_DIR/board/hyper-os/overlay"
POST_BUILD_SCRIPT="$ROOT_DIR/board/hyper-os/post-build.sh"

# Version pin (important)
BUILDROOT_VERSION="2023.11.x"

# Performance
JOBS="$(nproc)"
export BR2_DL_DIR="$DL_DIR"
export BR2_CCACHE_DIR="$CCACHE_DIR"

# =========================
# Logging
# =========================
log() { printf "\e[38;5;154m[HYPER-CI] [%s] %s\e[0m\n" "$(date '+%T')" "$*"; }
die() { log "FATAL: $*"; exit 1; }

# =========================
# Validation
# =========================
require_cmds() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null || die "Missing dependency: $cmd"
    done
}

validate_inputs() {
    [[ -f "$CONFIG_FILE" ]] || die "Defconfig not found: $CONFIG_FILE"
}

# =========================
# Environment Setup
# =========================
prepare_env() {
    log "Preparing environment..."

    mkdir -p "$DL_DIR" "$CCACHE_DIR" "$OUTPUT_DIR" "$ANALYSIS_DIR"

    if [[ ! -d "$BUILDROOT_DIR/.git" ]]; then
        log "Cloning Buildroot ($BUILDROOT_VERSION)..."
        git clone https://github.com/buildroot/buildroot.git "$BUILDROOT_DIR"
        git -C "$BUILDROOT_DIR" checkout "$BUILDROOT_VERSION"
    else
        log "Buildroot exists. Syncing version..."
        git -C "$BUILDROOT_DIR" fetch --depth=1 origin "$BUILDROOT_VERSION"
        git -C "$BUILDROOT_DIR" checkout "$BUILDROOT_VERSION"
    fi
}

# =========================
# Customization Hooks
# =========================
apply_customizations() {
    log "Applying Hyper OS customizations..."

    [[ -d "$OVERLAY_DIR" ]] || die "Overlay directory missing"
    [[ -f "$POST_BUILD_SCRIPT" ]] || die "Post-build script missing"

    chmod +x "$POST_BUILD_SCRIPT"
}

# =========================
# Build Pipeline
# =========================
execute_pipeline() {
    log "Loading defconfig: $(basename "$CONFIG_FILE")"

    make -C "$BUILDROOT_DIR" \
        O="$OUTPUT_DIR" \
        BR2_DEFCONFIG="$CONFIG_FILE" \
        defconfig

    log "Building system ($JOBS threads)..."

    flock "$OUTPUT_DIR/.build.lock" \
        make -C "$OUTPUT_DIR" BR2_JLEVEL="$JOBS" all
}

# =========================
# Verification
# =========================
verify_output() {
    log "Verifying build artifacts..."

    local img="$OUTPUT_DIR/images/sdcard.img"

    [[ -f "$img" ]] || die "Missing output image: $img"

    sha256sum "$img" > "$img.sha256"

    log "Image ready: $img"
}

# =========================
# Telemetry
# =========================
generate_telemetry() {
    log "Generating build analytics..."

    make -C "$OUTPUT_DIR" graph-build || true
    make -C "$OUTPUT_DIR" graph-size || true

    mv "$OUTPUT_DIR/graphs"/*.pdf "$ANALYSIS_DIR/" 2>/dev/null || true
}

# =========================
# Runtime
# =========================
main() {
    require_cmds make gcc g++ unzip bc python3 git flock sha256sum
    validate_inputs

    prepare_env
    apply_customizations
    execute_pipeline
    verify_output
    generate_telemetry

    log "SUCCESS: Deployment-ready image at $OUTPUT_DIR/images/sdcard.img"
}

main "$@"
