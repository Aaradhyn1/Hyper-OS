#!/usr/bin/env bash
# Hyper OS Systemd Optimizer (Production Grade)
set -Eeuo pipefail
trap 'echo "[Systemd-Pro] ERROR at line $LINENO"; exit 1' ERR

DRY_RUN="${DRY_RUN:-0}"
AGGRESSIVE="${AGGRESSIVE:-0}"
LOG_TAG="[Systemd-Pro]"

BACKUP_DIR="/var/log/hyperos-systemd"
BACKUP_FILE="$BACKUP_DIR/enabled-units-$(date +%s).txt"
STATE_FILE="$BACKUP_DIR/unit-state.log"

PROTECTED_UNITS=(
  systemd-journald.service
  systemd-udevd.service
  dbus.service
  networking.service
  systemd-networkd.service
  NetworkManager.service
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
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY] $*"
  else
    "$@"
  fi
}

require_root() {
  [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
}

init_backup() {
  mkdir -p "$BACKUP_DIR"
}

unit_exists() {
  systemctl list-unit-files --all | awk '{print $1}' | grep -qx "$1"
}

is_protected() {
  for u in "${PROTECTED_UNITS[@]}"; do
    [[ "$1" == "$u" ]] && return 0
  done
  return 1
}

backup_state() {
  log "Backing up enabled units → $BACKUP_FILE"
  systemctl list-unit-files --state=enabled > "$BACKUP_FILE"
}

record_unit_state() {
  local unit="$1"
  local state
  state=$(systemctl is-enabled "$unit" 2>/dev/null || echo "unknown")
  echo "$unit $state" >> "$STATE_FILE"
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

    record_unit_state "$unit"

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

  local CONF="/etc/systemd/system.conf.d/10-hyperos.conf"
  run mkdir -p "$(dirname "$CONF")"

  if [[ "$DRY_RUN" == "0" ]]; then
    cat > "$CONF" <<EOF
[Manager]
DefaultTimeoutStartSec=8s
DefaultTimeoutStopSec=4s
DefaultRestartSec=100ms
DefaultLimitNOFILE=65535
EOF
  fi
}

rollback() {
  log "Rolling back systemd changes..."

  [[ -f "$STATE_FILE" ]] || { log "No state file found"; exit 1; }

  while read -r unit state; do
    case "$state" in
      enabled)
        log "Re-enabling $unit"
        run systemctl unmask "$unit" 2>/dev/null || true
        run systemctl enable "$unit"
        ;;
      disabled)
        log "Disabling $unit"
        run systemctl disable "$unit"
        ;;
    esac
  done < "$STATE_FILE"

  run systemctl daemon-reload
  log "Rollback complete."
}

show_metrics() {
  log "Top slow services:"
  systemd-analyze blame | head -n 5 | sed 's/^/  /'
}

main() {
  require_root
  init_backup

  case "${1:-optimize}" in
    optimize)
      log "=== Hyper OS System Optimizer ==="
      backup_state
      optimize_units
      tune_systemd
      run systemctl daemon-reload
      show_metrics
      log "Done. Reboot recommended."
      ;;
    rollback)
      rollback
      ;;
    *)
      echo "Usage: $0 [optimize|rollback]"
      exit 1
      ;;
  esac
}

main "$@"
