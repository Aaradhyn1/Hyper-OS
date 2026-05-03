#!/usr/bin/env bash
set -Eeuo pipefail

# Load system X resources
[ -f /etc/X11/xinit/xinitrc.d/50-systemd-user.sh ] && \
  . /etc/X11/xinit/xinitrc.d/50-systemd-user.sh

# Merge Xresources if present
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

# Set sane defaults
export DESKTOP_SESSION=openbox
export XDG_CURRENT_DESKTOP=Openbox

# Start session
exec openbox-session
