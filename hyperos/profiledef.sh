#!/usr/bin/env bash

iso_name="hyperos"
iso_label="HYPEROS_$(date -u +%Y%m)"
iso_publisher="Hyper OS <https://github.com/hyper-os>"
iso_application="Hyper OS Live/Installer"
iso_version="$(date -u +%Y.%m.%d)"
install_dir="hyperos"
buildmodes=('iso')
bootmodes=('uefi-x64.systemd-boot' 'uefi-x64.grub')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19')

file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/usr/local/bin/hyper-firstboot"]="0:0:755"
)
