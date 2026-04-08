#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/build-common.sh
source "$SCRIPT_DIR/lib/build-common.sh"

USERNAME="${USERNAME:-hyper}"
USER_PASSWORD="${HYPER_PASSWORD:-hyper}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
HOSTNAME="${HOSTNAME:-hyperos}"

cleanup_and_report() {
  local code="$1"
  cleanup_mounts
  if [[ "$code" -ne 0 ]]; then
    log ERROR "System configuration failed with exit code $code"
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

  log INFO "Installing kernel, live runtime, and networking packages"
  if ! chroot "$ROOTFS_DIR" /bin/bash -eux <<CHROOT
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  linux-image-amd64 \
  systemd-sysv \
  live-boot \
  live-config \
  live-tools \
  squashfs-tools \
  initramfs-tools \
  ca-certificates \
  sudo \
  nano \
  network-manager \
  systemd-resolved \
  grub-pc-bin

install -d -m 0755 /lib/live

cat > /etc/hostname <<HOSTNAMEFILE
$HOSTNAME
HOSTNAMEFILE

cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 hyperos
::1 localhost ip6-localhost ip6-loopback
HOSTS
sed -i "s/^127.0.1.1 .*/127.0.1.1 $HOSTNAME/" /etc/hosts

: > /etc/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

install -d -m 0755 /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-dns-systemd-resolved.conf <<'NMCONF'
[main]
dns=systemd-resolved
NMCONF

rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

if ! id -u "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
fi
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd
printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd

systemctl enable NetworkManager
systemctl enable systemd-resolved
systemctl set-default multi-user.target

install -d -m 0755 /etc/initramfs-tools/conf.d
cat > /etc/initramfs-tools/conf.d/hyperos-live.conf <<'INITRAMFSCONF'
COMPRESS=zstd
MODULES=most
INITRAMFSCONF

update-initramfs -u -k all

latest_initrd="$(ls -1 /boot/initrd.img-* | sort -V | tail -n1)"
if [[ -z "$latest_initrd" ]]; then
  echo "ERROR: No initrd found after update-initramfs" >&2
  exit 1
fi

if ! lsinitramfs "$latest_initrd" | grep -Eq '^scripts/live|^usr/lib/live'; then
  echo "ERROR: live-boot hooks missing from $latest_initrd" >&2
  exit 1
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT
  then
    die "Chroot package/configuration stage failed"
  fi

  trap - EXIT
  cleanup_and_report 0
  log INFO "System configuration complete"
}

main "$@"
