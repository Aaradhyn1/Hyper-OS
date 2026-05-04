#!/usr/bin/env bash

# Ensure DBus session (critical for modern apps)
if command -v dbus-launch >/dev/null 2>&1 && [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  eval "$(dbus-launch --sh-syntax --exit-with-session)"
fi

# Load Xresources if present
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

# Set session identity (helps apps behave correctly)
export DESKTOP_SESSION=openbox
export XDG_CURRENT_DESKTOP=Openbox

# Start Openbox
exec openbox-session
