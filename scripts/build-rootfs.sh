#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-common.sh"

# --- Advanced Configuration ---
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
# Core packages for a functional low-latency live system
CORE_PKGS="linux-image-amd64,live-boot,systemd-sysv,sudo,network-manager,iproute2,pciutils,kmod,zstd"

main() {
  use_shared_logging
  require_root
  require_cmds debootstrap systemd-nspawn

  log INFO "Initializing Hyper OS Workspace"
  cleanup_mounts
  rm -rf "$ROOTFS_DIR" && mkdir -p "$ROOTFS_DIR"

  # 1. Optimized Bootstrap
  # Using --include ensures we don't need a heavy second stage for core tools
  log INFO "Bootstrapping optimized minbase with core packages"
  debootstrap \
    --arch="${ARCH:-amd64}" \
    --variant=minbase \
    --include="$CORE_PKGS" \
    "$DEBIAN_SUITE" "$ROOTFS_DIR" "$DEBIAN_MIRROR"

  # 2. Advanced Networking & DNS Setup
  log INFO "Configuring network stack"
  echo "$HOSTNAME" > "$ROOTFS_DIR/etc/hostname"
  # Use systemd-resolved for better latency/caching
  ln -sf /run/systemd/resolve/stub-resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

  # 3. APT Optimization (No Recommends = No Bloat)
  log INFO "Tuning APT for minimal footprint"
  cat > "$ROOTFS_DIR/etc/apt/apt.conf.d/01-hyperos-tuning" <<EOF
APT::Install-Recommends "0";
APT::Install-Suggests "0";
APT::Sandbox::User "root";
Binary::apt::APT::Keep-Downloaded-Packages "0";
EOF

  # 4. Use systemd-nspawn for safe configuration
  # This is much safer than manual mount/chroot
  log INFO "Running internal OS provisioning via nspawn"
  systemd-nspawn -D "$ROOTFS_DIR" /bin/bash <<EOF
    set -e
    # Create user with a pre-locked or specific password configuration
    useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:hyperos" | chpasswd
    usermod -aG sudo,video,audio "$USERNAME"
    
    # Force kernel to update initramfs inside the rootfs
    update-initramfs -u
EOF

  # 5. Advanced Hardware/Performance Baseline
  log INFO "Applying low-latency baseline"
  cat > "$ROOTFS_DIR/etc/default/irqbalance" <<EOF
# Prevent irqbalance from moving interrupts too frequently
IRQBALANCE_ONESHOT=1
EOF

  log SUCCESS "Rootfs provisioned. Size: $(du -sh "$ROOTFS_DIR" | cut -f1)"
}

main "$@"
