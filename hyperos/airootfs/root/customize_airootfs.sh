#!/usr/bin/env bash
set -Eeuo pipefail

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

useradd -m -G wheel,audio,video -s /bin/bash hyper
printf 'hyper:hyper\n' | chpasswd

chmod 0440 /etc/sudoers.d/wheel

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

systemctl enable NetworkManager.service
systemctl enable lightdm.service
systemctl enable hyper-firstboot.service
systemctl set-default graphical.target
