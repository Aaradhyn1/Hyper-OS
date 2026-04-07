#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '%s [perf] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/apply-performance-tuning.sh" >&2
  exit 1
fi

log "Installing sysctl profile"
install -D -m 0644 configs/performance/sysctl.conf /etc/sysctl.d/99-hyperos-performance.conf
sysctl --system >/dev/null

log "Installing systemd manager tuning"
install -D -m 0644 configs/performance/systemd.conf /etc/systemd/system.conf.d/10-hyperos-performance.conf

log "Installing journald limits"
install -D -m 0644 configs/performance/journald.conf /etc/systemd/journald.conf.d/10-hyperos-journal.conf

log "Disabling non-essential services/timers for faster boot + lower RAM"
for unit in \
  apt-daily.service \
  apt-daily-upgrade.service \
  apt-daily.timer \
  apt-daily-upgrade.timer \
  man-db.timer \
  e2scrub_all.timer \
  motd-news.timer \
  bluetooth.service \
  ModemManager.service \
  avahi-daemon.service \
  cups.service; do
  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    systemctl disable --now "$unit" || true
    systemctl mask "$unit" || true
  fi
done

log "Reloading systemd and restarting journald"
systemctl daemon-reload
systemctl restart systemd-journald

log "Done. Reboot recommended to apply all scheduling/boot-time changes."
