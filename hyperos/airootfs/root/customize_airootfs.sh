#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo "[HYPER-SETUP] $*"; }

# =========================
# Time & Locale
# =========================
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc || true

echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# =========================
# User Setup
# =========================
if ! id -u hyper >/dev/null 2>&1; then
  useradd -m -G wheel,audio,video -s /bin/bash hyper
fi

passwd -l hyper
passwd -l root

# Secure sudo access
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# =========================
# Systemd Helper
# =========================
enable_unit() {
  local unit="$1"

  local unit_path=""
  for path in /usr/lib/systemd/system /lib/systemd/system; do
    [[ -f "$path/$unit" ]] && unit_path="$path/$unit"
  done

  [[ -n "$unit_path" ]] || {
    echo "Missing unit file: $unit" >&2
    exit 1
  }

  ln -snf "$unit_path" "/etc/systemd/system/multi-user.target.wants/$unit"
}

# =========================
# First Boot Service
# =========================
cat > /etc/systemd/system/hyper-firstboot.service <<'UNIT'
[Unit]
Description=Hyper OS first boot user setup
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hyper-firstboot
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
UNIT

# =========================
# Enable Services
# =========================
enable_unit NetworkManager.service
enable_unit lightdm.service
enable_unit hyper-firstboot.service

# Default target (safe)
if command -v systemctl >/dev/null 2>&1; then
  systemctl set-default graphical.target || true
else
  ln -snf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
fi

log "System provisioning complete."
