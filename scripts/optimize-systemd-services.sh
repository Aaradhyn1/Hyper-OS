#!/usr/bin/env bash
# Hyper OS Systemd Performance Profiler & Optimizer
set -Eeuo pipefail

DRY_RUN="${DRY_RUN:-0}"
LOG_TAG="[Systemd-Pro]"

# Define "Protected" units that the script will never touch
PROTECTED_UNITS=(
    "systemd-journald.service" "systemd-udevd.service" "dbus.service" 
    "networking.service" "ssh.service" "systemd-networkd.service"
)

# High-overhead services to target for removal
TARGET_UNITS=(
    "apt-daily.service" "apt-daily.timer" "apt-daily-upgrade.service" 
    "apt-daily-upgrade.timer" "man-db.timer" "e2scrub_all.timer" 
    "motd-news.timer" "bluetooth.service" "ModemManager.service" 
    "avahi-daemon.service" "cups.service" "smartmontools.service"
    "packagekit.service" "udisks2.service" "fwupd.service"
)

log() { printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$LOG_TAG" "$1"; }

run_cmd() {
    [[ "$DRY_RUN" == "1" ]] && log "DRY_RUN: $*" || "$@"
}

# --- 1. Pre-Flight & Benchmarking ---
[[ "$EUID" -ne 0 ]] && { echo "Root required." >&2; exit 1; }

log "Capturing baseline performance..."
PRE_BOOT_TIME=$(systemd-analyze | awk '/Startup finished/ {print $4 " (kernel) + " $7 " (userspace)"}')
log "Baseline Boot: $PRE_BOOT_TIME"

# --- 2. Advanced Conflict Resolution ---
validate_unit() {
    local unit=$1
    # Check if unit is in the protected list
    for prot in "${PROTECTED_UNITS[@]}"; do
        [[ "$unit" == "$prot" ]] && return 1
    done
    # Check if unit actually exists
    systemctl list-unit-files "$unit" >/dev/null 2>&1 || return 1
    return 0
}

# --- 3. Execution Phase ---
log "Optimizing unit tree..."

for unit in "${TARGET_UNITS[@]}"; do
    if validate_unit "$unit"; then
        # Check if it's currently running/enabled
        if systemctl is-enabled "$unit" >/dev/null 2>&1; then
            log "Action: Purging $unit"
            if [[ "$DRY_RUN" == "1" ]]; then
                run_cmd systemctl disable --now "$unit"
                run_cmd systemctl mask "$unit"
            else
                systemctl disable --now "$unit"
                systemctl mask "$unit"
            fi
        fi
    else
        log "Skipping (Protected or Missing): $unit"
    fi
done

# --- 4. Advanced: Systemd Manager Optimizations ---
# Reducing the global timeout for hanging services
log "Tuning Systemd Manager timing..."
TUNING_CONF="/etc/systemd/system.conf.d/10-low-latency.conf"
run_cmd mkdir -p "$(dirname "$TUNING_CONF")"
if [[ "$DRY_RUN" == "0" ]]; then
    cat <<EOF > "$TUNING_CONF"
[Manager]
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=5s
DefaultRestartSec=100ms
DefaultLimitNOFILE=65535
EOF
fi

# --- 5. Post-Optimization Summary ---
log "Reloading daemon and validating state..."
run_cmd systemctl daemon-reload

log "Post-Optimization Stats:"
systemd-analyze blame | head -n 5 | sed 's/^/  [Blame] /'
log "Done. Run 'systemd-analyze critical-chain' after next reboot to verify."
