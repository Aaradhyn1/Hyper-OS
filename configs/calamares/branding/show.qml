import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: presentation
    width: 800
    height: 480
    color: "#0B0F14"

    property int currentIndex: 0

    readonly property var slides: [
        { title: "Hyper OS", desc: "Fast. Focused. Game Ready." },
        { title: "Auto Driver Setup", desc: "GPU detection and Vulkan stack provisioning at first boot." },
        { title: "Gaming Orchestration", desc: "Per-game profiles for governor, priority, and compatibility flags." }
    ]

    Timer {
        interval: 7000
        running: true
        repeat: true
        onTriggered: presentation.currentIndex = (presentation.currentIndex + 1) % slides.length
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.7
        spacing: 16

        Text {
            text: slides[presentation.currentIndex].title
            color: "#E6EDF7"
            font.pixelSize: 34
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 120
            height: 3
            color: "#29D3FF"
        }

        Text {
            text: slides[presentation.currentIndex].desc
            color: "#9BB0C8"
            font.pixelSize: 18
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }
    }
}
