#!/usr/bin/env bash
set -Eeuo pipefail

ISO_PATH="${1:-./hyperos.iso}"

log() { printf '[prelaunch] %s\n' "$*"; }
warn() { printf '[prelaunch][WARN] %s\n' "$*" >&2; }

if [[ ! -f "$ISO_PATH" ]]; then
  warn "ISO not found at $ISO_PATH"
  exit 1
fi

log "Computing SHA256"
sha256sum "$ISO_PATH" | tee "$ISO_PATH.sha256"

log "Static checks"
if command -v xorriso >/dev/null 2>&1; then
  xorriso -indev "$ISO_PATH" -find /EFI/BOOT/BOOTX64.EFI -print -quit >/dev/null || warn "Missing UEFI fallback file"
else
  warn "xorriso not installed; skipping boot artifact check"
fi

cat <<'CMDS'

Run these manual validation commands:
  # QEMU UEFI
  qemu-system-x86_64 -m 4096 -enable-kvm -cdrom ./hyperos.iso \
    -bios /usr/share/OVMF/OVMF_CODE.fd -boot d

  # QEMU BIOS
  qemu-system-x86_64 -m 4096 -enable-kvm -cdrom ./hyperos.iso -boot d

  # Validate cloud updater in live session
  sudo systemctl start hyperos-profile-update.service
  sudo journalctl -u hyperos-profile-update.service -n 50 --no-pager
CMDS

log "Checklist helper completed"
