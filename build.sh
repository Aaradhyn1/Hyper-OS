#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[HYPER-BRANDING] ERROR at line $LINENO"; exit 1' ERR

# =========================
# Environment
# =========================
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ROOTFS_DIR="$BUILD_DIR/rootfs"

CALAMARES_DIR="$ROOTFS_DIR/etc/calamares"
CALAMARES_BRAND_DIR="$CALAMARES_DIR/branding/hyperos"
QML_OUT="$CALAMARES_BRAND_DIR/show.qml"

log() { printf "\e[36m[HYPER-UI]\e[0m %s\n" "$*"; }
die() { printf "\e[31m[FATAL]\e[0m %s\n" "$*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Run as root."
}

require_rootfs() {
    [[ -d "$ROOTFS_DIR" ]] || die "RootFS not found → run build first"
}

# =========================
# UI Generation
# =========================
generate_ui() {
    log "Generating QML slideshow..."

    install -d "$CALAMARES_BRAND_DIR"

    cat > "$QML_OUT" <<'EOF'
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    anchors.fill: parent
    color: "#050505"

    property int idx: 0
    property var slides: [
        { "t": "Hyper OS", "d": "Performance-first Linux.", "i": "⚡" },
        { "t": "Fast Installs", "d": "Zstd SquashFS pipeline.", "i": "🚀" },
        { "t": "Low Latency", "d": "Tuned kernel & stack.", "i": "🛠️" }
    ]

    Timer {
        interval: 7000
        running: true
        repeat: true
        onTriggered: idx = (idx + 1) % slides.length
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.6
        spacing: 16

        Text {
            text: slides[idx].i
            font.pixelSize: parent.width * 0.07
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: slides[idx].t
            color: "white"
            font.bold: true
            font.pixelSize: parent.width * 0.035
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: slides[idx].d
            color: "#aaa"
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: parent.width * 0.018
            Layout.fillWidth: true
        }
    }
}
EOF
}

# =========================
# Branding Config
# =========================
generate_branding() {
    log "Writing branding.desc..."

    cat > "$CALAMARES_BRAND_DIR/branding.desc" <<'EOF'
---
componentName: hyperos
welcomeStyleCalamares: true
strings:
  productName: "Hyper OS"
  shortProductName: "Hyper"
slideshow: show.qml
EOF
}

# =========================
# Validation
# =========================
validate_output() {
    log "Validating branding..."

    [[ -f "$QML_OUT" ]] || die "QML not generated"
    [[ -f "$CALAMARES_BRAND_DIR/branding.desc" ]] || die "branding.desc missing"

    grep -q "slideshow: show.qml" "$CALAMARES_BRAND_DIR/branding.desc" \
        || die "Branding misconfigured"

    log "Branding OK"
}

# =========================
# Main
# =========================
main() {
    require_root
    require_rootfs

    generate_ui
    generate_branding
    validate_output

    log "Calamares branding injected successfully."
}

main "$@"
