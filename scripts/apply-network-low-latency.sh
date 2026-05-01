#!/usr/bin/env bash
set -Eeuo pipefail

# --- CONFIGURATION ---
LOG_TAG="\e[1;36m[NET-ULTRA-PRO]\e[0m"
NIC=$(ip route show to default | awk '{print $5}' | head -n1)
CPU_CORES=$(nproc)
RPS_MASK=$(printf '%x' $(( (1 << CPU_CORES) - 2 )))

log() { printf "${LOG_TAG} $(date +%H:%M:%S) %s\n" "$1"; }

# 1. PRE-FLIGHT & KERNEL MODULES
log "Loading advanced kernel modules..."
modprobe -a tcp_bbr sch_fq fq_codel xt_REDIRECT 2>/dev/null || true

# 2. IRQ PINNING
if command -v irqbalance >/dev/null; then
    log "Disabling irqbalance..."
    systemctl stop irqbalance 2>/dev/null || true
    systemctl disable irqbalance 2>/dev/null || true
fi

log "Pinning IRQs for $NIC..."
i=1
for irq in $(grep "$NIC" /proc/interrupts | awk '{print $1}' | tr -d ':'); do
    printf '%x' $((1 << i)) > "/proc/irq/$irq/smp_affinity"
    i=$(( (i + 1) % CPU_CORES ))
    [ "$i" -eq 0 ] && i=1
done

# 3. SYSCTL TUNING
log "Applying sysctl tuning..."
cat <<EOF > /etc/sysctl.d/99-ultra-performance.conf
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
EOF

sysctl --system >/dev/null

# 4. RPS/XPS
log "Configuring RPS/XPS..."
for q in /sys/class/net/$NIC/queues/rx-*; do
    echo "$RPS_MASK" > "$q/rps_cpus" 2>/dev/null || true
    echo 4096 > "$q/rps_flow_cnt" 2>/dev/null || true
done

for q in /sys/class/net/$NIC/queues/tx-*; do
    echo "$RPS_MASK" > "$q/xps_cpus" 2>/dev/null || true
done

echo 32768 > /proc/sys/net/core/rps_sock_flow_entries 2>/dev/null || true

# 5. ETHTOOL OPTIMIZATION
log "Optimizing NIC features..."
ethtool -K "$NIC" gro on gso on tso on lro off rx on tx on 2>/dev/null || true
ethtool -C "$NIC" adaptive-rx on adaptive-tx on rx-usecs 50 tx-usecs 50 2>/dev/null || true
ethtool -G "$NIC" rx 4096 tx 4096 2>/dev/null || true

# 6. XDP MODE
if command -v bpftool >/dev/null; then
    log "Setting XDP native mode..."
    ip link set dev "$NIC" xdp off 2>/dev/null || true
fi

# 7. FINAL
log "Configuration Complete."
printf "\e[1;32mOPTIMIZATION SUMMARY:\e[0m\n"
echo "-----------------------------------"
echo "NIC: $NIC"
echo "RPS Mask: $RPS_MASK"
echo "Congestion: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "Queuing: $(sysctl -n net.core.default_qdisc)"
echo "-----------------------------------"
