#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE_DIR="${PROFILE_DIR:-/etc/hyperos/game-profiles}"
DEFAULT_PROFILE="${DEFAULT_PROFILE:-$PROFILE_DIR/default.profile}"
STATE_DIR="/run/hyperos-gamed"
LOG_FILE="/var/log/hyperos-gamed.log"
POLL_SECS="${POLL_SECS:-3}"

mkdir -p "$STATE_DIR"

log() {
  local msg="[hyperos-gamed] $*"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" | tee -a "$LOG_FILE"
}

read_profile() {
  local profile_file=$1
  [[ -f "$profile_file" ]] || { log "missing profile: $profile_file"; return 1; }
  # shellcheck disable=SC1090
  source "$profile_file"
}

set_governor() {
  local gov=$1
  if [[ -w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      [[ -w "$f" ]] && echo "$gov" > "$f" || true
    done
  elif command -v cpupower >/dev/null 2>&1; then
    cpupower frequency-set -g "$gov" >/dev/null 2>&1 || true
  fi
}

apply_profile() {
  local profile_file=$1 pid=$2
  read_profile "$profile_file" || return 1

  [[ -f "$STATE_DIR/original_governor" ]] || cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor > "$STATE_DIR/original_governor" 2>/dev/null || true

  set_governor "$CPU_GOVERNOR"

  if [[ "$USE_GAMEMODE" == "1" ]] && command -v gamemoderun >/dev/null 2>&1; then
    systemctl start gamemoded.service >/dev/null 2>&1 || true
  fi

  renice "$NICE_LEVEL" -p "$pid" >/dev/null 2>&1 || true

  if [[ "$GPU_OFFLOAD" == "nvidia" ]]; then
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
  fi

  log "applied profile=${PROFILE_NAME:-unknown} pid=$pid"
  echo "$profile_file" > "$STATE_DIR/pid-$pid.profile"
}

restore_defaults() {
  local pid=$1
  [[ -f "$STATE_DIR/pid-$pid.profile" ]] || return 0
  rm -f "$STATE_DIR/pid-$pid.profile"

  if ! ls "$STATE_DIR"/pid-*.profile >/dev/null 2>&1; then
    if [[ -f "$STATE_DIR/original_governor" ]]; then
      set_governor "$(cat "$STATE_DIR/original_governor")"
    fi
    systemctl stop gamemoded.service >/dev/null 2>&1 || true
    log "restored defaults (no active tracked games)"
  fi
}

match_and_apply() {
  local profile_file=$1
  read_profile "$profile_file" || return 0
  local pids
  pids="$(pgrep -f "$PROCESS_MATCH" || true)"
  for pid in $pids; do
    [[ -f "$STATE_DIR/pid-$pid.profile" ]] && continue
    apply_profile "$profile_file" "$pid"
  done
}

garbage_collect() {
  local f pid
  for f in "$STATE_DIR"/pid-*.profile; do
    [[ -e "$f" ]] || continue
    pid="${f##*/pid-}"
    pid="${pid%.profile}"
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      restore_defaults "$pid"
    fi
  done
}

main() {
  log "starting daemon"
  while true; do
    for profile in "$PROFILE_DIR"/*.profile; do
      [[ -e "$profile" ]] || continue
      match_and_apply "$profile"
    done

    if [[ -f "$DEFAULT_PROFILE" ]]; then
      match_and_apply "$DEFAULT_PROFILE"
    fi

    garbage_collect
    sleep "$POLL_SECS"
  done
}

main "$@"
