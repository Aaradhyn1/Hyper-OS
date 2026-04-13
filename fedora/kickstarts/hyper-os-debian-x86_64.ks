#!/usr/bin/env bash
# Integrated Hyper OS Debian KDE Builder (Replaces Fedora Kickstart)
set -Eeuo pipefail

# --- Configuration ---
DEBIAN_SUITE="bookworm"
MIRROR="http://debian.org"
ROOTFS_DIR="./build/rootfs_kde"
USERNAME="hyper"
HOSTNAME="hyperos-kde"

# Package selection (equivalent to Fedora @kde-desktop-environment)
CORE_PKGS="linux-image-amd64,systemd-sysv,live-boot,sudo,sddm,plasma-desktop,konsole,dolphin,network-manager,firefox-esr"
HW_PKGS="fwupd,bolt,thermald,tlp,tlp-rdw,powertop,curl,ca-certificates"

log() { printf "\e[32m[hyper-build] %s\e[0m\n" "$*"; }

[[ "$EUID" -ne 0 ]] && { echo "Run as root"; exit 1; }

# 1. Bootstrap Base System
log "Bootstrapping Debian $DEBIAN_SUITE..."
mkdir -p "$ROOTFS_DIR"
debootstrap --variant=minbase --include="$CORE_PKGS,$HW_PKGS" "$DEBIAN_SUITE" "$ROOTFS_DIR" "$MIRROR"

# 2. Integrated Post-Install Optimization (Chroot)
log "Executing internal system tuning..."
chroot "$ROOTFS_DIR" /usr/bin/env bash  /etc/hostname
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$USERNAME" | chpasswd
usermod -aG sudo "$USERNAME"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME

# Networking Tuning
cat > /etc/network/interfaces <<EOT
auto lo
iface lo inet loopback
EOT

# Hyper OS Performance Tuning (Replaces Kickstart %post)
systemctl enable fstrim.timer thermald.service tlp.service
systemctl disable apt-daily.service apt-daily.timer apt-daily-upgrade.timer packagekit.service || true

# Hardware MOTD Setup
mkdir -p /etc/motd.d
cat > /etc/motd.d/hyper-os-hardware.txt <<'EOT'
Hyper-OS (Debian KDE) Hardware Note:
- For NVIDIA: Add 'non-free-firmware' to sources.list and apt install nvidia-driver.
- Low Latency: Optimized for TLP and Thermald.
EOT

# APT Footprint Reduction
cat > /etc/apt/apt.conf.d/01-low-bloat <<EOT
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOT

apt-get update && apt-get autoremove -y && apt-get clean
EOF

# 3. Finalize
log "System definition complete."
log "Rootfs location: $ROOTFS_DIR"
log "Next step: Run build-iso.sh targeting this directory."
