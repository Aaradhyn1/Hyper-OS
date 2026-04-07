#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/out/fedora-kde-x86_64}"
KICKSTART="${KICKSTART:-$ROOT_DIR/fedora/kickstarts/hyper-os-kde-x86_64.ks}"
RELEASEVER="${RELEASEVER:-42}"
OFFLINE_FALLBACK="${OFFLINE_FALLBACK:-1}"
IMAGE_NAME="${IMAGE_NAME:-Hyper-OS-Fedora-KDE-x86_64}"

run_offline_bundle() {
  mkdir -p "$OUTPUT_DIR"
  cp "$KICKSTART" "$OUTPUT_DIR/hyper-os-kde-x86_64.ks"

  cat > "$OUTPUT_DIR/BUILD_INSTRUCTIONS.txt" <<EOT
Hyper-OS Fedora KDE x86_64 offline bundle generated.

A full image build requires a Fedora x86_64 host (or privileged container) with:
  dnf install -y lorax-lmc-novirt livemedia-creator spin-kickstarts

Build command:
  sudo livemedia-creator --no-virt --ks $KICKSTART --resultdir $OUTPUT_DIR \\
    --project "$IMAGE_NAME" --make-iso --releasever $RELEASEVER

Notes:
- This repository is now targeted at Fedora KDE Plasma for x86_64 systems.
- The offline bundle preserves kickstart + exact command for reproducibility.
EOT

  echo "[hyper-os] livemedia-creator not available. Generated offline bundle at: $OUTPUT_DIR"
}

if command -v livemedia-creator >/dev/null 2>&1; then
  livemedia-creator --no-virt \
    --ks "$KICKSTART" \
    --resultdir "$OUTPUT_DIR" \
    --project "$IMAGE_NAME" \
    --make-iso \
    --releasever "$RELEASEVER"

  echo "Fedora KDE Plasma image artifacts are available in: $OUTPUT_DIR"
elif [[ "$OFFLINE_FALLBACK" == "1" ]]; then
  run_offline_bundle
else
  echo "[hyper-os] livemedia-creator is required for full Fedora image builds" >&2
  exit 1
fi
