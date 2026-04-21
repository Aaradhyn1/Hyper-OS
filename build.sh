#!/usr/bin/env bash
set -Eeuo pipefail

# --- Advanced Environment & Metadata ---
readonly SCRIPT_NAME="hyper-branding"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
readonly ROOTFS_DIR="$BUILD_DIR/rootfs"

# Calamares Paths
readonly BRAND_ID="hyperos"
readonly CALAMARES_DIR="$ROOTFS_DIR/etc/calamares"
readonly BRAND_DIR="$CALAMARES_DIR/branding/$BRAND_ID"

# Assets (Expects these in your source tree)
readonly SOURCE_ASSETS="$ROOT_DIR/assets/branding"

# --- UI Styling Constants ---
readonly COLOR_BG="#0a0a0a"
readonly COLOR_ACCENT="#00f2ff"

# =========================
# Utilities
# =========================
log() { printf "\e[34m[CORE]\e[0m %s\n" "$*"; }
info() { printf "\e[36m[INFO]\e[0m %s\n" "$*"; }
warn() { printf "\e[33m[WARN]\e[0m %s\n" "$*"; }
die() { printf "\e[31m[FATAL]\e[0m %s\n" "$*" >&2; exit 1; }

# =========================
# Core Logic
# =========================

setup_structure() {
    info "Initializing branding directory: $BRAND_DIR"
    mkdir -p "$BRAND_DIR/lang"
}

inject_qml_logic() {
    info "Generating reactive QML Slideshow..."
    
    # Using a HEREDOC but with variables for easy theming
    cat > "$BRAND_DIR/show.qml" <<EOF
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    anchors.fill: parent
    color: "$COLOR_BG"

    property int currentSlide: 0
    readonly property var content: [
        { title: "Hyper OS", desc: "Experience the ultimate kernel tuning.", img: "logo.png" },
        { title: "Blazing Fast", desc: "Optimized SquashFS with Zstd-19 compression.", img: "speed.png" },
        { title: "Privacy First", desc: "Hardened defaults with zero telemetry.", img: "shield.png" }
    ]

    // Background Gradient Effect
    Rectangle {
        anchors.fill: parent
        opacity: 0.1
        gradient: Gradient {
            GradientStop { position: 0.0; color: "$COLOR_ACCENT" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Timer {
        interval: 8000; running: true; repeat: true
        onTriggered: currentSlide = (currentSlide + 1) % content.length
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: 30

        Image {
            source: content[currentSlide].img
            Layout.preferredWidth: 128
            Layout.preferredHeight: 128
            Layout.alignment: Qt.AlignHCenter
            fillMode: Image.PreserveAspectFit
        }

        Column {
            Layout.fillWidth: true
            spacing: 10
            
            Text {
                text: content[currentSlide].title
                color: "white"
                font.pixelSize: 28
                font.weight: Font.Bold
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                text: content[currentSlide].desc
                color: "#888"
                font.pixelSize: 16
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
EOF
}

inject_branding_desc() {
    info "Configuring branding.desc..."

    cat > "$BRAND_DIR/branding.desc" <<EOF
---
componentName:   $BRAND_ID
welcomeStyleCalamares: true
welcomeExpandingLogo: true
windowSize: 800,520
windowResizability: none
windowPlacement: center

strings:
    productName:         "Hyper OS"
    shortProductName:    "Hyper"
    productUrl:          "https://hyperos.io"
    supportUrl:          "https://github.com/hyperos/support"
    knownIssuesUrl:      "https://github.com/hyperos/issues"
    releaseNotesUrl:     "https://hyperos.io/blog"

images:
    productLogo:         "logo.png"
    productIcon:         "icon.png"
    welcomeBackground:   "welcome.png"

slideshow:               "show.qml"

style:
   sidebarBackground:    "$COLOR_BG"
   sidebarText:          "#FFFFFF"
   sidebarTextSelect:    "$COLOR_ACCENT"
   sidebarTextHighlight: "$COLOR_ACCENT"
EOF
}

sync_assets() {
    if [[ -d "$SOURCE_ASSETS" ]]; then
        info "Syncing binary assets (Images/Icons)..."
        cp -v "$SOURCE_ASSETS"/*.{png,svg} "$BRAND_DIR/" 2>/dev/null || warn "No images found in $SOURCE_ASSETS"
    else
        warn "Source assets directory not found. UI might look broken!"
    fi
}

# =========================
# Pipeline Entry
# =========================
main() {
    [[ $EUID -eq 0 ]] || die "This script modifies RootFS and must be run as root."
    [[ -d "$ROOTFS_DIR" ]] || die "RootFS path '$ROOTFS_DIR' not found."

    log "--- Hyper Branding Engine Starting ---"
    
    setup_structure
    sync_assets
    inject_qml_logic
    inject_branding_desc
    
    # Final check: Calamares looks for branding.desc specifically.
    if [[ -f "$BRAND_DIR/branding.desc" ]]; then
        log "Success: Branding for '$BRAND_ID' injected into $CALAMARES_DIR"
    else
        die "Pipeline finished but branding.desc is missing."
    fi
}

main "$@"
