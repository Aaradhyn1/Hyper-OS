#!/usr/bin/env bash
# Advanced Hyper OS Performance Provisioner
set -Eeuo pipefail
trap 'echo "Error on line $LINENO. Script failed."' ERR

# Configuration
CONFIG_SRC="./configs/performance"
TARGET_DIR="/etc"
LOG_TAG="[HyperOS-Perf]"

# Utility for standardized logging
log() {
  printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_TAG" "$1"
}

# 1. Pre-flight Checks
if [[ "$EUID" -ne 0 ]]; then 
  log "ERROR: Must run as root. Try: sudo $0" >&2
  exit 1
fi

# Ensure source configs exist before proceeding
for cfg in sysctl.conf systemd.conf journald.conf; do
  [[ -f "$CONFIG_SRC/$cfg" ]] || { log "FATAL: $cfg missing in $CONFIG_SRC"; exit 1; }
done

# 2. Kernel & Systemd Hardening/Tuning
log "Applying kernel sysctl parameters..."
install -D -m 0644 "$CONFIG_SRC/sysctl.conf" "$TARGET_DIR/sysctl.d/99-hyperos-performance.conf"
# Apply without full system reload to avoid interrupting active network stacks unnecessarily
sysctl -p "$TARGET_DIR/sysctl.d/99-hyperos-performance.conf" >/dev/null

log "Configuring systemd manager & journald..."
install -D -m 0644 "$CONFIG_SRC/systemd.conf" "$TARGET_DIR/systemd/system.conf.d/10-hyperos-performance.conf"
install -D -m 0644 "$CONFIG_SRC/journald.conf" "$TARGET_DIR/systemd/journald.conf.d/10-hyperos-journal.conf"

# 3. Dynamic Service Optimization
# Added: udisks2 (heavy polling), fwupd (background scanning), and packagekit
SERVICES_TO_STRIP=(
  apt-daily.service apt-daily-upgrade.service apt-daily.timer apt-daily-upgrade.timer
  man-db.timer e2scrub_all.timer motd-news.timer bluetooth.service 
  ModemManager.service avahi-daemon.service cups.service 
  udisks2.service fwupd.service packagekit.service
)

log "Pruning non-essential background units..."
for unit in "${SERVICES_TO_STRIP[@]}"; do
  if systemctl is-enabled "$unit" >/dev/null 2>&1; then
    systemctl disable --now "$unit" || true
    systemctl mask "$unit" || true
    log "  - Masked $unit"
  fi
done

# 4. Advanced: I/O Scheduler & CPU Governor Tuning
log "Optimizing Hardware Governors..."
# Set CPU to performance if available
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null || true
fi

# Set I/O scheduler to 'none' (for NVMe) or 'mq-deadline' (for SSD)
for dev in /sys/block/sd* /sys/block/nvme*; do
    [ -e "$dev/queue/scheduler" ] || continue
    # If it's an NVMe, 'none' is usually best to bypass overhead
    [[ "$dev" == *"nvme"* ]] && echo "none" > "$dev/queue/scheduler" || echo "mq-deadline" > "$dev/queue/scheduler"
done

# 5. Finalize
log "Reloading control groups and daemon state..."
systemctl daemon-reload
systemctl restart systemd-journald

log "Optimization complete. System latency minimized."
log "RECOMMENDED: Reboot to clear fragmented memory and apply systemd-manager limits."
