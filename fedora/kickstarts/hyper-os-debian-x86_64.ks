#!/usr/bin/env bash
# Hyper OS Architect-Grade Build System
set -Eeuo pipefail

# --- Configuration & Shared Context ---
readonly DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
readonly ROOTFS_DIR="$(pwd)/build/rootfs"
readonly CACHE_DIR="$(pwd)/build/cache"
readonly APT_PROXY="${APT_PROXY:-}" # e.g., http://localhost:3142 if using apt-cacher-ng

# Package Sets (Categorized for modularity)
readonly PKG_CORE="linux-image-amd64,systemd-sysv,live-boot,sudo,bash-completion"
readonly PKG_UI="plasma-desktop,sddm,konsole,dolphin,network-manager,firefox-esr,pipewire-audio-client-libraries"
readonly PKG_PERF="tlp,thermald,fwupd,bolt,zram-tools,irqbalance"

log() { printf "\e[1;35m[HYPER-ARCHITECT]\e[0m %s\n" "$*"; }

# --- Build Engine Stages ---

stage_bootstrap() {
    log "Stage 1: Bootstrapping via debootstrap..."
    mkdir -p "$ROOTFS_DIR" "$CACHE_DIR"
    
    local opts=(
        "--variant=minbase"
        "--include=$PKG_CORE,$PKG_UI,$PKG_PERF"
        "--arch=amd64"
    )
    
    # Use local proxy if available to save bandwidth
    [[ -n "$APT_PROXY" ]] && export http_proxy="$APT_PROXY"

    debootstrap "${opts[@]}" "$DEBIAN_SUITE" "$ROOTFS_DIR" "http://debian.org"
}

stage_configure() {
    log "Stage 2: Injecting system-level policy..."
    
    # Create the internal build script to run inside chroot
    cat <<'EOF' > "$ROOTFS_DIR/tmp/setup.sh"
set -e
export DEBIAN_FRONTEND=noninteractive

# 1. Performance Tweak: ZRAM and Swapiness
echo "ALGO=zstd" > /etc/default/zramswap
echo "vm.swappiness=10" > /etc/sysctl.d/99-hyper.conf

# 2. KDE Plasma Minimal Branding
mkdir -p /etc/skel/.config
# Prevent KDE from starting baloo (file indexer) to save CPU/IO
cat <<KDE > /etc/skel/.config/baloofilerc
[Basic Settings]
Indexing-Enabled=false
KDE

# 3. Kernel & Driver Firmware Setup
# Add non-free-firmware to sources for modern WiFi/GPU support
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt-get update

# 4. Final Cleanup
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

    chmod +x "$ROOTFS_DIR/tmp/setup.sh"
    chroot "$ROOTFS_DIR" /bin/bash /tmp/setup.sh
    rm "$ROOTFS_DIR/tmp/setup.sh"
}

stage_compress() {
    log "Stage 3: Compressing RootFS into SquashFS..."
    # High-ratio XZ compression for smaller ISOs
    # -comp xz: Maximum compression
    # -Xbcj x86: Optimizes compression for x86 executables
    mksquashfs "$ROOTFS_DIR" "./build/filesystem.squashfs" \
        -comp xz -Xbcj x86 -b 1M -noappend
}

# --- Execution ---

main() {
    [[ $EUID -ne 0 ]] && { log "ERROR: Root required"; exit 1; }
    
    # Start Pipeline
    stage_bootstrap
    stage_configure
    stage_compress
    
    log "------------------------------------------------"
    log "Build Complete!"
    log "SquashFS: ./build/filesystem.squashfs"
    log "Ready for ISO wrap (xorriso/grub-mkrescue)"
    log "------------------------------------------------"
}

main "$@"
