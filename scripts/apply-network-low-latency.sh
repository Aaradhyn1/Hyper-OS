#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '%s [net-latency] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/apply-network-low-latency.sh" >&2
  exit 1
fi

log "Installing sysctl low-latency network profile"
install -D -m 0644 configs/networking/sysctl-low-latency.conf /etc/sysctl.d/98-hyperos-network-low-latency.conf
sysctl --system >/dev/null

log "Installing systemd-resolved DNS profile"
install -D -m 0644 configs/networking/resolved.conf /etc/systemd/resolved.conf.d/10-hyperos-low-latency.conf

log "Ensuring systemd-resolved is enabled"
systemctl enable --now systemd-resolved

if [[ -L /etc/resolv.conf ]]; then
  log "/etc/resolv.conf already symlinked"
else
  log "Linking /etc/resolv.conf -> systemd-resolved stub"
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

log "Restarting resolver to apply DNS tuning"
systemctl restart systemd-resolved

log "Applied. Validate with: resolvectl status && ping -c 20 1.1.1.1"
