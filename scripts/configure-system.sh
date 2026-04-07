#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/build-common.sh
source "$SCRIPT_DIR/lib/build-common.sh"

USERNAME="${USERNAME:-hyper}"
USER_PASSWORD="${HYPER_PASSWORD:-hyper}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"

cleanup_and_report() {
  local code="$1"
  cleanup_mounts
  if [[ "$code" -ne 0 ]]; then
    log ERROR "System configuration failed"
  fi
}

main() {
  use_shared_logging
  require_root
  require_cmds chroot mount umount apt-get
  [[ -d "$ROOTFS_DIR" ]] || die "Rootfs missing: $ROOTFS_DIR (run build-rootfs.sh first)"

  trap 'cleanup_and_report $?' EXIT

  log INFO "Mounting chroot filesystems"
  mount_chroot_fs

  log INFO "Installing kernel, systemd, and runtime packages"
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

if ! id -u "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
fi
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd
printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd

systemctl enable NetworkManager
systemctl set-default multi-user.target
CHROOT

  trap - EXIT
  cleanup_and_report 0
  log INFO "System configuration complete"
}

main "$@"
