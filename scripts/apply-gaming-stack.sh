#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG_DIR="$ROOT_DIR/configs/gaming"
GPU_VENDOR="${GPU_VENDOR:-auto}" # auto|intel|amd|nvidia
INSTALL_PKGS="${INSTALL_PKGS:-0}"

log() { printf '[gaming-apply] %s\n' "$*"; }

require_root() {
  [[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
}

install_cfg() {
  install -D -m 0644 "$1" "$2"
}

vendor_packages() {
  case "$GPU_VENDOR" in
    intel) echo "vulkan-intel" ;;
    amd) echo "vulkan-radeon" ;;
    nvidia) echo "nvidia nvidia-utils lib32-nvidia-utils" ;;
    auto)
      if lspci | grep -qi 'NVIDIA'; then
        echo "nvidia nvidia-utils lib32-nvidia-utils"
      elif lspci | grep -Eqi 'AMD|Radeon'; then
        echo "vulkan-radeon"
      else
        echo "vulkan-intel"
      fi
      ;;
    *) echo "" ;;
  esac
}

main() {
  require_root

  install_cfg "$CFG_DIR/environment.conf" /etc/environment.d/90-hyperos-gaming.conf
  install_cfg "$CFG_DIR/limits.conf" /etc/security/limits.d/90-hyperos-gaming.conf
  install_cfg "$CFG_DIR/gamemode.ini" /etc/gamemode.ini

  local vendor_pkgs
  vendor_pkgs="$(vendor_packages)"

  if [[ "$INSTALL_PKGS" == "1" ]]; then
    pacman -S --noconfirm --needed \
      steam lutris wine winetricks dxvk vkd3d \
      gamemode mangohud vulkan-tools \
      lib32-vulkan-icd-loader lib32-mesa lib32-gamemode lib32-mangohud \
      $vendor_pkgs
  else
    log "Package install skipped (set INSTALL_PKGS=1 to install)."
    log "Suggested command: pacman -S --needed steam lutris wine winetricks dxvk vkd3d gamemode mangohud vulkan-tools lib32-vulkan-icd-loader lib32-mesa lib32-gamemode lib32-mangohud $vendor_pkgs"
  fi

  log "gaming config applied"
}

main "$@"
