#!/usr/bin/env bash
# Hyper OS Architect Build System v4 (Production)
set -Eeuo pipefail
trap 'echo "[HYPER-BUILD] ERROR at line $LINENO"; exit 1' ERR

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
readonly PKG_UI="plasma-desktop,sddm,konsole,dolphin,network-manager,firefox-esr,pipewire,wireplumber"
readonly PKG_PERF="tlp,thermald,fwupd,bolt,zram-tools,irqbalance"

# =========================
# Logging
# =========================
log()   { printf "\e[1;34m[INFO]\e[0m %s\n" "$*"; }
warn()  { printf "\e[1;33m[WARN]\e[0m %s\n" "$*" >&2; }
die()   { printf "\e[1;31m[FATAL]\e[0m %s\n" "$*" >&2; exit 1; }

# =========================
# Cleanup (robust)
# =========================
cleanup() {
    log "Cleaning mounts..."
    mount | grep "$ROOTFS_DIR" | awk '{print $3}' | tac | xargs -r umount -lf || true
}
trap cleanup EXIT

# =========================
# Utilities
# =========================
require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root."
}

check_deps() {
    local deps=(debootstrap mksquashfs chroot mount umount sha256sum)
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null || die "Missing dependency: $dep"
    done
}

retry() {
    local attempts=5 delay=3
    for ((i=1;i<=attempts;i++)); do
        "$@" && return 0
        warn "Retry $i/$attempts failed → retrying..."
        sleep "$delay"
    done
    return 1
}

prepare_dirs() {
    mkdir -p "$ROOTFS_DIR" "$CACHE_DIR" "$OUT_DIR"
}

clean() {
    log "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
}

# =========================
# Stage 1: Bootstrap
# =========================
stage_bootstrap() {
    log "Bootstrapping Debian ($DEBIAN_SUITE)..."

    [[ -d "$ROOTFS_DIR/bin" ]] && {
        warn "RootFS exists → skipping bootstrap"
        return
    }

    [[ -n "$APT_PROXY" ]] && export http_proxy="$APT_PROXY"

    retry debootstrap \
        --variant=minbase \
        --arch="$ARCH" \
        --include="$PKG_CORE,$PKG_UI,$PKG_PERF" \
        "$DEBIAN_SUITE" "$ROOTFS_DIR" "https://deb.debian.org/debian"
}

# =========================
# Stage 2: Configure
# =========================
stage_configure() {
    log "Configuring system..."

    for fs in dev proc sys; do
        mountpoint -q "$ROOTFS_DIR/$fs" || mount --bind "/$fs" "$ROOTFS_DIR/$fs"
    done

    cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

    cat <<'EOF' > "$ROOTFS_DIR/tmp/setup.sh"
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "[HYPER] Applying optimizations..."

# Enable firmware repos
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list

apt-get update
apt-get install -y firmware-linux firmware-linux-nonfree

# ZRAM
echo "ALGO=zstd" > /etc/default/zramswap
echo "vm.swappiness=10" > /etc/sysctl.d/99-hyper.conf

# KDE optimization
mkdir -p /etc/skel/.config
cat <<KDE > /etc/skel/.config/baloofilerc
[Basic Settings]
Indexing-Enabled=false
KDE

# Reset identity
truncate -s 0 /etc/machine-id

# Cleanup
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

    chmod +x "$ROOTFS_DIR/tmp/setup.sh"
    chroot "$ROOTFS_DIR" /bin/bash /tmp/setup.sh
    rm -f "$ROOTFS_DIR/tmp/setup.sh"
}

# =========================
# Stage 3: Compress
# =========================
stage_compress() {
    log "Creating SquashFS..."

    local out="$OUT_DIR/filesystem.squashfs"

    mksquashfs "$ROOTFS_DIR" "$out" \
        -comp zstd -Xcompression-level 17 \
        -b 1M -processors "$(nproc)" \
        -noappend -always-use-fragments

    [[ -f "$out" ]] || die "SquashFS failed"

    log "Created: $out"
}

# =========================
# Stage 4: Verify
# =========================
stage_verify() {
    log "Verifying artifact..."

    local file="$OUT_DIR/filesystem.squashfs"

    [[ -f "$file" ]] || die "Missing SquashFS"

    sha256sum "$file" > "$file.sha256"

    log "Size: $(du -h "$file" | cut -f1)"
    log "Checksum generated."
}

# =========================
# CLI
# =========================
main() {
    require_root
    check_deps

    case "${1:-build}" in
        clean) clean ;;
        build)
            prepare_dirs
            stage_bootstrap
            stage_configure
            stage_compress
            stage_verify
            ;;
        rebuild)
            clean
            "$0" build
            ;;
        *)
            echo "Usage: $0 [build|clean|rebuild]"
            exit 1
            ;;
    esac
}

main "$@"
