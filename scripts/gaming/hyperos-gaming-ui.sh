#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE_DIR="/etc/hyperos/game-profiles"
ENV_FILE="/etc/environment.d/90-hyperos-gaming.conf"

need_cmd() { command -v "$1" >/dev/null 2>&1; }
need_cmd zenity || { echo "zenity is required" >&2; exit 1; }

show_stats() {
  local cpu ram
  cpu="$(grep 'cpu ' /proc/stat | awk '{print $2+$4}')"
  ram="$(free -h | awk '/Mem:/ {print $3" / "$2}')"
  zenity --info --title="HyperOS Gaming" --text="CPU ticks: $cpu\nRAM usage: $ram"
}

toggle_service() {
  if systemctl is-active --quiet hyperos-gamed.service; then
    pkexec systemctl stop hyperos-gamed.service
  else
    pkexec systemctl start hyperos-gamed.service
  fi
}

select_profile() {
  local profile
  profile="$(find "$PROFILE_DIR" -maxdepth 1 -name '*.profile' -printf '%f\n' | sort | zenity --list --title="Select Profile" --column="Profile")"
  [[ -n "$profile" ]] || return 0
  pkexec ln -sfn "$PROFILE_DIR/$profile" "$PROFILE_DIR/default.profile"
}

toggle_mangohud() {
  local enabled
  enabled="$(grep -E '^MANGOHUD=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo 0)"
  if [[ "$enabled" == "1" ]]; then
    pkexec sed -i 's/^MANGOHUD=.*/MANGOHUD=0/' "$ENV_FILE"
  else
    if grep -q '^MANGOHUD=' "$ENV_FILE" 2>/dev/null; then
      pkexec sed -i 's/^MANGOHUD=.*/MANGOHUD=1/' "$ENV_FILE"
    else
      echo 'MANGOHUD=1' | pkexec tee -a "$ENV_FILE" >/dev/null
    fi
  fi
}

ACTION="$(zenity --list --title='HyperOS Gaming Control' --column='Action' \
  'Toggle hyperos-gamed' \
  'View performance' \
  'Select default profile' \
  'Toggle MangoHud' \
  'Launch Steam' \
  'Launch Lutris')"

case "$ACTION" in
  'Toggle hyperos-gamed') toggle_service ;;
  'View performance') show_stats ;;
  'Select default profile') select_profile ;;
  'Toggle MangoHud') toggle_mangohud ;;
  'Launch Steam') steam & ;;
  'Launch Lutris') lutris & ;;
esac
