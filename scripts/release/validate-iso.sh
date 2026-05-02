#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[release-validate] failed at line $LINENO" >&2' ERR

ISO_PATH="${1:-}"
[[ -n "$ISO_PATH" ]] || { echo "usage: $0 /path/to.iso" >&2; exit 1; }
[[ -f "$ISO_PATH" ]] || { echo "iso not found: $ISO_PATH" >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
LOG_DIR="${LOG_DIR:-$TMP_DIR}"
QEMU_LOG="$LOG_DIR/qemu-boot.log"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE.fd}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }
}

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

check_artifacts() {
  echo "[release-validate] checking checksum"
  [[ -f "$ISO_PATH.sha256" ]] && sha256sum -c "$ISO_PATH.sha256"

  echo "[release-validate] checking boot catalog"
  xorriso -indev "$ISO_PATH" -report_el_torito plain | grep -qi 'UEFI'
}

check_embedded_metadata() {
  echo "[release-validate] checking embedded version metadata"
  xorriso -osirrox on -indev "$ISO_PATH" -extract /arch/x86_64/airootfs.sfs "$TMP_DIR/airootfs.sfs" >/dev/null 2>&1
  unsquashfs -d "$TMP_DIR/rootfs" "$TMP_DIR/airootfs.sfs" etc/hyper-release >/dev/null
  [[ -s "$TMP_DIR/rootfs/etc/hyper-release" ]]
  grep -q '^HYPER_VERSION=' "$TMP_DIR/rootfs/etc/hyper-release"
}

qemu_smoke_test() {
  if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    if [[ "${ALLOW_MISSING_QEMU:-0}" == "1" ]]; then
      echo "[release-validate] qemu missing; skipping by policy"
      return 0
    fi
    echo "qemu-system-x86_64 missing" >&2
    exit 1
  fi

  [[ -f "$OVMF_CODE" ]] || { echo "OVMF firmware missing: $OVMF_CODE" >&2; exit 1; }

  echo "[release-validate] qemu uefi smoke boot"
  timeout 180 qemu-system-x86_64 \
    -machine q35,accel=tcg \
    -m 3072 \
    -smp 2 \
    -nographic \
    -serial mon:stdio \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -cdrom "$ISO_PATH" \
    -boot d > "$QEMU_LOG" 2>&1 || true

  grep -Eiq 'Welcome to|Reached target Graphical Interface|lightdm' "$QEMU_LOG"
}

main() {
  require_cmd xorriso
  require_cmd unsquashfs

  check_artifacts
  check_embedded_metadata
  qemu_smoke_test

  echo "[release-validate] validation passed"
}

main "$@"
