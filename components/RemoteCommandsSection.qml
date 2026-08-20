pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
    id: root

    required property var panel

    width: parent ? parent.width : 0
    spacing: Style.space(6)
    visible: !!(panel && panel.device && panel.device.paired && panel.device.reachable && panel.device.capabilities && panel.device.capabilities.commands && (!panel.getSetting || panel.getSetting("showRemoteCommands", true)))

    readonly property var bar: panel ? panel.bar : null
    readonly property var service: panel ? panel.service : null
    readonly property var device: panel ? panel.device : null
    readonly property color foreground: bar ? bar.foreground : "#ffffff"
    readonly property string fontFamily: bar ? bar.fontFamily : "sans-serif"

    PanelSeparator { foreground: root.foreground }

    Row {
        width: parent.width
        spacing: Style.space(6)
        CursorSurface {
            width: Math.max(1, parent.width - (panel.commandsExpanded ? refreshCmdBtn.implicitWidth + Style.space(6) : 0))
            implicitHeight: headerRow.implicitHeight + Style.space(4)
            hasCursor: panel.cursorActive && panel.focusSection === "commands" && !panel.commandsExpanded
            foreground: root.foreground
            fill: Style.hoverFillFor(root.foreground, Color.accent)
            currentFill: Style.selectedFillFor(root.foreground, Color.accent)
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    panel.cursorActive = true
                    panel.focusSection = "commands"
                }
                onClicked: panel.toggleCommandsExpanded()
            }
            Row {
                id: headerRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)
                Text {
                    text: panel.commandsExpanded ? "󰅀" : "󰅂"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                }
                PanelSectionHeader {
                    text: "REMOTE COMMANDS"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
        Button {
            id: refreshCmdBtn
            visible: panel.commandsExpanded
            iconText: "󰑐"
            tooltipText: "Refresh commands"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !root.service || !root.service.commandsLoading
            onClicked: if (root.service && root.device) root.service.fetchRemoteCommands(root.device.id)
        }
    }

    Column {
        visible: panel.commandsExpanded
        width: parent.width
        spacing: Style.space(6)
        Text {
            visible: !!root.service && root.service.commandsLoading
            text: "Loading commands..."
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }
        Text {
            visible: !!root.service && !root.service.commandsLoading && root.service.remoteCommands.length === 0
            text: "No remote commands configured"
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }
        Repeater {
            model: root.service ? root.service.remoteCommands : []
            delegate: CursorSurface {
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: cmdRow.implicitHeight + Style.space(8)
                hasCursor: panel.cursorActive && panel.focusSection === "commands" && panel.commandsExpanded && panel.commandSelectedIndex === index
                foreground: root.foreground
                fill: Style.hoverFillFor(root.foreground, Color.accent)
                currentFill: Style.selectedFillFor(root.foreground, Color.accent)
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: {
                        panel.cursorActive = true
                        panel.focusSection = "commands"
                        panel.commandSelectedIndex = index
                    }
                    onClicked: if (root.service && root.device) root.service.executeRemoteCommand(root.device.id, modelData.key)
                }
                Row {
                    id: cmdRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                        text: "󰘳"
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: cmdBtnText
                        text: modelData.name
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                        width: Math.max(1, parent.width - Style.space(20))
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
