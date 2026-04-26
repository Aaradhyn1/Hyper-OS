#!/usr/bin/env bash
set -Eeuo pipefail

LIVE_USER="hyper"
LIVE_HOME="/home/${LIVE_USER}"

log() { printf '[airootfs] %s\n' "$*"; }

configure_locale() {
  log "Configuring locale"
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
  locale-gen
  cat > /etc/locale.conf <<LOCALE
LANG=en_US.UTF-8
LC_TIME=C
LOCALE
  ln -sf /usr/share/zoneinfo/UTC /etc/localtime
}

configure_live_user() {
  log "Configuring live user"
  if ! id -u "$LIVE_USER" >/dev/null 2>&1; then
    useradd -m -G wheel,audio,video,storage,network -s /bin/bash "$LIVE_USER"
  fi

  passwd -d "$LIVE_USER" >/dev/null 2>&1 || true
  passwd -l root >/dev/null 2>&1 || true

  install -d -m 0755 -o "$LIVE_USER" -g "$LIVE_USER" "$LIVE_HOME/.config/openbox"
  install -m 0644 /etc/xdg/openbox/autostart "$LIVE_HOME/.config/openbox/autostart"
  chown "$LIVE_USER:$LIVE_USER" "$LIVE_HOME/.config/openbox/autostart"

  cat > /etc/sudoers.d/99_hyper_live <<'SUDOERS'
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
Defaults:%wheel !authenticate
SUDOERS
  chmod 0440 /etc/sudoers.d/99_hyper_live
}

enable_services() {
  log "Enabling services"
  systemctl enable NetworkManager.service
  systemctl enable lightdm.service
  systemctl enable cpupower.service 2>/dev/null || true
  systemctl enable hyperos-driver-setup.service
  systemctl set-default graphical.target
}

main() {
  configure_locale
  configure_live_user
  enable_services
  log "Customization complete"
}

main "$@"
