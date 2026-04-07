#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/build-common.sh
source "$SCRIPT_DIR/lib/build-common.sh"

DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
ARCH="${ARCH:-amd64}"
HOSTNAME="${HOSTNAME:-hyperos}"
USERNAME="${USERNAME:-hyper}"

main() {
  use_shared_logging
  require_root
  require_cmds debootstrap find mount umount tee

  log INFO "Preparing workspace"
  cleanup_mounts
  rm -rf "$ROOTFS_DIR"
  mkdir -p "$BUILD_DIR" "$ROOTFS_DIR"

  log INFO "Bootstrapping Debian rootfs ($DEBIAN_SUITE/$ARCH)"
  debootstrap --arch="$ARCH" --variant=minbase "$DEBIAN_SUITE" "$ROOTFS_DIR" "$DEBIAN_MIRROR"

  log INFO "Writing baseline system files"
  cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
  echo "$HOSTNAME" > "$ROOTFS_DIR/etc/hostname"

  cat > "$ROOTFS_DIR/etc/fstab" <<'FSTAB'
proc   /proc    proc    defaults                              0 0
sysfs  /sys     sysfs   defaults                              0 0
devpts /dev/pts devpts  gid=5,mode=620,ptmxmode=000          0 0
FSTAB

  install -d -m 0755 "$ROOTFS_DIR/etc/sudoers.d"
  cat > "$ROOTFS_DIR/etc/sudoers.d/$USERNAME" <<SUDOERS
$USERNAME ALL=(ALL:ALL) ALL
SUDOERS
  chmod 0440 "$ROOTFS_DIR/etc/sudoers.d/$USERNAME"

  log INFO "Rootfs created at $ROOTFS_DIR"
}

main "$@"
