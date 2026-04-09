#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDROOT_DIR="${BUILDROOT_DIR:-$ROOT_DIR/buildroot}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/out/rpi4}"
OFFLINE_FALLBACK="${OFFLINE_FALLBACK:-1}"

run_offline_bundle() {
  local images_dir="$OUTPUT_DIR/images"

  mkdir -p "$images_dir/boot"
  cp "$ROOT_DIR/board/raspberrypi4-minimal/config.txt" "$images_dir/boot/config.txt"
  cp "$ROOT_DIR/board/raspberrypi4-minimal/cmdline.txt" "$images_dir/boot/cmdline.txt"
  cp "$ROOT_DIR/configs/rpi4_minimal_defconfig" "$images_dir/rpi4_minimal_defconfig"

  tar -C "$ROOT_DIR/board/raspberrypi4-minimal/rootfs-overlay" -czf "$images_dir/rootfs-overlay.tar.gz" .

  cat > "$images_dir/BUILD_INSTRUCTIONS.txt" <<EOT
Hyper-OS offline bundle generated because Buildroot source was not available locally.

To perform a full image build in a connected environment:
  1) Obtain Buildroot source and place it at:
     $BUILDROOT_DIR
  2) Run:
     make -C $BUILDROOT_DIR O=$OUTPUT_DIR BR2_DEFCONFIG=$ROOT_DIR/configs/rpi4_minimal_defconfig defconfig
     make -C $BUILDROOT_DIR O=$OUTPUT_DIR

This bundle includes boot config files, overlay, and defconfig to keep the build reproducible.
EOT

  echo "[hyper-os] Buildroot not found. Generated offline bundle at: $images_dir"
}

if [[ -f "$BUILDROOT_DIR/Makefile" ]]; then
  make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR" BR2_DEFCONFIG="$ROOT_DIR/configs/rpi4_minimal_defconfig" defconfig
  make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR"
  echo "Build artifacts are available under: $OUTPUT_DIR/images"
elif [[ "$OFFLINE_FALLBACK" == "1" ]]; then
  run_offline_bundle
else
  echo "[hyper-os] Buildroot source not found at $BUILDROOT_DIR" >&2
  echo "[hyper-os] Set BUILDROOT_DIR to a local Buildroot checkout or enable OFFLINE_FALLBACK=1" >&2
  exit 1
fi
