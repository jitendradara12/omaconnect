pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
    id: root

    required property var panel

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    readonly property var bar: panel ? panel.bar : null
    readonly property var device: panel ? panel.device : null
    readonly property string deviceName: panel ? panel.deviceName : "KDE Connect"
    readonly property color foreground: bar ? bar.foreground : "#ffffff"
    readonly property string fontFamily: bar ? bar.fontFamily : "sans-serif"

    property alias pingInput: pingInput
    property alias textInput: textInput

    Column {
        visible: panel.activeComposer === "ping" && !!root.device && root.device.paired && root.device.reachable && root.device.capabilities.ping
        width: parent.width
        spacing: Style.space(6)

        Text {
            text: "Ping " + root.deviceName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }

        Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
                id: pingInput
                width: Math.max(1, parent.width - sendPing.implicitWidth - cancelPing.implicitWidth - Style.space(12))
                placeholderText: "Ping message"
                placeholderTextColor: Qt.darker(root.foreground, 1.5)
                text: panel.draftPing
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                selectedTextColor: root.foreground

                background: Rectangle {
                    color: Style.hoverFillFor(root.foreground, Color.accent)
                    border.color: pingInput.activeFocus ? Color.accent : Qt.darker(root.foreground, 1.6)
                    border.width: 1
                    radius: Style.cornerRadius
                }

                onTextChanged: {
                    panel.draftPing = text
                    if (text.trim().length > 0) panel.composerError = ""
                }
                onAccepted: panel.submitPing()
                Keys.onEscapePressed: panel.closeComposer()
            }

            Button {
                id: sendPing
                text: "Send"
                selected: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: panel.submitPing()
            }

            Button {
                id: cancelPing
                text: "Cancel"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: panel.closeComposer()
            }
        }

        Text {
            visible: panel.activeComposer === "ping" && panel.composerError !== ""
            text: panel.composerError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
    }

    Column {
        visible: panel.activeComposer === "text" && !!root.device && root.device.paired && root.device.reachable && root.device.capabilities.text
        width: parent.width
        spacing: Style.space(6)

        Text {
            text: "Share text or link with " + root.deviceName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }

        Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
                id: textInput
                width: Math.max(1, parent.width - sendText.implicitWidth - cancelText.implicitWidth - Style.space(12))
                placeholderText: "Text or link"
                placeholderTextColor: Qt.darker(root.foreground, 1.5)
                text: panel.draftText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                selectedTextColor: root.foreground

                background: Rectangle {
                    color: Style.hoverFillFor(root.foreground, Color.accent)
                    border.color: textInput.activeFocus ? Color.accent : Qt.darker(root.foreground, 1.6)
                    border.width: 1
                    radius: Style.cornerRadius
                }

                onTextChanged: {
                    panel.draftText = text
                    if (text.trim().length > 0) panel.composerError = ""
                }
                onAccepted: panel.submitText()
                Keys.onEscapePressed: panel.closeComposer()
            }

            Button {
                id: sendText
                text: "Send"
                selected: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: panel.submitText()
            }

            Button {
                id: cancelText
                text: "Cancel"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: panel.closeComposer()
            }
        }

        Text {
            visible: panel.activeComposer === "text" && panel.composerError !== ""
            text: panel.composerError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }
    }
}
