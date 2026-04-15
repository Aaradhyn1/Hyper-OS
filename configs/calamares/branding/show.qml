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
        text: qsTr("Use Calamares to install Hyper OS to disk with BIOS or UEFI boot support.")
    }

    Slide {
        title: qsTr("Fast Live to Installed Transition")
        text: qsTr("The installer copies the live SquashFS system, configures GRUB, and prepares a standalone installation.")
    }
}
