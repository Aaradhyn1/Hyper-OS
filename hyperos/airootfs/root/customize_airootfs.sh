#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[HYPER-SETUP] ERROR at line $LINENO"; exit 1' ERR

LOG_TAG="[HYPER-SETUP]"
USER_NAME="${USERNAME:-hyper}"

log() { printf '%s %s %s\n' "$(date '+%T')" "$LOG_TAG" "$*"; }
die() { log "FATAL: $*"; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "Run as root."
}

require_cmds() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || die "Missing dependency: $cmd"
  done
}

# =========================
# Time & Locale
# =========================
setup_locale() {
  log "Configuring timezone & locale..."

  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
  hwclock --systohc || true

  sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  locale-gen

  echo 'LANG=en_US.UTF-8' > /etc/locale.conf
}

# =========================
# User Setup
# =========================
setup_user() {
  log "Configuring user: $USER_NAME"

  if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    useradd -m -G wheel,audio,video,render -s /bin/bash "$USER_NAME"
  fi

  passwd -l "$USER_NAME" || true
  passwd -l root || true

  # Harden sudoers safely
  install -m 0440 /dev/stdin /etc/sudoers.d/99-wheel <<EOF
%wheel ALL=(ALL:ALL) ALL
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
}

# =========================
# Systemd Helpers
# =========================
enable_unit() {
  local unit="$1"

  if systemctl list-unit-files | grep -q "^$unit"; then
    log "Enabling $unit"
    systemctl enable "$unit" >/dev/null 2>&1 || true
  else
    log "Missing unit → skip: $unit"
  fi
}

# =========================
# First Boot Service
# =========================
setup_firstboot() {
  log "Configuring first boot service..."

  install -d /usr/local/bin

  # Stub script (safe default)
  if [[ ! -f /usr/local/bin/hyper-firstboot ]]; then
    cat > /usr/local/bin/hyper-firstboot <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
echo "[Hyper Firstboot] Initializing..."
systemctl disable hyper-firstboot.service || true
EOF
    chmod +x /usr/local/bin/hyper-firstboot
  fi

  cat > /etc/systemd/system/hyper-firstboot.service <<'UNIT'
[Unit]
Description=Hyper OS First Boot Initialization
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hyper-firstboot
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reexec || true
  systemctl daemon-reload || true
  enable_unit hyper-firstboot.service
}

# =========================
# Core Services
# =========================
setup_services() {
  log "Enabling core services..."

  enable_unit NetworkManager.service
  enable_unit lightdm.service
}

# =========================
# Default Target
# =========================
set_default_target() {
  log "Setting default target..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl set-default graphical.target || true
  else
    ln -snf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
  fi
}

# =========================
# Main
# =========================
main() {
  require_root
  require_cmds locale-gen useradd systemctl

  setup_locale
  setup_user
  setup_firstboot
  setup_services
  set_default_target

  log "Provisioning complete."
}

main "$@"
