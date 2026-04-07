#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN="${DRY_RUN:-0}"

required_units=(
  systemd-journald.service
  systemd-udevd.service
  systemd-tmpfiles-setup.service
  systemd-tmpfiles-setup-dev.service
  systemd-sysctl.service
  systemd-modules-load.service
  systemd-random-seed.service
  dbus.service
  getty@tty1.service
)

optional_units=(
  apt-daily.service
  apt-daily.timer
  apt-daily-upgrade.service
  apt-daily-upgrade.timer
  man-db.timer
  e2scrub_all.timer
  motd-news.timer
  bluetooth.service
  ModemManager.service
  avahi-daemon.service
  cups.service
)

log() {
  printf '%s [systemd-opt] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: $*"
  else
    "$@"
  fi
}

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/optimize-systemd-services.sh" >&2
  exit 1
fi

log "Required units reference: ${required_units[*]}"
log "Analyzing enabled services"
systemctl list-unit-files --type=service --state=enabled || true

for unit in "${optional_units[@]}"; do
  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    log "Disabling optional unit: $unit"
    run_cmd systemctl disable --now "$unit" || true
  else
    log "Unit not present, skipping: $unit"
  fi
done

log "Masking optional units to avoid re-enable on package updates"
for unit in "${optional_units[@]}"; do
  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    run_cmd systemctl mask "$unit" || true
  fi
done

log "Reloading and showing failed units"
run_cmd systemctl daemon-reload
systemctl --failed || true

log "Done. Reboot and compare with: systemd-analyze + RSS snapshot"
