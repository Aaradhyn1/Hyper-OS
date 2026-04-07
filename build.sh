#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOT_DIR/rootfs}"
ISO_DIR="${ISO_DIR:-$ROOT_DIR/iso}"
ISO_NAME="${ISO_NAME:-hyperos.iso}"
ISO_PATH="$ROOT_DIR/$ISO_NAME"

DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
ARCH="amd64"
HOSTNAME="hyperos"
USERNAME="hyper"
USER_PASSWORD="${HYPER_PASSWORD:-hyper}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"

LOG_DIR="$BUILD_DIR/logs"
LOG_FILE="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
STEP=0
MOUNTS_ACTIVE=0

usage() {
  cat <<USAGE
Hyper OS production build script

Usage:
  sudo ./build.sh

Environment overrides:
  DEBIAN_SUITE, DEBIAN_MIRROR, ISO_NAME, BUILD_DIR, ROOTFS_DIR, ISO_DIR,
  HYPER_PASSWORD, ROOT_PASSWORD
USAGE
}

log() {
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2"
}

log_step() {
  STEP=$((STEP + 1))
  log INFO "Step ${STEP}: $1"
}

die() {
  log ERROR "$1"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

prepare_logging() {
  mkdir -p "$LOG_DIR"
  touch "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  log INFO "Build log: $LOG_FILE"
}

check_dependencies() {
  log_step "Checking required dependencies"
  local deps=(debootstrap chroot grub-mkrescue xorriso find mount umount tee)
  local missing=0

  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log ERROR "Missing dependency: $dep"
      missing=1
    fi
  done

  [[ "$missing" -eq 0 ]] || die "Install missing dependencies and retry"
}

ensure_root() {
  log_step "Validating root privileges"
  [[ "$EUID" -eq 0 ]] || die "This script must run as root. Use: sudo ./build.sh"
}

cleanup_mounts() {
  local mount_path
  for mount_path in "$ROOTFS_DIR/dev/pts" "$ROOTFS_DIR/dev" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys"; do
    if mountpoint -q "$mount_path" 2>/dev/null; then
      umount -lf "$mount_path" || true
    fi
  done
  MOUNTS_ACTIVE=0
}

cleanup_on_exit() {
  local exit_code="$1"

  if [[ "$MOUNTS_ACTIVE" -eq 1 ]]; then
    log INFO "Running cleanup: unmounting chroot filesystems"
    cleanup_mounts
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    log ERROR "Build failed (exit code: $exit_code). See $LOG_FILE"
    rm -f "$ISO_PATH.tmp" || true
  fi
}

prepare_workspace() {
  log_step "Preparing workspace for clean rebuild"

  cleanup_mounts
  rm -rf "$ROOTFS_DIR" "$ISO_DIR"
  mkdir -p "$BUILD_DIR" "$ROOTFS_DIR" "$ISO_DIR/boot/grub"
  rm -f "$ISO_PATH.tmp"
}

create_rootfs() {
  log_step "Creating Debian root filesystem"
  debootstrap --arch="$ARCH" --variant=minbase "$DEBIAN_SUITE" "$ROOTFS_DIR" "$DEBIAN_MIRROR"

  cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
  echo "$HOSTNAME" > "$ROOTFS_DIR/etc/hostname"

  cat > "$ROOTFS_DIR/etc/fstab" <<'FSTAB'
proc   /proc    proc    defaults               0 0
sysfs  /sys     sysfs   defaults               0 0
devpts /dev/pts devpts  gid=5,mode=620,ptmxmode=000 0 0
FSTAB

  install -d -m 0755 "$ROOTFS_DIR/etc/sudoers.d"
  cat > "$ROOTFS_DIR/etc/sudoers.d/$USERNAME" <<SUDOERS
$USERNAME ALL=(ALL:ALL) ALL
SUDOERS
  chmod 0440 "$ROOTFS_DIR/etc/sudoers.d/$USERNAME"
}

mount_chroot_filesystems() {
  log_step "Mounting chroot filesystems"
  mount --bind /dev "$ROOTFS_DIR/dev"
  mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
  mount -t proc proc "$ROOTFS_DIR/proc"
  mount -t sysfs sysfs "$ROOTFS_DIR/sys"
  MOUNTS_ACTIVE=1
}

configure_system() {
  log_step "Installing packages and configuring system in chroot"
  chroot "$ROOTFS_DIR" /bin/bash -eux <<CHROOT
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  linux-image-amd64 \
  systemd-sysv \
  sudo \
  nano \
  network-manager \
  grub-pc-bin
apt-get clean
rm -rf /var/lib/apt/lists/*

useradd -m -s /bin/bash "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd
printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd

systemctl enable NetworkManager
systemctl set-default multi-user.target
CHROOT
}

stage_iso_tree() {
  log_step "Staging kernel, initrd, and GRUB config"
  local kernel_path initrd_path
  kernel_path="$(find "$ROOTFS_DIR/boot" -maxdepth 1 -name 'vmlinuz-*' | head -n1)"
  initrd_path="$(find "$ROOTFS_DIR/boot" -maxdepth 1 -name 'initrd.img-*' | head -n1)"

  [[ -n "$kernel_path" ]] || die "Kernel image not found in $ROOTFS_DIR/boot"
  [[ -n "$initrd_path" ]] || die "Initrd image not found in $ROOTFS_DIR/boot"

  cp "$kernel_path" "$ISO_DIR/boot/vmlinuz"
  cp "$initrd_path" "$ISO_DIR/boot/initrd.img"

  cat > "$ISO_DIR/boot/grub/grub.cfg" <<'GRUBCFG'
set default=0
set timeout=3

menuentry "Hyper OS v0.1 (Debian minimal)" {
    linux /boot/vmlinuz root=/dev/sr0 ro console=tty0 console=ttyS0,115200n8 systemd.unit=multi-user.target
    initrd /boot/initrd.img
}
GRUBCFG
}

build_iso() {
  log_step "Building BIOS-bootable ISO"
  grub-mkrescue -o "$ISO_PATH.tmp" "$ISO_DIR"
  mv -f "$ISO_PATH.tmp" "$ISO_PATH"
}

print_summary() {
  log_step "Build complete"
  echo
  echo "ISO output : $ISO_PATH"
  echo "Build log  : $LOG_FILE"
  echo
  echo "Run in QEMU:"
  echo "qemu-system-x86_64 -m 2048 -cdrom $ISO_PATH -boot d -serial mon:stdio -no-reboot"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  prepare_logging
  trap 'cleanup_on_exit $?' EXIT

  ensure_root
  check_dependencies
  prepare_workspace
  create_rootfs
  mount_chroot_filesystems
  configure_system
  stage_iso_tree
  build_iso
  print_summary
}

main "$@"
