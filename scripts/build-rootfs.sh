 #!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[HyperOS-RootFS] ERROR at line $LINENO"; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-common.sh"

# =========================
# Validation
# =========================
: "${USERNAME:?USERNAME must be set}"
: "${HOSTNAME:?HOSTNAME must be set}"

declare -F cleanup_mounts >/dev/null || { echo "cleanup_mounts missing"; exit 1; }

# =========================
# Config
# =========================
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
ARCH="${ARCH:-amd64}"

CORE_PKGS="linux-image-amd64,live-boot,systemd-sysv,sudo,network-manager,iproute2,pciutils,kmod,zstd,ca-certificates"

APT_OPTS="-o Acquire::Retries=3 -o Acquire::http::Timeout=10"

# =========================
# Functions
# =========================
bootstrap() {
  log INFO "Bootstrapping Debian ($DEBIAN_SUITE)..."

  debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --include="$CORE_PKGS" \
    "$DEBIAN_SUITE" "$ROOTFS_DIR" "$DEBIAN_MIRROR"
}

configure_base() {
  log INFO "Configuring base system..."

  echo "$HOSTNAME" > "$ROOTFS_DIR/etc/hostname"
  truncate -s 0 "$ROOTFS_DIR/etc/machine-id"

  ln -sf /run/systemd/resolve/stub-resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

  cat > "$ROOTFS_DIR/etc/apt/apt.conf.d/01-hyperos-tuning" <<EOF
APT::Install-Recommends "0";
APT::Install-Suggests "0";
APT::Sandbox::User "root";
Binary::apt::APT::Keep-Downloaded-Packages "0";
Acquire::Retries "3";
Acquire::http::Timeout "10";
EOF
}

provision_container() {
  log INFO "Provisioning inside systemd-nspawn..."

  systemd-nspawn -D "$ROOTFS_DIR" \
    --resolv-conf=copy-host \
    --setenv=DEBIAN_FRONTEND=noninteractive \
    /bin/bash -eux <<'EOF'

apt-get update

apt-get install -y locales tzdata systemd-sysv dbus sudo

# Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

# Timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# User setup
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

usermod -aG sudo,video,audio,netdev "$USERNAME"

# Enable essential services
systemctl enable systemd-networkd || true
systemctl enable systemd-resolved || true

# Initramfs
update-initramfs -u -k all

# Clean
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

EOF
}

apply_performance() {
  log INFO "Applying performance baseline..."

  cat > "$ROOTFS_DIR/etc/sysctl.d/99-hyperos.conf" <<EOF
kernel.nmi_watchdog = 0
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 8192
EOF

  cat > "$ROOTFS_DIR/etc/security/limits.d/99-hyperos.conf" <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
EOF

  cat > "$ROOTFS_DIR/etc/default/irqbalance" <<EOF
IRQBALANCE_ONESHOT=1
EOF
}

sanitize() {
  log INFO "Sanitizing rootfs..."

  truncate -s 0 "$ROOTFS_DIR/etc/machine-id" || true
  rm -f "$ROOTFS_DIR/var/lib/dbus/machine-id"

  rm -rf "$ROOTFS_DIR/tmp/"*
  rm -rf "$ROOTFS_DIR/var/tmp/"*
  rm -rf "$ROOTFS_DIR/var/log/"*

  rm -f "$ROOTFS_DIR/etc/resolv.conf"
}

# =========================
# Main
# =========================
main() {
  use_shared_logging
  require_root
  require_cmds debootstrap systemd-nspawn

  log INFO "Initializing Hyper OS workspace..."
  cleanup_mounts

  rm -rf "$ROOTFS_DIR"
  mkdir -p "$ROOTFS_DIR"

  bootstrap
  configure_base
  provision_container
  apply_performance
  sanitize

  log SUCCESS "RootFS ready: $(du -sh "$ROOTFS_DIR" | cut -f1)"
}

main "$@"
