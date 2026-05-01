#!/usr/bin/env bash
# Hyper OS Isolated Build Engin
set -Eeuo pipefail
trap 'echo "[Hyper-Core] ERROR at line $LINENO"; exit 1' ERR

# =========================
# Environment
# =========================
export IDENTIFIER="hyper-core-$(date +%s)"
export WORKSPACE="${WORKSPACE:-/tmp/$IDENTIFIER}"
export SHM_SIZE="${SHM_SIZE:-2G}"
export TARGET_DIR=""
export LOG_DIR="${LOG_DIR:-$WORKSPACE/logs}"

LOG_TAG="[Hyper-Core]"

log() {
    local lvl=$1; shift
    printf '%s %s [%s] %s\n' "$(date '+%H:%M:%S')" "$LOG_TAG" "$lvl" "$*"
}

die() { log ERR "$*"; exit 1; }

# =========================
# Namespace Isolation
# =========================
isolate_namespace() {
    if [[ "${NS_ISOLATED:-}" != "true" ]]; then
        log INFO "Spawning isolated namespace..."
        export NS_ISOLATED=true
        exec unshare -m -u -i -p --fork --mount-proc --map-root-user "$BASH_SOURCE" "$@"
    fi
}

# =========================
# OverlayFS Snapshot Layer
# =========================
setup_overlay() {
    log INFO "Initializing OverlayFS..."

    mkdir -p "$WORKSPACE"/{lower,upper,work,merged,logs}
    mount --bind "$ROOTFS_DIR" "$WORKSPACE/lower"

    mount -t overlay overlay \
        -o lowerdir="$WORKSPACE/lower",upperdir="$WORKSPACE/upper",workdir="$WORKSPACE/work" \
        "$WORKSPACE/merged"

    export TARGET_DIR="$WORKSPACE/merged"
}

# =========================
# Mount Essentials
# =========================
mount_chroot_fs() {
    log INFO "Mounting chroot filesystems..."

    mkdir -p "$TARGET_DIR"/{proc,sys,dev,dev/pts}

    mount --bind /dev "$TARGET_DIR/dev"
    mount --bind /dev/pts "$TARGET_DIR/dev/pts"
    mount -t proc proc "$TARGET_DIR/proc"
    mount -t sysfs sys "$TARGET_DIR/sys"
}

cleanup_mounts() {
    log INFO "Cleaning mounts..."

    mount | grep "$WORKSPACE" | awk '{print $3}' | tac | xargs -r umount -lf || true
}
trap cleanup_mounts EXIT

# =========================
# Controlled Execution
# =========================
chroot_exec() {
    local cmd="$*"
    log INFO "Executing: $cmd"

    systemd-run --quiet --wait --collect \
        -p MemoryMax=4G \
        -p CPUQuota=80% \
        -p TasksMax=512 \
        chroot "$TARGET_DIR" /bin/bash -c "
            set -Eeuo pipefail
            export HOME=/root
            export LC_ALL=C.UTF-8
            source /etc/profile || true
            $cmd
        "
}

# =========================
# Hardware Mocking
# =========================
mock_hardware() {
    log INFO "Mocking hardware..."

    mkdir -p "$TARGET_DIR/sys/class/dmi/id"
    echo "Hyper-OS-Virtual" > "$TARGET_DIR/sys/class/dmi/id/product_name"

    cat > "$TARGET_DIR/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
    chmod +x "$TARGET_DIR/usr/sbin/policy-rc.d"
}

# =========================
# Diagnostics
# =========================
dump_debug_info() {
    log WARN "Collecting diagnostics..."

    mkdir -p "$LOG_DIR"

    df -h "$TARGET_DIR" > "$LOG_DIR/disk_usage.log" || true
    mount | grep "$WORKSPACE" > "$LOG_DIR/mounts.log" || true
    dmesg | tail -n 50 > "$LOG_DIR/dmesg.log" || true
}

# =========================
# Validation
# =========================
require_cmds() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null || die "Missing dependency: $cmd"
    done
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root"
}

# =========================
# Main Execution
# =========================
main() {
    require_root
    require_cmds unshare systemd-run mount chroot

    [[ -d "${ROOTFS_DIR:-}" ]] || die "ROOTFS_DIR not set or missing"

    mkdir -p "$WORKSPACE"

    isolate_namespace "$@"

    log INFO "Initializing workspace: $WORKSPACE"

    setup_overlay
    mount_chroot_fs
    mock_hardware

    # Example workload
    chroot_exec "apt-get update && apt-get install -y linux-image-amd64"

    log INFO "Build completed successfully."
}

main "$@"
