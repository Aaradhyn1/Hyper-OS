#!/usr/bin/env bash
set -Eeuo pipefail

# --- Environment & Logging ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/build-common.sh"

# Constants
KDE_PKGS="plasma-desktop sddm konsole dolphin" # If migrating to KDE
LIGHT_PKGS="openbox lightdm pcmanfm xterm"     # Current lean setup
PERF_PKGS="zram-tools irqbalance pipewire-audio-client-libraries"

log INFO "Initializing Advanced Configuration for $HOSTNAME"

main() {
  setup_build_env
  mount_chroot_fs

  chroot "$ROOTFS_DIR" /usr/bin/env bash -eux <<CHROOT
    export DEBIAN_FRONTEND=noninteractive
    
    # 1. Advanced Package Selection & Performance
    apt-get update
    apt-get install -y --no-install-recommends \
      $LIGHT_PKGS $PERF_PKGS \
      apparmor apparmor-utils ufw \
      htop neofetch mesa-utils
    
    # 2. Advanced: ZRAM for Live Persistence
    # Prevents "Live System Freeze" when RAM is full
    cat > /etc/default/zramswap <<EOF
ALGO=zstd
PERCENT=25
PRIORITY=100
EOF
    systemctl enable zramswap

    # 3. PipeWire Low-Latency Tuning
    # Sets quantum limits for professional audio responsiveness
    mkdir -p /etc/pipewire/pipewire.conf.d
    cat > /etc/pipewire/pipewire.conf.d/10-low-latency.conf <<EOF
context.properties = {
    default.clock.rate          = 48000
    default.clock.quantum       = 512
    default.clock.min-quantum   = 32
    default.clock.max-quantum   = 2048
}
EOF

    # 4. Security Hardening
    # Enable UFW firewall and basic AppArmor profiles
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    systemctl enable apparmor

    # 5. Robust User & Autologin Logic
    if ! id -u "$USERNAME" >/dev/null 2>&1; then
      useradd -m -s /bin/bash "$USERNAME"
      echo "$USERNAME:$USER_PASSWORD" | chpasswd
      usermod -aG sudo,audio,video,render "$USERNAME"
    fi

    # 6. Advanced X11/Openbox Polish
    mkdir -p /etc/skel/.config/openbox
    cat > /etc/skel/.config/openbox/rc.xml <<EOF
<openbox_config>
  <desktops><number>2</number></desktops>
  <keyboard><chainQuitKey>C-g</chainQuitKey></keyboard>
</openbox_config>
EOF

    # 7. Final Cleanup (Reduce SquashFS Size)
    install -d /usr/local/sbin
    cat > /usr/local/sbin/check-live-persistence <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

warn() {
  logger -t hyper-persistence-warning -- "$1"
  printf 'WARNING: %s\n' "$1" >&2
}

mapfile -t persistence_devices < <(blkid -t LABEL=HYPER_PERSIST -o device || true)
[[ "${#persistence_devices[@]}" -gt 0 ]] || exit 0

for dev in "${persistence_devices[@]}"; do
  mount_dir="$(mktemp -d)"
  if ! mount -o ro "$dev" "$mount_dir" 2>/dev/null; then
    warn "Persistence device $dev exists but could not be mounted read-only. Falling back to non-persistent live mode."
    rmdir "$mount_dir"
    continue
  fi

  if [[ ! -f "$mount_dir/persistence.conf" ]]; then
    warn "Persistence device $dev is missing /persistence.conf. Required content: '/ union'."
    umount "$mount_dir"
    rmdir "$mount_dir"
    continue
  fi

  if ! grep -Eq '^[[:space:]]*/[[:space:]]+union([[:space:]]|$)' "$mount_dir/persistence.conf"; then
    warn "Persistence device $dev has invalid /persistence.conf. Required content: '/ union'."
  fi

  umount "$mount_dir"
  rmdir "$mount_dir"
done
EOF
    chmod 0755 /usr/local/sbin/check-live-persistence

    cat > /etc/systemd/system/check-live-persistence.service <<'EOF'
[Unit]
Description=Validate Hyper OS live persistence partition configuration
DefaultDependencies=no
After=local-fs.target
ConditionKernelCommandLine=boot=live

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/check-live-persistence
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable check-live-persistence.service

    # 8. Final Cleanup (Reduce SquashFS Size)
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    rm -rf /usr/share/doc/* /usr/share/man/*
CHROOT

  log SUCCESS "Configuration applied successfully."
}

main "$@"
