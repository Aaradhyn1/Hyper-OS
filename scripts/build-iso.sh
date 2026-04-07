#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/build-common.sh
source "$SCRIPT_DIR/lib/build-common.sh"

build_grub_cfg() {
  cat > "$ISO_DIR/boot/grub/grub.cfg" <<'GRUBCFG'
set default=0
set timeout=3

menuentry "Hyper OS" {
  linux /boot/vmlinuz boot=live quiet root=/dev/sr0 ro console=tty0 console=ttyS0,115200n8 systemd.unit=multi-user.target
  initrd /boot/initrd.img
}
GRUBCFG
}

main() {
  use_shared_logging
  require_root
  require_cmds grub-mkrescue xorriso find cp mv
  [[ -d "$ROOTFS_DIR/boot" ]] || die "Rootfs boot directory missing: $ROOTFS_DIR/boot"

  log INFO "Preparing ISO staging tree"
  rm -rf "$ISO_DIR"
  mkdir -p "$ISO_DIR/boot/grub"

  local kernel_path initrd_path
  kernel_path="$(find "$ROOTFS_DIR/boot" -maxdepth 1 -name 'vmlinuz-*' | head -n1)"
  initrd_path="$(find "$ROOTFS_DIR/boot" -maxdepth 1 -name 'initrd.img-*' | head -n1)"
  [[ -n "$kernel_path" ]] || die "Kernel not found in $ROOTFS_DIR/boot"
  [[ -n "$initrd_path" ]] || die "Initrd not found in $ROOTFS_DIR/boot"

  cp "$kernel_path" "$ISO_DIR/boot/vmlinuz"
  cp "$initrd_path" "$ISO_DIR/boot/initrd.img"
  build_grub_cfg

  log INFO "Building ISO image"
  grub-mkrescue -o "$ISO_PATH.tmp" "$ISO_DIR"
  mv -f "$ISO_PATH.tmp" "$ISO_PATH"

  log INFO "ISO output: $ISO_PATH"
}

main "$@"
