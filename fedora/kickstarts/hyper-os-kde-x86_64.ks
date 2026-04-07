# Hyper-OS: Advanced Fedora KDE Plasma (x86_64)
lang en_US.UTF-8
keyboard us
timezone UTC --utc
rootpw --lock
user --name=hyper --groups=wheel --password=hyper --plaintext
firewall --enabled --service=ssh
selinux --enforcing
services --enabled=sshd,NetworkManager,sddm,fwupd,tlp,irqbalance --disabled=kdump,packagekit
bootloader --timeout=1 --append="quiet splash iommu=pt intel_iommu=on nvme_load=YES"
reboot

# Advanced Storage: Btrfs with Zstd Compression for NVMe longevity
zerombr
clearpart --all --initlabel
part /boot/efi --fstype="efi" --size=600
part /boot --fstype="ext4" --size=1024
part btrfs.01 --grow --size=1
part / --fstype="btrfs" --fsoptions="compress=zstd:3,discard=async,noatime" --ondisk=sda

# Repositories (Fedora + RPM Fusion for Multimedia/Hardware)
repo --name=fedora --mirrorlist=https://fedoraproject.org
repo --name=updates --mirrorlist=https://fedoraproject.org
repo --name=rpmfusion-free --mirrorlist=https://rpmfusion.org

%packages
@^kde-desktop-environment
@multimedia
@hardware-support
# Networking & Core
NetworkManager-wifi
openssh-server
# Performance & Power
tlp
tlp-rdw
thermald
powertop
irqbalance
zram-generator
# Wayland / KDE specific
plasma-workspace-wayland
konsole
dolphin
# Removal of Bloat
-dracut-config-rescue
-plymouth-scripts
-fedora-release-notes
-gnome-software
%end

%post --log=/root/hyper-os-post.log
# 1. Enable ZRAM for high-performance memory swap
cat > /etc/systemd/zram-generator.conf <<EOT
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOT

# 2. KDE Plasma / Wayland Tweaks
mkdir -p /etc/sddm.conf.d/
cat > /etc/sddm.conf.d/wayland.conf <<EOT
[General]
DisplayServer=wayland
EOT

# 3. Kernel & Power Tuning
systemctl enable tlp.service
systemctl enable irqbalance.service
# Optimize NVMe and SSDs
systemctl enable fstrim.timer

# 4. Hyper-OS Branding & MOTD
cat > /etc/motd <<'EOT'
   __ Hyper-OS Workstation __
   Optimized for x86_64 / Btrfs
   
   Hardware: Run 'powertop --auto-tune' for max battery.
   Graphics: Wayland enabled by default.
EOT

# 5. Cleanup
dnf -y clean all
%end
