#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/out"

IMAGE_NAME="Hyper-OS-Titan-$(date +%Y%m%d)"
DISTRO="debian" 
RELEASE="bookworm"
ARCH="amd64"

log() {
    local type=$1; shift
    local color="\e[32m"
    [[ "$type" == "ERR" ]] && color="\e[31m"
    printf "${color}[%s] [%s] %s\e[0m\n" "$(date +%H:%M:%S)" "$type" "$*"
}

setup_structure() {
    log INFO "Initializing Titan Build structure..."
    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"
    
    lb config \
        --distribution "$RELEASE" \
        --archive-areas "main contrib non-free non-free-firmware" \
        --debian-installer live \
        --debian-installer-distribution "$RELEASE" \
        --cache true \
        --apt-indices false \
        --apt-recommends false \
        --debootstrap-options "--variant=minbase" \
        --bootappend-live "boot=live components quiet splash loglevel=3 mitigations=off nowatchdog cpuidle.off=1 intel_pstate=performance" \
        --image-name "$IMAGE_NAME"
}

inject_packages() {
    log INFO "Injecting High-Performance Package Set..."
    local PKG_LIST="config/package-lists/titan.list.chroot"
    mkdir -p "$(dirname "$PKG_LIST")"

    cat <<EOF > "$PKG_LIST"
kde-plasma-desktop sddm plasma-nm
calamares-settings-debian calamares
tlp thermald smartmontools pciutils
zram-tools haveged
sudo curl wget micro htop
pipewire pipewire-pulse pipewire-alsa
EOF
}

inject_titan_optimizations() {
    log INFO "Injecting Deterministic Kernel Hooks..."
    local HOOK="config/hooks/live/99-titan-engine.chroot"
    mkdir -p "$(dirname "$HOOK")"

    cat <<'EOF' > "$HOOK"
#!/bin/sh
set -e

cat <<EOT > /etc/sysctl.d/99-titan.conf
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000
kernel.sched_migration_cost_ns = 500000
kernel.nmi_watchdog = 0
vm.swappiness = 1
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
EOT

echo "ALGO=zstd" > /etc/default/zramswap
echo "PERCENT=60" >> /etc/default/zramswap

cat <<EOT > /etc/security/limits.d/99-titan.conf
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOT

systemctl enable tlp
systemctl enable haveged

cat <<EOT > /etc/udev/rules.d/60-titan-schedulers.rules
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
EOT
EOF
    chmod +x "$HOOK"
}

main() {
    [[ $EUID -ne 0 ]] && { log ERR "Root required"; exit 1; }

    command -v lb >/dev/null || apt-get install -y live-build debootstrap

    setup_structure
    inject_packages
    inject_titan_optimizations
    
    log INFO "Compiling Titan ISO..."
    lb build 2>&1 | tee "$ROOT_DIR/build.log"

    mkdir -p "$OUTPUT_DIR"
    mv *.iso "$OUTPUT_DIR/${IMAGE_NAME}.iso" 2>/dev/null || true
    log INFO "Build success: $OUTPUT_DIR"
}

main "$@"
