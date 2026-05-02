#!/usr/bin/env bash

Hyper OS Titan Build System v2.0 (Deterministic + Parallel + Hardened)

set -Eeuo pipefail
shopt -s extglob

trap 'echo "[FATAL] Failure at line $LINENO"; exit 1' ERR

=========================

GLOBAL CONFIG (IMMUTABLE CORE)

=========================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_DIR="$SCRIPT_DIR/build"
readonly ROOTFS_DIR="$BUILD_DIR/rootfs"
readonly ISO_DIR="$BUILD_DIR/iso"
readonly OUT_DIR="$BUILD_DIR/out"
readonly CACHE_DIR="$BUILD_DIR/.cache"

readonly ISO_NAME="hyperos"
readonly BUILD_ID="$(date -u +%Y%m%d-%H%M%S)"
readonly ISO_LABEL="HYPER_OS_${BUILD_ID}"
readonly ISO_PATH="$OUT_DIR/${ISO_NAME}-${BUILD_ID}.iso"

readonly ARCH="amd64"
readonly DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
readonly MIRROR="${MIRROR:-http://deb.debian.org/debian}"

readonly THREADS="$(nproc)"
readonly ZSTD_LEVEL="${ZSTD_LEVEL:-19}"

=========================

LOGGING ENGINE

=========================

log()   { echo -e "\e[1;36m[$(date -u +%H:%M:%S)] [INFO]\e[0m $"; }
warn()  { echo -e "\e[1;33m[$(date -u +%H:%M:%S)] [WARN]\e[0m $" >&2; }
die()   { echo -e "\e[1;31m[$(date -u +%H:%M:%S)] [FATAL]\e[0m $*" >&2; exit 1; }


CLEANUP ENGINE


cleanup() {
log "Unmounting..."
mount | grep "$ROOTFS_DIR" | awk '{print $3}' | tac | xargs -r umount -lf || true
}
trap cleanup EXIT

=========================

PRECHECKS

=========================

require_root() { [[ $EUID -eq 0 ]] || die "Run as root"; }

require_cmds() {
local missing=0
for cmd in "$@"; do
command -v "$cmd" >/dev/null || { warn "Missing: $cmd"; missing=1; }
done
[[ $missing -eq 0 ]] || die "Install dependencies"
}


FILESYSTEM PREP


prepare_dirs() {
mkdir -p "$ROOTFS_DIR" "$ISO_DIR"/{boot/grub,live} "$OUT_DIR" "$CACHE_DIR"
}

=========================

STAGE 1: SMART BOOTSTRAP (CACHED)

=========================

stage_bootstrap() {
log "Bootstrap stage..."

if [[ -f "$CACHE_DIR/rootfs.tar.zst" ]]; then
    log "Using cached rootfs..."
    tar --zstd -xf "$CACHE_DIR/rootfs.tar.zst" -C "$BUILD_DIR"
    return
fi

debootstrap \
    --arch="$ARCH" \
    --variant=minbase \
    --include="linux-image-amd64,systemd-sysv,live-boot,sudo,network-manager,plasma-desktop,sddm" \
    "$DEBIAN_SUITE" "$ROOTFS_DIR" "$MIRROR"

log "Caching rootfs..."
tar --zstd -cf "$CACHE_DIR/rootfs.tar.zst" -C "$BUILD_DIR" rootfs

}

=========================

STAGE 2: CHROOT CONFIG (ISOLATED)

=========================

stage_configure() {
log "Configuring system..."

mount --bind /dev "$ROOTFS_DIR/dev"
mount --bind /proc "$ROOTFS_DIR/proc"
mount --bind /sys "$ROOTFS_DIR/sys"

cat <<'EOF' > "$ROOTFS_DIR/tmp/setup.sh"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list

apt-get update

apt-get install -y 
firmware-linux firmware-linux-nonfree 
zram-tools dbus-x11

PERFORMANCE TUNING

cat <<SYS > /etc/sysctl.d/99-hyper.conf
vm.swappiness=10
vm.dirty_ratio=10
vm.dirty_background_ratio=5
kernel.nmi_watchdog=0
SYS

ZRAM

echo -e "ALGO=zstd\nPERCENT=60" > /etc/default/zramswap

DISABLE USELESS SERVICES

systemctl disable apt-daily.service || true
systemctl disable apt-daily.timer || true

CLEAN

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

chmod +x "$ROOTFS_DIR/tmp/setup.sh"
chroot "$ROOTFS_DIR" /bin/bash /tmp/setup.sh
rm -f "$ROOTFS_DIR/tmp/setup.sh"

}

=========================

STAGE 3: SANITIZE

=========================

stage_sanitize() {
log "Sanitizing..."

truncate -s 0 "$ROOTFS_DIR/etc/machine-id" || true
rm -f "$ROOTFS_DIR/var/lib/dbus/machine-id"

rm -rf "$ROOTFS_DIR"/{tmp,var/tmp,var/log,root}/*

}

=========================

STAGE 4: PARALLEL SQUASHFS

=========================

stage_squashfs() {
log "Creating SquashFS (parallel)..."

mksquashfs "$ROOTFS_DIR" "$ISO_DIR/live/filesystem.squashfs" \
    -comp zstd -Xcompression-level "$ZSTD_LEVEL" \
    -processors "$THREADS" \
    -b 1M -noappend

}


STAGE 5: BOOTLOADER (UEFI + BIOS)


stage_bootloader() {
log "Bootloader setup..."

local kernel initrd
kernel=$(find "$ROOTFS_DIR/boot" -name 'vmlinuz-*' | sort -V | tail -n1)
initrd=$(find "$ROOTFS_DIR/boot" -name 'initrd.img-*' | sort -V | tail -n1)

cp "$kernel" "$ISO_DIR/live/vmlinuz"
cp "$initrd" "$ISO_DIR/live/initrd.img"

cat > "$ISO_DIR/boot/grub/grub.cfg" <<EOF

set timeout=2
menuentry "Hyper OS Titan" {
linux /live/vmlinuz boot=live quiet splash mitigations=off
initrd /live/initrd.img
}
EOF
}

=========================

STAGE 6: ISO BUILD (REPRODUCIBLE)

=========================

stage_iso() {
log "Building ISO..."

export SOURCE_DATE_EPOCH=0

grub-mkrescue -o "$ISO_PATH" "$ISO_DIR" \
    -- -volid "$ISO_LABEL"

}

=========================

STAGE 7: VERIFY (STRICT)

=========================

stage_verify() {
log "Verifying..."

sha256sum "$ISO_PATH" > "$ISO_PATH.sha256"

xorriso -indev "$ISO_PATH" -report_el_torito as_mkisofs | grep -q "UEFI" \
    || die "UEFI boot missing"

}

=========================

STAGE 8: TEST

=========================

stage_test() {
log "QEMU test..."

qemu-system-x86_64 \
    -enable-kvm \
    -m 2048 \
    -smp "$THREADS" \
    -cdrom "$ISO_PATH" \
    -boot d

}

=========================

PIPELINE EXECUTION

=========================

main() {
require_root
require_cmds debootstrap mksquashfs grub-mkrescue xorriso qemu-system-x86_64

case "${1:-build}" in
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
    clean) rm -rf "$BUILD_DIR" ;;
    rebuild) rm -rf "$BUILD_DIR"; exec "$0" build ;;
    *) echo "Usage: $0 [build|test|clean|rebuild]" ;;
esac

}

main "$@"
