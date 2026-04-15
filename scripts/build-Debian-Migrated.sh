#!/usr/bin/env bash
set -Eeuo pipefail

# --- Migrated Configuration ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/debian-live}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/out}"
IMAGE_NAME="${IMAGE_NAME:-Hyper-OS-Debian-KDE}"
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"

log() { printf "\e[34m[hyper-migrate] [%s] %s\e[0m\n" "$(date '+%H:%M:%S')" "$1"; }

require_root() {
    [[ "$EUID" -eq 0 ]] || { log "ERROR: Root required (sudo ./build.sh)"; exit 1; }
}

# --- Core Build Logic ---
setup_lb_config() {
    log "Configuring Live-Build for $DEBIAN_SUITE..."
    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"
    
    # Initialize basic live-build structure
    lb config \
        --distribution "$DEBIAN_SUITE" \
        --debian-installer none \
        --archive-areas "main contrib non-free non-free-firmware" \
        --apt-recommends false \
        --linux-flavours amd64 \
        --image-name "$IMAGE_NAME"

    # 1. Package Migration (Equivalent to %packages)
    log "Injecting migrated package lists..."
    mkdir -p config/package-lists
    cat > config/package-lists/hyper-os.list.chroot <<EOF
kde-standard plasma-desktop sddm
network-manager firefox-esr sudo curl
fwupd bolt thermald tlp tlp-rdw powertop
EOF

    # 2. Optimization Migration (Equivalent to %post)
    log "Injecting performance hooks..."
    mkdir -p config/hooks/live
cat > config/hooks/live/99-hyper-optimize.chroot <<'EOF'
#!/bin/sh
set -eu
# Applied from previously discussed optimizations
mkdir -p /etc/systemd/system/multi-user.target.wants /etc/systemd/system/timers.target.wants
ln -snf /lib/systemd/system/thermald.service /etc/systemd/system/multi-user.target.wants/thermald.service
ln -snf /lib/systemd/system/tlp.service /etc/systemd/system/multi-user.target.wants/tlp.service
ln -snf /lib/systemd/system/fstrim.timer /etc/systemd/system/timers.target.wants/fstrim.timer
for unit in apt-daily.service apt-daily.timer packagekit.service; do
  ln -snf /dev/null "/etc/systemd/system/$unit"
done
passwd -l root
EOF
    chmod +x config/hooks/live/99-hyper-optimize.chroot
}

main() {
    require_root
    
    if ! command -v lb >/dev/null; then
        log "Installing live-build dependencies..."
        apt-get update && apt-get install -y live-build debootstrap
    fi

    setup_lb_config
    
    log "Starting ISO construction..."
    lb build
    
    mkdir -p "$OUTPUT_DIR"
    mv *.iso "$OUTPUT_DIR/${IMAGE_NAME}.iso"
    log "Build Complete: $OUTPUT_DIR/${IMAGE_NAME}.iso"
}

main "$@"
