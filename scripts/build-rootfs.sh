#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-common.sh"

# --- Validation ---
: "${USERNAME:?USERNAME must be set}"
: "${HOSTNAME:?HOSTNAME must be set}"

declare -F cleanup_mounts >/dev/null || { echo "cleanup_mounts missing"; exit 1; }

# --- Config ---
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"

CORE_PKGS="linux-image-amd64,live-boot,systemd-sysv,sudo,network-manager,iproute2,pciutils,kmod,zstd"

main() {
  use_shared_logging
  require_root
  require_cmds debootstrap systemd-nspawn

  log INFO "Initializing Hyper OS Workspace"
  cleanup_mounts
  rm -rf "$ROOTFS_DIR"
  mkdir -p "$ROOTFS_DIR"

  log INFO "Bootstrapping system"
  debootstrap \
    --arch="${ARCH:-amd64}" \
    --variant=minbase \
    --include="$CORE_PKGS" \
    "$DEBIAN_SUITE" "$ROOTFS_DIR" "$DEBIAN_MIRROR"

  log INFO "Configuring base system"
  echo "$HOSTNAME" > "$ROOTFS_DIR/etc/hostname"
  truncate -s 0 "$ROOTFS_DIR/etc/machine-id"

  ln -sf /run/systemd/resolve/stub-resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

  cat > "$ROOTFS_DIR/etc/apt/apt.conf.d/01-hyperos-tuning" <<EOF
APT::Install-Recommends "0";
APT::Install-Suggests "0";
APT::Sandbox::User "root";
Binary::apt::APT::Keep-Downloaded-Packages "0";
EOF

  log INFO "Provisioning inside container"
  systemd-nspawn -D "$ROOTFS_DIR" \
    --resolv-conf=copy-host \
    --setenv=DEBIAN_FRONTEND=noninteractive \
    /bin/bash -eux <<EOF

apt-get update
apt-get install -y locales tzdata

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

useradd -m -s /bin/bash "$USERNAME"

if [[ -n "${USER_PASSWORD_HASH:-}" ]]; then
  usermod -p "${USER_PASSWORD_HASH}" "$USERNAME"
else
  passwd -l "$USERNAME"
fi

if [[ -n "${ROOT_PASSWORD_HASH:-}" ]]; then
  usermod -p "${ROOT_PASSWORD_HASH}" root
else
  passwd -l root
fi

usermod -aG sudo,video,audio "$USERNAME"

update-initramfs -u -k all

EOF

  log INFO "Applying performance baseline"
  cat > "$ROOTFS_DIR/etc/default/irqbalance" <<EOF
IRQBALANCE_ONESHOT=1
EOF

  log SUCCESS "Rootfs ready: $(du -sh "$ROOTFS_DIR" | cut -f1)"
}

main "$@"
