#!/usr/bin/env bash
set -Eeuo pipefail

# --- Advanced Configuration ---
LOG_TAG="[Net-Pro]"
NIC=$(ip route | grep default | awk '{print $5}' | head -n1)

log() { printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_TAG" "$1"; }

[[ "$EUID" -ne 0 ]] && { echo "Root required." >&2; exit 1; }

# 1. Sysctl & DNS Profile Deployment
log "Deploying kernel and DNS profiles..."
install -D -m 0644 configs/networking/sysctl-low-latency.conf /etc/sysctl.d/98-hyperos-network-low-latency.conf
install -D -m 0644 configs/networking/resolved.conf /etc/systemd/resolved.conf.d/10-hyperos-low-latency.conf

sysctl -p /etc/sysctl.d/98-hyperos-network-low-latency.conf >/dev/null

# 2. Hardware-Level Tuning (Eth/Wi-Fi)
if [[ -n "$NIC" ]]; then
    log "Optimizing Interface: $NIC"
    # Disable Energy Efficient Ethernet (EEE) to prevent wake-up latency
    ethtool --set-eee "$NIC" eee off 2>/dev/null || true
    # Increase Ring Buffer size to prevent packet drops during bursts
    ethtool -G "$NIC" rx 4096 tx 4096 2>/dev/null || true
    # Disable Interrupt Coalescing (Sacrifices CPU for raw latency reduction)
    ethtool -C "$NIC" rx-usecs 0 tx-usecs 0 2>/dev/null || true
fi

# 3. DNS-over-TLS & Caching Setup
log "Configuring systemd-resolved (DoT + Stub)..."
systemctl enable --now systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# 4. IRQ Affinity (Pinning Network Interrupts)
# Prevents network processing from jumping between CPU cores (reduces jitter)
if command -v irqbalance >/dev/null; then
    log "Tuning irqbalance for low-latency mode..."
    sed -i 's/IRQBALANCE_ONESHOT=0/IRQBALANCE_ONESHOT=1/' /etc/default/irqbalance 2>/dev/null || true
    systemctl restart irqbalance || true
fi

# 5. Apply & Validate
log "Restarting network stack components..."
systemctl restart systemd-resolved

log "------------------------------------------------"
log "SUCCESS: Network Latency Optimized"
log "NIC: $NIC"
log "DNS: $(resolvectl query google.com | grep 'Server:' | awk '{print $2}')"
log "Validation: ping -c 5 1.1.1.1 (Watch for jitter/mdev)"
log "------------------------------------------------"
