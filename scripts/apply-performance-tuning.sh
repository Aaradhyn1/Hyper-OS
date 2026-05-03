#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[hyperos-perf] failed at line $LINENO" >&2' ERR

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG_DIR="$ROOT_DIR/configs/performance"
DRY_RUN="${DRY_RUN:-0}"

log() { printf '[hyperos-perf] %s\n' "$*"; }

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

install_cfg() {
  local src=$1 dst=$2
  run install -D -m 0644 "$src" "$dst"
}

disable_if_exists() {
  local unit=$1
  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    run systemctl disable --now "$unit"
  fi
}

main() {
  require_root

  install_cfg "$CFG_DIR/sysctl.conf" /etc/sysctl.d/99-hyperos-performance.conf
  install_cfg "$CFG_DIR/systemd.conf" /etc/systemd/system.conf.d/10-hyperos-performance.conf
  install_cfg "$CFG_DIR/journald.conf" /etc/systemd/journald.conf.d/10-hyperos-performance.conf
  install_cfg "$CFG_DIR/cpupower.conf" /etc/default/cpupower
  install_cfg "$CFG_DIR/zram-generator.conf" /etc/systemd/zram-generator.conf
  install_cfg "$CFG_DIR/udev-iosched.rules" /etc/udev/rules.d/60-hyperos-iosched.rules

  run sysctl --system
  run systemctl daemon-reload
  run systemctl restart systemd-journald
  run udevadm control --reload
  run udevadm trigger --subsystem-match=block --action=change

  # Safe default removals for desktop ISO installs
  disable_if_exists ModemManager.service
  disable_if_exists bluetooth.service

  if systemctl list-unit-files cpupower.service >/dev/null 2>&1; then
    run systemctl enable --now cpupower.service
  fi

  log "performance profile applied"
  log "set DRY_RUN=1 to preview; remove files in /etc/{sysctl.d,systemd,journald.conf.d,udev/rules.d} to revert"
}

main "$@"
