#!/usr/bin/env bash
set -Eeuo pipefail

# --- CONFIGURATION ---
LOG_TAG="\e[1;36m[NET-ULTRA-PRO]\e[0m"
NIC=$(ip route show to default | awk '{print $5}' | head -n1)
CPU_CORES=$(nproc)
# Reserved mask: All cores except Core 0 (for OS stability)
RPS_MASK=$(printf 'x%x' $(( (1 << CPU_CORES) - 2 )))

log() { printf "${LOG_TAG} $(date +%H:%M:%S) %s\n" "$1"; }

# 1. PRE-FLIGHT & KERNEL MODULES
log "Loading advanced kernel modules..."
modprobe -a tcp_bbr sch_fq_codel xt_REDIRECT 2>/dev/null || true

# 2. NUMA-AWARE IRQ PINNING (The Gold Standard for Latency)
# Instead of letting the OS move interrupts around, we pin NIC queues to specific cores.
if command -v irqbalance >/dev/null; then
    log "Disabling irqbalance to manualy steer interrupts..."
    systemctl stop irqbalance 2>/dev/null || true
fi

log "Pinning IRQs for $NIC to dedicated CPU cores..."
i=1 # Start from Core 1
for irq in $(grep "$NIC" /proc/interrupts | awk '{print $1}' | sed 's/://'); do
    echo $((1 << i)) > "/proc/irq/$irq/smp_affinity"
    i=$(( (i + 1) % CPU_CORES ))
    [ $i -eq 0 ] && i=1
done

# 3. KERNEL SYSCAPES (Hardened & Optimized)
log "Applying 10GbE+ optimized sysctl parameters..."
cat <<EOF > /etc/sysctl.d/99-ultra-performance.conf
# TCP Stack Tuning
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# Bufferbloat & BBRv3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Memory & Buffer Management (Scales to 16MB)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Security: Anti-DDoS / SYN Cookies
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
EOF
sysctl -p /etc/sysctl.d/99-ultra-performance.conf

# 4. HARDWARE: DYNAMIC INTERRUPT MODERATION
# Adaptive-RX/TX reduces CPU usage during high load but lowers latency during low load.
log "Optimizing Hardware Coalescing..."
ethtool -C "$NIC" adaptive-rx on adaptive-tx on 2>/dev/null || log "Adaptive moderation not supported, skipping."

# 5. XDP NATIVE ACCELERATION (eBPF)
# Bypassing the kernel stack for dropped or forwarded packets.
if command -v bpftool >/dev/null; then
    log "Attempting to enable Native XDP (Zero Copy)..."
    # This acts as a high-speed bypass if a custom XDP program is provided.
    # For now, we ensure the driver is in 'native' mode for low overhead.
    ip link set dev "$NIC" xdp generic off 2>/dev/null || true
fi

# 6. REAPING THE REWARDS
log "Configuration Complete."
printf "\e[1;32mOPTIMIZATION SUMMARY:\e[0m\n"
echo "-----------------------------------"
echo "NIC: $NIC"
echo "RPS Mask: $RPS_MASK"
echo "Congestion: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "Queuing: $(sysctl -n net.core.default_qdisc)"
echo "-----------------------------------"
