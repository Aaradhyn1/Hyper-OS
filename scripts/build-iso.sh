#!/usr/bin/env bash
# Hyper OS - Ultimate Build Pipeline (Final)
set -Eeuo pipefail

# =========================
# Global Config
# =========================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_DIR="$SCRIPT_DIR/build"
readonly ROOTFS_DIR="$BUILD_DIR/rootfs"
readonly ISO_DIR="$BUILD_DIR/iso"
readonly OUT_DIR="$BUILD_DIR/out"

readonly ISO_NAME="hyperos"
readonly ISO_LABEL="HYPER_OS_$(date +%Y%m%d)"
readonly ISO_PATH="$OUT_DIR/${ISO_NAME}.iso"

readonly ARCH="amd64"
readonly DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
readonly ZSTD_LEVEL="${ZSTD_LEVEL:-17}"
readonly BLOCK_SIZE="1M"
readonly SQUASH_MEM="80%"

# =========================
# Logging
# =========================
log()   { printf "\e[1;34m[INFO]\e[0m %s\n" "$*"; }
warn()  { printf "\e[1;33m[WARN]\e[0m %s\n" "$*" >&2; }
die()   { printf "\e[1;31m[FATAL]\e[0m %s\n" "$*" >&2; exit 1; }

# =========================
# Cleanup (Reverse Unmount)
# =========================
cleanup() {
    log "Cleaning mounts..."
    tac < <(mount | grep "$ROOTFS_DIR" | awk '{print $3}') | xargs -r umount -lf || true
}
trap cleanup EXIT

# =========================
# Preconditions
# =========================
require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root."
}

require_cmds() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null || die "Missing dependency: $cmd"
    done
}

prepare_dirs() {
    mkdir -p "$ROOTFS_DIR" "$ISO_DIR/boot/grub" "$ISO_DIR/live" "$OUT_DIR"
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
        warn "RootFS exists, skipping bootstrap"
        return
    }

    debootstrap \
        --variant=minbase \
        --arch="$ARCH" \
        --include="linux-image-amd64,systemd-sysv,live-boot,sudo,plasma-desktop,sddm,network-manager" \
        "$DEBIAN_SUITE" "$ROOTFS_DIR" "http://deb.debian.org/debian"
}

# =========================
# Stage 2: Configure
# =========================
stage_configure() {
    log "Configuring system..."

    mkdir -p "$ROOTFS_DIR/tmp"

    mount --bind /dev "$ROOTFS_DIR/dev"
    mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"
    mount --bind /proc "$ROOTFS_DIR/proc"
    mount --bind /sys "$ROOTFS_DIR/sys"

    cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

    cat <<'EOF' > "$ROOTFS_DIR/tmp/setup.sh"
set -e
export DEBIAN_FRONTEND=noninteractive

# Enable firmware
sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt-get update
apt-get install -y firmware-linux firmware-linux-nonfree

# Performance tweaks
echo "vm.swappiness=10" > /etc/sysctl.d/99-hyper.conf
echo "ALGO=zstd" > /etc/default/zramswap

# KDE optimization
mkdir -p /etc/skel/.config
echo -e "[Basic Settings]\nIndexing-Enabled=false" > /etc/skel/.config/baloofilerc

# Identity
echo "Hyper OS $(date)" > /etc/hyper-release

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
# Stage 3: Sanitize
# =========================
stage_sanitize() {
    log "Sanitizing rootfs..."

    truncate -s 0 "$ROOTFS_DIR/etc/machine-id" || true
    rm -f "$ROOTFS_DIR/var/lib/dbus/machine-id"

    rm -rf "$ROOTFS_DIR/tmp/"*
    rm -rf "$ROOTFS_DIR/var/tmp/"*
    rm -rf "$ROOTFS_DIR/var/log/"*
    rm -rf "$ROOTFS_DIR/root/"*

    rm -f "$ROOTFS_DIR/etc/hostname"
    rm -f "$ROOTFS_DIR/etc/resolv.conf"
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

    [[ -f "$squash" ]] || die "SquashFS creation failed"
}

# =========================
# Stage 5: Bootloader
# =========================
stage_bootloader() {
    log "Setting up bootloader..."

    local kernel initrd

    kernel="$(find "$ROOTFS_DIR/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n1)"
    initrd="$(find "$ROOTFS_DIR/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort -V | tail -n1)"

    [[ -f "$kernel" ]] || die "Kernel not found"
    [[ -f "$initrd" ]] || die "Initrd not found"

    cp "$kernel" "$ISO_DIR/live/vmlinuz"
    cp "$initrd" "$ISO_DIR/live/initrd.img"

    cat > "$ISO_DIR/boot/grub/grub.cfg" <<'GRUB'
set timeout=5
set default=0

menuentry "Hyper OS (Live)" {
  linux /live/vmlinuz boot=live components quiet splash
  initrd /live/initrd.img
}

menuentry "Hyper OS (Persistence)" {
  linux /live/vmlinuz boot=live persistence persistence-label=HYPER_PERSIST quiet splash
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
        -preparer "HyperOS" \
        -publisher "HyperOS"

    [[ -f "$ISO_PATH" ]] || die "ISO build failed"
}

# =========================
# Stage 7: Verify
# =========================
stage_verify() {
    log "Verifying ISO..."

    sha256sum "$ISO_PATH" > "$ISO_PATH.sha256"

    # UEFI check
    xorriso -indev "$ISO_PATH" -find /EFI/BOOT/BOOTX64.EFI -quit >/dev/null \
        || die "UEFI boot missing"

    # BIOS check
    xorriso -indev "$ISO_PATH" -report_el_torito plain | grep -qi "platform id.*0x00" \
        || die "BIOS boot missing"

    log "ISO verified: $ISO_PATH"
}

# =========================
# Stage 8: Test (QEMU)
# =========================
stage_test() {
    log "Launching QEMU test..."

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
        test)
            stage_test
            ;;
        rebuild)
            clean
            "$0" build
            ;;
        *)
            echo "Usage: $0 [build|clean|rebuild|test]"
            exit 1
            ;;
    esac
}

main "$@"
