# Hyper-OS

Hyper-OS is a minimal Buildroot-based Linux image profile for Raspberry Pi 4 focused on:

- fast boot
- low memory footprint
- BusyBox-first user space
- no systemd

## What's included

- Buildroot defconfig: `configs/rpi4_minimal_defconfig`
- Pi firmware config and cmdline tuning: `board/raspberrypi4-minimal/`
- Tiny rootfs overlay with BusyBox init files
- Build script for local Buildroot builds + offline fallback bundle

## Prerequisites (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install -y build-essential git rsync bc bison flex file wget cpio unzip python3
```

## Build

```bash
make build
```

### Build behavior

- If Buildroot exists at `./buildroot`, a full OS image build is executed.
- If Buildroot is not present, `make build` now generates an **offline reproducibility bundle** in `out/rpi4/images` instead of failing.

You can override paths:

```bash
BUILDROOT_DIR=/path/to/buildroot OUTPUT_DIR=/tmp/hyper-os-out make build
```

## Full image build in connected environment

```bash
BUILDROOT_DIR=/path/to/buildroot make build
```

The script will run:

```bash
make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR" BR2_DEFCONFIG="$PWD/configs/rpi4_minimal_defconfig" defconfig
make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR"
```

## Flash to SD card

1. Partition SD card with a FAT32 boot partition + ext4 root partition.
2. Copy firmware/kernels from `out/rpi4/images` boot files to the FAT32 partition.
3. Write `rootfs.ext4` to the root partition.

> Tip: use `bmaptool` or `dd` carefully and verify target device path.

## Next optimization steps

- Build and use a custom kernel config (drop unused drivers/filesystems/protocols).
- Remove Dropbear if serial-only deployment is acceptable.
- Convert rootfs to squashfs + overlayfs for immutable deployments.
