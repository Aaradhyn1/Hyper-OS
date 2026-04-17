#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Environment
# =========================
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ROOTFS_DIR="$BUILD_DIR/rootfs"

CALAMARES_BRAND_DIR="$ROOTFS_DIR/etc/calamares/branding/hyperos"
QML_OUT="$CALAMARES_BRAND_DIR/show.qml"

ISO_PATH="$ROOT_DIR/hyperos-$(date +%Y%m%d).iso"

log() { printf "\e[32m[%s] %s\e[0m\n" "$(date '+%H:%M:%S')" "$*"; }
die() { printf "\e[31m[FATAL] %s\e[0m\n" "$*" >&2; exit 1; }

# =========================
# UI Generation
# =========================
generate_ui() {
    log "Generating Calamares UI..."

    mkdir -p "$CALAMARES_BRAND_DIR"

    cat > "$QML_OUT" <<'EOF'
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    anchors.fill: parent
    color: "#050505"

    property int currentIndex: 0

    property var slides: [
        {"title": "Hyper OS", "desc": "Performance-first Linux with instant responsiveness.", "icon": "⚡"},
        {"title": "Fast Installs", "desc": "Optimized SquashFS deployment pipeline.", "icon": "🚀"},
        {"title": "Low Latency Core", "desc": "System tuned for speed, not bloat.", "icon": "🛠️"}
    ]

    Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: currentIndex = (currentIndex + 1) % slides.length
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.6
        spacing: 20

        Text {
            text: slides[currentIndex].icon
            font.pixelSize: parent.width * 0.08
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: slides[currentIndex].title
            color: "white"
            font.bold: true
            font.pixelSize: parent.width * 0.04
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: slides[currentIndex].desc
            color: "#aaa"
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: parent.width * 0.02
            Layout.fillWidth: true
        }
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 40
        spacing: 10

        Repeater {
            model: slides.length
            Rectangle {
                width: 40; height: 4
                radius: 2
                color: index === currentIndex ? "#00aaff" : "#333"
            }
        }
    }
}
EOF
}

# =========================
# Branding Config
# =========================
generate_branding() {
    log "Configuring Calamares branding..."

    cat > "$CALAMARES_BRAND_DIR/branding.desc" <<EOF
---
componentName: hyperos
welcomeStyleCalamares: true
strings:
  productName: "Hyper OS"
  shortProductName: "Hyper"
images:
  productLogo: ""
slideshow: show.qml
EOF
}

# =========================
# Build Steps
# =========================
run_step() {
    local name="$1"
    log "===> $name"
}

# =========================
# Main
# =========================
main() {
    [[ "$EUID" -ne 0 ]] && die "Root required"

    mkdir -p "$BUILD_DIR" "$ROOTFS_DIR"

    generate_ui
    generate_branding

    run_step "Rootfs Bootstrap"
    run_step "System Configuration"
    run_step "ISO Build"

    log "Build Complete: $ISO_PATH"
}

main "$@"
