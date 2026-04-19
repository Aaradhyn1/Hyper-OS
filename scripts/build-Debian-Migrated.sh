#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[Titan-Build] ERROR at line $LINENO"; exit 1' ERR

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/out"
CACHE_DIR="${ROOT_DIR}/.cache"

IMAGE_NAME="Hyper-OS-Titan-$(date +%Y%m%d)"
DISTRO="debian"
RELEASE="bookworm"
ARCH="amd64"

LOG_TAG="[Titan-Build]"

log() {
    local type=$1; shift
    local color="\e[32m"
    [[ "$type" == "ERR" ]] && color="\e[31m"
    printf "${color}%s %s [%s] %s\e[0m\n" "$(date +%H:%M:%S)" "$LOG_TAG" "$type" "$*"
}

require_root() {
    [[ $EUID -eq 0 ]] || { log ERR "Run as root"; exit 1; }
}

check_deps() {
    local deps=(lb debootstrap xorriso squashfs-tools)
    for d in "${deps[@]}"; do
        command -v "$d" >/dev/null || {
            log INFO "Installing missing dependency: $d"
            apt-get update -y && apt-get install -y live-build debootstrap xorriso squashfs-tools
            break
        }
    done
}

prepare_env() {
    log INFO "Preparing build environment..."
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$CACHE_DIR"
    cd "$BUILD_DIR"
    lb clean --purge 2>/dev/null || true
}

setup_structure() {
    log INFO "Configuring live-build..."

    lb config \
        --mode debian \
        --architecture "$ARCH" \
        --distribution "$RELEASE" \
        --archive-areas "main contrib non-free non-free-firmware" \
        --debian-installer live \
        --debian-installer-distribution "$RELEASE" \
        --cache true \
        --cache-dir "$CACHE_DIR" \
        --apt-indices false \
        --apt-recommends false \
        --debootstrap-options "--variant=minbase" \
        --bootappend-live "boot=live components quiet splash loglevel=3 mitigations=off nowatchdog cpuidle.off=1 intel_pstate=performance" \
        --image-name "$IMAGE_NAME"
}

inject_packages() {
    log INFO "Injecting package set..."

    local PKG_LIST="config/package-lists/titan.list.chroot"
    mkdir -p "$(dirname "$PKG_LIST")"

    cat <<EOF > "$PKG_LIST"
kde-standard sddm plasma-nm
calamares calamares-settings-debian
tlp thermald smartmontools pciutils
zram-tools haveged
sudo curl wget micro htop
pipewire pipewire-pulse pipewire-alsa
network-manager openssh-client ca-certificates
EOF
}

inject_hooks() {
    log INFO "Injecting Titan kernel/system hooks..."

    local HOOK="config/hooks/live/99-titan-engine.chroot"
    mkdir -p "$(dirname "$HOOK")"

    cat <<'EOF' > "$HOOK"
#!/bin/sh
set -e

# SYSCTL
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

# LIMITS
cat <<EOT > /etc/security/limits.d/99-titan.conf
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOT

# ZRAM
echo "ALGO=zstd" > /etc/default/zramswap
echo "PERCENT=60" >> /etc/default/zramswap

# SERVICES
systemctl enable tlp || true
systemctl enable haveged || true
systemctl enable systemd-zram-setup@zram0 || true

# UDEV I/O SCHEDULER
cat <<EOT > /etc/udev/rules.d/60-titan-io.rules
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
EOT

# CPU PERFORMANCE
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  echo performance > "$gov" 2>/dev/null || true
done

# THP
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true

exit 0
EOF

    chmod +x "$HOOK"
}

build_iso() {
    log INFO "Building ISO..."
    lb build 2>&1 | tee "$ROOT_DIR/build.log"
}

finalize() {
    log INFO "Finalizing build output..."
    mkdir -p "$OUTPUT_DIR"

    local iso
    iso=$(ls ./*.iso 2>/dev/null | head -n1 || true)

    [[ -f "$iso" ]] || { log ERR "ISO not found"; exit 1; }

    mv "$iso" "$OUTPUT_DIR/${IMAGE_NAME}.iso"
    sha256sum "$OUTPUT_DIR/${IMAGE_NAME}.iso" > "$OUTPUT_DIR/${IMAGE_NAME}.sha256"

    log INFO "ISO ready: $OUTPUT_DIR/${IMAGE_NAME}.iso"
}

main() {
    require_root
    check_deps
    prepare_env
    setup_structure
    inject_packages
    inject_hooks
    build_iso
    finalize
    log INFO "Titan build pipeline complete."
}

main "$@"
