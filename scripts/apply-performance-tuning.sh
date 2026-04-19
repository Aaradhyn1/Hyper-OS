#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[HyperOS-Titan] ERROR at line $LINENO"; exit 1' ERR

LOG_TAG="[HyperOS-Titan]"
CONFIG_SRC="./configs/performance"
TARGET_DIR="/etc"
BACKUP_DIR="/var/backups/hyperos/$(date +%s)"

log() { printf '%s %s %s\n' "$(date '+%H:%M:%S')" "$LOG_TAG" "$1"; }

require_root() {
  [[ "$EUID" -eq 0 ]] || { log "Must run as root"; exit 1; }
}

check_deps() {
  for cmd in install sysctl systemctl; do
    command -v "$cmd" >/dev/null || { log "Missing dependency: $cmd"; exit 1; }
  done
}

backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  mkdir -p "$BACKUP_DIR"
  cp -a "$file" "$BACKUP_DIR/"
}

safe_write() {
  local target="$1"
  local tmp
  tmp=$(mktemp)
  cat > "$tmp"
  backup_file "$target"
  install -D -m 0644 "$tmp" "$target"
  rm -f "$tmp"
}

require_root
check_deps

for cfg in sysctl.conf systemd.conf journald.conf; do
  [[ -f "$CONFIG_SRC/$cfg" ]] || { log "Missing config: $cfg"; exit 1; }
done

log "Applying system configs..."

backup_file "$TARGET_DIR/sysctl.d/99-hyperos.conf"
backup_file "$TARGET_DIR/systemd/system.conf.d/10-hyperos.conf"
backup_file "$TARGET_DIR/systemd/journald.conf.d/10-hyperos.conf"

install -D -m 0644 "$CONFIG_SRC/sysctl.conf" "$TARGET_DIR/sysctl.d/99-hyperos.conf"
install -D -m 0644 "$CONFIG_SRC/systemd.conf" "$TARGET_DIR/systemd/system.conf.d/10-hyperos.conf"
install -D -m 0644 "$CONFIG_SRC/journald.conf" "$TARGET_DIR/systemd/journald.conf.d/10-hyperos.conf"

log "Applying limits..."
safe_write /etc/security/limits.d/99-hyperos.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOF

log "Applying sysctl tuning..."
safe_write /etc/sysctl.d/99-hyperos-ultra.conf <<EOF
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

sysctl --system >/dev/null

log "Configuring memory subsystem..."
[[ -f /sys/kernel/mm/transparent_hugepage/enabled ]] && echo madvise > /sys/kernel/mm/transparent_hugepage/enabled || true
[[ -f /sys/kernel/mm/transparent_hugepage/defrag ]] && echo never > /sys/kernel/mm/transparent_hugepage/defrag || true

SERVICES_TO_STRIP=(
  apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer
  man-db.timer e2scrub_all.timer motd-news.timer bluetooth.service
  ModemManager.service avahi-daemon.service cups.service
  udisks2.service fwupd.service packagekit.service
  gssproxy.service rpcbind.service rpcbind.socket
)

log "Disabling unnecessary services..."
for unit in "${SERVICES_TO_STRIP[@]}"; do
  systemctl disable --now "$unit" 2>/dev/null || true
  systemctl mask "$unit" 2>/dev/null || true
done

log "Setting CPU governor..."
if compgen -G "/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor" > /dev/null; then
  for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance > "$gov" 2>/dev/null || true
  done
fi

log "Disabling deep C-states..."
for dev in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
  [[ "$dev" == *state0* ]] && continue
  echo 1 > "$dev" 2>/dev/null || true
done

log "Optimizing block devices..."
for dev in /sys/block/*; do
  [[ -e "$dev/queue/scheduler" ]] || continue
  case "$dev" in
    *nvme*) echo none > "$dev/queue/scheduler" ;;
    *) echo mq-deadline > "$dev/queue/scheduler" ;;
  esac
  echo 2 > "$dev/queue/nomerges" 2>/dev/null || true
  echo 0 > "$dev/queue/add_random" 2>/dev/null || true
  echo 1 > "$dev/queue/rq_affinity" 2>/dev/null || true
done

if command -v setpci >/dev/null; then
  log "Applying PCIe latency tweaks..."
  setpci -v -d *:* 68.w=5910 2>/dev/null || true
fi

log "Reloading systemd..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl restart systemd-journald

log "Deployment Complete."
echo "Backup stored at: $BACKUP_DIR"
