# Hyper OS Performance Engineering Framework

## Baseline metrics (before tuning)
- Boot: `systemd-analyze`, `systemd-analyze blame`, `systemd-analyze critical-chain`
- CPU load: `uptime`, `top -b -n1 | head -n 20`
- Memory: `free -h`, `smem -rtk | head -n 20`
- I/O: `iostat -xz 1 3`, `iotop -oPa`

Use `scripts/performance-benchmark.sh` to capture a snapshot report.

## Applied optimizations

### Boot
- Reduced default systemd timeouts to avoid long hangs on optional units.
- Optional desktop services can be disabled with rollback support:
  - `ModemManager.service`
  - `bluetooth.service`
  - `cups.service`
  - `avahi-daemon.service`

### CPU
- Default governor: `schedutil` via `cpupower`.
- Enabled `cpupower.service` where available.

### Memory
- `vm.swappiness=20`, `vm.vfs_cache_pressure=75`
- ZRAM configured with zstd and size up to 4G or 50% RAM.

### Disk I/O
- Udev rule sets scheduler based on media type:
  - NVMe SSD: `none`
  - SATA SSD: `mq-deadline`
  - HDD: `bfq`

### Desktop
- Openbox autostart remains minimal.
- LightDM autologin retained for installer/live UX.

## Revert strategy
- Remove files:
  - `/etc/sysctl.d/99-hyperos-performance.conf`
  - `/etc/systemd/system.conf.d/10-hyperos-performance.conf`
  - `/etc/systemd/journald.conf.d/10-hyperos-performance.conf`
  - `/etc/systemd/zram-generator.conf`
  - `/etc/udev/rules.d/60-hyperos-iosched.rules`
  - `/etc/default/cpupower`
- Reload:
  - `sudo sysctl --system`
  - `sudo systemctl daemon-reload`
  - `sudo systemctl restart systemd-journald`
- Restore disabled services:
  - `sudo DRY_RUN=0 scripts/optimize-systemd-services.sh rollback`
