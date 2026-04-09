#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/build-common.sh
source "$SCRIPT_DIR/lib/build-common.sh"

DEBUG_MODE=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--debug]
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug)
        DEBUG_MODE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

build_grub_cfg() {
  cat > "$ISO_DIR/boot/grub/grub.cfg" <<'GRUBCFG'
set default=0
set timeout=8

menuentry "Hyper OS" {
  linux /live/vmlinuz boot=live components quiet splash noeject toram fsck.mode=force fsck.repair=yes
  initrd /live/initrd.img
}

menuentry "Hyper OS (Safe Mode)" {
  linux /live/vmlinuz boot=live components noapic nolapic nomodeset noeject toram fsck.mode=force fsck.repair=yes
  initrd /live/initrd.img
}

menuentry "Hyper OS (Verbose)" {
  linux /live/vmlinuz boot=live components noeject toram fsck.mode=force fsck.repair=yes systemd.log_level=debug loglevel=7
  initrd /live/initrd.img
}

menuentry "Hyper OS (Debug Mode)" {
  linux /live/vmlinuz boot=live components noeject toram debug systemd.log_level=debug loglevel=7 rd.systemd.show_status=1
  initrd /live/initrd.img
}
GRUBCFG
}

verify_rootfs_mount_safety() {
  local path
  for path in proc sys dev run; do
    if mountpoint -q "$ROOTFS_DIR/$path" 2>/dev/null; then
      die "Refusing to squashfs mounted path: $ROOTFS_DIR/$path"
    fi
  done
}

validate_build_inputs() {
  [[ -d "$ROOTFS_DIR" ]] || die "Missing rootfs directory: $ROOTFS_DIR"
  [[ -x "$ROOTFS_DIR/sbin/init" || -x "$ROOTFS_DIR/lib/systemd/systemd" ]] || die "No init system found in rootfs"
  [[ -d "$ROOTFS_DIR/lib/live" ]] || die "Missing live-boot runtime directory: $ROOTFS_DIR/lib/live"
}

main() {
  parse_args "$@"
  [[ "$DEBUG_MODE" -eq 1 ]] && set -x

  use_shared_logging
  require_root
  require_cmds grub-mkrescue xorriso find cp mv mksquashfs unsquashfs sha256sum

  validate_build_inputs

  log INFO "Preparing ISO staging tree"
  rm -rf "$ISO_DIR"
  mkdir -p "$ISO_DIR/boot/grub" "$ISO_DIR/live"

  local kernel_path initrd_path
  kernel_path="$(find "$ROOTFS_DIR/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n1)"
  initrd_path="$(find "$ROOTFS_DIR/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort -V | tail -n1)"
  [[ -n "$kernel_path" ]] || die "Kernel not found in $ROOTFS_DIR/boot"
  [[ -n "$initrd_path" ]] || die "Initrd not found in $ROOTFS_DIR/boot"
  [[ -f "$kernel_path" ]] || die "Kernel path is not a regular file: $kernel_path"
  [[ -f "$initrd_path" ]] || die "Initrd path is not a regular file: $initrd_path"

  log INFO "Sanitizing rootfs before squashfs"
  rm -f "$ROOTFS_DIR/etc/resolv.conf"
  install -d -m 1777 "$ROOTFS_DIR/tmp" "$ROOTFS_DIR/var/tmp"
  find "$ROOTFS_DIR/tmp" -mindepth 1 -delete
  find "$ROOTFS_DIR/var/tmp" -mindepth 1 -delete

  verify_rootfs_mount_safety

  log INFO "Generating live squashfs"
  rm -f "$ISO_DIR/live/filesystem.squashfs"
  local squashfs_processors="1"

    die "Failed to generate $ISO_DIR/live/filesystem.squashfs"
  fi

  log INFO "Validating squashfs integrity"
  unsquashfs -t "$ISO_DIR/live/filesystem.squashfs" >/dev/null
  sha256sum "$ISO_DIR/live/filesystem.squashfs" > "$ISO_DIR/live/filesystem.squashfs.sha256"

  cp "$kernel_path" "$ISO_DIR/live/vmlinuz"
  cp "$initrd_path" "$ISO_DIR/live/initrd.img"
  build_grub_cfg

  log INFO "Building hybrid BIOS/UEFI ISO image"
  if ! grub-mkrescue -o "$ISO_PATH.tmp" "$ISO_DIR"; then
    die "grub-mkrescue failed while creating ISO"
  fi
  mv -f "$ISO_PATH.tmp" "$ISO_PATH"

  log INFO "ISO output: $ISO_PATH"
}

main "$@"
