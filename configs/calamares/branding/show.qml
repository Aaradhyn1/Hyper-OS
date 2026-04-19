import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: presentation
    width: 800
    height: 480
    color: "#0f0f0f"

    property int currentIndex: 0

    VisualItemModel {
        id: slideModel

        SlideItem {
            title: "Hyper OS"
            desc: "Next-gen performance with BIOS and UEFI support."
            iconSource: "qrc:/assets/cpu.svg"
        }
        SlideItem {
            title: "Instant Deployment"
            desc: "Direct SquashFS imaging for lightning-fast installation."
            iconSource: "qrc:/assets/flash.svg"
        }
        SlideItem {
            title: "Kernel Optimized"
            desc: "Custom Zen-tuned headers for maximum throughput."
            iconSource: "qrc:/assets/settings.svg"
        }
    }

    Timer {
        id: slideTimer
        interval: 8000
        running: true
        repeat: true
        onTriggered: {
            presentation.currentIndex = (presentation.currentIndex + 1) % slideModel.count
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1a1a2e" }
            GradientStop { position: 1.0; color: "#0f0f0f" }
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: presentation.currentIndex

        Repeater {
            model: slideModel
            delegate: Item {
                opacity: index === presentation.currentIndex ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 600 } }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width * 0.6
                    spacing: 20

                    Image {
                        source: model.iconSource
                        fillMode: Image.PreserveAspectFit
                        Layout.alignment: Qt.AlignHCenter
                        width: 80
                        height: 80
                    }

                    Text {
                        text: model.title
                        color: "white"
                        font.pixelSize: 28
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: model.desc
                        color: "#bbbbbb"
                        font.pixelSize: 16
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

        Repeater {
            model: slideModel.count
            Rectangle {
                width: 40
                height: 4
                radius: 2
                color: index === presentation.currentIndex ? "#3498db" : "#333"

                Rectangle {
                    width: index === presentation.currentIndex ? parent.width : 0
                    height: parent.height
                    color: "#ffffff"
                    visible: index === presentation.currentIndex

                    PropertyAnimation on width {
                        from: 0
                        to: 40
                        duration: slideTimer.interval
                        running: index === presentation.currentIndex && slideTimer.running
                    }
                }
            }
        }
    }
}
