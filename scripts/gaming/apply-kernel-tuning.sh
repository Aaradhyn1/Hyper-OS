#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:-apply}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/configs/gaming/sysctl-gaming.conf"
DST="/etc/sysctl.d/99-hyperos-gaming-latency.conf"

require_root() {
  [[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
}

apply() {
  install -D -m 0644 "$SRC" "$DST"
  sysctl --system >/dev/null
  systemctl enable --now irqbalance.service 2>/dev/null || true
  echo "applied $DST"
}

restore() {
  rm -f "$DST"
  sysctl --system >/dev/null
  echo "restored defaults"
}

main() {
  require_root
  case "$ACTION" in
    apply) apply ;;
    restore) restore ;;
    *) echo "usage: $0 [apply|restore]" >&2; exit 1 ;;
  esac
}

main "$@"
