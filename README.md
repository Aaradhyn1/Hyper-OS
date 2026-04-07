# Hyper OS v0.1

Hyper OS uses a single production-grade build entrypoint:

```bash
sudo ./build.sh
```

This one command builds everything and outputs `hyperos.iso`.

## What `build.sh` does

1. Checks dependencies
2. Prepares a clean rebuild workspace
3. Creates Debian rootfs with `debootstrap`
4. Mounts chroot filesystems and installs packages
5. Configures hostname, fstab, users, sudo, and systemd target
6. Stages GRUB boot files and kernel/initrd
7. Builds `hyperos.iso`
8. Cleans up mounts on exit/failure

## Required dependencies

```bash
sudo apt-get update
sudo apt-get install -y debootstrap grub-pc-bin grub-common xorriso qemu-system-x86
```

## Run

```bash
sudo ./build.sh
```

Optional overrides:

```bash
sudo DEBIAN_SUITE=bookworm ISO_NAME=hyperos.iso HYPER_PASSWORD='change-me' ROOT_PASSWORD='change-root' ./build.sh
```

## Logging and error handling

- Every step is logged with timestamps.
- Logs are written to: `build/logs/build-YYYYMMDD-HHMMSS.log`
- Script stops immediately on any error (`set -Eeuo pipefail`).
- Cleanup trap unmounts chroot filesystems and removes partial ISO temp files.

## Rebuild safety

- Script supports repeated rebuilds safely.
- Existing `rootfs/` and `iso/` are recreated each run.
- Stale chroot mounts are cleaned before and after build.

## Expected output

After success:

- `./hyperos.iso`
- `./build/logs/build-*.log`

QEMU test command:

```bash
qemu-system-x86_64 -m 2048 -cdrom ./hyperos.iso -boot d -serial mon:stdio -no-reboot
```

## Performance tuning profile

For low-latency, fast-boot, low-RAM tuning, see `docs/PERFORMANCE_TUNING.md` and apply with:

```bash
sudo ./scripts/apply-performance-tuning.sh
```

## Systemd minimal-service optimization

For a minimal systemd profile (required vs removable services, safe disable commands, and expected boot/RAM impact), see:

- `docs/SYSTEMD_MINIMAL_PROFILE.md`

Apply optional service trimming script:

```bash
sudo ./scripts/optimize-systemd-services.sh
# or preview only
sudo DRY_RUN=1 ./scripts/optimize-systemd-services.sh
```

## Network low-latency optimization

For networking-focused low-latency tuning (sysctl, DNS, buffers, and test commands), see:

- `docs/NETWORK_LOW_LATENCY.md`

Apply profile:

```bash
sudo ./scripts/apply-network-low-latency.sh
```
