#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE_DIR="$ROOT_DIR/hyperos"
WORK_DIR="$ROOT_DIR/work"
OUT_DIR="$ROOT_DIR/out"

[[ $EUID -ne 0 ]] && { echo "Root required" >&2; exit 1; }

for cmd in mkarchiso pacstrap; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd is required" >&2; exit 1; }
done

mkdir -p "$PROFILE_DIR/airootfs/etc/sysctl.d"
mkdir -p "$PROFILE_DIR/airootfs/etc/security/limits.d"

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

cat <<EOF > "$PROFILE_DIR/airootfs/etc/security/limits.d/99-titan.conf"
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOF

cat <<EOF > "$PROFILE_DIR/packages.x86_64"
base
linux-zen
linux-zen-headers
linux-firmware
plasma-desktop
sddm
networkmanager
pciutils
haveged
htop
micro
EOF

grep -q "mitigations=off" "$PROFILE_DIR/airootfs/etc/default/grub" 2>/dev/null || \
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="mitigations=off nowatchdog cpuidle.off=1 intel_pstate=performance /' "$PROFILE_DIR/airootfs/etc/default/grub" 2>/dev/null || true

rm -rf "$WORK_DIR"
mkdir -p "$OUT_DIR"

cd "$ROOT_DIR"
mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"
