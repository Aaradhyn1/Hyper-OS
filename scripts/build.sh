#!/usr/bin/env bash
# Hyper OS Buildroot Engine (Generic / Platform-Agnostic)
set -Eeuo pipefail
trap 'echo "[HYPER-CI] FATAL at line $LINENO"; exit 1' ERR

# =========================
# Paths & Config
# =========================
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${1:-$ROOT_DIR/configs/hyper_defconfig}"

BUILDROOT_DIR="${BUILDROOT_DIR:-$ROOT_DIR/buildroot}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/out/buildroot}"
DL_DIR="${DL_DIR:-$ROOT_DIR/dl}"
CCACHE_DIR="${CCACHE_DIR:-$ROOT_DIR/.ccache}"
ANALYSIS_DIR="$ROOT_DIR/out/analysis"

OVERLAY_DIR="${OVERLAY_DIR:-$ROOT_DIR/overlay}"
POST_BUILD_SCRIPT="${POST_BUILD_SCRIPT:-$ROOT_DIR/post-build.sh}"

BUILDROOT_VERSION="2023.11.x"

JOBS="$(nproc)"
export BR2_DL_DIR="$DL_DIR"
export BR2_CCACHE_DIR="$CCACHE_DIR"

LOG_TAG="[HYPER-CI]"

# =========================
# Logging
# =========================
log() {
    local level=$1; shift
    local color="\e[38;5;154m"
    [[ "$level" == "ERR" ]] && color="\e[31m"
    printf "${color}%s %s [%s] %s\e[0m\n" "$(date '+%T')" "$LOG_TAG" "$level" "$*"
}

die() { log ERR "$*"; exit 1; }

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
    log INFO "Preparing environment..."

    mkdir -p "$DL_DIR" "$CCACHE_DIR" "$OUTPUT_DIR" "$ANALYSIS_DIR"

    if [[ ! -d "$BUILDROOT_DIR/.git" ]]; then
        log INFO "Cloning Buildroot ($BUILDROOT_VERSION)..."
        git clone --depth=1 --branch "$BUILDROOT_VERSION" https://github.com/buildroot/buildroot.git "$BUILDROOT_DIR"
    else
        log INFO "Syncing Buildroot..."
        git -C "$BUILDROOT_DIR" fetch --depth=1 origin "$BUILDROOT_VERSION"
        git -C "$BUILDROOT_DIR" checkout "$BUILDROOT_VERSION"
        git -C "$BUILDROOT_DIR" reset --hard "origin/$BUILDROOT_VERSION"
    fi
}

# =========================
# Customization Hooks
# =========================
apply_customizations() {
    log INFO "Applying Hyper OS customizations..."

    [[ -d "$OVERLAY_DIR" ]] && \
        grep -q "BR2_ROOTFS_OVERLAY" "$CONFIG_FILE" || \
        echo "BR2_ROOTFS_OVERLAY=\"$OVERLAY_DIR\"" >> "$CONFIG_FILE"

    if [[ -f "$POST_BUILD_SCRIPT" ]]; then
        chmod +x "$POST_BUILD_SCRIPT"
        grep -q "BR2_ROOTFS_POST_BUILD_SCRIPT" "$CONFIG_FILE" || \
        echo "BR2_ROOTFS_POST_BUILD_SCRIPT=\"$POST_BUILD_SCRIPT\"" >> "$CONFIG_FILE"
    fi
}

# =========================
# Build Pipeline
# =========================
execute_pipeline() {
    log INFO "Loading defconfig: $(basename "$CONFIG_FILE")"

    make -C "$BUILDROOT_DIR" \
        O="$OUTPUT_DIR" \
        BR2_DEFCONFIG="$CONFIG_FILE" \
        defconfig

    log INFO "Starting build ($JOBS threads)..."

    flock "$OUTPUT_DIR/.build.lock" \
        make -C "$OUTPUT_DIR" BR2_JLEVEL="$JOBS" all
}

# =========================
# Verification
# =========================
verify_output() {
    log INFO "Verifying build artifacts..."

    local img
    img=$(find "$OUTPUT_DIR/images" -type f \( -name "*.img" -o -name "*.iso" -o -name "*.ext4" \) | head -n1 || true)

    [[ -n "$img" ]] || die "No output image found"

    sha256sum "$img" > "$img.sha256"

    log INFO "Image ready: $img"
}

# =========================
# Telemetry
# =========================
generate_telemetry() {
    log INFO "Generating build analytics..."

    make -C "$OUTPUT_DIR" graph-build || true
    make -C "$OUTPUT_DIR" graph-size || true

    mkdir -p "$ANALYSIS_DIR"
    mv "$OUTPUT_DIR/graphs"/*.pdf "$ANALYSIS_DIR/" 2>/dev/null || true
}

# =========================
# Cleanup
# =========================
cleanup() {
    log INFO "Cleaning temp artifacts..."
    find "$OUTPUT_DIR" -name "*.stamp" -delete 2>/dev/null || true
}
trap cleanup EXIT

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

    log INFO "SUCCESS: Build complete → $OUTPUT_DIR/images"
}

main "$@"
