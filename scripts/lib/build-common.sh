#!/usr/bin/env bash
set -Eeuo pipefail

# --- Enterprise Configuration ---
export IDENTIFIER="hyper-core-$(date +%s)"
export WORKSPACE="${WORKSPACE:-/tmp/$IDENTIFIER}"
export SHM_SIZE="${SHM_SIZE:-2G}" # Speed up builds with RAM-backed storage

# --- Advanced Isolation (The "Sandbox" Logic) ---
# Uses unshare to create a private mount namespace
isolate_namespace() {
    if [[ "${NS_ISOLATED:-}" != "true" ]]; then
        log INFO "Spawning isolated mount namespace..."
        export NS_ISOLATED=true
        # -m: Private mount namespace | -u: Private UTS (hostname) namespace
        exec unshare -m -u --map-root-user "$BASH_SOURCE" "$@"
    fi
}

# --- Snapshotting with OverlayFS ---
# Allows you to "undo" changes to your rootfs instantly
setup_overlay() {
    log INFO "Initializing OverlayFS Layer..."
    mkdir -p "$WORKSPACE"/{lower,upper,work,merged}
    
    # 'lower' is your read-only base; 'upper' is where changes are written
    # This prevents accidental modification of your golden image base
    mount -t overlay overlay \
        -o lowerdir="$ROOTFS_DIR",upperdir="$WORKSPACE/upper",workdir="$WORKSPACE/work" \
        "$WORKSPACE/merged"
    
    # Update global path to point to the virtual merged layer
    export TARGET_DIR="$WORKSPACE/merged"
}

# --- Atomic Chroot Execution ---
# Runs a command inside the chroot and ensures it cannot escape
chroot_exec() {
    local cmd="$*"
    log INFO "Executing inside Jail: $cmd"
    
    # Use 'systemd-run' to cap CPU/RAM so the build doesn't freeze the host
    systemd-run --scope -p MemoryMax=4G -p CPUQuota=80% \
        chroot "$TARGET_DIR" /bin/bash -c "
            export HOME=/root
            export LC_ALL=C.UTF-8
            source /etc/profile
            $cmd
        "
}

# --- Virtual Hardware Injection ---
# Injects fake hardware info so the build doesn't try to touch host firmware
mock_hardware() {
    log INFO "Mocking hardware interfaces..."
    mkdir -p "$TARGET_DIR/sys/class/dmi/id"
    echo "Hyper-OS-Virtual-Platform" > "$TARGET_DIR/sys/class/dmi/id/product_name"
    
    # Prevent the chroot from starting real services
    cat <<EOF > "$TARGET_DIR/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
EOF
    chmod +x "$TARGET_DIR/usr/sbin/policy-rc.d"
}

# --- Enhanced Error Telemetry ---
dump_debug_info() {
    log WARN "Generating post-mortem diagnostics..."
    df -h "$TARGET_DIR"
    grep "$TARGET_DIR" /proc/mounts > "$LOG_DIR/mount_leak.log" || true
}

# --- Execution ---
main() {
    setup_build_env
    isolate_namespace "$@"
    
    # 1. Validation
    require_cmds systemd-run unshare mount chroot
    
    # 2. Virtualization Layer
    setup_overlay
    mount_chroot_fs "$TARGET_DIR"
    mock_hardware
    
    # 3. Task Execution Example
    chroot_exec "apt-get update && apt-get install -y linux-image-amd64"
    
    log INFO "Build Phase Finished Successfully."
}

# Trigger main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
