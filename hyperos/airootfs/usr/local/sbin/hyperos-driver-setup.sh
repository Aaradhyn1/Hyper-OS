#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="/var/lib/hyperos"
STATE_FILE="$STATE_DIR/driver-setup.done"
LOG_FILE="/var/log/hyperos-driver-setup.log"
FORCE="${1:-}"

log() {
  local msg="[hyperos-driver-setup] $*"
  echo "$msg"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >> "$LOG_FILE"
}

require_root() {
  [[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
}

detect_gpus() {
  local lspci_out drm_out lsmod_out
  lspci_out="$(lspci -nnk | grep -E 'VGA|3D|Display' || true)"
  drm_out="$(find /sys/class/drm -maxdepth 1 -type l -name 'card*' -printf '%f\n' 2>/dev/null || true)"
  lsmod_out="$(lsmod 2>/dev/null || true)"

  HAS_INTEL=0; HAS_AMD=0; HAS_NVIDIA=0
  grep -qiE 'Intel' <<<"$lspci_out" && HAS_INTEL=1
  grep -qiE 'AMD|Radeon' <<<"$lspci_out" && HAS_AMD=1
  grep -qiE 'NVIDIA' <<<"$lspci_out" && HAS_NVIDIA=1

  log "lspci GPU entries: ${lspci_out:-none}"
  log "drm cards: ${drm_out:-none}"
  log "loaded GPU modules snapshot: $(echo "$lsmod_out" | grep -E 'nvidia|nouveau|amdgpu|i915' || true)"
}

install_pkgs() {
  local pkgs=("$@")
  (( ${#pkgs[@]} > 0 )) || return 0
  log "installing packages: ${pkgs[*]}"
  pacman -S --noconfirm --needed "${pkgs[@]}"
}

configure_nvidia() {
  log "configuring proprietary NVIDIA stack"
  cat > /etc/modprobe.d/hyperos-nvidia.conf <<'MOD'
blacklist nouveau
options nouveau modeset=0
MOD

  if command -v mkinitcpio >/dev/null 2>&1; then
    mkinitcpio -P || true
  fi
}

configure_prime_offload() {
  log "configuring PRIME offload helper"
  cat > /etc/profile.d/hyperos-prime.sh <<'PRIME'
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
alias prime-run='__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only'
PRIME
  chmod 0644 /etc/profile.d/hyperos-prime.sh
}

validate_stack() {
  command -v vulkaninfo >/dev/null 2>&1 && vulkaninfo --summary | head -n 20 >> "$LOG_FILE" 2>&1 || true
  command -v glxinfo >/dev/null 2>&1 && glxinfo -B | head -n 20 >> "$LOG_FILE" 2>&1 || true
}

main() {
  require_root
  mkdir -p "$STATE_DIR"

  if [[ -f "$STATE_FILE" && "$FORCE" != "--force" ]]; then
    log "already configured; exiting"
    exit 0
  fi

  detect_gpus

  # Base graphics userspace (safe on all vendors)
  install_pkgs mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools

  # Gaming compatibility runtime
  install_pkgs wine winetricks dxvk vkd3d steam lutris gamemode mangohud lib32-gamemode lib32-mangohud

  if [[ $HAS_NVIDIA -eq 1 ]]; then
    install_pkgs nvidia nvidia-utils nvidia-settings lib32-nvidia-utils
    configure_nvidia
    if [[ $HAS_INTEL -eq 1 || $HAS_AMD -eq 1 ]]; then
      configure_prime_offload
    fi
  elif [[ $HAS_AMD -eq 1 ]]; then
    install_pkgs vulkan-radeon lib32-vulkan-radeon
    rm -f /etc/modprobe.d/hyperos-nvidia.conf
  elif [[ $HAS_INTEL -eq 1 ]]; then
    install_pkgs vulkan-intel lib32-vulkan-intel
    rm -f /etc/modprobe.d/hyperos-nvidia.conf
  else
    log "no known GPU vendor detected; keeping generic mesa/vulkan userspace"
  fi

  validate_stack

  date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE_FILE"
  log "driver setup complete"
}

main "$@"
