#!/usr/bin/env bash
# Hyper OS Buildroot Engine - Advanced CI Edition
set -Eeuo pipefail

# =========================
# Global Safety + Debug
# =========================
trap 'on_error $LINENO' ERR
trap cleanup EXIT

on_error() {
    local line=$1
    echo -e "\e[31m[HYPER-CI] ❌ FAILURE at line $line\e[0m"
    echo "[HYPER-CI] Dumping last 50 log lines..."
    tail -n 50 "$LOG_FILE" || true
    exit 1
}

# =========================
# Determinism Layer
# =========================
export LC_ALL=C
export LANG=C
export TZ=UTC
umask 022

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
LOG_DIR="$ROOT_DIR/out/logs"

OVERLAY_DIR="${OVERLAY_DIR:-$ROOT_DIR/overlay}"
POST_BUILD_SCRIPT="${POST_BUILD_SCRIPT:-$ROOT_DIR/post-build.sh}"

BUILDROOT_VERSION="2023.11.x"
JOBS="${JOBS:-$(nproc)}"

export BR2_DL_DIR="$DL_DIR"
export BR2_CCACHE_DIR="$CCACHE_DIR"

BUILD_EPOCH="${SOURCE_DATE_EPOCH:-$(date -u +%s)}"
LOG_FILE="$LOG_DIR/build_${BUILD_EPOCH}.log"
mkdir -p "$LOG_DIR"

LOG_TAG="[HYPER-CI]"

# =========================
# Logging System
# =========================
log() {
    local level=$1; shift
    local color="\e[38;5;45m"

    case "$level" in
        INFO) color="\e[38;5;45m" ;;
        WARN) color="\e[33m" ;;
        ERR)  color="\e[31m" ;;
    esac

    printf "${color}%s %s [%s] %s\e[0m\n" \
        "$(date '+%T')" "$LOG_TAG" "$level" "$*" | tee -a "$LOG_FILE"
}

die() { log ERR "$*"; exit 1; }

utc_date() {
    local fmt=$1
    date -u -d "@$BUILD_EPOCH" +"$fmt"
}

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
# Git Sync (Atomic)
# =========================
sync_buildroot() {
    log INFO "Syncing Buildroot ($BUILDROOT_VERSION)..."

    if [[ ! -d "$BUILDROOT_DIR/.git" ]]; then
        git clone --depth=1 --branch "$BUILDROOT_VERSION" \
            https://github.com/buildroot/buildroot.git "$BUILDROOT_DIR"
    else
        git -C "$BUILDROOT_DIR" fetch --depth=1 origin "$BUILDROOT_VERSION"
        git -C "$BUILDROOT_DIR" checkout "$BUILDROOT_VERSION"
        git -C "$BUILDROOT_DIR" reset --hard "origin/$BUILDROOT_VERSION"
        git -C "$BUILDROOT_DIR" clean -fdx
    fi
}

# =========================
# Immutable Config Handling
# =========================
prepare_config() {
    log INFO "Preparing isolated config..."

    mkdir -p "$OUTPUT_DIR"
    cp "$CONFIG_FILE" "$OUTPUT_DIR/.config"

    # Inject safely (no mutation of source config)
    {
        echo "BR2_ROOTFS_OVERLAY=\"$OVERLAY_DIR\""
        [[ -f "$POST_BUILD_SCRIPT" ]] && \
        echo "BR2_ROOTFS_POST_BUILD_SCRIPT=\"$POST_BUILD_SCRIPT\""
    } >> "$OUTPUT_DIR/.config"
}

# =========================
# Build Execution
# =========================
execute_pipeline() {
    log INFO "Running defconfig..."

    make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR" olddefconfig >>"$LOG_FILE" 2>&1

    log INFO "Starting build with $JOBS threads..."

    local start_time=$(date +%s)

    flock "$OUTPUT_DIR/.lock" \
        make -C "$OUTPUT_DIR" BR2_JLEVEL="$JOBS" all \
        >>"$LOG_FILE" 2>&1

    local end_time=$(date +%s)
    BUILD_DURATION=$((end_time - start_time))

    log INFO "Build completed in ${BUILD_DURATION}s"
}

# =========================
# Artifact Verification
# =========================
verify_output() {
    log INFO "Verifying artifacts..."

    local img
    img=$(find "$OUTPUT_DIR/images" -type f \
        \( -name "*.img" -o -name "*.iso" -o -name "*.ext4" \) | head -n1 || true)

    [[ -n "$img" ]] || die "No output image found"

    sha256sum "$img" > "$img.sha256"

    ARTIFACT="$img"
    log INFO "Artifact: $ARTIFACT"
}

# =========================
# Telemetry + Metrics
# =========================
generate_telemetry() {
    log INFO "Generating analytics..."

    make -C "$OUTPUT_DIR" graph-build >>"$LOG_FILE" 2>&1 || true
    make -C "$OUTPUT_DIR" graph-size >>"$LOG_FILE" 2>&1 || true

    mkdir -p "$ANALYSIS_DIR"
    mv "$OUTPUT_DIR/graphs"/*.pdf "$ANALYSIS_DIR/" 2>/dev/null || true

    cat <<EOF > "$ANALYSIS_DIR/build-meta.json"
{
  "timestamp": "$(utc_date "%Y-%m-%dT%H:%M:%SZ")",
  "source_date_epoch": $BUILD_EPOCH,
  "duration_sec": $BUILD_DURATION,
  "jobs": $JOBS,
  "buildroot_version": "$BUILDROOT_VERSION",
  "artifact": "$(basename "$ARTIFACT")"
}
EOF
}

# =========================
# Cleanup
# =========================
cleanup() {
    log INFO "Cleaning temporary files..."
    find "$OUTPUT_DIR" -name "*.stamp" -delete 2>/dev/null || true
}

# =========================
# Entry
# =========================
main() {
    require_cmds make gcc g++ unzip bc python3 git flock sha256sum

    validate_inputs
    sync_buildroot
    prepare_config
    execute_pipeline
    verify_output
    generate_telemetry

    log INFO "✅ SUCCESS → $OUTPUT_DIR/images"
}

main "$@"
