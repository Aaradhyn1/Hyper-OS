#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN="${DRY_RUN:-1}"
MODE="${1:-apply}"
STATE_DIR="/var/lib/hyperos"
STATE_FILE="$STATE_DIR/disabled-services.list"

TARGET_UNITS=(
  ModemManager.service
  bluetooth.service
  cups.service
  avahi-daemon.service
)

log() { printf '[hyperos-systemd] %s\n' "$*"; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

require_root() {
  [[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
}

apply_changes() {
  run install -d -m 0755 "$STATE_DIR"
  : > "$STATE_FILE"

  for unit in "${TARGET_UNITS[@]}"; do
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
      if systemctl is-enabled "$unit" >/dev/null 2>&1; then
        echo "$unit" >> "$STATE_FILE"
        run systemctl disable --now "$unit"
      fi
    fi
  done

  log "applied; see $STATE_FILE for rollback source"
}

rollback() {
  [[ -f "$STATE_FILE" ]] || { log "no state file: $STATE_FILE"; exit 1; }
  while read -r unit; do
    [[ -n "$unit" ]] || continue
    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
      run systemctl unmask "$unit" 2>/dev/null || true
      run systemctl enable "$unit"
    fi
  done < "$STATE_FILE"

  log "rollback complete"
}

show_metrics() {
  log "critical-chain"
  systemd-analyze critical-chain | sed -n '1,25p'
  log "top boot services"
  systemd-analyze blame | sed -n '1,15p'
}

main() {
  require_root
  case "$MODE" in
    apply) apply_changes ;;
    rollback) rollback ;;
    metrics) show_metrics ;;
    *) echo "usage: $0 [apply|rollback|metrics]" >&2; exit 1 ;;
  esac
}

main "$@"
