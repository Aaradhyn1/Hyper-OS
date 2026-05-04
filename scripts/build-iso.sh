#!/usr/bin/env bash
set -Eeuo pipefail

# --- Enhanced Path Handling & Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-common.sh"

# Performance Tuning Constants
ZSTD_LEVEL=19         # Higher for smaller ISOs, 15-19 is the sweet spot for Zstd
BLOCK_SIZE="1M"       # Larger blocks improve compression ratio for OS files
SQUASH_MEM="85%"      # Use up to 85% of RAM for mksquashfs speed

DEBUG_MODE=0

# --- Advanced GRUB: Added Persistence & Serial Support ---
build_grub_cfg() {
  log INFO "Generating Advanced GRUB Configuration"
  cat > "$ISO_DIR/boot/grub/grub.cfg" <<'GRUBCFG'
set default=0
set timeout=5
set gfxmode=auto
insmod all_video

# Serial console support for headless debugging
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_input serial console
terminal_output serial console

menuentry "Hyper OS (Live Performance Mode)" {
  linux /live/vmlinuz boot=live components quiet splash noeject toram \
        elevator=noop intel_idle.max_cstate=1 processor.max_cstate=1 \
        fsck.repair=yes
  initrd /live/initrd.img
}

menuentry "Hyper OS (Persistence Mode)" {
  linux /live/vmlinuz boot=live components persistence persistence-label=HYPER_PERSIST \
        quiet splash noeject
  initrd /live/initrd.img
}

menuentry "Hyper OS (Persistence Fallback: read-only live session)" {
  linux /live/vmlinuz boot=live components nopersistence quiet splash noeject
  initrd /live/initrd.img
}

menuentry "Hyper OS (Live Standard)" {
  linux /live/vmlinuz boot=live components quiet splash noeject
  initrd /live/initrd.img
}

menuentry "Hyper OS (Hardware Detection/Safe Mode)" {
  linux /live/vmlinuz boot=live components noapic nolapic nomodeset noeject \
        irqpoll maxcpus=1 xforcevesa
  initrd /live/initrd.img
}
GRUBCFG
}

validate_initramfs_persistence_support() {
  local initrd_path="$1"

  if ! command -v lsinitramfs >/dev/null 2>&1; then
    log WARN "lsinitramfs not available on builder host; skipping initrd persistence hook validation"
    return 0
  fi

  log INFO "Validating initramfs live-boot persistence hooks"
  if ! lsinitramfs "$initrd_path" | grep -Eq '^scripts/live|/live-boot/'; then
    die "initrd is missing live-boot persistence hooks. Ensure live-boot is installed in rootfs and initramfs is regenerated."
  fi
}

validate_iso_boot_artifacts() {
  local iso_path="$1"
  log INFO "Validating ISO UEFI/BIOS boot artifacts"

  xorriso -indev "$iso_path" -find /EFI/BOOT/BOOTX64.EFI -print -quit | grep -q '/EFI/BOOT/BOOTX64.EFI' \
    || die "Missing UEFI fallback loader: /EFI/BOOT/BOOTX64.EFI"

  local eltorito_report
  eltorito_report="$(xorriso -indev "$iso_path" -report_el_torito plain 2>/dev/null || true)"
  grep -qi 'platform id[[:space:]]*:[[:space:]]*0x00' <<<"$eltorito_report" \
    || die "Missing El Torito BIOS boot image (platform 0x00)"
  grep -qi 'platform id[[:space:]]*:[[:space:]]*0xef' <<<"$eltorito_report" \
    || die "Missing El Torito EFI boot image (platform 0xEF)"
}

# --- Intelligent SquashFS Sorting ---
# Groups critical boot files at the start of the image to reduce seek time
generate_sort_file() {
  local sort_file="$BUILD_DIR/squashfs-sort.txt"
  log INFO "Generating predictive I/O sort file"
  cat > "$sort_file" <<EOF
boot/* 32767
lib/modules/*/kernel/drivers/gpu/* 30000
lib/systemd/* 28000
usr/lib/systemd/* 28000
bin/* 25000
sbin/* 25000
lib/* 20000
usr/bin/* 15000
usr/sbin/* 15000
EOF
}

main() {
  parse_args "$@"
  [[ "$DEBUG_MODE" -eq 1 ]] && set -x

  use_shared_logging
  require_root
  require_cmds grub-mkrescue xorriso mksquashfs zstd nproc

  validate_build_inputs

  log INFO "Syncing ISO tree and cleaning artifacts"
  rm -rf "$ISO_DIR"
  mkdir -p "$ISO_DIR/boot/grub" "$ISO_DIR/live"

  # Find latest kernel/initrd with a fallback check
  local kernel_path initrd_path
  kernel_path=$(ls -v "$ROOTFS_DIR/boot/vmlinuz-"* | tail -n1)
  initrd_path=$(ls -v "$ROOTFS_DIR/boot/initrd.img-"* | tail -n1)
  
  [[ -f "$kernel_path" && -f "$initrd_path" ]] || die "Kernel/Initrd discovery failed."
  validate_initramfs_persistence_support "$initrd_path"

  # --- Advanced RootFS Sanitization ---
  log INFO "Sanitizing RootFS (Machine IDs, Logs, Temp)"
  [[ -f "$ROOTFS_DIR/etc/machine-id" ]] && truncate -s 0 "$ROOTFS_DIR/etc/machine-id"
  rm -f "$ROOTFS_DIR/var/lib/dbus/machine-id"
  find "$ROOTFS_DIR/var/log" -type f -delete
  find "$ROOTFS_DIR/root/" -mindepth 1 -delete

  verify_rootfs_mount_safety
  generate_sort_file

  # --- High-Performance SquashFS Compression ---
  log INFO "Building SquashFS with Zstd (Level: $ZSTD_LEVEL)"
  mksquashfs "$ROOTFS_DIR" "$ISO_DIR/live/filesystem.squashfs" \
    -e boot proc sys dev run tmp var/tmp .build_info \
    -comp zstd -Xcompression-level "$ZSTD_LEVEL" \
    -b "$BLOCK_SIZE" -mem "$SQUASH_MEM" \
    -sort "$BUILD_DIR/squashfs-sort.txt" \
    -processors "$(nproc)" \
    -noappend -always-use-fragments

  # Generate checksums for the live environment to verify at boot
  cd "$ISO_DIR" && find . -type f -not -path './boot/*' -exec md5sum {} + > live/filesystem.packages.md5sum
  
  cp "$kernel_path" "$ISO_DIR/live/vmlinuz"
  cp "$initrd_path" "$ISO_DIR/live/initrd.img"
  build_grub_cfg

  # --- Hybrid ISO Generation ---
  log INFO "Finalizing Hybrid BIOS/UEFI ISO"
  grub-mkrescue -o "$ISO_PATH" "$ISO_DIR" \
    -- -volid "HYPER_OS_$(date +%Y%m%d)" \
    -preparer "HyperOS-Builder" \
    -publisher "YourName"

  validate_iso_boot_artifacts "$ISO_PATH"

  log INFO "Build Successful: $ISO_PATH"
}

main "$@"
