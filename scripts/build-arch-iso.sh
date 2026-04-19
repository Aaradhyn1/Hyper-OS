#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[Titan-ArchISO] ERROR at line $LINENO"; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_DIR="$ROOT_DIR/hyperos"
WORK_DIR="$ROOT_DIR/work"
OUT_DIR="$ROOT_DIR/out"
CACHE_DIR="$ROOT_DIR/.cache"

LOG_TAG="[Titan-ArchISO]"

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
    local deps=(mkarchiso pacstrap arch-chroot)
    for d in "${deps[@]}"; do
        command -v "$d" >/dev/null || {
            log ERR "Missing dependency: $d"
            exit 1
        }
    done
}

prepare_dirs() {
    log INFO "Preparing directories..."
    rm -rf "$WORK_DIR"
    mkdir -p "$PROFILE_DIR/airootfs/etc/sysctl.d"
    mkdir -p "$PROFILE_DIR/airootfs/etc/security/limits.d"
    mkdir -p "$PROFILE_DIR/airootfs/etc/systemd/system"
    mkdir -p "$OUT_DIR" "$CACHE_DIR"
}

inject_sysctl() {
    log INFO "Injecting sysctl tuning..."
    cat <<EOF > "$PROFILE_DIR/airootfs/etc/sysctl.d/99-titan-ultra.conf"
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
EOF
}

inject_limits() {
    log INFO "Injecting limits..."
    cat <<EOF > "$PROFILE_DIR/airootfs/etc/security/limits.d/99-titan.conf"
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOF
}

inject_packages() {
    log INFO "Injecting package list..."
    cat <<EOF > "$PROFILE_DIR/packages.x86_64"
base
base-devel
linux-zen
linux-zen-headers
linux-firmware
plasma
sddm
networkmanager
pciutils
haveged
htop
micro
sudo
curl
wget
zram-generator
EOF
}

inject_services() {
    log INFO "Enabling services..."
    mkdir -p "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants"

    ln -sf /usr/lib/systemd/system/NetworkManager.service \
        "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service"

    ln -sf /usr/lib/systemd/system/sddm.service \
        "$PROFILE_DIR/airootfs/etc/systemd/system/display-manager.service"

    ln -sf /usr/lib/systemd/system/haveged.service \
        "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants/haveged.service"
}

inject_zram() {
    log INFO "Configuring ZRAM..."
    mkdir -p "$PROFILE_DIR/airootfs/etc/systemd/zram-generator.conf.d"
    cat <<EOF > "$PROFILE_DIR/airootfs/etc/systemd/zram-generator.conf.d/titan.conf"
[zram0]
zram-size = ram * 0.6
compression-algorithm = zstd
EOF
}

inject_boot_params() {
    log INFO "Injecting boot parameters..."
    mkdir -p "$PROFILE_DIR/airootfs/etc/default"

    cat <<EOF > "$PROFILE_DIR/airootfs/etc/default/grub"
GRUB_DEFAULT=0
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR="HyperOS Titan"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash mitigations=off nowatchdog cpuidle.off=1 intel_pstate=performance"
GRUB_CMDLINE_LINUX=""
EOF
}

build_iso() {
    log INFO "Building Arch ISO..."
    mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"
}

finalize() {
    log INFO "Build complete."
    ls -lh "$OUT_DIR"
}

main() {
    require_root
    check_deps
    prepare_dirs
    inject_sysctl
    inject_limits
    inject_packages
    inject_services
    inject_zram
    inject_boot_params
    build_iso
    finalize
}

main "$@"
