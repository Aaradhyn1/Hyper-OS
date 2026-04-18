#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Error on line $LINENO"' ERR

CONFIG_SRC="./configs/performance"
TARGET_DIR="/etc"
LOG_TAG="[HyperOS-Titan]"

log() {
  printf '%s %s %s\n' "$(date '+%H:%M:%S')" "$LOG_TAG" "$1"
}

if [[ "$EUID" -ne 0 ]]; then 
  exit 1
fi

for cfg in sysctl.conf systemd.conf journald.conf; do
  [[ -f "$CONFIG_SRC/$cfg" ]] || exit 1
done

log "Applying System Stack..."
install -D -m 0644 "$CONFIG_SRC/sysctl.conf" "$TARGET_DIR/sysctl.d/99-hyperos.conf"
install -D -m 0644 "$CONFIG_SRC/systemd.conf" "$TARGET_DIR/systemd/system.conf.d/10-hyperos.conf"
install -D -m 0644 "$CONFIG_SRC/journald.conf" "$TARGET_DIR/systemd/journald.conf.d/10-hyperos.conf"

cat <<EOF > /etc/security/limits.d/99-hyperos.conf
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOF

cat <<EOF > /etc/sysctl.d/99-hyperos-ultra.conf
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000
kernel.sched_migration_cost_ns = 500000
kernel.nmi_watchdog = 0
vm.swappiness = 1
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.mmap_min_addr = 4096
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
EOF
sysctl -p /etc/sysctl.d/99-hyperos-ultra.conf

echo "madvise" > /sys/kernel/mm/transparent_hugepage/enabled || true
echo "never" > /sys/kernel/mm/transparent_hugepage/defrag || true

SERVICES_TO_STRIP=(
  apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer
  man-db.timer e2scrub_all.timer motd-news.timer bluetooth.service 
  ModemManager.service avahi-daemon.service cups.service 
  udisks2.service fwupd.service packagekit.service
  gssproxy.service rpcbind.service rpcbind.socket
)

for unit in "${SERVICES_TO_STRIP[@]}"; do
  systemctl disable --now "$unit" 2>/dev/null || true
  systemctl mask "$unit" 2>/dev/null || true
done

if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then 
    echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null || true
fi

for dev in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
    [[ "${dev}" == *"state0"* ]] && continue
    echo 1 > "$dev" 2>/dev/null || true
done

for dev in /sys/block/sd* /sys/block/nvme*; do
    [ -e "$dev/queue/scheduler" ] || continue
    [[ "$dev" == *"nvme"* ]] && echo "none" > "$dev/queue/scheduler" || echo "mq-deadline" > "$dev/queue/scheduler"
    echo 2 > "$dev/queue/nomerges" 2>/dev/null || true
    echo 0 > "$dev/queue/add_random" 2>/dev/null || true
    echo 1 > "$dev/queue/rq_affinity" 2>/dev/null || true
done

if command -v setpci >/dev/null; then
    setpci -v -d *:* 68.w=5910 2>/dev/null || true
fi

systemctl daemon-reload
systemctl restart systemd-journald
log "Deployment Complete."
