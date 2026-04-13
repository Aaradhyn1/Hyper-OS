#!/usr/bin/env bash
set -Eeuo pipefail

# --- Environment & Pathing ---
export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPTS_DIR="$ROOT_DIR/scripts"
export BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
export LOG_DIR="${LOG_DIR:-$BUILD_DIR/logs}"
export ROOTFS_DIR="${ROOTFS_DIR:-$BUILD_DIR/rootfs}"
export ISO_DIR="${ISO_DIR:-$BUILD_DIR/iso_staging}"
export ISO_NAME="${ISO_NAME:-hyperos-$(date +%Y%m%d).iso}"
export ISO_PATH="$ROOT_DIR/$ISO_NAME"

# Global cleanup trap
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        printf "\n\e[31m[!] Build failed with exit code %s. Cleaning up mounts...\e[0m\n" "$exit_code"
    fi
    # Call a shared cleanup function if it exists in your lib
    if declare -f cleanup_mounts > /dev/null; then cleanup_mounts; fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

log() {
    local level="$1"
    local msg="$2"
    local color=""
    case "$level" in
        INFO)  color="\e[32m" ;;
        WARN)  color="\e[33m" ;;
        ERROR) color="\e[31m" ;;
    esac
    printf "%b%s [%s] %s\e[0m\n" "$color" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg"
}

# --- Advanced Step Runner ---
# This captures individual log files for each step AND pipes them to the master log
run_step() {
    local step_name="$1"
    local script_path="$2"
    local step_log="$LOG_DIR/${step_name// /-}.log"

    log INFO "===> [Step] $step_name"
    
    # Execute script, pipe stdout/stderr to step-specific log, and prefix for master log
    if ! "$script_path" 2>&1 | tee "$step_log"; then
        log ERROR "Step '$step_name' failed! See log: $step_log"
        return 1
    fi
    log INFO "Finished '$step_name' successfully."
}

main() {
    [[ "$EUID" -ne 0 ]] && { log ERROR "Root privileges required."; exit 1; }

    # Initialize environment
    mkdir -p "$LOG_DIR" "$BUILD_DIR" "$ROOTFS_DIR" "$ISO_DIR"
    
    # Source common library for cleanup_mounts and other shared helpers
    if [[ -f "$SCRIPTS_DIR/lib/build-common.sh" ]]; then
        source "$SCRIPTS_DIR/lib/build-common.sh"
    fi

    # --- Pipeline Execution ---
    run_step "Rootfs Bootstrap"   "$SCRIPTS_DIR/build-rootfs.sh"
    run_step "System Tuning"      "$SCRIPTS_DIR/configure-system.sh"
    run_step "Optimization"       "$SCRIPTS_DIR/optimize-systemd-services.sh"
    run_step "ISO Generation"     "$SCRIPTS_DIR/build-iso.sh"

    log INFO "=========================================="
    log INFO "Build Complete: $ISO_PATH"
    log INFO "Artifact Size: $(du -sh "$ISO_PATH" | cut -f1)"
    log INFO "=========================================="
}

main "$@"
