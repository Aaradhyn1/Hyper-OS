#!/usr/bin/env bash
set -Eeuo pipefail

# --- Advanced Configuration ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
CONFIG_DIR="${ROOT_DIR}/config"
OUTPUT_DIR="${ROOT_DIR}/out"

# OS Metadata
IMAGE_NAME="Hyper-OS-$(date +%Y%m%d)"
DISTRO="debian"
RELEASE="bookworm"
ARCH="amd64"

# Logging Utility
log() {
    local type=$1; shift
    local color="\e[32m" # Green
    [[ "$type" == "ERR" ]] && color="\e[31m" # Red
    printf "${color}[%s] [%s] %s\e[0m\n" "$(date +%H:%M:%S)" "$type" "$*"
}

# --- Build Modules ---

cleanup() {
    log INFO "Cleaning up build environment..."
    cd "$BUILD_DIR" && lb clean --purge
}

setup_structure() {
    log INFO "Initializing Live-Build structure..."
    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"
    
    lb config \
        --distribution "$RELEASE" \
        --archive-areas "main contrib non-free non-free-firmware" \
        --debian-installer live \
        --debian-installer-distribution "$RELEASE" \
        --cache true \
        --apt-indices false \
        --apt-recommends false \
        --debootstrap-options "--variant=minbase" \
        --bootappend-live "boot=live components quiet splash loglevel=3 udev.log_priority=3" \
        --image-name "$IMAGE_NAME"
}

inject_packages() {
    log INFO "Adding Core, KDE, and Performance packages..."
    local PKG_LIST="config/package-lists/hyper.list.chroot"
    mkdir -p "$(dirname "$PKG_LIST")"

    cat <<EOF > "$PKG_LIST"
# Desktop Environment
kde-standard plasma-nm sddm
# Installer & System
calamares-settings-debian calamares
# Power & Hardware
tlp tlp-rdw thermald fwupd bolt smartmontools fstrim
# Performance
zram-tools pipewire-audio-client-libraries
# Utilities
sudo curl wget nano micro htop
EOF
}

inject_customizations() {
    log INFO "Applying system-level optimizations..."
    local HOOK="config/hooks/live/99-performance.chroot"
    mkdir -p "$(dirname "$HOOK")"

    cat <<'EOF' > "$HOOK"
#!/bin/sh
set -e
# Enable ZRAM for better memory management
echo "ALGO=zstd" >> /etc/default/zramswap
echo "PERCENT=60" >> /etc/default/zramswap

# Low Latency Tuning
echo "vm.swappiness=10" > /etc/sysctl.d/99-hyper.conf
echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-hyper.conf

# Disable annoying system beeps and bloat services
rm -f /etc/apt/apt.conf.d/10periodic
systemctl enable tlp
systemctl enable thermald
EOF
    chmod +x "$HOOK"
}

# --- Main Execution ---

main() {
    [[ $EUID -ne 0 ]] && { log ERR "Root required"; exit 1; }

    # Pre-flight checks
    command -v lb >/dev/null || apt-get install -y live-build debootstrap

    # Execute Pipeline
    setup_structure
    inject_packages
    inject_customizations
    
    log INFO "Starting ISO build (this may take a while)..."
    lb build 2>&1 | tee "$ROOT_DIR/build.log"

    # Export
    mkdir -p "$OUTPUT_DIR"
    mv *.iso "$OUTPUT_DIR/${IMAGE_NAME}.iso"
    log INFO "Build success: $OUTPUT_DIR/${IMAGE_NAME}.iso"
}

main "$@"
