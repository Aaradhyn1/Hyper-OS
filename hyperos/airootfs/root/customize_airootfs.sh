#!/usr/bin/env bash
set -Eeuo pipefail

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

useradd -m -G wheel,audio,video -s /bin/bash hyper
passwd -l hyper
passwd -l root

chmod 0440 /etc/sudoers.d/wheel

enable_unit() {
  local unit="$1"
  local wants_dir="/etc/systemd/system/multi-user.target.wants"
  local unit_path="/usr/lib/systemd/system/$unit"
  mkdir -p "$wants_dir"
  [[ -f "$unit_path" ]] || { echo "Missing unit file: $unit" >&2; exit 1; }
  ln -snf "$unit_path" "$wants_dir/$unit"
}

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

enable_unit NetworkManager.service
enable_unit lightdm.service
ln -snf /etc/systemd/system/hyper-firstboot.service /etc/systemd/system/multi-user.target.wants/hyper-firstboot.service
ln -snf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
