#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="/var/log/hyperos"
LOG_FILE="$LOG_DIR/validation.log"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

pass_count=0
fail_count=0
warn_count=0

say() {
  local level="$1"; shift
  printf '%s %s\n' "$level" "$*" | tee -a "$LOG_FILE"
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

pass() { pass_count=$((pass_count + 1)); say "✔" "$*"; }
fail() { fail_count=$((fail_count + 1)); say "❌" "$*"; }
warn() { warn_count=$((warn_count + 1)); say "⚠" "$*"; }

check_core() {
  [[ -r /proc/version ]] && pass "Kernel loaded ($(uname -r))" || fail "Kernel information unavailable"
  [[ "$(ps -p 1 -o comm= 2>/dev/null || true)" == "systemd" ]] && pass "systemd is running as init" || fail "systemd not detected as PID 1"
  findmnt / >/dev/null 2>&1 && pass "Root filesystem mounted" || fail "Root filesystem mount check failed"
}

check_drivers() {
  if lspci | grep -Eqi 'VGA|3D|Display'; then
    local gpu
    gpu="$(lspci | grep -Ei 'VGA|3D|Display' | head -n1 | sed 's/^[^:]*: //')"
    pass "GPU detected ($gpu)"
  else
    fail "No GPU detected"
  fi

  if check_cmd vulkaninfo; then
    vulkaninfo --summary >/dev/null 2>&1 && pass "Vulkan working" || fail "Vulkan not working — reinstall GPU Vulkan drivers"
  else
    warn "vulkaninfo not installed"
  fi

  if check_cmd glxinfo; then
    glxinfo -B >/dev/null 2>&1 && pass "OpenGL working" || fail "OpenGL not working — check mesa/nvidia GL stack"
  else
    warn "glxinfo not installed (mesa-utils missing)"
  fi
}

check_gaming_stack() {
  check_cmd wine && pass "Wine installed ($(wine --version 2>/dev/null || echo unknown))" || fail "Wine missing"
  check_cmd steam && pass "Steam installed" || fail "Steam missing"
  if [[ -d /usr/share/steam/compatibilitytools.d || -d "$HOME/.steam/root/compatibilitytools.d" ]]; then
    pass "Proton tools directory available"
  else
    warn "Proton custom tools directory not found (Steam may still download default Proton)"
  fi
}

check_perf_tools() {
  check_cmd gamemoded && pass "GameMode available" || warn "GameMode daemon not found"
  check_cmd mangohud && pass "MangoHud available" || warn "MangoHud not found"
}

check_network() {
  systemctl is-active --quiet NetworkManager && pass "NetworkManager running" || fail "NetworkManager not active"
  ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && pass "Internet connectivity working" || warn "No internet connectivity (offline is allowed)"
}

main() {
  say "ℹ" "Hyper OS validation started: $(date -Is)"
  check_core
  check_drivers
  check_gaming_stack
  check_perf_tools
  check_network

  say "ℹ" "Summary: PASS=$pass_count WARN=$warn_count FAIL=$fail_count"

  if (( fail_count > 0 )); then
    say "ℹ" "Result: Action required. See $LOG_FILE"
    exit 1
  fi

  say "ℹ" "Result: System looks healthy"
}

main "$@"
