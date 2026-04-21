# Hyper OS v0.1

Hyper OS is built through a single deterministic entrypoint:

```bash
sudo ./build.sh
```

This command produces a bootable ISO image with a fully configured system.

---

## Build Pipeline Overview

The build system executes a controlled, reproducible pipeline:

1. Validates required dependencies and environment
2. Creates a clean, isolated build workspace
3. Bootstraps a minimal Debian root filesystem via `debootstrap`
4. Mounts required kernel filesystems (`/dev`, `/proc`, `/sys`)
5. Installs and configures core system packages
6. Applies system configuration (hostname, users, sudo policy, systemd target)
7. Stages kernel and initramfs
8. Assembles ISO image using GRUB
9. Verifies output and performs cleanup

---

## Requirements

Install required dependencies:

```bash
sudo apt-get update
sudo apt-get install -y \
  debootstrap \
  grub-pc-bin \
  grub-common \
  xorriso \
  mtools \
  dosfstools \
  qemu-system-x86
```

---

## Usage 

Run the build:

```bash
sudo ./build.sh
```

### Optional Overrides

```bash
sudo \
  DEBIAN_SUITE=bookworm \
  ISO_NAME=hyperos.iso \
  HYPER_PASSWORD='change-me' \
  ROOT_PASSWORD='change-root' \
  ./build.sh
```

---

## Output Artifacts

On successful build:

* `./hyperos.iso` → bootable image
* `./hyperos.iso.sha256` → checksum
* `./build/logs/build-YYYYMMDD-HHMMSS.log` → full build log

---

## Logging & Failure Model

* Strict execution: `set -Eeuo pipefail`
* Immediate abort on any failure
* Timestamped structured logs
* Automatic cleanup via trap handler
* Partial artifacts are discarded on failure

---

## Reproducibility Guarantees

* Clean workspace per build (`rootfs/`, `iso/` recreated)
* Deterministic package set
* No reuse of stale mounts or cached state
* Safe to rerun without manual intervention

---

## Verification

Validate ISO integrity:

```bash
sha256sum -c hyperos.iso.sha256
```

---

## Testing (QEMU)

```bash
qemu-system-x86_64 \
  -m 2048 \
  -cdrom ./hyperos.iso \
  -boot d \
  -serial mon:stdio \
  -no-reboot
```

---

## Performance Profile

Low-latency and system tuning:

```bash
sudo ./scripts/apply-performance-tuning.sh
```

Details:

* `docs/PERFORMANCE_TUNING.md`

---

## Systemd Optimization

Minimal service profile:

```bash
sudo ./scripts/optimize-systemd-services.sh
# Preview mode
sudo DRY_RUN=1 ./scripts/optimize-systemd-services.sh
```

Details:

* `docs/SYSTEMD_MINIMAL_PROFILE.md`

---

## Network Optimization

Low-latency network tuning:

```bash
sudo ./scripts/apply-network-low-latency.sh
```

Details:

* `docs/NETWORK_LOW_LATENCY.md`

---

## Design Principles

* Deterministic builds over convenience
* Minimal baseline with explicit opt-in features
* Fail-fast execution model
* No hidden state or implicit dependencies

---

## Status

Hyper OS v0.1 is an early-stage distribution with a stable build pipeline and evolving runtime profile.
