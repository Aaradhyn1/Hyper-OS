import QtQuick 2.7

Presentation {
    id: presentation

    Timer {
        interval: 24000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        title: qsTr("Welcome to Hyper OS")
        text: qsTr("Speed, Focus, Victory. Install Hyper OS with BIOS and UEFI support in a minimal flow.")
    }

    Slide {
        title: qsTr("Gaming-Ready by Default")
        text: qsTr("Hyper OS includes Steam, Lutris, Wine-Staging, GameMode, and profile-based optimizations out of the box.")
    }

    Slide {
        title: qsTr("Minimal, Fast, Cohesive")
        text: qsTr("From boot to desktop, Hyper OS uses a consistent low-overhead design focused on clarity and performance.")
    }
}
