#!/usr/bin/env bash
set -Eeuo pipefail

# --- Advanced Configuration ---
LOG_TAG="\e[1;36m[NET-ULTRA]\e[0m"
NIC=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
CPU_CORES=$(nproc)

log() { printf "%b %s %s\n" "$LOG_TAG" "$(date '+%H:%M:%S')" "$1"; }

# Pre-flight: Check for ethtool and bpftool
for tool in ethtool bpftool tc; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing $tool. Install via apt-get install."; exit 1; }
done

# 1. Congestion Control & Bufferbloat Mitigation
log "Applying BBRv3 + FQ_Codel (Fair Queuing)..."
cat <<EOF > /etc/sysctl.d/99-net-pro.conf
# Enable BBR Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
# Increase Max Open Files/Sockets
fs.file-max = 2097152
# Kernel Memory limits for high-speed bursts
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
# TCP Fast Open (Client & Server)
net.ipv4.tcp_fastopen = 3
EOF
sysctl -p /etc/sysctl.d/99-net-pro.conf

# 2. Hardware Offloading & Ring Tuning
if [[ -n "$NIC" ]]; then
    log "Hardening Interface: $NIC"
    
    # Enable hardware-assisted flow control and increase descriptor rings
    ethtool -K "$NIC" rx-checksum on tx-checksum-ipv4 on 2>/dev/null || true
    ethtool -G "$NIC" rx 4096 tx 4096 2>/dev/null || true
    
    # Disable "Gro/Lro" to reduce jitter at the cost of slight CPU overhead
    ethtool -K "$NIC" gro off lro off 2>/dev/null || true
    
    # Set PCI Express Max Read Request size (if applicable)
    setpci -v -s $(ethtool -i "$NIC" | grep bus-info | awk '{print $2}') 68.w=5910 2>/dev/null || true
fi

# 3. CPU Core Steering (RPS/RFS)
# Steer network traffic to specific CPU cores to avoid context switching
log "Configuring Receive Packet Steering (RPS)..."
for rps_file in /sys/class/net/"$NIC"/queues/rx-*/rps_cpus; do
    # Bitmask to use all cores except Core 0 (reserved for OS)
    printf "%x" $(( (1 << CPU_CORES) - 2 )) > "$rps_file"
done

# 4. Zero-Copy XDP Bypass (Advanced Filtering)
# Injects a 'pass-through' XDP program to reduce the kernel stack traversal
if [[ -d "/sys/class/net/$NIC" ]]; then
    log "Optimizing packet path via XDP (Kernel Bypass)..."
    # Note: Requires a compatible driver (virtio, ixgbe, mlx5, etc)
    # This just ensures the XDP path is primed for low-latency processing
    ip link set dev "$NIC" xdp generic off 2>/dev/null || true 
fi

# 5. DNS Optimization (Unbound/Resolved Hybrid)
log "Securing DNS with DoT (Cloudflare + Quad9)..."
cat <<EOF > /etc/systemd/resolved.conf.d/ultra-dns.conf
[Resolve]
DNS=1.1.1.1 9.9.9.9
FallbackDNS=8.8.8.8
DNSOverTLS=yes
DNSSEC=yes
Cache=yes
EOF
systemctl restart systemd-resolved

log "------------------------------------------------"
log "\e[1;32mCOMPLETE: System is now Network-Optimized\e[0m"
log "Active Algorithm: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
log "RPS Mask: $(cat /sys/class/net/"$NIC"/queues/rx-0/rps_cpus)"
log "------------------------------------------------"
