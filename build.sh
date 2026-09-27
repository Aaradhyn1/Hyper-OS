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
readonly SOURCE_ASSETS="$ROOT_DIR/assets/branding"

# --- UI Styling Constants ---
readonly COLOR_BG="#0a0a0a"
readonly COLOR_TEXT_PRIMARY="#ffffff"
readonly COLOR_TEXT_MUTED="#888888"
readonly COLOR_ACCENT="#00f2ff"

# =========================
# Utilities
# =========================
log()  { printf "\e[34m[CORE]\e[0m %s\n" "$*"; }
info() { printf "\e[36m[INFO]\e[0m %s\n" "$*"; }
warn() { printf "\e[33m[WARN]\e[0m %s\n" "$*"; }
die()  { printf "\e[31m[FATAL]\e[0m %s\n" "$*" >&2; exit 1; }

# =========================
# Core Logic
# =========================

setup_structure() {
    info "Initializing branding directory structural hierarchy..."
    mkdir -p "$BRAND_DIR/lang"
}

sync_assets() {
    if [[ -d "$SOURCE_ASSETS" ]]; then
        info "Syncing binary vector and raster assets..."
        # Safely expand matching extensions using find to prevent globbing crashes
        find "$SOURCE_ASSETS" -maxdepth 1 -type f \( -name "*.png" -o -name "*.svg" \) -exec cp -t "$BRAND_DIR/" {} +
    else
        warn "Source assets directory missing at $SOURCE_ASSETS. Deploying fallback placeholders..."
        # Prevent Calamares crash due to missing critical images
        touch "$BRAND_DIR/logo.png" "$BRAND_DIR/icon.png" "$BRAND_DIR/welcome.png"
    fi
}

inject_qml_logic() {
    info "Generating reactive QML Slideshow with smooth cross-fades..."
    
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

    Rectangle {
        anchors.fill: parent
        opacity: 0.08
        gradient: Gradient {
            GradientStop { position: 0.0; color: "$COLOR_ACCENT" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Timer {
        interval: 8000; running: true; repeat: true
        onTriggered: {
            slideOut.start()
        }
    }

    SequentialAnimation {
        id: slideOut
        NumberAnimation { target: mainLayout; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InOutQuad }
        ScriptAction {
            script: root.currentSlide = (root.currentSlide + 1) % root.content.length
        }
        NumberAnimation { target: mainLayout; property: "opacity"; to: 1; duration: 400; easing.type: Easing.InOutQuad }
    }

    ColumnLayout {
        id: mainLayout
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: 30
        opacity: 1

        Image {
            source: root.content[root.currentSlide].img
            Layout.preferredWidth: 128
            Layout.preferredHeight: 128
            Layout.alignment: Qt.AlignHCenter
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            
            Text {
                text: root.content[root.currentSlide].title
                color: "$COLOR_TEXT_PRIMARY"
                font.pixelSize: 26
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }

            Text {
                text: root.content[root.currentSlide].desc
                color: "$COLOR_TEXT_MUTED"
                font.pixelSize: 15
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                renderType: Text.NativeRendering
            }
        }
    }
}
EOF
}

inject_branding_desc() {
    info "Configuring descriptor layer: branding.desc..."

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
   sidebarText:          "$COLOR_TEXT_PRIMARY"
   sidebarTextSelect:    "$COLOR_ACCENT"
   sidebarTextHighlight: "$COLOR_ACCENT"
EOF

    # Validate output schema syntax if tools are present
    if command -v yamllint &> /dev/null; then
        yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "$BRAND_DIR/branding.desc" || die "YAML Syntax validation failed in branding.desc"
    fi
}

# =========================
# Pipeline Entry
# =========================
main() {
    [[ $EUID -eq 0 ]] || die "Privilege escalation required. Please run this script execution as root."
    [[ -d "$ROOTFS_DIR" ]] || die "Target RootFS target workspace path '$ROOTFS_DIR' does not exist."

    log "--- Hyper Branding Engine Deployment Initialized ---"
    
    setup_structure
    sync_assets
    inject_qml_logic
    inject_branding_desc
    
    log "Deployment verified. Branding successfully initialized for framework ID: $BRAND_ID"
}

main "$@"
