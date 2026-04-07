# Linux Networking Optimization for Low Latency

This profile focuses on:
- sysctl tuning
- DNS optimization
- buffer tuning
- measurement commands

## Apply tuning

```bash
sudo ./scripts/apply-network-low-latency.sh
```

## 1) Sysctl tuning

The file `configs/networking/sysctl-low-latency.conf` applies:
- `fq` qdisc + `bbr` congestion control
- controlled socket/buffer limits
- tuned backlog and accept queue sizing
- faster connection behavior (`tcp_fastopen`, no slow-start-after-idle)

## 2) DNS optimization

The file `configs/networking/resolved.conf` configures `systemd-resolved` with:
- low-latency public DNS endpoints
- cache enabled
- opportunistic DNS-over-TLS
- stub listener for local fast resolver path

## 3) Buffer tuning rationale

- Moderate defaults avoid excessive memory use on small systems.
- Higher max buffers allow bursts without drops.
- Balanced values reduce jitter from retransmit/backlog pressure.

## 4) Commands to test latency improvements

Run baseline before tuning, then run again after tuning:

```bash
# Internet RTT/jitter
ping -c 30 1.1.1.1
ping -c 30 8.8.8.8

# DNS query latency and resolver path
time getent hosts debian.org
resolvectl query debian.org

# TCP/UDP path quality (requires remote iperf3 server)
iperf3 -c <server-ip> -t 20 -R
iperf3 -c <server-ip> -t 20 -u -b 0

# Socket and drop stats
ss -s
nstat -az | egrep 'TcpRetransSegs|IpInDiscards|UdpRcvbufErrors'

# Kernel network config verification
sysctl net.core.default_qdisc net.ipv4.tcp_congestion_control
```

## Expected impact

Typical on VM/server links (workload and path dependent):
- 5-25% lower p95/p99 request latency for chatty TCP services
- lower DNS lookup time variance due to local cache + fast resolvers
- fewer packet drops/retransmits during short bursts

## Notes

- For private networks, use closest internal DNS resolvers instead of public DNS.
- For high-bandwidth WAN, tune NIC offloads and IRQ affinity as next step.
