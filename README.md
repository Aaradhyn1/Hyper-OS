# Hyper-OS

Hyper-OS is now targeted at **x86_64 (64-bit)** systems and builds a **Fedora KDE Plasma** image.

## Primary target

- Architecture: `x86_64`
- Base distro: Fedora Linux
- Desktop: KDE Plasma
- Build tool: `livemedia-creator` (Lorax)

## Lenovo ThinkPad P15 Gen 2 support

Yes — this profile is suitable for ThinkPad P15 Gen 2 class hardware (x86_64).
The kickstart includes laptop-friendly defaults like Wi-Fi networking, firmware updates,
Thunderbolt support, and thermal/power tuning packages (`fwupd`, `bolt`, `thermald`, `tlp`).

For P15 Gen 2 models with NVIDIA dGPU:
- install RPM Fusion + NVIDIA drivers after first boot
- if Secure Boot is enabled, enroll/sign third-party kernel modules (MOK flow)

## Repository layout

- Fedora kickstart profile: `fedora/kickstarts/hyper-os-kde-x86_64.ks`
- Fedora builder script: `scripts/build-fedora-kde.sh`
- Legacy Buildroot flow (kept for reference): `scripts/build.sh` + `configs/rpi4_minimal_defconfig`

## Build (default)

```bash
make build
```

This runs:

```bash
./scripts/build-fedora-kde.sh
```

## Full Fedora KDE image build requirements

Use a Fedora x86_64 host with required tools:

```bash
sudo dnf install -y lorax-lmc-novirt livemedia-creator spin-kickstarts
```

Then run:

```bash
sudo make build
```

## Offline / restricted-environment behavior

If `livemedia-creator` is not installed, the build script generates an offline reproducibility bundle in:

- `out/fedora-kde-x86_64/BUILD_INSTRUCTIONS.txt`
- `out/fedora-kde-x86_64/hyper-os-kde-x86_64.ks`

This keeps `make build` runnable in locked-down environments while preserving exact instructions for full image generation.

## Useful overrides

```bash
RELEASEVER=42 IMAGE_NAME="Hyper-OS-Fedora-KDE-x86_64" OUTPUT_DIR=/tmp/hyper-os make build
```

## Legacy Buildroot profile

The previous Raspberry Pi 4 Buildroot profile still exists for reference:

```bash
make build-buildroot
```
