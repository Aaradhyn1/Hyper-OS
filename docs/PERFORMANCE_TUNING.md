# Hyper OS Performance Tuning Profile

This profile targets:
- low latency
- fast boot
- low RAM usage

## Files included

- `configs/performance/sysctl.conf`
- `configs/performance/systemd.conf`
- `configs/performance/journald.conf`
- `scripts/apply-performance-tuning.sh`

## Apply on target system

```bash
sudo ./scripts/apply-performance-tuning.sh
sudo reboot
```

## What changes and expected gains

### 1) `sysctl.conf`
- Lowers swap aggressiveness (`vm.swappiness=10`) and improves cache retention (`vm.vfs_cache_pressure=50`) to reduce memory churn.
- Tighter dirty page limits reduce long writeback stalls, improving responsiveness under I/O.
- `fq + bbr` and TCP fast open improve network latency/throughput consistency.

**Expected gains (typical):**
- 5-20% lower tail latency for mixed I/O/network workloads
- smoother responsiveness under memory pressure

### 2) systemd manager tweaks
- Shorter timeout defaults reduce boot stalls when optional hardware/services are missing.
- Lower manager log level reduces boot-time log overhead.

**Expected gains (typical):**
- 1-6 seconds faster boot on minimal systems with disabled optional hardware/services

### 3) service optimization
Disables/masks non-essential periodic/background units (apt timers, man-db timer, ModemManager, Avahi, CUPS, etc.) when present.

**Expected gains (typical):**
- 30-150 MB lower steady-state RAM usage (workload-dependent)
- fewer wakeups and lower background CPU noise

## Notes
- If you need Wi-Fi or printing, do not disable/mask related services.
- For the lowest latency, consider CPU governor `performance` and IRQ affinity tuning as next steps.
