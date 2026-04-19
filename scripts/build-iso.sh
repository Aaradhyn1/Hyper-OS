#!/usr/bin/env bash
# Hyper OS - Ultimate Build Pipeline (Production Grade)
set -Eeuo pipefail
trap 'echo "[FATAL] Error at line $LINENO"; exit 1' ERR

# =========================
# Global Config
# =========================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_DIR="$SCRIPT_DIR/build"
readonly ROOTFS_DIR="$BUILD_DIR/rootfs"
readonly ISO_DIR="$BUILD_DIR/iso"
readonly OUT_DIR="$BUILD_DIR/out"
readonly CACHE_DIR="$BUILD_DIR/.cache"

readonly ISO_NAME="hyperos"
readonly ISO_LABEL="HYPER_OS_$(date +%Y%m%d)"
readonly ISO_PATH="$OUT_DIR/${ISO_NAME}.iso"

readonly ARCH="amd64"
readonly DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
readonly MIRROR="${MIRROR:-http://deb.debian.org/debian}"

readonly ZSTD_LEVEL="${ZSTD_LEVEL:-19}"
readonly BLOCK_SIZE="1M"
readonly SQUASH_MEM="75%"

LOG_TAG="[Titan-Core]"

# =========================
# Logging
# =========================
log()   { printf "\e[1;34m%s [INFO] %s\e[0m\n" "$(date +%H:%M:%S)" "$*"; }
warn()  { printf "\e[1;33m%s [WARN] %s\e[0m\n" "$(date +%H:%M:%S)" "$*" >&2; }
die()   { printf "\e[1;31m%s [FATAL] %s\e[0m\n" "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# =========================
# Cleanup (Safe Reverse Unmount)
# =========================
cleanup() {
    log "Unmounting build mounts..."
    mount | grep "$ROOTFS_DIR" | awk '{print $3}' | tac | xargs -r umount -lf || true
}
trap cleanup EXIT

# =========================
# Preconditions
# =========================
require_root() { [[ $EUID -eq 0 ]] || die "Run as root"; }

require_cmds() {
    local missing=0
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null || { warn "Missing: $cmd"; missing=1; }
    done
    [[ $missing -eq 0 ]] || die "Install missing dependencies"
}

prepare_dirs() {
    mkdir -p "$ROOTFS_DIR" "$ISO_DIR/boot/grub" "$ISO_DIR/live" "$OUT_DIR" "$CACHE_DIR"
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

    if [[ -d "$ROOTFS_DIR/bin" ]]; then
        warn "RootFS exists, skipping bootstrap"
        return
    fi

    debootstrap \
        --arch="$ARCH" \
        --variant=minbase \
        --include="linux-image-amd64,systemd-sysv,live-boot,sudo,plasma-desktop,sddm,network-manager,ca-certificates" \
        "$DEBIAN_SUITE" "$ROOTFS_DIR" "$MIRROR"
}

# =========================
# Stage 2: Configure
# =========================
stage_configure() {
    log "Configuring system..."

    mount --bind /dev "$ROOTFS_DIR/dev"
    mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
    mount --bind /proc "$ROOTFS_DIR/proc"
    mount --bind /sys "$ROOTFS_DIR/sys"

    cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

    cat <<'EOF' > "$ROOTFS_DIR/tmp/setup.sh"
set -e
export DEBIAN_FRONTEND=noninteractive

echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list

apt-get update
apt-get install -y firmware-linux firmware-linux-nonfree zram-tools

# Performance tuning
cat <<EOT > /etc/sysctl.d/99-hyper.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
kernel.nmi_watchdog=0
EOT

# ZRAM
echo "ALGO=zstd" > /etc/default/zramswap
echo "PERCENT=50" >> /etc/default/zramswap

# KDE optimization
mkdir -p /etc/skel/.config
echo -e "[Basic Settings]\nIndexing-Enabled=false" > /etc/skel/.config/baloofilerc

# Identity
echo "Hyper OS Titan $(date)" > /etc/hyper-release

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
# Stage 3: Sanitize
# =========================
stage_sanitize() {
    log "Sanitizing rootfs..."

    truncate -s 0 "$ROOTFS_DIR/etc/machine-id" || true
    rm -f "$ROOTFS_DIR/var/lib/dbus/machine-id"

    rm -rf "$ROOTFS_DIR/tmp/"* "$ROOTFS_DIR/var/tmp/"* "$ROOTFS_DIR/var/log/"*
    rm -rf "$ROOTFS_DIR/root/"*

    rm -f "$ROOTFS_DIR/etc/hostname" "$ROOTFS_DIR/etc/resolv.conf"
}

# =========================
# Stage 4: SquashFS
# =========================
stage_squashfs() {
    log "Creating SquashFS..."

    local squash="$ISO_DIR/live/filesystem.squashfs"

    mksquashfs "$ROOTFS_DIR" "$squash" \
        -comp zstd -Xcompression-level "$ZSTD_LEVEL" \
        -b "$BLOCK_SIZE" -mem "$SQUASH_MEM" \
        -processors "$(nproc)" \
        -noappend -always-use-fragments

    [[ -f "$squash" ]] || die "SquashFS failed"
}

# =========================
# Stage 5: Bootloader
# =========================
stage_bootloader() {
    log "Setting up bootloader..."

    local kernel initrd
    kernel=$(find "$ROOTFS_DIR/boot" -name 'vmlinuz-*' | sort -V | tail -n1)
    initrd=$(find "$ROOTFS_DIR/boot" -name 'initrd.img-*' | sort -V | tail -n1)

    [[ -f "$kernel" ]] || die "Kernel missing"
    [[ -f "$initrd" ]] || die "Initrd missing"

    cp "$kernel" "$ISO_DIR/live/vmlinuz"
    cp "$initrd" "$ISO_DIR/live/initrd.img"

    cat > "$ISO_DIR/boot/grub/grub.cfg" <<'GRUB'
set timeout=3
set default=0

menuentry "Hyper OS (Live)" {
    linux /live/vmlinuz boot=live components quiet splash mitigations=off
    initrd /live/initrd.img
}
GRUB
}

# =========================
# Stage 6: ISO Build
# =========================
stage_iso() {
    log "Building ISO..."

    grub-mkrescue -o "$ISO_PATH" "$ISO_DIR" \
        -- -volid "$ISO_LABEL" \
        -preparer "HyperOS Titan" \
        -publisher "HyperOS"

    [[ -f "$ISO_PATH" ]] || die "ISO build failed"
}

# =========================
# Stage 7: Verify
# =========================
stage_verify() {
    log "Verifying ISO..."

    sha256sum "$ISO_PATH" > "$ISO_PATH.sha256"

    xorriso -indev "$ISO_PATH" -find /EFI/BOOT/BOOTX64.EFI -quit >/dev/null \
        || die "UEFI boot missing"

    log "ISO verified successfully"
}

# =========================
# Stage 8: Test
# =========================
stage_test() {
    log "Testing in QEMU..."

    qemu-system-x86_64 \
        -m 2048 \
        -cdrom "$ISO_PATH" \
        -boot d \
        -enable-kvm \
        -cpu host \
        -smp "$(nproc)" \
        -serial mon:stdio || warn "QEMU test failed"
}

# =========================
# CLI
# =========================
main() {
    require_root
    require_cmds debootstrap mksquashfs grub-mkrescue xorriso qemu-system-x86_64

    case "${1:-build}" in
        clean) clean ;;
        build)
            prepare_dirs
            stage_bootstrap
            stage_configure
            stage_sanitize
            stage_squashfs
            stage_bootloader
            stage_iso
            stage_verify
            ;;
        test) stage_test ;;
        rebuild) clean; "$0" build ;;
        *) echo "Usage: $0 [build|clean|rebuild|test]" ;;
    esac
}

main "$@"
