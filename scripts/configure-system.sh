#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Environment & Logging
# =========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-common.sh"

: "${HOSTNAME:?HOSTNAME must be set}"
: "${USERNAME:=hyper}"

# =========================
# Package Sets
# =========================
KDE_PKGS="plasma-desktop sddm konsole dolphin"
LIGHT_PKGS="openbox lightdm pcmanfm xterm"
PERF_PKGS="zram-tools irqbalance pipewire wireplumber pipewire-audio-client-libraries"
INSTALLER_PKGS="calamares calamares-settings-debian parted grub-pc grub-efi-amd64 os-prober"

log INFO "Initializing Advanced Configuration for $HOSTNAME"

main() {
  setup_build_env
  mount_chroot_fs

  log INFO "Installing Calamares assets"
  install -d \
    "$ROOTFS_DIR/etc/calamares/modules" \
    "$ROOTFS_DIR/etc/calamares/branding/hyperos" \
    "$ROOTFS_DIR/usr/local/bin" \
    "$ROOTFS_DIR/usr/share/applications" \
    "$ROOTFS_DIR/etc/xdg/autostart"

  install -m 0644 "$ROOT_DIR/configs/calamares/settings.conf" \
    "$ROOTFS_DIR/etc/calamares/settings.conf"
  install -m 0644 "$ROOT_DIR/configs/calamares/modules.conf" \
    "$ROOTFS_DIR/etc/calamares/modules.conf"
  install -m 0644 "$ROOT_DIR/configs/calamares/branding/branding.desc" \
    "$ROOTFS_DIR/etc/calamares/branding/hyperos/branding.desc"
  install -m 0644 "$ROOT_DIR/configs/calamares/branding/show.qml" \
    "$ROOTFS_DIR/etc/calamares/branding/hyperos/show.qml"

  install -m 0644 "$ROOT_DIR/configs/calamares/modules/unpackfs.conf" \
    "$ROOTFS_DIR/etc/calamares/modules/unpackfs.conf"
  install -m 0644 "$ROOT_DIR/configs/calamares/modules/bootloader.conf" \
    "$ROOTFS_DIR/etc/calamares/modules/bootloader.conf"
  install -m 0644 "$ROOT_DIR/configs/calamares/modules/shellprocess.conf" \
    "$ROOTFS_DIR/etc/calamares/modules/shellprocess.conf"

  install -m 0755 "$ROOT_DIR/configs/installer/hyperos-installer" \
    "$ROOTFS_DIR/usr/local/bin/hyperos-installer"
  install -m 0644 "$ROOT_DIR/configs/installer/install-hyper-os.desktop" \
    "$ROOTFS_DIR/usr/share/applications/install-hyper-os.desktop"
  install -m 0644 "$ROOT_DIR/configs/installer/hyperos-calamares-autostart.desktop" \
    "$ROOTFS_DIR/etc/xdg/autostart/hyperos-calamares-autostart.desktop"

  log INFO "Entering chroot provisioning"

  LIGHT_PKGS="$LIGHT_PKGS" \
  PERF_PKGS="$PERF_PKGS" \
  INSTALLER_PKGS="$INSTALLER_PKGS" \
  USERNAME="$USERNAME" \
  HOSTNAME="$HOSTNAME" \
  USER_PASSWORD_HASH="${USER_PASSWORD_HASH:-}" \
  ROOT_PASSWORD_HASH="${ROOT_PASSWORD_HASH:-}" \
  chroot "$ROOTFS_DIR" /usr/bin/env bash -eux <<'CHROOT'

export DEBIAN_FRONTEND=noninteractive

# =========================
# Packages
# =========================
apt-get update
apt-get install -y --no-install-recommends \
  $LIGHT_PKGS $PERF_PKGS $INSTALLER_PKGS \
  apparmor apparmor-utils ufw \
  htop neofetch mesa-utils

command -v calamares >/dev/null || { echo "Calamares install failed"; exit 1; }

# =========================
# Host Identity
# =========================
echo "$HOSTNAME" > /etc/hostname

# =========================
# ZRAM
# =========================
cat > /etc/default/zramswap <<EOF
ALGO=zstd
PERCENT=25
PRIORITY=100
EOF
systemctl enable zramswap.service

# =========================
# PipeWire Low Latency
# =========================
mkdir -p /etc/pipewire/pipewire.conf.d
cat > /etc/pipewire/pipewire.conf.d/10-low-latency.conf <<EOF
context.properties = {
    default.clock.rate          = 48000
    default.clock.quantum       = 512
    default.clock.min-quantum   = 32
    default.clock.max-quantum   = 2048
}
EOF

# =========================
# Security
# =========================
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw --force enable

systemctl enable apparmor.service

# =========================
# User Setup
# =========================
if ! id -u "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  if [[ -n "$USER_PASSWORD_HASH" ]]; then
    usermod -p "$USER_PASSWORD_HASH" "$USERNAME"
  else
    passwd -l "$USERNAME"
  fi
  usermod -aG sudo,audio,video,render "$USERNAME"
fi

if [[ -n "$ROOT_PASSWORD_HASH" ]]; then
  usermod -p "$ROOT_PASSWORD_HASH" root
else
  passwd -l root
fi

# =========================
# LightDM Autologin
# =========================
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<EOF
[Seat:*]
autologin-user=$USERNAME
autologin-session=openbox
EOF

systemctl enable lightdm.service

# =========================
# Openbox Defaults
# =========================
mkdir -p /etc/skel/.config/openbox
cat > /etc/skel/.config/openbox/rc.xml <<EOF
<openbox_config>
  <desktops><number>2</number></desktops>
  <keyboard><chainQuitKey>C-g</chainQuitKey></keyboard>
</openbox_config>
EOF

# =========================
# Persistence Validator
# =========================
install -d /usr/local/sbin

cat > /usr/local/sbin/check-live-persistence <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
logger -t hyper-persistence "Checking persistence..."

mapfile -t devs < <(blkid -t LABEL=HYPER_PERSIST -o device || true)
[[ "${#devs[@]}" -gt 0 ]] || exit 0

for dev in "${devs[@]}"; do
  mnt="$(mktemp -d)"
  mount -o ro "$dev" "$mnt" 2>/dev/null || continue

  if [[ ! -f "$mnt/persistence.conf" ]]; then
    logger -t hyper-persistence "Invalid persistence on $dev"
  fi

  umount "$mnt"
  rmdir "$mnt"
done
EOF

chmod +x /usr/local/sbin/check-live-persistence

cat > /etc/systemd/system/check-live-persistence.service <<EOF
[Unit]
Description=Validate persistence
After=local-fs.target systemd-udev-settle.service
ConditionKernelCommandLine=boot=live

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/check-live-persistence

[Install]
WantedBy=multi-user.target
EOF

systemctl enable check-live-persistence.service

# =========================
# Cleanup
# =========================
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /usr/share/doc/* /usr/share/man/*

CHROOT

  log SUCCESS "Configuration complete."
}

main "$@"
