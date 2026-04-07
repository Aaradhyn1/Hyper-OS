# Fedora KDE Plasma image definition for Hyper-OS (x86_64)
lang en_US.UTF-8
keyboard us
timezone UTC --utc
rootpw --lock
user --name=hyper --groups=wheel --password=hyper --plaintext
firewall --enabled --service=ssh
selinux --enforcing
services --enabled=sshd,NetworkManager,sddm,fwupd --disabled=kdump
bootloader --timeout=1 --append="quiet splash"
reboot

zerombr
clearpart --all --initlabel
autopart --type=lvm

repo --name=fedora --baseurl=https://download.fedoraproject.org/pub/fedora/linux/releases/$releasever/Everything/x86_64/os/
repo --name=updates --baseurl=https://download.fedoraproject.org/pub/fedora/linux/updates/$releasever/Everything/x86_64/

%packages
@^kde-desktop-environment
NetworkManager
NetworkManager-wifi
plasma-workspace
sddm
konsole
dolphin
firefox
openssh-server
fwupd
bolt
thermald
tlp
tlp-rdw
powertop
-dracut-config-rescue
-plymouth
%end

%post --log=/root/hyper-os-post.log
# Keep boot fast and image lean for desktop/laptop usage
systemctl set-default graphical.target
systemctl disable packagekit.service packagekit-offline-update.service || true
systemctl enable fstrim.timer fwupd.service thermald.service tlp.service || true

cat >/etc/motd.d/hyper-os-hardware.txt <<'EOT'
Hyper-OS hardware note:
- For NVIDIA dGPU systems (e.g., some ThinkPad P15 Gen 2 configs), install RPM Fusion and the NVIDIA driver after first boot.
- Secure Boot users must enroll MOK/sign modules for third-party kernel modules.
EOT

dnf -y clean all || true
%end
