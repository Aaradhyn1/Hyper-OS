#!/usr/bin/env bash
# Hyper OS Architect-Grade Build System v2
set -Eeuo pipefail

# =========================
# Globals
# =========================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_DIR="$SCRIPT_DIR/build"
readonly ROOTFS_DIR="$BUILD_DIR/rootfs"
readonly CACHE_DIR="$BUILD_DIR/cache"
readonly OUT_DIR="$BUILD_DIR/out"

readonly DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
readonly ARCH="amd64"
readonly APT_PROXY="${APT_PROXY:-}"

readonly PKG_CORE="linux-image-amd64,systemd-sysv,live-boot,sudo,bash-completion"
readonly PKG_UI="plasma-desktop,sddm,konsole,dolphin,network-manager,firefox-esr,pipewire-audio-client-libraries"
readonly PKG_PERF="tlp,thermald,fwupd,bolt,zram-tools,irqbalance"

# =========================
# Logging
# =========================
log()   { printf "\e[1;34m[INFO]\e[0m %s\n" "$*"; }
warn()  { printf "\e[1;33m[WARN]\e[0m %s\n" "$*" >&2; }
error() { printf "\e[1;31m[ERROR]\e[0m %s\n" "$*" >&2; exit 1; }

# =========================
# Cleanup & Trap
# =========================
cleanup() {
    log "Cleaning up mounts..."
    mount | grep "$ROOTFS_DIR" | awk '{print $3}' | xargs -r umount -lf || true
}
trap cleanup EXIT

# =========================
# Utilities
# =========================
require_root() {
    [[ $EUID -eq 0 ]] || error "Run as root."
}

check_deps() {
    local deps=(debootstrap mksquashfs chroot)
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null || error "Missing dependency: $dep"
    done
}

prepare_dirs() {
    mkdir -p "$ROOTFS_DIR" "$CACHE_DIR" "$OUT_DIR"
}

clean() {
    log "Nuking build directory..."
    rm -rf "$BUILD_DIR"
}

# =========================
# Stage 1: Bootstrap
# =========================
stage_bootstrap() {
    log "Stage 1: Bootstrap ($DEBIAN_SUITE)..."

    [[ -d "$ROOTFS_DIR/bin" ]] && {
        warn "RootFS already exists. Skipping bootstrap."
        return
    }

    [[ -n "$APT_PROXY" ]] && export http_proxy="$APT_PROXY"

    debootstrap \
        --variant=minbase \
        --arch="$ARCH" \
        --include="$PKG_CORE,$PKG_UI,$PKG_PERF" \
        "$DEBIAN_SUITE" "$ROOTFS_DIR" "http://deb.debian.org/debian"
}

# =========================
# Stage 2: Configure
# =========================
stage_configure() {
    log "Stage 2: System Configuration..."

    mount --bind /dev  "$ROOTFS_DIR/dev"
    mount --bind /proc "$ROOTFS_DIR/proc"
    mount --bind /sys  "$ROOTFS_DIR/sys"

    cat <<'EOF' > "$ROOTFS_DIR/tmp/setup.sh"
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[HYPER] Applying performance policies..."

# ZRAM
echo "ALGO=zstd" > /etc/default/zramswap
echo "vm.swappiness=10" > /etc/sysctl.d/99-hyper.conf

# KDE Optimization
mkdir -p /etc/skel/.config
cat <<KDE > /etc/skel/.config/baloofilerc
[Basic Settings]
Indexing-Enabled=false
KDE

# Firmware Support
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt-get update
apt-get install -y firmware-linux firmware-linux-nonfree

# Cleanup
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

    chmod +x "$ROOTFS_DIR/tmp/setup.sh"
    chroot "$ROOTFS_DIR" /bin/bash /tmp/setup.sh
    rm "$ROOTFS_DIR/tmp/setup.sh"
}

# =========================
# Stage 3: Compress
# =========================
stage_compress() {
    log "Stage 3: SquashFS Compression..."

    local out="$OUT_DIR/filesystem.squashfs"

    mksquashfs "$ROOTFS_DIR" "$out" \
        -comp xz -Xbcj x86 -b 1M -noappend

    log "SquashFS created: $out"
}

# =========================
# Stage 4: Verify
# =========================
stage_verify() {
    log "Stage 4: Verifying artifact..."

    local file="$OUT_DIR/filesystem.squashfs"

    [[ -f "$file" ]] || error "Build failed: SquashFS missing"

    du -h "$file"
    file "$file"

    log "Verification passed."
}

# =========================
# CLI
# =========================
main() {
    require_root
    check_deps

    case "${1:-build}" in
        clean)
            clean
            ;;
        build)
            prepare_dirs
            stage_bootstrap
            stage_configure
            stage_compress
            stage_verify
            ;;
        rebuild)
            clean
            prepare_dirs
            stage_bootstrap
            stage_configure
            stage_compress
            stage_verify
            ;;
        *)
            echo "Usage: $0 [build|clean|rebuild]"
            exit 1
            ;;
    esac
}

main "$@"
