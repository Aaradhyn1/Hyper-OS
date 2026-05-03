# Systemd Service Analysis for Minimal Hyper OS

Objective:
- fastest boot
- minimal RAM usage

## Required services (keep enabled)

These are typically required for a bootable, usable minimal Debian VM:
 
- `systemd-journald.service` (logging)
- `systemd-udevd.service` (device management)
- `systemd-tmpfiles-setup.service` + `systemd-tmpfiles-setup-dev.service`
- `systemd-sysctl.service`
- `systemd-modules-load.service`
- `systemd-random-seed.service`
- `dbus.service` (required by NetworkManager and other core components)
- `NetworkManager.service` (if networking via NM is needed)
- `getty@tty1.service` (console login)

> Keep your bootloader, kernel, initramfs, and mount units intact.

## Commonly removable services (if not needed)

Disable only if feature is not required:

- `apt-daily.service`, `apt-daily.timer`
- `apt-daily-upgrade.service`, `apt-daily-upgrade.timer`
- `man-db.timer`
- `e2scrub_all.timer`
- `motd-news.timer`
- `bluetooth.service`
- `ModemManager.service`
- `avahi-daemon.service`
- `cups.service`

## Safe disable workflow

### 1) Measure current boot and memory

```bash
systemd-analyze
systemd-analyze blame | head -n 25
systemctl list-unit-files --type=service --state=enabled
ps -eo pid,comm,rss --sort=-rss | head -n 25
```

### 2) Disable non-essential units safely (runtime + persistent)

```bash
sudo systemctl disable --now apt-daily.service apt-daily.timer
sudo systemctl disable --now apt-daily-upgrade.service apt-daily-upgrade.timer
sudo systemctl disable --now man-db.timer e2scrub_all.timer motd-news.timer
sudo systemctl disable --now bluetooth.service ModemManager.service avahi-daemon.service cups.service
```

### 3) Optional: mask to prevent re-enabling

```bash
sudo systemctl mask apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer
sudo systemctl mask man-db.timer e2scrub_all.timer motd-news.timer
sudo systemctl mask bluetooth.service ModemManager.service avahi-daemon.service cups.service
```

### 4) Verify boot is still healthy

```bash
sudo systemctl daemon-reload
sudo systemctl --failed
systemd-analyze
systemd-analyze critical-chain
```

## Expected impact

Typical impact on small VM/minimal host (workload-dependent):

- Boot time: **1-6s faster** (mostly from fewer timers/services and timeout avoidance)
- RAM: **30-150MB lower steady-state RSS**
- CPU wakeups: fewer periodic background tasks

## Rollback

If a disabled unit is needed:

```bash
sudo systemctl unmask <unit>
sudo systemctl enable --now <unit>
```
