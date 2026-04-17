#!/usr/bin/env bash
# Hyper OS Systemd Optimizer (Safe Edition)
set -Eeuo pipefail

DRY_RUN="${DRY_RUN:-0}"
AGGRESSIVE="${AGGRESSIVE:-0}"   # enable masking only if 1
LOG_TAG="[Systemd-Pro]"

BACKUP_FILE="/var/log/hyperos-systemd-backup.txt"

PROTECTED_UNITS=(
  systemd-journald.service
  systemd-udevd.service
  dbus.service
  networking.service
  systemd-networkd.service
)

TARGET_UNITS=(
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
  smartmontools.service
  packagekit.service
  fwupd.service
)

log() { printf '%s %s %s\n' "$(date '+%H:%M:%S')" "$LOG_TAG" "$*"; }

run() {
  [[ "$DRY_RUN" == "1" ]] && log "[DRY] $*" || "$@"
}

require_root() {
  [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
}

unit_exists() {
  systemctl list-unit-files | grep -q "^$1"
}

is_protected() {
  for u in "${PROTECTED_UNITS[@]}"; do
    [[ "$1" == "$u" ]] && return 0
  done
  return 1
}

backup_state() {
  log "Saving current enabled units → $BACKUP_FILE"
  systemctl list-unit-files --state=enabled > "$BACKUP_FILE"
}

optimize_units() {
  log "Optimizing systemd units..."

  for unit in "${TARGET_UNITS[@]}"; do
    if is_protected "$unit"; then
      log "Protected → skip: $unit"
      continue
    fi

    if ! unit_exists "$unit"; then
      log "Missing → skip: $unit"
      continue
    fi

    if systemctl is-enabled "$unit" >/dev/null 2>&1; then
      log "Disabling: $unit"
      run systemctl disable --now "$unit"

      if [[ "$AGGRESSIVE" == "1" ]]; then
        log "Masking: $unit"
        run systemctl mask "$unit"
      fi
    fi
  done
}

tune_systemd() {
  log "Applying systemd tuning..."

  CONF="/etc/systemd/system.conf.d/10-hyperos.conf"
  run mkdir -p "$(dirname "$CONF")"

  [[ "$DRY_RUN" == "0" ]] && cat > "$CONF" <<EOF
[Manager]
DefaultTimeoutStartSec=8s
DefaultTimeoutStopSec=4s
DefaultRestartSec=100ms
DefaultLimitNOFILE=65535
EOF
}

show_metrics() {
  log "Top slow services:"
  systemd-analyze blame | head -n 5 | sed 's/^/  /'
}

main() {
  require_root

  log "=== Hyper OS System Optimizer ==="

  backup_state
  optimize_units
  tune_systemd

  run systemctl daemon-reload

  show_metrics

  log "Done. Reboot and run: systemd-analyze critical-chain"
  log "Rollback: systemctl re-enable units from $BACKUP_FILE"
}

main "$@"
