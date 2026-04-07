#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOT_DIR/rootfs}"
ISO_DIR="${ISO_DIR:-$ROOT_DIR/iso}"
ISO_NAME="${ISO_NAME:-hyperos.iso}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
ARCH="amd64"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[hyper-os] missing command: $1" >&2
    exit 1
  }
}

require_cmd sudo
require_cmd debootstrap
require_cmd chroot
require_cmd grub-mkrescue
require_cmd xorriso

sudo rm -rf "$BUILD_DIR" "$ROOTFS_DIR" "$ISO_DIR" "$ROOT_DIR/$ISO_NAME"
mkdir -p "$BUILD_DIR" "$ROOTFS_DIR" "$ISO_DIR/boot/grub"

echo "[1/5] Creating minimal Debian root filesystem with debootstrap"
sudo debootstrap --arch="$ARCH" --variant=minbase "$DEBIAN_SUITE" "$ROOTFS_DIR" "$DEBIAN_MIRROR"

echo "[2/5] Configuring base system"
sudo cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
echo "hyperos" | sudo tee "$ROOTFS_DIR/etc/hostname" >/dev/null

sudo tee "$ROOTFS_DIR/etc/fstab" >/dev/null <<'FSTAB'
proc  /proc  proc   defaults  0  0
sysfs /sys   sysfs  defaults  0  0
devpts /dev/pts devpts gid=5,mode=620 0 0
FSTAB

sudo install -m 0755 -d "$ROOTFS_DIR/etc/sudoers.d"
sudo tee "$ROOTFS_DIR/etc/sudoers.d/hyper" >/dev/null <<'SUDOERS'
hyper ALL=(ALL:ALL) ALL
SUDOERS
sudo chmod 0440 "$ROOTFS_DIR/etc/sudoers.d/hyper"

sudo mount --bind /dev "$ROOTFS_DIR/dev"
sudo mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
sudo mount -t proc proc "$ROOTFS_DIR/proc"
sudo mount -t sysfs sysfs "$ROOTFS_DIR/sys"

cleanup_mounts() {
  set +e
  sudo umount -lf "$ROOTFS_DIR/dev/pts"
  sudo umount -lf "$ROOTFS_DIR/dev"
  sudo umount -lf "$ROOTFS_DIR/proc"
  sudo umount -lf "$ROOTFS_DIR/sys"
}
trap cleanup_mounts EXIT

sudo chroot "$ROOTFS_DIR" /bin/bash -eux <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends linux-image-amd64 systemd-sysv sudo nano network-manager grub-pc-bin
apt-get clean

useradd -m -s /bin/bash hyper
printf 'hyper:hyper\n' | chpasswd
printf 'root:root\n' | chpasswd

systemctl enable NetworkManager
systemctl set-default multi-user.target
CHROOT

echo "[3/5] Preparing ISO boot payload"
KERNEL_PATH="$(sudo find "$ROOTFS_DIR/boot" -maxdepth 1 -name 'vmlinuz-*' | head -n1)"
INITRD_PATH="$(sudo find "$ROOTFS_DIR/boot" -maxdepth 1 -name 'initrd.img-*' | head -n1)"

if [[ -z "$KERNEL_PATH" || -z "$INITRD_PATH" ]]; then
  echo "[hyper-os] kernel/initrd not found in rootfs boot directory" >&2
  exit 1
fi

sudo cp "$KERNEL_PATH" "$ISO_DIR/boot/vmlinuz"
sudo cp "$INITRD_PATH" "$ISO_DIR/boot/initrd.img"
cp "$ROOT_DIR/configs/grub.cfg" "$ISO_DIR/boot/grub/grub.cfg"

echo "[4/5] Creating bootable BIOS ISO with GRUB"
grub-mkrescue -o "$ROOT_DIR/$ISO_NAME" "$ISO_DIR"

echo "[5/5] Build complete"
echo "ISO image: $ROOT_DIR/$ISO_NAME"
echo "QEMU test command:"
echo "  qemu-system-x86_64 -m 2048 -cdrom $ROOT_DIR/$ISO_NAME -boot d -serial mon:stdio -no-reboot"
